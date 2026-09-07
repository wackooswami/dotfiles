#!/usr/bin/env bash
#
# setup.sh - symlink these dotfiles into ~/.config using GNU Stow.
#
# Usage:
#   ./setup.sh              stow every package into ~/.config
#   ./setup.sh hypr nvim    stow only the named packages
#   ./setup.sh -n           dry run (show what would happen, change nothing)
#   ./setup.sh -D           unstow (remove the symlinks) instead of installing
#
set -uo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

# Directories that live in the repo but aren't stow packages.
EXCLUDE=(.git README.md setup.sh)

color() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
info()  { color '1;34' "==> $*"; }
warn()  { color '1;33' "!!  $*"; }
ok()    { color '1;32' " ✓  $*"; }
err()   { color '1;31' " ✗  $*"; }

STOW_ARGS=(-v)
MODE="stow"
DRY_RUN=false
PACKAGES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) STOW_ARGS+=(-n); DRY_RUN=true ;;
    -D|--delete)  MODE="delete" ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      err "Unknown option: $1"
      exit 1
      ;;
    *) PACKAGES+=("$1") ;;
  esac
  shift
done

# --- make sure stow is available ------------------------------------------

if ! command -v stow &>/dev/null; then
  warn "GNU Stow is not installed."
  if command -v emerge &>/dev/null; then
    info "Installing stow with emerge (requires sudo)..."
    sudo emerge --ask app-admin/stow
  elif command -v apt &>/dev/null; then
    info "Installing stow with apt (requires sudo)..."
    sudo apt update && sudo apt install -y stow
  elif command -v dnf &>/dev/null; then
    info "Installing stow with dnf (requires sudo)..."
    sudo dnf install -y stow
  elif command -v pacman &>/dev/null; then
    info "Installing stow with pacman (requires sudo)..."
    sudo pacman -S --noconfirm stow
  elif command -v zypper &>/dev/null; then
    info "Installing stow with zypper (requires sudo)..."
    sudo zypper install -y stow
  elif command -v brew &>/dev/null; then
    info "Installing stow with brew..."
    brew install stow
  else
    err "Could not detect a package manager. Please install GNU Stow manually and re-run this script."
    exit 1
  fi
fi

if ! command -v stow &>/dev/null; then
  err "stow still isn't on PATH after attempting install. Aborting."
  exit 1
fi

# --- figure out which packages to (un)stow ---------------------------------

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  for entry in "$DOTFILES_DIR"/*/; do
    name="$(basename -- "$entry")"
    skip=false
    for ex in "${EXCLUDE[@]}"; do
      [[ "$name" == "$ex" ]] && skip=true && break
    done
    $skip || PACKAGES+=("$name")
  done
fi

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  err "No packages found in $DOTFILES_DIR"
  exit 1
fi

mkdir -p "$TARGET_DIR"

info "Dotfiles dir: $DOTFILES_DIR"
info "Target dir:   $TARGET_DIR"
info "Packages:     ${PACKAGES[*]}"
echo

# --- clear out stale/broken symlinks that would make stow bail out ---------

for pkg in "${PACKAGES[@]}"; do
  target_path="$TARGET_DIR/$pkg"
  if [[ -L "$target_path" && ! -e "$target_path" ]]; then
    if $DRY_RUN; then
      warn "Would remove broken symlink $target_path"
    else
      warn "Removing broken symlink $target_path"
      rm -f -- "$target_path"
    fi
  fi
done

# --- stow (or unstow) each package ------------------------------------------

failures=()
for pkg in "${PACKAGES[@]}"; do
  if [[ ! -d "$DOTFILES_DIR/$pkg" ]]; then
    warn "Skipping '$pkg': no such directory in $DOTFILES_DIR"
    continue
  fi

  target_path="$TARGET_DIR/$pkg"
  action=(-R "${STOW_ARGS[@]}")
  [[ "$MODE" == "delete" ]] && action=(-D "${STOW_ARGS[@]}")

  # Each package dir (e.g. dotfiles/hypr/*) mirrors the *contents* of its
  # matching ~/.config subdir, so target one level deeper than $TARGET_DIR -
  # otherwise stow has no directory to fold and scatters files straight
  # into $TARGET_DIR instead of $TARGET_DIR/$pkg. stow also requires the
  # target to already exist, so create it (and clean it back up if this
  # was only a dry run and it ended up empty).
  pre_existing_dir=true
  [[ -d "$target_path" ]] || pre_existing_dir=false
  mkdir -p "$target_path"
  if stow -d "$DOTFILES_DIR" -t "$target_path" "${action[@]}" "$pkg"; then
    ok "$pkg"
  else
    err "$pkg failed (likely a conflicting file already in $TARGET_DIR/$pkg)"
    failures+=("$pkg")
  fi
  if $DRY_RUN && ! $pre_existing_dir; then
    rmdir --ignore-fail-on-non-empty -- "$target_path" 2>/dev/null || true
  fi
done

echo
if [[ ${#failures[@]} -eq 0 ]]; then
  ok "Done."
else
  err "Finished with problems in: ${failures[*]}"
  warn "Back up or remove the conflicting files/dirs under $TARGET_DIR and re-run this script."
  exit 1
fi
