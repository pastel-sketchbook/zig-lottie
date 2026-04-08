/// Built-in Lottie sample animations, ordered from simple to complex.
/// Each exercises progressively more features of the parser and renderer.

export interface Sample {
  name: string
  description: string
  json?: object
  /** URL to fetch JSON from (for large fixture files). */
  url?: string
}

// ---------------------------------------------------------------------------
// 1. Static Circle — minimal valid Lottie, no animation
// ---------------------------------------------------------------------------
const staticCircle: Sample = {
  name: 'Static Circle',
  description: 'Minimal Lottie — one shape layer with a filled ellipse, no keyframes',
  json: {
    v: '5.7.1',
    fr: 30,
    ip: 0,
    op: 60,
    w: 512,
    h: 512,
    nm: 'Static Circle',
    layers: [
      {
        ty: 4,
        nm: 'Circle Layer',
        ind: 0,
        ip: 0,
        op: 60,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: { a: 0, k: [256, 256, 0] },
          s: { a: 0, k: [100, 100, 100] },
          r: { a: 0, k: 0 },
          o: { a: 0, k: 100 },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Group',
            it: [
              { ty: 'el', nm: 'Ellipse', s: { a: 0, k: [120, 120] }, p: { a: 0, k: [0, 0] } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.486, 0.435, 0.769, 1] }, o: { a: 0, k: 100 } },
            ],
          },
        ],
      },
    ],
  },
}

// ---------------------------------------------------------------------------
// 2. Bouncing Ball — position keyframes (the original sample)
// ---------------------------------------------------------------------------
const bouncingBall: Sample = {
  name: 'Bouncing Ball',
  description: 'Position keyframes on a shape layer — ball moves up and down',
  json: {
    v: '5.7.1',
    fr: 30,
    ip: 0,
    op: 90,
    w: 512,
    h: 512,
    nm: 'Bouncing Ball',
    layers: [
      {
        ty: 4,
        nm: 'Ball',
        ind: 1,
        ip: 0,
        op: 90,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: {
            a: 1,
            k: [
              { t: 0, s: [256, 100, 0] },
              { t: 30, s: [256, 400, 0] },
              { t: 60, s: [256, 100, 0] },
            ],
          },
          s: { a: 0, k: [100, 100, 100] },
          r: { a: 0, k: 0 },
          o: { a: 0, k: 100 },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Ball Group',
            it: [
              { ty: 'el', nm: 'Circle', s: { a: 0, k: [80, 80] }, p: { a: 0, k: [0, 0] } },
              { ty: 'fl', nm: 'Red Fill', c: { a: 0, k: [0.835, 0.478, 0.545, 1] }, o: { a: 0, k: 100 } },
            ],
          },
        ],
      },
      { ty: 3, nm: 'Null Controller', ind: 2, ip: 0, op: 90 },
    ],
  },
}

// ---------------------------------------------------------------------------
// 3. Pulsing Ring — scale + opacity keyframes, stroke (no fill)
// ---------------------------------------------------------------------------
const pulsingRing: Sample = {
  name: 'Pulsing Ring',
  description: 'Scale and opacity keyframes with a stroke-only ellipse — ring expands and fades',
  json: {
    v: '5.7.1',
    fr: 30,
    ip: 0,
    op: 60,
    w: 512,
    h: 512,
    nm: 'Pulsing Ring',
    layers: [
      {
        ty: 4,
        nm: 'Ring',
        ind: 0,
        ip: 0,
        op: 60,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: { a: 0, k: [256, 256, 0] },
          s: {
            a: 1,
            k: [
              { t: 0, s: [40, 40, 100] },
              { t: 30, s: [140, 140, 100] },
              { t: 60, s: [40, 40, 100] },
            ],
          },
          r: { a: 0, k: 0 },
          o: {
            a: 1,
            k: [
              { t: 0, s: [100] },
              { t: 30, s: [30] },
              { t: 60, s: [100] },
            ],
          },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Ring Group',
            it: [
              { ty: 'el', nm: 'Circle', s: { a: 0, k: [200, 200] }, p: { a: 0, k: [0, 0] } },
              {
                ty: 'st',
                nm: 'Stroke',
                c: { a: 0, k: [0.486, 0.435, 0.769, 1] },
                o: { a: 0, k: 100 },
                w: { a: 0, k: 4 },
              },
            ],
          },
        ],
      },
    ],
  },
}

