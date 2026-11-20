#!/usr/bin/env python3
"""bin/viz beyond the server: viz path, page.toml, viz bundle and look, viz targets and viz publish. Offline, on temporary homes and repositories."""
import ast
import contextlib
import datetime
import fcntl
import hashlib
import io
import json
import os
import pty
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.parse
from pathlib import Path

import tomllib

REPO = Path(__file__).resolve().parents[1]
VIZ = REPO / 'bin' / 'viz'
# Everything viz reads or writes lives under one temporary directory, set before the package is imported
# (lib/viz/config.py reads the environment once).
SANDBOX = Path(tempfile.mkdtemp(prefix='viz-core-'))
BASE_ENV = {
    'HOME': str(SANDBOX / 'home'), 'VIZ_DIR': str(SANDBOX / 'viz'), 'VIZ_STATE': str(SANDBOX / 'state'),
    'VIZ_CONFIG': str(SANDBOX / 'config'), 'XDG_RUNTIME_DIR': str(SANDBOX / 'run'),
    # uv does not follow HOME to its cache: point it, and Playwright, into the sandbox, offline.
    'UV_CACHE_DIR': str(SANDBOX / 'uv'), 'PLAYWRIGHT_BROWSERS_PATH': str(SANDBOX / 'browsers'), 'UV_OFFLINE': '1',
    'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull,
    'GIT_AUTHOR_NAME': 'A. Person', 'GIT_AUTHOR_EMAIL': 'a.person@example.com',
    'GIT_COMMITTER_NAME': 'A. Person', 'GIT_COMMITTER_EMAIL': 'a.person@example.com',
}
# The browser tests reuse what this machine already has (see Look); read before HOME moves.
REAL_UV_CACHE = os.environ.get('UV_CACHE_DIR') or str(Path('~/.cache/uv').expanduser())
REAL_BROWSERS = os.environ.get('PLAYWRIGHT_BROWSERS_PATH') or str(Path('~/.cache/ms-playwright').expanduser())
os.environ.update(BASE_ENV)
for name in ('CLAUDE_CODE_SESSION_ID', 'VSCODE_IPC_HOOK_CLI', 'PROJECT_DIR'):
    os.environ.pop(name, None)
(SANDBOX / 'home').mkdir()
sys.path.insert(0, str(REPO / 'lib'))

from viz import formats, manifest

ROOT = Path(BASE_ENV['VIZ_DIR']).resolve()
TODAY = datetime.date.today().isoformat()  # noqa: DTZ011


def viz(*args, cwd=None, **env):
    """Run bin/viz in the sandbox; ENV adds variables, a None value removes one."""
    environ = dict(os.environ)
    for key, val in env.items():
        if val is None:
            environ.pop(key, None)
        else:
            environ[key] = val
    return subprocess.run([sys.executable, str(VIZ), *args], cwd=cwd or SANDBOX, env=environ,
                          capture_output=True, text=True, timeout=60, check=False)


def git(cwd, *args):
    return subprocess.run(['git', '-C', str(cwd), *args], capture_output=True, text=True, check=True).stdout


def make_repo(path):
    path.mkdir(parents=True)
    git(path, 'init', '-q', '-b', 'main')
    (path / 'build.py').write_text('print(1)\n')
    git(path, 'add', '-A')
    git(path, 'commit', '-q', '-m', 'first')
    return path


