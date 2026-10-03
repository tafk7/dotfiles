# yank

`/yank` opens a pane listing the latest messages (newest first); Enter copies
the chosen one with `$.ui.copy`, which lands in the tmux buffer even with
`set-clipboard off`. Send it to the client clipboard with your tmux binding
(prefix `e` here).

Built-in `/copy` covers the latest reply, `/copy N`, and code blocks through the
terminal clipboard. `/yank` adds older messages of any role and the tmux
buffer path.

Needs Claude Code 2.1.287 (mods). Install:
`claude plugin install yank@tafk7`, or try it with `claude --plugin-dir plugins/yank-claude`.
Tests: `claude plugin test plugins/yank-claude`.
