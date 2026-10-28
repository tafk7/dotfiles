"""Trace a chord through Windows, WezTerm and tmux to each pane program, and judge the results.

A pane program is reached only if no outer layer takes the chord. tmux rules
that test the pane (#{pane_current_command}, #{alternate_on}, ...) are evaluated
per program, and the terminal's key encoding can merge chords on the way in
(a program that asks for no extended keys hears Ctrl+Shift+G as Ctrl+G).
"""
import re

from . import chord

# Pane programs: what tmux's conditions see, and which keys the program can hear.
# kmode: legacy (plain VT keys), mok1 (modifyOtherKeys 1), mok2 (every chord distinct).
APPS = {
    'shell':    dict(label='bash', cmd='bash', alt='0', mouse='0', kmode='legacy'),
    'fzf':      dict(label='fzf', cmd='fzf', alt='0', mouse='1', kmode='legacy'),
    'nvim':     dict(label='Neovim', cmd='nvim', alt='1', mouse='1', kmode='mok2'),
    'copy':     dict(label='tmux copy mode', cmd='bash', alt='0', mouse='0', kmode='mok2', in_mode=True),
    'claude':   dict(label='Claude Code', cmd='claude', alt='1', mouse='1', kmode='mok2'),
    'codex':    dict(label='Codex', cmd='codex', alt='1', mouse='1', kmode='legacy'),
    'opencode': dict(label='OpenCode', cmd='opencode', alt='1', mouse='1', kmode='mok1'),
    'pi':       dict(label='pi', cmd='pi', alt='1', mouse='1', kmode='mok2'),
}
KMODE_NOTE = {
    'legacy': 'plain keys: Ctrl+Shift+letter arrives as Ctrl+letter, Shift+Enter and Ctrl+Enter as Enter, Ctrl+I as Tab',
    'mok1': 'modifyOtherKeys 1: Ctrl+Shift+letter arrives as Ctrl+letter, Ctrl+I as Tab',
    'mok2': 'modifyOtherKeys 2: every chord arrives distinct',
}
# Where contexts overlap on one screen the earlier wins (Codex: the composer's Enter submits
# before the editor's Enter can add a line).
PRECEDENCE = {'codex': ['fixed', 'composer', 'chat', 'global', 'editor']}
ALIAS_KEYS = {
    'legacy': [{'ctrl+h', 'ctrl+backspace'}, {'ctrl+_', 'ctrl+/', 'ctrl+-'}, {'enter', 'ctrl+m'},
               {'tab', 'ctrl+i'}, {'esc', 'ctrl+['}],
    'mok1': [{'tab', 'ctrl+i'}],
    'mok2': [],
}
# WezTerm on Windows has no names for these keys: only a binding by key code
# (raw:145, raw:19 in configs/wezterm.lua) sees them.
WEZTERM_DEAF = {'scrolllock', 'pause'}


# --- tmux command parsing and format evaluation -------------------------------------------------
def match_brace(s, i):
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '{':
            depth += 1
        elif s[j] == '}':
            depth -= 1
            if depth == 0:
                return j
    return len(s) - 1


