"""Read the things you type by name: shell aliases and functions, git aliases, and bin/ commands.

Descriptions come from the source, never from running anything: a trailing
comment on the definition, else the comment directly above it when that comment
belongs to it alone. A comment above several definitions heads a section, and
becomes a tag of each. Commands take a Python docstring's first line, else the
first comment after the shebang; `--help` is never run (some scripts act).
"""
import ast
import os
import re

ALIAS = re.compile(r"""^\s*(?:command -v \S+ (?:>/dev/null 2>&1|&>/dev/null) && )?alias (?:-- )?([^=\s]+)="""
                   r"""(?:'([^']*)'|"((?:[^"\\]|\\.)*)"|(\S+))""")
FUNC = re.compile(r'^\s*(?:function\s+)?([A-Za-z.][\w.:-]*)\s*\(\)\s*[{(]')
TRAILING = re.compile(r"\s#\s+(\S.*)$")
GIT_ALIAS = re.compile(r'^\s*([\w-]+)\s*=\s*(.+)$')


def first_sentence(text, cap=110):
    """The first sentence of TEXT (a semicolon in parentheses doesn't end it), or its
    first CAP characters."""
    text = ' '.join(text.split())
    depth, end = 0, len(text)
    for i, c in enumerate(text):
        depth += (c in '([') - (c in ')]')
        after = text[i + 2:i + 3]
        if c in '.;' and depth <= 0 and (i + 1 == len(text) or text[i + 1] == ' ' and (c == ';' or not after.islower())):
            end = i
            break
    out = text[:end].rstrip('.;:')
    return out if len(out) <= cap else out[:cap - 1].rstrip() + '…'


def section_tag(block):
    """A section header's words: '# Status and inspection' -> 'status and inspection'."""
    text = re.split(r'[.(:—]| - |;', ' '.join(block))[0].strip()
    return text.lower() if 0 < len(text) <= 40 else ''


def paragraphs(lines):
    """[(start index, lines)] split on blank lines."""
    out, cur, start = [], [], 0
    for i, line in enumerate(lines):
        if line.strip():
            if not cur:
                start = i
            cur.append(line)
        elif cur:
            out.append((start, cur))
            cur = []
    if cur:
        out.append((start, cur))
    return out


def comment_text(line):
    return re.sub(r'^\s*#\s?', '', line).rstrip()


def definitions(path, text, match, comment='#'):
    """[(name, line number, value, summary, via, tags)] from TEXT, where MATCH(line) gives
    (name, value, rest of the line) for a definition line. Paragraph by paragraph: a leading comment block
    over one definition describes it; over several, it names their section."""
    out = []
    lines = text.splitlines()
    for start, para in paragraphs(lines):
        block = []
        for line in para:
            if line.lstrip().startswith(comment) and not line.lstrip().startswith('#!'):
                block.append(comment_text(line))
            else:
                break
        found, first = [], None
        for j, line in enumerate(para):
            m = match(line)
            if m:
                found.append((m[0], start + j + 1, m[1], m[2]))
                first = j if first is None else first
        names = {f[0] for f in found}
        # A description sits right on its definition (an `unalias NAME` may come between).
        between = para[len(block):first] if first is not None else []
        adjacent = all(re.match(r'\s*unalias\b', l) for l in between)
        own = first_sentence(' '.join(block)) if block and len(names) == 1 and adjacent else ''
        tag = section_tag(block) if block and len(names) > 1 else ''
        for name, lnum, value, rest in found:
            t = TRAILING.search(' ' + rest)
            if t:
                out.append((name, lnum, value, first_sentence(t.group(1)), 'comment', [tag] if tag else []))
            elif own:
                out.append((name, lnum, value, own, 'comment', []))
            else:
                out.append((name, lnum, value, '', 'action', [tag] if tag else []))
    return out


def shell_match(line):
    m = ALIAS.match(line)
    if m:
        return m.group(1), next(g for g in m.groups()[1:] if g is not None), line[m.end():]
    m = FUNC.match(line)
    if m and not m.group(1).startswith('_'):
        body = re.match(r'.*?\(\)\s*\{\s*(.+?);?\s*\}([^}]*)$', line)
        return m.group(1), (body.group(1) if body else ''), (body.group(2) if body else line[m.end():])
    return None


