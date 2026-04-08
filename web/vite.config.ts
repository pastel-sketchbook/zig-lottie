import { readFileSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { defineConfig } from 'vite'
import solidPlugin from 'vite-plugin-solid'

// Read the single-source-of-truth VERSION file from the repo root.
const appVersion = readFileSync(join(__dirname, '..', 'VERSION'), 'utf-8').trim()

// Serve test fixture files from /fixtures/* during development
function fixturesPlugin() {
  const fixturesDir = join(__dirname, '..', 'test', 'fixtures')
  return {
    name: 'serve-fixtures',
    configureServer(server: {
      middlewares: { use: (fn: (req: InReq, res: InRes, next: () => void) => void) => void }
    }) {
      server.middlewares.use(async (req: InReq, res: InRes, next: () => void) => {
        if (req.url?.startsWith('/fixtures/')) {
          const filename = req.url.slice('/fixtures/'.length)
          // Only allow .json files, no path traversal
          if (!filename.match(/^[\w.-]+\.json$/)) return next()
          try {
            const content = await readFile(join(fixturesDir, filename), 'utf-8')
            res.setHeader('Content-Type', 'application/json')
            res.end(content)
          } catch {
            next()
          }
          return
        }
        next()
      })
    },
  }
}

interface InReq {
  url?: string
}
interface InRes {
  setHeader(name: string, value: string): void
  end(data: string): void
  statusCode: number
}

export default defineConfig({
  plugins: [solidPlugin(), fixturesPlugin()],
  define: {
    __APP_VERSION__: JSON.stringify(appVersion),
  },
  server: {
    port: 3000,
  },
  build: {
    target: 'esnext',
  },
  // Allow loading .wasm from parent directory
  publicDir: '../zig-out/wasm',
})