class Fresh(unittest.TestCase):
    """Each test starts with an empty VIZ_DIR and no config."""

    def setUp(self):
        for name in ('viz', 'config', 'work'):
            shutil.rmtree(SANDBOX / name, ignore_errors=True)
        (SANDBOX / 'work').mkdir()
        self.work = SANDBOX / 'work'

    def path(self, *args, **env):
        result = viz('path', *args, cwd=env.pop('cwd', self.work), **env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return Path(result.stdout.strip())

    def manifest_of(self, folder):
        return tomllib.loads((folder / 'page.toml').read_text())


class PathLayout(Fresh):
    def test_layout(self):
        day = ROOT / TODAY
        for name, printed, entry in (
                ('report', day / 'report', None),
                ('chart.html', day / 'chart' / 'index.html', 'index.html'),
                ('deck.htm', day / 'deck' / 'index.html', 'index.html'),
                ('brief/index.html', day / 'brief' / 'index.html', 'index.html'),
                ('slides.pdf', day / 'slides' / 'slides.pdf', 'slides.pdf'),
                ('plot.svg', day / 'plot' / 'plot.svg', 'plot.svg'),
                ('study/parts/one.html', day / 'study' / 'parts' / 'one.html', 'parts/one.html')):
            with self.subTest(name=name):
                self.assertEqual(self.path(name), printed)
                folder = day / Path(name).parts[0] if '/' in name else day / Path(name).stem
                self.assertTrue(folder.is_dir())
                self.assertTrue(printed.parent.is_dir())
                data = self.manifest_of(folder)
                self.assertEqual(data.get('entry'), entry)
                if entry:
                    self.assertEqual(data['format'], manifest.format_of(entry))
                else:
                    self.assertNotIn('format', data)
        self.assertEqual(manifest.format_of('deck.htm'), 'html')

    def test_refusals(self):
        for name in ('../escape.html', '/abs/page.html', 'a/../../b.html'):
            with self.subTest(name=name):
                result = viz('path', name, cwd=self.work)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('relative path', result.stderr)
        (ROOT / TODAY).mkdir(parents=True)
        (ROOT / TODAY / 'taken').write_text('a file from before folders')
        result = viz('path', 'taken.html', cwd=self.work)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not a directory', result.stderr)

    def test_never_overwritten(self):
        folder = self.path('report').parent / 'report'
        mine = '# my notes\ntitle = "Mine"\nsummary = "kept"\n'
        (folder / 'page.toml').write_text(mine)
        result = viz('path', 'report/index.html', '--title', 'Other', cwd=self.work)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('left as it is', result.stderr)
        self.assertEqual((folder / 'page.toml').read_text(), mine)
        self.assertEqual(viz('path', 'report/data.json', cwd=self.work).stderr, '')   # no flags, no note
        self.assertEqual((folder / 'page.toml').read_text(), mine)


class Stub(Fresh):
    def test_fields(self):
        folder = self.path('pr51.html', '--title', 'PR 51: the cache', '--kind', 'review',
                           '--project', 'proj').parent
        text = (folder / 'page.toml').read_text()
        data = tomllib.loads(text)
        self.assertEqual(data['title'], 'PR 51: the cache')
        self.assertEqual(data['kind'], 'review')
        self.assertEqual(data['project'], 'proj')
        self.assertEqual(data['summary'], '')
        self.assertEqual(data['source']['generator'], '')
        self.assertEqual(data['date'], datetime.date.fromisoformat(TODAY))
        self.assertEqual(data['updated'], data['date'])
        self.assertEqual(text.count('# fill in'), 2)
        self.assertLess(text.index('# fill in'), text.index('summary ='))
        self.assertLess(text.rindex('# fill in'), text.index('generator ='))
        self.assertEqual(data['source']['dir'], str(self.work))
        self.assertNotIn('repo', data['source'])   # not in a repository
        self.assertEqual(manifest.missing(data), ['summary', 'source.generator'])

    def test_title_defaults_to_the_folder(self):
        self.assertEqual(self.manifest_of(self.path('weekly'))['title'], 'weekly')

    def test_repository_provenance(self):
        repo = make_repo(self.work / 'proj')
        git(repo, 'remote', 'add', 'origin', 'https://someone:s3cret@git.example.com/me/proj.git')
        sub = repo / 'src'
        sub.mkdir()
        folder = self.path('a.html', cwd=sub, CLAUDE_CODE_SESSION_ID='session-1').parent
        source = self.manifest_of(folder)['source']
        self.assertEqual(source['dir'], str(sub))
        self.assertEqual(source['repo'], str(repo))
        self.assertEqual(source['commit'], git(repo, 'rev-parse', '--short', 'HEAD').strip())
        self.assertIs(source['dirty'], False)
        self.assertEqual(source['remote'], 'https://git.example.com/me/proj.git')
        self.assertEqual(source['session'], 'session-1')
        self.assertTrue(source['host'])
        self.assertEqual(self.manifest_of(folder)['project'], 'proj')
        (repo / 'untracked.txt').write_text('new')   # only changes to tracked files make a tree dirty
        self.assertIs(self.manifest_of(self.path('u.html', cwd=repo).parent)['source']['dirty'], False)
        (repo / 'build.py').write_text('print(2)\n')
        self.assertIs(self.manifest_of(self.path('b.html', cwd=repo).parent)['source']['dirty'], True)
        self.assertNotIn('session', self.manifest_of(self.path('c.html', cwd=repo).parent)['source'])

    def test_config(self):
        repo = make_repo(self.work / 'proj')
        config = SANDBOX / 'config'
        config.mkdir()
        (config / 'config.toml').write_text(
            '[provenance]\nenv = ["ROLE", "UNSET_ONE"]\nsession_env = "MY_SESSION"\n'
            'project_from = "PROJECT_DIR"\n')
        folder = self.path('a.html', cwd=repo, ROLE='reviewer', MY_SESSION='s-2', CLAUDE_CODE_SESSION_ID='no',
                           PROJECT_DIR='/somewhere/team-pages/')
        data = self.manifest_of(folder.parent)
        self.assertEqual(data['source']['env'], {'ROLE': 'reviewer'})
        self.assertEqual(data['source']['session'], 's-2')
        self.assertEqual(data['project'], 'team-pages')
        (config / 'config.toml').write_text('[provenance\n')
        result = viz('path', 'b.html', cwd=repo)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('config.toml', result.stderr)


class Locate(Fresh):
    def test_folder_page(self):
        folder = self.path('report.html').parent
        (folder / 'index.html').write_text('<p>r</p>')
        (folder / 'parts').mkdir()
        (folder / 'parts' / 'b.html').write_text('<p>b</p>')
        for given in (folder, folder / 'page.toml', folder / 'index.html', folder / 'parts' / 'b.html'):
            with self.subTest(given=given):
                page = manifest.locate(given)
                self.assertEqual(page.folder, folder)
                self.assertEqual(page.manifest, folder / 'page.toml')
                self.assertEqual(page.entry, folder / 'index.html')
                self.assertEqual(page.format, 'html')
                self.assertFalse(page.loose)

    def test_entry_from_the_file_when_the_manifest_has_none(self):
        folder = self.path('notes')
        (folder / 'notes.pdf').write_bytes(b'%PDF-1.4\n')
        page = manifest.locate(folder / 'notes.pdf')
        self.assertEqual((page.folder, page.entry, page.format), (folder, folder / 'notes.pdf', 'pdf'))
        self.assertEqual(manifest.locate(folder).entry, folder / 'index.html')

    def test_loose_files(self):
        old = ROOT / TODAY / 'old.html'   # a draft from before folders
        old.parent.mkdir(parents=True)
        old.write_text('<p>old</p>')
        reports = self.work / 'reports'
        reports.mkdir()
        (reports / 'report.html').write_text('<p>r</p>')
        (reports / 'report.pdf').write_bytes(b'%PDF-1.4\n')
        (reports / 'report.html.page.toml').write_text('title = "The HTML one"\n')
        for given, sidecar, title in ((old, ROOT / TODAY / 'old.html.page.toml', None),
                                      (reports / 'report.html', reports / 'report.html.page.toml', 'The HTML one'),
                                      (reports / 'report.pdf', reports / 'report.pdf.page.toml', None)):
            with self.subTest(given=given):
                page = manifest.locate(given)
                self.assertTrue(page.loose)
                self.assertEqual((page.manifest, page.entry), (sidecar, given))
                self.assertEqual(page.data.get('title'), title)

    def test_a_sidecar_wins_over_a_folder_manifest(self):
        folder = self.path('report.html').parent
        (folder / 'extra.svg').write_text('<svg/>')
        (folder / 'extra.svg.page.toml').write_text('title = "Just the figure"\n')
        page = manifest.locate(folder / 'extra.svg')
        self.assertTrue(page.loose)
        self.assertEqual(page.data['title'], 'Just the figure')


class Writing(unittest.TestCase):
    def test_append_keeps_every_byte(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'page.toml'
            original = '# a comment the agent wrote\ntitle = "T"   # trailing\n\n[source]\ngenerator = "by hand"'
            path.write_text(original)
            path.chmod(0o640)
            at = datetime.datetime(2026, 11, 20, 21, 40, tzinfo=datetime.UTC)
            manifest.append(path, 'published', {'target': 'file', 'at': at, 'place': '/tmp/x', 'pushed': False})
            manifest.append(path, 'published', {'target': 'team', 'at': at, 'place': '2026-11-20/pr51'})
            text = path.read_text()
            self.assertTrue(text.startswith(original + '\n'))
            data = tomllib.loads(text)
            self.assertEqual(data['source'], {'generator': 'by hand'})   # not swallowed by the new tables
            self.assertEqual([p['target'] for p in data['published']], ['file', 'team'])
            self.assertEqual(data['published'][0]['at'], at)
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)

    def test_append_refuses_what_it_cannot_extend(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'page.toml'
            path.write_text('published = "a string"\n')
            with self.assertRaises(ValueError):
                manifest.append(path, 'published', {'target': 'file'})
            self.assertEqual(path.read_text(), 'published = "a string"\n')
            self.assertEqual(os.listdir(tmp), ['page.toml'])

    def test_dumps_round_trips(self):
        data = {
            'title': 'Quotes " and \\ and\nnewlines, ünïcode', 'summary': 's', 'count': 3, 'ratio': 0.5,
            'ok': True, 'date': datetime.date(2026, 11, 20),
            'tags': ['a', 'b'], 'odd key': 'x',
            'links': [{'label': 'PR', 'url': 'https://example.com/pr/1'}, {'label': 'Run', 'url': 'u'}],
            'source': {'commit': 'abc1234', 'generator': 'build.py', 'env': {'ROLE': 'r'}, 'data': ['a.csv']},
            'empty': {},
        }
        text = manifest.dumps(data, comment='Published by viz.\n\nDo not edit.')
        self.assertTrue(text.startswith('# Published by viz.\n#\n# Do not edit.\n'))
        self.assertEqual(tomllib.loads(text), data)
        self.assertLess(text.index('title ='), text.index('[source]'))

    def test_missing_and_warnings(self):
        self.assertEqual(manifest.missing({}), ['title', 'summary', 'source.generator'])
        full = {'title': 't', 'summary': 's', 'source': {'generator': 'g'}}
        self.assertEqual(manifest.missing(full), [])
        self.assertEqual(manifest.missing(full, required=['project', 'title']), ['project'])
        self.assertEqual(manifest.missing({**full, 'source': 'odd'}), ['source.generator'])
        self.assertEqual(manifest.warnings({'kind': 'report'}), [])
        self.assertEqual(manifest.warnings({'kind': ''}), [])
        self.assertEqual(len(manifest.warnings({'kind': 'poster'})), 1)



def draft(case, name='report.html', summary='What the page shows.', generator='build.py', cwd=None):
    """A filled-in draft folder made by viz path, with a page, an asset and a generator."""
    entry = case.path(name, cwd=cwd or case.work)
    folder = entry.parent if entry.suffix else entry
    if entry.suffix in ('.html', '.htm'):
        entry.write_text('<html><head><link rel="stylesheet" href="style.css"></head><body>r</body></html>')
        (folder / 'style.css').write_text('body {}')
        (folder / 'data').mkdir(exist_ok=True)
        (folder / 'data' / 'points.json').write_text('[1, 2]')
        (folder / 'data' / 'raw.parquet').write_bytes(b'PAR1')
        (folder / '.shots').mkdir(exist_ok=True)
        (folder / '.shots' / 'light.png').write_bytes(b'png')
        (folder / 'build.py').write_text('print()')
        (folder / 'notes.md').write_text('notes')
    elif entry.suffix:
        entry.write_bytes(PDF)
    text = (folder / 'page.toml').read_text()
    text = text.replace('summary = ""', f'summary = "{summary}"', 1)
    text = text.replace('generator = ""', f'generator = "{generator}"', 1)
    (folder / 'page.toml').write_text(text)
    return folder


PDF = b'%PDF-1.4\n1 0 obj << /Type /Page >> endobj\n%%EOF\n'


def targets_dir():
    path = SANDBOX / 'config' / 'targets.d'
    path.mkdir(parents=True, exist_ok=True)
    return path


class Targets(Fresh):
    def test_builtins(self):
        result = viz('targets')
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertTrue(lines[0].startswith('preview') and 'built in' in lines[0], lines)
        self.assertTrue(lines[1].startswith('file') and 'whoever you hand the file to' in lines[1], lines)
        listed = json.loads(viz('targets', '--json').stdout)
        self.assertEqual([t['name'] for t in listed], ['preview', 'file', 'live'])
        self.assertEqual(listed[1]['required'], ['title', 'summary', 'source.generator'])
        one = viz('targets', 'file')
        self.assertIn('--out PATH', one.stdout)
        self.assertIn('whoever you hand', json.loads(viz('targets', 'file', '--json').stdout)['audience'])
        missing = viz('targets', 'nowhere')
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn('no target named nowhere', missing.stderr)

    def test_broken_files_are_listed_not_fatal(self):
        conf = targets_dir()
        (conf / 'preview.toml').write_text('type = "git"\n')
        (conf / 'bad.toml').write_text('type = \n')
        (conf / 'odd.toml').write_text('type = "ftp"\naudience = "someone"\n')
        (conf / '.hidden.toml').write_text('type = "ftp"\n')
        result = viz('targets')
        self.assertEqual(result.returncode, 0, result.stderr)
        text = result.stdout
        self.assertIn('cannot be redefined', text)
        self.assertIn('bad.toml', text)
        self.assertIn("type 'ftp' is not a configurable target type", text)
        self.assertNotIn('hidden', text)
        self.assertEqual(sum(1 for line in text.splitlines() if line.startswith('preview')), 2)
        self.assertIn('BROKEN', viz('targets', 'odd').stdout)
        status = viz('status')
        self.assertIn('targets:  3 (preview, file, live)', status.stdout)
        self.assertIn('broken:', status.stdout)
        refused = viz('publish', str(draft(self)), '--to', 'odd')
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn('cannot be used', refused.stderr)


class Compose(unittest.TestCase):
    def test_order_and_what_viz_sets(self):
        day = datetime.date(2026, 11, 22)
        first = datetime.datetime(2026, 11, 20, 12, 0, tzinfo=datetime.UTC)
        draft_data = {
            'title': 'Draft title', 'summary': 's', 'kind': '', 'state': 'draft-state', 'author': 'Draft Author',
            'date': datetime.date(2026, 11, 1), 'format': 'html', 'entry': 'main.html',
            'source': {'dir': '/home/me/src/proj', 'repo': '/home/me/src/proj', 'commit': 'abc1234', 'dirty': True,
                       'remote': 'git@example.com:me/proj.git', 'host': 'box1', 'session': 'sess',
                       'env': {'ROLE': 'r'}, 'generator': 'build.py', 'run': '77'},
            'to': {'team': {'state': 'current', 'alias': 'pr51'}, 'other': {'state': 'never'}},
            'live': {'run': 'x'}, 'bundle': {'exclude': ['*.csv']},
            'published': [{'target': 'other', 'at': datetime.datetime(2026, 11, 2, tzinfo=datetime.UTC)},
                          {'target': 'team', 'at': first, 'place': '2026-11-20/report'}],
        }
        data = manifest.compose(draft_data, 'team',
                                defaults=[{'author': 'Config Author', 'license': 'cc'},
                                          {'author': 'Target Author', 'state': 'shared', 'audience': 'team'}],
                                provenance=['commit', 'generator', 'remote'],
                                sets=[('alias', 'set-alias'), ('source.run', '99')],
                                day=day, entry='index.html', fmt='html')
        self.assertEqual(data['author'], 'Draft Author')          # the draft over the target's [manifest]
        self.assertEqual(data['license'], 'cc')                   # config.toml's defaults stay underneath
        self.assertEqual(data['audience'], 'team')                # target defaults fill what the draft lacks
        self.assertEqual(data['state'], 'current')                # [to.team] over the draft
        self.assertEqual(data['alias'], 'set-alias')              # --set over everything
        self.assertEqual(data['date'], first.astimezone().date())  # the first publication to this target
        self.assertEqual(data['updated'], day)
        self.assertEqual((data['entry'], data['format']), ('index.html', 'html'))
        self.assertEqual(data['source'], {'commit': 'abc1234', 'remote': 'git@example.com:me/proj.git',
                                          'generator': 'build.py'})   # run was set, but is not listed
        for gone in ('to', 'live', 'bundle', 'published', 'kind'):
            self.assertNotIn(gone, data)
        fresh = manifest.compose({'title': 't', 'source': {'host': 'h'}}, 'new', day=day)
        self.assertEqual(fresh['date'], day)
        self.assertNotIn('source', fresh)                          # nothing listed survived


class PublishFile(Fresh):
    def publish(self, *args, ok=True):
        result = viz('publish', *args, cwd=self.work)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def test_refuses_without_the_minimum(self):
        folder = self.path('bare')
        (folder / 'index.html').write_text('<p>x</p>')
        before = (folder / 'page.toml').read_bytes()
        result = self.publish(str(folder), '--to', 'file', '--out', str(self.work / 'out'), ok=False)
        self.assertIn('lacks summary, source.generator', result.stderr)
        self.assertFalse((self.work / 'out').exists())
        self.assertEqual((folder / 'page.toml').read_bytes(), before)
        loose = self.work / 'loose.html'
        loose.write_text('<p>l</p>')
        result = self.publish(str(loose), '--to', 'file', '--out', str(self.work / 'out'), ok=False)
        self.assertIn('loose.html.page.toml lacks title', result.stderr)
        self.assertIn('does not exist yet', result.stderr)

    def test_out_through_links(self):
        folder = draft(self)
        before = (folder / 'page.toml').read_bytes()
        into = self.work / 'into-page'
        into.symlink_to(folder, target_is_directory=True)
        elsewhere = self.work / 'elsewhere'
        elsewhere.mkdir()
        linked = self.work / 'linked-out'
        linked.symlink_to(elsewhere, target_is_directory=True)
        for args, said in (((str(into / 'copy'),), 'inside the page'), ((str(linked),), 'is a link')):
            with self.subTest(said=said):
                result = self.publish(str(folder), '--to', 'file', '--out', *args, ok=False)
                self.assertIn(said, result.stderr)
                result = viz('bundle', str(folder), '--out', *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(said, result.stderr)
                self.assertNotIn('Traceback', result.stderr)
        self.assertEqual(sorted(p.name for p in folder.iterdir() if not p.name.startswith('.')),
                         ['build.py', 'data', 'index.html', 'notes.md', 'page.toml', 'style.css'])
        self.assertEqual(list(elsewhere.iterdir()), [])
        self.assertEqual(sorted(p.name for p in self.work.iterdir()), ['elsewhere', 'into-page', 'linked-out'])
        self.assertEqual((folder / 'page.toml').read_bytes(), before)

    def test_folder_publish_record_and_republish(self):
        repo = make_repo(self.work / 'proj')
        folder = draft(self, cwd=repo)
        out = self.work / 'out'
        self.assertEqual(self.publish(str(folder), '--to', 'file', '--out', str(out)).stdout.strip(), str(out))
        self.assertEqual(sorted(p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file()),
                         ['data/points.json', 'index.html', 'page.toml', 'style.css'])
        published = (out / 'page.toml').read_text()
        self.assertTrue(published.startswith('# Published by viz publish'))
        data = tomllib.loads(published)
        self.assertEqual(data['source'], {'commit': git(repo, 'rev-parse', '--short', 'HEAD').strip(),
                                          'generator': 'build.py'})
        for private in (str(self.work), 'host', 'session', 'dirty'):
            self.assertNotIn(private, published)
        self.assertEqual(data['entry'], 'index.html')
        record = tomllib.loads((folder / 'page.toml').read_text())['published']
        self.assertEqual(len(record), 1)
        self.assertEqual((record[0]['target'], record[0]['place']), ('file', str(out)))
        self.assertEqual(record[0]['at'].tzinfo, datetime.UTC)
        # Republished without --out: the same place, replaced whole.
        (folder / 'style.css').unlink()
        (folder / 'index.html').write_text('<html><body>r, without its stylesheet</body></html>')
        self.assertEqual(self.publish(str(folder / 'index.html'), '--to', 'file').stdout.strip(), str(out))
        self.assertFalse((out / 'style.css').exists())
        self.assertEqual(len(tomllib.loads((folder / 'page.toml').read_text())['published']), 2)

    def test_bundle_include_and_exclude(self):
        folder = draft(self)
        with open(folder / 'page.toml', 'r+') as f:
            text = f.read().replace('\n[source]\n', '\n[bundle]\ninclude = ["data/*.parquet"]\n'
                                    'exclude = ["data/points.json"]\n\n[source]\n')
            f.seek(0)
            f.write(text)
        out = self.work / 'out'
        self.publish(str(folder), '--to', 'file', '--out', str(out))
        self.assertTrue((out / 'data' / 'raw.parquet').is_file())
        self.assertFalse((out / 'data' / 'points.json').exists())
        self.assertNotIn('bundle', tomllib.loads((out / 'page.toml').read_text()))

    def test_dry_run_changes_nothing(self):
        folder = draft(self)
        before = (folder / 'page.toml').read_bytes()
        out = self.work / 'out'
        result = self.publish(str(folder), '--to', 'file', '--out', str(out), '--dry-run', '--set', 'state=current')
        for expected in (f'place:    {out}', 'index.html', 'style.css', 'state = "current"', 'dry run'):
            self.assertIn(expected, result.stdout)
        self.assertNotIn('build.py\n', result.stdout.split('manifest:')[0])
        self.assertFalse(out.exists())
        self.assertEqual((folder / 'page.toml').read_bytes(), before)

    def test_where_it_will_not_write(self):
        folder = draft(self)
        foreign = self.work / 'mine'
        foreign.mkdir()
        (foreign / 'keep.txt').write_text('mine')
        for out, why in ((foreign, 'did not publish'), (folder / 'copy', 'inside the page'),
                         (self.work / 'page.html', 'as a folder'), (foreign / 'keep.txt', 'not a folder')):
            with self.subTest(out=out):
                self.assertIn(why, self.publish(str(folder), '--to', 'file', '--out', str(out), ok=False).stderr)
        self.assertEqual((foreign / 'keep.txt').read_text(), 'mine')
        self.assertIn('needs --out', self.publish(str(folder), '--to', 'file', ok=False).stderr)
        self.assertIn('cannot make pptx from html',
                      self.publish(str(folder), '--to', 'file', '--out', str(self.work / 'r.pptx'), '--format', 'pptx',
                                   ok=False).stderr)

    def test_loose_html_and_single_pdf(self):
        loose = self.work / 'chart.html'
        loose.write_text('<p>c</p>')
        (self.work / 'chart.html.page.toml').write_text(
            'title = "Chart"\nsummary = "s"\n[source]\ngenerator = "by hand"\nhost = "box1"\n')
        out = self.work / 'out'
        self.publish(str(loose), '--to', 'file', '--out', str(out))
        self.assertEqual(sorted(p.name for p in out.iterdir()), ['index.html', 'page.toml'])
        self.assertIn('[[published]]', (self.work / 'chart.html.page.toml').read_text())
        folder = draft(self, 'deck.pdf')
        pdf = self.work / 'deck-for-mail.pdf'
        self.publish(str(folder), '--to', 'file', '--out', str(pdf))
        self.assertTrue(pdf.read_bytes().startswith(b'%PDF'))
        self.assertEqual(tomllib.loads(Path(str(pdf) + '.page.toml').read_text())['format'], 'pdf')
        self.publish(str(folder), '--to', 'file')   # republish over its own earlier copy
        other = self.work / 'other.pdf'
        other.write_bytes(b'%PDF other')
        self.assertIn('exists', self.publish(str(folder), '--to', 'file', '--out', str(other), ok=False).stderr)


class PublishPreview(Fresh):
    def test_preview_is_viz_open(self):
        folder = draft(self)
        before = (folder / 'page.toml').read_bytes()
        dry = viz('publish', str(folder), '--to', 'preview', '--dry-run')
        self.assertIn(f'would open {folder}', dry.stdout)
        (SANDBOX / 'run').mkdir(mode=0o700, exist_ok=True)
        try:
            result = viz('publish', str(folder), '--to', 'preview')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f'/{TODAY}/report/', result.stdout)
        finally:
            viz('stop')
        self.assertEqual((folder / 'page.toml').read_bytes(), before)



FIXTURES = SANDBOX / 'fixtures'
FONT_CSS = 'https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap'
MONO_CSS = 'https://fonts.googleapis.com/css2?family=Mono'
D3 = 'https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js'
PLOT = 'https://cdn.jsdelivr.net/npm/@observablehq/plot@0.6.16/dist/plot.umd.min.js'
HLJS = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css'
PLOTLY = 'https://cdn.plot.ly/plotly-2.27.0.min.js'
KATEX = 'https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css'


def record(url, body):
    FIXTURES.mkdir(exist_ok=True)
    (FIXTURES / urllib.parse.quote(url, safe='')).write_bytes(body if isinstance(body, bytes) else body.encode())


def record_all():
    shutil.rmtree(FIXTURES, ignore_errors=True)
    record(FONT_CSS, "@font-face { font-family: 'Inter'; font-weight: 400;\n"
                     '  src: url(https://fonts.gstatic.com/s/inter/v13/inter-400.woff2) format("woff2"); }\n'
                     "@font-face { font-family: 'Inter'; font-weight: 700;\n"
                     '  src: url(https://fonts.gstatic.com/s/inter/v13/inter-700.woff2) format("woff2"); }\n')
    record(MONO_CSS, "@font-face { font-family: 'Mono'; src: url('https://fonts.gstatic.com/s/mono/v2/mono.woff2'); }")
    for face in ('inter/v13/inter-400', 'inter/v13/inter-700', 'mono/v2/mono'):
        record(f'https://fonts.gstatic.com/s/{face}.woff2', b'wOF2' + face.encode())
    record(D3, '/* d3 */')
    record(PLOT, '/* plot */')
    record(HLJS, '.hljs{}')
    record(PLOTLY, '/* plotly */')
    record(KATEX, '@font-face{src:url(fonts/KaTeX_Main-Regular.woff2) format("woff2")}')
    record('https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/fonts/KaTeX_Main-Regular.woff2', b'wOF2katex')


PORTABLE_PAGE = f"""<!doctype html><html><head>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="{FONT_CSS.replace('&', '&amp;')}" rel="stylesheet">
<link rel="stylesheet" href="style.css">
<link rel="stylesheet" href="{HLJS}">
<link rel="stylesheet" href="{KATEX}">
<link rel="canonical" href="https://example.com/report/">
<script src="{D3}" integrity="sha384-x" crossorigin="anonymous"></script>
<script src="{PLOT}"></script>
<script src="{PLOTLY}"></script>
</head><body>
<a href="https://example.com/elsewhere">a link out is fine</a>
<a href="parts/b.html">part b</a> <a href="parts/">the parts</a>
<img src="img/dot.png" alt="">
<script>fetch('data/points.json').then(r => r.json());</script>
</body></html>
"""


class Bundle(Fresh):
    def setUp(self):
        super().setUp()
        record_all()
        os.environ['VIZ_FETCH_FIXTURES'] = str(FIXTURES)
        shutil.rmtree(SANDBOX / 'home' / '.cache', ignore_errors=True)
        self.out = SANDBOX / 'work' / 'bundle'

    def tearDown(self):
        os.environ.pop('VIZ_FETCH_FIXTURES', None)

    def page(self, body=PORTABLE_PAGE, **files):
        folder = draft(self)
        (folder / 'index.html').write_text(body)
        (folder / 'style.css').write_text(f"@import url('{MONO_CSS}');\nbody {{ background: url(img/dot.png); }}\n")
        (folder / 'img').mkdir(exist_ok=True)
        (folder / 'img' / 'dot.png').write_bytes(b'\x89PNG')
        (folder / 'parts').mkdir(exist_ok=True)
        (folder / 'parts' / 'index.html').write_text('<a href="b.html">b</a>')
        (folder / 'parts' / 'b.html').write_text(f'<link rel="stylesheet" href="{FONT_CSS.replace("&", "&amp;")}">'
                                                 '<a href="../index.html">back</a>')
        for name, text in files.items():
            (folder / name.replace('__', '/')).write_text(text)
        return manifest.locate(folder)

    def bundle(self, page, policy=None):
        shutil.rmtree(self.out, ignore_errors=True)
        return formats.bundle(page, page.format, self.out, policy)

    def test_portable_page(self):
        report = self.bundle(self.page())
        self.assertEqual(report.problems, [])
        out = self.out
        index = (out / 'index.html').read_text()
        self.assertNotIn('fonts.g', index)                      # preconnects gone, link pointed at the copy
        self.assertIn('<link rel="stylesheet" href="fonts/fonts.css">', index)
        self.assertIn('href="../fonts/fonts.css"', (out / 'parts' / 'b.html').read_text())
        self.assertIn('@import url("fonts/fonts.css");', (out / 'style.css').read_text())
        css = (out / 'fonts' / 'fonts.css').read_text()
        self.assertIn('url(inter-400.woff2)', css)
        self.assertIn('url(mono.woff2)', css)
        self.assertNotIn('gstatic', css)
        fonts = json.loads((out / 'fonts' / 'MANIFEST.json').read_text())
        faces = {f['file']: f for f in fonts if f['file'] != 'fonts.css'}
        self.assertEqual(sorted(faces), ['inter-400.woff2', 'inter-700.woff2', 'mono.woff2'])
        self.assertEqual(faces['mono.woff2']['sha256'], hashlib.sha256(b'wOF2mono/v2/mono').hexdigest())
        self.assertEqual((out / 'fonts' / 'inter-700.woff2').read_bytes(), b'wOF2inter/v13/inter-700')
        for url, local in ((D3, 'vendor/d3@7.9.0/dist/d3.min.js'),
                           (PLOT, 'vendor/@observablehq__plot@0.6.16/dist/plot.umd.min.js'),
                           (HLJS, 'vendor/highlight.js@11.9.0/styles/github.min.css'),
                           (PLOTLY, 'vendor/plotly@2.27.0/plotly-2.27.0.min.js'),
                           (KATEX, 'vendor/katex@0.16.9/dist/katex.min.css')):
            with self.subTest(url=url):
                self.assertNotIn(url, index)
                self.assertIn(f'"{local}"', index)
                self.assertTrue((out / local).is_file())
        self.assertIn('integrity="sha384-x"', index)
        self.assertTrue((out / 'vendor/katex@0.16.9/dist/fonts/KaTeX_Main-Regular.woff2').is_file())
        vendor = {e['name']: e for e in json.loads((out / 'vendor' / 'MANIFEST.json').read_text())}
        self.assertEqual(vendor['d3']['version'], '7.9.0')
        self.assertEqual(vendor['d3']['url'], D3)
        self.assertEqual(vendor['d3']['sha256'], hashlib.sha256(b'/* d3 */').hexdigest())
        self.assertIn('https://example.com/elsewhere', index)   # links out are left alone
        self.assertNotIn('build.py', report.files)

    def test_font_cache(self):
        self.bundle(self.page())
        os.environ['VIZ_FETCH_FIXTURES'] = str(SANDBOX / 'no-fixtures')   # nothing recorded: no network at all
        report = self.bundle(self.page())
        self.assertEqual(report.problems, [])
        self.assertTrue((self.out / 'fonts' / 'inter-400.woff2').is_file())
        shutil.rmtree(SANDBOX / 'home' / '.cache')
        report = self.bundle(self.page())
        self.assertTrue(any('cannot download' in p.what for p in report.problems), report.problems)

    def test_refusals(self):
        body = (
            '<script src="https://cdn.jsdelivr.net/npm/d3@7/dist/d3.min.js"></script>\n'
            '<script src="https://unpkg.com/vega@latest"></script>\n'
            '<script src="https://example.com/lib.js"></script>\n'
            '<img src="https://example.com/a.png">\n'
            "<script>fetch('https://api.example.com/v1/x'); fetch('data/none.json');</script>\n"
            '<a href="missing.html">gone</a> <a href="../other/">sibling</a> <link rel="stylesheet" href="/abs.css">\n'
            '<style>body { background: url(https://example.com/bg.png) }</style>\n')
        report = self.bundle(self.page(body))
        found = [str(p) for p in report.problems]
        for line, words in ((1, 'd3@7, not an exact version'), (2, 'vega@latest, not an exact version'),
                            (3, 'loads https://example.com/lib.js'), (4, 'loads https://example.com/a.png'),
                            (5, 'loads https://api.example.com/v1/x'), (5, 'data/none.json is not in the bundle'),
                            (6, 'missing.html is not in the bundle'), (6, '../other/ points outside'),
                            (6, '/abs.css is relative to the site root'), (7, 'loads https://example.com/bg.png')):
            with self.subTest(words=words):
                self.assertTrue(any(f.startswith(f'index.html:{line}:') and words in f for f in found), found)
        relaxed = self.bundle(self.page(body), formats.Policy(network=True))
        self.assertFalse(any('loads' in p.what for p in relaxed.problems), relaxed.problems)
        self.assertTrue(any('not an exact version' in p.what for p in relaxed.problems))

    def test_downloads_stay_in_the_bundle(self):
        # A CDN path that climbs out of vendor/, a vendored stylesheet's asset that does, and a font file
        # named "..": each is a problem, and nothing is written outside the bundle.
        escape = 'https://cdn.jsdelivr.net/npm/x@1.0.0/../../../escaped.js'
        sheet = 'https://cdn.jsdelivr.net/npm/y@1.0.0/y.css'
        fonts = 'https://fonts.googleapis.com/css2?family=Odd'
        record(escape, '/* escaped */')
        record(sheet, 'a{background:url(../../../../escaped-asset.png)} b{background:url(../z@1.0.0/ok.png)}')
        record('https://cdn.jsdelivr.net/npm/escaped-asset.png', b'png')
        record('https://cdn.jsdelivr.net/npm/z@1.0.0/ok.png', b'png')
        record(fonts, "@font-face { font-family: 'Odd'; src: url(https://fonts.gstatic.com/s/odd/..); }")
        record('https://fonts.gstatic.com/s/odd/..', b'wOF2odd')
        report = self.bundle(self.page(f'<script src="{escape}"></script><link rel="stylesheet" href="{sheet}">'
                                       f'<link rel="stylesheet" href="{fonts}">'))
        self.assertFalse((self.work / 'escaped.js').exists())
        self.assertEqual([p for p in self.work.rglob('escaped*')], [])
        found = [str(p) for p in report.problems]
        self.assertTrue(any('escaped.js' in f and 'outside its package' in f for f in found), found)
        self.assertTrue(any('escaped-asset.png' in f and 'outside vendor/' in f for f in found), found)
        self.assertTrue((self.out / 'vendor' / 'z@1.0.0' / 'ok.png').is_file())
        self.assertTrue((self.out / 'fonts' / 'font').is_file())
        self.assertIn('url(font)', (self.out / 'fonts' / 'fonts.css').read_text())

    def test_links_out_of_the_page_are_not_followed(self):
        secret = self.work / 'secret'
        secret.mkdir()
        (secret / 'id_key.txt').write_text('PRIVATE')
        (secret / 'notes.css').write_text('PRIVATE')
        page = self.page()
        (page.folder / 'key.txt').symlink_to(secret / 'id_key.txt')
        (page.folder / 'img' / 'outside').symlink_to(secret, target_is_directory=True)
        (page.folder / 'same.css').symlink_to(page.folder / 'style.css')       # inside the page: copied
        report = self.bundle(page)
        self.assertNotIn('PRIVATE', ''.join(p.read_text(errors='replace') for p in self.out.rglob('*')
                                            if p.is_file()))
        self.assertFalse((self.out / 'key.txt').exists())
        self.assertFalse((self.out / 'img' / 'outside').exists())
        found = [str(p) for p in report.problems]
        for rel in ('key.txt', 'img/outside'):
            with self.subTest(rel=rel):
                self.assertIn(f'{rel}: is a link to outside the page; not copied', found)
        self.assertFalse((self.out / 'same.css').is_symlink())
        self.assertIn('img/dot.png', (self.out / 'same.css').read_text())

    def test_vendor_manifest_merge(self):
        page = self.page(f'<script src="{D3}"></script><script src="vendor/old.js"></script>')
        (page.folder / 'vendor').mkdir()
        (page.folder / 'vendor' / 'old.js').write_text('//')
        (page.folder / 'vendor' / 'MANIFEST.json').write_text('[{"name": "old", "url": "https://example.com/old"}]')
        self.bundle(page)
        names = [e['name'] for e in json.loads((self.out / 'vendor' / 'MANIFEST.json').read_text())]
        self.assertEqual(names, ['old', 'd3'])
        (page.folder / 'vendor' / 'MANIFEST.json').write_text('{"old": {}}')
        report = self.bundle(page)
        self.assertTrue(any('not a JSON list' in p.what for p in report.problems))

    def test_pdf_and_svg(self):
        folder = draft(self, 'deck.pdf')
        (folder / 'deck.pdf').write_bytes(b'%PDF-1.4\n%%EOF')
        page = manifest.locate(folder)
        self.assertIn('no pages', str(self.bundle(page).problems))
        (folder / 'deck.pdf').write_bytes(PDF)
        self.assertEqual(self.bundle(page).problems, [])
        folder = draft(self, 'fig.svg')
        (folder / 'fig.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg">\n'
                                        '<image href="https://example.com/x.png"/></svg>')
        problems = [str(p) for p in self.bundle(manifest.locate(folder)).problems]
        self.assertEqual(problems, ['fig.svg:2: loads https://example.com/x.png from outside the page'])

    def test_viz_bundle_command(self):
        page = self.page()
        default = SANDBOX / 'state' / 'bundles' / 'report'
        result = viz('bundle', str(page.folder))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], str(default))
        self.assertTrue((default / 'fonts' / 'fonts.css').is_file())
        self.assertTrue((default / 'page.toml').read_text().startswith('# Bundled by viz bundle'))
        (page.folder / 'index.html').write_text('<img src="https://example.com/a.png">')
        result = viz('bundle', str(page.folder))
        self.assertEqual(result.returncode, 1)
        self.assertIn('problem: index.html:1: loads https://example.com/a.png', result.stdout)
        self.assertFalse((default / 'vendor').exists())       # replaced whole, each run
        refused = viz('publish', str(page.folder), '--to', 'file', '--out', str(self.work / 'pub'))
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn('is not portable', refused.stderr)
        self.assertFalse((self.work / 'pub').exists())
        mine = self.work / 'mine'
        mine.mkdir()
        (mine / 'notes.txt').write_text('keep')
        self.assertIn('not a bundle viz wrote', viz('bundle', str(page.folder), '--out', str(mine)).stderr)
        self.assertEqual((mine / 'notes.txt').read_text(), 'keep')
        self.assertIn('inside the page', viz('bundle', str(page.folder), '--out', str(page.folder / 'b')).stderr)



