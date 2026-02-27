#!/bin/bash
# Install PlantUML JAR from GitHub releases
# Downloads to ~/.local/lib/plantuml/, wrapper script in ~/.local/bin/plantuml

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

REPO="plantuml/plantuml"
LIB_DIR="$HOME/.local/lib/plantuml"
BIN_DIR="$HOME/.local/bin"
WRAPPER="$BIN_DIR/plantuml"

log "Installing PlantUML..."

# Check java is available (APT installs it earlier in the dev tier)
if ! command -v java >/dev/null 2>&1; then
    error "Java not found — install default-jre first"
    exit 1
fi

VERSION=$(github_latest_version "$REPO" --strip-v)

# Check existing installation
if [[ "$FORCE" != true ]] && [[ -f "$LIB_DIR/plantuml.jar" ]] && verify_binary plantuml -version; then
    CURRENT=$(plantuml -version 2>&1 | head -n1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
    if [[ "$CURRENT" == "$VERSION" ]]; then
        success "PlantUML v$VERSION already installed"
        exit 2
    fi
    log "PlantUML v$CURRENT installed, updating to v$VERSION..."
fi

# Download JAR
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

DOWNLOAD_URL="https://github.com/$REPO/releases/download/v${VERSION}/plantuml-${VERSION}.jar"

log "Downloading PlantUML v${VERSION}..."
curl -Lo "$TEMP_DIR/plantuml.jar" "$DOWNLOAD_URL"

# Install JAR
mkdir -p "$LIB_DIR" "$BIN_DIR"
mv "$TEMP_DIR/plantuml.jar" "$LIB_DIR/plantuml.jar"

# Create wrapper script
cat > "$WRAPPER" << 'EOF'
#!/bin/bash
exec java -jar "$HOME/.local/lib/plantuml/plantuml.jar" "$@"
EOF
chmod +x "$WRAPPER"

# Verify
if "$WRAPPER" -version >/dev/null 2>&1; then
    success "PlantUML v$VERSION installed successfully!"
    "$WRAPPER" -version 2>&1 | head -n1
else
    error "PlantUML installation failed — wrapper does not run"
    exit 1
fi
