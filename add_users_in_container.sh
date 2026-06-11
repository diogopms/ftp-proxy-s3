#!/usr/bin/env bash
#
# Live-reload loop: periodically pulls the USERS list from the config bucket and
# reconciles accounts (creating users, updating passwords) plus repairs file
# permissions. The actual account logic is shared with users.sh.
set -euo pipefail

# shellcheck source=users.sh
source /usr/local/users.sh

CONFIG_FILE="${CONFIG_FILE:-env.list}"
SLEEP_DURATION="${SLEEP_DURATION:-60}"

# Download the config file and provision every user it lists.
reconcile_users() {
  local tmp
  tmp="$(mktemp)"
  if ! aws s3 cp "s3://$CONFIG_BUCKET/$CONFIG_FILE" "$tmp" >/dev/null 2>&1; then
    log "Could not download s3://$CONFIG_BUCKET/$CONFIG_FILE; skipping this cycle"
    rm -f "$tmp"
    return 0
  fi

  local users_line
  users_line="$(grep -E '^USERS=' "$tmp" | head -n1 | cut -d= -f2- || true)"
  rm -f "$tmp"

  local entry username passwd
  # shellcheck disable=SC2086 # intentional word-splitting on the USERS string
  for entry in $users_line; do
    username="${entry%%:*}"
    passwd="${entry#*:}"
    provision_user "$username" "$passwd" || log "Failed to provision '$username'"
    fix_user_permissions "$username" || log "Failed to fix permissions for '$username'"
  done
}

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
