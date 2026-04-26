#!/usr/bin/env bash
# publier CLI installer.
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
	[ -n "$EXPECTED" ] || die "tarball not listed in checksums file"
	ACTUAL="$(cd "$TMPDIR" && sha256sum "$TARBALL" | awk '{print $1}')"
	[ "$EXPECTED" = "$ACTUAL" ] || die "SHA-256 mismatch (expected $EXPECTED, got $ACTUAL)"
	ok "SHA-256 matches"
else
	warn "no checksums file at $CHECKSUMS_URL — installing without integrity check"
fi

# --- SLSA provenance verification (optional) ----------------------------------
#
# When `gh` is available, verify the GitHub Artifact Attestation bound to the
# tarball. The attestation binds the binary to a specific workflow run in the
# publier/releases repo — a tampered replacement fails verification because
# only that workflow's OIDC identity can sign.
if command -v gh >/dev/null 2>&1; then
	info "Verifying SLSA provenance attestation"
	if gh attestation verify "$TMPDIR/$TARBALL" --repo "${RELEASES_REPO}" >/dev/null 2>&1; then
		ok "provenance verified (gh attestation)"
	else
		warn "attestation verification failed or not yet published for this release"
		warn "continuing with SHA-256-only trust; install gh ≥2.49 for strongest guarantee"
	fi
else
	warn "gh CLI not installed — skipping SLSA provenance check"
	warn "install https://cli.github.com/ for cryptographic install-time verification"
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
printf "  publier new my-docs     # scaffold a new project\n"
printf "  publier login --token <your-token>    # cache your license token\n"
printf "  https://publier.net/docs/get-started\n"
