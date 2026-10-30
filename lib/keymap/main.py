"""Map every key binding across the keyboard, Windows, WezTerm, tmux and the pane programs.

    keymap build [-o DIR]       write keymap.json and keymap.html (default: $VIZ_DIR/keymap)
    keymap open                 build, then show the page through viz
    keymap why CHORD [APP...]   trace one chord, e.g. keymap why ctrl+shift+g codex
    keymap free [MODS]          chords the keyboard sends that no layer binds, e.g. keymap free alt
    keymap check [--update]     fail on broken keys not in configs/keymap/known-issues.json
    keymap defaults [APP...]    refresh configs/keymap/defaults from the installed agent CLIs

Everything is read from this checkout: the Defy's Bazecor export in configs/keyboard,
configs/wezterm.lua and configs/tmux.conf, the shell and Neovim configs, and the
agents' defaults saved in configs/keymap/defaults with the checkout's config on top.
TMUX_BIN picks the tmux whose tables are read (default: tmux on PATH).
"""
import argparse
import datetime
import json
import os
import subprocess
import sys

# bin/keymap runs this under a Python 3.11 or newer (lib/python.sh).
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
sys.path.insert(0, os.path.join(REPO, 'lib'))

from keymap import analysis, defaults  # noqa: E402

PAGE = os.path.join(REPO, 'lib/keymap/page.html')
KNOWN = os.path.join(REPO, 'configs/keymap/known-issues.json')


def git(*args):
    r = subprocess.run(['git', '-C', REPO, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else '?'


def build(out_dir):
    data, _ = analysis.build(REPO, os.environ.get('TMUX_BIN'))
    data['meta'] = dict(branch=git('rev-parse', '--abbrev-ref', 'HEAD'), commit=git('rev-parse', '--short', 'HEAD'),
                        date=datetime.date.today().isoformat())
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'keymap.json'), 'w') as f:
        json.dump(data, f, separators=(',', ':'))
    with open(PAGE) as f:
        page = f.read().replace('/*DATA*/', json.dumps(data, separators=(',', ':')).replace('</', '<\\/'))
    html = os.path.join(out_dir, 'keymap.html')
    with open(html, 'w') as f:
        f.write(page)
    return data, html


def default_out():
    return os.path.join(os.environ.get('VIZ_DIR', os.path.expanduser('~/viz')), 'keymap')


def main():
    ap = argparse.ArgumentParser(prog='keymap', description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('-o', '--out', default=None)
    sub.add_parser('open')
    w = sub.add_parser('why')
    w.add_argument('chord')
    w.add_argument('apps', nargs='*')
    fr = sub.add_parser('free')
    fr.add_argument('mods', nargs='?', default='')
    c = sub.add_parser('check')
    c.add_argument('--update', action='store_true', help='record the current broken keys as known')
    d = sub.add_parser('defaults')
    d.add_argument('apps', nargs='*')
    args = ap.parse_args()

    if args.cmd in ('build', 'open'):
        data, html = build(getattr(args, 'out', None) or default_out())
        n = analysis.counts(data['findings'])
        print(f"{html}: {len(data['traces'])} chords traced; {n['bug']} broken, {n['adapted']} rewritten on purpose, "
              f"{n['cost']} hidden by design")
        for note in data['notes']:
            print('  note:', note)
        if args.cmd == 'open':
            os.execvp('viz', ['viz', 'open', html])
        return 0
    if args.cmd == 'defaults':
        return defaults.refresh(REPO, args.apps)
    data, _ = analysis.build(REPO, os.environ.get('TMUX_BIN'))
    if args.cmd == 'why':
        print(analysis.why(data, args.chord, args.apps or None))
    elif args.cmd == 'free':
        for ch, rating in analysis.free(data, args.mods):
            print(f'{ch:<22} {rating}')
    elif args.cmd == 'check':
        bugs = sorted({analysis.finding_key(f) for f in data['findings'] if f['sev'] == 'bug'})
        if args.update:
            with open(KNOWN, 'w') as f:
                json.dump({'$comment': 'Broken keys keymap check tolerates until they are fixed; '
                           'refresh with keymap check --update.', 'known': bugs}, f, indent=2)
                f.write('\n')
            print(f'{len(bugs)} known broken keys recorded')
            return 0
        known = set()
        if os.path.exists(KNOWN):
            with open(KNOWN) as f:
                known = set(json.load(f)['known'])
        new, fixed = [k for k in bugs if k not in known], sorted(known - set(bugs))
        for k in new:
            print('new broken key:', k)
        for k in fixed:
            print('fixed (drop from known-issues):', k)
        if new or fixed:
            return 1
        print(f'keymap: no new broken keys ({len(bugs)} known)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
