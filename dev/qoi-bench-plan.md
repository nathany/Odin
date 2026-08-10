# QOI decode-performance project — plan for a fresh session

**Goal:** find out how much decode throughput Odin's `core:image/qoi` is leaving on the
table, and whether porting Blend2D's scalar tricks is worth it. Decode is the target
(runtime asset loading for games); encode is a nice-to-have for an asset pipeline.

**Non-goals:** tiling / format changes (QOIR-style). Staying bit-compatible with the
QOI spec is a hard constraint — concurrency comes from loading multiple files in
parallel, not from splitting one file.

**Compression ratio is explicitly out of scope.** Investigated and set aside: QOI+xz
beats PNG by 10–47% depending on content, and in-format variants like QOIPond buy ratio
by adding decode complexity (function-pointer opcode dispatch). Neither is worth it
here — file size isn't on the critical path, level-load time is. If this ever comes
back, the only lever that doesn't cost decode speed is post-compressing the QOI stream
with LZ4/zstd, which composes cleanly with everything below and can be bolted on later.
See the conversation notes for references.

---

## Setup

New empty Odin project, *not* in the Odin repo. Vendor a copy of the upstream codec so
all three variants sit side by side:

```
qoi-bench/
  bench/main.odin           # harness
  variants/
    v0_upstream/            # verbatim copy of Odin core/image/qoi
    v1_safe/                # v0 + low-risk fixes, still bounds-safe
    v2_blend2d/             # structural port
  corpus/                   # .qoi test images (gitignored)
  reference/                # phoboslab qoi.h, built as a C baseline
```

Copy the upstream source from `Odin/core/image/qoi/qoi.odin` (375 lines) — it depends on
`core:image`, `core:compress`, `core:bytes`. For a standalone benchmark it's probably
cleaner to strip the `core:image` dependency and make each variant a self-contained
`decode(data: []u8) -> ([]u8, int, int, Error)`. Do that surgery **once**, on v0, and
verify it still round-trips before deriving v1/v2 from it.

---

## Baselines to measure

1. **v0** — Odin upstream, as-is.
2. **v0-nofs** — v0 with *only* `@(optimization_mode="favor_size")` removed
   (`qoi.odin:172`). This is a one-line change and might be most of the gap. Measure it
   separately before anything else; if it's a big win it's also the easiest upstream PR.
3. **ref** — phoboslab `qoi.h` compiled with the same clang/opt level, via Odin's
   `foreign` import. This is the number everyone else's blog posts are relative to.
4. **v1** — safe micro-optimizations (below).
5. **v2** — Blend2D-style port.

---

## v1: safe optimizations

These keep the current structure and stay memory-safe. Expected: modest but free.

- **Run fill** (`qoi.odin:296`). Currently a per-pixel `copy(pixels, pix[:channels])`
  loop. Blend2D fills `u32` at a time (`fillRgba32`). For the 4-channel case this can be
  a `u32` fill; consider `slice.fill` or an explicit widened loop.
- **Encoder bounds checks**. The encode loop has no `#no_bounds_check` even though
  `max_size` is pre-computed at `qoi.odin:53` to be worst-case-sufficient. The decoder
  *does* use it on its writes. Asymmetric — but only touch this if you can convince
  yourself the size calc is airtight (it is: 4 bytes/px for RGB, 5 for RGBA).
- **Hoist the channel branch.** `img.channels` is loop-invariant but tested every
  iteration in both loops. Two specialized loops (`when`/parametric on channel count)
  removes it. This is also a prerequisite for v2.
- **Avoid re-reading `seen[]` on INDEX.** Minor.

Keep bounds checking on all *input* reads. The decoder reads attacker-controlled data;
`#no_bounds_check` belongs only on writes into buffers we sized ourselves.

---

## v2: the Blend2D port

Source: `blend2d/codec/qoicodec.cpp` (991 lines) —
https://github.com/blend2d/blend2d/blob/master/blend2d/codec/qoicodec.cpp
Blog writeup: https://blend2d.com/blog/qoi-image-codec.html

Four distinct ideas, in rough order of expected payoff. Port and measure them
**one at a time** — the blog reports 28–49% total, but doesn't break it down per trick.

### (a) Decode to a fixed 32-bit pixel, always

This is the structural change everything else depends on, and it's the one the blog
underplays. Blend2D's decode loop always writes `u32` RGBA — `*dst_ptr = packed_pixel;
++dst_ptr`. Odin writes `img.channels` bytes per pixel via `copy()`, so every store is a
variable-length memcpy. Uniform `u32` stores make the run-fill, the index store, and the
literal store all one instruction.

Cost: 3-channel images decode to 4-channel output. For game asset loading that's
almost certainly what you want anyway (GPU upload wants RGBA), but it's a behaviour
change vs. upstream, so it can't land in core as-is without an option.

### (b) The unpacked-pixel representation

`UnpackedPixel` (qoicodec.cpp:112) holds the pixel as `0x00AA00GG00RR00BB` in a `u64`,
so R/G/B/A each get 16 bits of headroom. DIFF/LUMA deltas then become a **single 64-bit
add** with no per-channel masking, followed by one `& 0x00FF00FF00FF00FFu`. Odin
currently does `pix += {diff_r, diff_g, diff_b, 0}` on a `[4]u8` — which is fine, but
the unpacked form is what makes the LUT trick (d) work.

Odin has `#simd` types and native `u64`; the u64 path is the one to use (Blend2D's
32-bit fallback split into `ag`/`rb` is only for 32-bit targets — skip it).

