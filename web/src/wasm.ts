/// TypeScript wrapper around the zig-lottie WASM module.

export interface LottieWasm {
  version: () => string
  parse: (json: string) => ParseResult
  validate: (json: string) => ValidateResult
  compileFrame: (json: string, frame: number) => CompileFrameResult
  compile: (json: string) => CompileResult
}

export interface ParseResult {
  ok: boolean
  version?: string
  frame_rate?: number
  in_point?: number
  out_point?: number
  width?: number
  height?: number
  duration?: number
  layer_count?: number
  name?: string
  layers?: LayerInfo[]
  error?: string
}

export interface LayerInfo {
  ty: number
  name?: string
  shapes: number
  has_transform: boolean
}

export interface ValidateResult {
  valid: boolean
  errors: number
  warnings: number
  issues: ValidationIssue[]
  error?: string
}

export interface ValidationIssue {
  severity: 'error' | 'warning'
  message: string
}

export interface ResolvedTransform {
  anchor: [number, number, number]
  position: [number, number, number]
  scale: [number, number, number]
  rotation: number
  opacity: number
}

export interface ResolvedShape {
  ty: string
  name?: string
  size?: [number, number]
  position?: [number, number]
  roundness?: number
  color?: [number, number, number, number]
  opacity?: number
  stroke_width?: number
  transform?: ResolvedTransform
  items?: ResolvedShape[]
}

export interface ResolvedLayer {
  ty: number
  visible: boolean
  name?: string
  index?: number
  parent?: number
  in_point: number
  out_point: number
  transform?: ResolvedTransform
  shapes: ResolvedShape[]
}

export interface CompileFrameResult {
  frame?: number
  layers?: ResolvedLayer[]
  error?: string
}

export interface CompileResult {
  frame_rate?: number
  width?: number
  height?: number
  frame_count?: number
  frames?: { frame: number; layers: ResolvedLayer[] }[]
  error?: string
}

interface WasmExports {
  memory: WebAssembly.Memory
  lottie_version: () => number
  lottie_version_len: () => number
  lottie_alloc: (len: number) => number
  lottie_free: (ptr: number, len: number) => void
  lottie_parse: (ptr: number, len: number) => number
  lottie_validate: (ptr: number, len: number) => number
  lottie_compile_frame: (ptr: number, len: number, frame: number) => number
  lottie_compile: (ptr: number, len: number) => number
}

function assertWasmExports(exports: WebAssembly.Exports): WasmExports {
  const required = [
    'memory',
    'lottie_version',
    'lottie_version_len',
    'lottie_alloc',
    'lottie_free',
    'lottie_parse',
    'lottie_validate',
    'lottie_compile_frame',
    'lottie_compile',
  ]
  for (const name of required) {
    if (!(name in exports)) throw new Error(`Missing WASM export: ${name}`)
  }
  return exports as unknown as WasmExports
}

function isParseResult(v: unknown): v is ParseResult {
  return typeof v === 'object' && v !== null && 'ok' in v
}

function isValidateResult(v: unknown): v is ValidateResult {
  return typeof v === 'object' && v !== null && 'valid' in v && 'issues' in v
}

function isCompileFrameResult(v: unknown): v is CompileFrameResult {
  return typeof v === 'object' && v !== null && 'frame' in v && 'layers' in v
}

function isCompileResult(v: unknown): v is CompileResult {
  return typeof v === 'object' && v !== null && 'frame_count' in v && 'frames' in v
}

