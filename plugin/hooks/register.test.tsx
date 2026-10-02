import { expect, test } from 'claude-code/testing'

import { ACTIONS, INSTALL_HINT, lastCodeBlock } from './register'

test('lastCodeBlock picks the final fenced block', async () => {
  expect(lastCodeBlock('a\n```js\none\n```\nb\n```\ntwo\n```')).toBe('two\n')
  expect(lastCodeBlock('no code')).toBeUndefined()
})

test('every action gets a one-letter hint and copies on press', async ($, on) => {
  const copied: string[] = []
  on('ui.copy', async (_$, e) => {
    copied.push(e.text)
    return { value: { isCopied: true } }
  })
  on('ui.close', async () => ({ value: undefined }))
  on('session.cwd', async () => ({ value: '/work' }))

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({
      plugin: 'vimium-hints',
      surface,
      component: 'Pane',
      requestId: 'vimium',
      props: {
        title: 'vimium',
        isFocused: true,
        bodyColumns: 60,
        placement: 'inline',
        scroll: { offset: 0, bodyRows: 7, contentRows: 6 },
        view: {},
      },
    })
    expect(await ui.findAll({ type: 'Button' })).toHaveLength(ACTIONS.length)
    await ui.press({ key: 'hint:f' })
    await ui.unmount()
  }
  expect(copied).toEqual(['/work', '/work'])
})

test('/vimium asks the app to toggle through its URL scheme', async ($, on) => {
  const opened: string[][] = []
  on('process.run', async (_$, e) => {
    opened.push([...e.argv])
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  expect(await $.command.run({ command: 'vimium' })).toEqual({})
  expect(opened.at(-1)).toEqual(['/usr/bin/open', '-g', 'claude-vimium://toggle'])
})

test('/vimium says how to install when the app is missing', async ($, on) => {
  on('process.run', async () => ({ value: { exitCode: 1, stdout: '', stderr: 'no application' } }))
  const answer = await $.command.run({ command: 'vimium' })
  expect(answer.text).toBe(`vimium-hints: ${INSTALL_HINT}`)
})