### (c) The multiply-shift hash

```c
static BL_INLINE uint32_t hashPixelAGxRBx64(uint64_t ag_rb) noexcept {
  ag_rb *= (uint64_t(kQoiHashA) << ( 8 + 2)) + (uint64_t(kQoiHashG) << (24 + 2)) +
           (uint64_t(kQoiHashR) << (40 + 2)) + (uint64_t(kQoiHashB) << (56 + 2)) ;
  return uint32_t(ag_rb >> 58);
}
```

One multiply + one shift, replacing Odin's four 16-bit multiplies and three adds
(`qoi.odin:363`). Operates directly on the unpacked form from (b).

**Verify this exhaustively before trusting it.** It must reproduce
`(3r + 5g + 7b + 11a) & 63` for all 2^32 pixel values. That's a cheap brute-force test
(a few seconds, parallelizable) and it's the kind of thing that silently corrupts one
image in ten thousand if it's subtly wrong. Write that test *first*.

### (d) The 129-entry DIFF/LUMA lookup table

`IndexDiffLumaTableGen` at qoicodec.cpp:57. Indices 0–63 encode DIFF deltas, 64–127
encode LUMA first-byte deltas, entry 128 is a zero sentinel so the table can be indexed
without a bounds branch. Each entry packs `r,g,b` deltas plus a `luma_mask` in the low
byte:

```c
static constexpr uint32_t luma(uint32_t b0) noexcept {
  return rgb(b0 - 40u, b0 - 32u, b0 - 40u, 0xFF);
}
```

The decode side (qoicodec.cpp:316) then handles DIFF and LUMA in one branchless path —
`src += hbyte0 >> 7` advances by 1 or 2 bytes depending on which op it was, and the
`luma_mask` selects whether the second byte contributes. Odin currently has two separate
`case` arms with shifts and subtractions.

Odin has compile-time execution, so generate the table with a `when`-block or an
`@(init)` proc rather than hand-writing 129 constants.

### (e) Branchless RGB/RGBA

```c
BL_INLINE void opRGBX(uint32_t hbyte0, const UnpackedPixel& other) noexcept {
  uint64_t msk = uint64_t(hbyte0 + 1) << 48;
  ag_rb = (ag_rb & msk) | (other.ag_rb & ~msk);
}
```

`hbyte0` is 0xFE (RGB) or 0xFF (RGBA); `+1` gives 0xFF or 0x100, and `<< 48` puts either
0 or a set bit in the alpha lane — so alpha is taken from the *previous* pixel for RGB
and from the *stream* for RGBA, with no branch. Advance is `src += hbyte0 - 251` (3 or
4). Cute, and worth measuring: the blog credits much of the win to branch-misprediction
reduction, and RGB/RGBA literals are the least predictable ops in the stream.

### Also worth stealing: the paired-INDEX peek

qoicodec.cpp:293 speculatively reads `hbyte1` and, if it's *also* an INDEX op, decodes
two pixels in one iteration. Cheap ILP win since INDEX ops cluster.

---

## Benchmark harness

- **Corpus:** the official suite from https://qoiformat.org/benchmark/
  (`qoi_benchmark_suite.tar`, ~1.3 GB — images, textures, screenshots, photos). Don't
  benchmark on one image; QOI's op mix varies enormously by content and the whole point
  is that game textures/screenshots are the favourable case. At minimum split results by
  the suite's own categories.
- **Also add your own:** a handful of actual karl2d-style sprite sheets and tilemaps.
  Those are the workload you care about, and they're likely more run/index-heavy than
  the photo-dominated public suite.
- **Method:** decode-only timing, warm cache, N iterations, report **median** and
  min — not mean. Preload the file into memory first so you're not measuring I/O.
  Report MP/s (megapixels/sec), which is how the QOI world quotes numbers and makes
  cross-image comparison meaningful.
- **Correctness gate:** every variant must produce byte-identical output to v0 on the
  entire corpus, checked before any timing run is reported. Wire this as a hard
  assertion in the harness, not a separate step you might forget.
- Test on both arm64 (your Mac) and x86-64 if you can — the multiply-shift hash and the
  u64 unpacked representation have different costs on each, and your players are on
  Windows/x86.

---

## Suggested order

1. Standalone v0 + correctness harness + corpus. Get a number.
2. Flip off `favor_size`. Get a number. (Possibly the whole story.)
3. C reference via `foreign`. Now you know where you stand vs. the world.
4. v1 safe fixes. Get a number.
5. v2 incrementally: (a) → (c)+exhaustive hash test → (d) → (e) → paired-index.
   Number after each.
6. Decide what's worth upstreaming. `favor_size` and the run-fill are easy PRs
   regardless of how v2 turns out.

---

## Open question for step 6

The v2 decoder is a different shape from upstream's (fixed RGBA32 output, no
`core:compress` streaming context). If it wins big, the upstream conversation is
probably "add a fast path for the common case" rather than "replace the decoder" —
worth deciding early whether you're building a PR or your own package.

---

## References

- Odin upstream: `core/image/qoi/qoi.odin`, decoder at `:173`, hash at `:363`
- QOI spec: https://qoiformat.org/qoi-specification.pdf
- Reference impl: https://github.com/phoboslab/qoi
- Blend2D codec: https://github.com/blend2d/blend2d/blob/master/blend2d/codec/qoicodec.cpp
- Blend2D writeup: https://blend2d.com/blog/qoi-image-codec.html
- Benchmark suite: https://qoiformat.org/benchmark/
