#!/bin/bash
# Install AWS CLI v2 from AWS's signed Linux distribution.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"; export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
while (( $# )); do
    case "$1" in --force) FORCE=true ;; --dry-run) DRY_RUN=true ;;
        --help|-h) sed -n '2,2p' "$0" | sed 's/^# //'; exit 0 ;;
        *) error "Unknown option: $1"; exit 64 ;; esac
    shift
done

if [[ "${DRY_RUN:-false}" == true ]]; then
    log "[DRY RUN] Would download, verify, and install AWS CLI v2 under /usr/local/aws-cli"
    exit 0
fi

if command -v aws >/dev/null 2>&1; then
    aws_path="$(readlink -f "$(command -v aws)" 2>/dev/null || command -v aws)"
    if [[ "$aws_path" != /usr/local/aws-cli/* ]]; then
        warn "Keeping externally managed AWS CLI: $aws_path"
        exit 2
    fi
    if [[ "$FORCE" != true ]] && aws --version 2>&1 | grep -q '^aws-cli/2\.'; then
        success "AWS CLI v2 already installed"
        exit 2
    fi
fi
safe_sudo apt-get install -y ca-certificates curl gnupg unzip || exit 1
case "$(get_arch)" in x86_64) aws_arch=x86_64 ;; aarch64) aws_arch=aarch64 ;;
    *) error "Unsupported AWS CLI architecture"; exit 1 ;; esac
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT INT TERM
mkdir -m 0700 "$tmpdir/gnupg"
archive="$tmpdir/awscliv2.zip"
download_https "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" "$archive"
download_https "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip.sig" "$archive.sig"

expected=FB5DB77FD5C118B80511ADA8A6310ACC4672475C
actual="$(GNUPGHOME="$tmpdir/gnupg" gpg --batch --show-keys --with-colons "$INSTALLER_DIR/aws-cli-signing-key.asc" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$actual" == "$expected" ]] || { error "Bundled AWS CLI signing-key fingerprint mismatch"; exit 1; }
GNUPGHOME="$tmpdir/gnupg" gpg --batch --dearmor --output "$tmpdir/aws-keyring.gpg" "$INSTALLER_DIR/aws-cli-signing-key.asc"
gpgv --keyring "$tmpdir/aws-keyring.gpg" "$archive.sig" "$archive" \
    || { error "AWS CLI distribution signature verification failed"; exit 1; }
unzip -Z1 "$archive" | awk '$0 ~ /^\// || $0 ~ /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad ? 0 : 1 }' \
    && { error "AWS CLI archive contains an unsafe path"; exit 1; }
unzip -q "$archive" -d "$tmpdir/unpacked"
[[ -x "$tmpdir/unpacked/aws/install" ]] || { error "AWS CLI archive is missing its installer"; exit 1; }

args=(--bin-dir /usr/local/bin --install-dir /usr/local/aws-cli)
[[ -d /usr/local/aws-cli ]] && args+=(--update)
safe_sudo "$tmpdir/unpacked/aws/install" "${args[@]}" || exit 1
/usr/local/bin/aws --version 2>&1 | grep -q '^aws-cli/2\.' \
    || { error "AWS CLI v2 verification failed"; exit 1; }
success "AWS CLI v2 installed; ~/.aws credentials and configuration remain user-owned"
