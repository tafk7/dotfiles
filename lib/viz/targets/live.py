"""The built-in `live` target: a fixed, undated place, VIZ_DIR/live/NAME/, kept current by a collector.

    viz publish --to live --as NAME --run 'COMMAND' --every 5m [--cwd DIR] --summary TEXT [--title TEXT]
    viz publish DRAFT --to live [--as NAME]      # the draft's page.toml carries [live] run and every

The page's own page.toml is the registration: its [live] table names the command `viz collect` runs every
interval. Publishing runs the collector once in the foreground, in a staged copy of the page, and puts the
page in place only when that run succeeds: a broken command fails now, not later in a log, and an earlier
registration stays as it was.
"""
import os
import shutil
import signal
import stat
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

import tomllib

from .. import collect, manifest
from ..config import die
from ..paths import url_for
from . import Target, TargetError, check_slug, order
from .file import ours

COMMENT = ('Published by viz publish --to live.\n'
           'Its [live] table registers the collector viz collect runs: edit it here, or set paused = true.')
TAIL = 40   # lines of a failed first run's output shown


@dataclass
class LiveTarget(Target):
    name: str = 'live'
    type: str = 'live'
    description: str = ('A fixed, undated place in the private browser, VIZ_DIR/live/NAME/, rewritten by a '
                        'collector: a command viz collect runs every interval')
    audience: str = 'you, at a fixed address in your browser; a collector keeps it current'
    network: bool = True   # as private as preview: a live draft may load from outside, as it does in ~/viz
    builtin = True
    usage = ("viz publish --to live --as NAME --run 'COMMAND' --every 5m [--cwd DIR] --summary TEXT, "
             'or viz publish DRAFT --to live with a [live] table in its page.toml')

    # -- a draft, through viz publish's own steps

    def place(self, job, last, reuse):
        if job.args.title or job.args.summary:
            raise TargetError('--title and --summary are for --to live without a page; a draft has its own '
                              '(or use --set title=...)')
        name = Path(str(last['place'])).name if reuse and last and last.get('place') else job.slug
        check_slug(name)
        self.settings(job.page.data.get('live'), job.args)   # refuse a bad [live] before bundling
        return str(folder_of(name)), url_of(name), []

    def publish(self, job, bundle_dir, text):
        settings = self.settings(job.page.data.get('live'), job.args)
        text += '\n' + collect.table(**settings)
        install(Path(job.place), text, bundle_dir)
        return {}

    def dry_run_lines(self, job):
        settings = self.settings(job.page.data.get('live'), job.args)
        return ['live:     ' + line for line in collect.table(**settings).splitlines()]

    @staticmethod
    def settings(draft_live, args):
        """The [live] settings: the draft's table under the command line's --run, --every and --cwd."""
        live = dict(draft_live) if isinstance(draft_live, dict) else {}
        for key in ('run', 'every', 'cwd'):
            if getattr(args, key, None):
                live[key] = getattr(args, key)
        if not live.get('run') or not live.get('every'):
            raise TargetError("--to live needs a collector: --run 'COMMAND' and --every 5m, or run and every "
                              "in the draft's [live] table")
        live['cwd'] = collect.home_relative(Path(os.path.expanduser(live.get('cwd') or '.')).absolute())
        try:
            checked = collect.spec('check', Path('.'), {'live': live})
        except collect.SpecError as error:
            raise TargetError(str(error)) from None
        return {'run': checked.run, 'every': live['every'], 'cwd': checked.cwd, 'timeout': live.get('timeout')}

    # -- no draft: the command line is the whole page

    def register(self, args):
        """viz publish --to live --as NAME --run ... --every ... --summary ...: a page that is only its collector."""
        if args.as_name is None:
            die('--to live without a page needs --as NAME (the page is VIZ_DIR/live/NAME/)')
        name = check_slug(args.as_name)
        if not args.summary:
            die('--to live without a page needs --summary: one or two sentences on what the page shows')
        try:
            settings = self.settings({}, args)
        except TargetError as error:
            die(str(error))
        dest = folder_of(name)
        try:
            refusal(dest)
        except TargetError as error:
            die(str(error))
        day = manifest.today()
        try:
            earlier = manifest.read(dest / manifest.NAME) if ours(dest) else {}
        except ValueError:
            earlier = {}
        data = order({'title': args.title or name, 'summary': args.summary, 'format': 'html',
                      'entry': 'index.html', 'date': earlier.get('date', day), 'updated': day,
                      'source': {'generator': settings['run']}})
        text = manifest.dumps(data, comment=COMMENT) + '\n' + collect.table(**settings)
        url = url_of(name)
        if args.dry_run:
            print(f'target:   live (built in)\nplace:    {dest}\nurl:      {url}\nmanifest:')
            for line in text.splitlines():
                print(f'          {line}' if line else '')
            print('dry run: nothing was written or run')
            return
        try:
            install(dest, text)
        except TargetError as error:
            die(str(error))
        print(url)


