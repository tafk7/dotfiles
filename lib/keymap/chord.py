"""One notation for key chords from every layer's own notation.

Canonical form: modifiers in the order ctrl, alt, shift, super joined with '+',
then a lowercase key name: 'ctrl+shift+g', 'alt+backspace', 'shift+pageup'.
A sequence (a tmux prefix, a leader key, a multi-key vim map) joins its strokes
with spaces: 'ctrl+x ctrl+e'.
"""
import re

ORDER = ['ctrl', 'alt', 'shift', 'super']
MODS = {'c': 'ctrl', 'ctrl': 'ctrl', 'control': 'ctrl', 'm': 'alt', 'a': 'alt', 'alt': 'alt',
        'meta': 'alt', 'opt': 'alt', 'option': 'alt', 's': 'shift', 'shift': 'shift',
        'd': 'super', 'super': 'super', 'cmd': 'super', 'command': 'super', 'win': 'super', 'gui': 'super'}
KEYS = {
    'bspace': 'backspace', 'bs': 'backspace', 'dc': 'delete', 'del': 'delete', 'ic': 'insert',
    'ppage': 'pageup', 'pgup': 'pageup', 'page-up': 'pageup', 'npage': 'pagedown', 'pgdn': 'pagedown',
    'pgdown': 'pagedown', 'page-down': 'pagedown', 'btab': 'shift+tab', 'escape': 'esc',
    'return': 'enter', 'cr': 'enter', 'lt': '<', 'bslash': '\\', 'bar': '|', 'minus': '-', 'plus': '+',
    'arrowup': 'up', 'arrowdown': 'down', 'arrowleft': 'left', 'arrowright': 'right',
}


def key_name(k):
    low = k.lower()
    if low in KEYS:
        return KEYS[low]
    return k if len(k) == 1 else low


def make(mods, key):
    """Canonical chord from a modifier collection and a key name (an uppercase letter implies Shift)."""
    mods = set(mods)
    key = key_name(key)
    if '+' in key and key != '+':  # btab -> shift+tab
        extra, key = key.rsplit('+', 1)
        mods |= set(extra.split('+'))
    if len(key) == 1 and key.isalpha() and key.isupper():
        mods.add('shift')
        key = key.lower()
    return '+'.join([m for m in ORDER if m in mods] + [key])


def split(stroke):
    """'ctrl+shift+g' -> ({'ctrl', 'shift'}, 'g'); handles the '+' key itself."""
    if stroke == '+' or stroke.endswith('++'):
        return set(filter(None, stroke[:-2].split('+'))), '+'
    parts = stroke.split('+')
    return set(parts[:-1]), parts[-1]


def tmux(k):
    """tmux key names: C-S-G, M-BSpace, M-F (a shifted letter), S-PPage, M-C-?, \\$."""
    if len(k) == 2 and k[0] == '\\':
        k = k[1]
    mods = []
    while re.match(r'^[CMS]-.', k):
        mods.append(MODS[k[0].lower()])
        k = k[2:]
    if k == '?' and 'ctrl' in mods:  # C-? is DEL, which is Backspace
        mods.remove('ctrl')
        k = 'backspace'
    elif k == '\x7f':
        k = 'backspace'
    return make(mods, k)


# WezTerm key names that bind by Windows key code (raw:) or US position (phys:).
WEZ_RAW = {'145': 'scrolllock', '19': 'pause'}
WEZ_PHYS = {'Equal': '=', 'Minus': '-'}


def wezterm(mods, key):
    """WezTerm key assignments: mods='CTRL|SHIFT', key='PageUp', 'raw:145', 'phys:Equal'."""
    ms = [] if mods in (None, 'NONE', '') else [MODS[m.lower()] for m in mods.split('|')]
    if key.startswith('raw:'):
        key = WEZ_RAW.get(key[4:], key)
    elif key.startswith('phys:'):
        key = WEZ_PHYS.get(key[5:], key[5:])
    return make(ms, key)


def plus(s, sep='+'):
    """'ctrl+shift+g' (Claude, OpenCode, pi), 'ctrl-shift-g' (Codex, fzf); strokes split on spaces."""
    for a, b in (('page-up', 'pageup'), ('page-down', 'pagedown'), ('pageUp', 'pageup'), ('pageDown', 'pagedown')):
        s = s.replace(a, b)
    out = []
    for part in s.split():
        bits = part.split(sep)
        key = bits[-1] if bits[-1] else sep
        out.append(make([MODS[b.lower()] for b in bits[:-1] if b], key))
    return ' '.join(out)


def vim(lhs):
    """<C-S-g>, <S-PageUp>, <M-x>, gc. In vim <C-G> is Ctrl+G: Shift needs an explicit S-."""
    out = []
    for tok in re.findall(r'<[^>]+>|.', lhs):
        if tok.startswith('<') and len(tok) > 2:
            parts = tok[1:-1].split('-')
            if len(parts) > 1 and parts[-1] == '':
                parts = parts[:-2] + ['-']
            ms = [MODS[p.lower()] for p in parts[:-1] if p.lower() in MODS]
            key = parts[-1]
            if len(key) == 1 and ms and 'shift' not in ms:
                key = key.lower()
            out.append(make(ms, key))
        else:
            out.append('space' if tok == ' ' else tok)
    return ' '.join(out)


