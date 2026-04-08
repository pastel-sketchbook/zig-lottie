/// TypeScript wrapper around the zig-lottie WASM module.

export interface LottieWasm {
  version: () => string
  parse: (json: string) => ParseResult
  validate: (json: string) => ValidateResult
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

interface WasmExports {
  memory: WebAssembly.Memory
  lottie_version: () => number
  lottie_version_len: () => number
  lottie_alloc: (len: number) => number
  lottie_free: (ptr: number, len: number) => void
  lottie_parse: (ptr: number, len: number) => number
  lottie_validate: (ptr: number, len: number) => number
}

export async function loadLottieWasm(): Promise<LottieWasm> {
  const response = await fetch('/zig-lottie.wasm')
  const bytes = await response.arrayBuffer()
  const { instance } = await WebAssembly.instantiate(bytes, {})
  const exports = instance.exports as unknown as WasmExports

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
      return JSON.parse(resultStr) as ParseResult
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
      return JSON.parse(resultStr) as ValidateResult
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

  return { version, parse, validate }
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

  // Read result string by scanning for matching closing brace
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
