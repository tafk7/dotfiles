#!/usr/bin/env python3
"""One-off: move shell/shortcuts-index.tsv's wording to where keys derives it, and report.

    maintenance/migrate-shortcuts.py apply     write alias and function comments from the TSV
    maintenance/migrate-shortcuts.py report    every TSV row, where its wording went, and the
                                               summary keys now shows for it (needs a build)

Alias rows become a trailing comment on the alias; function rows a trailing
comment on the definition line, unless the function's own comment already says
it. tmux, WezTerm, Neovim, agent and line-editing rows went to bind -N notes,
wezterm.lua comments and configs/keymap/notes.toml by hand; ROWS below names
the entries each row maps to, so the report can check that every row's meaning
is still shown. Deleted with the TSV once the switch is reviewed.
"""
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
sys.path.insert(0, os.path.join(REPO, 'lib'))
TSV = os.path.join(REPO, 'shell/shortcuts-index.tsv')
SHELL = ('git', 'shell', 'docker', 'python', 'node', 'vscode', 'wsl')

# Wording that differs from the row's: a fuller sentence, a dropped command, a merged row.
WORDING = {
    'cl': 'Start a new Claude session', 'clc': 'Continue the last Claude session', 'clp': 'Run a one-off Claude prompt',
    'cla': 'Claude agent view: background sessions', 'cll': 'Claude with project and local settings only (no global ones)',
    'cllc': 'Continue a Claude session with project and local settings only', 'cllp': 'One-off Claude prompt with project and local settings only',
    'cx': 'Start a new Codex session', 'cxr': 'Resume a Codex session (picker)', 'cxc': 'Continue the last Codex session',
    'cxp': 'Run a one-off Codex prompt', 'cxa': 'Codex agent sessions (shared app-server daemon)',
    'cxh': 'Codex with the alternate config dir (~/.codex-alt)', 'cxhr': 'Resume Codex (alternate config dir, picker)',
    'cxhc': 'Continue the last Codex session (alternate config dir)', 'cxhp': 'One-off Codex prompt (alternate config dir)',
    'oc': 'Launch the OpenCode TUI (new session)', 'ocr': 'Run a one-off OpenCode prompt', 'ocrc': 'One-off OpenCode prompt, continuing the last session',
    'pic': 'Continue the most recent pi session', 'pir': 'Browse and pick a past pi session',
    'dprune': 'Remove unused containers and images (asks first)', 'dprunea': 'Remove all unused Docker resources (asks first)',
    'view': 'Syntax-highlighted file viewer (bat)', 'cheat': 'The keys lookup, by its old name',
    'top': 'System monitor (btop)', 'venv': 'Create .venv (with uv when it is installed)',
    'pipreqs': 'Install from requirements.txt (with uv when it is installed)',
    'nclean': 'Clean reinstall: delete node_modules, then npm ci (or npm install without a lockfile)',
    'explorer': 'Open Explorer (the current directory by default)', 'open': 'Same as explorer',
    'pwsh': 'PowerShell (7 if installed, otherwise 5)', 'll': 'Long listing with timestamps',
    'la': 'Long listing including hidden files', 'l': 'Compact column listing', 'tree': 'Recursive directory tree',
    'tr': 'Resume the most recently used tmux session (no args; inside tmux, the last session)',
    'reload': 'Restart the shell in place with fresh config (--soft re-sources instead)',
    'killport': 'Kill the process on a port (--force skips the question)',
    'md': 'Render Markdown in the terminal (paged when interactive)',
    'p': 'Print the canonical current directory, or resolve the paths given',
    'yo': 'Print a command\'s output and copy it to the clipboard',
    '..': 'Go up N directories (default 1)',
}
# Rows whose name is no alias or function: where their meaning lives instead.
ALSO = {'bat': 'alias:view'}