// ---------------------------------------------------------------------------
// 4. Spinning Squares — rotation keyframes, multiple shapes, rounded rect
// ---------------------------------------------------------------------------
const spinningSquares: Sample = {
  name: 'Spinning Squares',
  description: 'Rotation keyframes on two layers with rounded rectangles and different colors',
  json: {
    v: '5.7.1',
    fr: 30,
    ip: 0,
    op: 120,
    w: 512,
    h: 512,
    nm: 'Spinning Squares',
    layers: [
      {
        ty: 4,
        nm: 'Outer Square',
        ind: 0,
        ip: 0,
        op: 120,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: { a: 0, k: [256, 256, 0] },
          s: { a: 0, k: [100, 100, 100] },
          r: {
            a: 1,
            k: [
              { t: 0, s: [0] },
              { t: 120, s: [360] },
            ],
          },
          o: { a: 0, k: 80 },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Square Group',
            it: [
              { ty: 'rc', nm: 'Rect', s: { a: 0, k: [180, 180] }, p: { a: 0, k: [0, 0] }, r: { a: 0, k: 16 } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.486, 0.435, 0.769, 1] }, o: { a: 0, k: 100 } },
            ],
          },
        ],
      },
      {
        ty: 4,
        nm: 'Inner Square',
        ind: 1,
        ip: 0,
        op: 120,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: { a: 0, k: [256, 256, 0] },
          s: { a: 0, k: [100, 100, 100] },
          r: {
            a: 1,
            k: [
              { t: 0, s: [0] },
              { t: 120, s: [-360] },
            ],
          },
          o: { a: 0, k: 100 },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Square Group',
            it: [
              { ty: 'rc', nm: 'Rect', s: { a: 0, k: [100, 100] }, p: { a: 0, k: [0, 0] }, r: { a: 0, k: 8 } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.835, 0.478, 0.545, 1] }, o: { a: 0, k: 100 } },
            ],
          },
        ],
      },
    ],
  },
}

// ---------------------------------------------------------------------------
// 5. Color Morph — animated fill color + animated stroke
// ---------------------------------------------------------------------------
const colorMorph: Sample = {
  name: 'Color Morph',
  description: 'Animated fill color cycling through hues, with animated stroke width',
  json: {
    v: '5.7.1',
    fr: 30,
    ip: 0,
    op: 90,
    w: 512,
    h: 512,
    nm: 'Color Morph',
    layers: [
      {
        ty: 4,
        nm: 'Morphing Shape',
        ind: 0,
        ip: 0,
        op: 90,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: { a: 0, k: [256, 256, 0] },
          s: { a: 0, k: [100, 100, 100] },
          r: { a: 0, k: 0 },
          o: { a: 0, k: 100 },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Shape Group',
            it: [
              { ty: 'el', nm: 'Circle', s: { a: 0, k: [200, 200] }, p: { a: 0, k: [0, 0] } },
              {
                ty: 'fl',
                nm: 'Animated Fill',
                c: {
                  a: 1,
                  k: [
                    { t: 0, s: [0.486, 0.435, 0.769, 1] },
                    { t: 30, s: [0.42, 0.702, 0.557, 1] },
                    { t: 60, s: [0.835, 0.478, 0.545, 1] },
                    { t: 90, s: [0.486, 0.435, 0.769, 1] },
                  ],
                },
                o: { a: 0, k: 100 },
              },
              {
                ty: 'st',
                nm: 'Animated Stroke',
                c: { a: 0, k: [0.36, 0.33, 0.49, 1] },
                o: { a: 0, k: 100 },
                w: {
                  a: 1,
                  k: [
                    { t: 0, s: [2] },
                    { t: 45, s: [8] },
                    { t: 90, s: [2] },
                  ],
                },
              },
            ],
          },
        ],
      },
    ],
  },
}

