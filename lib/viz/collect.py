"""Live pages' collectors: a command run on a schedule that rewrites its page.

A live page (`viz publish --to live`) is a folder VIZ_DIR/live/NAME/ whose page.toml registers its collector:

    [live]
    run = 'make-report "$VIZ_OUT"'   # run by sh -c, in cwd
    cwd = "~/src/proj"               # default: the page's folder
    every = "5m"                     # 30s, 5m, 1h, 1d; at least 30s
    timeout = "10m"                  # default: the interval, at most 30m
    paused = false                   # true stops collecting; the page stays

A collector gets VIZ_OUT (the page's entry, NAME/index.html by default), VIZ_PAGE_DIR and VIZ_LIVE_NAME, and
otherwise a bare environment, the same for the first run `viz publish` makes in the foreground as for every
later one: HOME, USER, LOGNAME, SHELL, LANG, TZ, XDG_RUNTIME_DIR and a fixed PATH. A command that needs more
sets it up itself (`. ~/env.sh && make-report "$VIZ_OUT"`), so what works at registration works in the
service. It should write its page atomically (a temporary file, then a rename): the server reloads an open
page whenever the file changes.

A collector is a command run on a schedule, not a process kept alive: the runner owns timing, timeouts,
overlap and logs. The server never imports this module (it serves pages a browser can script).
"""
import os
import pwd
import re
import signal
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from . import manifest
from .config import ROOT

LIVE = ROOT / 'live'
KEYS = {'run', 'cwd', 'every', 'timeout', 'paused'}
UNITS = {'s': 1, 'm': 60, 'h': 3600, 'd': 86400}
SHORTEST = 30              # the shortest interval
LONGEST_DEFAULT_TIMEOUT = 30 * 60
GRACE = 5                  # seconds between TERM and KILL when a run times out
PATH = '{home}/.local/bin:/usr/local/bin:/usr/bin:/bin'


class SpecError(ValueError):
    """A [live] table viz cannot run; the message says why."""


def seconds(text, what='every'):
    """A duration: '30s', '5m', '1h', '1d', or a whole number of seconds."""
    if isinstance(text, int) and not isinstance(text, bool):
        n = text
    elif isinstance(text, str) and (m := re.fullmatch(r'\s*(\d+)\s*([smhd])\s*', text)):
        n = int(m[1]) * UNITS[m[2]]
    else:
        raise SpecError(f'{what} takes a duration such as 30s, 5m, 1h or 1d, not {text!r}')
    if n <= 0:
        raise SpecError(f'{what} must be longer than nothing')
    return n


def short(n):
    """N seconds as the largest whole unit: 300 -> '5m'."""
    for unit in ('d', 'h', 'm'):
        if n % UNITS[unit] == 0:
            return f'{n // UNITS[unit]}{unit}'
    return f'{n}s'


@dataclass
class Spec:
    """One collector, from its live page's [live] table."""
    name: str
    folder: Path         # VIZ_DIR/live/NAME (or the staged folder of a first run)
    run: str
    every: int           # seconds
    timeout: int         # seconds
    cwd: str = ''        # as written ('~/src/proj'); '' runs in the page's folder
    entry: str = 'index.html'
    paused: bool = False

    @property
    def out(self):
        return self.folder / self.entry

    def workdir(self):
        return Path(os.path.expanduser(self.cwd)) if self.cwd else self.folder


def spec(name, folder, data):
    """The Spec in DATA, a live page's parsed page.toml; SpecError when its [live] table is wrong."""
    live = data.get('live')
    if not isinstance(live, dict):
        raise SpecError('page.toml has no [live] table')
    unknown = sorted(set(live) - KEYS)
    if unknown:
        raise SpecError(f'[live] has unknown keys: {", ".join(unknown)} (it takes {", ".join(sorted(KEYS))})')
    run = live.get('run')
    if not isinstance(run, str) or not run.strip():
        raise SpecError('[live] run is the command to run, and it is missing or empty')
    if 'every' not in live:
        raise SpecError('[live] every is missing: how often to run, such as 5m')
    every = seconds(live['every'])
    if every < SHORTEST:
        raise SpecError(f'[live] every is {short(every)}; the shortest is {SHORTEST}s')
    timeout = (seconds(live['timeout'], 'timeout') if 'timeout' in live
               else min(every, LONGEST_DEFAULT_TIMEOUT))
    cwd = live.get('cwd', '')
    if not isinstance(cwd, str):
        raise SpecError('[live] cwd is a directory path')
    paused = live.get('paused', False)
    if not isinstance(paused, bool):
        raise SpecError('[live] paused is true or false')
    entry = data.get('entry') or 'index.html'
    if not isinstance(entry, str) or Path(entry).is_absolute() or '..' in Path(entry).parts:
        raise SpecError(f'entry {entry!r} is not a path inside the page')
    return Spec(name=name, folder=Path(folder), run=run, every=every, timeout=timeout, cwd=cwd, entry=entry,
                paused=paused)


