#!/usr/bin/env bash
#
# Live-reload loop: periodically pulls the USERS list from the config bucket and
# reconciles accounts (creating users, updating passwords) plus repairs file
# permissions. The actual account logic is shared with users.sh.
set -euo pipefail

# shellcheck source=users.sh
source "${USERS_LIB:-/usr/local/users.sh}"

CONFIG_MOUNT="${CONFIG_MOUNT:-/home/aws/config}"
CONFIG_FILE="${CONFIG_FILE:-env.list}"
CONFIG_PATH="$CONFIG_MOUNT/$CONFIG_FILE"
SLEEP_DURATION="${SLEEP_DURATION:-60}"

# Read the config file (mounted read-only from the config bucket by s3-fuse.sh)
# and provision every user it lists.
reconcile_users() {
  if [[ ! -r "$CONFIG_PATH" ]]; then
    log "Config file $CONFIG_PATH is not readable yet; skipping this cycle"
    return 0
  fi

  local users_line
  users_line="$(grep -E '^USERS=' "$CONFIG_PATH" | head -n1 | cut -d= -f2- || true)"

  local entry username passwd
  # shellcheck disable=SC2086 # intentional word-splitting on the USERS string
  for entry in $users_line; do
    username="${entry%%:*}"
    passwd="${entry#*:}"
    provision_user "$username" "$passwd" || log "Failed to provision '$username'"
    fix_user_permissions "$username" || log "Failed to fix permissions for '$username'"
  done
}

# The reconcile loop only runs when executed directly; sourcing this file (e.g.
# from the test suite) just defines reconcile_users.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ -z "${CONFIG_BUCKET:-}" ]]; then
    log "CONFIG_BUCKET is not set; live user reload is disabled."
    # Stay alive (supervised) without busy-looping.
    exec sleep infinity
  fi

  ensure_base
  while true; do
    reconcile_users || log "Reconcile cycle failed; will retry"
    sleep "$SLEEP_DURATION"
  done
fi