# viz look and html to pdf need uv, Playwright and a Chromium Playwright has downloaded. They run only with
# VIZ_TEST_BROWSER=1, against uv's own cache and the browsers already on this machine (read before HOME was
# moved into the sandbox), offline; CI has no Chromium and skips them.
BROWSER_ENV = {'UV_CACHE_DIR': REAL_UV_CACHE, 'PLAYWRIGHT_BROWSERS_PATH': REAL_BROWSERS, 'UV_OFFLINE': '1'}
BROWSER = os.environ.get('VIZ_TEST_BROWSER') == '1' and shutil.which('uv') and any(
    Path(REAL_BROWSERS).glob('chromium*'))


class Look(Fresh):
    def test_wiring(self):
        self.assertEqual(formats.exports('html'), ['pdf'])
        for path in (REPO / 'lib' / 'viz').rglob('*.py'):
            tree = ast.parse(path.read_text())
            names = {a.name for n in ast.walk(tree) if isinstance(n, (ast.Import, ast.ImportFrom)) for a in n.names}
            names |= {n.module or '' for n in ast.walk(tree) if isinstance(n, ast.ImportFrom)}
            self.assertFalse({'look', 'playwright', 'playwright.sync_api'} & names - ({'playwright.sync_api'}
                             if path.name == 'look.py' else set()), f'{path.name} imports the browser side')
        from viz import browser
        command = browser.command(['page.html'])
        self.assertEqual(command[command.index('--with') + 1], f'playwright=={browser.PLAYWRIGHT}')
        self.assertTrue(command[-2].endswith('lib/viz/look.py'))

    def test_without_uv(self):
        folder = draft(self)
        bare = SANDBOX / 'bin'
        bare.mkdir(exist_ok=True)
        python = bare / 'python3'
        if not python.exists():
            python.symlink_to(sys.executable)
        result = viz('look', str(folder), PATH=str(bare))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('needs uv', result.stderr)
        self.assertIn('shows html and svg', viz('look', str(draft(self, 'deck.pdf'))).stderr)

    @unittest.skipUnless(BROWSER, 'set VIZ_TEST_BROWSER=1 on a machine with uv and a Playwright Chromium')
    def test_look_and_portable(self):
        folder = draft(self)
        (folder / 'index.html').write_text('<!doctype html><body><h1>Look</h1>'
                                           '<img src="https://example.com/x.png"></body>')
        result = viz('look', str(folder), **BROWSER_ENV)
        self.assertEqual(result.returncode, 0, result.stderr)
        for theme in ('light', 'dark'):
            self.assertTrue((folder / '.shots' / f'report-{theme}.png').stat().st_size > 1000)
        self.assertIn('needs the network: example.com', result.stdout)
        result = viz('look', '--portable', '--theme', 'light', str(folder), **BROWSER_ENV)
        self.assertTrue((folder / '.shots' / 'report-portable-light.png').is_file(), result.stderr)
        self.assertIn('bundle problem: index.html:1: loads https://example.com/x.png', result.stdout)
        self.assertIn('blocked: a bundle must load nothing from outside', result.stdout)

    @unittest.skipUnless(BROWSER, 'set VIZ_TEST_BROWSER=1 on a machine with uv and a Playwright Chromium')
    def test_html_to_pdf(self):
        folder = draft(self)
        (folder / 'index.html').write_text('<!doctype html><link rel="stylesheet" href="style.css">'
                                           '<body><h1>Printed</h1><p>One page.</p></body>')
        out = self.work / 'report.pdf'
        result = viz('publish', str(folder), '--to', 'file', '--out', str(out), '--format', 'pdf', **BROWSER_ENV)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(out.read_bytes().startswith(b'%PDF-'))
        self.assertEqual(tomllib.loads(Path(str(out) + '.page.toml').read_text())['format'], 'pdf')
        result = viz('bundle', str(folder), '--format', 'pdf', **BROWSER_ENV)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((SANDBOX / 'state' / 'bundles' / 'report' / 'report.pdf').is_file())



