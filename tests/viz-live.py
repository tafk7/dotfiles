#!/usr/bin/env python3
"""The live target and its collectors: viz publish --to live and viz collect. Offline, on temporary homes."""
import contextlib
import datetime
import io
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

import tomllib

REPO = Path(__file__).resolve().parents[1]
VIZ = REPO / 'bin' / 'viz'
# Everything viz reads or writes lives under one short temporary directory, set before the package is
# imported (lib/viz/config.py reads the environment once).
SANDBOX = Path(tempfile.mkdtemp(prefix='viz-live-', dir='/tmp')).resolve()
BASE_ENV = {
    'HOME': str(SANDBOX / 'home'), 'VIZ_DIR': str(SANDBOX / 'viz'), 'VIZ_STATE': str(SANDBOX / 'state'),
    'VIZ_CONFIG': str(SANDBOX / 'config'), 'XDG_RUNTIME_DIR': str(SANDBOX / 'run'),
    'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull,
}
os.environ.update(BASE_ENV)
for name in ('CLAUDE_CODE_SESSION_ID', 'VSCODE_IPC_HOOK_CLI'):
    os.environ.pop(name, None)
(SANDBOX / 'home').mkdir()
sys.path.insert(0, str(REPO / 'lib'))

from viz import collect

ROOT = Path(BASE_ENV['VIZ_DIR'])
LIVE = ROOT / 'live'
STATE = Path(BASE_ENV['VIZ_STATE'])
TODAY = datetime.date.today().isoformat()  # noqa: DTZ011


def viz(*args, cwd=None, timeout=60, **env):
    """Run bin/viz in the sandbox; ENV adds variables."""
    return subprocess.run([sys.executable, str(VIZ), *args], cwd=cwd or SANDBOX, env={**os.environ, **env},
                          capture_output=True, text=True, timeout=timeout, check=False)


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


class Fresh(unittest.TestCase):
    """Each test starts with an empty VIZ_DIR, state and config."""

    def setUp(self):
        for name in ('viz', 'state', 'config', 'work'):
            shutil.rmtree(SANDBOX / name, ignore_errors=True)
        self.work = SANDBOX / 'work'
        self.work.mkdir()

    def publish(self, *args, ok=True, cwd=None, **env):
        result = viz('publish', *args, cwd=cwd or self.work, **env)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def register(self, name='clock', run='date > "$VIZ_OUT"', every='5m', *more, ok=True, **env):
        return self.publish('--to', 'live', '--as', name, '--run', run, '--every', every,
                            '--summary', 'The time, every five minutes.', *more, ok=ok, **env)

    def manifest_of(self, folder):
        return tomllib.loads((folder / 'page.toml').read_text())

    def leftovers(self):
        """Hidden staging folders left in VIZ_DIR/live."""
        return [p.name for p in LIVE.iterdir() if p.name.startswith('.')] if LIVE.is_dir() else []


def draft(case, live=None, name='report'):
    """A filled-in draft folder made by viz path, with a page and an asset; LIVE is its [live] table's text."""
    result = viz('path', f'{name}.html', cwd=case.work)
    case.assertEqual(result.returncode, 0, result.stderr)
    entry = Path(result.stdout.strip())
    folder = entry.parent
    entry.write_text('<html><head><link rel="stylesheet" href="style.css"></head><body>draft</body></html>')
    (folder / 'style.css').write_text('body {}')
    (folder / 'build.py').write_text('print()')
    text = (folder / 'page.toml').read_text()
    text = text.replace('summary = ""', 'summary = "What the page shows."', 1)
    text = text.replace('generator = ""', 'generator = "build.py"', 1)
    if live:
        text += '\n[live]\n' + live
    (folder / 'page.toml').write_text(text)
    return folder


# ---------------------------------------------------------------------------
# The [live] table
# ---------------------------------------------------------------------------

