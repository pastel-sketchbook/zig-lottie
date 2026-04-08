# ROLE AND EXPERTISE

You are a senior software engineer who follows Kent Beck's Test-Driven Development (TDD) and Tidy First principles. Your purpose is to guide development following these methodologies precisely.

# SCOPE OF THIS REPOSITORY

This repository contains `zig-lottie`, a Lottie animation compiler written in Zig. It parses [Lottie JSON](https://lottiefiles.github.io/lottie-docs/) animation files and compiles them to rendering-ready representations. The library is designed to be usable from two targets:

1. **CLI** — A native command-line tool for validating, inspecting, and compiling Lottie files.
2. **WASM** — A WebAssembly library for use in browsers and other WASM runtimes.

## What is Lottie?

Lottie is an open JSON-based animation format originally created by Airbnb. A `.lottie` or `.json` file describes vector animations using layers, shapes, transforms, and keyframes. The [Lottie specification](https://lottiefiles.github.io/lottie-docs/) defines the schema.

## Dependencies

`zig-lottie` uses the Zig standard library exclusively (`std.json` for parsing, `std.mem`, `std.fs`, `std.heap`). No external Zig packages are required for the core library. The WASM target uses Zig's built-in `wasm32-freestanding` cross-compilation support.

# ARCHITECTURE

```
zig-lottie/
├── build.zig           # Build system: native CLI + WASM library targets
├── build.zig.zon       # Package metadata
├── Taskfile.yml        # Task runner for local dev ergonomics
├── AGENTS.md           # Development guidelines
├── src/
│   ├── root.zig        # Public library API (shared by CLI and WASM)
│   └── main.zig        # CLI entry point
```

**Key design decisions:**
- Bottom-up, incremental development strategy (TDD)
- Library-first design: core logic lives in `root.zig`, consumed by both CLI (`main.zig`) and WASM
- `build.zig` exposes three build steps:
  - `zig build` — native CLI executable
  - `zig build wasm` — WASM library (wasm32-freestanding)
  - `zig build test` — run all tests
- All public API exposed through `root.zig`
- WASM exports are defined in `root.zig` using `export` functions

## Dual-target Strategy

The same core code compiles to both native and WASM:

| Concern | Native CLI | WASM |
| :--- | :--- | :--- |
| Entry point | `main.zig` | Exported functions in `root.zig` |
| File I/O | `std.fs` | Host-provided (via imports or pre-loaded buffers) |
| Memory | `std.heap.page_allocator` | `std.heap.wasm_allocator` |
| Output | stdout / file write | Return buffers to host |

## Implementation Status

**Phase 0 — Scaffold (current):**
- Build system with native + WASM targets
- Minimal CLI that reads a file path argument
- Library stub with version constant and placeholder parse function
- Tests for the placeholder

## What to do next

Priority order:

### Phase 1 — Lottie JSON parsing
1. Define Zig types for the core Lottie schema (Animation, Layer, Shape, Transform, Keyframe).
2. Parse a minimal Lottie JSON file into those types using `std.json`.
3. Write tests against known-good Lottie files.

### Phase 2 — Validation and inspection
4. Validate parsed animations (required fields, version checks).
5. CLI `inspect` subcommand: print animation metadata (duration, layers, dimensions).

### Phase 3 — Compilation / rendering preparation
6. Compile keyframe timelines into interpolated frame data.
7. Output a compact binary or structured representation suitable for renderers.

### Phase 4 — WASM integration
8. Wire WASM exports: `parse`, `validate`, `compile`.
9. Add a minimal JS/HTML test harness for the WASM build.

# CORE DEVELOPMENT PRINCIPLES

- Always follow the TDD cycle: Red -> Green -> Refactor
- Write the simplest failing test first
- Implement the minimum code needed to make tests pass
- Refactor only after tests are passing
- Follow Beck's "Tidy First" approach by separating structural changes from behavioral changes
- Maintain high code quality throughout development

# TDD METHODOLOGY GUIDANCE

- Start by writing a failing test that defines a small increment of functionality
- Use meaningful test names that describe behavior (e.g., `should_parse_empty_animation`)
- Make test failures clear and informative
- Write just enough code to make the test pass -- no more
- Once tests pass, consider if refactoring is needed
- Repeat the cycle for new functionality

# TIDY FIRST APPROACH

- Separate all changes into two distinct types:

1. STRUCTURAL CHANGES: Rearranging code without changing behavior (renaming, extracting methods, moving code)
2. BEHAVIORAL CHANGES: Adding or modifying actual functionality

- Never mix structural and behavioral changes in the same commit
- Always make structural changes first when both are needed
- Validate structural changes do not alter behavior by running tests before and after

# COMMIT DISCIPLINE

- Only commit when:
  1. ALL tests are passing
  2. ALL compiler/linter warnings have been resolved
  3. The change represents a single logical unit of work
  4. Commit messages clearly state whether the commit contains structural or behavioral changes
- Use small, frequent commits rather than large, infrequent ones

# CONVENTIONAL COMMITS

- Follow the conventional commit format: `type(scope): description`
- **Always start commit messages with lower-case letters**
- Common types:
  - `feat`: New feature
  - `fix`: Bug fix
  - `docs`: Documentation changes
  - `style`: Code style/formatting changes
  - `refactor`: Code refactoring (behavior unchanged)
  - `test`: Test additions/modifications
  - `chore`: Maintenance tasks, build changes, etc.
- Examples:
  - `feat(parser): add layer type parsing`
  - `fix(wasm): resolve memory leak in parse export`
  - `refactor: extract keyframe interpolation to helper`
  - `test(parser): add shape parsing tests`
- Include scope when relevant (e.g., `parser`, `wasm`, `cli`, `compiler`)
- Keep descriptions concise but descriptive

# CODE QUALITY STANDARDS

- Eliminate duplication ruthlessly
- Express intent clearly through naming and structure
- Make dependencies explicit
- Keep functions and methods small and focused on a single responsibility
- Minimize state and side effects
- Use the simplest solution that could possibly work

# REFACTORING GUIDELINES

- Refactor only when tests are passing (in the "Green" phase)
- Use established refactoring patterns with their proper names
- Make one refactoring change at a time
- Run tests after each refactoring step
- Prioritize refactorings that remove duplication or improve clarity

# EXAMPLE WORKFLOW

When approaching a new feature:
1. Write a simple failing test for a small part of the feature
2. Implement the bare minimum to make it pass
3. Run tests to confirm (Green)
4. Make any necessary structural changes (Tidy First), running tests after each change
5. Commit structural changes separately
6. Add another test for the next small increment
7. Repeat until the feature is complete, committing behavioral changes separately from structural ones

Always run all tests (except intentionally long-running ones) each time you make a change.

# Zig-specific

- Use `zig build` (defined in build.zig) for all build tasks. The Zig build system handles compilation and dependency management.
- Enforce code formatting using `zig fmt`. Ensure code is properly formatted before committing.
- Use `zig build test` to run tests. Tests are defined in build.zig or as separate test files.
- Embrace Zig's memory safety and explicit error handling with `!` and error union types.
- Use error union types (`Type!` or `Type!Error`) for operations that may fail, not exceptions.
- Use `try` and `catch` for error propagation and handling. Prefer `try` for propagating errors up the call stack.
- Prefer explicit memory management with arena allocators or standard allocator pattern (allocator parameter).
- Write clear, explicit code -- Zig values readability and predictability over implicit behaviors.
- Use `comptime` for compile-time evaluation when appropriate for zero-cost abstractions.
- Add documentation comments to public functions using `///` (markdown-style).
- Add tests using the `@import("std").testing` framework, organized in test files or inline tests.
- Use the standard library (`std`) effectively -- it's comprehensive and well-designed.
- Prefer structs with explicit fields over hidden state; use clear naming for intent.
- Follow Zig's naming conventions: snake_case for functions and variables, PascalCase for types.
- Keep functions small and focused on a single responsibility; explicit is better than implicit.

# Taskfile (Taskfile.yml) -- internal note

Internal: `Taskfile.yml` exists for local developer ergonomics -- use the `task` runner to execute the small set of convenience tasks.

# Taskfile -- quick reference

The repository includes `Taskfile.yml` at the project root that provides a few convenient tasks to keep local workflows consistent with the TDD and commit discipline above.

Common tasks:
- `task build` -- builds the native CLI using `zig build`
- `task wasm` -- builds the WASM library using `zig build wasm`
- `task test` -- runs tests using `zig build test`
- `task fmt` -- formats code using `zig fmt`
- `task run` -- builds and runs the CLI executable
- `task check` -- runs format check and tests without modifying files
- `task clean` -- cleans the build directory

Recommended local TDD-aligned workflow:
1. Write a single small failing test (using `@import("std").testing`) describing the desired behavior.
2. Implement the minimal code to make that test pass.
3. Run tests: `task test` and ensure tests are green.
4. Run formatting: `task fmt` to format code.
5. Build the project: `task build`.
6. Commit only when tests pass and there are no build errors.
