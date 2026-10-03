// Claude side of agent-badge: maps Claude Code events to scripts/agent-status.sh,
// the single state writer shared with Codex. Needs Claude Code >= 2.1.287.
let interactive = false
let needs = false
let root = ''

async function send($, state, payload) {
  if (!interactive) return
  try {
    const pane = await $.env.get('TMUX_PANE')
    if (!pane || root === '') return
    await $.process.run(['bash', root + '/scripts/agent-status.sh', state, pane], {
      stdin: JSON.stringify(payload ?? {}),
      timeoutMs: 5000,
    })
  } catch {
    // The badge must never disturb the session.
  }
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    interactive = e.isInteractive === true
    needs = false
    root = String(await $.plugin.root)
    return next(e)
  })

  // Fires for /clear, /resume and compaction as well; the script ignores compaction.
  on('classic.SessionStart', async ($, e, next) => {
    needs = false
    await send($, 'session-start', e)
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    needs = false
    await send($, 'working', e)
    return next(e)
  })

  on('classic.PermissionRequest', async ($, e, next) => {
    needs = true
    await send($, 'needs', e)
    return next(e)
  })

  on('classic.PermissionDenied', async ($, e, next) => {
    needs = false
    await send($, 'working', e)
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    const out = await next(e)
    if (needs && !e.agentId) {
      needs = false
      await send($, 'working', e)
    }
    return out
  })

  on('classic.SubagentStart', async ($, e, next) => {
    await send($, 'sub-start', e)
    return next(e)
  })

  on('classic.SubagentStop', async ($, e, next) => {
    await send($, 'sub-stop', e)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (!e.agentId) {
      needs = false
      await send($, e.isAborted === true ? 'idle' : 'done', e)
    }
    return next(e)
  })

  on('classic.PreCompact', async ($, e, next) => {
    await send($, 'busy', e)
    return next(e)
  })

  on('classic.PostCompact', async ($, e, next) => {
    await send($, 'uncompact', e)
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    await send($, 'gone', e)
    return next(e)
  })
}
