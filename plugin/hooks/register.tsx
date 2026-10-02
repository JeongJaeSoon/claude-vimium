import type { EngineInterface, Register } from 'claude-code'

const PANE = 'vimium'
// Same default alphabet as src/claude-vimium.js. A Button hotkey is one
// lowercase letter, so labels never grow past one character here.
const ALPHABET = 'asfgqwertzxcv'

type ActionId = 'reply' | 'code' | 'cwd' | 'session' | 'usage' | 'compact'

export const ACTIONS: readonly { id: ActionId; label: string }[] = [
  { id: 'reply', label: 'Copy last reply' },
  { id: 'code', label: 'Copy last code block' },
  { id: 'cwd', label: 'Copy working directory' },
  { id: 'session', label: 'Copy session id' },
  { id: 'usage', label: 'Show context usage' },
  { id: 'compact', label: 'Compact conversation' },
]

export function lastCodeBlock(text: string): string | undefined {
  const blocks = [...text.matchAll(/```[^\n]*\n([\s\S]*?)```/g)]
  return blocks.at(-1)?.[1]
}

export const INSTALL_HINT =
  'the claude-vimium app was not found. Install it with: brew install jeongjaesoon/tap/claude-vimium && claude-vimium setup'

// Hint mode lives in the ClaudeVimium app: it needs the Accessibility tree and
// a global key, and no mod surface reaches either. The URL scheme also starts
// the app when it is not running.
async function openApp($: EngineInterface, command: 'start' | 'toggle') {
  const run = await $.process.run(['/usr/bin/open', '-g', `claude-vimium://${command}`], { timeoutMs: 10_000 })
  return run.exitCode === 0
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'vimium',
      description: 'Hint mode over the whole Claude Desktop window (also Ctrl+;)',
      immediate: true,
    })
    await $.command.register({
      name: 'vimium-palette',
      description: 'Hint palette: press one letter to act',
      immediate: true,
    })
    if (!(await openApp($, 'start'))) $.ui.toast(`vimium-hints: ${INSTALL_HINT}`)
    return next(e)
  })

  on('command.run', { command: 'vimium' }, async $ => {
    return (await openApp($, 'toggle')) ? {} : { text: `vimium-hints: ${INSTALL_HINT}` }
  })

  on('command.run', { command: 'vimium-palette' }, async $ => {
    await $.ui.open({ id: PANE, title: 'vimium', focus: true, closeOnEscape: true, rows: ACTIONS.length + 1 })
    return {}
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button } = $.ui.resolve(e)

    const lastReply = async () => {
      const messages = await $.session.messages()
      if ('deny' in messages) return undefined
      return messages.findLast(m => m.role === 'assistant' && m.text.trim() !== '')?.text
    }
    const copy = async (text: string | undefined, what: string) => {
      if (text === undefined) return `No ${what} to copy`
      const done = await $.ui.copy({ text, surface: e.surface })
      return done.isCopied ? `Copied ${what}` : `Could not copy ${what}: ${done.reason}`
    }
    const run = async (id: ActionId): Promise<string> => {
      switch (id) {
        case 'reply':
          return copy(await lastReply(), 'last reply')
        case 'code': {
          const reply = await lastReply()
          return copy(reply && lastCodeBlock(reply), 'code block')
        }
        case 'cwd':
          return copy(await $.session.cwd(), 'working directory')
        case 'session':
          return copy(await $.session.id(), 'session id')
        case 'usage': {
          const { context } = await $.session.usage()
          return `Context ${context.percent ?? '?'}% · ${await $.session.model()}`
        }
        case 'compact':
          await $.command.run({ command: 'compact' })
          return 'Compacted'
      }
    }

    return (
      <Box flexDirection="column">
        {ACTIONS.map((action, i) => (
          <Button
            key={`hint:${ALPHABET[i]}`}
            hotkey={ALPHABET[i]}
            plain
            onPress={async () => {
              await $.ui.close({ id: PANE })
              $.ui.toast(await run(action.id))
            }}
          >
            {action.label}
          </Button>
        ))}
      </Box>
    )
  })
}
