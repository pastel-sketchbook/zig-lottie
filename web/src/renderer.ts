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
}

interface LottieShape {
  ty: string
  nm?: string
  it?: LottieShape[]
  s?: AnimProp
  p?: AnimProp
  r?: AnimProp
  c?: AnimProp
  o?: AnimProp
  w?: AnimProp
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

    for (const layer of this.anim.layers) {
      // Check layer visibility
      const layerIn = layer.ip ?? this.anim.ip
      const layerOut = layer.op ?? this.anim.op
      if (frame < layerIn || frame >= layerOut) continue

      // Skip non-shape layers for rendering
      if (layer.ty !== 4) continue

      ctx.save()

      // Apply layer transform
      if (layer.ks) {
        this.applyTransform(ctx, layer.ks, frame)
      }

      // Render shapes
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

    ctx.globalAlpha = Math.max(0, Math.min(1, opacity / 100))
    ctx.translate(pos[0], pos[1])
    ctx.rotate((rotation * Math.PI) / 180)
    ctx.scale(scale[0] / 100, scale[1] / 100)
    ctx.translate(-anchor[0], -anchor[1])
  }

  private renderShapes(ctx: CanvasRenderingContext2D, shapes: LottieShape[], frame: number) {
    // Lottie render model: styles apply to all geometry in the same group.
    // Pass 1: collect styles (fl, st) and transforms (tr).
    // Pass 2: draw geometry (el, rc) with collected styles.
    // Groups (gr) recurse independently.
    let fillColor: string | null = null
    let strokeColor: string | null = null
    let strokeWidth = 0

    for (const shape of shapes) {
      switch (shape.ty) {
        case 'fl': {
          const c = resolveMulti(shape.c, frame, [0, 0, 0, 1])
          const opacity = resolveScalar(shape.o, frame, 100)
          fillColor = `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${opacity / 100})`
          break
        }
        case 'st': {
          const c = resolveMulti(shape.c, frame, [0, 0, 0, 1])
          const opacity = resolveScalar(shape.o, frame, 100)
          strokeColor = `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${opacity / 100})`
          strokeWidth = resolveScalar(shape.w, frame, 1)
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
      }
    }
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
      ctx.stroke()
    }
  }
}

// -- Interpolation helpers --

function resolveScalar(prop: AnimProp | undefined, frame: number, fallback: number): number {
  if (!prop) return fallback
  const k = prop.k
  if (typeof k === 'number') return k
  if (Array.isArray(k)) {
    if (k.length === 0) return fallback
    // Static array value [v]
    if (typeof k[0] === 'number') return k[0] as number
    // Keyframed
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
    // Static array value [x, y, ...]
    if (typeof k[0] === 'number') return k as number[]
    // Keyframed
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
      const t = (frame - curr.t) / (next.t - curr.t)
      const v0 = curr.s?.[0] ?? fallback
      const v1 = next.s?.[0] ?? v0
      return v0 + (v1 - v0) * t
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
      const t = (frame - curr.t) / (next.t - curr.t)
      const v0 = curr.s ?? fallback
      const v1 = next.s ?? v0
      return v0.map((v, j) => v + ((v1[j] ?? v) - v) * t)
    }
  }
  const last = keyframes[keyframes.length - 1]
  return last.s ?? fallback
}