# Every other row: the entries that carry its meaning (bind -N, comments, notes.toml, derived headers).
ROWS = {
    ('git', 'git profile'): ['cmd:git-profile', 'cmd:git profile use', 'cmd:git profile whoami'],
    ('tmux', 'Alt+E / Alt+D'): ['tmux:alt+e', 'tmux:alt+d'],
    ('tmux', 'Alt+S / Alt+F'): ['tmux:alt+s', 'tmux:alt+f'],
    ('tmux', 'Alt+Shift+S / Alt+Shift+F'): ['tmux:alt+shift+s', 'tmux:alt+shift+f'],
    ('tmux', 'Alt+arrows'): ['tmux:alt+up', 'tmux:alt+down', 'tmux:alt+left', 'tmux:alt+right'],
    ('tmux', 'PgUp'): ['tmux:pageup'],
    ('tmux', 'Shift+PgUp / Shift+PgDn'): ['tmux:shift+pageup', 'tmux:shift+pagedown'],
    ('tmux', 'Ctrl+Home'): ['tmux:ctrl+home'],
    ('tmux', 'Alt+1-0'): ['group:window-n'],
    ('tmux', 'Alt+Shift+W'): ['tmux:alt+shift+w'],
    ('tmux', 'Alt+Shift+T'): ['tmux:alt+shift+t'],
    ('tmux', 'Alt+V'): ['tmux:alt+v'],
    ('tmux', 'Ctrl+G (Claude, Codex) / Ctrl+X E (OpenCode)'): ['tip:compose-editor-key'],
    ('tmux', ':q / :wq / :cq (compose on an agent)'): ['tip:compose-return'],
    ('tmux', 'Alt+Shift+V'): ['tmux:alt+shift+v'],
    ('tmux', 'Ctrl+S (compose)'): ['tip:compose-send'],
    ('tmux', 'Ctrl+Shift+S / ,s (compose)'): ['tip:compose-stage'],
    ('tmux', 'PgUp / PgDn / Ctrl+Home / Ctrl+End (compose)'): ['tip:compose-scroll'],
    ('tmux', 'Alt+Shift+J (Claude, Codex, OpenCode)'): ['tmux:alt+shift+j'],
    ('tmux', 'Alt+Shift+K (Claude, Codex)'): ['tmux:alt+shift+k'],
    ('tmux', 'Alt+Shift+L (Claude, Codex, OpenCode)'): ['tmux:alt+shift+l'],
    ('tmux', 'Alt+Enter'): ['tmux:alt+enter'],
    ('tmux', 'Alt+Shift+Enter'): ['tmux:alt+shift+enter'],
    ('tmux', 'Alt+Z'): ['tmux:alt+z'],
    ('tmux', 'Shift+Enter (Codex)'): ['tmux:shift+enter'],
    ('tmux', 'Alt+M (Codex)'): ['tmux:alt+m'],
    ('tmux', 'Break (Pause key)'): ['tmux:shift+f9', 'wezterm:pause'],
    ('tmux', 'Ctrl+Z'): ['tmux:ctrl+z'],
    ('tmux', 'prefix Ctrl+Z'): ['tmux-prefix:ctrl+z'],
    ('tmux', 'Ctrl+L (compose, insert)'): ['tip:compose-fix-spelling'],
    ('tmux', 'Ctrl+a ↑↓←→'): ['tmux-prefix:up', 'tmux-prefix:down', 'tmux-prefix:left', 'tmux-prefix:right'],
    ('tmux', 'Ctrl+a Alt+ESDF'): ['tmux-prefix:alt+e', 'tmux-prefix:alt+s', 'tmux-prefix:alt+d', 'tmux-prefix:alt+f'],
    ('tmux', 'Ctrl+a Shift+↑↓←→'): ['tmux-prefix:shift+up', 'tmux-prefix:shift+down', 'tmux-prefix:shift+left', 'tmux-prefix:shift+right'],
    ('tmux', 'Ctrl+a z'): ['tmux-prefix:z'], ('tmux', 'Ctrl+a q'): ['tmux-prefix:q'],
    ('tmux', 'Ctrl+a Space'): ['tmux-prefix:space'], ('tmux', 'Ctrl+a Ctrl+Space'): ['tmux-prefix:ctrl+space'],
    ('tmux', 'Ctrl+a j'): ['tmux-prefix:j'], ('tmux', 'Ctrl+a l'): ['tmux-prefix:l'], ('tmux', 'Ctrl+a g'): ['tmux-prefix:g'],
    ('tmux', 'Ctrl+a >'): ['tmux-prefix:>'], ('tmux', 'Ctrl+a -'): ['tmux-prefix:-'], ('tmux', 'Ctrl+a ='): ['tmux-prefix:='],
    ('tmux', 'Ctrl+a t'): ['tmux-prefix:t'], ('tmux', 'Ctrl+a w'): ['tmux-prefix:w'], ('tmux', 'Ctrl+a x'): ['tmux-prefix:x'],
    ('tmux', 'Ctrl+a X'): ['tmux-prefix:shift+x'], ('tmux', 'Ctrl+a n'): ['tmux-prefix:n'], ('tmux', 'Ctrl+a i'): ['tmux-prefix:i'],
    ('tmux', 'Ctrl+a <'): ['tmux-prefix:<'], ('tmux', 'Ctrl+a C'): ['tmux-prefix:shift+c'], ('tmux', 'Ctrl+a s'): ['tmux-prefix:s'],
    ('tmux', 'Ctrl+a d'): ['tmux-prefix:d'], ('tmux', 'Ctrl+a ) / ('): ['tmux-prefix:)', 'tmux-prefix:('],
    ('tmux', 'Ctrl+a $'): ['tmux-prefix:$'], ('tmux', 'Ctrl+a v'): ['tmux-prefix:v'],
    ('tmux', 'ScrollLock / Ctrl+a f'): ['tmux:shift+f5', 'tmux-prefix:f', 'wezterm:scrolllock'],
    ('tmux', 'Shift+ScrollLock / Ctrl+a /'): ['tmux:shift+f7', 'tmux-prefix:/', 'wezterm:shift+scrolllock'],
    ('tmux', 'Ctrl+a o'): ['tmux-prefix:o'],
    ('tmux', 'e / s / d / f (and arrows)'): ['tmux-copy:e', 'tmux-copy:s', 'tmux-copy:d', 'tmux-copy:f', 'tmux-copy:up'],
    ('tmux', 'E / S / D / F (and Shift+arrows)'): ['tmux-copy:shift+e', 'tmux-copy:shift+s', 'tmux-copy:shift+d',
                                                    'tmux-copy:shift+f', 'tmux-copy:shift+up'],
    ('tmux', 'Ctrl+Shift+E/S/D/F, Shift+Home/End, Ctrl+Shift+Home/End'): [
        'tmux-copy:ctrl+shift+e', 'tmux-copy:ctrl+shift+s', 'tmux-copy:shift+home', 'tmux-copy:ctrl+shift+home'],
    ('tmux', 'Ctrl+s / Ctrl+f (and Ctrl+←/→)'): ['tmux-copy:ctrl+s', 'tmux-copy:ctrl+f', 'tmux-copy:ctrl+left'],
    ('tmux', 'Ctrl+e / Ctrl+d (and Ctrl+↑/↓)'): ['tmux-copy:ctrl+e', 'tmux-copy:ctrl+d', 'tmux-copy:ctrl+up'],
    ('tmux', 'Home / End'): ['tmux-copy:home', 'tmux-copy:end'],
    ('tmux', 'PgUp / PgDn'): ['tmux-copy:pageup', 'tmux-copy:pagedown'],
    ('tmux', 'Ctrl+Home / Ctrl+End'): ['tmux-copy:ctrl+home', 'tmux-copy:ctrl+end'],
    ('tmux', '/ and ? then n / N'): ['tmux-copy:/', 'tmux-copy:?', 'tmux-copy:n', 'tmux-copy:shift+n'],
    ('tmux', 'o'): ['tmux-copy:o'], ('tmux', 'h'): ['tmux-copy:h'],
    ('tmux', 'Click (review)'): ['tmux-mouse:click@copy'],
    ('tmux', 'Esc / q'): ['tmux-copy:esc', 'tmux-copy:q'],
    ('tmux', 'Alt+Copy / y'): ['tmux:ctrl+alt+insert', 'tmux-copy:y', 'tmux-copy:ctrl+alt+insert'],
    ('tmux', 'Copy'): ['tmux:ctrl+insert', 'tmux-copy:ctrl+insert', 'wezterm:ctrl+insert'],
    ('tmux', 'Ctrl+C / Ctrl+a Ctrl+C'): ['tmux:ctrl+c', 'tmux-prefix:ctrl+c'],
    ('tmux', 'Ctrl+Backspace / Ctrl+Delete (Claude)'): ['tmux:ctrl+backspace', 'tmux:ctrl+h', 'tmux:ctrl+delete'],
    ('tmux', 'Alt+Backspace / Alt+Delete (Claude)'): ['tmux:alt+backspace', 'tmux:alt+delete'],
    ('tmux', 'Alt+Paste'): ['tmux:alt+shift+insert'],
    ('tmux', 'Click an inactive pane'): ['tmux-mouse:click'],
    ('tmux', 'Alt+click'): ['tmux-mouse:alt+click'],
    ('tmux', 'Alt+mouse drag'): ['tmux-mouse:alt+drag'],
    ('tmux', 'Alt+double-click'): ['tmux-mouse:alt+double-click'],
    ('tmux', 'Alt+triple-click'): ['tmux-mouse:alt+triple-click'],
    ('tmux', 'Shift+mouse drag'): ['tip:wezterm-select'],
    ('tmux', 'Ctrl+a p'): ['tmux-prefix:p'],
    ('tmux', 'Ctrl+a y / Shift+Copy'): ['tmux-prefix:y', 'tmux:ctrl+shift+insert', 'wezterm:ctrl+shift+insert'],
    ('tmux', 'Ctrl+a e'): ['tmux-prefix:e'], ('tmux', 'Ctrl+a r'): ['tmux-prefix:r'],
    ('tmux', 'Ctrl+a R'): ['tmux-prefix:shift+r'], ('tmux', 'Ctrl+a Ctrl+l'): ['tmux-prefix:ctrl+l'],
    ('tmux', 'Ctrl+a ?'): ['tmux-prefix:?'],
    ('wezterm', 'Ctrl+Shift+Enter'): ['wezterm:ctrl+shift+enter'],
    ('wezterm', 'Ctrl+Shift+= / Ctrl+Shift+- / Ctrl+Shift+0'): ['wezterm:ctrl+shift+=', 'wezterm:ctrl+shift+-', 'wezterm:ctrl+shift+0'],
    ('wezterm', 'Image key (Ctrl+Alt+V)'): ['wezterm:ctrl+alt+v'],
    ('vim', 'Ctrl+P'): ['nvim:ctrl+p@n'], ('vim', ',f'): ['nvim:, f@n'], ('vim', ',b'): ['nvim:, b@n'],
    ('vim', ',g'): ['nvim:, g@n'], ('vim', ',gs'): ['nvim:, g s@n'], ('vim', ',gd'): ['nvim:, g d@n'],
    ('vim', ',gc'): ['nvim:, g c@n'], ('vim', ',gb'): ['nvim:, g b@n'], ('vim', ',hn'): ['nvim:, h n@n'],
    ('vim', ',hp'): ['nvim:, h p@n'], ('vim', ',hs'): ['nvim:, h s@n'], ('vim', ',hu'): ['nvim:, h u@n'],
    ('vim', 'jk'): ['nvim:j k@i'],
    ('vim', 'Alt+Backspace / Alt+Delete'): ['nvim:alt+backspace@i', 'nvim:alt+delete@i'],
    ('vim', 'Ctrl+Backspace / Ctrl+Delete'): ['nvim:ctrl+backspace@i', 'nvim:ctrl+delete@i'],
    ('vim', 'Shift+PgUp / Shift+PgDn'): ['nvim:shift+pageup@n', 'nvim:shift+pagedown@n'],
    ('vim', 'Ctrl+Z'): ['nvim:ctrl+z@n', 'nvim:ctrl+z@i', 'nvim:ctrl+z@x'],
    ('vim', ',/'): ['nvim:, /@n'], ('vim', 'gc'): ['tip:vim-comment-motion'],
    ('vim', ',w'): ['nvim:, w@n'], ('vim', ',q'): ['nvim:, q@n'], ('vim', ',Q'): ['nvim:, Q@n'],
    ('vim', ',n'): ['nvim:, n@n'], ('vim', ',ss'): ['nvim:, s s@n'], ('vim', 'Space'): ['nvim:space@n'],
    ('vim', 'cs"\''): ['nvim:c s@n'], ('vim', 'ds"'): ['nvim:d s@n'], ('vim', 'ysiw"'): ['nvim:y s@n'],
    ('vim', 'Ctrl+E'): ['nvim:ctrl+e@n'], ('vim', 'Ctrl+S'): ['nvim:ctrl+s@n'], ('vim', 'Ctrl+D'): ['nvim:ctrl+d@n'],
    ('vim', 'Ctrl+F'): ['nvim:ctrl+f@n'],
    ('vim', ',af'): None, ('vim', ',an'): None,
    ('vim', ':Theme'): ['tip:vim-theme'],
    ('shell', 'Ctrl+Backspace'): ['shell:ctrl+backspace'], ('shell', 'Ctrl+Delete'): ['shell:ctrl+delete'],
    ('shell', 'Ctrl+Z'): ['shell:ctrl+z'], ('shell', 'Alt+Backspace'): ['shell:alt+backspace'],
    ('shell', 'Alt+Delete'): ['shell:alt+delete'],
    ('shell', 'Ctrl+Shift+Backspace'): ['shell:shift+f1', 'wezterm:ctrl+shift+backspace'],
    ('shell', 'Ctrl+Shift+Delete'): ['shell:shift+f2', 'wezterm:ctrl+shift+delete'],
    ('shell', 'Alt+Shift+Backspace'): ['shell:shift+f3', 'wezterm:alt+shift+backspace'],
    ('shell', 'Alt+Shift+Delete'): ['shell:shift+f4', 'wezterm:alt+shift+delete'],
    ('shell', 'Shift+Tab'): ['zsh:shift+tab'], ('shell', 'Alt+I'): ['shell:alt+i'],
    ('shell', 'Alt+Shift+I'): ['shell:alt+shift+i'],
    ('shell', 'keymap open'): ['cmd:keys open'], ('shell', 'keymap why'): ['cmd:keys why'],
    ('shell', 'keymap free'): ['cmd:keys free'],
    ('shell', 'theme-window'): ['tip:theme-window'], ('shell', 'theme-window-clear'): ['tip:theme-window-clear'],
    ('shell', 'theme-current'): ['tip:theme-current'], ('shell', 'theme-nvim'): ['tip:theme-nvim'],
    ('shell', 'dotfiles bump'): ['tip:dotfiles-bump'], ('shell', 'dotfiles update'): ['tip:dotfiles-update'],
    ('shell', 'dotfiles apply'): ['tip:dotfiles-apply'], ('shell', 'dotfiles upgrade'): ['tip:dotfiles-upgrade'],
    ('shell', 'dotfiles refresh'): ['tip:dotfiles-refresh'], ('shell', 'dotfiles profile'): ['tip:dotfiles-profile'],
    ('shell', 'dotfiles verify'): ['tip:dotfiles-verify'], ('shell', 'verify'): ['cmd:verify'],
    ('shell', 'diff-config'): ['cmd:diff-config'], ('shell', 'check-updates'): ['cmd:check-updates'],
    ('shell', 'uninstall-tool'): ['cmd:uninstall-tool'], ('shell', 'install-git-hooks'): ['cmd:install-git-hooks'],
    ('claude', 'Alt+M'): ['claude:alt+m@Chat'],
    ('claude', 'Ctrl+PgUp / Ctrl+PgDn'): ['claude:ctrl+pageup@Chat', 'claude:ctrl+pagedown@Chat'],
    ('codex', 'Ctrl+G'): ['codex:ctrl+g@global'], ('codex', 'F7'): ['codex:f7@chat'],
    ('codex', 'Ctrl+PgUp / Ctrl+PgDn'): ['codex:ctrl+pageup@chat', 'codex:ctrl+pagedown@chat'],
    ('opencode', 'Ctrl+Home / Ctrl+End'): ['opencode:ctrl+home', 'opencode:ctrl+end'],
    ('opencode', 'Home / End'): ['opencode:home', 'opencode:end'],
    ('opencode', 'Ctrl+Tab'): ['opencode:ctrl+tab'], ('opencode', 'Alt+M'): ['opencode:alt+m'],
    ('opencode', 'Ctrl+PgUp / Ctrl+PgDn'): ['opencode:ctrl+pageup', 'opencode:ctrl+pagedown'],
    ('opencode', 'Ctrl+Z'): ['opencode:ctrl+z'], ('opencode', 'Ctrl+Up / Ctrl+Down'): ['opencode:ctrl+up', 'opencode:ctrl+down'],
    ('opencode', 'Ctrl+C'): ['opencode:ctrl+c'], ('opencode', 'Ctrl+R'): ['tip:opencode-ctrl-r'],
    ('pi', 'Alt+M'): ['pi:alt+m@app.model'], ('pi', 'Ctrl+PgUp / Ctrl+PgDn'): ['pi:ctrl+pageup@app.thinking', 'pi:ctrl+pagedown@app.thinking'],
    ('pi', 'Ctrl+Z'): ['pi:ctrl+z@tui.editor'], ('pi', 'Alt+Z'): ['pi:alt+z@app.session'],
    ('pi', 'Shift+PgUp / Shift+PgDn'): ['pi:shift+pageup@tui.altScreen', 'pi:shift+pagedown@tui.altScreen'],
    ('python', 'pip install -e'): ['tip:pip-editable'],
    ('python', 'uv python list'): ['tip:uv-python-list'], ('python', 'uv python install'): ['tip:uv-python-install'],
    ('python', 'uv python pin'): ['tip:uv-python-pin'], ('python', 'uv venv'): ['tip:uv-venv'],
    ('diagramming', 'dot'): ['tip:graphviz-dot'],
}
DROPPED = {
    ('vim', ',af'): 'no such mapping: configs/init.vim no longer has ALE or its maps',
    ('vim', ',an'): 'no such mapping: configs/init.vim no longer has ALE or its maps',
}