export async function loadLottieWasm(): Promise<LottieWasm> {
  const response = await fetch('/zig-lottie.wasm')
  if (!response.ok) throw new Error(`Failed to fetch WASM: ${response.status} ${response.statusText}`)
  const bytes = await response.arrayBuffer()
  const { instance } = await WebAssembly.instantiate(bytes, {})
  const exports = assertWasmExports(instance.exports)

  function version(): string {
    const ptr = exports.lottie_version()
    const len = exports.lottie_version_len()
    const buf = new Uint8Array(exports.memory.buffer, ptr, len)
    return new TextDecoder().decode(buf)
  }

  function parse(json: string): ParseResult {
    const resultStr = callWasmJson(exports, exports.lottie_parse, json)
    if (resultStr === null) {
      return { ok: false, error: 'Parse failed' }
    }
    try {
      const parsed: unknown = JSON.parse(resultStr)
      if (isParseResult(parsed)) return parsed
      return { ok: false, error: `Unexpected response shape: ${resultStr.slice(0, 200)}` }
    } catch {
      return { ok: false, error: `Invalid JSON response: ${resultStr.slice(0, 200)}` }
    }
  }

  function validate(json: string): ValidateResult {
    const resultStr = callWasmJson(exports, exports.lottie_validate, json)
    if (resultStr === null) {
      return { valid: false, errors: 1, warnings: 0, issues: [], error: 'Validation failed' }
    }
    try {
      const parsed: unknown = JSON.parse(resultStr)
      if (isValidateResult(parsed)) return parsed
      return {
        valid: false,
        errors: 1,
        warnings: 0,
        issues: [],
        error: `Unexpected response shape: ${resultStr.slice(0, 200)}`,
      }
    } catch {
      return {
        valid: false,
        errors: 1,
        warnings: 0,
        issues: [],
        error: `Invalid JSON response: ${resultStr.slice(0, 200)}`,
      }
    }
  }

  function compileFrame(json: string, frame: number): CompileFrameResult {
    const resultStr = callWasmJsonWithFrame(exports, exports.lottie_compile_frame, json, frame)
    if (resultStr === null) {
      return { error: 'Compile frame failed' }
    }
    try {
      const parsed: unknown = JSON.parse(resultStr)
      if (isCompileFrameResult(parsed)) return parsed
      return { error: `Unexpected response shape: ${resultStr.slice(0, 200)}` }
    } catch {
      return { error: `Invalid JSON response: ${resultStr.slice(0, 200)}` }
    }
  }

  function compile(json: string): CompileResult {
    const resultStr = callWasmJson(exports, exports.lottie_compile, json)
    if (resultStr === null) {
      return { error: 'Compile failed' }
    }
    try {
      const parsed: unknown = JSON.parse(resultStr)
      if (isCompileResult(parsed)) return parsed
      return { error: `Unexpected response shape: ${resultStr.slice(0, 200)}` }
    } catch {
      return { error: `Invalid JSON response: ${resultStr.slice(0, 200)}` }
    }
  }

  return { version, parse, validate, compileFrame, compile }
}

function callWasmJson(exports: WasmExports, fn: (ptr: number, len: number) => number, json: string): string | null {
  const encoder = new TextEncoder()
  const encoded = encoder.encode(json)

  const ptr = exports.lottie_alloc(encoded.length)
  if (ptr === 0) return null

  const wasmBuf = new Uint8Array(exports.memory.buffer, ptr, encoded.length)
  wasmBuf.set(encoded)

  const resultPtr = fn(ptr, encoded.length)
  exports.lottie_free(ptr, encoded.length)

  if (resultPtr === 0) return null
  return readWasmJsonResult(exports, resultPtr)
}

function callWasmJsonWithFrame(
  exports: WasmExports,
  fn: (ptr: number, len: number, frame: number) => number,
  json: string,
  frame: number,
): string | null {
  const encoder = new TextEncoder()
  const encoded = encoder.encode(json)

  const ptr = exports.lottie_alloc(encoded.length)
  if (ptr === 0) return null

  const wasmBuf = new Uint8Array(exports.memory.buffer, ptr, encoded.length)
  wasmBuf.set(encoded)

  const resultPtr = fn(ptr, encoded.length, frame)
  exports.lottie_free(ptr, encoded.length)

  if (resultPtr === 0) return null
  return readWasmJsonResult(exports, resultPtr)
}

function readWasmJsonResult(exports: WasmExports, resultPtr: number): string {
  const mem = new Uint8Array(exports.memory.buffer)
  let end = resultPtr
  let braceDepth = 0
  let inString = false
  let foundStart = false

  for (let i = resultPtr; i < mem.length; i++) {
    const ch = mem[i]
    if (ch === 0) {
      end = i
      break
    }
    if (ch === 0x22 /* " */) {
      if (i > resultPtr && mem[i - 1] !== 0x5c /* \ */) {
        inString = !inString
      }
    }
    if (!inString) {
      if (ch === 0x7b /* { */) {
        foundStart = true
        braceDepth++
      }
      if (ch === 0x7d /* } */) {
        braceDepth--
        if (foundStart && braceDepth === 0) {
          end = i + 1
          break
        }
      }
    }
  }

  const resultBuf = new Uint8Array(exports.memory.buffer, resultPtr, end - resultPtr)
  const resultStr = new TextDecoder().decode(resultBuf)
  exports.lottie_free(resultPtr, end - resultPtr)
  return resultStr
}
