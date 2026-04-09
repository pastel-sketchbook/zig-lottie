# zig-lottie

A [Lottie](https://lottiefiles.github.io/lottie-docs/) animation compiler
written in Zig. Parses Lottie JSON files, validates them, and renders
animations — in the terminal or in the browser via WebAssembly.

> **⚠️ This is a learning project, not production software.** It exists to
> explore what it takes to compile the Lottie format from scratch — parsing
> the JSON schema, resolving keyframe interpolation, rasterizing vector shapes,
> and wiring it all up for both native and WASM targets. Use it to learn from,
> not to depend on.

## Features

- **Parse** — Reads Lottie JSON into typed Zig structs (layers, shapes,
  transforms, keyframes).
- **Validate** — Checks for semantic issues (missing fields, out-of-range
  values, version warnings).
- **Inspect** — Prints animation metadata, layer tree, shape summary, and
  keyframe counts.
- **Render** — Rasterizes and plays animations directly in the terminal using
  the [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/).
- **Compile** — Resolves all keyframes at every frame to produce a
  rendering-ready snapshot (used by both CLI render and WASM).
- **WASM** — Compiles to `wasm32-freestanding` for use in browsers.

## Requirements

- [Zig](https://ziglang.org/) ≥ 0.15.2
- [Task](https://taskfile.dev/) (optional, for convenience commands)
- [Bun](https://bun.sh/) (optional, for the web test app)

## Quick Start

```sh
# Build the CLI
zig build

# Run tests
zig build test

# Inspect a Lottie file
zig build run -- inspect test/fixtures/kitchen_sink.json

# Validate a Lottie file
zig build run -- validate test/fixtures/kitchen_sink.json

# Render an animation in the terminal (requires Kitty-compatible terminal)
zig build run -- render test/fixtures/kitchen_sink.json

# Render a single frame with options
zig build run -- render test/fixtures/kitchen_sink.json --frame 0 --width 400 --bg 1a1a2e

# Build the WASM library
zig build wasm
# Output: zig-out/wasm/zig-lottie.wasm
```

## CLI Usage

```
Usage: zig-lottie <command> [args]

Commands:
  version              Print version
  inspect <file>       Parse and display Lottie animation info
  validate <file>      Validate a Lottie file for semantic correctness
  render <file> [opts] Render animation in terminal (Kitty graphics)
  help                 Show this help

Render options:
  --width <N>          Output width in pixels (default: anim width, max 800)
  --height <N>         Output height in pixels (default: proportional)
  --frame <N>          Render a single frame number
  --loops <N>          Number of loops (0 = infinite, default: 1)
  --bg <RRGGBB>        Background color in hex (default: transparent)
```

## Project Structure

```
zig-lottie/
├── src/
│   ├── root.zig        # Library core: types, parser, validator, compiler, WASM exports
│   ├── main.zig        # CLI entry point and subcommands
│   ├── rasterizer.zig  # Software rasterizer (pixel buffer, shapes, transforms)
│   ├── terminal.zig    # Terminal renderer (frame loop, sizing, Kitty output)
│   └── kitty.zig       # Kitty graphics protocol encoder
├── test/
│   ├── fixtures/       # Lottie JSON test fixtures
│   └── wasm-harness.html
├── web/                # Browser test app (Vite + TypeScript)
├── docs/
│   └── rationale/      # Architecture and design decision documents
├── build.zig           # Build system: native CLI + WASM targets
├── build.zig.zon       # Package metadata
├── Taskfile.yml        # Task runner for dev ergonomics
└── VERSION             # Single source of truth for version
```

## Dual-Target Architecture

The same core library (`root.zig`) compiles to both native and WASM:

| | Native CLI | WASM |
| :--- | :--- | :--- |
| Entry point | `main.zig` | Exported functions in `root.zig` |
| File I/O | `std.fs` | Host-provided buffers |
| Memory | `std.heap.page_allocator` | `std.heap.wasm_allocator` |
| Output | stdout (Kitty protocol) | Return buffers to host |

Rendering modules (`rasterizer.zig`, `terminal.zig`, `kitty.zig`) are
CLI-only and not included in the WASM build.

## Task Runner

If you have [Task](https://taskfile.dev/) installed:

```sh
task build      # Build the CLI
task test       # Run all tests
task fmt        # Format code
task check      # Format check + tests (CI-friendly)
task wasm       # Build WASM library
task render     # Render kitchen_sink.json in terminal
task web:dev    # Build WASM + start Vite dev server
task clean      # Remove build artifacts
```

## Web Test App

```sh
task web:dev    # Start dev server at http://localhost:3000
task web:build  # Production build
task web:run    # Preview production build
```

The web app loads the WASM module and renders Lottie animations on a canvas,
providing a browser-based test harness alongside the CLI.

## Test Fixtures

Four hand-crafted Lottie files in `test/fixtures/` exercise specific parser
and renderer features:

| Fixture | Purpose |
| :--- | :--- |
| `many_layers.json` | Layer count, type variety, parent-child relationships |
| `many_keyframes.json` | Keyframe interpolation (linear, bezier, hold) |
| `deep_nesting.json` | Deeply nested shape groups |
| `kitchen_sink.json` | All features combined |

## Dependencies

**Zero external dependencies.** The library uses only the Zig standard library
(`std.json`, `std.mem`, `std.fs`, `std.heap`). The web test app uses Vite and
TypeScript (managed via Bun).

## License

[MIT](LICENSE)