def rows():
    out = []
    with open(TSV) as f:
        for line in f:
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            out.append(tuple(line.split('│')))
    return out


def name_of(shortcut):
    return re.split(r'\s+[\[<]', shortcut)[0].strip()


def definition_lines(name):
    """[(path, index, kind)] where NAME is defined as an alias or function in shell/."""
    from keymap import names
    hits = []
    for sub in ('shell/tools', 'shell/platform'):
        for f in sorted(os.listdir(os.path.join(REPO, sub))):
            path = os.path.join(REPO, sub, f)
            lines = open(path).read().split('\n')
            for i, line in enumerate(lines):
                m = names.ALIAS.match(line)
                if m and m.group(1) == name:
                    hits.append((path, i, 'alias'))
                m = names.FUNC.match(line)
                if m and m.group(1) == name:
                    hits.append((path, i, 'function'))
    return hits


def apply():
    from keymap import names
    changed = 0
    for cat, shortcut, desc, _ in rows():
        if cat not in SHELL:
            continue
        name = name_of(shortcut)
        hits = definition_lines(name)
        if not hits:
            continue
        path, i, kind = hits[0]
        lines = open(path).read().split('\n')
        words = WORDING.get(name, desc)
        if kind == 'function':
            derived = {e['id']: e for e in names.shell(REPO)}.get('fn:' + name, {})
            if derived.get('summary') and name not in WORDING:
                continue  # its own comment already says it
            # a comment that says it replaces the old one-line comment above
            if i and lines[i - 1].lstrip().startswith('#') and (i < 2 or not lines[i - 2].strip()) and name in WORDING:
                lines[i - 1] = re.match(r'\s*', lines[i - 1]).group(0) + '# ' + words
            else:
                lines[i] = re.sub(r'\s+#\s.*$', '', lines[i]) + '  # ' + words
        else:
            m = names.ALIAS.match(lines[i])
            lines[i] = lines[i][:m.end()] + '  # ' + words
        open(path, 'w').write('\n'.join(lines))
        changed += 1
    print(f'{changed} definitions described')


