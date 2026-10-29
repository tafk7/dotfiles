"""Read each layer's bindings from the checkout (and the tools it configures).

Every reader returns Binding records; a reader whose tool is missing returns
none and adds a note, so the map still builds on a partial machine.
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import tomllib
from dataclasses import dataclass, field

from . import chord

HERE = os.path.dirname(os.path.abspath(__file__))


@dataclass
class Binding:
    layer: str            # wezterm, tmux, tmux-prefix, tmux-copy, windows, or a pane program id
    chord: str
    action: str
    kind: str = 'consume'  # consume | translate | conditional
    to: list = field(default_factory=list)
    context: str = ''
    origin: str = 'stock'  # stock | ours
    primary: bool = True   # main screen of the program, not a dialog or picker
    source: str = ''


def read(path):
    with open(path) as f:
        return f.read()


def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kw)
    except (OSError, subprocess.TimeoutExpired):
        return None


def alternatives(ch):
    """'ctrl+h|ctrl+backspace' -> both chords (a legacy byte that means two keys)."""
    head, _, last = ch.rpartition(' ')
    return [(head + ' ' + alt).strip() for alt in last.split('|')]


# --- WezTerm -----------------------------------------------------------------------
def wezterm(repo, notes):
    if not shutil.which('nvim'):
        notes.append('WezTerm skipped: nvim is needed to evaluate wezterm.lua')
        return []
    r = run(['nvim', '-l', os.path.join(HERE, 'wezterm-dump.lua'), os.path.join(repo, 'configs/wezterm.lua')])
    out = []
    for line in ((r.stdout + r.stderr) if r else '').splitlines():
        parts = line.split('\t')
        if len(parts) != 3:
            continue
        mods, key, action = parts
        ch = chord.wezterm(mods, key)
        m = re.match(r'SendString\("(.*)"\)$', action)
        if m:
            sent = chord.decode(chord.unescape(m.group(1)))
            out.append(Binding('wezterm', ch, action, 'translate', [sent[0].split('|')[0]], source='configs/wezterm.lua'))
        elif action == 'callback' and ch == 'ctrl+insert':
            out.append(Binding('wezterm', ch, 'copy a WezTerm selection', 'conditional', [ch],
                               context='passes when nothing is selected', source='configs/wezterm.lua'))
        else:
            label = 'upload clipboard image' if action == 'callback' else action
            out.append(Binding('wezterm', ch, label, origin='ours', source='configs/wezterm.lua'))
    for b in out:
        b.origin = 'ours'
    return out


# --- tmux ---------------------------------------------------------------------------
def tmux_dump(tmux_bin, conf, repo, name):
    """The key tables of a private server loaded with CONF, the extended-keys format, and
    why it failed (None when it read). A socket of its own per dump: kill-server returns
    before the server is gone, and a dump on the same socket could reach that server."""
    sock = f'keymap{os.getpid()}-{name}'
    env = dict(os.environ, DOTFILES_DIR=repo)
    env.pop('TMUX', None)
    started = run([tmux_bin, '-L', sock, '-f', conf, 'new-session', '-d', '-s', 'keymap'], env=env)
    keys = run([tmux_bin, '-L', sock, 'list-keys'], env=env)
    fmt = run([tmux_bin, '-L', sock, 'show', '-sv', 'extended-keys-format'], env=env)
    run([tmux_bin, '-L', sock, 'kill-server'], env=env)
    table = {}
    for line in (keys.stdout if keys else '').splitlines():
        m = re.match(r'bind-key\s+(?:-r\s+)?-T\s+(\S+)\s+(\S+)\s+(.*)', line)
        if m:
            table[(m.group(1), m.group(2))] = m.group(3).strip()
    failed = None
    if not table:
        step, result = ('new-session', started) if not started or started.returncode else ('list-keys', keys)
        failed = f'{step} ' + ('timed out or could not run' if result is None else
                               f'exited {result.returncode}: {result.stderr.strip()[:200]}')
    return table, (fmt.stdout.strip() if fmt and fmt.returncode == 0 else 'xterm'), failed


def tmux(repo, tmux_bin, notes):
    """Root and prefix tables, copy-mode-vi, and the extended-keys format the config sets."""
    tmux_bin = tmux_bin or shutil.which('tmux')
    if not tmux_bin:
        notes.append('tmux skipped: no tmux binary')
        return [], {'extended_keys_format': 'xterm', 'version': None}
    version = run([tmux_bin, '-V'])
    conf = os.path.join(repo, 'configs/tmux.conf')
    stock, _, _ = tmux_dump(tmux_bin, '/dev/null', repo, 'stock')
    ours, ext_format, failed = tmux_dump(tmux_bin, conf, repo, 'ours')
    if failed or ('root', 'M-s') not in ours:  # once more, on a fresh socket
        ours, ext_format, failed = tmux_dump(tmux_bin, conf, repo, 'ours-again')
    if failed or ('root', 'M-s') not in ours:
        notes.append(f'tmux tables unread: {failed or "configs/tmux.conf did not load (no Alt+S)"}')
    out = []
    for (table, key), action in sorted(ours.items()):
        if table not in ('root', 'prefix', 'copy-mode-vi') or re.search(r'Mouse|Wheel|Click|Drag', key):
            continue
        layer = {'root': 'tmux', 'prefix': 'tmux-prefix', 'copy-mode-vi': 'tmux-copy'}[table]
        origin = 'stock' if stock.get((table, key)) == action else 'ours'
        out.append(Binding(layer, chord.tmux(key), action, origin=origin, source='configs/tmux.conf'))
    return out, {'extended_keys_format': ext_format,
                 'version': version.stdout.strip() if version else None}


# --- Shells --------------------------------------------------------------------------
def readline(repo, notes):
    out, ours = [], set()
    text = read(os.path.join(repo, 'entry/bash.sh'))
    for m in re.finditer(r'^\s*bind\s+(-x\s+)?\'"([^"]+)":\s*([^\']+)\'', text, re.M):
        ch = chord.decode(chord.unescape(m.group(2)))[0]
        for alt in alternatives(ch):
            ours.add(alt)
            out.append(Binding('shell', alt, m.group(3).strip(), context='readline', origin='ours',
                               source='entry/bash.sh'))
    if not shutil.which('bash'):
        return out
    r = run(['bash', '--noprofile', '--norc', '-i', '-c', 'bind -p'])
    for line in (r.stdout if r else '').splitlines():
        m = re.match(r'"(.+)":\s*(\S+)$', line)
        if not m or m.group(2) in ('self-insert', 'do-lowercase-version'):
            continue
        chs = chord.decode(chord.unescape(m.group(1)))
        if len(chs) > 2:
            continue
        seq = ' '.join(chs)
        for alt in alternatives(seq):
            if alt.split(' ')[-1] not in ours:
                out.append(Binding('shell', alt, m.group(2), context='readline', source='bash defaults'))
    out += [Binding('shell', 'ctrl+c', 'interrupt (SIGINT)', context='terminal', source='tty'),
            Binding('shell', 'ctrl+d', 'end of input', context='terminal', source='tty')]
    return out


def fzf(repo, notes):
    out, seen = [], set()
    for path in ('shell/fzf.sh', 'shell/tools/fzf.sh'):
        for m in re.finditer(r"--bind\s+['\"]([a-z0-9/+-]+):([^'\"]+)", read(os.path.join(repo, path))):
            if m.group(1) in ('start', 'change') or m.group(1) in seen:
                continue
            seen.add(m.group(1))
            out.append(Binding('fzf', chord.plus(m.group(1), '-'), m.group(2).strip().split('\n')[0],
                               origin='ours', source=path))
    return out


def nvim(repo, notes):
    if not shutil.which('nvim'):
        notes.append('Neovim skipped: no nvim')
        return []
    lua = ("local o={} for _,m in ipairs({'n','i','x'}) do for _,k in ipairs(vim.api.nvim_get_keymap(m)) do "
           "o[#o+1]=m..'\\t'..k.lhs..'\\t'..(k.desc or k.rhs or '<lua>'):gsub('\\n',' ') end end "
           "io.stdout:write(table.concat(o,'\\n'))")

    def maps(*args):
        env = dict(os.environ, DOTFILES_DIR=repo)
        r = run(['nvim', *args, '--headless', '-c', f'lua {lua}', '-c', 'qa!'], env=env)
        return {tuple(l.split('\t')) for l in ((r.stdout + r.stderr) if r else '').splitlines() if l.count('\t') == 2}

    clean = {m[:2] for m in maps('--clean')}
    out = []
    for mode, lhs, rhs in sorted(maps('-u', os.path.join(repo, 'configs/init.vim'), '-i', 'NONE')):
        if (mode, lhs) in clean or lhs.startswith('<Plug>') or '<SNR>' in lhs:
            continue
        out.append(Binding('nvim', chord.vim(lhs.replace(' ', '<Space>')), rhs[:80], context=f'mode {mode}',
                           origin='ours', primary=mode in ('n', 'i'), source='configs/init.vim'))
    return out


# --- Agent programs: vendored defaults with the checkout's config on top ---------------------
def vendored(repo, app):
    path = os.path.join(repo, 'configs/keymap/defaults', f'{app}.json')
    return json.loads(read(path)) if os.path.exists(path) else None


def load_jsonc(path):
    if not os.path.exists(path):
        return {}
    text = re.sub(r'(?m)^\s*//.*$', '', read(path))
    text = re.sub(r',(\s*[}\]])', r'\1', text)
    return json.loads(text) if text.strip() else {}


def plus_any(s, sep='+'):
    for a, b in (('escape', 'esc'), ('return', 'enter'), ('meta', 'alt'), ('cmd', 'super'), ('opt', 'alt'),
                 ('minus', '-')):
        s = re.sub(rf'\b{a}\b', b, s)
    return chord.plus(s, sep)


CLAUDE_BUILT_IN = [  # outside the bindings table: the composer's readline keys and newline variants
    ('shift+enter', 'newline'), ('alt+enter', 'newline'), ('ctrl+a', 'line-start'), ('ctrl+e', 'line-end'),
    ('ctrl+k', 'kill-line-end'), ('ctrl+u', 'kill-line-start'), ('ctrl+w', 'delete-word-back'),
    ('alt+backspace', 'delete-word-back'), ('alt+d', 'delete-word-fwd'), ('alt+b', 'word-left'),
    ('alt+f', 'word-right'), ('ctrl+y', 'yank'), ('alt+y', 'yank-pop'), ('ctrl+z', 'suspend'),
    ('esc esc', 'rewind')]
CODEX_FIXED = [  # not rebindable in Codex
    ('ctrl+c', 'interrupt'), ('ctrl+d', 'exit'), ('ctrl+v', 'paste-image'), ('shift+tab', 'plan-mode'),
    ('esc esc', 'edit-previous'), ('alt+left', 'previous-agent'), ('alt+right', 'next-agent'), ('ctrl+z', 'suspend'),
    ('pageup', 'page-up'), ('pagedown', 'page-down'), ('ctrl+home', 'top'), ('ctrl+end', 'bottom'),
    ('alt+<', 'top'), ('alt+>', 'bottom')]


def claude(repo, notes):
    d = vendored(repo, 'claude')
    if not d:
        return [], None
    table = {ctx: dict(b) for ctx, b in d['bindings'].items()}
    ours = set()
    user = load_jsonc(os.path.join(repo, 'configs/ai/claude/keybindings.json'))
    for block in user.get('bindings', []):
        for key, action in (block.get('bindings') or {}).items():
            ctx = table.setdefault(block['context'], {})
            ours.add((block['context'], key))
            if action is None:
                ctx.pop(key, None)
            else:
                ctx[key] = action
    out = []
    for ctx, b in table.items():
        for key, action in b.items():
            out.append(Binding('claude', plus_any(key), action, context=ctx, primary=ctx in ('Global', 'Chat', 'Scroll'),
                               origin='ours' if (ctx, key) in ours else 'stock', source='claude defaults'))
    out += [Binding('claude', k, 'hard:' + a, context='Built in', source='claude composer') for k, a in CLAUDE_BUILT_IN]
    return out, d['version']


def codex(repo, notes):
    d = vendored(repo, 'codex')
    if not d:
        return [], None
    table = {ctx: dict(b) for ctx, b in d['bindings'].items()}
    user = {}
    for name in ('configs/codex.defaults.toml', 'configs/codex.toml'):
        path = os.path.join(repo, name)
        if os.path.exists(path):
            with open(path, 'rb') as f:
                for ctx, b in tomllib.load(f).get('tui', {}).get('keymap', {}).items():
                    if isinstance(b, dict):
                        user.setdefault(ctx, {}).update(b)
    for ctx, b in user.items():
        for action, keys in b.items():
            table.setdefault(ctx, {})[action] = [keys] if isinstance(keys, str) else list(keys)
    out = []
    for ctx, b in table.items():
        if ctx.startswith('vim'):
            continue
        for action, keys in b.items():
            if action == 'leader':
                continue
            for key in keys:
                out.append(Binding('codex', plus_any(key, '-'), action, context=ctx,
                                   primary=ctx in ('global', 'chat', 'composer', 'editor'),
                                   origin='ours' if action in user.get(ctx, {}) else 'stock', source='codex defaults'))
    out += [Binding('codex', k, 'fixed:' + a, context='fixed', source='codex (not rebindable)') for k, a in CODEX_FIXED]
    return out, d['version']


def opencode(repo, notes):
    d = vendored(repo, 'opencode')
    if not d:
        return [], None
    table = dict(d['bindings'])
    user = {}
    for name in ('configs/opencode-cli.defaults.json', 'configs/opencode-cli.json'):
        user.update(load_jsonc(os.path.join(repo, name)).get('keybinds', {}) or {})

    def norm(v):
        if v is False or v == 'none':
            return []
        if isinstance(v, str):
            return [x for x in v.split(',') if x]
        return [x for item in v for x in norm(item)] if isinstance(v, list) else []

    for k, v in user.items():
        table[k] = norm(v)
    leader = (table.get('leader') or ['ctrl+x'])[0]
    out = []
    for oid, keys in table.items():
        if oid == 'leader':
            continue
        primary = oid.split('.')[0] in ('app', 'prompt', 'input', 'session', 'agent', 'messages', 'command', 'model')
        for key in keys:
            out.append(Binding('opencode', plus_any(key.replace('<leader>', leader + ' ')), oid, context='keybinds',
                               primary=primary, origin='ours' if oid in user else 'stock', source='opencode defaults'))
    return out, d['version']


def pi(repo, notes):
    d = vendored(repo, 'pi')
    if not d:
        return [], None
    # configs/ai/pi/keybindings.json replaces an action's keys, as pi applies it.
    user = load_jsonc(os.path.join(repo, 'configs/ai/pi/keybindings.json'))
    out = []
    for pid, keys in {**d['bindings'], **user}.items():
        primary = not pid.startswith(('app.tree', 'app.models', 'app.session', 'tui.select', 'tui.altScreen.search'))
        for key in [keys] if isinstance(keys, str) else keys:
            out.append(Binding('pi', plus_any(key), pid, context=pid.rsplit('.', 1)[0], primary=primary,
                               source='configs/ai/pi/keybindings.json' if pid in user else 'pi defaults'))
    return out, d['version']


# --- Windows ---------------------------------------------------------------------------------
# What Windows itself acts on before WezTerm sees a key. Win-key chords belong to Windows wholesale.
WINDOWS = [
    ('alt+tab', 'switch windows'), ('alt+shift+tab', 'switch windows back'), ('ctrl+alt+tab', 'window picker'),
    ('alt+esc', 'cycle windows'), ('alt+f4', 'close the window'), ('ctrl+esc', 'Start menu'),
    ('ctrl+shift+esc', 'Task Manager'), ('ctrl+alt+delete', 'security screen'), ('alt+space', 'window menu'),
    ('printscreen', 'screenshot'),
]


def windows():
    return [Binding('windows', ch, action, source='Windows') for ch, action in WINDOWS]
