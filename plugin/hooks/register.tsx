import type { EngineInterface, Register } from 'claude-code'

const PANE = 'hintvim'
// Same default alphabet as src/hintvim.js. A Button hotkey is one
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
  'the hintvim app was not found. Run /hintvim:setup, or: brew install jeongjaesoon/tap/hintvim && hintvim setup'

// Hint mode lives in the Hintvim app: it needs the Accessibility tree and
// a global key, and no mod surface reaches either. The URL scheme also starts
// the app when it is not running.
async function openApp($: EngineInterface, command: 'start' | 'toggle') {
  const run = await $.process.run(['/usr/bin/open', '-g', `hintvim://${command}`], { timeoutMs: 10_000 })
  return run.exitCode === 0
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'hintvim',
      description: 'Show hint labels over the Claude window (same as Ctrl+;)',
      immediate: true,
    })
    await $.command.register({
      name: 'hintvim-palette',
      description: 'Copy the last reply, code block, cwd or session id; show usage; compact',
      immediate: true,
    })
    if (!(await openApp($, 'start'))) $.ui.toast(`hintvim: ${INSTALL_HINT}`)
    return next(e)
  })

  on('command.run', { command: 'hintvim' }, async $ => {
    return (await openApp($, 'toggle')) ? {} : { text: `hintvim: ${INSTALL_HINT}` }
  })

  on('command.run', { command: 'hintvim-palette' }, async $ => {
    await $.ui.open({ id: PANE, title: 'hintvim', focus: true, closeOnEscape: true, rows: ACTIONS.length + 1 })
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