def folder_of(name):
    return collect.LIVE / name


def url_of(name):
    return url_for(folder_of(name)).rstrip('/') + '/'


def refusal(dest):
    """Raise TargetError when viz may not (re)place a live page at DEST."""
    live = dest.parent
    if live.is_symlink() or (live.exists() and not live.is_dir()):
        raise TargetError(f'{live} is not a real folder; live pages go in one')
    for top in (live.parent, live):
        if top.is_dir() and not collect.closed(top, stat.S_ISDIR):
            raise TargetError(f'{top} is owned or writable by another account, or by a group (chmod g-w,o-w '
                              'it): viz collect runs nothing from there')
    if dest.is_symlink() or (dest.exists() and not dest.is_dir()):
        raise TargetError(f'{dest} exists and is not a folder')
    if dest.is_dir() and any(dest.iterdir()) and not ours(dest):
        raise TargetError(f'{dest} is a folder viz did not publish; move it, or pick another --as')


class Interrupted(Exception):
    """viz publish was stopped (Ctrl-C, TERM, a closed terminal) during the first run."""


def _interrupted(signum, frame):
    raise Interrupted(signal.Signals(signum).name)


def install(dest, text, bundle_dir=None):
    """Stage the page (BUNDLE_DIR's files and the manifest TEXT), run its collector once there, then put it at
    DEST. A failing or interrupted run leaves DEST as it was and raises TargetError with the run's output.

    NAME's lock is held throughout, so viz collect never runs the page while it is replaced.
    """
    refusal(dest)
    data = tomllib.loads(text)
    for folder in (dest.parent.parent, dest.parent):
        if not folder.exists():
            folder.mkdir(parents=True)
            os.chmod(folder, 0o755)   # whatever the umask: viz collect looks only in folders closed to others
    handlers = {sig: signal.signal(sig, _interrupted) for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
    staged = None
    try:
        with collect.page_lock(dest.name) as held:
            if not held:
                raise TargetError(f'{dest.name} is being collected or published right now (viz status shows a '
                                  'run); publish again when it ends')
            staged = Path(tempfile.mkdtemp(prefix=f'.{dest.name}.viz-', dir=dest.parent))
            if bundle_dir is not None:
                shutil.copytree(bundle_dir, staged, dirs_exist_ok=True)
            (staged / manifest.NAME).write_text(text)
            os.chmod(staged / manifest.NAME, 0o644)
            os.chmod(staged, 0o755)
            s = collect.spec(dest.name, staged, data)
            s.folder.joinpath(s.entry).parent.mkdir(parents=True, exist_ok=True)
            result, said, state = collect.run_logged(s, by='publish')
            if not result.ok:
                lines = said.rstrip('\n').splitlines()
                shown = '\n'.join('  ' + line for line in lines[-TAIL:]) or '  (it printed nothing)'
                raise TargetError(f'the collector\'s first run failed: {result.describe(s)}; nothing was '
                                  f'published.\nIt ran: {s.run}\nin {s.workdir()}, with VIZ_OUT={s.out}; its output'
                                  f'{" (the last " + str(TAIL) + " lines)" if len(lines) > TAIL else ""}:\n{shown}')
            print(f'viz: the collector\'s first run: {result.describe(s)}', file=sys.stderr)
            swap(staged, dest)
            collect.save_state(dest.name, state)   # viz collect runs it again one interval later
    except Interrupted as error:
        raise TargetError(f'stopped by {error} during the collector\'s first run, which was stopped too; nothing '
                          'was published') from None
    finally:
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
        if staged is not None:
            shutil.rmtree(staged, ignore_errors=True)
    if not collect.collector_pid():
        print('viz: viz collect is not running, so the page stays as it is: systemctl --user start '
              'viz-collect, or run viz collect', file=sys.stderr)


def swap(staged, dest):
    """Put STAGED at DEST, replacing what viz published there before."""
    old = None
    if dest.exists():
        old = dest.with_name(f'.{dest.name}.old-{os.getpid()}')
        dest.rename(old)
    staged.rename(dest)
    if old:
        shutil.rmtree(old, ignore_errors=True)