def in_terminal(args, answer=None, timeout=60):
    """Run bin/viz ARGS with stdin and stdout on a terminal; type ANSWER at its [y/N] prompt."""
    leader, follower = pty.openpty()
    proc = subprocess.Popen([sys.executable, str(VIZ), *args], cwd=SANDBOX, stdin=follower, stdout=follower,
                            stderr=follower)
    os.close(follower)
    output, deadline = b'', time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([leader], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(leader, 4096)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
            if answer is not None and b'[y/N]' in output:
                os.write(leader, answer.encode() + b'\n')
                answer = None
        elif proc.poll() is not None:
            break
    proc.wait(timeout=10)
    os.close(leader)
    return proc.returncode, output.decode(errors='replace')


class GitTarget(Fresh):
    def setUp(self):
        super().setUp()
        self.bare = self.work / 'origin.git'
        git(self.work, 'init', '-q', '--bare', '-b', 'gh-pages', str(self.bare))
        self.pages = self.work / 'team-pages'
        git(self.work, 'clone', '-q', str(self.bare), str(self.pages))
        git(self.pages, 'checkout', '-q', '-b', 'gh-pages')
        (self.pages / 'README.md').write_text('team pages\n')
        git(self.pages, 'add', '-A')
        git(self.pages, 'commit', '-q', '-m', 'start')
        git(self.pages, 'push', '-q', '-u', 'origin', 'gh-pages')
        self.other = self.work / 'other-clone'
        git(self.work, 'clone', '-q', '-b', 'gh-pages', str(self.bare), str(self.other))
        self.place = f'{TODAY}/report'

    def target(self, **keys):
        conf = {'type': 'git', 'description': 'Team pages', 'audience': 'Anyone on the company network',
                'rules': 'Nothing secret.\n\nAsk A. Person first.', 'checkout': str(self.pages),
                'branch': 'gh-pages', 'remote': 'origin', 'url': 'https://pages.example.com/me/team-pages/{folder}/',
                'push': 'auto', **keys}
        conf = {k: v for k, v in conf.items() if v is not None}
        (targets_dir() / 'team.toml').write_text(manifest.dumps(conf))

    def publish(self, folder, *args, ok=True):
        result = viz('publish', str(folder), '--to', 'team', *args, cwd=self.work)
        (self.assertEqual if ok else self.assertNotEqual)(result.returncode, 0, result.stdout + result.stderr)
        return result

    def remote_subjects(self):
        return git(self.bare, 'log', '--format=%s', 'gh-pages').splitlines()

    def head(self):
        return git(self.pages, 'rev-parse', '--short', 'HEAD').strip()

    def records(self, folder):
        return tomllib.loads((folder / 'page.toml').read_text()).get('published', [])

    def test_auto_publish_and_republish(self):
        self.target(provenance=['commit', 'generator', 'remote'])
        repo = make_repo(self.work / 'proj')
        git(repo, 'remote', 'add', 'origin', 'git@example.com:me/proj.git')
        folder = draft(self, cwd=repo)
        result = self.publish(folder)
        url = f'https://pages.example.com/me/team-pages/{self.place}/'
        self.assertEqual(result.stdout.strip(), url)
        placed = self.pages / self.place
        self.assertEqual(sorted(p.name for p in placed.iterdir()), ['data', 'index.html', 'page.toml', 'style.css'])
        published = tomllib.loads((placed / 'page.toml').read_text())
        self.assertEqual(published['source']['remote'], 'git@example.com:me/proj.git')
        self.assertNotIn('dir', published['source'])
        self.assertEqual(self.remote_subjects()[0], f'Publish {self.place}: report')
        record = self.records(folder)[-1]
        self.assertEqual((record['target'], record['place'], record['url'], record['commit'], record['pushed']),
                         ('team', self.place, url, self.head(), True))
        self.assertEqual(git(self.pages, 'status', '--porcelain'), '')
        # Republish: the same place, the folder replaced whole, one more commit.
        (folder / 'style.css').unlink()
        (folder / 'index.html').write_text('<p>second</p>')
        self.assertEqual(self.publish(folder).stdout.strip(), url)
        self.assertFalse((placed / 'style.css').exists())
        self.assertEqual(len(self.remote_subjects()), 3)
        self.assertEqual(self.publish(folder, '--as', 'renamed').stdout.strip(),
                         f'https://pages.example.com/me/team-pages/{TODAY}/renamed/')
        self.assertTrue((self.pages / TODAY / 'renamed' / 'index.html').is_file())
        # Nothing new: no commit, and the record says so.
        result = self.publish(folder, '--as', 'renamed')
        self.assertIn('nothing changed', result.stderr)
        self.assertEqual(len(self.remote_subjects()), 4)

    def test_refuses_an_unclean_checkout(self):
        self.target()
        folder = draft(self)
        before = (folder / 'page.toml').read_bytes()
        (self.pages / 'README.md').write_text('edited\n')
        self.assertIn('has changes', self.publish(folder, ok=False).stderr)
        git(self.pages, 'checkout', '-q', 'README.md')
        (self.pages / 'stray.txt').write_text('untracked')
        self.assertIn('has changes', self.publish(folder, ok=False).stderr)
        self.assertEqual((self.pages / 'stray.txt').read_text(), 'untracked')   # never cleaned away
        git(self.pages, 'config', 'status.showUntrackedFiles', 'no')    # hidden from a plain git status
        (self.pages / 'drafts').mkdir()
        (self.pages / 'drafts' / 'private.txt').write_text('untracked')
        self.assertIn('has changes', self.publish(folder, ok=False).stderr)
        self.assertEqual((self.pages / 'drafts' / 'private.txt').read_text(), 'untracked')
        shutil.rmtree(self.pages / 'drafts')
        git(self.pages, 'config', '--unset', 'status.showUntrackedFiles')
        (self.pages / 'stray.txt').unlink()
        git(self.pages, 'checkout', '-q', '-b', 'elsewhere')
        self.assertIn('is on elsewhere, not gh-pages', self.publish(folder, ok=False).stderr)
        git(self.pages, 'checkout', '-q', 'gh-pages')
        self.target(checkout=str(self.work / 'missing'))
        self.assertIn('does not exist', self.publish(folder, ok=False).stderr)
        self.target(checkout=str(self.pages / '.git'))
        self.assertIn('not the top of a git working tree', self.publish(folder, ok=False).stderr)
        self.assertEqual((folder / 'page.toml').read_bytes(), before)
        self.assertEqual(self.remote_subjects(), ['start'])

    def test_place_through_a_link_is_refused(self):
        self.target()
        folder = draft(self)
        outside = self.work / 'outside'
        (outside / 'report').mkdir(parents=True)
        (outside / 'report' / 'keep.txt').write_text('keep')
        (self.pages / TODAY).symlink_to(outside, target_is_directory=True)     # a committed link to a folder
        git(self.pages, 'add', '-A')
        git(self.pages, 'commit', '-q', '-m', 'link')
        result = self.publish(folder, ok=False)
        self.assertIn('through a link', result.stderr)
        self.assertEqual(sorted(p.name for p in outside.rglob('*')), ['keep.txt', 'report'])
        self.assertEqual(git(self.pages, 'status', '--porcelain'), '')
        self.assertEqual(self.records(folder), [])

    def test_after(self):
        self.target(after=['sh', '-c', 'echo "$VIZ_PLACE $VIZ_TARGET $VIZ_URL" > after.txt'])
        folder = draft(self)
        self.publish(folder)
        self.assertEqual((self.pages / 'after.txt').read_text().split(),
                         [self.place, 'team', f'https://pages.example.com/me/team-pages/{self.place}/'])
        self.assertEqual(git(self.pages, 'show', '--format=', '--name-only', 'HEAD').count('after.txt'), 1)
        start = self.head()
        (folder / 'index.html').write_text('<p>changed</p>')
        before = (folder / 'page.toml').read_bytes()
        for after, timeout, said in ((['sh', '-c', 'echo junk > junk.txt; rm README.md; echo it broke; exit 3'], None,
                                      'it broke'),
                                     (['sleep', '5'], 1, 'ran past 1 s')):
            with self.subTest(said=said):
                self.target(after=after, after_timeout=timeout)
                result = self.publish(folder, ok=False)
                self.assertIn(said, result.stderr)
                self.assertIn('the checkout is reset', result.stderr)
                self.assertEqual(git(self.pages, 'status', '--porcelain'), '')
                self.assertEqual(self.head(), start)
                self.assertNotIn('changed', (self.pages / self.place / 'index.html').read_text())
                self.assertEqual((folder / 'page.toml').read_bytes(), before)

    def test_lock(self):
        self.target()
        folder = draft(self)
        gitdir = Path(git(self.pages, 'rev-parse', '--absolute-git-dir').strip())
        with open(gitdir / 'viz-publish.lock', 'a') as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            proc = subprocess.Popen([sys.executable, str(VIZ), 'publish', str(folder), '--to', 'team'],
                                    cwd=self.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            time.sleep(2)
            self.assertIsNone(proc.poll(), 'publish did not wait for the lock')
            self.assertEqual(self.remote_subjects(), ['start'])
        _out, err = proc.communicate(timeout=60)
        self.assertEqual(proc.returncode, 0, err)
        self.assertEqual(len(self.remote_subjects()), 2)
        # The checkout is checked again once the lock is held: whoever held it may have left changes.
        (folder / 'index.html').write_text('<p>waited</p>')
        with open(gitdir / 'viz-publish.lock', 'a') as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            proc = subprocess.Popen([sys.executable, str(VIZ), 'publish', str(folder), '--to', 'team'],
                                    cwd=self.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            time.sleep(2)
            (self.pages / 'half-done.txt').write_text('another publish, interrupted')
        _out, err = proc.communicate(timeout=60)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn('has changes', err)
        self.assertEqual((self.pages / 'half-done.txt').read_text(), 'another publish, interrupted')
        self.assertEqual(len(self.remote_subjects()), 2)

    def test_push_never_and_ask_without_a_terminal(self):
        self.target(push='never', remote=None)
        folder = draft(self)
        result = self.publish(folder)
        self.assertIn('push = never', result.stderr)
        self.assertEqual(self.remote_subjects(), ['start'])
        self.assertIs(self.records(folder)[-1]['pushed'], False)
        refused = viz('publish', '--to', 'team', '--push')
        self.assertIn('by hand', refused.stderr)
        git(self.pages, 'reset', '-q', '--hard', 'origin/gh-pages')
        self.target(push='ask')
        (folder / 'index.html').write_text('<p>asked</p>')
        result = self.publish(folder)
        self.assertIn('viz publish --to team --push', result.stderr)
        self.assertEqual(self.remote_subjects(), ['start'])
        self.assertIs(self.records(folder)[-1]['pushed'], False)
        refused = viz('publish', '--to', 'team', '--push')
        self.assertEqual(refused.returncode, 1)
        self.assertIn('needs a terminal', refused.stderr)
        self.assertEqual(self.remote_subjects(), ['start'])
        code, out = in_terminal(['publish', '--to', 'team', '--push'], answer='n')
        self.assertEqual((code, self.remote_subjects()), (1, ['start']), out)
        code, out = in_terminal(['publish', '--to', 'team', '--push'], answer='y')
        self.assertEqual(code, 0, out)
        self.assertIn(f'{TODAY}/report/index.html', out)          # the stat shown before asking
        self.assertEqual(len(self.remote_subjects()), 2)           # the never commit was reset away
        code, out = in_terminal(['publish', '--to', 'team', '--push'])
        self.assertIn('nothing waits', out)

    def test_ask_at_a_terminal(self):
        self.target(push='ask')
        folder = draft(self)
        code, out = in_terminal(['publish', str(folder), '--to', 'team'], answer='y')
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.remote_subjects()), 2)
        (folder / 'index.html').write_text('<p>no</p>')
        code, out = in_terminal(['publish', str(folder), '--to', 'team', '-m', 'the waiting one'], answer='n')
        self.assertEqual(code, 0, out)
        self.assertIn('not pushed', out)
        self.assertEqual(len(self.remote_subjects()), 2)
        self.assertIs(self.records(folder)[-1]['pushed'], False)
        # The question shows every commit the push would send, not only the newest.
        (folder / 'index.html').write_text('<p>yes</p>')
        code, out = in_terminal(['publish', str(folder), '--to', 'team', '-m', 'the new one'], answer='y')
        self.assertEqual(code, 0, out)
        asked = out.split('[y/N]')[0]
        self.assertIn('the waiting one', asked)
        self.assertIn('the new one', asked)
        self.assertEqual(self.remote_subjects()[:2], ['the new one', 'the waiting one'])

    def race(self, path, text):
        """An after command that pushes PATH from another clone while viz publishes: a rejected push."""
        return ['sh', '-c', (f'cd {self.other} && git pull -q && mkdir -p "$(dirname "{path}")" && '
                             f'echo {text} > "{path}" && git add -A && git commit -qm race && git push -q')]

    def test_rejected_push(self):
        self.target(after=self.race('race.txt', 'theirs'))
        folder = draft(self)
        self.publish(folder)
        self.assertEqual(self.remote_subjects()[:2], [f'Publish {self.place}: report', 'race'])
        self.assertIs(self.records(folder)[-1]['pushed'], True)
        self.assertEqual(self.records(folder)[-1]['commit'], self.head())   # the rebased commit
        # A conflicting push: the rebase fails, the commit stays here, unpushed, and no rebase is left open.
        (folder / 'index.html').write_text('<p>ours</p>')
        self.target(after=self.race(f'{self.place}/index.html', 'theirs'))
        result = self.publish(folder)
        self.assertIn('the commit is kept', result.stderr)
        self.assertIs(self.records(folder)[-1]['pushed'], False)
        self.assertEqual(git(self.pages, 'log', '-1', '--format=%s'), f'Publish {self.place}: report\n')
        self.assertFalse((Path(git(self.pages, 'rev-parse', '--absolute-git-dir').strip()) / 'rebase-merge').exists())
        self.assertEqual(git(self.pages, 'status', '--porcelain'), '')

    def test_a_hung_rebase_is_aborted(self):
        # A push is rejected and the rebase onto the remote hangs (here, a hook that sleeps): viz gives up
        # on it cleanly, aborting the rebase and keeping the commit, instead of leaving the checkout mid-rebase.
        from viz import targets
        from viz.targets import git as git_type
        self.target()
        (self.other / 'theirs.txt').write_text('theirs')
        git(self.other, 'add', '-A')
        git(self.other, 'commit', '-q', '-m', 'theirs')
        git(self.other, 'push', '-q')
        (self.pages / 'ours.txt').write_text('ours')
        git(self.pages, 'add', '-A')
        git(self.pages, 'commit', '-q', '-m', 'ours')
        hook = self.pages / '.git' / 'hooks' / 'post-checkout'
        hook.write_text('#!/bin/sh\nexec sleep 30 </dev/null >/dev/null 2>&1\n')
        hook.chmod(0o755)
        target = targets.find('team')
        self.assertIsInstance(target, git_type.GitTarget)
        saved = git_type.GIT_TIMEOUT
        git_type.GIT_TIMEOUT = 3
        try:
            with contextlib.redirect_stderr(io.StringIO()) as err:
                pushed = target.push()
        finally:
            git_type.GIT_TIMEOUT = saved
        self.assertIs(pushed, False)
        self.assertIn('the commit is kept', err.getvalue())
        gitdir = self.pages / '.git'
        self.assertFalse((gitdir / 'rebase-merge').exists() or (gitdir / 'rebase-apply').exists())
        self.assertEqual(git(self.pages, 'log', '-1', '--format=%s'), 'ours\n')
        self.assertEqual(git(self.pages, 'status', '--porcelain'), '')

    def test_dry_run_listing_and_config(self):
        self.target(required=['project'], after=['true'])
        folder = draft(self)
        self.assertIn('lacks project', self.publish(folder, ok=False).stderr)
        text = (folder / 'page.toml').read_text().replace('kind = ""', 'kind = ""\nproject = "proj"', 1)
        (folder / 'page.toml').write_text(text)
        result = self.publish(folder, '--dry-run')
        for expected in (f'place:    {self.place}', 'push:     auto', f'commit:   Publish {self.place}: report',
                         'after:    true', 'pulls from origin'):
            self.assertIn(expected, result.stdout)
        self.assertEqual(self.remote_subjects(), ['start'])
        self.assertFalse((self.pages / TODAY).exists())
        shown = viz('targets', 'team').stdout
        for expected in ('Anyone on the company network', 'Ask A. Person first.', 'push:        auto',
                         'required:    title, summary, source.generator, project', 'checkout:'):
            self.assertIn(expected, shown)
        listed = viz('targets').stdout
        self.assertIn('team', listed)
        self.assertIn('git', listed)
        for keys, error in (({'checkout': None}, 'checkout is required'), ({'push': 'sometimes'}, 'auto, ask or never'),
                            ({'remote': None}, 'needs a remote'), ({'folder': '{nope}/{slug}'}, 'placeholder'),
                            ({'after': 'make'}, 'after should be list'), ({'colour': 'red'}, "unknown key 'colour'")):
            with self.subTest(error=error):
                self.target(**keys)
                self.assertIn(error, viz('targets').stdout)
        self.target(folder='{project}/{slug}', url='https://pages.example.com/{project}/{slug}/',
                    message='{project}: {title}')
        self.assertEqual(self.publish(folder).stdout.strip(), 'https://pages.example.com/proj/report/')
        self.assertTrue((self.pages / 'proj' / 'report' / 'index.html').is_file())
        self.assertEqual(self.remote_subjects()[0], 'proj: report')
        (folder / 'index.html').write_text('<p>again</p>')
        self.publish(folder, '-m', 'Fix the {braces} in the legend')
        self.assertEqual(self.remote_subjects()[0], 'Fix the {braces} in the legend')


class ServerNeverPublishes(unittest.TestCase):
    """The server reads files a browser page can reach, so it must never be able to publish (design 12)."""

    def imports(self, module):
        path = REPO / 'lib' / 'viz' / (module.replace('.', '/') + '.py')
        if not path.exists():
            path = path.with_suffix('') / '__init__.py'
        found = set()
        for node in ast.walk(ast.parse(path.read_text())):
            if isinstance(node, ast.ImportFrom) and node.level:
                base = module.split('.')[:len(module.split('.')) - node.level + (path.name == '__init__.py')]
                if node.module:
                    found.add('.'.join([*base, node.module]))
                else:   # from . import x: x is a module of the package
                    found |= {'.'.join([*base, a.name]) for a in node.names}
            elif isinstance(node, (ast.Import, ast.ImportFrom)):
                names = [a.name for a in node.names] if isinstance(node, ast.Import) else [node.module]
                found |= {n[4:] for n in names if n and n.startswith('viz.')}
        return found

    def test_import_graph(self):
        seen, todo = set(), ['serve']
        while todo:
            module = todo.pop()
            if module in seen or not ((REPO / 'lib/viz' / (module.replace('.', '/') + '.py')).exists()
                                      or (REPO / 'lib/viz' / module.replace('.', '/')).is_dir()):
                continue
            seen.add(module)
            todo += self.imports(module)
        self.assertIn('access', seen)
        for forbidden in ('targets', 'collect', 'formats', 'bundle', 'cli'):
            self.assertFalse(any(m == forbidden or m.startswith(forbidden + '.') for m in seen),
                             f'serve.py reaches {forbidden}: {sorted(seen)}')

    def test_endpoints(self):
        text = (REPO / 'lib' / 'viz' / 'serve.py').read_text()
        paths = set(re.findall(r"'/__viz/([\w.]*)", text)) - {''}
        self.assertEqual(paths, {'ping', 'version', 'reload.js', 'login', 'diff'})


if __name__ == '__main__':
    try:
        unittest.main(verbosity=1)
    finally:
        shutil.rmtree(SANDBOX, ignore_errors=True)