class Spec(unittest.TestCase):
    def test_durations(self):
        for text, n in (('30s', 30), ('5m', 300), (' 2h ', 7200), ('1d', 86400), (90, 90)):
            self.assertEqual(collect.seconds(text), n)
        for bad in ('5', '5x', '1.5m', '', '-1m', True, 0, '0s'):
            with self.subTest(bad=bad), self.assertRaises(collect.SpecError):
                collect.seconds(bad)
        self.assertEqual([collect.short(n) for n in (30, 300, 7200, 86400, 90)], ['30s', '5m', '2h', '1d', '90s'])

    def test_spec(self):
        s = collect.spec('n', Path('/p'), {'entry': 'sub/page.html',
                                            'live': {'run': 'x', 'every': '1h', 'cwd': '~/w'}})
        self.assertEqual((s.every, s.timeout, s.paused), (3600, 1800, False))   # timeout: the interval, at most 30m
        self.assertEqual(s.out, Path('/p/sub/page.html'))
        self.assertEqual(s.workdir(), Path.home() / 'w')
        self.assertEqual(collect.spec('n', Path('/p'), {'live': {'run': 'x', 'every': '5m'}}).timeout, 300)
        self.assertEqual(collect.spec('n', Path('/p'), {'live': {'run': 'x', 'every': '5m'}}).workdir(), Path('/p'))
        self.assertEqual(collect.spec('n', Path('/p'), {'live': {'run': 'x', 'every': '5m', 'timeout': '1h'}})
                         .timeout, 3600)
        for live, why in (({}, 'run'), ({'run': ' ', 'every': '5m'}, 'run'), ({'run': 'x'}, 'every is missing'),
                          ({'run': 'x', 'every': '10s'}, 'shortest'), ({'run': 'x', 'every': '5m', 'when': 1}, 'unknown'),
                          ({'run': 'x', 'every': '5m', 'paused': 'yes'}, 'paused'),
                          ({'run': 'x', 'every': '5m', 'timeout': 'soon'}, 'timeout')):
            with self.subTest(live=live), self.assertRaisesRegex(collect.SpecError, why):
                collect.spec('n', Path('/p'), {'live': live})
        with self.assertRaisesRegex(collect.SpecError, 'no \\[live\\]'):
            collect.spec('n', Path('/p'), {})
        with self.assertRaisesRegex(collect.SpecError, 'inside the page'):
            collect.spec('n', Path('/p'), {'entry': '../x.html', 'live': {'run': 'x', 'every': '5m'}})

    def test_table_round_trips(self):
        for run in ('scriv usage html "$VIZ_OUT" --collect', "echo 'quoted' > \"$VIZ_OUT\"", 'a\\b'):
            with self.subTest(run=run):
                live = tomllib.loads(collect.table(run, '5m', '~/w'))['live']
                self.assertEqual(live, {'run': run, 'cwd': '~/w', 'every': '5m'})
        self.assertIn("run = 'scriv usage html \"$VIZ_OUT\" --collect'", collect.table(
            'scriv usage html "$VIZ_OUT" --collect', '5m'))   # a literal string: the command as typed
        self.assertEqual(tomllib.loads(collect.table('x', '1h', timeout='2h'))['live']['timeout'], '2h')


# ---------------------------------------------------------------------------
# viz publish --to live (slice a)
# ---------------------------------------------------------------------------

class Listed(Fresh):
    def test_listed_and_described(self):
        listed = json.loads(viz('targets', '--json').stdout)
        self.assertEqual([t['name'] for t in listed], ['preview', 'file', 'live'])
        self.assertTrue(listed[2]['builtin'])
        one = viz('targets', 'live').stdout
        self.assertIn('a collector keeps it current', one)
        self.assertIn('--run', one)


