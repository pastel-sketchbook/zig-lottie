/// Simple canvas renderer for Lottie animations.
/// Reads raw Lottie JSON (JS-side) and renders shapes onto a canvas,
/// interpolating keyframes frame-by-frame.

interface LottieJson {
  fr: number
  ip: number
  op: number
  w: number
  h: number
  layers: LottieLayer[]
}

interface LottieLayer {
  ty: number
  nm?: string
  ip?: number
  op?: number
  ks?: LottieTransform
  shapes?: LottieShape[]
  parent?: number
  ind?: number
}

interface LottieTransform {
  a?: AnimProp
  p?: AnimProp
  s?: AnimProp
  r?: AnimProp
  o?: AnimProp
}

interface AnimProp {
  a?: number
  k: number | number[] | AnimKeyframe[]
}

interface AnimKeyframe {
  t: number
  s: number[]
  h?: number
  o?: { x: number[]; y: number[] }
  i?: { x: number[]; y: number[] }
}

interface PathData {
  c: boolean
  v: number[][]
  i: number[][]
  o: number[][]
}

interface LottieShape {
  ty: string
  nm?: string
  it?: LottieShape[]
  ks?: AnimProp | { a?: number; k: PathData }
  s?: AnimProp
  p?: AnimProp
  r?: AnimProp
  c?: AnimProp
  o?: AnimProp
  w?: AnimProp
  e?: AnimProp
}

