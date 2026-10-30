"""The Dygma Defy: its Bazecor keymap export, key positions, and what a chord costs to press.

configs/keyboard/dygma-defy.json is a Bazecor backup (Bazecor > Preferences >
Backup). Its keymap.custom holds 80 codes per layer, indexed by the device's
left/right position tables. Codes follow Kaleidoscope: a HID usage in the low
byte with modifier flags above it, then ranges for layer keys and one-shots.
"""
import json
import math
import os

from . import chord

HID = {4 + i: chr(ord('a') + i) for i in range(26)}
HID.update({30 + i: str((i + 1) % 10) for i in range(10)})
HID.update({40: 'enter', 41: 'esc', 42: 'backspace', 43: 'tab', 44: 'space', 45: '-', 46: '=', 47: '[', 48: ']',
            49: '\\', 51: ';', 52: "'", 53: '`', 54: ',', 55: '.', 56: '/', 57: 'capslock', 70: 'printscreen',
            71: 'scrolllock', 72: 'pause', 73: 'insert', 74: 'home', 75: 'pageup', 76: 'delete', 77: 'end',
            78: 'pagedown', 79: 'right', 80: 'left', 81: 'down', 82: 'up', 83: 'numlock', 101: 'menu',
            224: 'lctrl', 225: 'lshift', 226: 'lalt', 227: 'lgui', 228: 'rctrl', 229: 'rshift', 230: 'ralt',
            231: 'rgui'})
HID.update({58 + i: f'f{i + 1}' for i in range(12)})
HID.update({104 + i: f'f{i + 13}' for i in range(12)})
SHIFTED = {'1': '!', '2': '@', '3': '#', '4': '$', '5': '%', '6': '^', '7': '&', '8': '*', '9': '(', '0': ')',
           '-': '_', '=': '+', '[': '{', ']': '}', '\\': '|', ';': ':', "'": '"', '`': '~', ',': '<', '.': '>', '/': '?'}
FLAGS = [(1, 'ctrl'), (2, 'alt'), (4, 'altgr'), (8, 'shift'), (16, 'super')]
MODKEY = {'lctrl': 'ctrl', 'rctrl': 'ctrl', 'lshift': 'shift', 'rshift': 'shift', 'lalt': 'alt', 'ralt': 'altgr',
          'lgui': 'super', 'rgui': 'super'}
LEGEND = {'backspace': 'Bksp', 'delete': 'Del', 'pageup': 'PgUp', 'pagedown': 'PgDn', 'scrolllock': 'ScrLk',
          'capslock': 'Caps', 'insert': 'Ins', 'printscreen': 'PrtSc', 'space': 'Space', 'enter': 'Enter',
          'esc': 'Esc', 'tab': 'Tab', 'home': 'Home', 'end': 'End', 'pause': 'Pause', 'up': '↑', 'down': '↓',
          'left': '←', 'right': '→'}


def typed_form(ch):
    """The chord a terminal reports for a shifted symbol with Alt: alt+shift+/ -> alt+? (or None)."""
    mods, key = chord.split(ch)
    if 'shift' in mods and 'ctrl' not in mods and key in SHIFTED:
        return chord.make(mods - {'shift'}, SHIFTED[key])
    return None


def decode(code, names):
    if code == 65535:
        return {'kind': 'transparent'}
    if code == 0:
        return {'kind': 'none'}
    if code < 8192 and (code & 0xff) in HID:
        base, flags = HID[code & 0xff], code >> 8
        mods = [n for b, n in FLAGS if flags & b]
        if base in MODKEY and not mods:
            return {'kind': 'mod', 'mod': MODKEY[base], 'legend': base[0].upper() + base[1:].replace('ctrl', 'Ctrl')
                    .replace('shift', 'Shift').replace('alt', 'Alt').replace('gui', 'Win')}
        typed = SHIFTED.get(base) if mods == ['shift'] else None
        legend = typed or LEGEND.get(base) or (base.upper() if len(base) == 1 or base.startswith('f') else base)
        badge = '' if typed else ' '.join({'super': 'W'}.get(m, m[0].upper()) for m in mods)
        return {'kind': 'key', 'key': base, 'mods': mods, 'typed': typed, 'legend': legend, 'badge': badge}
    for lo, kind in ((17408, 'layer-lock'), (17450, 'layer-hold'), (17492, 'layer-move')):
        if lo <= code < lo + 42:
            n = code - lo
            return {'kind': kind, 'layer': n, 'legend': f'{names.get(n, n)}'}
    if 49161 <= code <= 49168:
        n = code - 49161
        return {'kind': 'layer-oneshot', 'layer': n, 'legend': f'{names.get(n, n)}'}
    if 49153 <= code <= 49160:
        return {'kind': 'mod-oneshot', 'legend': 'one-shot'}
    if 20480 <= code < 20736:
        return {'kind': 'mouse', 'legend': 'mouse'}
    if 53852 <= code < 54044:
        return {'kind': 'macro', 'legend': 'macro'}
    return {'kind': 'other', 'legend': str(code)}


