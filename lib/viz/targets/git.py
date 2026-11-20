"""The `git` target type: pages placed in a folder of a git checkout, committed, and pushed by policy.

    type = "git"
    checkout = "~/src/team-pages"      # a working tree on BRANCH, used only for publishing
    branch = "gh-pages"
    remote = "origin"                  # needed unless push = "never"
    folder = "{date}/{slug}"           # placeholders: date, slug, project, year
    url = "https://pages.example.com/me/team-pages/{folder}/"
    after = ["python3", "tools/site.py", "index"]   # optional; run in the checkout before the commit
    after_timeout = 600                # seconds
    push = "ask"                       # auto | ask | never
    message = "Publish {folder}: {title}"

All or nothing, under a lock in the checkout's git directory: it refuses a checkout that is dirty or on
another branch, makes one commit per publish, and resets the checkout when the after command fails. `ask`
needs a person at a terminal; a run without one (an agent's) commits and stops, and the person pushes later
with `viz publish --to NAME --push` in their own terminal.
"""
import fcntl
import os
import posixpath
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import ClassVar

from .. import manifest
from . import Target, TargetError

PLACEHOLDERS = ('date', 'slug', 'project', 'year')
POLICIES = ('auto', 'ask', 'never')
LOCK_WAIT = 120   # seconds another publish to the same checkout may hold the lock


def terminal():
    """A person can answer: stdin and stdout are both a terminal."""
    return sys.stdin.isatty() and sys.stdout.isatty()