class Register(Fresh):
    def test_page_registration_and_first_run(self):
        result = self.register('clock', 'date > "$VIZ_OUT"; pwd > "$VIZ_PAGE_DIR/where"', '5m',
                               '--title', 'The clock')
        folder = LIVE / 'clock'
        self.assertEqual(result.stdout.strip().split(':', 2)[2].split('/', 1)[1], 'live/clock/')
        self.assertIn('first run: ok', result.stderr)
        self.assertTrue((folder / 'index.html').read_text().strip())       # the first run wrote the page
        self.assertEqual((folder / 'where').read_text().strip(), str(self.work))   # in the directory it ran in
        text = (folder / 'page.toml').read_text()
        self.assertTrue(text.startswith('# Published by viz publish --to live.'))
        data = tomllib.loads(text)
        self.assertEqual((data['title'], data['summary'], data['entry'], data['format']),
                         ('The clock', 'The time, every five minutes.', 'index.html', 'html'))
        self.assertEqual(data['live'], {'run': 'date > "$VIZ_OUT"; pwd > "$VIZ_PAGE_DIR/where"',
                                        'cwd': str(self.work), 'every': '5m'})
        self.assertEqual(data['source'], {'generator': data['live']['run']})
        self.assertEqual(str(data['date']), TODAY)
        self.assertEqual(self.leftovers(), [])

    def test_cwd_is_written_from_home(self):
        home = Path.home() / 'proj'
        home.mkdir(exist_ok=True)
        self.register('here', 'pwd > "$VIZ_OUT"', '1m', '--cwd', str(home))
        self.assertEqual(self.manifest_of(LIVE / 'here')['live']['cwd'], '~/proj')
        self.assertEqual((LIVE / 'here' / 'index.html').read_text().strip(), str(home))

    def test_the_collector_gets_a_bare_environment(self):
        self.register('env', 'env > "$VIZ_OUT"', '1m', SECRET_TOKEN='leak', VIRTUAL_ENV='/somewhere',
                      LANG='C.UTF-8')
        env = dict(line.split('=', 1) for line in (LIVE / 'env' / 'index.html').read_text().splitlines()
                   if '=' in line)
        self.assertNotIn('SECRET_TOKEN', env)
        self.assertNotIn('VIRTUAL_ENV', env)
        self.assertNotIn('VIZ_DIR', env)
        self.assertEqual(env['HOME'], str(Path.home()))
        self.assertEqual(env['PATH'], f'{Path.home()}/.local/bin:/usr/local/bin:/usr/bin:/bin')
        self.assertEqual(env['LANG'], 'C.UTF-8')
        self.assertEqual(env['VIZ_LIVE_NAME'], 'env')
        self.assertTrue(env['VIZ_OUT'].endswith('/index.html'))
        self.assertEqual(Path(env['VIZ_OUT']).parent, Path(env['VIZ_PAGE_DIR']))
        self.assertLessEqual(set(env) - {'PWD', 'SHLVL', '_', 'OLDPWD'},
                             {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'LANG', 'XDG_RUNTIME_DIR', 'VIZ_OUT',
                              'VIZ_PAGE_DIR', 'VIZ_LIVE_NAME'})

    def test_a_failing_first_run_changes_nothing(self):
        result = self.register('clock', 'echo "it broke"; exit 3', '5m', ok=False)
        self.assertIn('first run failed: exit 3', result.stderr)
        self.assertIn('it broke', result.stderr)
        self.assertIn('nothing was published', result.stderr)
        self.assertFalse((LIVE / 'clock').exists())
        self.assertEqual(self.leftovers(), [])
        # An earlier registration stays as it was.
        self.register('clock', 'echo first > "$VIZ_OUT"', '5m')
        before = (LIVE / 'clock' / 'page.toml').read_bytes()
        self.register('clock', 'echo second > "$VIZ_OUT"; exit 1', '1m', ok=False)
        self.assertEqual((LIVE / 'clock' / 'page.toml').read_bytes(), before)
        self.assertEqual((LIVE / 'clock' / 'index.html').read_text(), 'first\n')
        missing = self.register('gone', 'true', '5m', '--cwd', str(self.work / 'nowhere'), ok=False)
        self.assertIn('nowhere', missing.stderr)
        self.assertEqual(self.leftovers(), [])

    def test_a_first_run_past_its_timeout_is_stopped_whole(self):
        pidfile = self.work / 'child.pid'
        folder = draft(self, f"run = 'sleep 60 & echo $! > {pidfile}; wait'\nevery = \"5m\"\ntimeout = \"1s\"\n")
        result = self.publish(str(folder), '--to', 'live', ok=False)
        self.assertIn('timed out after 1s', result.stderr)
        self.assertFalse(alive(int(pidfile.read_text())), 'the collector\'s child outlived its timeout')
        self.assertFalse((LIVE / 'report').exists())

    def test_republish_replaces_and_keeps_the_date(self):
        self.register('clock', 'echo one > "$VIZ_OUT"; echo x > "$VIZ_PAGE_DIR/extra"', '5m')
        page = LIVE / 'clock' / 'page.toml'
        page.write_text(page.read_text().replace(f'date = {TODAY}', 'date = 2026-01-02'))
        self.register('clock', 'echo two > "$VIZ_OUT"', '10m')
        data = self.manifest_of(LIVE / 'clock')
        self.assertEqual((str(data['date']), str(data['updated'])), ('2026-01-02', TODAY))
        self.assertEqual(data['live']['every'], '10m')
        self.assertEqual((LIVE / 'clock' / 'index.html').read_text(), 'two\n')
        self.assertFalse((LIVE / 'clock' / 'extra').exists())             # replaced whole
        self.assertEqual(self.leftovers(), [])

    def test_dry_run_writes_and_runs_nothing(self):
        marker = self.work / 'ran'
        result = self.register('clock', f'touch {marker}', '5m', '--dry-run')
        for expected in ('place:    ', '/live/clock/', '[live]', f"run = 'touch {marker}'", 'nothing was written'):
            self.assertIn(expected, result.stdout)
        self.assertFalse(marker.exists())
        self.assertFalse(LIVE.exists())

    def test_refusals(self):
        def refused(why, *args):
            with self.subTest(args=args):
                self.assertIn(why, self.publish(*args, ok=False).stderr)
        refused('needs --as', '--to', 'live', '--run', 'true', '--every', '5m', '--summary', 's')
        refused('needs --summary', '--to', 'live', '--as', 'x', '--run', 'true', '--every', '5m')
        refused('--run', '--to', 'live', '--as', 'x', '--every', '5m', '--summary', 's')
        refused('--every', '--to', 'live', '--as', 'x', '--run', 'true', '--summary', 's')
        refused('shortest is 30s', '--to', 'live', '--as', 'x', '--run', 'true', '--every', '5s', '--summary', 's')
        refused('duration', '--to', 'live', '--as', 'x', '--run', 'true', '--every', 'often', '--summary', 's')
        refused('plain name', '--to', 'live', '--as', '../x', '--run', 'true', '--every', '5m', '--summary', 's')
        refused('plain name', '--to', 'live', '--as', '.x', '--run', 'true', '--every', '5m', '--summary', 's')
        refused('--run is for --to live', str(draft(self)), '--to', 'file', '--out', str(self.work / 'o'),
                '--run', 'true')
        refused('--every is for --to live', '--to', 'preview', '--every', '5m')
        refused('which page', '--to', 'file')
        foreign = LIVE / 'mine'
        foreign.mkdir(parents=True)
        (foreign / 'notes.txt').write_text('mine')
        refused('viz did not publish', '--to', 'live', '--as', 'mine', '--run', 'true', '--every', '5m',
                '--summary', 's')
        self.assertEqual((foreign / 'notes.txt').read_text(), 'mine')
        (LIVE / 'afile').write_text('x')
        refused('not a folder', '--to', 'live', '--as', 'afile', '--run', 'true', '--every', '5m', '--summary', 's')
        self.assertEqual(self.leftovers(), [])

    def test_refuses_a_live_folder_others_can_write(self):
        LIVE.mkdir(parents=True)
        LIVE.chmod(0o777)
        try:
            self.assertIn('writable by another account', self.register(ok=False).stderr)
        finally:
            LIVE.chmod(0o755)
        shutil.rmtree(LIVE)
        elsewhere = SANDBOX / 'work' / 'elsewhere'
        elsewhere.mkdir()
        ROOT.mkdir(exist_ok=True)
        LIVE.symlink_to(elsewhere)
        self.assertIn('not a real folder', self.register(ok=False).stderr)
        self.assertEqual(list(elsewhere.iterdir()), [])