export class LottieRenderer {
  private canvas: HTMLCanvasElement
  private ctx: CanvasRenderingContext2D
  private anim: LottieJson | null = null
  private animId: number | null = null
  private startTime = 0
  private playing = false

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas
    this.ctx = canvas.getContext('2d') as CanvasRenderingContext2D
  }

  get width() {
    return this.anim?.w ?? 0
  }

  get height() {
    return this.anim?.h ?? 0
  }

  load(json: string): boolean {
    try {
      this.anim = JSON.parse(json) as LottieJson
      this.canvas.width = this.anim.w
      this.canvas.height = this.anim.h
      this.drawFrame(this.anim.ip)
      return true
    } catch {
      return false
    }
  }

  play() {
    if (!this.anim || this.playing) return
    this.playing = true
    this.startTime = performance.now()
    this.tick()
  }

  stop() {
    this.playing = false
    if (this.animId !== null) {
      cancelAnimationFrame(this.animId)
      this.animId = null
    }
  }

  isPlaying() {
    return this.playing
  }

  private tick = () => {
    if (!this.playing || !this.anim) return
    const elapsed = (performance.now() - this.startTime) / 1000
    const totalFrames = this.anim.op - this.anim.ip
    const frame = this.anim.ip + ((elapsed * this.anim.fr) % totalFrames)
    this.drawFrame(frame)
    this.animId = requestAnimationFrame(this.tick)
  }

  drawFrame(frame: number) {
    if (!this.anim) return
    const ctx = this.ctx
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)

    // Draw background
    ctx.fillStyle = '#ffffff'
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height)

    // Build layer index for parent lookups
    const layerMap = new Map<number, LottieLayer>()
    for (const layer of this.anim.layers) {
      if (layer.ind !== undefined) layerMap.set(layer.ind, layer)
    }

    for (const layer of this.anim.layers) {
      const layerIn = layer.ip ?? this.anim.ip
      const layerOut = layer.op ?? this.anim.op
      if (frame < layerIn || frame >= layerOut) continue
      if (layer.ty !== 4) continue

      ctx.save()

      // Walk parent chain and apply transforms from root to leaf
      const chain: LottieLayer[] = []
      let current: LottieLayer | undefined = layer
      while (current) {
        chain.unshift(current)
        current = current.parent !== undefined ? layerMap.get(current.parent) : undefined
      }
      for (const ancestor of chain) {
        if (ancestor.ks) {
          this.applyTransform(ctx, ancestor.ks, frame)
        }
      }

      if (layer.shapes) {
        this.renderShapes(ctx, layer.shapes, frame)
      }

      ctx.restore()
    }
  }

  private applyTransform(ctx: CanvasRenderingContext2D, ks: LottieTransform, frame: number) {
    const anchor = resolveMulti(ks.a, frame, [0, 0, 0])
    const pos = resolveMulti(ks.p, frame, [0, 0, 0])
    const scale = resolveMulti(ks.s, frame, [100, 100, 100])
    const rotation = resolveScalar(ks.r, frame, 0)
    const opacity = resolveScalar(ks.o, frame, 100)

    ctx.globalAlpha *= Math.max(0, Math.min(1, opacity / 100))
    ctx.translate(pos[0], pos[1])
    ctx.rotate((rotation * Math.PI) / 180)
    ctx.scale(scale[0] / 100, scale[1] / 100)
    ctx.translate(-anchor[0], -anchor[1])
  }

  private renderShapes(ctx: CanvasRenderingContext2D, shapes: LottieShape[], frame: number) {
    // Pass 1: collect styles, trim, and transform
    let fillColor: string | null = null
    let strokeColor: string | null = null
    let strokeWidth = 0
    let trimStart = 0
    let trimEnd = 1
    let hasTrim = false

    for (const shape of shapes) {
      switch (shape.ty) {
        case 'fl': {
          const c = resolveMulti(shape.c, frame, [0, 0, 0, 1])
          const opacity = resolveScalar(shape.o, frame, 100)
          fillColor = rgbaStr(c, opacity)
          break
        }
        case 'st': {
          const c = resolveMulti(shape.c, frame, [0, 0, 0, 1])
          const opacity = resolveScalar(shape.o, frame, 100)
          strokeColor = rgbaStr(c, opacity)
          strokeWidth = resolveScalar(shape.w, frame, 1)
          break
        }
        case 'tm': {
          trimStart = resolveScalar(shape.s, frame, 0) / 100
          trimEnd = resolveScalar(shape.e, frame, 100) / 100
          hasTrim = true
          break
        }
        case 'tr':
          this.applyTransform(ctx, shape as unknown as LottieTransform, frame)
          break
      }
    }

    // Pass 2: draw geometry and recurse into groups
    for (const shape of shapes) {
      switch (shape.ty) {
        case 'gr':
          if (shape.it) {
            ctx.save()
            this.renderShapes(ctx, shape.it, frame)
            ctx.restore()
          }
          break

        case 'el': {
          const size = resolveMulti(shape.s, frame, [0, 0])
          const pos = resolveMulti(shape.p, frame, [0, 0])
          ctx.beginPath()
          ctx.ellipse(pos[0], pos[1], size[0] / 2, size[1] / 2, 0, 0, Math.PI * 2)
          this.applyPaint(ctx, fillColor, strokeColor, strokeWidth)
          break
        }

        case 'rc': {
          const size = resolveMulti(shape.s, frame, [0, 0])
          const pos = resolveMulti(shape.p, frame, [0, 0])
          const r = resolveScalar(shape.r, frame, 0)
          const x = pos[0] - size[0] / 2
          const y = pos[1] - size[1] / 2
          ctx.beginPath()
          if (r > 0) {
            ctx.roundRect(x, y, size[0], size[1], r)
          } else {
            ctx.rect(x, y, size[0], size[1])
          }
          this.applyPaint(ctx, fillColor, strokeColor, strokeWidth)
          break
        }

        case 'sh': {
          const pathData = resolvePathData(shape.ks, frame)
          if (!pathData) break
          this.buildPath(ctx, pathData)
          if (hasTrim && strokeColor && !fillColor) {
            // Approximate trim via lineDash on stroke-only paths
            this.applyTrimmedStroke(ctx, strokeColor, strokeWidth, trimStart, trimEnd)
          } else {
            this.applyPaint(ctx, fillColor, strokeColor, strokeWidth)
          }
          break
        }
      }
    }
  }

  private buildPath(ctx: CanvasRenderingContext2D, path: PathData) {
    const verts = path.v
    const inTan = path.i
    const outTan = path.o
    if (verts.length === 0) return

    ctx.beginPath()
    ctx.moveTo(verts[0][0], verts[0][1])

    const len = verts.length
    const segments = path.c ? len : len - 1

    for (let j = 0; j < segments; j++) {
      const curr = j
      const next = (j + 1) % len
      const cp1x = verts[curr][0] + outTan[curr][0]
      const cp1y = verts[curr][1] + outTan[curr][1]
      const cp2x = verts[next][0] + inTan[next][0]
      const cp2y = verts[next][1] + inTan[next][1]

      // If both handles are zero, use lineTo for sharp edges
      if (outTan[curr][0] === 0 && outTan[curr][1] === 0 && inTan[next][0] === 0 && inTan[next][1] === 0) {
        ctx.lineTo(verts[next][0], verts[next][1])
      } else {
        ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, verts[next][0], verts[next][1])
      }
    }

    if (path.c) ctx.closePath()
  }

  private applyTrimmedStroke(ctx: CanvasRenderingContext2D, color: string, width: number, start: number, end: number) {
    // Approximate trim by measuring the path and using lineDash
    // This is a simplified version — real renderers clip the path geometry
    ctx.strokeStyle = color
    ctx.lineWidth = width
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'

    if (start >= end) {
      // Nothing visible
      return
    }

    // Estimate path length (canvas doesn't expose it directly for arbitrary paths)
    // Use a large dash pattern to approximate: visible portion = (end - start)
    const estimatedLength = 2000 // generous estimate
    const visibleLen = (end - start) * estimatedLength
    const offsetLen = start * estimatedLength

    ctx.setLineDash([visibleLen, estimatedLength - visibleLen])
    ctx.lineDashOffset = -offsetLen
    ctx.stroke()
    ctx.setLineDash([])
  }

  private applyPaint(
    ctx: CanvasRenderingContext2D,
    fillColor: string | null,
    strokeColor: string | null,
    strokeWidth: number,
  ) {
    if (fillColor) {
      ctx.fillStyle = fillColor
      ctx.fill()
    }
    if (strokeColor) {
      ctx.strokeStyle = strokeColor
      ctx.lineWidth = strokeWidth
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.stroke()
    }
  }
}

