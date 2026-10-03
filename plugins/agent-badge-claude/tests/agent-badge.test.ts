import { expect, test } from 'claude-code/testing'

type Run = { state: string; pane: string; stdin: string }

function wire(on, runs: Run[], pane: string | null = '%7') {
  on('env.get', () => ({ value: pane ?? undefined }))
  on('process.run', ($, e) => {
    runs.push({ state: e.argv[2], pane: e.argv[3], stdin: e.init?.stdin ?? '' })
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  on('session.start', () => ({ cwd: '/work' }))
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('tool.call', () => ({ result: 'ok' }))
  on('session.end', () => ({ sessionId: 's' }))
  on('classic.SessionStart', () => ({}))
  on('classic.PermissionRequest', () => ({}))
  on('classic.PermissionDenied', () => ({}))
  on('classic.SubagentStart', () => ({}))
  on('classic.SubagentStop', () => ({}))
  on('classic.PreCompact', () => ({}))
  on('classic.PostCompact', () => ({}))
}

const states = (runs: Run[]) => runs.map(r => r.state)
const start = ($, isInteractive = true) =>
  $.session.start({ surface: 'terminal', isInteractive, cwd: '/work' })
const complete = ($, extra = {}) =>
  $.turn.complete({ turnId: 't', answer: '', durationMs: 1, isAborted: false, usage: null, ...extra })

test('a headless session never touches the badge', async ($, on) => {
  const runs: Run[] = []
  wire(on, runs)
  await start($, false)
  await $.turn.start({ turnId: 't' })
  await complete($)
  expect(runs).toEqual([])
})

test('no tmux pane means no calls', async ($, on) => {
  const runs: Run[] = []
  wire(on, runs, null)
  await start($)
  await $.turn.start({ turnId: 't' })
  expect(runs).toEqual([])
})

test('dialog -> needs -> working, then done', async ($, on) => {
  const runs: Run[] = []
  wire(on, runs)
  await start($)
  await $.turn.start({ turnId: 't' })
  await $.classic.PermissionRequest({ tool_name: 'Bash' })
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  await $.tool.call({ tool: 'Bash', command: 'pwd' })
  await complete($)
  expect(states(runs)).toEqual(['working', 'needs', 'working', 'done'])
  expect(runs[0].pane).toBe('%7')
})

test('an aborted turn goes idle', async ($, on) => {
  const runs: Run[] = []
  wire(on, runs)
  await start($)
  await $.turn.start({ turnId: 't' })
  await complete($, { isAborted: true })
  expect(states(runs)).toEqual(['working', 'idle'])
})

test('subagent turns do not settle the pane; start/stop carry the agent id', async ($, on) => {
  const runs: Run[] = []
  wire(on, runs)
  await start($)
  await $.classic.SubagentStart({ agent_id: 'a1' })
  await complete($, { agentId: 'a1' })
  await $.classic.SubagentStop({ agent_id: 'a1' })
  expect(states(runs)).toEqual(['sub-start', 'sub-stop'])
  expect(JSON.parse(runs[0].stdin).agent_id).toBe('a1')
})

test('compaction interlude and session end', async ($, on) => {
  const runs: Run[] = []
  wire(on, runs)
  await start($)
  await $.classic.PreCompact({})
  await $.classic.PostCompact({})
  await $.classic.SessionStart({ source: 'clear' })
  await $.session.end({ reason: 'prompt_input_exit' })
  expect(states(runs)).toEqual(['busy', 'uncompact', 'session-start', 'gone'])
  expect(JSON.parse(runs[2].stdin).source).toBe('clear')
})

test('a failing script never breaks the event', async ($, on) => {
  on('env.get', () => ({ value: '%1' }))
  on('process.run', () => ({ deny: 'boom' }))
  on('session.start', () => ({ cwd: '/work' }))
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  await start($)
  const out = await $.turn.start({ turnId: 't' })
  expect(out.turnId).toBe('t')
})
