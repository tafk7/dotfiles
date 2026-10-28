"""Refresh configs/keymap/defaults: each agent CLI's built-in keybindings at its installed version.

None of the four tools prints its defaults, so each is read from where it lives:
  claude    the table literal in the native binary (extract/claude.cjs, needs node)
  codex     built_in_defaults() in codex-rs/tui/src/keymap.rs at the installed tag (fetched)
  opencode  the defaults table in the compiled binary
  pi        KeybindingsManager in the installed package (extract/pi.mjs, needs node)
The saved files keep `keymap build` deterministic and runnable where the agents are not installed.
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def version_of(cmd):
    try:
        out = subprocess.run([cmd, '--version'], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    m = re.search(r'(\d+\.\d+\.\d+)', out)
    return m.group(1) if m else None


def write(repo, app, tool, version, source, bindings, descriptions=None):
    """One binding per line, so a refresh diffs readably."""
    path = os.path.join(repo, 'configs/keymap/defaults', f'{app}.json')
    lines = ['{', f'  "tool": {json.dumps(tool)},', f'  "version": {json.dumps(version)},',
             f'  "source": {json.dumps(source)},', '  "bindings": {']
    groups = list(bindings.items())
    for gi, (k, v) in enumerate(groups):
        comma = ',' if gi < len(groups) - 1 else ''
        if isinstance(v, dict):
            lines.append(f'    {json.dumps(k)}: {{')
            items = list(v.items())
            for i, (a, b) in enumerate(items):
                lines.append(f'      {json.dumps(a)}: {json.dumps(b)}' + (',' if i < len(items) - 1 else ''))
            lines.append('    }' + comma)
        else:
            lines.append(f'    {json.dumps(k)}: {json.dumps(v)}{comma}')
    lines.append('  }' + (',' if descriptions else ''))
    if descriptions:
        lines.append(f'  "descriptions": {json.dumps(descriptions, sort_keys=True)}')
    lines.append('}')
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'{app}: {version} -> {os.path.relpath(path, repo)}')


def claude(repo):
    exe = shutil.which('claude')
    if not exe or not shutil.which('node'):
        return 'needs claude and node'
    r = subprocess.run(['node', os.path.join(HERE, 'extract/claude.cjs'), os.path.realpath(exe)],
                       capture_output=True, text=True)
    if r.returncode:
        return r.stderr.strip()
    write(repo, 'claude', 'Claude Code', version_of('claude'), 'bundled defaults in the claude binary',
          json.loads(r.stdout))


CODEX_CTX = {'AppKeymap': 'global', 'ChatKeymap': 'chat', 'ComposerKeymap': 'composer', 'EditorKeymap': 'editor',
             'VimNormalKeymap': 'vim_normal', 'VimOperatorKeymap': 'vim_operator',
             'VimTextObjectKeymap': 'vim_text_object', 'PagerKeymap': 'pager', 'ListKeymap': 'list',
             'AgentsKeymap': 'agents', 'ApprovalKeymap': 'approval'}
CODEX_KEYS = {'Enter': 'enter', 'Tab': 'tab', 'Backspace': 'backspace', 'Esc': 'esc', 'Delete': 'delete', 'Up': 'up',
              'Down': 'down', 'Left': 'left', 'Right': 'right', 'Home': 'home', 'End': 'end', 'PageUp': 'page-up',
              'PageDown': 'page-down', 'Insert': 'insert'}


def codex_defaults(src):
    def keycode(expr):
        expr = expr.strip()
        if m := re.fullmatch(r"KeyCode::Char\('(\\?.)'\)", expr):
            return {' ': 'space', '-': 'minus'}.get(m.group(1).replace("\\'", "'"), m.group(1).replace("\\'", "'"))
        if m := re.fullmatch(r'KeyCode::F\((\d+)\)', expr):
            return f'f{m.group(1)}'
        if m := re.fullmatch(r'KeyCode::(\w+)', expr):
            return CODEX_KEYS.get(m.group(1), m.group(1).lower())
        raise ValueError(expr)

    def entries(body):
        out = []
        for m in re.finditer(r'(plain|ctrl|alt|shift)\((KeyCode::[^()]*(?:\([^()]*\))?)\)|raw\(KeyBinding::new\(\s*'
                             r'(KeyCode::[^,]*?(?:\([^()]*\))?)\s*,\s*([^)]*?)\s*,?\s*\)\)', body):
            if m.group(1):
                mods = [] if m.group(1) == 'plain' else [m.group(1)]
                key = keycode(m.group(2))
            else:
                mods = [x.strip().split('::')[-1].lower().replace('control', 'ctrl') for x in m.group(4).split('|')]
                key = keycode(m.group(3))
            out.append('-'.join([x for x in ('ctrl', 'alt', 'shift', 'super') if x in mods] + [key]))
        return out

    start = src.index('fn built_in_defaults() -> Self {')
    block = src[start:src.index('fn validate_conflicts', start)]
    result, ctx = {}, None
    for m in re.finditer(r'(\w+Keymap) \{|(\w+): (?:default_bindings!\[(.*?)\]|Vec::new\(\)),', block, re.S):
        if m.group(1) in CODEX_CTX:
            ctx = CODEX_CTX[m.group(1)]
            result.setdefault(ctx, {})
        elif m.group(2) and ctx:
            result[ctx][m.group(2)] = entries(m.group(3) or '')
    result.setdefault('global', {})['leader'] = ['ctrl-x']
    return result


def codex(repo):
    version = version_of('codex')
    if not version:
        return 'needs codex'
    url = f'https://raw.githubusercontent.com/openai/codex/rust-v{version}/codex-rs/tui/src/keymap.rs'
    with urllib.request.urlopen(url, timeout=30) as r:
        src = r.read().decode()
    write(repo, 'codex', 'Codex', version, f'codex-rs/tui/src/keymap.rs built_in_defaults() at rust-v{version}',
          codex_defaults(src))


def opencode(repo):
    exe = shutil.which('opencode')
    if not exe:
        return 'needs opencode'
    binary = os.path.realpath(exe)
    with open(binary, 'rb') as f:
        if f.read(2) == b'#!':
            binary = os.path.expanduser('~/.opencode/bin/opencode')
    with open(binary, 'rb') as f:
        data = f.read().decode('latin-1')
    m = re.search(r'(\w+)=\(\w,\w\)=>\(\{default:\w,description:\w\}\),\w+=\{leader:\1\((\w+|"[^"]*"),"([^"]*)"\)', data)
    if not m:
        return 'opencode: defaults table not found'
    fn, leader_ref = m.group(1), m.group(2)
    if leader_ref.startswith('"'):
        leader = leader_ref.strip('"')
    else:
        lm = re.search(re.escape(leader_ref) + r'="([^"]*)"', data[max(0, m.start() - 4000):m.start()])
        leader = lm.group(1) if lm else 'ctrl+x'
    start, depth, q = data.index('{leader:', m.start()), 0, None
    i = start
    for i in range(start, len(data)):
        c = data[i]
        if q:
            if c == q and data[i - 1] != '\\':
                q = None
        elif c in '"\'`':
            q = c
        elif c in '{(':
            depth += 1
        elif c in '})':
            depth -= 1
            if depth == 0:
                break
    block = data[start:i + 1]
    entry = re.compile(r'"?([\w.<>-]+)"?:' + re.escape(fn) + r'\("((?:[^"\\]|\\.)*)","((?:[^"\\]|\\.)*)"\)')
    bindings, desc = {'leader': [leader]}, {'leader': m.group(3)}
    for e in entry.finditer(block):
        bindings[e.group(1)] = [x for x in e.group(2).split(',') if x and x != 'none']
        desc[e.group(1)] = e.group(3)
    write(repo, 'opencode', 'OpenCode', version_of('opencode'), 'defaults table in the opencode binary', bindings, desc)


def pi(repo):
    exe = shutil.which('pi')
    if not exe or not shutil.which('node'):
        return 'needs pi and node'
    path = os.path.realpath(exe)
    pkg = path[:path.index('pi-coding-agent') + len('pi-coding-agent')] if 'pi-coding-agent' in path else None
    if not pkg:
        return f'pi: package not found from {path}'
    with tempfile.TemporaryDirectory() as home:
        r = subprocess.run(['node', os.path.join(HERE, 'extract/pi.mjs'), pkg], capture_output=True, text=True,
                           env=dict(os.environ, HOME=home))
    if r.returncode:
        return r.stderr.strip()
    found = json.loads(r.stdout)
    write(repo, 'pi', 'pi', version_of('pi'), 'KeybindingsManager.getResolvedBindings() in the installed package',
          {k: v['keys'] for k, v in found.items()}, {k: v['description'] for k, v in found.items()})


def refresh(repo, apps):
    status = 0
    for app in apps or ['claude', 'codex', 'opencode', 'pi']:
        err = globals()[app](repo)
        if err:
            print(f'{app}: skipped ({err})')
            status = 1
    return status