// -- Path data resolution --

function resolvePathData(prop: LottieShape['ks'], _frame: number): PathData | null {
  if (!prop) return null
  const k = (prop as { k: PathData }).k
  if (k && typeof k === 'object' && 'v' in k) {
    return k as PathData
  }
  return null
}

// -- RGBA string helper --

function rgbaStr(c: number[], opacity: number): string {
  return `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${opacity / 100})`
}

// -- Interpolation helpers --

function resolveScalar(prop: AnimProp | undefined, frame: number, fallback: number): number {
  if (!prop) return fallback
  const k = prop.k
  if (typeof k === 'number') return k
  if (Array.isArray(k)) {
    if (k.length === 0) return fallback
    if (typeof k[0] === 'number') return k[0] as number
    return interpolateScalar(k as AnimKeyframe[], frame, fallback)
  }
  return fallback
}

function resolveMulti(prop: AnimProp | undefined, frame: number, fallback: number[]): number[] {
  if (!prop) return fallback
  const k = prop.k
  if (typeof k === 'number') return [k]
  if (Array.isArray(k)) {
    if (k.length === 0) return fallback
    if (typeof k[0] === 'number') return k as number[]
    return interpolateMulti(k as AnimKeyframe[], frame, fallback)
  }
  return fallback
}

function interpolateScalar(keyframes: AnimKeyframe[], frame: number, fallback: number): number {
  if (keyframes.length === 0) return fallback
  if (frame <= keyframes[0].t) return keyframes[0].s?.[0] ?? fallback
  for (let i = 0; i < keyframes.length - 1; i++) {
    const curr = keyframes[i]
    const next = keyframes[i + 1]
    if (frame >= curr.t && frame < next.t) {
      // Hold keyframe: no interpolation, snap to current value
      if (curr.h === 1) return curr.s?.[0] ?? fallback
      const t = (frame - curr.t) / (next.t - curr.t)
      const v0 = curr.s?.[0] ?? fallback
      const v1 = next.s?.[0] ?? v0
      return v0 + (v1 - v0) * easeT(t, curr)
    }
  }
  const last = keyframes[keyframes.length - 1]
  return last.s?.[0] ?? fallback
}

function interpolateMulti(keyframes: AnimKeyframe[], frame: number, fallback: number[]): number[] {
  if (keyframes.length === 0) return fallback
  if (frame <= keyframes[0].t) return keyframes[0].s ?? fallback
  for (let i = 0; i < keyframes.length - 1; i++) {
    const curr = keyframes[i]
    const next = keyframes[i + 1]
    if (frame >= curr.t && frame < next.t) {
      // Hold keyframe: no interpolation
      if (curr.h === 1) return curr.s ?? fallback
      const t = (frame - curr.t) / (next.t - curr.t)
      const eased = easeT(t, curr)
      const v0 = curr.s ?? fallback
      const v1 = next.s ?? v0
      return v0.map((v, j) => v + ((v1[j] ?? v) - v) * eased)
    }
  }
  const last = keyframes[keyframes.length - 1]
  return last.s ?? fallback
}

// -- Bezier easing --

function easeT(t: number, kf: AnimKeyframe): number {
  // If keyframe has bezier easing curves, approximate with cubic bezier
  if (kf.o && kf.i) {
    const ox = kf.o.x?.[0] ?? 0
    const oy = kf.o.y?.[0] ?? 0
    const ix = kf.i.x?.[0] ?? 1
    const iy = kf.i.y?.[0] ?? 1
    return cubicBezierY(t, ox, oy, ix, iy)
  }
  return t // linear
}

function cubicBezierY(t: number, x1: number, y1: number, x2: number, y2: number): number {
  // Solve for the bezier parameter u where bezierX(u) = t,
  // then return bezierY(u). Use Newton's method (5 iterations).
  let u = t
  for (let i = 0; i < 5; i++) {
    const bx = bezierComponent(u, x1, x2)
    const dx = bezierComponentDeriv(u, x1, x2)
    if (Math.abs(dx) < 1e-6) break
    u -= (bx - t) / dx
    u = Math.max(0, Math.min(1, u))
  }
  return bezierComponent(u, y1, y2)
}

function bezierComponent(t: number, p1: number, p2: number): number {
  // Cubic bezier with p0=0, p3=1
  const mt = 1 - t
  return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
}

function bezierComponentDeriv(t: number, p1: number, p2: number): number {
  const mt = 1 - t
  return 3 * mt * mt * p1 + 6 * mt * t * (p2 - p1) + 3 * t * t * (1 - p2)
}