def shell(repo):
    """Aliases and functions in shell/tools/*.sh and shell/platform/*.sh, as dicts.
    A name defined twice (an if/else on an optional tool) keeps its first definition."""
    out = {}
    for sub in ('shell/tools', 'shell/platform'):
        folder = os.path.join(repo, sub)
        if not os.path.isdir(folder):
            continue
        for f in sorted(os.listdir(folder)):
            if not f.endswith('.sh'):
                continue
            path = f'{sub}/{f}'
            with open(os.path.join(repo, path)) as fh:
                text = fh.read()
            stem = f[:-3]
            for name, lnum, value, summary, via, tags in definitions(path, text, shell_match):
                kind = 'alias' if ALIAS.match(text.splitlines()[lnum - 1]) else 'function'
                key = ('alias:' if kind == 'alias' else 'fn:') + name
                prev = out.get(key)
                if prev:
                    if not prev['summary'] and summary:
                        prev.update(summary=summary, via=via)
                    continue
                out[key] = dict(id=key, kind=kind, key=name, label=name, layer='shell', summary=summary, via=via,
                                expands=value, origin='ours', tags=list(dict.fromkeys([stem] + tags + (['wsl'] if sub.endswith('platform') else []))),
                                source=f'{path}:{lnum}')
    return list(out.values())


def git_aliases(repo):
    path = os.path.join(repo, 'configs/gitconfig')
    if not os.path.exists(path):
        return []
    with open(path) as f:
        lines = f.read().splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == '[alias]')
    except StopIteration:
        return []
    end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith('[')), len(lines))
    section = '\n'.join([''] * (start + 1) + lines[start + 1:end])

    def match(line):
        m = GIT_ALIAS.match(line)
        if not m:
            return None
        value = m.group(2).strip().strip('"')
        return m.group(1), (value[1:] if value.startswith('!') else 'git ' + value), ''

    out = []
    for name, lnum, value, summary, via, tags in definitions('configs/gitconfig', section, match):
        out.append(dict(id='git:' + name, kind='git-alias', key='git ' + name, label='git ' + name, layer='git',
                        summary=summary, via=via, expands=value, origin='ours', tags=['git'] + tags,
                        source=f'configs/gitconfig:{lnum}'))
    return out


# Helpers the keys run, rather than commands you type: hidden from the commands
# view, shown in the preview of the key that runs them.
INTERNAL = re.compile(r'^(tmux-.*|compose-editor|git-credential-.*|codex-transcript)$')


def header(text):
    """(summary, via) for a script: its docstring's first line, else its first comment."""
    lines = text.splitlines()
    if lines and 'python' in lines[0]:
        try:
            doc = ast.get_docstring(ast.parse(text))
        except SyntaxError:
            doc = None
        if doc:
            return first_sentence(doc.strip().split('\n\n')[0]), 'docstring'
    block = []
    for line in lines[1:]:
        if line.startswith('#') and not re.match(r'#\s*shellcheck\b', line):
            words = comment_text(line)
            if not words.strip():
                if block:
                    break
                continue
            block.append(words)
        elif block or line.strip():
            break
    return (first_sentence(' '.join(block)), 'comment') if block else ('', 'action')


def usage_lines(name, text):
    """Subcommands a script's header lists with a description, as
    `#   NAME SUB ARGS   description` (two or more spaces before the description)."""
    out = []
    names = {name, name.replace('-', ' ', 1)}
    for i, line in enumerate(text.splitlines()):
        m = re.match(r'#\s{2,}(\S+(?: \S+)?) ([a-z][\w-]*)\b(.*?)\s{2,}(\S.*)$', line)
        if m and m.group(1) in names:
            out.append((f'{m.group(1)} {m.group(2)}', (m.group(2) + m.group(3)).strip(), m.group(4).strip(), i + 1))
    return out


def commands(repo):
    folder = os.path.join(repo, 'bin')
    try:
        with open(os.path.join(repo, 'configs/tmux.conf')) as f:
            tmux_conf = f.read()
    except OSError:
        tmux_conf = ''
    out = []
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if not os.path.isfile(path) or not os.access(path, os.X_OK):
            continue
        try:
            with open(path) as f:
                text = f.read()
        except (OSError, UnicodeDecodeError):
            continue
        summary, via = header(text)
        internal = bool(INTERNAL.match(name)) or bool(re.search(r'run-shell[^\n]*bin/' + re.escape(name) + r'\b', tmux_conf))
        out.append(dict(id='cmd:' + name, kind='command', key=name, label=name, layer='bin', summary=summary, via=via,
                        expands=f'bin/{name}', origin='ours', tags=['internal'] if internal else [],
                        source=f'bin/{name}:1'))
        seen = set()
        for full, usage, desc, lnum in [] if internal else usage_lines(name, text):
            if full in seen:
                continue
            seen.add(full)
            out.append(dict(id='cmd:' + full, kind='command', key=full, label=full, layer='bin', summary=desc,
                            via='comment', expands=full.split(' ')[0] + ' ' + usage, origin='ours',
                            tags=['subcommand'], source=f'bin/{name}:{lnum}'))
    return out
