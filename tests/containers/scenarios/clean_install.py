"""dotfiles/clean-install: the real `--bash` installer on a clean Ubuntu 24.04, as CI runs it, before any push.

Setup: the clean image (CI's prerequisites and a sudo user `test`), Docker's default network
(the installer downloads its tools), the commit cloned to ~/dev/dotfiles.
Checks: `setup.sh --bash --force` exits 0, and so does a second `setup.sh --bash`; then
`dotfiles profile`, `dotfiles verify -v` and `bin/verify --tier bash` pass, and a login and an
interactive shell start. Covers: bootstrap on a clean machine.
"""

from lib.results import Failure

from _install import CHECKOUT, INSTALL_TIMEOUT, check_install, login, start

NAME = "dotfiles/clean-install"
SLOW = True
NETWORK = True
NEEDS = ()
INTERFACE = 1


def run(ctx):
    container = start(ctx, "clean-install")
    ctx.clone(container, "test", CHECKOUT)
    for args in ("--bash --force", "--bash"):
        result = login(container, f"cd {CHECKOUT} && ./setup.sh {args}", timeout=INSTALL_TIMEOUT)
        if result.returncode != 0:
            raise Failure(f"setup.sh {args} exited {result.returncode}: "
                          + " | ".join((result.stdout + result.stderr).strip().splitlines()[-3:]))
    check_install(container, "after install")
    return "installed with --bash, re-ran clean, verify passed"