def report(out):
    env = dict(os.environ)
    idx = subprocess.run([os.path.join(REPO, 'bin/keys'), 'ls', '--json', '--all'], capture_output=True, text=True, env=env)
    found = {e['id']: e for e in json.loads(idx.stdout)}
    groups = subprocess.run([os.path.join(REPO, 'bin/keys'), 'ls', '--json'], capture_output=True, text=True, env=env)
    found.update({e['id']: e for e in json.loads(groups.stdout) if e['id'].startswith('group:')})
    tally, problems, lines = {}, [], []
    for cat, shortcut, desc, cmd in rows():
        ids = ROWS.get((cat, shortcut))
        if (cat, shortcut) in DROPPED:
            dest, ids = 'dropped: ' + DROPPED[(cat, shortcut)], []
        elif ids is None and cat in SHELL:
            name = name_of(shortcut)
            ids = [i for i in (ALSO.get(name), 'alias:' + name, 'fn:' + name) if i and i in found][:1]
            dest = 'comment'
        else:
            dest = None
        shown = []
        for i in ids or []:
            e = found.get(i)
            if not e:
                problems.append(f'{cat}│{shortcut}: {i} not in the index')
                continue
            shown.append(f"{i} [{e['via']}] {e['summary']}")
            if dest is None:
                dest = {'tmux-N': 'bind -N', 'comment': 'comment', 'note': 'notes.toml', 'docstring': 'docstring',
                        'desc': 'desc'}.get(e['via'], e['via'])
                if i.startswith('tip:'):
                    dest = 'notes.toml tip'
                elif i.startswith('wezterm:') and e['via'] == 'comment':
                    dest = 'wezterm.lua comment'
                elif i.startswith('cmd:') and e['via'] == 'comment':
                    dest = 'bin/ header'
        if not ids and not dest.startswith('dropped'):
            problems.append(f'{cat}│{shortcut}: no destination')
        if ids and not shown:
            dest = 'MISSING'
        tally[dest] = tally.get(dest, 0) + 1
        lines.append(f'{cat}│{shortcut}│{desc}\n    -> {dest}: ' + ('\n       '.join(shown) or '-'))
    with open(out, 'w') as f:
        f.write(f'{len(rows())} rows\n')
        for k, v in sorted(tally.items(), key=lambda x: -x[1]):
            f.write(f'  {v:4}  {k}\n')
        f.write('\nproblems:\n' + '\n'.join(problems or ['  none']) + '\n\n')
        f.write('\n'.join(lines) + '\n')
    print(open(out).read().split('\n\n')[0])
    print('problems:', len(problems))
    return 1 if problems else 0


if __name__ == '__main__':
    if sys.argv[1:2] == ['apply']:
        apply()
    elif sys.argv[1:2] == ['report']:
        sys.exit(report(sys.argv[2] if len(sys.argv) > 2 else '/dev/stdout'))
    else:
        print(__doc__)