// ---------------------------------------------------------------------------
// 6. Solar System — multi-layer scene with nested groups, multiple shapes,
//    various keyframe types (position, rotation, scale, opacity)
// ---------------------------------------------------------------------------
const solarSystem: Sample = {
  name: 'Solar System',
  description:
    'Multi-layer scene: orbiting planet with moon, animated position/rotation/scale/opacity, nested groups, strokes and fills',
  json: {
    v: '5.7.1',
    fr: 30,
    ip: 0,
    op: 180,
    w: 512,
    h: 512,
    nm: 'Solar System',
    layers: [
      // Background stars (static dots)
      {
        ty: 4,
        nm: 'Stars',
        ind: 0,
        ip: 0,
        op: 180,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: { a: 0, k: [0, 0, 0] },
          s: { a: 0, k: [100, 100, 100] },
          r: { a: 0, k: 0 },
          o: {
            a: 1,
            k: [
              { t: 0, s: [60] },
              { t: 90, s: [100] },
              { t: 180, s: [60] },
            ],
          },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Star 1',
            it: [
              { ty: 'el', nm: 'Dot', s: { a: 0, k: [6, 6] }, p: { a: 0, k: [80, 60] } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.85, 0.82, 0.95, 1] }, o: { a: 0, k: 100 } },
            ],
          },
          {
            ty: 'gr',
            nm: 'Star 2',
            it: [
              { ty: 'el', nm: 'Dot', s: { a: 0, k: [4, 4] }, p: { a: 0, k: [420, 90] } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.85, 0.82, 0.95, 1] }, o: { a: 0, k: 100 } },
            ],
          },
          {
            ty: 'gr',
            nm: 'Star 3',
            it: [
              { ty: 'el', nm: 'Dot', s: { a: 0, k: [5, 5] }, p: { a: 0, k: [150, 430] } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.85, 0.82, 0.95, 1] }, o: { a: 0, k: 100 } },
            ],
          },
          {
            ty: 'gr',
            nm: 'Star 4',
            it: [
              { ty: 'el', nm: 'Dot', s: { a: 0, k: [3, 3] }, p: { a: 0, k: [370, 380] } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.85, 0.82, 0.95, 1] }, o: { a: 0, k: 100 } },
            ],
          },
          {
            ty: 'gr',
            nm: 'Star 5',
            it: [
              { ty: 'el', nm: 'Dot', s: { a: 0, k: [4, 4] }, p: { a: 0, k: [460, 250] } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.85, 0.82, 0.95, 1] }, o: { a: 0, k: 100 } },
            ],
          },
        ],
      },
      // Orbit ring (stroke-only)
      {
        ty: 4,
        nm: 'Orbit Ring',
        ind: 1,
        ip: 0,
        op: 180,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: { a: 0, k: [256, 256, 0] },
          s: { a: 0, k: [100, 100, 100] },
          r: { a: 0, k: 0 },
          o: { a: 0, k: 30 },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Ring',
            it: [
              { ty: 'el', nm: 'Orbit', s: { a: 0, k: [320, 320] }, p: { a: 0, k: [0, 0] } },
              {
                ty: 'st',
                nm: 'Dash',
                c: { a: 0, k: [0.55, 0.51, 0.7, 1] },
                o: { a: 0, k: 100 },
                w: { a: 0, k: 1.5 },
              },
            ],
          },
        ],
      },
      // Sun (center, pulsing scale)
      {
        ty: 4,
        nm: 'Sun',
        ind: 2,
        ip: 0,
        op: 180,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: { a: 0, k: [256, 256, 0] },
          s: {
            a: 1,
            k: [
              { t: 0, s: [100, 100, 100] },
              { t: 90, s: [110, 110, 100] },
              { t: 180, s: [100, 100, 100] },
            ],
          },
          r: { a: 0, k: 0 },
          o: { a: 0, k: 100 },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Sun Body',
            it: [
              { ty: 'el', nm: 'Core', s: { a: 0, k: [80, 80] }, p: { a: 0, k: [0, 0] } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.769, 0.529, 0.424, 1] }, o: { a: 0, k: 100 } },
            ],
          },
          {
            ty: 'gr',
            nm: 'Sun Glow',
            it: [
              { ty: 'el', nm: 'Glow', s: { a: 0, k: [110, 110] }, p: { a: 0, k: [0, 0] } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.769, 0.529, 0.424, 1] }, o: { a: 0, k: 25 } },
            ],
          },
        ],
      },
      // Planet (orbiting via position keyframes + self-rotation)
      {
        ty: 4,
        nm: 'Planet',
        ind: 3,
        ip: 0,
        op: 180,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: {
            a: 1,
            k: [
              { t: 0, s: [416, 256, 0] },
              { t: 45, s: [256, 96, 0] },
              { t: 90, s: [96, 256, 0] },
              { t: 135, s: [256, 416, 0] },
              { t: 180, s: [416, 256, 0] },
            ],
          },
          s: { a: 0, k: [100, 100, 100] },
          r: {
            a: 1,
            k: [
              { t: 0, s: [0] },
              { t: 180, s: [720] },
            ],
          },
          o: { a: 0, k: 100 },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Planet Body',
            it: [
              { ty: 'rc', nm: 'Square', s: { a: 0, k: [36, 36] }, p: { a: 0, k: [0, 0] }, r: { a: 0, k: 6 } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.42, 0.702, 0.557, 1] }, o: { a: 0, k: 100 } },
              {
                ty: 'st',
                nm: 'Outline',
                c: { a: 0, k: [0.32, 0.6, 0.45, 1] },
                o: { a: 0, k: 60 },
                w: { a: 0, k: 2 },
              },
            ],
          },
        ],
      },
      // Moon (orbiting planet — offset position keyframes, smaller)
      {
        ty: 4,
        nm: 'Moon',
        ind: 4,
        ip: 0,
        op: 180,
        ks: {
          a: { a: 0, k: [0, 0, 0] },
          p: {
            a: 1,
            k: [
              { t: 0, s: [446, 256, 0] },
              { t: 45, s: [256, 66, 0] },
              { t: 90, s: [66, 256, 0] },
              { t: 135, s: [256, 446, 0] },
              { t: 180, s: [446, 256, 0] },
            ],
          },
          s: {
            a: 1,
            k: [
              { t: 0, s: [100, 100, 100] },
              { t: 90, s: [70, 70, 100] },
              { t: 180, s: [100, 100, 100] },
            ],
          },
          r: { a: 0, k: 0 },
          o: {
            a: 1,
            k: [
              { t: 0, s: [100] },
              { t: 90, s: [50] },
              { t: 180, s: [100] },
            ],
          },
        },
        shapes: [
          {
            ty: 'gr',
            nm: 'Moon Body',
            it: [
              { ty: 'el', nm: 'Sphere', s: { a: 0, k: [14, 14] }, p: { a: 0, k: [0, 0] } },
              { ty: 'fl', nm: 'Fill', c: { a: 0, k: [0.75, 0.72, 0.85, 1] }, o: { a: 0, k: 100 } },
            ],
          },
        ],
      },
    ],
  },
}

