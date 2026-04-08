# 0002: Test Fixtures and Web Examples

## Overview

zig-lottie ships four hand-crafted Lottie JSON fixtures in `test/fixtures/`
plus six inline samples in `web/src/samples.ts`. Every fixture is a purpose-built
animation that stress-tests specific parser features while remaining visually
interesting in the web test app's canvas renderer.

This document explains what each fixture tests, why it is shaped the way it is,
and how the fixtures and inline samples form a graduated complexity ramp.

---

## Table of Contents

1. [Design Philosophy](#1-design-philosophy)
2. [Inline Samples (samples.ts)](#2-inline-samples)
3. [Fixture Files](#3-fixture-files)
   - 3.1 [Many Layers](#31-many-layers)
   - 3.2 [Many Keyframes](#32-many-keyframes)
   - 3.3 [Deep Nesting](#33-deep-nesting)
   - 3.4 [Kitchen Sink](#34-kitchen-sink)
4. [Pastel Color Palette](#4-pastel-color-palette)
5. [Integration Tests](#5-integration-tests)
6. [Web Serving](#6-web-serving)

---

## 1. Design Philosophy

Every test file must satisfy three constraints simultaneously:

1. **Parser coverage** -- exercise a specific parser feature at scale (wide
   layer arrays, deep group nesting, many keyframes, mixed layer/shape types).
2. **Visual interest** -- produce a recognizable, animated scene when rendered.
   Mechanically generated grids of identical shapes are unacceptable; each
   fixture should tell a visual story.
3. **Reasonable size** -- stay under ~500 KB with indent-2 formatting so the
   web editor remains responsive. The editor skips syntax highlighting above
   500 lines but still needs to handle scrolling and line numbering smoothly.

The inline samples in `samples.ts` serve a different purpose: they are small
(under 5 KB each), embedded directly in TypeScript as object literals, and
exercise one or two features each. Together, the six inline samples plus four
fixture files form a **complexity ramp**:

```
Static Circle           ->  minimal valid Lottie, zero animation
Bouncing Ball           ->  position keyframes, null layer
Pulsing Ring            ->  scale + opacity keyframes, stroke-only
Spinning Squares        ->  rotation keyframes, rounded rects
Color Morph             ->  animated fill color, animated stroke width
Solar System            ->  multi-layer scene, nested groups, mixed keyframe types
Many Layers (148K)      ->  50 layers, grid layout, varied shapes
Many Keyframes (247K)   ->  1100+ keyframes, bezier easing, orbital motion
Deep Nesting (414K)     ->  5-level recursive groups, animated at every level
Kitchen Sink (282K)     ->  all layer types, all shape types, all features
```

Each step introduces something the previous steps did not.

---

## 2. Inline Samples

The six inline samples live in `web/src/samples.ts` as plain JavaScript
objects. They are embedded rather than loaded from files because:

- They are small enough that the overhead is negligible.
- They load instantly with no async fetch.
- They are editable in the web editor -- the user sees the JSON source and
  can modify it to experiment.

### Static Circle

```
1 shape layer, 1 ellipse with static fill, no keyframes
```

The absolute minimum valid Lottie animation. Tests that the parser can handle
a file with zero animated properties. The renderer draws a single filled
ellipse at the canvas center.

### Bouncing Ball

```
1 shape layer + 1 null layer, position keyframes
```

Introduces keyframed animation (position oscillates vertically) and the null
layer type (`ty: 3`). The null layer has no shapes and no transform, testing
that the parser tolerates empty layers.

### Pulsing Ring

```
1 shape layer, scale + opacity keyframes, stroke-only (no fill)
```

Tests stroke rendering without fill. The ring expands and fades via scale and
opacity keyframes simultaneously. This exercises the `st` (stroke) shape type
and multi-property animation.

### Spinning Squares

```
2 shape layers, rotation keyframes, rounded rectangles
```

Two layers spinning in opposite directions. Tests rotation keyframes, the `rc`
(rectangle) shape type with corner roundness (`r` field), and multiple layers
rendering in the correct order.

### Color Morph

```
1 shape layer, animated fill color (4 keyframes), animated stroke width
```

Tests animated color values (fill `c` property cycles through hues) and
animated stroke width (`w` property). This exercises the parser's handling of
animated multi-dimensional properties on style shapes, not just transforms.

### Solar System

```
5 shape layers, position/rotation/scale/opacity keyframes, nested groups,
stroke + fill, multiple shapes per layer
```

The most complex inline sample. A sun with pulsing scale, an orbiting planet
with self-rotation, and a moon orbiting the planet. Tests:
- Multiple keyframe types on different layers
- Multiple shapes per layer (star dots, sun glow)
- Nested groups (planet body with fill + stroke + outline in one group)
- Opacity animation on background layer

This is the bridge between "simple demos" and the large fixture files.

---

## 3. Fixture Files

Fixture files are generated by Python scripts (not committed) and stored as
pretty-printed JSON with indent-2 formatting. They are loaded in the web app
via async fetch from `/fixtures/*.json`, served by a custom Vite middleware
plugin.

### 3.1 Many Layers

**File**: `test/fixtures/many_layers.json` (148 KB)

**Scene**: A 10x5 grid of 50 shape layers on a 1024x1024 canvas. Each layer
contains one shape group with a geometry shape (rectangle, ellipse, or both),
a fill, and optionally a stroke and transform. Layers are positioned in a
regular grid but have varied shapes, colors, rotation keyframes, and scale
pulse animations.

**What it tests**:
- **Wide layer arrays**: 50 layers in a single animation. Verifies
  `parseLayers()` handles large arrays without stack overflow or excessive
  allocation.
- **Uniform structure with variation**: all layers are shape layers (`ty: 4`)
  with one group, but group item counts vary (3 or 4 items depending on
  whether a stroke is present). The test asserts `items.len >= 3` rather than
  an exact count.
- **Layer transform keyframes**: most layers have animated rotation and/or
  scale on their layer-level `ks` transform.

**Why not a simple grid of identical rectangles?** A uniform grid tests nothing
beyond array allocation. Varying the shapes, colors, and animation per layer
ensures the parser handles heterogeneous data within a homogeneous structure.

### 3.2 Many Keyframes

**File**: `test/fixtures/many_keyframes.json` (247 KB)

**Scene**: An orbital system at 1024x1024, 60fps. A central pulsing sun
surrounded by 7 orbiting bodies. Each orbiter follows a circular path via
position keyframes with 61 samples per orbit. All layers have animated scale
(41 keyframes) and opacity (31 keyframes). Orbiter layers additionally have
animated position (61 keyframes) with bezier easing.

**What it tests**:
- **High keyframe density**: 1100+ total keyframed properties. Verifies that
  `parseAnimatedScalar` and `parseAnimatedMulti` handle large keyframe arrays
  efficiently.
- **Bezier easing handles**: orbiter position keyframes include `o` (ease-out)
  and `i` (ease-in) objects with `x`/`y` arrays. Tests the `parseEaseHandle`
  code path.
- **All transform properties animated**: position, scale, and opacity are
  keyframed on every layer. Rotation is static on most layers (the central
  sun doesn't orbit).
- **60fps frame rate**: tests that the frame rate field is parsed correctly as
  a float, not just the common 24/30 values.

**Design choice**: the orbital metaphor was chosen because it naturally produces
many evenly-spaced position keyframes (sampling a circle at regular intervals)
without feeling artificial. 61 keyframes per orbit at 60fps gives a smooth
one-second revolution with sub-frame sampling precision.

### 3.3 Deep Nesting

**File**: `test/fixtures/deep_nesting.json` (414 KB)

**Scene**: "Fractal Garden" -- an 800x600 landscape at 30fps with 8 layers:

| Layer | Description | Nesting Depth |
|:------|:------------|:-------------:|
| Oak, Birch, Willow | Three recursive trees at different positions | 5 |
| Ground | Terrain ridges > grass patches > tufts > blades | 5 |
| Clouds | Cloud field > clouds > clusters > puff groups > puffs | 5 |
| Fireflies | Particle streams > waves > clusters > pairs > dots | 5 |
| Seeds | Same structure as Fireflies, different position/colors | 5 |
| Sun | Sun core > corona > ray groups > ray pairs > rays | 5 |

Every layer has exactly 5 levels of nested shape groups.

**What it tests**:
- **Recursive shape parsing**: `parseShapes()` calls itself for group items.
  5-level nesting means 5 levels of recursion. The test walks the first tree's
  nesting chain using a `findGroup` helper that searches for the first group
  child at each level.
- **Group transform shapes**: every group has a `ty: "tr"` transform as its
  last item, exercising `parseTransformFromShapeFields()` at every nesting
  level.
- **Animated properties at every depth**: rotation sway, scale pulsing,
  opacity fading, and color cycling are applied at different nesting levels.
  The parser must correctly associate animated properties with their
  containing shape regardless of depth.

**Why trees instead of mechanical nesting?** The previous version was 8
identical layers with 5-level nesting of static rectangles -- correct for
parser testing but visually dead. Recursive tree branching is a natural
fit for deep nesting: each branch subdivides into smaller branches, producing
the required depth organically. The variety of layer types (trees, ground,
clouds, particles, sun) ensures different shape combinations at each level.

**Size management**: 5-level binary branching would produce 2^5 = 32 leaf
nodes per tree, exploding file size. Each tree uses single-child branching
(one branch per level) with two top-level branches in the root group. This
keeps the file at 414 KB while maintaining the full nesting depth.

### 3.4 Kitchen Sink

**File**: `test/fixtures/kitchen_sink.json` (282 KB)

**Scene**: "The Clockwork Aquarium" -- a 1920x1080 Art Deco underwater
scene at 60fps combining organic sea life with mechanical clockwork elements.
20 layers exercising every feature the parser supports.

#### Layer Inventory

| # | Type | Name | Parser Features Exercised |
|:--|:-----|:-----|:------------------------|
| 0 | Null | Camera Rig | Null layer, bezier-eased position/scale |
| 1 | Null | Fish School Rig | Null layer, 5-keyframe position path |
| 2 | Null | Gear Train Rig | Null layer, static position, bezier scale |
| 3 | Precomp | Bubble Column | Precomp layer, refId, w/h, animated opacity |
| 4 | Precomp | Kelp Forest | Precomp layer, animated scale |
| 5 | Shape | Angelfish | Parent ref (->1), ellipse body, path tail, rect fin with round_corners, animated fill color (4 kf), animated stroke width |
| 6 | Shape | Clownfish | Parent ref (->1), same structure, different scale |
| 7 | Shape | Neon Tetra | Parent ref (->1), smallest fish variant |
| 8 | Shape | Moon Jelly | Bezier bell path, 4 wavy tentacle paths, trim animation on each tentacle, animated scale pulsing |
| 9 | Shape | Box Jelly | Same structure as Moon Jelly, different position/size |
| 10 | Shape | Main Gear | Parent ref (->2), gear-tooth path (48 vertices), round_corners, hold keyframes on opacity, continuous rotation |
| 11 | Shape | Pinion | Parent ref (->2), smaller gear, counter-rotation |
| 12 | Shape | Pendulum | Parent ref (->2), rect rod + ellipse bob, bezier-eased swing, animated bob fill color |
| 13 | Shape | Nautilus | Golden spiral path (25 pts), animated trim (drawing on/off), animated stroke width |
| 14 | Shape | Anemone | 6 wavy paths with per-tendril trim offsets, animated rotation per tendril |
| 15 | Shape | Coral Reef | Rect base with round_corners, hold-keyframed mound colors |
| 16 | Shape | Light Rays | 4 trapezoidal paths, animated opacity |
| 17 | Shape | Seahorse | Organic body path (12 pts with curved handles), spiral tail with trim, round_corners, animated fill cycling |
| 18 | Shape | Starfish | Star path (10-vertex star), animated fill color, round_corners |
| 19 | Shape | Treasure Chest | Rect body, animated lid rotation (opens/closes), lock path with hold-keyframed trim (unlock), hold-keyframed glow |

#### Feature Coverage Matrix

| Feature | Where It Appears |
|:--------|:----------------|
| `ty: 0` (precomp) | Bubble Column, Kelp Forest |
| `ty: 3` (null) | Camera Rig, Fish School Rig, Gear Train Rig |
| `ty: 4` (shape) | All 15 shape layers |
| `parent` reference | Fish (->1), Gears+Pendulum (->2) |
| `el` (ellipse) | Fish bodies, eyes, bobs, glow, center dots |
| `rc` (rectangle) | Fish fins, pendulum rod, chest body/lid, reef, gear axles |
| `sh` (path) | Fish tails, jellyfish bells/tentacles, gears, nautilus, anemone, light rays, seahorse body/tail, starfish, lock |
| `fl` (fill) | Nearly every shape |
| `st` (stroke) | Fish outlines, jellyfish tentacles, gear/pendulum outlines, nautilus spiral, anemone, seahorse, starfish, lock |
| `gr` (group) | Every shape layer uses groups |
| `tm` (trim) | Jellyfish tentacles, nautilus spiral, anemone tendrils, lock mechanism |
| `rd` (round_corners) | Fish fins, gears, nautilus body, seahorse body, starfish, chest, reef |
| `tr` (transform) | Inside most groups |
| Hold keyframes | Gear opacity, chest lid fill, lock trim, glow opacity, coral mound colors |
| Bezier easing | Fish/jelly/pendulum/nautilus/camera position, gear/camera scale |
| Static properties | Anchors, some positions, reef/light ray transforms |
| Animated fill `c` | Fish bodies (4 kf color cycle), pendulum bob, nautilus body, seahorse, starfish, lock stroke |
| Animated stroke `w` | Fish outlines, jellyfish tentacles, nautilus spiral, seahorse tail |
| Animated opacity | Nearly every layer and many sub-shapes |

**Why "Clockwork Aquarium"?** The kitchen sink fixture must exercise *every*
parser feature simultaneously. An underwater scene with mechanical elements
provides natural homes for every shape type:
- Organic curves (fish, jellyfish, seahorse) require **paths** with bezier
  handles.
- Mechanical parts (gears, pendulum, chest) require **rectangles** and
  **round_corners**.
- Drawing effects (tentacles unfolding, lock opening, spiral tracing) require
  **trim**.
- Discrete state changes (chest open/closed, lock on/off, color flashing)
  require **hold keyframes**.
- Hierarchical motion (fish following a school, gears on a rig) require
  **parent references** to null controller layers.
- Background composition requires **precomp** layers.

The scene was designed so that each feature appears at least twice in different
visual contexts, ensuring the test is not just a checklist but a realistic
exercise of the parser under varied conditions.

---

## 4. Pastel Color Palette

All fixture colors use a shared 12-color pastel palette. Every RGB component
falls between 0.25 and 0.95 to avoid harsh saturated or near-black values.

```
Soft indigo     [0.486, 0.435, 0.769]
Soft rose       [0.835, 0.478, 0.545]
Soft sage       [0.420, 0.702, 0.557]
Soft terracotta [0.769, 0.529, 0.424]
Soft sky blue   [0.435, 0.667, 0.820]
Soft lavender   [0.667, 0.537, 0.788]
Soft gold       [0.820, 0.729, 0.424]
Soft teal       [0.392, 0.718, 0.694]
Soft mauve      [0.718, 0.475, 0.663]
Soft moss       [0.502, 0.682, 0.455]
Soft salmon     [0.878, 0.565, 0.502]
Soft steel blue [0.498, 0.573, 0.710]
```

The palette is shared with the web UI's design system (which uses the same
indigo/rose/sage/terracotta tones). Animated color keyframes cycle between
palette entries via index arithmetic (`col(i)`, `col(i+1)`, etc.).

---

## 5. Integration Tests

Each fixture has a corresponding integration test in `src/root.zig` that
loads the file from disk via `readFixture()` and validates the parsed result:

```zig
test "fixture: many_layers.json (148KB, 50 layers)" {
    const json = try readFixture("test/fixtures/many_layers.json");
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqual(@as(usize, 50), anim.layers.len);
    // ... structural assertions
}
```

The integration tests verify:
- **Metadata**: version, dimensions, frame rate, name, layer count.
- **Structure**: layer types, shape group structure, nesting depth.
- **Animated properties**: that position/scale/opacity are keyframed where
  expected, with minimum keyframe counts.

Tests use `>=` bounds rather than exact counts for keyframe lengths and item
counts. This makes the tests resilient to fixture regeneration (e.g., adding
an extra grass blade) without losing structural verification.

The `deep_nesting` test uses an inline `findGroup` helper struct to walk the
nesting chain, searching for the first group child at each level rather than
assuming a fixed index. This is because the first items in each group are
geometry shapes (rect, fill), and the first group child appears at varying
indices depending on how many non-group shapes precede it.

---

## 6. Web Serving

Fixture files live in `test/fixtures/` (not in the web app's source tree)
because they are primarily Zig test data. The web app needs to serve them
for the sample dropdown.

**Problem**: Vite's `publicDir` is already set to `../zig-out/wasm/` (for the
WASM binary). Vite only supports one `publicDir`. The `fs.allow` config
option permits module imports from parent directories but does not serve
arbitrary files over HTTP.

**Solution**: A custom Vite plugin (`serve-fixtures`) injects Connect
middleware that intercepts requests matching `/fixtures/*.json` and serves the
corresponding file from `test/fixtures/`:

```typescript
// vite.config.ts
function fixturesPlugin(): Plugin {
  return {
    name: 'serve-fixtures',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (req.url?.startsWith('/fixtures/') && req.url.endsWith('.json')) {
          // serve from test/fixtures/
        }
      })
    },
  }
}
```

The `samples.ts` entries for fixture files use `url: '/fixtures/many_layers.json'`
(relative URL) rather than embedding the JSON. The `App.tsx` component detects
the `url` field and fetches asynchronously, showing "Loading..." in the editor
until the file arrives.
