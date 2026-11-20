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

A collector is a command run on a schedule, not a process kept alive. `viz collect` (what the
viz-collect user service runs) looks in VIZ_DIR/live every 15 seconds, at folders that are real, this
account's and closed to other accounts, and runs each collector that is due in a thread of its own. A run
still going when the next is due makes that one skipped, never a second at once; a run past its timeout is
stopped. Each run's output goes to VIZ_STATE/collect/NAME.log (kept under 1 MB, with one older copy) and its
outcome to NAME.json, which `viz status` shows. The server never imports this module: it serves pages a
browser can script, and those must never start a command.
"""
import datetime
import fcntl
import json
import math
import os
import pwd
import re
import signal
import stat
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from . import manifest
from .config import ROOT, STATE, die
from .paths import others_can_write

LIVE = ROOT / 'live'
KEYS = {'run', 'cwd', 'every', 'timeout', 'paused'}
UNITS = {'s': 1, 'm': 60, 'h': 3600, 'd': 86400}
SHORTEST = 30              # the shortest interval
LONGEST_DEFAULT_TIMEOUT = 30 * 60
GRACE = 5                  # seconds between TERM and KILL when a run times out
PATH = '{home}/.local/bin:/usr/local/bin:/usr/bin:/bin'
STATE_DIR = STATE / 'collect'
SCAN = 15                  # seconds between looks at VIZ_DIR/live
LOG_MAX = 1 << 20          # a log past this is moved to NAME.log.1 before the next run


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


# ---------------------------------------------------------------------------
# Logs and the last run's outcome
# ---------------------------------------------------------------------------

def stamp(when):
    return datetime.datetime.fromtimestamp(when).strftime('%Y-%m-%d %H:%M:%S')  # noqa: DTZ006


def state_dir():
    STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    return STATE_DIR


def load_state(name):
    """What NAME.json says of the collector's last run; {} when there is none."""
    try:
        data = json.loads((STATE_DIR / f'{name}.json').read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_state(name, data):
    path = state_dir() / f'{name}.json'
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f'.{path.name}.')
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, path)


def open_log(name):
    """NAME.log for appending, moved to NAME.log.1 first when it has grown past LOG_MAX."""
    path = state_dir() / f'{name}.log'
    try:
        if path.stat().st_size > LOG_MAX:
            os.replace(path, path.with_name(path.name + '.1'))
    except FileNotFoundError:
        pass
    return open(path, 'ab')


def run_logged(s, started=None, by='collect'):
    """Run collector S once, logged to NAME.log; (Result, the run's output, the state it leaves).

    The state is not saved here: `viz collect` saves every run's, a first run from viz publish only a
    successful one.
    """
    with open_log(s.name) as log:
        begin = time.time()
        log.write(f'== {stamp(begin)} ({by}) {s.run}\n== in {s.workdir()}\n'.encode())
        log.flush()
        offset = os.fstat(log.fileno()).st_size
        result = run(s, log, started)
        end = time.time()
        size = os.fstat(log.fileno()).st_size
        log.write(f'== {stamp(end)} {result.describe(s)}\n'.encode())
    with open(log.name, 'rb') as f:
        f.seek(offset)
        output = f.read(max(0, size - offset)).decode(errors='replace')
    state = {'run': s.run, 'every': short(s.every), 'started': begin, 'finished': end,
             'seconds': round(result.seconds, 3), 'exit': result.exit, 'timed_out': result.timed_out,
             'error': result.error, 'ok': result.ok, 'by': by, 'outcome': result.describe(s)}
    return result, output, state


def next_due(state, every):
    """When a collector whose last run STATE describes is due again: the first interval boundary after that
    run's start that is not before its end (the boundaries it overran were skipped)."""
    start = state.get('started')
    if not isinstance(start, (int, float)):
        return 0
    end = state.get('finished')
    end = end if isinstance(end, (int, float)) and end >= start else start
    return start + max(1, math.ceil((end - start) / every)) * every


# ---------------------------------------------------------------------------
# Finding the live pages
# ---------------------------------------------------------------------------

@dataclass
class Problem:
    """A live page whose collector cannot run, and why."""
    name: str
    error: str


def closed(path, kind):
    """True for PATH a real KIND (stat.S_ISDIR or S_ISREG) that this account owns and no other can write."""
    try:
        info = os.lstat(path)
    except OSError:
        return False
    return kind(info.st_mode) and info.st_uid == os.getuid() and not others_can_write(info)


def found():
    """Every live page in VIZ_DIR/live, by name: its Spec, or a Problem."""
    if not closed(LIVE, stat.S_ISDIR):
        return []
    pages = []
    for folder in sorted(LIVE.iterdir()):
        name = folder.name
        if name.startswith('.'):
            continue
        if not closed(folder, stat.S_ISDIR):
            pages.append(Problem(name, 'not a real folder of this account, closed to others'))
            continue
        page = folder / manifest.NAME
        if not page.exists() and not page.is_symlink():
            pages.append(Problem(name, 'no page.toml'))
            continue
        if not closed(page, stat.S_ISREG):
            pages.append(Problem(name, 'page.toml is not a real file of this account, closed to others'))
            continue
        try:
            pages.append(spec(name, folder, manifest.read(page)))
        except ValueError as error:   # SpecError too
            pages.append(Problem(name, str(error)))
    return pages


# ---------------------------------------------------------------------------
# viz collect
# ---------------------------------------------------------------------------

def say(text):
    print(f'{stamp(time.time())} {text}', flush=True)


