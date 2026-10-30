#!/usr/bin/env python3
"""bin/keys (lib/keymap): chord notation, tmux rule evaluation, the Defy export, the readers
behind the entry index, notes, and a full build of this checkout."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, 'lib'))

from keymap import analysis, chord, entries, keyboard, names, route, sources, track, views  # noqa: E402
KEYS = os.path.join(REPO, 'bin/keys')


def fixture(files):
    """A checkout-shaped temp dir with FILES ({path: text}); executable under bin/."""
    root = tempfile.mkdtemp()
    for path, text in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'w') as f:
            f.write(text)
        if path.startswith('bin/'):
            os.chmod(full, 0o755)
    return root


def keys_env(tmp):
    """bin/keys with its cache and state in TMP, never the caller's."""
    return dict(os.environ, XDG_CACHE_HOME=os.path.join(tmp, 'cache'), XDG_STATE_HOME=os.path.join(tmp, 'state'),
                VIZ_DIR=os.path.join(tmp, 'viz'), NO_COLOR='1')


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
        self.assertEqual(self.kb.presses('ctrl+alt+k')[0][1], 'stretch')  # Ctrl and Alt: a squeeze
        self.assertEqual(self.kb._cost([(19, 'key'), (69, 'ctrl'), (68, 'layer')])[1], 'one hand')  # laid across
        self.assertEqual(self.kb.presses('f11'), [])
        self.assertEqual(self.kb.presses('ctrl+_')[0][3], 1)


class Names(unittest.TestCase):
    """Aliases, functions, git aliases and commands, described from their own source."""

    @classmethod
    def setUpClass(cls):
        cls.root = fixture({
            'shell/tools/demo.sh': (
                '#!/bin/bash\n# Demo tools\n\n'
                '# Status and inspection\n'
                "alias ds='git status'          # Show what changed\n"
                "alias dl='git log --oneline'\n\n"
                '# Make a directory and go into it\n'
                'mk() {\n    mkdir -p "$1" && cd "$1" || return\n}\n\n'
                '# A comment that heads an if, not a definition\n'
                'if true; then\n    wrapped() { command wrapped "$@"; }\nfi\n\n'
                '_private() { :; }\n'),
            'shell/platform/wsl.sh': "#!/bin/bash\nalias clip='clip.exe'  # Pipe to the Windows clipboard\n",
            'configs/gitconfig': ('[alias]\n    # Basic shortcuts\n    st = status -sb\n    co = checkout\n\n'
                                  '    # Today\'s work\n    today = "!git log --since=midnight"\n[push]\n    default = simple\n'),
            'bin/pydoc': '#!/usr/bin/env python3\n# A comment the docstring outranks.\n"""Do a thing, then another.\n\nMore."""\n',
            'bin/strict': '#!/bin/bash\nset -euo pipefail\necho hi\n',
            'bin/tool': ('#!/bin/bash\n# Run the tool. Second sentence.\n#\n# Usage:\n'
                         '#   tool go [FAST]     go somewhere\n#   tool stop          stop it\nset -e\n'),
            'bin/tmux-helper': '#!/bin/bash\n# A helper the keys run.\n',
            'configs/tmux.conf': '',
        })
        cls.shell = {e['id']: e for e in names.shell(cls.root)}
        cls.cmds = {e['id']: e for e in names.commands(cls.root)}

    def test_trailing_comment_and_section(self):
        self.assertEqual(self.shell['alias:ds']['summary'], 'Show what changed')
        self.assertIn('status and inspection', self.shell['alias:ds']['tags'])
        self.assertEqual(self.shell['alias:dl']['summary'], '')  # a section header is no description
        self.assertEqual(self.shell['alias:dl']['expands'], 'git log --oneline')

    def test_comment_above(self):
        self.assertEqual(self.shell['fn:mk']['summary'], 'Make a directory and go into it')
        self.assertEqual(self.shell['fn:wrapped']['summary'], '')  # not adjacent: it heads the if
        self.assertNotIn('fn:_private', self.shell)
        self.assertIn('wsl', self.shell['alias:clip']['tags'])

    def test_git_aliases(self):
        found = {e['id']: e for e in names.git_aliases(self.root)}
        self.assertEqual(set(found), {'git:st', 'git:co', 'git:today'})
        self.assertEqual(found['git:st']['expands'], 'git status -sb')
        self.assertIn('basic shortcuts', found['git:st']['tags'])
        self.assertEqual(found['git:today']['summary'], "Today's work")
        self.assertEqual(found['git:today']['expands'], 'git log --since=midnight')

    def test_commands(self):
        self.assertEqual((self.cmds['cmd:pydoc']['summary'], self.cmds['cmd:pydoc']['via']), ('Do a thing, then another', 'docstring'))
        self.assertEqual(self.cmds['cmd:strict']['summary'], '')  # set -euo pipefail is no description
        self.assertEqual(self.cmds['cmd:tool']['summary'], 'Run the tool')
        self.assertEqual(self.cmds['cmd:tool go']['summary'], 'go somewhere')
        self.assertEqual(self.cmds['cmd:tool go']['expands'], 'tool go [FAST]')
        self.assertIn('cmd:tool stop', self.cmds)
        self.assertIn('internal', self.cmds['cmd:tmux-helper']['tags'])


