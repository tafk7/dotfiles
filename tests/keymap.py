#!/usr/bin/env python3
"""bin/keymap: chord notation, tmux rule evaluation, the Defy export, and a full build of this checkout."""
import json
import os
import shutil
import subprocess
import sys
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, 'lib'))

from keymap import analysis, chord, keyboard, route  # noqa: E402


class Notation(unittest.TestCase):
    def test_tmux(self):
        self.assertEqual(chord.tmux('C-S-G'), 'ctrl+shift+g')
        self.assertEqual(chord.tmux('M-F'), 'alt+shift+f')
        self.assertEqual(chord.tmux('M-C-?'), 'alt+backspace')
        self.assertEqual(chord.tmux('M-\x7f'), 'alt+backspace')
        self.assertEqual(chord.tmux('S-PPage'), 'shift+pageup')
        self.assertEqual(chord.tmux('BTab'), 'shift+tab')

    def test_other_layers(self):
        self.assertEqual(chord.wezterm('CTRL|SHIFT', 'PageUp'), 'ctrl+shift+pageup')
        self.assertEqual(chord.plus('ctrl+x ctrl+e'), 'ctrl+x ctrl+e')
        self.assertEqual(chord.plus('ctrl-shift-g', '-'), 'ctrl+shift+g')
        self.assertEqual(chord.plus('pageUp'), 'pageup')
        self.assertEqual(chord.vim('<C-S-g>'), 'ctrl+shift+g')
        self.assertEqual(chord.vim('<C-G>S'), 'ctrl+g S')

    def test_escape_sequences(self):
        self.assertEqual(chord.decode(chord.unescape(r'\e[3;5~')), ['ctrl+delete'])
        self.assertEqual(chord.decode(chord.unescape(r'\e[1;2P')), ['shift+f1'])
        self.assertEqual(chord.decode(chord.unescape(r'\27[27;6;71~')), ['ctrl+shift+g'])
        self.assertEqual(chord.decode(chord.unescape(r'\C-h')), ['ctrl+h|ctrl+backspace'])

    def test_label(self):
        self.assertEqual(chord.label('ctrl+shift+pageup'), 'Ctrl+Shift+PgUp')
        self.assertEqual(chord.label('ctrl++'), 'Ctrl++')


class TmuxRules(unittest.TestCase):
    def test_format(self):
        ctx = route.pane_ctx('claude')
        self.assertEqual(route.fmt('#{&&:#{==:#{pane_current_command},claude},#{==:#{pane_in_mode},0}}', ctx), '1')
        self.assertEqual(route.fmt('#{||:#{alternate_on},#{mouse_any_flag}}', route.pane_ctx('shell')), '0')
        self.assertEqual(route.fmt('#{?pane_in_mode,yes,no}', route.pane_ctx('copy')), 'yes')

    def test_branches(self):
        rule = ('if-shell -F "#{==:#{pane_current_command},claude}" "send-keys C-u" '
                '"send-keys \\"M-\\\\177\\""')
        self.assertEqual(route.run_tmux(rule, route.pane_ctx('claude')), (['ctrl+u'], []))
        self.assertEqual(route.run_tmux(rule, route.pane_ctx('codex')), (['alt+backspace'], []))
        self.assertEqual(route.run_tmux('select-pane -L', {})[1], [('focus-left', 'focus pane left')])

    def test_encoding(self):
        self.assertEqual(route.encode('ctrl+shift+g', 'legacy'), 'ctrl+g')
        self.assertEqual(route.encode('ctrl+shift+g', 'mok1'), 'ctrl+g')
        self.assertEqual(route.encode('ctrl+shift+g', 'mok2'), 'ctrl+shift+g')
        self.assertEqual(route.encode('shift+enter', 'legacy'), 'enter')
        self.assertEqual(route.encode('shift+enter', 'mok1'), 'shift+enter')
        self.assertEqual(route.encode('ctrl+space', 'legacy'), 'ctrl+space')
        self.assertIn('ctrl+alt+backspace', route.aliases('ctrl+alt+h', 'legacy'))


class Defy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.kb = keyboard.load(os.path.join(REPO, 'configs/keyboard/dygma-defy.json'))

    def test_layout(self):
        self.assertEqual(len(self.kb.geo), 70)  # 35 keys a side
        self.assertEqual(self.kb.mod_keys, {'shift': [48], 'super': [76], 'alt': [70], 'ctrl': [69]})
        self.assertEqual(self.kb.hold[1], [68, 75])
        self.assertEqual(self.kb.chords_at(64, 0), ['ctrl+insert'])
        self.assertEqual(self.kb.chords_at(19, 1), ['up'])
        self.assertEqual(sum(e['kind'] == 'none' for e in self.kb.layers[0].values()), 4)

    def test_presses(self):
        cost, rating, keys, layer = self.kb.presses('alt+up')[0]
        self.assertEqual((rating, layer), ('easy', 1))
        self.assertEqual({p for p, _ in keys}, {19, 70, 75})  # E, left Alt, right Symbols thumb
        self.assertEqual(self.kb.presses('ctrl+shift+g')[0][1], 'one hand')
        self.assertEqual(self.kb.presses('ctrl+alt+insert')[0][1], 'stretch')
        self.assertEqual(self.kb.presses('f11'), [])
        self.assertEqual(self.kb.presses('ctrl+_')[0][3], 1)


@unittest.skipUnless(shutil.which('tmux') and shutil.which('nvim'), 'needs tmux and nvim')
class Build(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data, cls.model = analysis.build(REPO)

    def finding(self, app, ch):
        return [f for f in self.data['findings'] if f.get('app') == app and f['chord'] == ch]

    def test_layers_read(self):
        self.assertEqual(self.data['notes'], [])
        self.assertIn('ctrl+shift+g', self.data['wez'])
        for app in ('claude', 'codex', 'opencode', 'pi', 'shell', 'nvim', 'copy'):
            self.assertGreater(self.data['counts'][app], 5, app)

    def test_routes(self):
        t = self.data['traces']
        self.assertEqual(t['alt+s']['claude']['effects'][0][:2], ['tmux', 'focus-left'])
        self.assertEqual(t['ctrl+c']['claude']['delivered'], 'esc')  # tmux's Claude rule
        self.assertEqual(t['ctrl+c']['shell']['delivered'], 'ctrl+c')
        self.assertEqual(t['super+h']['shell']['hops'][0][0], 'windows')
        self.assertEqual(t['scrolllock']['shell']['effects'], [['wezterm', 'not delivered']])

    def test_judgement(self):
        self.assertEqual(self.finding('codex', 'ctrl+shift+g')[0]['sev'], 'bug')
        self.assertEqual(self.finding('claude', 'ctrl+c')[0]['sev'], 'adapted')
        self.assertEqual(self.finding('shell', 'alt+f')[0]['sev'], 'cost')
        focus = next(i for i in self.data['intents'] if i['label'] == 'Focus left')
        self.assertTrue(all(a['status'] == 'ok' for a in focus['apps'].values()))

    def test_check_matches_known_issues(self):
        r = subprocess.run([os.path.join(REPO, 'bin/keymap'), 'check'], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_why(self):
        r = subprocess.run([os.path.join(REPO, 'bin/keymap'), 'why', 'ctrl+shift+g', 'codex'],
                           capture_output=True, text=True)
        self.assertIn('next_permission_mode', r.stdout)
        self.assertIn('LCtrl (left thumb)', r.stdout)


if __name__ == '__main__':
    unittest.main()
