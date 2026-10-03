import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'yank',
  component: 'Pane',
  requestId: 'yank',
  viewport: { columns: 100, rows: 30 },
  props: { title: 'Yank', isFocused: true, bodyColumns: 60, placement: 'inline', scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

function stubs(on, messages, log) {
  on('session.start', () => ({ cwd: '/work' }))
  on('command.register', () => ({ value: undefined }))
  on('session.messages', () => ({ value: messages }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.close', () => ({ value: undefined }))
  on('ui.toast', ($, e) => { log.toasts.push(e.text); return { value: undefined } })
  on('ui.copy', ($, e) => { log.copied.push(e.text); return { value: { isCopied: true } } })
}

test('picking an entry copies it and closes the pane', async ($, on) => {
  const log = { toasts: [] as string[], copied: [] as string[] }
  stubs(on, [
    { role: 'user', text: 'first question', toolUses: [] },
    { role: 'assistant', text: 'the answer\nmore', toolUses: [] },
    { role: 'assistant', text: '', toolUses: [] },
  ], log)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await $.command.run({ command: 'yank', args: '' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /prefix e/ })).toBeDefined()
  await ui.select({ key: 'entry', value: '0' })
  expect(log.copied).toEqual(['the answer\nmore'])
  expect(log.toasts[0]).toMatch(/Copied 15 characters/)
  await ui.unmount()
})

test('an empty session only toasts', async ($, on) => {
  const log = { toasts: [] as string[], copied: [] as string[] }
  stubs(on, [], log)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await $.command.run({ command: 'yank', args: '' })
  expect(log.toasts).toEqual(['Nothing to copy yet'])
})