def tokens(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c.isspace():
            i += 1
        elif c in '"\'':
            j, buf = i + 1, ''
            while j < len(s) and s[j] != c:
                if s[j] == '\\' and c == '"' and j + 1 < len(s):
                    octal = re.match(r'[0-7]{3}', s[j + 1:j + 4])
                    buf += chr(int(octal.group(0), 8)) if octal else s[j + 1]
                    j += 4 if octal else 2
                    continue
                buf += s[j]
                j += 1
            out.append(buf)
            i = j + 1
        elif c == '{':
            j = match_brace(s, i)
            out.append(s[i + 1:j].strip())
            i = j + 1
        else:
            j = i
            while j < len(s) and not s[j].isspace():
                j += 1
            tok = s[i:j]
            out.append(';' if tok in ('\\;', ';') else tok)
            i = j
    return out


def split_args(s):
    args, depth, cur, i = [], 0, '', 0
    while i < len(s):
        if s.startswith('#{', i):
            depth += 1
            cur += '#{'
            i += 2
            continue
        c = s[i]
        if c == '}' and depth:
            depth -= 1
        if c == ',' and depth == 0:
            args.append(cur)
            cur = ''
        else:
            cur += c
        i += 1
    return args + [cur]


def truthy(v):
    return v not in ('', '0')


def fmt(s, ctx):
    out, i = '', 0
    while i < len(s):
        if s.startswith('#{', i):
            j = match_brace(s, i + 1)
            out += expr(s[i + 2:j], ctx)
            i = j + 1
        else:
            out += s[i]
            i += 1
    return out


def expr(e, ctx):
    if e.startswith('?'):
        a = split_args(e[1:])
        cv = fmt(a[0], ctx) if '#{' in a[0] else ctx.get(a[0], '')
        return fmt(a[1] if truthy(cv) else (a[2] if len(a) > 2 else ''), ctx)
    m = re.match(r'(&&|\|\||==|!=|!|>|<|m/r|m):', e)
    if not m:
        return ctx.get(e, '')
    op, args = m.group(1), [fmt(a, ctx) for a in split_args(e[m.end():])]
    if op == '&&':
        return '1' if all(truthy(a) for a in args) else '0'
    if op == '||':
        return '1' if any(truthy(a) for a in args) else '0'
    if op == '==':
        return '1' if args[0] == args[1] else '0'
    if op == '!=':
        return '1' if args[0] != args[1] else '0'
    if op == '!':
        return '0' if truthy(args[0]) else '1'
    if op in '<>':
        try:
            return '1' if (int(args[0]) > int(args[1])) == (op == '>') else '0'
        except ValueError:
            return '0'
    return '1' if re.search(args[0], args[1]) else '0'


def pane_ctx(app):
    a = APPS[app]
    return {'pane_current_command': a['cmd'], 'pane_in_mode': '1' if a.get('in_mode') else '0',
            'pane_mode': 'copy-mode' if a.get('in_mode') else '', 'alternate_on': a['alt'],
            'mouse_any_flag': a['mouse'], 'session_windows': '3', 'window_index': '2', 'pane_at_top': '0',
            'pane_at_bottom': '0', 'pane_at_left': '0', 'pane_at_right': '0', 'selection_present': '0',
            'pane_floating_flag': '0', 'floating_pane_flag': '0'}


FRIENDLY = [  # first match wins
    (r'^display-menu', 'menu', 'menu'),
    (r'join-pane \} \{ break-pane', 'float-toggle', 'float / tile pane'),
    (r'switch-mode -kw', 'win-switcher', 'window switcher'),
    (r'switch-mode -ks', 'sess-switcher', 'session switcher'),
    (r'tmux-compose" toggle', 'compose', 'compose box'),
    (r'tmux-compose" fullscreen', 'compose-full', 'prompt in nvim, full pane'),
    (r'tmux-last-reply', 'last-reply', 'copy last reply'),
    (r'tmux-review', 'review', 'review transcript'),
    (r'tmux-copy', 'export', 'buffer to clipboard'),
    (r'@clipboard-export', 'clip-export', 'toggle clipboard export'),
    (r'send -X cancel', 'copy-toggle', 'copy mode on/off'),
    (r'select-pane -U', 'focus-up', 'focus pane above'),
    (r'select-pane -D', 'focus-down', 'focus pane below'),
    (r'previous-window ; select-pane|select-pane -L', 'focus-left', 'focus pane left'),
    (r'next-window ; select-pane|select-pane -R', 'focus-right', 'focus pane right'),
    (r'select-pane -m', 'mark', 'mark pane'),
    (r'select-pane -M', 'unmark', 'clear mark'),
    (r'select-pane -T', 'pane-title', 'pane title'),
    (r'select-window -t "?\{end\}', 'window-last', 'last window'),
    (r'select-window -t "?\{start\}', 'window-first', 'first window'),
    (r'select-window -t :?=?(\d+)', 'window-n', 'window {0}'),
    (r'new-window', 'new-window', 'new window'),
    (r'new-session', 'new-session', 'new session'),
    (r'choose-tree', 'tree', 'session tree'),
    (r'choose-client', 'clients', 'choose client'),
    (r'choose-buffer', 'buffers', 'choose buffer'),
    (r'paste-buffer', 'paste-buffer', 'paste tmux buffer'),
    (r'copy-mode -eu', 'page-up', 'copy mode, page up'),
    (r'history-top', 'history-top', 'copy mode, top'),
    (r'^copy-mode', 'copy-mode', 'enter copy mode'),
    (r'resize-pane -Z', 'zoom', 'zoom pane'),
    (r'resize-pane', 'resize', 'resize pane'),
    (r'split-window', 'split', 'split pane'),
    (r'switch-client -p', 'session-prev', 'previous session'),
    (r'switch-client -n', 'session-next', 'next session'),
    (r'switch-client -l', 'session-last', 'last session'),
    (r'detach-client', 'detach', 'detach'),
    (r'suspend-client', 'suspend', 'suspend client'),
    (r'kill-window', 'kill-window', 'kill window'),
    (r'kill-pane', 'kill-pane', 'kill pane'),
    (r'rename-session', 'rename-session', 'rename session'),
    (r'rename-window', 'rename-window', 'rename window'),
    (r'last-window', 'last-used-window', 'last used window'),
    (r'next-window', 'next-window', 'next window'),
    (r'previous-window', 'prev-window', 'previous window'),
    (r'display-panes', 'pane-numbers', 'pane numbers'),
    (r'list-keys', 'list-keys', 'list keys'),
    (r'clock-mode', 'clock', 'clock'),
    (r'swap-pane', 'swap-pane', 'swap pane'),
    (r'break-pane', 'break-pane', 'pane to window'),
    (r'join-pane', 'join-pane', 'join pane'),
    (r'rotate-window', 'rotate', 'rotate panes'),
    (r'next-layout', 'next-layout', 'next layout'),
    (r'previous-layout', 'prev-layout', 'previous layout'),
    (r'select-layout', 'layout', 'layout'),
    (r'source-file', 'reload', 'reload config'),
    (r'new-pane', 'float', 'floating pane'),
    (r'synchronize-panes', 'sync', 'sync panes'),
    (r'show-messages', 'messages', 'messages'),
    (r'customize-mode', 'customize', 'options editor'),
    (r'clear-history', 'clear-history', 'clear history'),
    (r'command-prompt', 'prompt', 'command prompt'),
    (r'refresh-client', 'refresh', 'refresh'),
    (r'send-prefix', 'send-prefix', 'send Ctrl+A'),
    (r'display-message', 'info', 'show info'),
]


def friendly(cmd):
    for pat, fid, label in FRIENDLY:
        m = re.search(pat, cmd)
        if m:
            return fid + ('-' + m.group(1) if m.groups() else ''), label.format(*m.groups())
    return (cmd.split() or [cmd])[0], cmd[:48]


def run_tmux(cmd, ctx):
    """Evaluate one binding's command list for a pane: (chords sent on, tmux effects)."""
    sends, effects, cmds, cur = [], [], [], []
    for t in tokens(cmd):
        if t == ';':
            cmds.append(cur)
            cur = []
        else:
            cur.append(t)
    cmds.append(cur)
    for c in cmds:
        if not c:
            continue
        if c[0] in ('if-shell', 'if'):
            args, i = c[1:], 0
            while i < len(args) and args[i].startswith('-') and len(args[i]) == 2:
                i += 2 if args[i] == '-t' else 1
            cond, branches = args[i], args[i + 1:]
            chosen = branches[0] if truthy(fmt(cond, ctx)) else (branches[1] if len(branches) > 1 else '')
            s, e = run_tmux(chosen, ctx)
            sends += s
            effects += e
        elif c[0] in ('send-keys', 'send'):
            args, keys, i, xcmd = c[1:], [], 0, None
            while i < len(args):
                a = args[i]
                if a in ('-t', '-N'):
                    i += 2
                elif a == '-X':
                    xcmd = args[i + 1] if i + 1 < len(args) else ''
                    i += 2
                elif a.startswith('-'):
                    i += 1
                else:
                    keys.append(a)
                    i += 1
            if xcmd:
                effects.append(('copy-' + xcmd, 'copy mode: ' + xcmd))
            else:
                sends += [chord.tmux(k) for k in keys]
        else:
            effects.append(friendly(' '.join(c)))
    return sends, list(dict.fromkeys(effects))


def scroll_effect(app, direction):
    """bin/tmux-scroll's dispatch for one pane program."""
    a = APPS[app]
    if a.get('in_mode'):
        return 'consume', f'scroll-lines-{direction}', f'copy mode, 3 lines {direction}'
    if a['cmd'] in ('claude', 'codex', 'opencode') and a['mouse'] == '1':
        return 'consume', f'scroll-lines-{direction}', f'3 lines {direction} (wheel events)'
    if a['alt'] == '0' and a['mouse'] == '0':
        if direction == 'up':
            return 'consume', 'scroll-lines-up', 'copy mode, 3 lines up'
        return 'consume', 'nothing', 'nothing (no history below)'
    return 'pass', None, 'passes the key on'


# --- Key encoding -------------------------------------------------------------------------------------
def encode(k, kmode):
    if kmode == 'mok2':
        return k
    mods, key = chord.split(k)
    if {'ctrl', 'shift'} <= mods and len(key) == 1 and key.isalpha():
        mods.discard('shift')
    if 'ctrl' in mods and key in ('i', 'm', '['):
        mods.discard('ctrl')
        key = {'i': 'tab', 'm': 'enter', '[': 'esc'}[key]
    if kmode == 'legacy':
        if key == 'enter':
            mods -= {'ctrl', 'shift'}
        elif key == 'tab':
            mods.discard('ctrl')
        elif key == 'space':
            mods.discard('shift')  # Ctrl+Space still sends NUL
        if key == 'backspace' and 'ctrl' in mods:
            key = 'h'
        if key in ('/', '-') and 'ctrl' in mods:
            key = '_'
    return chord.make(mods, key)


def aliases(k, kmode):
    """Chords a pane cannot tell apart from k; modifiers outside the group carry over."""
    out = {k}
    mods, key = chord.split(k)
    for group in ALIAS_KEYS[kmode]:
        for g in group:
            gm, gk = chord.split(g)
            if key == gk and gm <= mods:
                extra = mods - gm
                out |= {chord.make(extra | chord.split(o)[0], chord.split(o)[1]) for o in group}
    return out


# --- The model -------------------------------------------------------------------------------------------
class Model:
    def __init__(self, bindings, tmux_meta, keyboard):
        self.kb = keyboard
        self.apps = {a: dict(v) for a, v in APPS.items()}
        if tmux_meta.get('extended_keys_format') == 'csi-u':
            self.apps['codex']['kmode'] = 'mok2'  # Codex asks for modifyOtherKeys 2 only under csi-u
        self.windows = {b.chord: b for b in bindings if b.layer == 'windows'}
        self.wez = {b.chord: b for b in bindings if b.layer == 'wezterm'}
        self.root = {b.chord: b for b in bindings if b.layer == 'tmux'}
        self.prefix = {b.chord: b for b in bindings if b.layer == 'tmux-prefix'}
        self.app_bindings = {a: {} for a in APPS}
        for b in bindings:
            app = 'copy' if b.layer == 'tmux-copy' else b.layer
            if app in self.app_bindings:
                action = b.action
                if app == 'copy':
                    m = re.search(r'send-keys -X (\S+)', b.action)
                    action = m.group(1) if m else b.action[:60]
                if 'super' in b.chord.split(' ')[0] or 'wheel' in b.chord:
                    continue
                self.app_bindings[app].setdefault(b.chord, []).append(
                    [b.context, action, b.origin, b.primary])

    def lookup(self, app, k):
        kmode = self.apps[app]['kmode']
        hits = []
        for other in sorted(aliases(k, kmode)):
            hits += self.app_bindings[app].get(other, [])
        order = PRECEDENCE.get(app, [])
        hits.sort(key=lambda h: (not h[3], order.index(h[0]) if h[0] in order else len(order)))
        if order and hits and hits[0][0] in order:
            hits = [h for h in hits if h[0] == hits[0][0]] + [h for h in hits if not h[3]]
        seq = [[ctx, f'{action} (after {ch})', origin, prim] for ch, lst in self.app_bindings[app].items()
               if ch.startswith(k + ' ') for ctx, action, origin, prim in lst]
        return hits, seq

    def route(self, p, app):
        """{hops: [[layer, kind, detail, chord-after, note?]], effects: [[owner, ...]], delivered}"""
        a, k, hops = self.apps[app], p, []
        mods, _ = chord.split(k)
        if 'super' in mods or k in self.windows:
            label = self.windows[k].action if k in self.windows else 'Win-key shortcut'
            hops.append(['windows', 'consume', label, None])
            return dict(hops=hops, effects=[['windows', label]], delivered=None)
        if chord.split(k)[1] in WEZTERM_DEAF and k not in self.wez:
            hops.append(['wezterm', 'consume', 'never delivered: WezTerm does not receive this key', None])
            return dict(hops=hops, effects=[['wezterm', 'not delivered']], delivered=None)
        w = self.wez.get(k)
        if w:
            if w.kind == 'translate':
                k = w.to[0]
                hops.append(['wezterm', 'rewrite', f'sends {k}', k])
            elif w.kind == 'conditional':
                hops.append(['wezterm', 'cond', 'copies a WezTerm selection; with none, passes', k])
            else:
                hops.append(['wezterm', 'consume', w.action, None])
                return dict(hops=hops, effects=[['wezterm', w.action]], delivered=None)
        if k == 'ctrl+a':
            hops.append(['tmux', 'consume', 'prefix: the next key goes to the prefix table', None])
            return dict(hops=hops, effects=[['tmux', 'prefix', 'prefix']], delivered=None)
        t = self.root.get(k)
        if t:
            cmd = t.action
            if 'tmux-scroll' in cmd:
                kind, fid, label = scroll_effect(app, 'up' if ' up ' in cmd else 'down')
                if kind == 'consume':
                    hops.append(['tmux', 'consume', label, None])
                    return dict(hops=hops, effects=[['tmux', fid, label]], delivered=None)
                hops.append(['tmux', 'cond', 'tmux-scroll: ' + label, k])
            else:
                patterns = re.findall(r'#\{m/r:([^,]+),#\{pane_current_command\}\}', cmd)
                named = [self.apps[x]['label'] for x in APPS if x != 'copy' and (
                    f"pane_current_command}},{APPS[x]['cmd']}}}" in cmd or
                    any(re.fullmatch(p, APPS[x]['cmd']) for p in patterns))]
                mine = self.apps[app]['label'] in named
                rule = (f' (rule for {", ".join(named)})' if mine else
                        f' (fallback for programs other than {", ".join(named)})' if named else '')
                sends, effects = run_tmux(cmd, pane_ctx(app))
                if effects or not sends:
                    label = '; '.join(e[1] for e in effects) or 'nothing here (edge of the layout)'
                    hops.append(['tmux', 'consume', label, None])
                    return dict(hops=hops, effects=[['tmux', e[0], e[1]] for e in effects] or [['tmux', 'nothing', 'nothing']],
                                delivered=None)
                if sends == [k]:
                    hops.append(['tmux', 'cond', 'passes the key on' + rule, k])
                else:
                    k = ' '.join(sends)
                    hops.append(['tmux', 'rewrite', f'sends {k}' + rule, k, 'adapter' if mine else 'fallback'])
        d = ' '.join(encode(x, a['kmode']) for x in k.split(' '))
        if d != k:
            hops.append(['keys', 'collapse', f'arrives as {d}', d])
        first = d.split(' ')[0]
        hits, seq = self.lookup(app, first)
        if ' ' in d:
            hits = list(self.app_bindings[app].get(d, [])) or hits
        return dict(hops=hops, effects=[[app] + h[:3] for h in hits], prefixes=[[app] + h[:2] for h in seq][:6],
                    delivered=d)


def interesting(ch):
    """Chords worth tracing: anything with a modifier, or a named key; not bare or shifted text."""
    first = ch.split(' ')[0]
    mods, key = chord.split(first)
    if '|' in first:
        return False
    if not mods:
        return len(key) > 1
    if mods == {'shift'} and len(key) == 1:
        return False
    return True


def trace_all(model, extra=()):
    chords = set(model.wez) | set(model.root) | set(model.windows) | set(extra)
    for b in model.app_bindings.values():
        chords |= {c.split(' ')[0] for c in b}
    chords = sorted(c for c in chords if interesting(c))
    return {c: {app: model.route(c, app) for app in APPS} for c in chords}