# xterm-style escape sequences: readline, zle, WezTerm SendString
CSI_LETTER = {'A': 'up', 'B': 'down', 'C': 'right', 'D': 'left', 'H': 'home', 'F': 'end',
              'P': 'f1', 'Q': 'f2', 'R': 'f3', 'S': 'f4', 'Z': 'shift+tab'}
CSI_TILDE = {1: 'home', 2: 'insert', 3: 'delete', 4: 'end', 5: 'pageup', 6: 'pagedown', 15: 'f5', 17: 'f6',
             18: 'f7', 19: 'f8', 20: 'f9', 21: 'f10', 23: 'f11', 24: 'f12'}


def xmods(n):
    n -= 1
    return [m for bit, m in ((4, 'ctrl'), (2, 'alt'), (1, 'shift'), (8, 'super')) if n & bit]


def unescape(s):
    """Readline '\\e[3;5~' / '\\C-h', zle '^[[1;5C', Lua '\\27[..' to raw characters."""
    s = s.replace('\\e', '\x1b').replace('\\E', '\x1b').replace('\\27', '\x1b')
    s = re.sub(r'\\C-(.)', lambda m: '\x7f' if m.group(1) == '?' else chr(ord(m.group(1).upper()) & 0x1f), s)
    s = s.replace('\\M-', '\x1b')
    s = re.sub(r'\^(.)', lambda m: '\x7f' if m.group(1) == '?' else chr(ord(m.group(1).upper()) & 0x1f), s)
    return s.replace('\\\\', '\\').replace('\\"', '"')


# Code points that modifyOtherKeys and CSI u name by their control character.
CODEPOINT = {9: 'tab', 13: 'enter', 27: 'esc', 32: 'space', 127: 'backspace'}


def decode(raw):
    """Raw characters to chords. A legacy byte that stands for two chords gives 'a|b'."""
    out, i = [], 0
    while i < len(raw):
        alt = False
        if raw[i] == '\x1b' and i + 1 < len(raw) and raw[i + 1] not in '[O':
            alt, i = True, i + 1
        if raw.startswith('\x1b[', i) or raw.startswith('\x1bO', i):
            m = re.match(r'\x1b[\[O]([\d;]*)([A-Za-z~])', raw[i:])
            if not m:
                out.append('esc')
                i += 1
                continue
            params = [int(p) for p in m.group(1).split(';') if p]
            final = m.group(2)
            if final == '~' and len(params) == 3 and params[0] == 27:
                ms, key = xmods(params[1]), CODEPOINT.get(params[2], chr(params[2]))  # modifyOtherKeys
            elif final == 'u' and params:
                ms, key = (xmods(params[1]) if len(params) > 1 else []), CODEPOINT.get(params[0], chr(params[0]))
            elif final == '~':
                key = CSI_TILDE.get(params[0], f'csi{params[0]}~') if params else '?'
                ms = xmods(params[1]) if len(params) > 1 else []
            else:
                key = CSI_LETTER.get(final, f'csi{final}')
                ms = xmods(params[1]) if len(params) > 1 else []
            out.append(make(ms + (['alt'] if alt else []), key))
            i += m.end()
            continue
        c = raw[i]
        i += 1
        ms = ['alt'] if alt else []
        if c == '\x7f':
            out.append(make(ms, 'backspace'))
        elif c == '\x1b':
            out.append(make(ms, 'esc'))
        elif c == '\t':
            out.append(make(ms, 'tab') + '|' + make(ms + ['ctrl'], 'i'))
        elif c == '\r':
            out.append(make(ms, 'enter') + '|' + make(ms + ['ctrl'], 'm'))
        elif c == '\x08':
            out.append(make(ms + ['ctrl'], 'h') + '|' + make(ms + ['ctrl'], 'backspace'))
        elif c == '\x00':
            out.append(make(ms + ['ctrl'], 'space'))
        elif ord(c) < 0x20:
            out.append(make(ms + ['ctrl'], chr(ord(c) + 0x60) if ord(c) <= 0x1a else chr(ord(c) + 0x40)))
        else:
            out.append(make(ms, c))
    return out


def label(chord):
    """'ctrl+shift+pageup' -> 'Ctrl+Shift+PgUp' for people."""
    names = {'pageup': 'PgUp', 'pagedown': 'PgDn', 'backspace': 'Bksp', 'delete': 'Del', 'insert': 'Ins',
             'enter': 'Enter', 'esc': 'Esc', 'tab': 'Tab', 'space': 'Space', 'up': '↑', 'down': '↓',
             'left': '←', 'right': '→', 'home': 'Home', 'end': 'End'}
    strokes = []
    for stroke in chord.split(' '):
        mods, key = split(stroke)
        k = names.get(key) or (key.upper() if re.fullmatch(r'f\d+', key) or len(key) == 1 else key)
        strokes.append('+'.join([m.capitalize() for m in ORDER if m in mods] + [k]))
    return ' '.join(strokes)
