#!/usr/bin/env python3
"""bin/viz beyond the server: viz path and page.toml. Offline, on temporary homes and repositories."""
import datetime
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
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
    'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull,
    'GIT_AUTHOR_NAME': 'A. Person', 'GIT_AUTHOR_EMAIL': 'a.person@example.com',
    'GIT_COMMITTER_NAME': 'A. Person', 'GIT_COMMITTER_EMAIL': 'a.person@example.com',
}
os.environ.update(BASE_ENV)
for name in ('CLAUDE_CODE_SESSION_ID', 'VSCODE_IPC_HOOK_CLI', 'PROJECT_DIR'):
    os.environ.pop(name, None)
(SANDBOX / 'home').mkdir()
sys.path.insert(0, str(REPO / 'lib'))

from viz import manifest

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


if __name__ == '__main__':
    try:
        unittest.main(verbosity=1)
    finally:
        shutil.rmtree(SANDBOX, ignore_errors=True)
