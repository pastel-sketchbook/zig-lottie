import { readFileSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { defineConfig } from 'vite'
import solidPlugin from 'vite-plugin-solid'

// Read the single-source-of-truth VERSION file from the repo root.
const appVersion = readFileSync(join(__dirname, '..', 'VERSION'), 'utf-8').trim()

// Serve test fixture files from /fixtures/* during dev and preview
function fixturesPlugin() {
  const fixturesDir = join(__dirname, '..', 'test', 'fixtures')
  const testDir = join(__dirname, '..', 'test')

  function fixtureMiddleware(req: InReq, res: InRes, next: () => void) {
    // Serve test fixtures
    if (req.url?.startsWith('/fixtures/')) {
      const filename = req.url.slice('/fixtures/'.length)
      // Only allow .json files, no path traversal
      if (!filename.match(/^[\w.-]+\.json$/)) return next()
      readFile(join(fixturesDir, filename), 'utf-8')
        .then((content) => {
          res.setHeader('Content-Type', 'application/json')
          res.end(content)
        })
        .catch(() => next())
      return
    }
    // Serve WASM test harness
    if (req.url === '/wasm-harness' || req.url === '/wasm-harness.html') {
      readFile(join(testDir, 'wasm-harness.html'), 'utf-8')
        .then((content) => {
          res.setHeader('Content-Type', 'text/html')
          res.end(content)
        })
        .catch(() => next())
      return
    }
    next()
  }

  return {
    name: 'serve-fixtures',
    configureServer(server: {
      middlewares: { use: (fn: (req: InReq, res: InRes, next: () => void) => void) => void }
    }) {
      server.middlewares.use(fixtureMiddleware)
    },
    configurePreviewServer(server: {
      middlewares: { use: (fn: (req: InReq, res: InRes, next: () => void) => void) => void }
    }) {
      server.middlewares.use(fixtureMiddleware)
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
  preview: {
    port: 3000,
  },
  build: {
    target: 'esnext',
  },
  // Allow loading .wasm from parent directory
  publicDir: '../zig-out/wasm',
})