def table(run, every, cwd='', timeout=None):
    """A [live] table's text, as viz publish writes it: what it was given, then the other keys commented."""
    lines = ['[live]', f'run = {literal(run)}']
    if cwd:
        lines.append(f'cwd = {manifest.value(cwd)}')
    lines.append(f'every = {manifest.value(every)}')
    default = short(min(seconds(every), LONGEST_DEFAULT_TIMEOUT))
    lines.append(f'timeout = {manifest.value(timeout)}' if timeout else
                 f'# timeout = "{default}"'.ljust(21) + '# default: the interval, at most 30m')
    lines.append('# paused = true'.ljust(21) + '# stops collecting; the page stays')
    return '\n'.join(lines) + '\n'


def literal(text):
    """TEXT as a TOML string, a literal one ('...') when it can be, so a command reads as typed."""
    if "'" not in text and not any(c in text for c in '\n\r') and text.isprintable():
        return f"'{text}'"
    return manifest.value(text)


def home_relative(path):
    """PATH with the home directory written as ~."""
    home = str(Path.home())
    text = str(path)
    return '~' + text[len(home):] if text == home or text.startswith(home + '/') else text


# ---------------------------------------------------------------------------
# Running one collector
# ---------------------------------------------------------------------------

def environment(s):
    """The bare environment every run of collector S gets, wherever it is started from."""
    account = pwd.getpwuid(os.getuid())
    home = str(Path.home())
    env = {'HOME': home, 'USER': account.pw_name, 'LOGNAME': account.pw_name,
           'SHELL': account.pw_shell or '/bin/sh', 'PATH': PATH.format(home=home)}
    for name in ('LANG', 'TZ', 'XDG_RUNTIME_DIR'):
        if os.environ.get(name):
            env[name] = os.environ[name]
    env.update(VIZ_OUT=str(s.out), VIZ_PAGE_DIR=str(s.folder), VIZ_LIVE_NAME=s.name)
    return env


@dataclass
class Result:
    exit: int | None = None     # the command's exit status; None when it never ran or was killed
    seconds: float = 0.0
    timed_out: bool = False
    error: str = ''             # why it could not run (its cwd is missing)

    @property
    def ok(self):
        return self.exit == 0 and not self.timed_out and not self.error

    def describe(self, s):
        if self.error:
            return self.error
        if self.timed_out:
            return f'timed out after {short(s.timeout)} and was stopped'
        if self.exit == 0:
            return f'ok in {self.seconds:.1f}s'
        if self.exit is not None and self.exit < 0:
            return f'killed by signal {-self.exit} after {self.seconds:.1f}s'
        return f'exit {self.exit} after {self.seconds:.1f}s'


def run(s, output, started=None, clock=None):
    """Run collector S once, its output (stdout and stderr) appended to the open binary file OUTPUT.

    STARTED, if given, is called with the Popen as soon as the command runs (the service keeps it to stop it).
    A run past its timeout is sent TERM, then KILL GRACE seconds later, across its whole process group.
    """
    clock = clock or time.monotonic
    workdir = s.workdir()
    if not workdir.is_dir():
        return Result(error=f'its cwd, {s.cwd or workdir}, is not a directory')
    begin = clock()
    try:
        proc = subprocess.Popen(['/bin/sh', '-c', s.run], cwd=workdir, env=environment(s),
                                stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                start_new_session=True)
    except OSError as error:
        return Result(error=f'could not start /bin/sh: {error}')
    if started:
        started(proc)
    result = Result()
    try:
        result.exit = proc.wait(timeout=s.timeout)
    except subprocess.TimeoutExpired:
        result.timed_out = True
        stop(proc)
    result.seconds = clock() - begin
    return result


def stop(proc):
    """End PROC and everything it started: TERM to its process group, then KILL GRACE seconds later."""
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=GRACE)
    except subprocess.TimeoutExpired:
        pass
    # The shell may be gone while something it started ignores TERM: the group is killed either way.
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait()