class Readers(unittest.TestCase):
    def test_zsh_bindkey(self):
        root = fixture({'entry/zsh.sh': ("bindkey '^[[3;5~' kill-word       # Ctrl+Delete\n"
                                         "bindkey $'\\e\\x7f' backward-kill-line # Alt+Backspace (DEL encoding)\n"
                                         "bindkey '^X^E' edit-command-line\n"),
                        'shell/tools/w.sh': "bindkey -M emacs '^[i' my-widget  # Do my thing\n"})
        found = {(b.chord, b.action): b for b in sources.zsh(root, [])}
        self.assertIn(('ctrl+delete', 'kill-word'), found)
        self.assertEqual(found[('ctrl+delete', 'kill-word')].note, '')  # a comment naming the key says nothing
        self.assertIn(('alt+backspace', 'backward-kill-line'), found)
        self.assertIn(('ctrl+x ctrl+e', 'edit-command-line'), found)
        self.assertEqual(found[('alt+i', 'my-widget')].note, 'Do my thing')
        self.assertEqual(found[('alt+i', 'my-widget')].source, 'shell/tools/w.sh:1')

    def test_wezterm_comments(self):
        text = "  {\n    key = 'a', -- Next tab\n    mods = 'CTRL|SHIFT',\n  },\n  {\n    key = 'F11',\n    mods = 'NONE',\n  },\n"
        self.assertEqual(sources.wezterm_comments(text), {('CTRL|SHIFT', 'a'): (2, 'Next tab'), ('NONE', 'F11'): (6, '')})

    def test_mouse_chords(self):
        self.assertEqual(sources.mouse_chord('M-DoubleClick1Pane'), 'alt+double-click')
        self.assertEqual(sources.mouse_chord('MouseDragEnd1Pane'), 'drag-end')
        self.assertEqual(sources.mouse_chord('WheelUpPane'), 'wheel-up')
        self.assertIsNone(sources.mouse_chord('MouseDown3Status'))
        self.assertEqual(chord.label('alt+double-click'), 'Alt+Double-click')

    def test_tmux_lines(self):
        conf = 'bind -n M-z send-keys x\nbind -N "Zoom" z resize-pane -Z\nbind -T copy-mode-vi -N "up" e send -X cursor-up\nbind -r S-Up resize-pane -U 5\n'
        self.assertEqual(sources.tmux_lines(conf), {('root', 'alt+z'): (1, ''), ('prefix', 'z'): (2, 'Zoom'),
                                                    ('copy-mode-vi', 'e'): (3, 'up'), ('prefix', 'shift+up'): (4, '')})

    @unittest.skipUnless(shutil.which('tmux'), 'needs tmux')
    def test_bind_notes(self):
        """bind -N notes come back from list-keys -N; list-keys itself is unchanged by them."""
        root = fixture({'configs/tmux.conf': ('bind -N "Jump to the first window" -n M-S select-window -t "{start}"\n'
                                              'bind -N \'Zoom "it"\' z resize-pane -Z\n'
                                              'bind -N "Move up" -T copy-mode-vi e send -X cursor-up\n'
                                              'bind -n M-s select-pane -L\nbind \'"\' new-window\n')})
        table, _, failed, notes = sources.tmux_dump(shutil.which('tmux'), os.path.join(root, 'configs/tmux.conf'), root, 'notes')
        self.assertIsNone(failed)
        self.assertIn(('root', 'M-S'), table)
        self.assertEqual(notes[('root', 'alt+shift+s')], 'Jump to the first window')
        self.assertEqual(notes[('prefix', 'z')], 'Zoom "it"')
        self.assertEqual(notes[('copy-mode-vi', 'e')], 'Move up')
        self.assertNotIn(('root', 'alt+s'), notes)
        self.assertNotIn(('prefix', '"'), notes)  # rebinding a stock key without -N drops its note


