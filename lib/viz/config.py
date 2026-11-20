"""Where viz reads and writes: VIZ_DIR, VIZ_STATE, VIZ_PORT and the other settings from the environment."""
import os
import sys
from pathlib import Path

# The checkout this package belongs to, and the entry point the background server is started through:
# viz.service, bin/forwards and server_pid() all expect a process run as `.../bin/viz serve`.
REPO = Path(__file__).resolve().parents[2]
ENTRY = REPO / 'bin' / 'viz'

ROOT = Path(os.environ.get('VIZ_DIR') or '~/viz').expanduser().resolve()
PORT = int(os.environ.get('VIZ_PORT') or 20000 + os.getuid() % 10000)
# Per account, like the socket in the account's runtime directory: one server and one secret for every
# shell of this account. XDG_STATE_HOME is not used, so a shell that points it elsewhere (a scriv root does)
# still reaches the account's server instead of finding "another VIZ_DIR or secret".
STATE = Path(os.environ.get('VIZ_STATE') or '~/.local/state/viz').expanduser()
TOKEN = STATE / 'token'      # the account's secret, 0600; never printed or sent to a browser
OPENED = STATE / 'opened'    # files opened from linked directories, for the gallery
BROWSER_SUFFIXES = {'.html', '.htm', '.svg', '.pdf'}
IMAGE_SUFFIXES = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'}
LINKED = ROOT / 'linked'
DIFF_ROOTS = [Path(p).expanduser().resolve()
              for p in (os.environ.get('VIZ_DIFF_ROOTS') or '~/projects:~/ref').split(':') if p]
# The client end of the forward. 127.0.0.1 rather than localhost, so the browser
# cannot reach an IPv6 listener on [::1] that someone else bound first.
URL_HOST = '127.0.0.1'


def die(message):
    print(f'viz: {message}', file=sys.stderr)
    sys.exit(1)
