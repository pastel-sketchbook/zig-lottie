# 0003: CLI Render Feature

## Overview

The `render` subcommand adds real-time Lottie animation playback directly in
the terminal. It rasterizes Lottie vector shapes into an RGBA pixel buffer and
streams frames to the terminal using the **Kitty graphics protocol** — no
external renderer, browser, or GUI toolkit required.

This document explains the architecture of the render pipeline, the design
decisions behind each layer, and the trade-offs involved.

---

## Table of Contents

1. [Motivation](#1-motivation)
2. [Architecture](#2-architecture)
3. [Module Responsibilities](#3-module-responsibilities)
   - 3.1 [CLI Entry (`main.zig` — `renderFile`)](#31-cli-entry)
   - 3.2 [Terminal Renderer (`terminal.zig`)](#32-terminal-renderer)
   - 3.3 [Rasterizer (`rasterizer.zig`)](#33-rasterizer)
   - 3.4 [Kitty Protocol (`kitty.zig`)](#34-kitty-protocol)
4. [Rendering Pipeline](#4-rendering-pipeline)
5. [Key Design Decisions](#5-key-design-decisions)
   - 5.1 [Kitty Over Sixel or Block Characters](#51-kitty-over-sixel-or-block-characters)
   - 5.2 [Wall-Clock Animation Loop](#52-wall-clock-animation-loop)
   - 5.3 [Software Rasterizer](#53-software-rasterizer)
   - 5.4 [No Heap Allocation for Base64 Encoding](#54-no-heap-allocation-for-base64-encoding)
   - 5.5 [Inverse-Transform Ellipse Testing](#55-inverse-transform-ellipse-testing)
   - 5.6 [Parent-Chain Transform Resolution](#56-parent-chain-transform-resolution)
   - 5.7 [Two-Pass Group Rendering](#57-two-pass-group-rendering)
   - 5.8 [Terminal Size Detection](#58-terminal-size-detection)
   - 5.9 [Buffered I/O with Explicit Flushes](#59-buffered-io-with-explicit-flushes)
6. [CLI Options](#6-cli-options)
7. [Limitations and Future Work](#7-limitations-and-future-work)

---

## 1. Motivation

zig-lottie already had `inspect` and `validate` subcommands, plus a WASM
build with a web test harness. But the only way to *see* an animation was in
the browser. A terminal-native renderer closes the feedback loop for CLI-only
workflows: parse, validate, and preview without leaving the shell.

Choosing to output images directly in the terminal (rather than writing PNG
files or launching a window) keeps the tool zero-dependency and composable
with existing terminal workflows.

---

## 2. Architecture

The render feature is split across four modules, each with a single
responsibility. Data flows linearly from left to right:

```
main.zig          terminal.zig        rasterizer.zig      kitty.zig
──────────        ────────────        ──────────────      ─────────
CLI arg parse  →  Animation loop   →  Pixel raster    →  Kitty escape
  & config        frame timing        fill/blend          base64 stream
                  dimension calc      transform math
```

All modules are CLI-only; they are not included in the WASM build. The
`build.zig` file registers them as separate Zig modules imported only by the
`exe` target.

---

## 3. Module Responsibilities

### 3.1 CLI Entry (`main.zig` — `renderFile`)

`renderFile` (lines 229–315) is the glue between the CLI argument parser and
the terminal renderer. It:

1. Parses optional flags (`--width`, `--height`, `--frame`, `--loops`, `--bg`)
   with explicit error messages for each.
2. Loads and parses the Lottie file via the shared `loadAndParse` helper.
3. Flushes any prior buffered stdout before handing control to
   `terminal.render`, which writes escape sequences that must not be
   interleaved with buffered text.
4. Delegates to `terminal.render` with a `RenderConfig`.

The `parseHexColor` helper converts a bare `RRGGBB` string to an RGBA pixel,
keeping the CLI interface simple (no `#` prefix required).

### 3.2 Terminal Renderer (`terminal.zig`)

`terminal.zig` owns two concerns: **output sizing** and **frame timing**.

**Output sizing.** `defaultOutputWidth` tries three sources in priority order:

1. Explicit `--width` from the user.
2. Terminal pixel dimensions via `TIOCGWINSZ` ioctl.
3. A hard-coded 800 px cap.

Height is either explicit or derived from the aspect ratio. This ensures
images render at a reasonable size regardless of terminal configuration.

**Single-frame mode.** When `--frame` is set, `render` compiles one frame,
rasterizes it, encodes it, and returns. No cursor manipulation is needed.

**Animation mode.** A wall-clock `Timer` drives the loop. For each tick:

- Compute which frame index corresponds to the elapsed time.
- Skip frames already displayed (temporal decimation when the terminal or
  rasterizer can't keep up).
- Clear the pixel buffer, compile the frame, rasterize, and send via Kitty.
- Reposition the cursor to overwrite the previous frame in-place.

The cursor is hidden during playback and restored on exit via `defer`.

### 3.3 Rasterizer (`rasterizer.zig`)

The rasterizer is a minimal software renderer. It provides:

| Primitive | Function | Algorithm |
| :--- | :--- | :--- |
| Pixel buffer | `PixelBuffer` | RGBA flat array, source-over alpha blend |
| Rectangle | `fillRect` | Transformed bounding-box scan, cross-product winding test |
| Ellipse | `fillEllipse` | Inverse-transform to local space, ellipse equation test |
| Stroke rect | `strokeRect` | Four filled-rect edges |
| Frame render | `renderFrame` | Reverse-order layer iteration, parent-chain transform walk |
| Shape render | `renderShapes` | Two-pass: collect fill/stroke context, then draw geometry |

**Transform math.** A `Matrix` struct implements 2D affine transforms
(translate, scale, rotate, multiply, apply). `matrixFromTransform` converts
a `ResolvedTransform` into a matrix following the Lottie spec's transform
order: `translate(pos) * rotate(r) * scale(s) * translate(-anchor)`.

**Color conversion.** `colorToPixel` maps Lottie's 0–1 float RGBA + 0–100
opacity to a `[4]u8` pixel, clamping out-of-range values.

### 3.4 Kitty Protocol (`kitty.zig`)

`kitty.zig` implements the subset of the Kitty graphics protocol needed for
inline image display and animation:

- `encodeImage` — transmit + display (action `a=T`), chunked base64.
- `encodeImageReplace` — same but with an image ID for in-place replacement.
- `deleteImage` — remove an image by ID.
- Cursor helpers: `cursorUp`, `cursorHome`, `hideCursor`, `showCursor`.

The chunked encoder (`encodeImageChunked`) streams base64 in 4096-byte
segments, using only a stack-allocated buffer. Each chunk is wrapped in a
separate `ESC_G ... ST` sequence with the `m=0/1` continuation flag. This
avoids allocating a potentially multi-megabyte base64 string.

A standalone `base64Encode` function exists for ad-hoc use (it heap-allocates
via `page_allocator`), but the streaming path avoids it entirely.

---

## 4. Rendering Pipeline

For each frame the animation loop processes:

```
Animation.layers
  → compileFrame()          resolve keyframes at time t
  → ResolvedLayer[]         static snapshot of all layers
  → renderFrame()           for each visible layer (reverse order):
      → resolveLayerWorldTransform()
                             walk parent chain, compose matrices & opacity
      → renderShapes()       two-pass: 1) collect fill/stroke 2) draw geometry
          → fillRect()       scan transformed bounding box
          → fillEllipse()    inverse-transform + ellipse equation
          → blendPixel()     source-over compositing into PixelBuffer
  → encodeImageReplace()    base64 stream to terminal via Kitty protocol
```

---

## 5. Key Design Decisions

### 5.1 Kitty Over Sixel or Block Characters

**Decision:** Use the Kitty graphics protocol exclusively.

**Rationale:** Kitty supports true-color RGBA at pixel resolution, chunked
streaming, and in-place image replacement (essential for animation). Sixel is
limited to 256 colors and not universally faster. Unicode block characters
(e.g., `▄▀`) give at best 2× row resolution and cannot represent smooth
gradients. Kitty is supported by Kitty, WezTerm, Ghostty, and recent versions
of other modern terminals.

**Trade-off:** Terminals without Kitty support will see garbled escape
sequences. A future `--format` flag could add Sixel or iTerm2 support.

### 5.2 Wall-Clock Animation Loop

**Decision:** Use `std.time.Timer` to determine which frame to display rather
than sleeping a fixed interval between frames.

**Rationale:** Fixed-sleep loops drift because rasterization and encoding
take variable time. A wall-clock approach naturally drops frames when the
renderer falls behind, maintaining correct playback speed. The 1 ms poll
sleep in the inner loop keeps CPU usage low while providing sufficient
temporal resolution.

The render FPS is capped at 30 regardless of the animation's declared frame
rate, avoiding excessive terminal I/O for high-FPS sources.

### 5.3 Software Rasterizer

**Decision:** Implement rasterization entirely in Zig with no GPU or external
library.

**Rationale:** The target is terminal preview, not production rendering. A
software rasterizer keeps the build zero-dependency, works on all platforms
(including headless servers), and compiles to both native and potentially WASM.
The pixel-by-pixel scan with winding tests is simple and correct for the
supported shape set (rectangles, ellipses). Performance is adequate for
terminal-sized images (typically ≤ 800 px wide).

### 5.4 No Heap Allocation for Base64 Encoding

**Decision:** `encodeImageChunked` uses a fixed 4100-byte stack buffer.

**Rationale:** A 100×100 RGBA image is 40 KB raw / ~54 KB base64. At larger
sizes (800×600 = 1.9 MB raw) a single heap allocation for the full base64
output wastes memory and adds allocation failure paths. Chunked streaming
caps memory at one 4 KB stack buffer regardless of image size.

### 5.5 Inverse-Transform Ellipse Testing

**Decision:** `fillEllipse` computes the matrix inverse and tests each pixel
in local (pre-transform) space against the unit ellipse equation.

**Rationale:** Unlike rectangles (which use a cross-product winding test on
the 4 transformed corners), an ellipse cannot be decomposed into a simple
polygon test. Inverse-transforming each candidate pixel back to local space
and checking `(dx/rx)² + (dy/ry)² ≤ 1` is the standard approach. The matrix
inverse is computed once per ellipse, so the per-pixel cost is just a
multiply-and-compare.

### 5.6 Parent-Chain Transform Resolution

**Decision:** `resolveLayerWorldTransform` walks up the parent chain
(capped at depth 32) and composes transforms from root to leaf.

**Rationale:** Lottie layers form a parent-child hierarchy where each
child's transform is relative to its parent. Composing in root-to-leaf order
matches the spec's semantics: the canvas matrix is applied first, then each
ancestor's transform, then the layer's own. The depth cap of 32 guards
against malformed files with cyclic parent references.

### 5.7 Two-Pass Group Rendering

**Decision:** `renderShapes` makes two passes over a group's shape list:
first to collect fill/stroke context, then to draw geometry.

**Rationale:** In Lottie, a group's fill and stroke apply to all geometry
siblings within that group, but the fill/stroke shapes can appear after the
geometry in the JSON order. A single pass would miss forward-declared
fill/stroke. Two passes (scan context, then render) ensure geometry always
uses the correct paint regardless of declaration order.

### 5.8 Terminal Size Detection

**Decision:** Use `TIOCGWINSZ` ioctl on stdout to detect pixel dimensions.

**Rationale:** This is the standard POSIX mechanism for querying terminal
size. It returns both character and pixel dimensions. Pixel dimensions let
the renderer scale the image to fit the terminal without user intervention.
If the ioctl fails (stdout is piped, or the terminal doesn't report pixels),
the renderer falls back to the animation's native width capped at 800 px.

### 5.9 Buffered I/O with Explicit Flushes

**Decision:** `main.zig` creates buffered writers for stdout/stderr and
flushes stdout explicitly before and after rendering.

**Rationale:** Kitty escape sequences must arrive as complete chunks; partial
writes can confuse the terminal. Flushing before `terminal.render` ensures no
prior buffered text is interleaved. Flushing after ensures the final frame
reaches the terminal before the process exits. The 4096-byte buffer matches
the Kitty chunk size for alignment.

---

## 6. CLI Options

| Flag | Default | Purpose |
| :--- | :--- | :--- |
| `--width <N>` | Animation width (max 800 or terminal width) | Output width in pixels |
| `--height <N>` | Proportional to width | Output height in pixels |
| `--frame <N>` | Animate all frames | Render a single frame |
| `--loops <N>` | 1 | Loop count (0 = infinite) |
| `--bg <RRGGBB>` | Transparent (0,0,0,0) | Background color |

All flags are optional and positional after the file path. Unknown flags
produce an error and exit with code 1.

---

## 7. Limitations and Future Work

- **Kitty-only.** No fallback for terminals without Kitty graphics support.
  A `--format sixel|iterm2|kitty` flag would broaden compatibility.
- **No path rendering.** Bézier paths (`ty: "sh"`) are parsed but not
  rasterized. Adding a scanline fill or tessellation pass would unlock most
  real-world Lottie files.
- **No gradient support.** Gradient fills/strokes are parsed but skipped
  during rasterization. Linear and radial gradient interpolation would be the
  next rendering feature.
- **No text layers.** Text rendering requires font shaping, which is out of
  scope for a minimal rasterizer.
- **Approximate row estimation.** The cursor-up count uses `height / 20` as a
  rough approximation of terminal rows. Querying character cell height from
  `TIOCGWINSZ` would improve accuracy.
- **No anti-aliasing.** Shape edges are aliased (no sub-pixel sampling). A
  simple 2×2 or 4× SSAA pass would improve visual quality at the cost of
  rasterization time.
- **Unused `hw` variable.** `strokeRect` computes `hw = width / 2.0` but
  never uses it (suppressed with `_ = hw`). The edges are drawn as centered
  rects instead. This should be cleaned up.