class PublishDraft(Fresh):
    def test_draft_with_its_live_table(self):
        folder = draft(self, 'run = \'echo "<p>live</p>" > "$VIZ_OUT"\'\nevery = "5m"\n')
        result = self.publish(str(folder), '--to', 'live')
        dest = LIVE / 'report'
        self.assertTrue(result.stdout.strip().endswith('/live/report/'))
        self.assertEqual(sorted(p.name for p in dest.iterdir()), ['index.html', 'page.toml', 'style.css'])
        self.assertEqual((dest / 'index.html').read_text(), '<p>live</p>\n')
        published = self.manifest_of(dest)
        self.assertEqual(published['live'], {'run': 'echo "<p>live</p>" > "$VIZ_OUT"', 'cwd': str(self.work),
                                             'every': '5m'})
        self.assertEqual(published['title'], 'report')
        self.assertEqual(published['source'], {'generator': 'build.py'})
        record = self.manifest_of(folder)['published']
        self.assertEqual([(r['target'], r['place'], r['url'].split('/', 3)[3]) for r in record],
                         [('live', str(dest), 'live/report/')])
        # Republished: the same place; the command line's --every over the draft's.
        self.publish(str(folder), '--to', 'live', '--every', '1h')
        self.assertEqual(self.manifest_of(dest)['live']['every'], '1h')
        self.assertEqual(len(self.manifest_of(folder)['published']), 2)
        self.assertEqual(self.leftovers(), [])

    def test_draft_without_a_collector_and_dry_run(self):
        folder = draft(self)
        self.assertIn('needs a collector', self.publish(str(folder), '--to', 'live', ok=False).stderr)
        self.assertIn('--title and --summary are for --to live without a page',
                      self.publish(str(folder), '--to', 'live', '--run', 'true', '--every', '5m', '--title', 't',
                                   ok=False).stderr)
        before = (folder / 'page.toml').read_bytes()
        dry = self.publish(str(folder), '--to', 'live', '--as', 'other', '--run', 'touch ran', '--every', '5m',
                           '--dry-run')
        self.assertIn("live:     run = 'touch ran'", dry.stdout)
        self.assertIn('/live/other/', dry.stdout)
        self.assertFalse(LIVE.exists())
        self.assertFalse((self.work / 'ran').exists())
        self.assertEqual((folder / 'page.toml').read_bytes(), before)


