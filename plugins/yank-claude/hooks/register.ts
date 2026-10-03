// /yank: choose one of the latest messages and copy it with $.ui.copy, which
// lands in the tmux buffer even with `set-clipboard off`. Built-in /copy
// covers the latest reply, /copy N and code blocks through the terminal
// clipboard; this covers older messages of any role and the tmux buffer.
const PANE = 'yank'
const RECENT = 20

let entries: { role: string; text: string }[] = []

function label(entry, index) {
  const first = String(entry.text).split('\n').find(line => line.trim() !== '') ?? ''
  const short = first.length > 70 ? first.slice(0, 69) + '…' : first
  return index + 1 + '. ' + entry.role + ': ' + short
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'yank', description: 'Copy a recent message to the tmux buffer', immediate: true })
    return next(e)
  })

  on('command.run', { command: 'yank' }, async ($) => {
    const messages = await $.session.messages()
    entries = messages
      .filter(m => typeof m.text === 'string' && m.text.trim() !== '')
      .slice(-RECENT)
      .reverse()
    if (entries.length === 0) {
      await $.ui.toast('Nothing to copy yet')
      return {}
    }
    await $.ui.open({ id: PANE, title: 'Yank', focus: true, closeOnEscape: true })
    return {}
  })

  on('ui.render', { component: 'Pane' }, async ($, e, next) => {
    if (e.requestId !== PANE) return next(e)
    const { Box, Text, Select } = $.ui.resolve(e)
    return Box({
      flexDirection: 'column',
      children: [
        Text({ children: ['Newest first. Enter copies; prefix e sends the tmux buffer to the client.'], dimColor: true }),
        Select({
          key: 'entry',
          label: 'Copy',
          autoFocus: true,
          options: entries.map((entry, i) => ({ value: String(i), label: label(entry, i) })),
          onSelect: async (value) => {
            const entry = entries[Number(value)]
            if (!entry) return
            await $.ui.copy({ text: entry.text })
            await $.ui.close({ id: PANE })
            await $.ui.toast('Copied ' + entry.text.length + ' characters to the tmux buffer')
          },
        }),
      ],
    })
  })
}