// ---------------------------------------------------------------------------
// Export ordered list
// ---------------------------------------------------------------------------

// Fixture samples (loaded from test files via URL)
const manyLayers: Sample = {
  name: 'Many Layers (148K)',
  description: '50 shape layers in a 10x5 grid with varied shapes, colors, rotations, and scale pulses',
  url: '/fixtures/many_layers.json',
}

const manyKeyframes: Sample = {
  name: 'Many Keyframes (247K)',
  description: '8 layers: central pulsing sun + 7 orbiting bodies with 1100+ keyframes and bezier easing',
  url: '/fixtures/many_keyframes.json',
}

const deepNesting: Sample = {
  name: 'Deep Nesting (414K)',
  description:
    'Fractal garden: trees, clouds, fireflies, sun — 8 layers with 5-level nested groups and animated transforms',
  url: '/fixtures/deep_nesting.json',
}

const kitchenSink: Sample = {
  name: 'Kitchen Sink (282K)',
  description:
    'Clockwork Aquarium: fish schools, jellyfish, gear mechanisms, nautilus spiral, seahorse, treasure chest — 20 layers, all shape types, hold keyframes, bezier easing, parent refs',
  url: '/fixtures/kitchen_sink.json',
}

export const SAMPLES: Sample[] = [
  staticCircle,
  bouncingBall,
  pulsingRing,
  spinningSquares,
  colorMorph,
  solarSystem,
  manyLayers,
  manyKeyframes,
  deepNesting,
  kitchenSink,
]