# --- Geometry, in the units of a Bazecor screenshot (key pitch ~102) ----------------------------
# Left half: column x, row-0 top per column (the Defy's column stagger), rows per column.
COL_X = [33, 136, 238, 340, 441, 543, 646]
COL_TOP = [90, 90, 55, 28, 55, 55, 105]
COL_ROWS = [4, 4, 4, 4, 4, 4, 3]
PITCH, SIZE, MIRROR = 102, 90, 1723
# Thumb arc, left half: position -> (centre x, centre y, w, h, rotation degrees)
THUMB_LEFT = {64: (406, 507, 126, 82, 0), 65: (526, 507, 92, 84, 4), 66: (623, 521, 94, 82, 20),
              67: (705, 566, 94, 82, 42), 71: (405, 600, 112, 80, 0), 70: (519, 603, 88, 82, 6),
              69: (612, 630, 92, 84, 28), 68: (714, 698, 178, 90, -44)}
THUMB_MIRROR = {64: 79, 65: 78, 66: 77, 67: 76, 68: 75, 69: 74, 70: 73, 71: 72}
FINGER = ['pinky', 'pinky', 'ring', 'middle', 'index', 'index', 'index']
ABSENT = {57}  # listed in the right half's table, but the Defy has no key there


# Two keys under one thumb, by how they feel on the Defy rather than by distance:
# Ctrl and Symbols take one thumb laid across both (an easy press), Ctrl and Alt
# a squeeze (a stretch). Mirrored for a right-hand Ctrl beside right Symbols.
THUMB_FEEL = {frozenset({68, 69}): 'lay', frozenset({74, 75}): 'lay',
              frozenset({69, 70}): 'squeeze', frozenset({73, 74}): 'squeeze'}


def geometry(left_rows, right_rows):
    keys = {}
    for side, rows in (('left', left_rows), ('right', right_rows)):
        for r, row in enumerate(rows[:4]):
            for c, pos in enumerate(row):
                if pos in ABSENT:
                    continue
                lc = c if side == 'left' else 6 - c
                if r >= COL_ROWS[lc]:
                    continue
                x = COL_X[lc] if side == 'left' else MIRROR - COL_X[lc] - SIZE
                y = COL_TOP[lc] + r * PITCH
                keys[pos] = dict(side=side, cx=x + SIZE / 2, cy=y + SIZE / 2, w=SIZE, h=SIZE, rot=0,
                                 finger=FINGER[lc], row=r, col=c)
    for pos, (cx, cy, w, h, rot) in THUMB_LEFT.items():
        keys[pos] = dict(side='left', cx=cx, cy=cy, w=w, h=h, rot=rot, finger='thumb', row=4, col=pos - 64)
        m = THUMB_MIRROR[pos]
        keys[m] = dict(side='right', cx=MIRROR - cx, cy=cy, w=w, h=h, rot=-rot, finger='thumb', row=4, col=m - 72)
    return keys