def entry(eid, **kw):
    layer, _, key = eid.partition(':')
    return entries.Entry(id=eid, kind=kw.pop('kind', 'chord'), key=key, label=key, layer=layer, **kw)


class Notes(unittest.TestCase):
    def test_apply(self):
        root = fixture({'bin/tool': '#!/bin/bash\n# go fast\n'})
        found = [entry('tmux:alt+z', summary='if-shell ...', via='action'), entry('tmux:alt+1'), entry('tmux:alt+2'),
                 entry('zsh:alt+i'), entry('shell:alt+i')]
        notes = {'note': {'tmux:alt+z': {'summary': 'Back a turn'}, 'shell:alt+i': {'summary': 'AI', 'also': ['zsh:alt+i']},
                          'tmux:alt+q': {'summary': 'gone'}},
                 'group': {'window-n': {'match': 'tmux:alt+[0-9]', 'label': 'Alt+1…0'}, 'none': {'match': 'nope:*'}},
                 'tip': {'fast': {'label': 'go', 'summary': 'Go fast', 'anchor': ['bin/tool', 'go fast']},
                         'stale': {'label': 'x', 'summary': 'y', 'anchor': ['bin/tool', 'no such words']}},
                 'hide': {'ids': ['tmux:alt+2', 'tmux:gone']}}
        problems = entries.apply_notes(found, notes, root)
        by = {e.id: e for e in found}
        self.assertEqual((by['tmux:alt+z'].summary, by['tmux:alt+z'].via), ('Back a turn', 'note'))
        self.assertEqual(by['zsh:alt+i'].summary, 'AI')
        self.assertEqual(by['tmux:alt+1'].group, 'window-n')
        self.assertNotIn('tmux:alt+2', by)
        self.assertEqual(by['tip:fast'].summary, 'Go fast')
        self.assertEqual(sorted(problems), sorted([
            'configs/keymap/notes.toml: note "tmux:alt+q" matches no entry',
            'configs/keymap/notes.toml: group "none" (nope:*) matches no entry',
            'configs/keymap/notes.toml: tip "stale": "no such words" is no longer in bin/tool',
            'configs/keymap/notes.toml: hide "tmux:gone" matches no entry']))

    def test_nvim_notes_without_plugins(self):
        found = [entry('nvim:, f@n')]
        notes = {'note': {'nvim:, g@n': {'summary': 'grep'}}}
        self.assertEqual(entries.apply_notes(found, notes, REPO, plugins=False), [])
        self.assertEqual(len(entries.apply_notes(found, notes, REPO, plugins=True)), 1)

    def test_compact_outcomes(self):
        labels = {a: a for a in route.APPS}
        apps = {'shell': '⇒ nothing', 'fzf': '⇒ nothing', 'claude': 'tmux: sends Esc Esc ⇒ rewind',
                'codex': 'tmux: sends Esc Esc ⇒ edit previous', 'pi': '⇒ tree'}
        self.assertEqual(views.merged_outcomes(apps, labels), [
            ('claude, codex', 'tmux sends Esc Esc ⇒ rewind / edit previous'), ('pi', 'straight through ⇒ tree'),
            ('shell, fzf', '⇒ nothing')])