class Collector:
    """The service: each due collector run in a thread of its own, never two of one at once."""

    def __init__(self):
        self.threads = {}     # name -> the Thread running it
        self.procs = {}       # name -> its Popen, to stop on shutdown
        self.problems = {}    # name -> the problem last reported
        self.stopping = threading.Event()

    def tick(self, now=None):
        """Start every collector that is due; the names started."""
        now = time.time() if now is None else now
        begun = []
        pages = found()
        for page in pages:
            if isinstance(page, Problem):
                if self.problems.get(page.name) != page.error:
                    say(f'{page.name}: cannot run: {page.error}')
                    self.problems[page.name] = page.error
                continue
            self.problems.pop(page.name, None)
            thread = self.threads.get(page.name)
            if page.paused or (thread and thread.is_alive()) or self.stopping.is_set():
                continue
            if now < next_due(load_state(page.name), page.every):
                continue
            thread = threading.Thread(target=self.one, args=(page,), name=f'collect-{page.name}', daemon=True)
            self.threads[page.name] = thread
            thread.start()
            begun.append(page.name)
        names = {p.name for p in pages}
        for name in [n for n in self.threads if n not in names and not self.threads[n].is_alive()]:
            del self.threads[name]
        return begun

    def one(self, s):
        earlier = load_state(s.name)
        save_state(s.name, {**earlier, 'running': True, 'started': time.time()})
        try:
            result, _, state = run_logged(s, started=lambda proc: self.procs.__setitem__(s.name, proc))
        except OSError as error:   # the log or state cannot be written
            say(f'{s.name}: {error}')
            return
        finally:
            self.procs.pop(s.name, None)
        overran = max(1, math.ceil((state['finished'] - state['started']) / s.every)) - 1
        state['skipped'] = earlier.get('skipped', 0) + overran
        save_state(s.name, state)
        skipped = f'; {overran} run{"s" * (overran > 1)} skipped while it went on' if overran else ''
        say(f'{s.name}: {result.describe(s)}{skipped}')

    def wait(self, timeout=None):
        """Wait for the running collectors; True when none is left."""
        deadline = None if timeout is None else time.monotonic() + timeout
        for thread in list(self.threads.values()):
            thread.join(None if deadline is None else max(0, deadline - time.monotonic()))
        return not any(t.is_alive() for t in self.threads.values())

    def shutdown(self):
        """Stop starting runs and end the ones going: TERM to each, KILL to what is left after GRACE."""
        self.stopping.set()
        for sig in (signal.SIGTERM, signal.SIGKILL):
            for proc in list(self.procs.values()):
                try:
                    os.killpg(proc.pid, sig)
                except (ProcessLookupError, PermissionError):
                    pass
            if self.wait(GRACE):
                return


def hold_lock():
    """The lock one `viz collect` per account holds, or None when another holds it."""
    lock = open(state_dir() / 'lock', 'a+')  # noqa: SIM115
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock.close()
        return None
    lock.truncate(0)
    lock.write(str(os.getpid()))
    lock.flush()
    return lock


def collector_pid():
    """The pid of the running `viz collect`, or None."""
    try:
        lock = open(STATE_DIR / 'lock')  # noqa: SIM115
    except OSError:
        return None
    with lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            text = lock.read().strip()
            return int(text) if text.isdigit() else -1
        return None


def cmd_collect(args):
    lock = hold_lock()
    if lock is None:
        die(f'viz collect already runs (pid {collector_pid()})')
    collector = Collector()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: collector.stopping.set())
    say(f'viz collect: the live pages in {LIVE}, looked at every {SCAN}s; logs in {STATE_DIR}')
    while not collector.stopping.is_set():
        try:
            collector.tick()
        except Exception as error:  # noqa: BLE001  (one bad look must not end the service)
            say(f'looking at {LIVE} failed: {error}')
        collector.stopping.wait(SCAN)
    say('viz collect: stopping')
    collector.shutdown()
    lock.close()


# ---------------------------------------------------------------------------
# viz status
# ---------------------------------------------------------------------------

def when(t):
    moment = datetime.datetime.fromtimestamp(t)  # noqa: DTZ006
    return moment.strftime('%H:%M' if moment.date() == datetime.date.today() else '%Y-%m-%d %H:%M')  # noqa: DTZ011


def status_lines():
    """For `viz status`: whether viz collect runs, and each live page's last run."""
    pages = found()
    pid = collector_pid()
    if not pages:
        head = f'running (pid {pid}); ' if pid else ''
        return [head + 'no live pages (viz publish --to live makes one)']
    count = f'{len(pages)} live page{"s" * (len(pages) > 1)}'
    if pid:
        lines = [f'running (pid {pid}); {count}; logs in {home_relative(STATE_DIR)}']
    else:
        lines = [f'not running, so nothing rewrites {count}: systemctl --user start viz-collect, or viz collect']
    width = max(len(p.name) for p in pages)
    for page in pages:
        if isinstance(page, Problem):
            lines.append(f'{page.name:<{width}}  BROKEN: {page.error}')
            continue
        state = load_state(page.name)
        what = f'every {short(page.every)}'
        if page.paused:
            what += ', paused'
        if state.get('running') and pid:
            what += f'; running since {when(state["started"])}'
        elif isinstance(state.get('finished'), (int, float)):
            what += f'; last {when(state["started"])}, {state.get("outcome", "?")}'
            if not state.get('ok'):
                what += f' (see {page.name}.log)'
        else:
            what += '; not run yet'
        if pid and not page.paused and not state.get('running'):
            what += f'; next {when(max(time.time(), next_due(state, page.every)))}'
        lines.append(f'{page.name:<{width}}  {what}')
    return lines
