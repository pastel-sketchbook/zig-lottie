import { createResource, createSignal, For, onCleanup, Show } from 'solid-js'
import { LottieRenderer } from './renderer'
import { loadLottieWasm, type ParseResult } from './wasm'

const SAMPLE_LOTTIE = JSON.stringify(
  {
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
              {
                ty: 'el',
                nm: 'Circle',
                s: { a: 0, k: [80, 80] },
                p: { a: 0, k: [0, 0] },
              },
              {
                ty: 'fl',
                nm: 'Red Fill',
                c: { a: 0, k: [1, 0, 0, 1] },
                o: { a: 0, k: 100 },
              },
            ],
          },
        ],
      },
      { ty: 3, nm: 'Null Controller', ind: 2, ip: 0, op: 90 },
    ],
  },
  null,
  2,
)

const LAYER_TYPES: Record<number, string> = {
  0: 'Precomp',
  1: 'Solid',
  2: 'Image',
  3: 'Null',
  4: 'Shape',
  5: 'Text',
}

type Tab = 'parse' | 'render'

const btnBase = {
  padding: '0.5rem 1.5rem',
  color: 'white',
  border: 'none',
  'border-radius': '4px',
  'font-size': '14px',
  cursor: 'pointer',
} as const

export default function App() {
  const [wasm] = createResource(loadLottieWasm)
  const [jsonInput, setJsonInput] = createSignal(SAMPLE_LOTTIE)
  const [result, setResult] = createSignal<ParseResult | null>(null)
  const [error, setError] = createSignal<string | null>(null)
  const [playing, setPlaying] = createSignal(false)
  const [tab, setTab] = createSignal<Tab>('parse')

  let canvasRef: HTMLCanvasElement | undefined
  let renderer: LottieRenderer | null = null

  function setCanvasRef(el: HTMLCanvasElement) {
    canvasRef = el
    // Canvas was remounted — old renderer has a stale context
    if (renderer) {
      renderer.stop()
      renderer = null
      setPlaying(false)
    }
  }

  onCleanup(() => renderer?.stop())

  function handleParse() {
    const w = wasm()
    if (!w) return
    setError(null)
    try {
      const r = w.parse(jsonInput())
      setResult(r)
      if (!r.ok) setError(r.error ?? 'Unknown error')
    } catch (e: unknown) {
      setError(String(e))
    }
  }

  function handleRender() {
    if (!canvasRef) return
    setError(null)

    if (!renderer) {
      renderer = new LottieRenderer(canvasRef)
    }

    if (renderer.isPlaying()) {
      renderer.stop()
      setPlaying(false)
      return
    }

    const ok = renderer.load(jsonInput())
    if (!ok) {
      setError('Failed to load Lottie JSON for rendering')
      return
    }

    renderer.play()
    setPlaying(true)
  }

  function switchTab(t: Tab) {
    if (t === tab()) return
    // Stop renderer when leaving render tab
    if (tab() === 'render' && renderer?.isPlaying()) {
      renderer.stop()
      setPlaying(false)
    }
    setError(null)
    setTab(t)
  }

  return (
    <div style={{ 'font-family': 'system-ui, sans-serif', 'max-width': '1200px', margin: '0 auto', padding: '2rem' }}>
      <h1 style={{ 'margin-bottom': '0.5rem' }}>zig-lottie WASM Test</h1>

      <Show when={wasm()} fallback={<p>Loading WASM module...</p>}>
        <p style={{ color: '#666', 'margin-bottom': '1rem' }}>
          WASM loaded — library version:{' '}
          <code style={{ background: '#f0f0f0', padding: '0.2em 0.4em', 'border-radius': '3px' }}>
            {wasm()?.version()}
          </code>
        </p>
      </Show>

      {/* Tab bar */}
      <div style={{ display: 'flex', gap: '0', 'border-bottom': '2px solid #e5e7eb', 'margin-bottom': '1.5rem' }}>
        <TabButton label="Parse" active={tab() === 'parse'} onClick={() => switchTab('parse')} />
        <TabButton label="Render" active={tab() === 'render'} onClick={() => switchTab('render')} />
      </div>

      {/* Shared JSON input */}
      <div style={{ 'margin-bottom': '1rem' }}>
        <h2 style={{ 'margin-bottom': '0.5rem' }}>Lottie JSON Input</h2>
        <textarea
          value={jsonInput()}
          onInput={(e) => setJsonInput(e.currentTarget.value)}
          style={{
            width: '100%',
            height: '250px',
            'font-family': 'monospace',
            'font-size': '12px',
            padding: '0.75rem',
            border: '1px solid #ccc',
            'border-radius': '4px',
            resize: 'vertical',
            'box-sizing': 'border-box',
          }}
        />
      </div>

      {/* Error banner (shared) */}
      <Show when={error()}>
        <div
          style={{
            background: '#fef2f2',
            border: '1px solid #fca5a5',
            'border-radius': '4px',
            padding: '0.75rem',
            color: '#991b1b',
            'margin-bottom': '1rem',
          }}
        >
          {error()}
        </div>
      </Show>

      {/* Parse tab */}
      <Show when={tab() === 'parse'}>
        <div style={{ 'margin-bottom': '1rem' }}>
          <button
            type="button"
            onClick={handleParse}
            disabled={!wasm()}
            style={{
              ...btnBase,
              background: wasm() ? '#2563eb' : '#ccc',
              cursor: wasm() ? 'pointer' : 'not-allowed',
            }}
          >
            Parse
          </button>
        </div>

        <Show when={result()?.ok}>
          {(_ok) => {
            const r = result() as ParseResult
            return (
              <div>
                <h3 style={{ 'margin-bottom': '0.5rem' }}>Animation Info</h3>
                <table
                  style={{
                    width: '100%',
                    'max-width': '600px',
                    'border-collapse': 'collapse',
                    'margin-bottom': '1rem',
                  }}
                >
                  <tbody>
                    <Row label="Version" value={r.version} />
                    <Row label="Name" value={r.name ?? '(unnamed)'} />
                    <Row label="Size" value={`${r.width} x ${r.height}`} />
                    <Row label="Frame Rate" value={`${r.frame_rate} fps`} />
                    <Row label="Duration" value={`${r.duration?.toFixed(2)}s`} />
                    <Row label="Frames" value={`${r.in_point} - ${r.out_point}`} />
                    <Row label="Layers" value={String(r.layer_count)} />
                  </tbody>
                </table>

                <Show when={r.layers && r.layers.length > 0}>
                  <h3 style={{ 'margin-bottom': '0.5rem' }}>Layers</h3>
                  <table style={{ width: '100%', 'max-width': '600px', 'border-collapse': 'collapse' }}>
                    <thead>
                      <tr style={{ 'text-align': 'left', 'border-bottom': '2px solid #e5e7eb' }}>
                        <th style={{ padding: '0.4rem' }}>#</th>
                        <th style={{ padding: '0.4rem' }}>Type</th>
                        <th style={{ padding: '0.4rem' }}>Name</th>
                        <th style={{ padding: '0.4rem' }}>Shapes</th>
                        <th style={{ padding: '0.4rem' }}>Transform</th>
                      </tr>
                    </thead>
                    <tbody>
                      <For each={r.layers}>
                        {(layer, i) => (
                          <tr style={{ 'border-bottom': '1px solid #f3f4f6' }}>
                            <td style={{ padding: '0.4rem' }}>{i()}</td>
                            <td style={{ padding: '0.4rem' }}>
                              <code>{LAYER_TYPES[layer.ty] ?? `Unknown(${layer.ty})`}</code>
                            </td>
                            <td style={{ padding: '0.4rem' }}>{layer.name ?? '-'}</td>
                            <td style={{ padding: '0.4rem' }}>{layer.shapes}</td>
                            <td style={{ padding: '0.4rem' }}>{layer.has_transform ? 'yes' : 'no'}</td>
                          </tr>
                        )}
                      </For>
                    </tbody>
                  </table>
                </Show>
              </div>
            )
          }}
        </Show>

        <Show when={!result()}>
          <p style={{ color: '#999' }}>Click "Parse" to analyze the Lottie JSON via WASM.</p>
        </Show>
      </Show>

      {/* Render tab */}
      <Show when={tab() === 'render'}>
        <div style={{ 'margin-bottom': '1rem' }}>
          <button
            type="button"
            onClick={handleRender}
            disabled={!wasm()}
            style={{
              ...btnBase,
              background: wasm() ? (playing() ? '#dc2626' : '#16a34a') : '#ccc',
              cursor: wasm() ? 'pointer' : 'not-allowed',
            }}
          >
            {playing() ? 'Stop' : 'Render'}
          </button>
        </div>

        <div
          style={{
            border: '1px solid #e5e7eb',
            'border-radius': '4px',
            overflow: 'hidden',
            background: '#fafafa',
            'text-align': 'center',
            'max-width': '520px',
          }}
        >
          <canvas
            ref={setCanvasRef}
            width={512}
            height={512}
            style={{ 'max-width': '100%', height: 'auto', display: 'block', margin: '0 auto' }}
          />
        </div>
      </Show>
    </div>
  )
}

function TabButton(props: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={props.onClick}
      style={{
        padding: '0.6rem 1.5rem',
        'font-size': '14px',
        'font-weight': props.active ? '600' : '400',
        color: props.active ? '#2563eb' : '#6b7280',
        background: 'none',
        border: 'none',
        'border-bottom': props.active ? '2px solid #2563eb' : '2px solid transparent',
        cursor: 'pointer',
        'margin-bottom': '-2px',
      }}
    >
      {props.label}
    </button>
  )
}

function Row(props: { label: string; value?: string }) {
  return (
    <tr style={{ 'border-bottom': '1px solid #f3f4f6' }}>
      <td style={{ padding: '0.4rem 0.75rem 0.4rem 0', 'font-weight': '600', color: '#374151' }}>{props.label}</td>
      <td style={{ padding: '0.4rem 0' }}>
        <code style={{ background: '#f9fafb', padding: '0.15em 0.3em', 'border-radius': '3px' }}>
          {props.value ?? '-'}
        </code>
      </td>
    </tr>
  )
}
