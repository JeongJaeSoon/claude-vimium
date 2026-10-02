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

// The helper is a native app: hint mode needs the Accessibility tree and a
// global key, and no mod surface reaches either.
async function helper($: EngineInterface, verb: 'start' | 'toggle') {
  const run = await $.process.run(['/bin/sh', `${$.plugin.root}/helper/launch.sh`, verb], { timeoutMs: 180_000 })
  return { ok: run.exitCode === 0, message: (run.stderr || run.stdout).trim().split('\n').at(-1) ?? '' }
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
    const started = await helper($, 'start')
    $.ui.toast(started.ok ? 'vimium-hints: Ctrl+; for hints' : `vimium-hints: helper failed: ${started.message}`)
    return next(e)
  })

  on('command.run', { command: 'vimium' }, async $ => {
    const toggled = await helper($, 'toggle')
    return toggled.ok ? {} : { text: `vimium-hints: helper failed: ${toggled.message}` }
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
