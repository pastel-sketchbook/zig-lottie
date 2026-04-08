/// TypeScript wrapper around the zig-lottie WASM module.

export interface LottieWasm {
  version: () => string
  parse: (json: string) => ParseResult
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

interface WasmExports {
  memory: WebAssembly.Memory
  lottie_version: () => number
  lottie_version_len: () => number
  lottie_alloc: (len: number) => number
  lottie_free: (ptr: number, len: number) => void
  lottie_parse: (ptr: number, len: number) => number
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
    const encoder = new TextEncoder()
    const encoded = encoder.encode(json)

    // Allocate WASM memory and copy JSON in
    const ptr = exports.lottie_alloc(encoded.length)
    if (ptr === 0) {
      return { ok: false, error: 'WASM allocation failed' }
    }

    const wasmBuf = new Uint8Array(exports.memory.buffer, ptr, encoded.length)
    wasmBuf.set(encoded)

    // Call parse
    const resultPtr = exports.lottie_parse(ptr, encoded.length)

    // Free the input buffer
    exports.lottie_free(ptr, encoded.length)

    if (resultPtr === 0) {
      return { ok: false, error: 'Parse failed' }
    }

    // Read the result string (scan for end of JSON)
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
        // Check if escaped
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

    // Free the result buffer
    exports.lottie_free(resultPtr, end - resultPtr)

    try {
      return JSON.parse(resultStr) as ParseResult
    } catch {
      return { ok: false, error: `Invalid JSON response: ${resultStr.slice(0, 200)}` }
    }
  }

  return { version, parse }
}