class Tracking(unittest.TestCase):
    """keys diff and the changed markers: snapshots compared by id."""

    def index(self, rows, broken=()):
        out = []
        for eid, summary in rows.items():
            out.append(dict(id=eid, kind='chord', key=eid.split(':')[1], label=eid, layer=eid.split(':')[0], summary=summary,
                            status='', origin='ours', apps={}))
        return dict(meta=dict(full='abc', date='2026-10-30'), entries=out, broken=list(broken))

    def test_compare(self):
        old = track.snapshot(self.index({'tmux:alt+z': 'Back a turn', 'tmux:alt+q': 'Gone', 'alias:gs': 'status'}))
        new_index = self.index({'tmux:alt+z': 'Back a turn, now', 'alias:gs': 'status', 'tmux:alt+?': 'Lookup'}, ['x bug'])
        d = track.compare(old, track.snapshot(new_index))
        self.assertEqual((d['added'], d['removed'], d['changed']), (['tmux:alt+?'], ['tmux:alt+q'], [('tmux:alt+z', ['summary'])]))
        self.assertEqual((d['new'], d['fixed']), (['x bug'], []))
        doc = track.changes_doc(old, track.snapshot(new_index), new_index, 'abc')
        self.assertEqual(doc['removed'][0]['summary'], 'Gone')  # from the baseline: the entry is gone now

    def test_decorate_marks_since_seen(self):
        with tempfile.TemporaryDirectory() as state:
            env = os.environ.get('XDG_STATE_HOME')
            os.environ['XDG_STATE_HOME'] = state
            try:
                first = self.index({'tmux:alt+z': 'Back a turn'})
                track.decorate(REPO, first)  # the first build is the baseline
                self.assertTrue(os.path.exists(os.path.join(state, 'keys/seen.json')))
                later = self.index({'tmux:alt+z': 'Back two turns', 'tmux:alt+?': 'Lookup'})
                track.decorate(REPO, later)
                self.assertEqual({e['id']: e['changed'] for e in later['entries']}, {'tmux:alt+z': 'changed', 'tmux:alt+?': 'added'})
                track.mark_seen(later)
                again = self.index({'tmux:alt+z': 'Back two turns', 'tmux:alt+?': 'Lookup'})
                track.decorate(REPO, again)
                self.assertEqual([e['changed'] for e in again['entries']], ['', ''])
            finally:
                if env is None:
                    os.environ.pop('XDG_STATE_HOME')
                else:
                    os.environ['XDG_STATE_HOME'] = env

    def test_defaults_diff(self):
        old = {'version': '1.0', 'bindings': {'app.exit': ['ctrl+c', 'ctrl+d'], 'model.list': ['ctrl+x m'], 'gone': ['f1']}}
        new = {'version': '1.1', 'bindings': {'app.exit': ['ctrl+d'], 'model.list': ['ctrl+x m'], 'new.thing': ['f2']}}
        d = track.defaults_diff('opencode', old, new)
        self.assertEqual(d['version'], ['1.0', '1.1'])
        self.assertEqual(d['added'], [('', 'new.thing', 'f2')])
        self.assertEqual(d['removed'], [('', 'gone', 'f1')])
        self.assertEqual(d['rebound'], [('', 'app.exit', ['ctrl+c', 'ctrl+d'], ['ctrl+d'])])
        claude = track.defaults_diff('claude', {'version': 'a', 'bindings': {'Chat': {'ctrl+g': 'chat:externalEditor'}}},
                                     {'version': 'b', 'bindings': {'Chat': {'ctrl+e': 'chat:externalEditor'}}})
        self.assertEqual(claude['rebound'], [('Chat', 'chat:externalEditor', ['ctrl+g'], ['ctrl+e'])])