@dataclass
class GitTarget(Target):
    KEYS: ClassVar[dict] = {'checkout': str, 'branch': str, 'remote': str, 'folder': str, 'url': str, 'after': list,
            'after_timeout': int, 'push': str, 'message': str}
    REQUIRED_KEYS = ('checkout', 'branch')

    @property
    def checkout(self):
        return Path(self.config['checkout']).expanduser()

    @property
    def branch(self):
        return self.config['branch']

    @property
    def remote(self):
        return self.config.get('remote')

    @property
    def policy(self):
        return self.config.get('push', 'ask')

    def check_config(self):
        c = self.config
        if self.policy not in POLICIES:
            raise TargetError(f'push is {self.policy!r}; it takes auto, ask or never')
        if self.policy != 'never' and not self.remote:
            raise TargetError(f'push = "{self.policy}" needs a remote (or push = "never")')
        if not all(isinstance(a, str) for a in c.get('after', [])):
            raise TargetError('after is a command as a list of strings: ["python3", "tools/site.py", "index"]')
        dummy = dict.fromkeys(PLACEHOLDERS, 'x')
        for key, extra in (('folder', ()), ('url', ('folder',)), ('message', ('folder', 'title', 'target'))):
            try:
                c.get(key, '').format_map({**dummy, **dict.fromkeys(extra, 'x')})
            except (KeyError, ValueError, IndexError) as error:
                raise TargetError(f'{key} has a placeholder viz does not fill: {error}') from None

    def describe(self):
        lines = [f'checkout:    {self.config["checkout"]} (branch {self.branch}'
                 + (f', remote {self.remote})' if self.remote else ', no remote)'),
                 f'folder:      {self.config.get("folder", "{date}/{slug}")}',
                 f'push:        {self.policy}']
        if self.config.get('url'):
            lines.append(f'url:         {self.config["url"]}')
        if self.config.get('after'):
            lines.append(f'after:       {" ".join(self.config["after"])}')
        return lines

    # -- where -------------------------------------------------------------------------------

    def place(self, job, last, reuse):
        self.check_checkout()
        if reuse and last and last.get('place'):
            folder = str(last['place'])
        else:
            template = self.config.get('folder', '{date}/{slug}')
            if '{project}' in template and not self.project(job):
                raise TargetError(f'{self.name} files pages by project; set project in {job.page.manifest}')
            folder = template.format_map(self.values(job))
        folder = posixpath.normpath(folder.strip('/'))
        if folder in ('.', '') or folder.startswith('..') or folder.split('/')[0] == '.git':
            raise TargetError(f'{folder!r} is not a folder inside the checkout')
        url = self.config.get('url', '').format_map({**self.values(job), 'folder': folder})
        return folder, url, []

    def project(self, job):
        data = job.page.data
        own = data.get('to', {}).get(self.name, {}) if isinstance(data.get('to'), dict) else {}
        return own.get('project') or data.get('project') or self.manifest.get('project') or ''

    def values(self, job):
        """What the folder, url and message templates may name."""
        return {'date': job.first.isoformat(), 'year': str(job.first.year), 'slug': job.slug,
                'project': self.project(job)}

    def dry_run_lines(self, job):
        lines = [f'checkout: {self.checkout} on {self.branch}, clean'
                 + (f'; pulls from {self.remote} first' if self.remote and self.policy != 'never' else '')]
        if self.config.get('after'):
            lines.append(f'after:    {" ".join(self.config["after"])}')
        lines.append(f'commit:   {self.message(job)}')
        lines.append(f'push:     {self.policy}' + (' (at a terminal; else it commits and waits)'
                                                  if self.policy == 'ask' else ''))
        return lines

    def message(self, job):
        if job.message:   # -m, as written
            return job.message
        return self.config.get('message', 'Publish {folder}: {title}').format_map(
            {**self.values(job), 'folder': job.place, 'title': job.page.data.get('title') or job.slug,
             'target': self.name})

    # -- git ---------------------------------------------------------------------------------

    def git(self, *args, check=True, timeout=120):
        result = subprocess.run(['git', '-C', str(self.checkout), *args], capture_output=True, text=True,
                                timeout=timeout, check=False, stdin=subprocess.DEVNULL)
        if check and result.returncode != 0:
            raise TargetError(f'git {" ".join(args)} in {self.checkout} failed:\n'
                              + (result.stderr or result.stdout).strip())
        return result

    def check_checkout(self):
        if not self.checkout.is_dir():
            raise TargetError(f'{self.name}: the checkout {self.checkout} does not exist')
        top = self.git('rev-parse', '--show-toplevel', check=False)
        if top.returncode != 0 or Path(top.stdout.strip()).resolve() != self.checkout.resolve():
            raise TargetError(f'{self.name}: {self.checkout} is not the top of a git working tree')
        branch = self.git('symbolic-ref', '--quiet', '--short', 'HEAD', check=False).stdout.strip()
        if branch != self.branch:
            raise TargetError(f'{self.name}: {self.checkout} is on {branch or "a detached HEAD"}, not '
                              f'{self.branch}; viz never switches a checkout')
        status = self.git('status', '--porcelain').stdout
        if status.strip():
            raise TargetError(f'{self.name}: {self.checkout} has changes; viz publishes only into a clean '
                              f'checkout and never stashes or resets work it found:\n{status.rstrip()}')

    def lock(self):
        gitdir = Path(self.git('rev-parse', '--absolute-git-dir').stdout.strip())
        handle = open(gitdir / 'viz-publish.lock', 'a')  # noqa: SIM115 (held until the publish ends)
        deadline = time.monotonic() + LOCK_WAIT
        while True:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return handle
            except BlockingIOError:
                if time.monotonic() > deadline:
                    handle.close()
                    raise TargetError(f'another publish to {self.checkout} has held its lock for '
                                      f'{LOCK_WAIT} s') from None
                time.sleep(0.2)

    def reset(self):
        """Back to the last commit: safe, because the checkout was clean when the publish began."""
        self.git('reset', '--hard', '--quiet', 'HEAD', check=False)
        self.git('clean', '-fd', '--quiet', check=False)

    def pull(self):
        if self.remote and self.policy != 'never':
            self.git('pull', '--ff-only', '--quiet', self.remote, self.branch)

    def push(self):
        """Push BRANCH; on a rejection, one pull --rebase and a retry. True when it went."""
        if self.git('push', '--quiet', self.remote, f'HEAD:{self.branch}', check=False).returncode == 0:
            return True
        rebase = self.git('pull', '--rebase', '--quiet', self.remote, self.branch, check=False)
        if rebase.returncode != 0:
            self.git('rebase', '--abort', check=False)
            print(f'viz: the push to {self.remote} was rejected and rebasing onto it failed; the commit is kept '
                  f'in {self.checkout}:\n{(rebase.stderr or rebase.stdout).strip()}', file=sys.stderr)
            return False
        if self.git('push', '--quiet', self.remote, f'HEAD:{self.branch}', check=False).returncode == 0:
            return True
        print(f'viz: the push to {self.remote} was rejected twice; the commit is kept in {self.checkout}',
              file=sys.stderr)
        return False

    def ask(self, what):
        print(self.git('log', '--stat', '--format=%h %s', what).stdout.rstrip())
        answer = input(f'push to {self.remote} {self.branch}? [y/N] ').strip().lower()
        return answer in ('y', 'yes')

    # -- publishing --------------------------------------------------------------------------

    def publish(self, job, bundle_dir, text):
        handle = self.lock()
        try:
            self.check_checkout()
            self.pull()
            dest = self.checkout / job.place
            try:
                if dest.exists() or dest.is_symlink():
                    if dest.is_symlink() or not dest.is_dir():
                        raise TargetError(f'{dest} exists and is not a folder')
                    shutil.rmtree(dest)
                shutil.copytree(bundle_dir, dest)
                (dest / manifest.NAME).write_text(text)
                self.run_after(job)
                self.git('add', '-A')
                if not self.git('status', '--porcelain').stdout.strip():
                    commit = self.git('rev-parse', '--short', 'HEAD').stdout.strip()
                    job.notes.append(f'nothing changed in {job.place}; no commit')
                    return {'commit': commit, 'pushed': self.pushed_already()}
                self.git('commit', '--quiet', '-m', self.message(job))
            except BaseException:
                self.reset()
                raise
            commit = self.git('rev-parse', '--short', 'HEAD').stdout.strip()
            pushed = self.after_commit(job, commit)
            # A rejected push rebases: record the commit as it now is.
            return {'commit': self.git('rev-parse', '--short', 'HEAD').stdout.strip(), 'pushed': pushed}
        finally:
            handle.close()

    def run_after(self, job):
        argv = self.config.get('after')
        if not argv:
            return
        env = dict(os.environ, VIZ_PLACE=job.place, VIZ_URL=job.url, VIZ_TARGET=self.name)
        timeout = self.config.get('after_timeout', 600)
        try:
            result = subprocess.run(argv, cwd=self.checkout, env=env, capture_output=True, text=True,
                                    timeout=timeout, check=False, stdin=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            raise TargetError(f'{" ".join(argv)} ran past {timeout} s; the checkout is reset') from None
        except OSError as error:
            raise TargetError(f'{" ".join(argv)}: {error}; the checkout is reset') from None
        if result.returncode != 0:
            raise TargetError(f'{" ".join(argv)} failed (exit {result.returncode}); the checkout is reset:\n'
                              + (result.stdout + result.stderr).strip())

    def pushed_already(self):
        if not self.remote:
            return False
        ahead = self.git('rev-list', '--count', f'{self.remote}/{self.branch}..HEAD', check=False)
        return ahead.returncode == 0 and ahead.stdout.strip() == '0'

    def after_commit(self, job, commit):
        if self.policy == 'never':
            job.notes.append(f'committed {commit} in {self.checkout}; push = never, so pushing is yours')
            return False
        if self.policy == 'ask':
            if not terminal():
                job.notes.append(f'committed {commit} in {self.checkout}; it waits for a person to push it: '
                                 f'viz publish --to {self.name} --push, in their own terminal')
                return False
            if not self.ask('-1'):
                job.notes.append(f'committed {commit} in {self.checkout}, not pushed; later: '
                                 f'viz publish --to {self.name} --push')
                return False
        return self.push()

    def push_pending(self, args):
        """`viz publish --to NAME --push`: push the checkout's waiting commits, asked at a terminal."""
        if self.policy == 'never':
            print(f'viz: {self.name} has push = "never": push {self.checkout} by hand', file=sys.stderr)
            return 1
        if not terminal():
            print(f'viz: --push asks a person before pushing, so it needs a terminal; run it in yours:\n'
                  f'    viz publish --to {self.name} --push', file=sys.stderr)
            return 1
        handle = self.lock()
        try:
            self.check_checkout()
            self.git('fetch', '--quiet', self.remote, self.branch)
            what = f'{self.remote}/{self.branch}..HEAD'
            count = self.git('rev-list', '--count', what).stdout.strip()
            if count == '0':
                print(f'nothing waits to be pushed in {self.checkout}')
                return 0
            if not self.ask(what):
                print('not pushed')
                return 1
            if not self.push():
                return 1
            print(f'pushed {count} commit(s) to {self.remote} {self.branch}')
            return 0
        finally:
            handle.close()

