"""dotfiles/bootstrap: `bootstrap.sh` piped to bash on a bare Ubuntu 24.04 installs the commit.

Setup: the minimal image (only sudo and a sudo user `test`: no git, curl or CA certificates),
Docker's default network, the commit's bundle standing in for the repository
(`DOTFILES_REPO=/tmp/repo.bundle`), and the commit's own bootstrap.sh fed on stdin as
`curl … | bash` would.
Checks: bootstrap exits 0 after installing its prerequisites, cloning to ~/dev/dotfiles at the
commit and handing off to `setup.sh --bash`; the install's checks pass (as in clean-install).
Covers: the curl-pipe entry point on a fresh machine.
"""

from lib.results import Failure

from _install import CHECKOUT, INSTALL_TIMEOUT, check_install, login, start

NAME = "dotfiles/bootstrap"
SLOW = True
NETWORK = True
NEEDS = ()
INTERFACE = 1


def run(ctx):
    container = start(ctx, "bootstrap", image_kind="minimal")
    bundle = ctx.copy_bundle(container)
    container.copy_in(ctx.file_at("bootstrap.sh"), "/tmp/bootstrap.sh")
    missing = container.exec("command -v git curl || true").stdout.strip()
    if missing:
        raise RuntimeError(f"the minimal image already has {missing}: bootstrap's prerequisites are not tested")
    result = login(container, f"DOTFILES_REPO={bundle} bash -s -- --bash < /tmp/bootstrap.sh", timeout=INSTALL_TIMEOUT)
    if result.returncode != 0:
        raise Failure(f"bootstrap exited {result.returncode}: "
                      + " | ".join((result.stdout + result.stderr).strip().splitlines()[-3:]))
    head = container.exec(f"git -C {CHECKOUT} rev-parse HEAD").stdout.strip()
    if head != ctx.commit:
        raise Failure(f"bootstrap checked out {head[:12]}, not {ctx.commit[:12]}")
    check_install(container, "after bootstrap")
    return "bootstrap installed git and curl, cloned the commit, installed --bash, verify passed"
