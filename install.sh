#!/bin/sh
# publier CLI installer. POSIX shell — verified with `dash -n install.sh`.
#
# curl -fsSL https://raw.githubusercontent.com/publier/releases/main/install.sh | sh
#
# Detects platform, fetches the latest release tarball from GitHub Releases,
# verifies SHA-256 against the checksum published in the release, and installs
# the binary to ~/.publier/bin/publier. Prints shell-rc instructions so the
# installed path is on $PATH for future sessions.
#
# Env overrides (maintainer / CI):
#   PUBLIER_INSTALL_DIR   — override install prefix (default ~/.publier)
#   PUBLIER_VERSION       — pin to a specific tag (default: latest release)
#   PUBLIER_SOURCE        — override download base URL (default GitHub Releases)

set -eu

RELEASES_REPO="publier/releases"
API_BASE="${PUBLIER_SOURCE:-https://api.github.com/repos/${RELEASES_REPO}}"
DOWNLOAD_BASE="${PUBLIER_SOURCE:-https://github.com/${RELEASES_REPO}/releases/download}"
INSTALL_DIR="${PUBLIER_INSTALL_DIR:-$HOME/.publier}"
BIN_DIR="${INSTALL_DIR}/bin"

c_red="$(printf '\033[31m')"; c_green="$(printf '\033[32m')"
c_yellow="$(printf '\033[33m')"; c_bold="$(printf '\033[1m')"
c_reset="$(printf '\033[0m')"

die()  { printf "%sError:%s %s\n" "$c_red" "$c_reset" "$*" >&2; exit 1; }
info() { printf "%s==>%s %s\n" "$c_bold" "$c_reset" "$*"; }
ok()   { printf "  %s✓%s %s\n" "$c_green" "$c_reset" "$*"; }
warn() { printf "  %s!%s %s\n" "$c_yellow" "$c_reset" "$*"; }

# --- Prerequisites ------------------------------------------------------------

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar  >/dev/null 2>&1 || die "tar is required"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"
command -v bun  >/dev/null 2>&1 || warn "bun not found — required for 'publier dev'. Install from https://bun.sh"

# --- Platform detection -------------------------------------------------------

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS-$ARCH" in
	Linux-x86_64) PLATFORM="linux-x64" ;;
	*) die "Unsupported platform: ${OS}-${ARCH}. publier is linux-x64 only today. Track macOS/Windows support at https://github.com/${RELEASES_REPO}/issues" ;;
esac

# --- Version resolution -------------------------------------------------------

if [ -n "${PUBLIER_VERSION:-}" ]; then
	TAG="$PUBLIER_VERSION"
	info "Installing publier ${TAG} (pinned via PUBLIER_VERSION)"
else
	info "Resolving latest release"
	# The `latest` endpoint is cacheable + doesn't require auth for public repos.
	TAG="$(curl -fsSL "${API_BASE}/releases/latest" \
		| grep -m1 '"tag_name":' \
		| sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
	[ -n "$TAG" ] || die "could not resolve latest release tag"
	ok "latest: ${TAG}"
fi

# --- Download + verify --------------------------------------------------------

TARBALL="${TAG}-${PLATFORM}.tar.gz"
CHECKSUMS="${TAG}-checksums.txt"
TARBALL_URL="${DOWNLOAD_BASE}/${TAG}/${TARBALL}"
CHECKSUMS_URL="${DOWNLOAD_BASE}/${TAG}/${CHECKSUMS}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading ${TARBALL}"
curl -fsSL "$TARBALL_URL" -o "$TMPDIR/$TARBALL" \
	|| die "download failed: $TARBALL_URL"
ok "downloaded $(du -h "$TMPDIR/$TARBALL" | awk '{print $1}')"

info "Verifying SHA-256"
if curl -fsSL "$CHECKSUMS_URL" -o "$TMPDIR/$CHECKSUMS" 2>/dev/null; then
	EXPECTED="$(grep "  $TARBALL$" "$TMPDIR/$CHECKSUMS" | awk '{print $1}')"
	if [ -z "$EXPECTED" ]; then
		die "Tarball '$TARBALL' not found in checksums file at $CHECKSUMS_URL"
	fi
	ACTUAL="$(cd "$TMPDIR" && sha256sum "$TARBALL" | awk '{print $1}')"
	if [ "$EXPECTED" != "$ACTUAL" ]; then
		die "SHA-256 mismatch — expected $EXPECTED, got $ACTUAL. The tarball may be corrupted or tampered."
	fi
	ok "SHA-256 verified"
else
	if [ "${PUBLIER_SKIP_CHECKSUM:-0}" = "1" ]; then
		warn "PUBLIER_SKIP_CHECKSUM=1 — skipping integrity check"
	else
		die "Checksums file unavailable at $CHECKSUMS_URL. Set PUBLIER_SKIP_CHECKSUM=1 to bypass (not recommended)."
	fi
fi

# --- Install ------------------------------------------------------------------

info "Installing to ${BIN_DIR}/publier"
mkdir -p "$BIN_DIR"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
[ -f "$TMPDIR/publier" ] || die "binary 'publier' not found in tarball"
mv "$TMPDIR/publier" "$BIN_DIR/publier"
chmod 0755 "$BIN_DIR/publier"
ok "installed"

# --- PATH setup ---------------------------------------------------------------

# Check if BIN_DIR is already on PATH.
case ":$PATH:" in
	*":$BIN_DIR:"*) ON_PATH=1 ;;
	*) ON_PATH=0 ;;
esac

printf "\n%spublier %s installed%s\n" "$c_green$c_bold" "$TAG" "$c_reset"
printf "  binary: %s\n" "$BIN_DIR/publier"
printf "  version check: %s\n\n" "$("$BIN_DIR/publier" --version 2>/dev/null || echo '(add to PATH, then run: publier --version)')"

if [ "$ON_PATH" = "0" ]; then
	printf "%sAdd to your shell PATH:%s\n" "$c_bold" "$c_reset"
	printf "  echo 'export PATH=\"%s:\$PATH\"' >> ~/.bashrc   # or ~/.zshrc\n" "$BIN_DIR"
	printf "  source ~/.bashrc\n\n"
fi

printf "Next:\n"
printf "  publier new my-docs              # scaffold a new project\n"
printf "  cd my-docs && pnpm install       # enter project and install deps\n"
printf "  publier login --token <token>    # cache your license token\n"
printf "  publier dev                      # start the dev server at http://localhost:4321\n"
printf "\n"
printf "  Docs: https://publier.net/docs/get-started\n"