@unittest.skipUnless(shutil.which('tmux') and shutil.which('nvim'), 'needs tmux and nvim')
class Build(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data, cls.model = analysis.build(REPO)
        cls.entries, cls.problems = entries.build(REPO, cls.data, cls.model)
        cls.by = {e.id: e for e in cls.entries}
        cls.tmp = tempfile.mkdtemp()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def keys(self, *args):
        return subprocess.run([KEYS, *args], capture_output=True, text=True, env=keys_env(self.tmp))

    def finding(self, app, ch):
        return [f for f in self.data['findings'] if f.get('app') == app and f['chord'] == ch]

    def test_layers_read(self):
        self.assertEqual(self.data['notes'], [])
        self.assertIn('ctrl+shift+tab', self.data['wez'])
        self.assertEqual(self.data['wez']['scrolllock'][0], 'translate')  # by Windows key code, raw:145
        for app in ('claude', 'codex', 'opencode', 'pi', 'shell', 'nvim', 'copy'):
            self.assertGreater(self.data['counts'][app], 5, app)

    def test_routes(self):
        self.assertFalse([n for n in self.data['notes'] if n.startswith('tmux')], self.data['notes'])
        t = self.data['traces']
        self.assertEqual(t['alt+s']['claude']['effects'][0][:2], ['tmux', 'focus-left'])
        self.assertEqual(t['ctrl+c']['claude']['delivered'], 'esc')  # tmux's Claude rule
        self.assertEqual(t['ctrl+c']['shell']['delivered'], 'ctrl+c')
        self.assertEqual(t['super+h']['shell']['hops'][0][0], 'windows')
        self.assertEqual(t['scrolllock']['shell']['effects'][0][:2], ['tmux', 'review'])
        self.assertEqual(t['pause']['claude']['delivered'], 'esc')  # Break stops an agent's turn
        self.assertEqual(t['pause']['shell']['delivered'], 'ctrl+c')

    def test_judgement(self):
        self.assertEqual(self.data['traces']['shift+enter']['codex']['delivered'], 'ctrl+j')  # plain keys would merge it into Enter
        self.assertEqual(self.data['traces']['alt+z']['claude']['delivered'], 'esc esc')  # the pause between is no effect
        self.assertEqual(self.finding('opencode', 'ctrl+shift+d')[0]['sev'], 'bug')  # arrives as Ctrl+D: exit
        self.assertEqual(self.finding('claude', 'ctrl+c')[0]['sev'], 'adapted')
        self.assertEqual(self.finding('shell', 'alt+f')[0]['sev'], 'cost')
        focus = next(i for i in self.data['intents'] if i['label'] == 'Focus left')
        self.assertTrue(all(a['status'] == 'ok' for a in focus['apps'].values()))

    def test_check_passes(self):
        """keys check, rules 1-5, holds for this checkout (and keymap is keys)."""
        r = subprocess.run([os.path.join(REPO, 'bin/keymap'), 'check'], capture_output=True, text=True, env=keys_env(self.tmp))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.problems, [])

    def test_why(self):
        r = self.keys('why', 'alt+shift+v', 'codex', 'pi', '--all')
        self.assertIn('prompt in nvim, full pane', r.stdout)
        self.assertIn('LAlt (left thumb)', r.stdout)
        compact = self.keys('why', 'alt+k').stdout.splitlines()
        self.assertEqual(compact[-1].split()[-2:], ['⇒', 'nothing'])  # every app: one line

    def test_entries(self):
        ids = [e.id for e in self.entries]
        self.assertEqual(len(ids), len(set(ids)))
        alt_s = self.by['tmux:alt+s']
        self.assertEqual((alt_s.kind, alt_s.label, alt_s.origin, alt_s.intent), ('chord', 'Alt+S', 'ours', 'focus-left'))
        self.assertTrue(alt_s.source.startswith('configs/tmux.conf:'))
        self.assertIn('codex', alt_s.scope)
        self.assertEqual(self.by['opencode:ctrl+shift+d'].status, 'bug')
        self.assertEqual(self.by['intent:undo-turn'].key, 'alt+z')
        self.assertEqual(self.by['alias:gs'].kind, 'alias')
        self.assertIn('internal', self.by['cmd:tmux-scroll'].tags)
        self.assertEqual(self.by['pi:ctrl+w@tui.editor'].via, 'desc')  # pi's saved descriptions
        self.assertEqual(self.by['tmux:alt+z'].via, 'tmux-N')  # bind -N
        self.assertEqual(self.by['alias:gs'].via, 'comment')

    def test_ids_stable(self):
        data, model = analysis.build(REPO)
        again, _ = entries.build(REPO, data, model)
        self.assertEqual([e.id for e in again], [e.id for e in self.entries])

    def test_ls_tsv_columns(self):
        """keys ls --tsv: the golden columns scripts rely on."""
        lines = self.keys('ls', '--tsv', '-l', 'tmux').stdout.splitlines()
        self.assertTrue(lines)
        self.assertTrue(all(len(l.split('\t')) == len(views.TSV_COLUMNS) for l in lines))
        row = next(l.split('\t') for l in lines if l.startswith('tmux:alt+s\t'))
        self.assertEqual(dict(zip(views.TSV_COLUMNS, row))['label'], 'Alt+S')
        self.assertEqual(views.TSV_COLUMNS, ['id', 'kind', 'label', 'layer', 'summary', 'intent', 'status', 'origin',
                                             'scope', 'tags', 'source'])
        self.assertEqual(dict(zip(views.TSV_COLUMNS, row))['intent'], 'focus-left')

    def test_page(self):
        """The page: routes stored once, entries inline, under 1 MB, nothing fetched but viz's own."""
        out = os.path.join(self.tmp, 'page')
        r = self.keys('build', '-o', out)
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(os.path.join(out, 'keymap.html')) as f:
            html = f.read()
        self.assertLess(len(html.encode()), 1_000_000)
        self.assertNotIn('fonts.googleapis', html)
        self.assertNotIn('<link', html)
        self.assertNotRegex(html, r'(src|href)="https?://')
        for part in ('id="q"', 'id="shell"', 'id="cards"', 'id="changed"', '@media print', 'keyroutes-theme'):
            self.assertIn(part, html)
        from keymap import main
        index = {'entries': entries.to_json(self.entries), 'groups': {}}
        inline = main.page_data(self.data, index)
        for ch in ('alt+z', 'ctrl+c', 'shift+tab'):
            for n, app in enumerate(inline['routeApps']):
                self.assertEqual(inline['routes'][inline['routeTable'][ch][n]], self.data['traces'][ch][app])
        self.assertIsNone(inline['traces'])

    def test_diff_against_a_commit(self):
        """keys diff REV builds REV's snapshot from git archive with today's readers."""
        if not os.path.isdir(os.path.join(REPO, '.git')) and not os.path.isfile(os.path.join(REPO, '.git')):
            self.skipTest('not a git checkout')
        r = self.keys('diff', 'HEAD')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertRegex(r.stdout.splitlines()[0], r'changes since HEAD|Nothing changed since HEAD')

    def test_plain_listing(self):
        """Off a terminal, keys is keys ls: plain text, no fzf, no color."""
        r = self.keys('-k', 'alias')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn('\033[', r.stdout)
        self.assertTrue(any(l.split()[:2] == ['gs', 'alias'] for l in r.stdout.splitlines()), r.stdout[:400])
        stock = self.keys('ls', '-l', 'claude').stdout
        self.assertNotIn('·', stock)  # stock agent keys stay hidden ...
        self.assertIn('·', self.keys('ls', '-l', 'claude', '--stock').stdout)  # ... until asked for


if __name__ == '__main__':
    unittest.main()