# ---------------------------------------------------------------------------
# viz collect (slice b)
# ---------------------------------------------------------------------------

def quietly(fn, *args):
    """FN(*ARGS) with what it prints captured; (its result, the text)."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        result = fn(*args)
    return result, out.getvalue()


def spec_of(case, name, run, every=30, timeout=10):
    """A Spec for a live page made by hand, past the 30s minimum the [live] table enforces."""
    folder = LIVE / name
    folder.mkdir(parents=True, exist_ok=True)
    return collect.Spec(name=name, folder=folder, run=run, every=every, timeout=timeout, cwd=str(case.work))


class Found(Fresh):
    def test_what_is_looked_at(self):
        self.register('good', 'true', '1m')
        LIVE.joinpath('.staged').mkdir()
        LIVE.joinpath('empty').mkdir()
        LIVE.joinpath('open').mkdir(mode=0o777)
        LIVE.joinpath('open').chmod(0o777)
        (LIVE / 'open' / 'page.toml').write_text((LIVE / 'good' / 'page.toml').read_text())
        LIVE.joinpath('linked').symlink_to(LIVE / 'good')
        LIVE.joinpath('wrong').mkdir()
        (LIVE / 'wrong' / 'page.toml').write_text('[live]\nrun = "true"\nevery = "often"\n')
        LIVE.joinpath('alias').mkdir()
        (LIVE / 'alias' / 'page.toml').symlink_to(LIVE / 'good' / 'page.toml')
        LIVE.joinpath('plain').mkdir()
        (LIVE / 'plain' / 'page.toml').write_text('title = "no collector"\n')
        pages = {p.name: p for p in collect.found()}
        self.assertEqual(sorted(pages), ['alias', 'empty', 'good', 'linked', 'open', 'plain', 'wrong'])
        self.assertIsInstance(pages['good'], collect.Spec)
        self.assertEqual(pages['good'].every, 60)
        for name, why in (('empty', 'no page.toml'), ('open', 'closed to others'), ('linked', 'real folder'),
                          ('wrong', 'duration'), ('alias', 'real file'), ('plain', 'no [live]')):
            with self.subTest(name=name):
                self.assertIsInstance(pages[name], collect.Problem)
                self.assertIn(why, pages[name].error)
        LIVE.chmod(0o777)
        try:
            self.assertEqual(collect.found(), [])   # a live folder others can write is not looked in at all
        finally:
            LIVE.chmod(0o755)

    def test_next_due(self):
        self.assertEqual(collect.next_due({}, 60), 0)
        self.assertEqual(collect.next_due({'started': 1000, 'finished': 1002}, 60), 1060)
        self.assertEqual(collect.next_due({'started': 1000, 'finished': 1060}, 60), 1060)
        self.assertEqual(collect.next_due({'started': 1000, 'finished': 1130}, 60), 1180)   # two skipped
        self.assertEqual(collect.next_due({'started': 1000, 'finished': 900, 'running': True}, 60), 1060)


class Schedule(Fresh):
    def test_due_after_the_first_run_and_logged(self):
        self.register('clock', 'echo tick; date > "$VIZ_OUT"', '1m')
        first = collect.load_state('clock')
        self.assertEqual((first['by'], first['ok'], first['every']), ('publish', True, '1m'))
        collector = collect.Collector()
        self.assertEqual(quietly(collector.tick, first['started'] + 30)[0], [])          # not due yet
        begun, _ = quietly(lambda: (collector.tick(first['started'] + 60), collector.wait(10))[0])
        self.assertEqual(begun, ['clock'])
        state = collect.load_state('clock')
        self.assertEqual((state['by'], state['exit'], state['ok'], state['skipped']), ('collect', 0, True, 0))
        self.assertGreater(state['started'], first['started'])
        log = (STATE / 'collect' / 'clock.log').read_text()
        self.assertEqual(log.count('tick\n'), 2)
        self.assertIn('(publish) echo tick', log)
        self.assertIn('(collect) echo tick', log)
        self.assertEqual(log.count(' ok in '), 2)

    def test_paused_and_problems(self):
        self.register('clock', 'echo tick', '1m')
        page = LIVE / 'clock' / 'page.toml'
        page.write_text(page.read_text().replace('# paused = true', 'paused = true'))
        collector = collect.Collector()
        self.assertEqual(quietly(collector.tick, 1e12)[0], [])
        page.write_text(page.read_text().replace('every = "1m"', 'every = "1x"'))
        said = quietly(collector.tick, 1e12)[1] + quietly(collector.tick, 1e12)[1]
        self.assertEqual(said.count('clock: cannot run'), 1)      # said once, not every look

    def test_no_overlap_and_skips_counted(self):
        s = spec_of(self, 'slow', 'sleep 2.5', every=1)
        collector = collect.Collector()
        thread = threading.Thread(target=quietly, args=(collector.one, s))
        collector.threads['slow'] = thread
        thread.start()
        time.sleep(0.5)
        self.assertTrue(collect.load_state('slow')['running'])
        (LIVE / 'slow' / 'page.toml').write_text('entry = "index.html"\n[live]\nrun = "true"\nevery = "30s"\n')
        self.assertEqual(quietly(collector.tick, 1e12)[0], [])     # due, but its run is still going
        thread.join(10)
        state = collect.load_state('slow')
        self.assertFalse(state.get('running'))
        self.assertEqual((state['ok'], state['skipped']), (True, 2))

    def test_timeout_stops_the_whole_group(self):
        pidfile = self.work / 'child.pid'
        s = spec_of(self, 'stuck', f'sleep 60 & echo $! > {pidfile}; wait', timeout=1)
        quietly(collect.Collector().one, s)
        state = collect.load_state('stuck')
        self.assertTrue(state['timed_out'])
        self.assertFalse(state['ok'])
        self.assertIn('timed out after 1s', (STATE / 'collect' / 'stuck.log').read_text())
        self.assertFalse(alive(int(pidfile.read_text())))

    def test_log_keeps_one_old_copy(self):
        s = spec_of(self, 'chatty', 'echo fresh')
        log = STATE / 'collect' / 'chatty.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_bytes(b'x' * (collect.LOG_MAX + 1))
        quietly(collect.Collector().one, s)
        self.assertEqual(Path(str(log) + '.1').stat().st_size, collect.LOG_MAX + 1)
        self.assertLess(log.stat().st_size, 1000)
        self.assertIn('fresh', log.read_text())

    def test_shutdown_ends_running_collectors(self):
        pidfile = self.work / 'child.pid'
        s = spec_of(self, 'long', f'sleep 60 & echo $! > {pidfile}; wait', timeout=120)
        collector = collect.Collector()
        thread = threading.Thread(target=quietly, args=(collector.one, s))
        collector.threads['long'] = thread
        thread.start()
        for _ in range(100):
            if pidfile.exists() and 'long' in collector.procs:
                break
            time.sleep(0.05)
        begin = time.monotonic()
        collector.shutdown()
        self.assertLess(time.monotonic() - begin, collect.GRACE)
        self.assertFalse(thread.is_alive())
        self.assertFalse(alive(int(pidfile.read_text())))
        self.assertIn('killed by signal 15', collect.load_state('long')['outcome'])


class Service(Fresh):
    def test_viz_collect_runs_once_per_account_and_status_shows_it(self):
        self.assertIn('collect:  no live pages', viz('status').stdout)
        result = self.register('clock', 'date > "$VIZ_OUT"', '1m')
        self.assertIn('viz collect is not running', result.stderr)
        (STATE / 'collect' / 'clock.json').unlink()        # never run: due at once
        status = viz('status').stdout
        self.assertIn('collect:  not running, so nothing rewrites 1 live page: systemctl', status)
        self.assertIn('clock  every 1m; not run yet', status)
        proc = subprocess.Popen([sys.executable, str(VIZ), 'collect'], cwd=SANDBOX, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        try:
            for _ in range(200):
                if collect.load_state('clock').get('by') == 'collect' and 'finished' in collect.load_state('clock'):
                    break
                time.sleep(0.05)
            self.assertTrue(collect.load_state('clock')['ok'])
            again = viz('collect')
            self.assertNotEqual(again.returncode, 0)
            self.assertIn(f'already runs (pid {proc.pid})', again.stderr)
            status = viz('status').stdout
            self.assertIn(f'collect:  running (pid {proc.pid}); 1 live page', status)
            self.assertRegex(status, r'clock  every 1m; last \d\d:\d\d, ok in [\d.]+s; next \d\d:\d\d')
            self.assertNotIn('is not running', self.register('other', 'true', '1m').stderr)
        finally:
            proc.send_signal(signal.SIGTERM)
            out, _ = proc.communicate(timeout=20)
        self.assertEqual(proc.returncode, 0, out)
        self.assertIn('clock: ok in', out)
        self.assertIn('viz collect: stopping', out)
        self.assertIn('collect:  not running', viz('status').stdout)
        broken = LIVE / 'other' / 'page.toml'
        broken.write_text(broken.read_text().replace("run = 'true'", 'run = ""'))
        self.assertIn('other  BROKEN: [live] run', viz('status').stdout)


if __name__ == '__main__':
    try:
        unittest.main(verbosity=1)
    finally:
        shutil.rmtree(SANDBOX, ignore_errors=True)