def load(path):
    with open(path) as f:
        d = json.load(f)
    neuron = d['neuron']
    names = {l['id']: l['name'] for l in neuron['layers']}
    kb = neuron['device']['keyboard']
    data = next(b['data'] for b in d['backup'] if b['command'] == 'keymap.custom')
    codes = [int(x) for x in data.split()]
    per = kb['rows'] * kb['columns']
    geo = geometry(kb['left'], kb['right'])
    layers = []
    for li in range(len(codes) // per):
        layer = {}
        for pos in geo:
            e = decode(codes[li * per + pos], names)
            if e['kind'] == 'transparent' and li:
                e = dict(layers[0][pos], inherited=True)
            layer[pos] = e
        layers.append(layer)
    return Keyboard(neuron['device']['info']['displayName'], names, geo, layers)


class Keyboard:
    def __init__(self, name, names, geo, layers):
        self.name, self.names, self.geo, self.layers = name, names, geo, layers
        base = layers[0]
        self.mod_keys = {}  # mod -> positions on the base layer
        for pos, e in base.items():
            if e['kind'] == 'mod':
                self.mod_keys.setdefault(e['mod'], []).append(pos)
        self.hold = {}  # layer -> positions that hold it
        for pos, e in base.items():
            if e['kind'] == 'layer-hold':
                self.hold.setdefault(e['layer'], []).append(pos)

    def chords_at(self, pos, layer, extra=()):
        """Chords a position sends on a layer with extra modifiers held (a typed symbol gives two names)."""
        e = self.layers[layer][pos]
        if e['kind'] != 'key':
            return []
        mods = set(extra) | set(e['mods'])
        out = [chord.make(mods, e['key'])]
        if e['typed']:
            out.insert(0, chord.make(mods - {'shift'}, e['typed']))
        elif 'shift' in mods and 'ctrl' not in mods and e['key'] in SHIFTED:
            # Alt+Shift+/ reaches tmux as Alt+? (Esc ?), as Shift+/ types ?.
            out.insert(0, chord.make(mods - {'shift'}, SHIFTED[e['key']]))
        return out

    def presses(self, target):
        """Ways to press a chord: [(cost, rating, [(pos, role)])], cheapest first. A shifted
        symbol no key types by itself is pressed with Shift: Alt+? is Alt+Shift+/ (tmux's M-?)."""
        want_mods, key = chord.split(target)
        ways = self._presses(want_mods, key)
        unshifted = next((k for k, v in SHIFTED.items() if v == key), None)
        if not ways and unshifted and 'shift' not in want_mods:
            ways = self._presses(want_mods | {'shift'}, unshifted)
        return ways

    def _presses(self, want_mods, key):
        ways = []
        for layer in (0, 1):
            if layer and 1 not in self.hold:
                continue
            for pos, e in self.layers[layer].items():
                if e['kind'] != 'key' or (layer and e.get('inherited')):
                    continue
                built = set(e['mods'])
                for name in self.chords_at(pos, layer):
                    m, k = chord.split(name)
                    if k != key or not m <= want_mods:
                        continue
                    extra = want_mods - m
                    if any(x not in self.mod_keys for x in extra):
                        continue
                    ways.append(self._plan(pos, layer, extra))
        ways.sort(key=lambda w: w[0])
        return ways

    def _plan(self, pos, layer, extra):
        """Cheapest way to hold the modifiers and layer key a chord needs alongside pos."""
        options = [[(pos, 'key')]]
        for m in sorted(extra):
            options = [o + [(c, m)] for o in options for c in self.mod_keys[m]]
        if layer:
            options = [o + [(c, 'layer')] for o in options for c in self.hold[layer]]
        best = min((self._cost(o) for o in options), key=lambda x: x[0])
        return best[0], best[1], best[2], layer

    def _cost(self, keys):
        """Keys pressed, plus a penalty when one thumb or finger must hold two keys (see THUMB_FEEL)."""
        fingers = {}
        for p, _ in keys:
            g = self.geo[p]
            fingers.setdefault((g['side'], g['finger']), []).append(p)
        clash = [ps for ps in fingers.values() if len(ps) > 1]
        feel = [THUMB_FEEL.get(frozenset(ps)) for ps in clash]
        clash = [ps for ps, f in zip(clash, feel) if f != 'lay']
        sides = {self.geo[p]['side'] for p, _ in keys}
        if 'squeeze' in feel:
            rating = 'stretch'
        elif clash:
            tight = len(clash) == 1 and len(clash[0]) == 2 and self.geo[clash[0][0]]['finger'] == 'thumb' \
                and self._adjacent(*clash[0])
            rating = 'tight' if tight else 'stretch'
        elif len(keys) == 1 or len(sides) == 2:
            rating = 'easy'
        else:
            rating = 'one hand'
        return len(keys) + {'easy': 0, 'one hand': 0.5, 'tight': 1, 'stretch': 3}[rating], rating, keys

    def _adjacent(self, a, b):
        ga, gb = self.geo[a], self.geo[b]
        return math.hypot(ga['cx'] - gb['cx'], ga['cy'] - gb['cy']) < 115

    def describe(self, keys, layer=0):
        out = []
        for pos, role in keys:
            g = self.geo[pos]
            e = self.layers[layer if role == 'key' else 0][pos]
            out.append(dict(pos=pos, role=role, hand=g['side'], finger=g['finger'], name=e.get('legend', '?')))
        return out

    def to_json(self):
        layers = []
        for li in range(min(2, len(self.layers))):
            layers.append({str(p): {k: v for k, v in e.items() if k in ('kind', 'key', 'mods', 'typed', 'legend', 'badge', 'layer', 'mod', 'inherited')}
                           for p, e in self.layers[li].items()})
        return dict(name=self.name, layerNames={str(k): v for k, v in self.names.items()},
                    geo={str(p): g for p, g in self.geo.items()}, layers=layers,
                    holds={str(k): v for k, v in self.hold.items()}, mods=self.mod_keys)
