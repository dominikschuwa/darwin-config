#!/usr/bin/env bash
#
# zen-list-profiles.sh
#
# Lists Zen browser profiles with hints about which one actually
# contains your data (logins, sessions, etc.).
#
# Why this exists: every Nix rebuild changes Zen's on-disk path, so
# Zen recomputes its "install hash", treats each rebuild as a new
# install, and silently spawns a fresh empty profile. To stop the
# bleed declaratively, the home-manager config declares
# `programs.zen-browser.profiles.main = { };` — that writes a
# Default=1 entry in profiles.ini, which catches every future
# install-hash and re-binds it to the same profile.
#
# To migrate an existing orphaned profile into that declarative
# slot, quit Zen and run:
#
#   mv "$HOME/Library/Application Support/Zen/Profiles/<old-dir>" \
#      "$HOME/Library/Application Support/Zen/Profiles/main"
#   rm  "$HOME/Library/Application Support/Zen/installs.ini"
#
# Use this script to figure out which <old-dir> is the right one.

set -euo pipefail

ZEN_DIR="${HOME}/Library/Application Support/zen"
PROFILES_DIR="${ZEN_DIR}/Profiles"

if [[ ! -d "$PROFILES_DIR" ]]; then
    # The home-manager module spells the dir "Zen"; case-insensitive
    # APFS hides the difference, but be defensive anyway.
    ZEN_DIR="${HOME}/Library/Application Support/Zen"
    PROFILES_DIR="${ZEN_DIR}/Profiles"
fi

if [[ ! -d "$PROFILES_DIR" ]]; then
    echo "error: no Zen Profiles directory under ~/Library/Application Support" >&2
    exit 1
fi

# Collect profile dirs, newest mtime first. NUL-delimited so spaces
# (e.g. "Default (release)-1") survive intact.
profile_paths=()
while IFS= read -r -d '' line; do
    profile_paths+=("${line#* }")
done < <(
    /usr/bin/find "$PROFILES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 \
    | xargs -0 stat -f '%m %N' \
    | sort -rn \
    | tr '\n' '\0'
)

if (( ${#profile_paths[@]} == 0 )); then
    echo "no profile directories in $PROFILES_DIR"
    exit 0
fi

echo "Zen profiles in $PROFILES_DIR (newest first):"
echo
printf '  %-46s %-17s %-6s %-7s %-9s\n' \
    'profile' 'modified' 'files' 'logins' 'sessions'
for p in "${profile_paths[@]}"; do
    bn=$(basename "$p")
    mtime=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$p")
    files=$(/usr/bin/find "$p" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
    has_logins=no
    [[ -f "$p/logins.json" || -f "$p/key4.db" ]] && has_logins=yes
    has_sessions=no
    [[ -d "$p/sessionstore-backups" ]] && has_sessions=yes
    printf '  %-46s %-17s %-6s %-7s %-9s\n' \
        "$bn" "$mtime" "$files" "$has_logins" "$has_sessions"
done

cat <<EOF

To adopt the right profile into the declarative slot, quit Zen and:

  mv "$PROFILES_DIR/<old-dir>" "$PROFILES_DIR/main"
  rm "$ZEN_DIR/installs.ini"

Then relaunch Zen — it will fall through to the Default=1 entry in
profiles.ini and bind the new install-hash to Profiles/main.
EOF
