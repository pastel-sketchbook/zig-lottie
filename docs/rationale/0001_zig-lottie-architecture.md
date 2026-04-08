# 0001: zig-lottie Architecture and Implementation Rationale

## Overview

zig-lottie is a Lottie animation compiler written in Zig. It parses
[Lottie JSON](https://lottiefiles.github.io/lottie-docs/) animation files and
compiles them to a rendering-ready in-memory representation. The library is
designed to be consumed from two targets simultaneously:

1. **Native CLI** -- a command-line tool for validating, inspecting, and
   compiling Lottie files.
2. **WebAssembly** -- a WASM module for use in browsers and other WASM runtimes.

Both targets share the same core code. This document explains how every part
of the Zig codebase works, why each decision was made, and how the pieces
connect.

---

## Table of Contents

1. [Build System (`build.zig` / `build.zig.zon`)](#1-build-system)
2. [Library Core (`src/root.zig`)](#2-library-core)
   - 2.1 [Lottie Type System](#21-lottie-type-system)
   - 2.2 [JSON Parser](#22-json-parser)
   - 2.3 [Memory Management](#23-memory-management)
   - 2.4 [WASM Exports](#24-wasm-exports)
   - 2.5 [Manual Number Formatting](#25-manual-number-formatting)
   - 2.6 [Tests](#26-tests)
3. [CLI Entry Point (`src/main.zig`)](#3-cli-entry-point)
4. [Dual-Target Strategy](#4-dual-target-strategy)
5. [Design Decisions and Trade-offs](#5-design-decisions-and-trade-offs)

---

## 1. Build System

### `build.zig.zon` -- Package Manifest

```zig
.{
    .name = .zig_lottie,
    .version = "0.1.0",
    .fingerprint = 0xa784e7e719150b39,
    .minimum_zig_version = "0.14.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
```

- **`.name = .zig_lottie`** -- Zig 0.15 package names are bare identifiers
  (no hyphens allowed). The identifier `zig_lottie` maps to the human-readable
  name "zig-lottie".
- **`.fingerprint`** -- A unique 64-bit value that distinguishes this package
  in the Zig package manager's content-addressed store.
- **`.paths`** -- Declares which paths are part of the package. Only
  `build.zig`, `build.zig.zon`, and the `src/` tree are included; everything
  else (web/, docs/, Taskfile.yml) is excluded from package distribution.

### `build.zig` -- Build Configuration

The build script defines **three build steps** using Zig 0.15's module-based
build API:

#### Step 1: Native CLI (`zig build`)

```zig
const lib_mod = b.addModule("zig-lottie", .{
    .root_source_file = b.path("src/root.zig"),
    .target = target,
    .optimize = optimize,
});

const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "zig-lottie", .module = lib_mod },
    },
});

const exe = b.addExecutable(.{
    .name = "zig-lottie",
    .root_module = exe_mod,
});
```

The key pattern: a **library module** (`lib_mod`) is created from `root.zig`,
then an **executable module** (`exe_mod`) is created from `main.zig` that
*imports* the library module under the name `"zig-lottie"`. This is why
`main.zig` can do `const lottie = @import("zig-lottie");`.

The Zig 0.15 API uses `root_module` instead of the older inline
`root_source_file` / `target` / `optimize` fields directly on
`addExecutable`. Modules are created first, then attached.

#### Step 2: WASM Library (`zig build wasm`)

```zig
const wasm_mod = b.createModule(.{
    .root_source_file = b.path("src/root.zig"),
    .target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    }),
    .optimize = .ReleaseSmall,
    .strip = true,
});

const wasm_lib = b.addExecutable(.{
    .name = "zig-lottie",
    .root_module = wasm_mod,
});
wasm_lib.entry = .disabled;
wasm_lib.rdynamic = true;
```

Key decisions:

- **`wasm32-freestanding`** -- No OS, no libc. The WASM module is a
  standalone binary that communicates with the host exclusively through
  exported functions.
- **`.optimize = .ReleaseSmall`** -- Aggressively optimizes for binary size.
  Critical for WASM where every kilobyte matters for download speed.
- **`.strip = true`** -- Removes DWARF debug info and WASM name sections.
  Reduces the raw `.wasm` file significantly (saves several KB).
- **`.entry = .disabled`** -- WASM libraries have no `_start`; the host calls
  exported functions directly.
- **`.rdynamic = true`** -- Ensures all `export fn` declarations in `root.zig`
  are emitted as WASM exports (not dead-code-eliminated).

The WASM artifact is installed to `zig-out/wasm/` (via a custom `dest_dir`),
which the Vite dev server in `web/` serves as a public directory.

#### Step 3: Tests (`zig build test`)

```zig
const lib_tests = b.addTest(.{ .root_module = lib_test_mod });
const exe_tests = b.addTest(.{ .root_module = exe_test_mod });
```

Both `root.zig` and `main.zig` are compiled and tested independently. The
test step depends on both, so `zig build test` runs the full suite.

---

## 2. Library Core

Everything in `src/root.zig` is the shared library consumed by both CLI and
WASM. It has four responsibilities:

1. Define Zig types that model the Lottie JSON schema.
2. Parse raw JSON bytes into those types.
3. Manage memory for all parsed data.
4. Export a WASM-compatible API.

### 2.1 Lottie Type System

The type system maps the [Lottie specification](https://lottiefiles.github.io/lottie-docs/)
into Zig structs and enums. The hierarchy is:

```
Animation
  +-- version_str: []const u8      (Lottie "v" field, e.g. "5.7.1")
  +-- frame_rate: f64              (Lottie "fr")
  +-- in_point / out_point: f64    (Lottie "ip" / "op")
  +-- width / height: u32          (Lottie "w" / "h")
  +-- name: ?[]const u8            (Lottie "nm", optional)
  +-- layers: []const Layer
        +-- ty: LayerType          (Lottie "ty", integer enum)
        +-- name: ?[]const u8      (Lottie "nm")
        +-- index / parent: ?i64   (Lottie "ind" / "parent")
        +-- in_point / out_point   (Lottie "ip" / "op")
        +-- transform: ?Transform  (Lottie "ks")
        +-- shapes: []const Shape  (Lottie "shapes", for shape layers ty=4)
```

#### Animated Properties

Lottie properties can be either static or animated. This is modeled with
tagged unions:

```zig
pub const AnimatedValue = union(enum) {
    static: f64,
    keyframed: []const Keyframe,
};

pub const AnimatedMulti = union(enum) {
    static: []const f64,
    keyframed: []const MultiKeyframe,
};
```

- **`AnimatedValue`** -- Scalar properties like rotation and opacity. Either a
  single `f64` or an array of `Keyframe` structs.
- **`AnimatedMulti`** -- Multi-dimensional properties like position (`[x,y,z]`)
  and scale (`[sx,sy,sz]`). Either a static slice of floats or an array of
  `MultiKeyframe` structs.

The distinction between `AnimatedValue` and `AnimatedMulti` exists because
Lottie uses different JSON structures for scalar vs. multi-dimensional
animated values. Scalar keyframes store a single `value: f64`, while
multi-dimensional keyframes store `values: []const f64`.

#### Keyframes

```zig
pub const Keyframe = struct {
    time: f64,          // Frame number ("t")
    value: f64,         // Scalar value ("s")
    ease_out: ?Vec2,    // Bezier out-handle ("o")
    ease_in: ?Vec2,     // Bezier in-handle ("i")
    hold: bool,         // Hold interpolation ("h")
};
```

Each keyframe has:
- A **time** (frame number) at which the value applies.
- The **value** at that frame.
- Optional **bezier easing handles** for smooth interpolation. `Vec2` is
  `[2]f64` representing `[x, y]` control points for a cubic bezier curve.
- A **hold** flag -- when true, the value snaps instantly to the next keyframe
  with no interpolation (like a step function).

#### Transform

```zig
pub const Transform = struct {
    anchor: ?AnimatedMulti,     // "a" -- anchor point
    position: ?AnimatedMulti,   // "p" -- position
    scale: ?AnimatedMulti,      // "s" -- scale (percentage, 100 = 1x)
    rotation: ?AnimatedValue,   // "r" -- rotation in degrees
    opacity: ?AnimatedValue,    // "o" -- opacity 0-100
};
```

Every field is optional because Lottie JSON omits fields that use default
values. The transform appears in two contexts:
1. **Layer-level** (`ks` field) -- applies to the entire layer.
2. **Shape-level** (`ty: "tr"` inside a group's `it` array) -- applies to a
   shape group.

#### Shapes

```zig
pub const Shape = struct {
    ty: ShapeType,
    name: ?[]const u8,
    items: []const Shape,        // Sub-shapes (for groups)
    size: ?AnimatedMulti,        // Rectangle/ellipse size
    position: ?AnimatedMulti,    // Rectangle/ellipse position
    roundness: ?AnimatedValue,   // Rectangle corner roundness
    color: ?AnimatedMulti,       // Fill/stroke color [r,g,b,a]
    opacity: ?AnimatedValue,     // Fill/stroke opacity
    stroke_width: ?AnimatedValue,// Stroke width
    transform: ?Transform,       // Shape-level transform (ty="tr")
};
```

The `Shape` struct uses a **flat union of all possible fields** rather than a
tagged union per shape type. This is a deliberate trade-off:

- **Pro**: Simpler parser code. Each field is independently optional; the
  parser just checks which JSON keys are present and populates accordingly.
- **Pro**: Easier to extend. Adding a new shape type only requires adding
  fields, not restructuring the union.
- **Con**: Wastes some memory per shape (unused fields are `null`). Acceptable
  because shape trees are typically small (tens to hundreds of shapes).

Shapes form a **tree structure** through the `items` field. A group shape
(`ty: .group`) contains child shapes in `items`, which can themselves be
groups. This mirrors the Lottie JSON structure where `"gr"` shapes have an
`"it"` (items) array.

#### Layer Types and Shape Types

```zig
pub const LayerType = enum(u8) {
    precomp = 0, solid = 1, image = 2, null_object = 3,
    shape = 4, text = 5, audio = 6, ...
    _,  // non-exhaustive: allows unknown integer values
};

pub const ShapeType = enum {
    group, rectangle, ellipse, path, fill, stroke, transform,
    gradient_fill, gradient_stroke, merge, trim, round_corners,
    repeater, star, unknown,
};
```

`LayerType` is a **non-exhaustive integer enum** (`_`) because the Lottie spec
defines types by integer, and future versions may add new ones. Unknown values
don't crash the parser -- they just produce a valid enum with an unnamed value.

`ShapeType` is a regular enum with an explicit `unknown` variant because shape
types are identified by two-character strings (`"gr"`, `"rc"`, etc.) and the
mapping is done by `shapeTypeFromStr()`.

### 2.2 JSON Parser

The parser converts raw JSON bytes into the type system described above.

#### Entry Point: `parse()`

```zig
pub fn parse(allocator: Allocator, json_buf: []const u8) ParseError!Animation
```

The function:

1. **Parses JSON into a generic tree** using `std.json.parseFromSlice`. This
   gives a `std.json.Value` tree (dynamic JSON: objects, arrays, numbers,
   strings).
2. **Extracts required top-level fields** (`v`, `fr`, `ip`, `op`, `w`, `h`).
   Any missing required field returns `ParseError.MissingRequiredField`.
3. **Duplicates all strings** from the JSON tree before `parsed.deinit()` frees
   it. This is critical -- `std.json.parseFromSlice` returns string slices that
   point into the parsed tree's memory. Once `parsed.deinit()` is called, those
   pointers become dangling. Every string must be `allocator.dupe(u8, s)`'d.
4. **Parses layers** via `parseLayers()`.
5. **Returns an `Animation`** that owns all its memory.

#### Error Handling with `errdefer`

The parser makes extensive use of Zig's `errdefer` for exception-safe resource
management:

```zig
const version_str = allocator.dupe(u8, s) catch return ParseError.OutOfMemory;
errdefer allocator.free(version_str);

const anim_name = ...;
errdefer if (anim_name) |n| allocator.free(n);

const layers = try parseLayers(allocator, layers_val);
errdefer { /* free all layers */ }

return Animation{ ... };  // success: errdefers don't run
```

Each allocation is immediately followed by an `errdefer` that frees it. If any
subsequent operation fails, all previously allocated resources are freed in
reverse order. If the function succeeds (reaches `return Animation{...}`),
none of the `errdefer` blocks run, and ownership transfers to the caller.

This pattern is applied consistently at every level of the parse tree:
`parseLayers`, `parseShapes`, `parseSingleShape`, `parseTransform`,
`parseAnimatedScalar`, `parseAnimatedMulti`.

#### Layer Parsing: `parseLayers()`

```zig
fn parseLayers(allocator: Allocator, layers_val: ?std.json.Value) ParseError![]Layer
```

- If `layers_val` is `null` (the `"layers"` key is absent), returns an
  empty slice. This makes the parser tolerant of incomplete files.
- Otherwise, iterates the JSON array and builds a `std.ArrayList(Layer)`.
- For each layer object, extracts `ty`, `nm`, `ind`, `parent`, `ip`, `op`.
- Parses the `ks` field (transform) and `shapes` field (shape tree).
- Converts the type integer to `LayerType` via `@enumFromInt` with clamping
  to 0-255 to prevent undefined behavior.
- Finalizes with `toOwnedSlice()` to transfer ArrayList memory to a regular
  slice owned by the caller.

#### Shape Parsing: `parseShapes()` / `parseSingleShape()`

Shape parsing is recursive because shapes can nest (groups contain items):

```
parseShapes(allocator, json_array)
  -> for each item: parseSingleShape(allocator, json_object)
       -> if group: parseShapes(allocator, "it" array)  // recurse
```

`parseSingleShape` parses all fields that *might* be present regardless of
shape type. For example, it always checks for `"s"` (size), `"p"` (position),
`"c"` (color), etc. If a field isn't present, the corresponding struct field
is `null`. This simplifies the code: no need for a type-specific switch
statement in the parser.

Special case: **`ty: "tr"` (transform shapes)** -- these appear as the last
item in a group's `"it"` array and encode a group-level transform. The parser
calls `parseTransformFromShapeFields()` which reads `a`, `p`, `s`, `r`, `o`
directly from the shape object (not from a nested `"ks"` object as with layer
transforms).

#### Animated Property Parsing

The Lottie format encodes animated properties as:

```json
{
  "a": 0,        // 0 = static, 1 = animated
  "k": <value>   // number/array (static) or array of keyframe objects (animated)
}
```

`parseAnimatedScalar()` and `parseAnimatedMulti()` check the `"a"` flag:

- **Static (`a: 0`)**: Extract the value from `"k"`. For scalars, `k` may be
  a number or a single-element array like `[100]`. For multi-dimensional, `k`
  is an array of numbers like `[256, 256, 0]`.
- **Animated (`a: 1`)**: `k` is an array of keyframe objects. Each keyframe
  has `t` (time), `s` (start value), `o` (ease out), `i` (ease in), `h` (hold).

#### Bezier Easing Handles

```zig
fn parseEaseHandle(val: ?std.json.Value) ?Vec2
```

Lottie easing handles are objects like `{ "x": [0.33], "y": [0] }` or
`{ "x": 0.33, "y": 0 }`. The `x` and `y` values can be either a bare number
or a single-element array. `easeComponent()` handles both cases by trying
`jsonFloat()` first, then checking for an array.

#### JSON Helper Functions

Four small helpers abstract over `std.json.Value` variants:

- **`jsonFloat(val)`** -- Extracts `f64` from a JSON `.float` or `.integer`.
  Integers are coerced to float via `@floatFromInt`. This is necessary because
  Lottie JSON uses both `30` and `30.0` interchangeably.
- **`jsonInt(val)`** -- Extracts `i64` from a JSON `.integer`.
- **`jsonUint(T, val)`** -- Extracts an unsigned integer, returning `null` for
  negative values.
- **`jsonFloatArray(allocator, arr)`** -- Converts a JSON array of numbers to
  an `[]f64` slice, defaulting non-numeric values to `0`.

### 2.3 Memory Management

#### Ownership Model

The `Animation` struct **owns all memory** it references. The caller is
responsible for calling `anim.deinit()` when done. This follows Zig's
convention of explicit ownership.

`deinit()` walks the entire tree and frees everything:

```zig
pub fn deinit(self: *const Animation) void {
    for (self.layers) |layer| {
        freeShapes(self.allocator, layer.shapes);
        freeTransform(self.allocator, layer.transform);
        if (layer.name) |n| self.allocator.free(n);
    }
    self.allocator.free(self.layers);
    if (self.name) |n| self.allocator.free(n);
    self.allocator.free(self.version_str);
}
```

#### Recursive Free Helpers

The free helpers mirror the recursive structure of the data:

- **`freeShapes(allocator, shapes)`** -- Iterates shapes, recursively frees
  sub-shapes (`items`), all animated properties, optional names, then frees
  the shapes slice itself.
- **`freeTransform(allocator, transform)`** -- Frees all five animated
  properties (anchor, position, scale, rotation, opacity).
- **`freeAnimatedValue(allocator, av)`** -- For keyframed values, frees the
  keyframe slice. Static values have no heap allocation.
- **`freeAnimatedMulti(allocator, am)`** -- For static values, frees the
  `[]const f64` slice. For keyframed values, frees each keyframe's `values`
  slice, then frees the keyframe slice.

This is the most delicate part of the codebase. Every allocation made during
parsing has a corresponding free in exactly one of these helpers. Missing a
free causes a memory leak; double-freeing causes undefined behavior. The tests
run under Zig's `testing.allocator` (which is a `GeneralPurposeAllocator` in
debug mode) that detects both leaks and use-after-free.

#### Why `std.json.parseFromSlice` Requires String Duplication

`std.json.parseFromSlice` returns a parsed tree whose string values are slices
pointing into the *parsed tree's internal buffer*. When `parsed.deinit()` is
called, that buffer is freed. Any string slice that wasn't duplicated becomes
a dangling pointer.

This was discovered empirically as a segfault when accessing `anim.name` or
`layer.name` after the parsed tree was freed. The fix: every string extracted
from the JSON tree is immediately `allocator.dupe(u8, s)`'d.

### 2.4 WASM Exports

The bottom section of `root.zig` defines functions with the `export` keyword
that become WASM exports:

#### Target Detection

```zig
const is_wasm = builtin.cpu.arch.isWasm();
const wasm_allocator = if (is_wasm)
    std.heap.wasm_allocator
else
    std.heap.page_allocator;
```

At **compile time**, Zig evaluates `builtin.cpu.arch.isWasm()`:
- WASM build: uses `std.heap.wasm_allocator` (calls `memory.grow` to expand
  WASM linear memory).
- Native build: uses `std.heap.page_allocator` (calls OS-level `mmap`/`VirtualAlloc`).

This comptime branching means the same source file works for both targets
with zero runtime overhead.

#### Exported Functions

| Export | Purpose |
| :--- | :--- |
| `lottie_version()` | Returns pointer to version string |
| `lottie_version_len()` | Returns length of version string |
| `lottie_alloc(len)` | Allocates a buffer in WASM linear memory |
| `lottie_free(ptr, len)` | Frees a previously allocated buffer |
| `lottie_parse(ptr, len)` | Parses Lottie JSON, returns JSON result string |
| `lottie_result_len(ptr)` | Scans for the length of a null-terminated result |

The **WASM calling convention** works as follows:

1. **Host (JS) calls `lottie_alloc(n)`** to get a pointer to `n` bytes in
   WASM memory.
2. **Host writes JSON bytes** into that buffer via the WASM memory view.
3. **Host calls `lottie_parse(ptr, len)`** which parses the JSON and returns
   a pointer to a new buffer containing a JSON result string.
4. **Host reads the result** from WASM memory. The result is a JSON object
   like `{"ok":true,"version":"5.7.1","frame_rate":30,...}`.
5. **Host calls `lottie_free(ptr, len)`** to free both the input and result
   buffers.

This is a standard pattern for passing variable-length data across the
WASM boundary, where only integers and floats can be passed as function
arguments.

#### `lottie_parse()` -- The Core WASM Export

```zig
export fn lottie_parse(ptr: [*]const u8, len: u32) ?[*]u8 {
    const json_buf = ptr[0..len];
    const anim = parse(wasm_allocator, json_buf) catch return null;
    defer anim.deinit();
    // Build JSON result string...
}
```

This function:
1. Slices the raw pointer into a Zig slice.
2. Calls the same `parse()` function used by the CLI.
3. Builds a JSON result string using manual formatting (see next section).
4. Returns the pointer to the result, or `null` on error.

The result includes animation metadata plus a `layers` array summarizing each
layer (type, name, shape count, whether it has a transform). This gives the
host enough information to render or display the animation without needing
to re-query individual fields.

#### `lottie_result_len()` -- Length Discovery

Because WASM can only return numeric values (no way to return a pointer+length
pair in a single return value), the host needs a way to determine the result
length. `lottie_result_len` scans forward from the pointer looking for a null
byte (the allocator zero-initializes memory, so bytes after the JSON string
are `0`). This is a pragmatic hack -- a cleaner approach would be to return
the length separately, but this works within the constraint of single-return
WASM functions.

### 2.5 Manual Number Formatting

The WASM export builds its JSON result string using manual integer and float
formatting instead of `std.fmt`:

```zig
fn writeU32(w: anytype, v: u32) !void { ... }
fn writeUsize(w: anytype, v: usize) !void { ... }
fn writeF64(w: anytype, v: f64) !void { ... }
```

**Why**: Using `writer.print("{d}", .{some_f64})` pulls in Zig's full
float-to-decimal conversion machinery (Dragonbox algorithm + Ryu lookup
tables), which adds approximately **5.5 KB** to the WASM binary. For a library
targeting ~78 KB raw size, this is significant.

The manual `writeF64` function:
1. Handles the sign.
2. Splits the float into integer and fractional parts via `@intFromFloat`.
3. Scales the fraction to 4 decimal places (i.e., multiply by 10000 and round).
4. Writes the integer part digit-by-digit.
5. Writes the fractional part, trimming trailing zeros.

This is less precise than Dragonbox (4 decimal places max, no scientific
notation) but perfectly adequate for Lottie values (frame numbers, dimensions,
percentages) which rarely need more precision.

`writeU32` and `writeUsize` use the same digit-extraction loop but for
unsigned integers, avoiding even `std.fmt.formatInt`.

### 2.6 Tests

The test suite (22 tests, all inline in `root.zig`) validates the parser
against increasingly complex Lottie JSON inputs. Tests use
`testing.allocator`, which in debug mode is a `GeneralPurposeAllocator` that
detects memory leaks and use-after-free.

The tests are organized by feature area:

| Test | What it validates |
| :--- | :--- |
| `version is semver` | Library version string has two dots |
| `parse valid minimal lottie json` | Minimal valid input with all required fields |
| `parse rejects invalid json` | Garbage input returns `InvalidJson` |
| `parse rejects json missing required fields` | Missing `fr`/`ip`/`op`/`w`/`h` returns `MissingRequiredField` |
| `parse animation with name` | Optional `nm` field is captured |
| `parse animation with layers` | Layer array parsing, layer fields (ty, nm, ind, parent, ip, op) |
| `animation duration calculation` | `(out_point - in_point) / frame_rate` math |
| `parse layer types` | Integer-to-enum mapping for precomp, solid, image, shape, text |
| `parse rejects layer missing ty` | Layer without `ty` field returns error |
| `parse animation without layers field` | Missing `layers` key returns empty array (tolerant) |
| `parse layer with static transform` | Static anchor/position/scale/rotation/opacity |
| `parse animated scalar property with keyframes` | Opacity with 3 keyframes, bezier easing handles |
| `parse animated multi-dimensional property with keyframes` | Position with 2 keyframes, multi-value arrays |
| `parse shape layer with rectangle` | Rectangle size, position, roundness |
| `parse shape layer with ellipse` | Ellipse size and position |
| `parse shape layer with fill` | Fill color [r,g,b,a] and opacity |
| `parse shape layer with stroke` | Stroke color, opacity, and width |
| `parse shape group with nested items` | Group with items: rect + fill + transform, recursive parse |
| `parse shape path type` | Path shape (`ty: "sh"`) recognized |
| `parse hold keyframe` | Hold flag (`h: 1`) on keyframes |
| `shapeTypeFromStr maps all known types` | All 14 shape type strings map correctly |
| `parse rejects shape missing ty` | Shape without `ty` returns error |

Every test that successfully parses an animation calls `defer anim.deinit()`,
ensuring the `GeneralPurposeAllocator` can verify no memory was leaked.

---

## 3. CLI Entry Point

`src/main.zig` implements the command-line interface. It imports the library
via `const lottie = @import("zig-lottie");`.

### I/O Pattern (Zig 0.15)

```zig
var stdout_buf: [4096]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
const stdout = &stdout_writer.interface;
defer stdout.flush() catch {};
```

Zig 0.15 changed the I/O API:
- `std.io.getStdOut()` no longer exists.
- `std.fs.File.stdout()` returns a `File`.
- `.writer(&buf)` creates a buffered writer backed by a stack buffer.
- `.interface` gives the `std.Io.Writer` interface (vtable-based).
- `defer stdout.flush()` ensures all buffered output is flushed on exit.

Both stdout and stderr use this pattern with separate 4 KB buffers.

### Subcommands

| Command | Behavior |
| :--- | :--- |
| `version` | Prints `zig-lottie 0.1.0` |
| `inspect <file>` | Parses a Lottie file and prints metadata |
| `help` | Prints usage information |
| (none) | Prints usage information |
| (unknown) | Prints error + usage, exits with code 1 |

### `inspect` Subcommand

`inspectFile()` demonstrates the full parse pipeline:

1. Opens the file from the path argument.
2. Reads entire contents into memory (up to 64 MB limit).
3. Calls `lottie.parse()`.
4. Prints a formatted summary: file path, version, frame rate, duration,
   frame range, dimensions, name, layer count.
5. For each layer: prints type, name, index, transform presence, shape count.
6. For each layer's shapes: recursively prints the shape tree with indentation
   via `printShapes()`.

`shapeTypeName()` converts `ShapeType` enum values to human-readable strings
for display.

### Error Handling

The CLI uses a pattern of `catch |err|` with explicit error messages and
`std.process.exit(1)` rather than propagating errors to `main`'s return type.
This provides user-friendly error messages instead of Zig's default error
trace.

---

## 4. Dual-Target Strategy

The same `root.zig` compiles to both native and WASM with zero `#ifdef`-style
conditionals. The key mechanisms:

| Concern | How it's resolved |
| :--- | :--- |
| **Allocator selection** | `comptime` check on `builtin.cpu.arch.isWasm()` |
| **Entry point** | CLI uses `main.zig`; WASM uses `export fn` in `root.zig` |
| **File I/O** | CLI reads files via `std.fs`; WASM receives data via `lottie_alloc` + `lottie_parse` |
| **Output** | CLI writes to stdout; WASM returns JSON string pointer |
| **Optimization** | CLI uses user-selected optimization; WASM always uses `ReleaseSmall` |

The `export fn` declarations in `root.zig` are compiled for both targets but
are only meaningful for WASM (where `rdynamic = true` exports them). In the
native build, they're simply unused functions that the linker dead-code
eliminates.

---

## 5. Design Decisions and Trade-offs

### Why `std.json` (dynamic parsing) instead of `std.json.parseFromValue` (typed)?

Zig's `std.json` can parse directly into Zig structs (compile-time reflection
on struct fields). However, Lottie JSON has many optional fields, inconsistent
types (numbers vs single-element arrays), and nested structures that don't map
cleanly to Zig structs. Parsing to `std.json.Value` first, then manually
extracting fields, provides:
- Fine-grained error handling per field.
- Tolerance for format variations (e.g., `k: 100` vs `k: [100]`).
- Clear mapping from Lottie spec field names (`"v"`, `"fr"`, `"ks"`) to Zig
  field names.

### Why flat `Shape` struct instead of tagged union per type?

A tagged union like `Shape = union(enum) { rectangle: RectData, fill: FillData, ... }`
would be type-safer but harder to parse (needs a switch on the type *before*
deciding which fields to extract) and harder to extend. The flat struct with
optional fields is simpler and matches how the JSON is actually structured.

### Why `[]const` slices instead of `ArrayList`?

After parsing, the data is immutable. `ArrayList` is used during parsing
(dynamic growth), then `toOwnedSlice()` converts to a plain `[]const` slice.
This makes the parsed `Animation` safe to share across threads (all data is
read-only) and reduces the per-element overhead (no ArrayList metadata).

### Why manual number formatting in WASM?

The ~5.5 KB savings from avoiding `std.fmt` float formatting is a 7% reduction
in the 78 KB WASM binary. For a library that's downloaded on every page load,
this matters. The trade-off (4 decimal places max) is acceptable for Lottie's
domain where values are frame counts, pixel coordinates, and percentages.

### Why `lottie_result_len` scans for null instead of returning length?

WASM functions can only return a single value. To return both a pointer and a
length, you'd need either:
- A two-value return (not supported in WASM MVP).
- Writing the length to a known memory location.
- Using the null-scanning approach.

The null-scan approach was chosen for simplicity. The allocator provides
zero-initialized memory beyond the written JSON, so scanning for a null byte
reliably finds the end. The 1 MB scan limit prevents infinite loops on
corrupted data.

### Why `ParseError` is a distinct error set?

```zig
pub const ParseError = error{
    InvalidJson, MissingRequiredField, UnsupportedVersion, OutOfMemory,
};
```

Using a named error set (instead of Zig's inferred error sets with `!`) makes
the API explicit about what can go wrong. Callers can switch on specific errors
and provide appropriate user-facing messages. `OutOfMemory` is included because
allocation failures during parsing are mapped to this error rather than
propagating `Allocator.Error` directly.

### Why store `allocator` in `Animation`?

The `Animation` struct stores the allocator it was created with so that
`deinit()` can free all owned memory without the caller needing to pass the
allocator again. This follows the Zig standard library convention (e.g.,
`std.ArrayList` in older versions stored the allocator, though 0.15 moved to
allocator-per-call). Since `Animation` is the top-level owner of a complete
parse tree, storing the allocator simplifies the API: `anim.deinit()` is all
the caller needs.
