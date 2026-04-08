import type { JSX } from 'solid-js'
import { createMemo, createResource, createSignal, For, onCleanup, Show } from 'solid-js'
import { highlightJson } from './highlight'
import { LottieRenderer } from './renderer'
import { loadLottieWasm, type ParseResult } from './wasm'

// ---------------------------------------------------------------------------
// Sample data
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Pastel palette
// ---------------------------------------------------------------------------

const C = {
  // Backgrounds
  pageBg: '#f8f7ff',
  cardBg: '#ffffff',
  inputBg: '#fafaff',
  codeBg: '#f0eef8',
  panelBg: '#fcfbff',

  // Borders
  border: '#e4e0f0',
  borderLight: '#eeeaf6',
  divider: '#e8e4f2',

  // Text
  text: '#3b3651',
  textMuted: '#8b82a3',
  textLabel: '#5c5478',

  // Accent — soft indigo
  accent: '#7c6fc4',
  accentLight: '#ece8ff',
  accentHover: '#6b5eb3',

  // Success — soft sage
  success: '#6bb38e',
  successLight: '#e6f5ed',
  successHover: '#5a9e7c',

  // Danger — soft rose
  danger: '#d47a8b',
  dangerLight: '#fdf0f2',
  dangerHover: '#c26878',

  // Warning / error banner
  errorBg: '#fdf0f2',
  errorBorder: '#f0c4cc',
  errorText: '#94404e',

  // Table
  rowHover: '#faf8ff',
  headerBorder: '#d8d2ea',
} as const

// Shared style for the overlay editor (textarea + pre must match exactly)
const editorTextStyle = {
  'font-size': '0.8125rem',
  'line-height': '1.6',
  padding: '1rem 1.25rem',
  margin: '0',
  'tab-size': '2',
} as const

// ---------------------------------------------------------------------------
// Line-only SVG icons (24x24 viewBox, stroke-width 1.5, no fill)
// ---------------------------------------------------------------------------

function IconCode(props: { size?: number }) {
  const s = props.size ?? 18
  return (
    <svg
      aria-hidden="true"
      width={s}
      height={s}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <polyline points="16 18 22 12 16 6" />
      <polyline points="8 6 2 12 8 18" />
    </svg>
  )
}

function IconPlay(props: { size?: number }) {
  const s = props.size ?? 18
  return (
    <svg
      aria-hidden="true"
      width={s}
      height={s}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <polygon points="5 3 19 12 5 21 5 3" />
    </svg>
  )
}

function IconStop(props: { size?: number }) {
  const s = props.size ?? 18
  return (
    <svg
      aria-hidden="true"
      width={s}
      height={s}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
    </svg>
  )
}

function IconLayers(props: { size?: number }) {
  const s = props.size ?? 18
  return (
    <svg
      aria-hidden="true"
      width={s}
      height={s}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <polygon points="12 2 2 7 12 12 22 7 12 2" />
      <polyline points="2 17 12 22 22 17" />
      <polyline points="2 12 12 17 22 12" />
    </svg>
  )
}

function IconInfo(props: { size?: number }) {
  const s = props.size ?? 18
  return (
    <svg
      aria-hidden="true"
      width={s}
      height={s}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <circle cx="12" cy="12" r="10" />
      <line x1="12" y1="16" x2="12" y2="12" />
      <line x1="12" y1="8" x2="12.01" y2="8" />
    </svg>
  )
}

function IconAlert(props: { size?: number }) {
  const s = props.size ?? 18
  return (
    <svg
      aria-hidden="true"
      width={s}
      height={s}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
      <line x1="12" y1="9" x2="12" y2="13" />
      <line x1="12" y1="17" x2="12.01" y2="17" />
    </svg>
  )
}

function IconMonitor(props: { size?: number }) {
  const s = props.size ?? 18
  return (
    <svg
      aria-hidden="true"
      width={s}
      height={s}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <rect x="2" y="3" width="20" height="14" rx="2" ry="2" />
      <line x1="8" y1="21" x2="16" y2="21" />
      <line x1="12" y1="17" x2="12" y2="21" />
    </svg>
  )
}

