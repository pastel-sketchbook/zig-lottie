/// Lightweight JSON syntax highlighter.
/// Returns an HTML string with <span> elements for each token type.

// Colors tuned to the pastel palette
const TOKEN_COLORS = {
  key: '#7c6fc4', // accent indigo — keys
  string: '#6bb38e', // sage green — string values
  number: '#c4856c', // warm terracotta — numbers
  boolean: '#d47a8b', // soft rose — true/false
  null: '#8b82a3', // muted — null
  brace: '#5c5478', // dark plum — {} []
  punctuation: '#8b82a3', // muted — : ,
} as const

/// Highlight JSON source text into an HTML string with colored spans.
/// Handles malformed JSON gracefully — falls back to plain text for
/// any segment that doesn't match a known token pattern.
export function highlightJson(source: string): string {
  const parts: string[] = []
  let i = 0

  while (i < source.length) {
    const ch = source[i]

    // Whitespace — pass through
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
      parts.push(esc(ch))
      i++
      continue
    }

    // Strings (keys and values)
    if (ch === '"') {
      const end = findStringEnd(source, i)
      const raw = source.slice(i, end)
      // Peek backwards past whitespace to find if this is a key (followed by ':')
      const afterStr = skipWhitespace(source, end)
      const isKey = afterStr < source.length && source[afterStr] === ':'
      const color = isKey ? TOKEN_COLORS.key : TOKEN_COLORS.string
      parts.push(`<span style="color:${color}">${esc(raw)}</span>`)
      i = end
      continue
    }

    // Numbers
    if (ch === '-' || (ch >= '0' && ch <= '9')) {
      const start = i
      if (ch === '-') i++
      while (
        i < source.length &&
        ((source[i] >= '0' && source[i] <= '9') ||
          source[i] === '.' ||
          source[i] === 'e' ||
          source[i] === 'E' ||
          source[i] === '+' ||
          source[i] === '-')
      ) {
        // Avoid consuming a second '-' that isn't part of exponent
        if ((source[i] === '-' || source[i] === '+') && source[i - 1] !== 'e' && source[i - 1] !== 'E') break
        i++
      }
      parts.push(`<span style="color:${TOKEN_COLORS.number}">${esc(source.slice(start, i))}</span>`)
      continue
    }

    // Booleans
    if (source.startsWith('true', i)) {
      parts.push(`<span style="color:${TOKEN_COLORS.boolean}">true</span>`)
      i += 4
      continue
    }
    if (source.startsWith('false', i)) {
      parts.push(`<span style="color:${TOKEN_COLORS.boolean}">false</span>`)
      i += 5
      continue
    }

    // Null
    if (source.startsWith('null', i)) {
      parts.push(`<span style="color:${TOKEN_COLORS.null}">null</span>`)
      i += 4
      continue
    }

    // Braces / brackets
    if (ch === '{' || ch === '}' || ch === '[' || ch === ']') {
      parts.push(`<span style="color:${TOKEN_COLORS.brace}">${esc(ch)}</span>`)
      i++
      continue
    }

    // Punctuation (colon, comma)
    if (ch === ':' || ch === ',') {
      parts.push(`<span style="color:${TOKEN_COLORS.punctuation}">${esc(ch)}</span>`)
      i++
      continue
    }

    // Fallback — emit as-is (handles malformed input)
    parts.push(esc(ch))
    i++
  }

  return parts.join('')
}

// -- Helpers --

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

/// Find the end index of a JSON string starting at `start` (which points to the opening `"`).
function findStringEnd(source: string, start: number): number {
  let i = start + 1
  while (i < source.length) {
    if (source[i] === '\\') {
      i += 2 // skip escaped character
      continue
    }
    if (source[i] === '"') {
      return i + 1
    }
    i++
  }
  return i // unterminated string — return end of input
}

/// Skip whitespace characters from `start`, return first non-whitespace index.
function skipWhitespace(source: string, start: number): number {
  let i = start
  while (i < source.length && (source[i] === ' ' || source[i] === '\t' || source[i] === '\n' || source[i] === '\r')) {
    i++
  }
  return i
}
