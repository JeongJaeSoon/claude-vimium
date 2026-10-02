import { expect, test } from 'claude-code/testing'

import { ACTIONS, lastCodeBlock } from './register'

test('lastCodeBlock picks the final fenced block', async () => {
  expect(lastCodeBlock('a\n```js\none\n```\nb\n```\ntwo\n```')).toBe('two\n')
  expect(lastCodeBlock('no code')).toBeUndefined()
})

test('every action gets a one-letter hint and copies on press', async ($, on) => {
  const copied: string[] = []
  on('ui.copy', async (_$, e) => {
    copied.push(e.text)
    return { isCopied: true }
  })

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
  expect(copied).toHaveLength(2)
})