function IconZap(props: { size?: number }) {
  const s = props.size ?? 16
  return (
    <svg
      aria-hidden="true"
      width={s}
      height={s}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" />
    </svg>
  )
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type Tab = 'parse' | 'render'

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

export default function App() {
  const [wasm] = createResource(loadLottieWasm)
  const [jsonInput, setJsonInput] = createSignal(SAMPLE_LOTTIE)
  const [result, setResult] = createSignal<ParseResult | null>(null)
  const [error, setError] = createSignal<string | null>(null)
  const [playing, setPlaying] = createSignal(false)
  const [tab, setTab] = createSignal<Tab>('parse')
  const highlighted = createMemo(() => highlightJson(jsonInput()))

  let canvasRef: HTMLCanvasElement | undefined
  let renderer: LottieRenderer | null = null

  function setCanvasRef(el: HTMLCanvasElement) {
    canvasRef = el
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
    if (tab() === 'render' && renderer?.isPlaying()) {
      renderer.stop()
      setPlaying(false)
    }
    setError(null)
    setTab(t)
  }

  return (
    <div
      style={{
        display: 'flex',
        'flex-direction': 'column',
        height: '100vh',
        'min-height': '0',
      }}
    >
      {/* ---- Top bar ---- */}
      <header
        style={{
          display: 'flex',
          'align-items': 'center',
          'justify-content': 'space-between',
          padding: '0.6rem 1.25rem',
          'border-bottom': `1px solid ${C.border}`,
          background: C.cardBg,
          'flex-shrink': '0',
        }}
      >
        <div style={{ display: 'flex', 'align-items': 'center', gap: '0.5rem' }}>
          <IconZap size={18} />
          <span style={{ 'font-size': '0.9375rem', 'font-weight': '600', color: C.text, 'letter-spacing': '-0.01em' }}>
            zig-lottie
          </span>
        </div>
        <Show
          when={wasm()}
          fallback={<span style={{ 'font-size': '0.75rem', color: C.textMuted }}>Loading WASM...</span>}
        >
          <span style={{ 'font-size': '0.75rem', color: C.textMuted }}>
            WASM{' '}
            <code
              style={{
                background: C.accentLight,
                color: C.accent,
                padding: '0.1em 0.4em',
                'border-radius': '4px',
                'font-size': '0.6875rem',
                'font-weight': '500',
              }}
            >
              v{wasm()?.version()}
            </code>
          </span>
        </Show>
      </header>

      {/* ---- Main split ---- */}
      <div
        style={{
          display: 'flex',
          flex: '1',
          'min-height': '0',
        }}
      >
        {/* ======== Left panel: JSON editor ======== */}
        <div
          style={{
            width: '45%',
            'min-width': '320px',
            display: 'flex',
            'flex-direction': 'column',
            'border-right': `1px solid ${C.border}`,
            background: C.panelBg,
          }}
        >
          <div
            style={{
              display: 'flex',
              'align-items': 'center',
              'justify-content': 'space-between',
              padding: '0.6rem 1rem',
              'border-bottom': `1px solid ${C.borderLight}`,
              'flex-shrink': '0',
            }}
          >
            <SectionLabel icon={<IconCode size={14} />} text="Lottie JSON" />
          </div>
          {/* Overlay editor: highlighted <pre> behind transparent <textarea> */}
          <div
            style={{
              flex: '1',
              position: 'relative',
              'min-height': '0',
              overflow: 'auto',
              background: C.inputBg,
            }}
          >
            <pre
              aria-hidden="true"
              innerHTML={`${highlighted()}\n`}
              style={{
                ...editorTextStyle,
                position: 'absolute',
                inset: '0',
                'pointer-events': 'none',
                'white-space': 'pre',
                'overflow-wrap': 'normal',
              }}
            />
            <textarea
              value={jsonInput()}
              onInput={(e) => setJsonInput(e.currentTarget.value)}
              spellcheck={false}
              style={{
                ...editorTextStyle,
                position: 'relative',
                width: '100%',
                height: '100%',
                color: 'transparent',
                'caret-color': C.text,
                background: 'transparent',
                border: 'none',
                outline: 'none',
                resize: 'none',
                'white-space': 'pre',
                'overflow-wrap': 'normal',
              }}
            />
          </div>
        </div>

        {/* ======== Right panel: tabs + output ======== */}
        <div
          style={{
            flex: '1',
            'min-width': '0',
            display: 'flex',
            'flex-direction': 'column',
            background: C.pageBg,
          }}
        >
          {/* Tab bar + action button row */}
          <div
            style={{
              display: 'flex',
              'align-items': 'center',
              'justify-content': 'space-between',
              padding: '0 1rem',
              'border-bottom': `1px solid ${C.border}`,
              background: C.cardBg,
              'flex-shrink': '0',
            }}
          >
            <nav style={{ display: 'flex', gap: '0.15rem' }}>
              <TabButton
                icon={<IconCode size={15} />}
                label="Parse"
                active={tab() === 'parse'}
                onClick={() => switchTab('parse')}
              />
              <TabButton
                icon={<IconMonitor size={15} />}
                label="Render"
                active={tab() === 'render'}
                onClick={() => switchTab('render')}
              />
            </nav>
            <div>
              <Show when={tab() === 'parse'}>
                <ActionButton
                  label="Parse"
                  icon={<IconCode size={14} />}
                  color={C.accent}
                  hoverColor={C.accentHover}
                  disabled={!wasm()}
                  onClick={handleParse}
                />
              </Show>
              <Show when={tab() === 'render'}>
                <ActionButton
                  label={playing() ? 'Stop' : 'Render'}
                  icon={playing() ? <IconStop size={14} /> : <IconPlay size={14} />}
                  color={playing() ? C.danger : C.success}
                  hoverColor={playing() ? C.dangerHover : C.successHover}
                  disabled={!wasm()}
                  onClick={handleRender}
                />
              </Show>
            </div>
          </div>

          {/* Output area */}
          <div
            style={{
              flex: '1',
              display: 'flex',
              'flex-direction': 'column',
              'min-height': '0',
            }}
          >
            {/* Error banner */}
            <Show when={error()}>
              <div
                style={{
                  display: 'flex',
                  'align-items': 'flex-start',
                  gap: '0.6rem',
                  background: C.errorBg,
                  border: `1px solid ${C.errorBorder}`,
                  'border-radius': '0',
                  padding: '0.65rem 1.25rem',
                  color: C.errorText,
                  'font-size': '0.8125rem',
                  'border-bottom': `1px solid ${C.errorBorder}`,
                  'flex-shrink': '0',
                }}
              >
                <span style={{ 'flex-shrink': '0', 'margin-top': '1px' }}>
                  <IconAlert size={15} />
                </span>
                <span>{error()}</span>
              </div>
            </Show>

            {/* ---- Parse tab content (scrollable) ---- */}
            <Show when={tab() === 'parse'}>
              <div
                style={{
                  flex: '1',
                  'overflow-y': 'auto',
                  padding: '1.25rem',
                  'min-height': '0',
                }}
              >
                <Show when={result()?.ok}>
                  {(_ok) => {
                    const r = result() as ParseResult
                    return (
                      <>
                        <Card style={{ 'margin-bottom': '1rem' }}>
                          <SectionLabel icon={<IconInfo size={14} />} text="Animation Info" />
                          <div
                            style={{
                              display: 'grid',
                              'grid-template-columns': 'repeat(auto-fill, minmax(150px, 1fr))',
                              gap: '0.5rem',
                            }}
                          >
                            <InfoCell label="Version" value={r.version} />
                            <InfoCell label="Name" value={r.name ?? '(unnamed)'} />
                            <InfoCell label="Size" value={`${r.width} x ${r.height}`} />
                            <InfoCell label="Frame Rate" value={`${r.frame_rate} fps`} />
                            <InfoCell label="Duration" value={`${r.duration?.toFixed(2)}s`} />
                            <InfoCell label="Frames" value={`${r.in_point} - ${r.out_point}`} />
                            <InfoCell label="Layers" value={String(r.layer_count)} />
                          </div>
                        </Card>

                        <Show when={r.layers && r.layers.length > 0}>
                          <Card>
                            <SectionLabel icon={<IconLayers size={14} />} text="Layers" />
                            <div style={{ overflow: 'auto' }}>
                              <table style={{ width: '100%', 'border-collapse': 'collapse', 'font-size': '0.8125rem' }}>
                                <thead>
                                  <tr
                                    style={{
                                      'text-align': 'left',
                                      'border-bottom': `1.5px solid ${C.headerBorder}`,
                                      color: C.textMuted,
                                      'font-weight': '500',
                                      'font-size': '0.6875rem',
                                      'text-transform': 'uppercase',
                                      'letter-spacing': '0.04em',
                                    }}
                                  >
                                    <th style={{ padding: '0.45rem 0.5rem' }}>#</th>
                                    <th style={{ padding: '0.45rem 0.5rem' }}>Type</th>
                                    <th style={{ padding: '0.45rem 0.5rem' }}>Name</th>
                                    <th style={{ padding: '0.45rem 0.5rem' }}>Shapes</th>
                                    <th style={{ padding: '0.45rem 0.5rem' }}>Transform</th>
                                  </tr>
                                </thead>
                                <tbody>
                                  <For each={r.layers}>
                                    {(layer, i) => (
                                      <tr style={{ 'border-bottom': `1px solid ${C.borderLight}` }}>
                                        <td style={{ padding: '0.45rem 0.5rem', color: C.textMuted }}>{i()}</td>
                                        <td style={{ padding: '0.45rem 0.5rem' }}>
                                          <code
                                            style={{
                                              background: C.codeBg,
                                              padding: '0.1em 0.35em',
                                              'border-radius': '4px',
                                              'font-size': '0.75rem',
                                            }}
                                          >
                                            {LAYER_TYPES[layer.ty] ?? `Unknown(${layer.ty})`}
                                          </code>
                                        </td>
                                        <td style={{ padding: '0.45rem 0.5rem' }}>{layer.name ?? '-'}</td>
                                        <td style={{ padding: '0.45rem 0.5rem' }}>{layer.shapes}</td>
                                        <td style={{ padding: '0.45rem 0.5rem' }}>
                                          <span style={{ color: layer.has_transform ? C.success : C.textMuted }}>
                                            {layer.has_transform ? 'yes' : 'no'}
                                          </span>
                                        </td>
                                      </tr>
                                    )}
                                  </For>
                                </tbody>
                              </table>
                            </div>
                          </Card>
                        </Show>
                      </>
                    )
                  }}
                </Show>

                <Show when={!result()}>
                  <EmptyState text='Click "Parse" to analyze the Lottie JSON via WASM.' />
                </Show>
              </div>
            </Show>

            {/* ---- Render tab content (fills remaining height) ---- */}
            <Show when={tab() === 'render'}>
              <div
                style={{
                  flex: '1',
                  display: 'flex',
                  'align-items': 'center',
                  'justify-content': 'center',
                  padding: '1rem',
                  'min-height': '0',
                  background: C.pageBg,
                }}
              >
                <canvas
                  ref={setCanvasRef}
                  width={512}
                  height={512}
                  style={{
                    'max-width': '100%',
                    'max-height': '100%',
                    'object-fit': 'contain',
                    display: 'block',
                    'border-radius': '8px',
                    border: `1px solid ${C.border}`,
                    background: '#ffffff',
                    'box-shadow': '0 1px 4px rgba(60, 50, 90, 0.06)',
                  }}
                />
              </div>
            </Show>
          </div>
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Shared sub-components
// ---------------------------------------------------------------------------

function Card(props: { children: JSX.Element; style?: JSX.CSSProperties }) {
  return (
    <div
      style={{
        background: C.cardBg,
        border: `1px solid ${C.border}`,
        'border-radius': '10px',
        padding: '1rem',
        'box-shadow': '0 1px 3px rgba(60, 50, 90, 0.04)',
        ...props.style,
      }}
    >
      {props.children}
    </div>
  )
}

function SectionLabel(props: { icon: JSX.Element; text: string }) {
  return (
    <div
      style={{
        display: 'flex',
        'align-items': 'center',
        gap: '0.35rem',
        color: C.textLabel,
        'font-family': "'IBM Plex Serif', Georgia, serif",
        'font-size': '0.6875rem',
        'font-weight': '500',
        'text-transform': 'uppercase',
        'letter-spacing': '0.04em',
        'margin-bottom': '0.6rem',
      }}
    >
      {props.icon}
      {props.text}
    </div>
  )
}

function InfoCell(props: { label: string; value?: string }) {
  return (
    <div
      style={{
        background: C.inputBg,
        'border-radius': '6px',
        padding: '0.5rem 0.65rem',
        border: `1px solid ${C.borderLight}`,
      }}
    >
      <div
        style={{
          'font-size': '0.625rem',
          color: C.textMuted,
          'text-transform': 'uppercase',
          'letter-spacing': '0.04em',
          'margin-bottom': '0.15rem',
        }}
      >
        {props.label}
      </div>
      <div style={{ 'font-size': '0.8125rem', 'font-weight': '500', color: C.text }}>{props.value ?? '-'}</div>
    </div>
  )
}

function TabButton(props: { icon: JSX.Element; label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={props.onClick}
      style={{
        display: 'flex',
        'align-items': 'center',
        gap: '0.35rem',
        padding: '0.6rem 0.85rem',
        'font-size': '0.8125rem',
        'font-weight': props.active ? '600' : '400',
        color: props.active ? C.accent : C.textMuted,
        background: 'none',
        border: 'none',
        'border-bottom': props.active ? `2px solid ${C.accent}` : '2px solid transparent',
        cursor: 'pointer',
        'margin-bottom': '-1px',
        transition: 'color 0.15s, border-color 0.15s',
      }}
    >
      {props.icon}
      {props.label}
    </button>
  )
}

function ActionButton(props: {
  label: string
  icon: JSX.Element
  color: string
  hoverColor: string
  disabled: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      onClick={props.onClick}
      disabled={props.disabled}
      style={{
        display: 'inline-flex',
        'align-items': 'center',
        gap: '0.35rem',
        padding: '0.35rem 1rem',
        'font-size': '0.75rem',
        'font-weight': '500',
        color: '#ffffff',
        background: props.disabled ? C.border : props.color,
        border: 'none',
        'border-radius': '5px',
        cursor: props.disabled ? 'not-allowed' : 'pointer',
        transition: 'background 0.15s',
      }}
    >
      {props.icon}
      {props.label}
    </button>
  )
}

function EmptyState(props: { text: string }) {
  return (
    <div
      style={{
        display: 'flex',
        'align-items': 'center',
        'justify-content': 'center',
        padding: '3rem 1rem',
        color: C.textMuted,
        'font-size': '0.8125rem',
      }}
    >
      {props.text}
    </div>
  )
}
