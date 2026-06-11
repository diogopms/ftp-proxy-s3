#!/usr/bin/env bash
#
# User provisioning for the FTP/SFTP server.
#
# This file doubles as a library: when sourced it only defines functions, and
# when executed directly it performs the initial provisioning from the USERS
# environment variable. add_users_in_container.sh sources it to reuse the same
# logic for the live-reload loop, so the account-management code lives in one
# place.
set -euo pipefail

FTP_DIRECTORY="${FTP_DIRECTORY:-/home/aws/s3bucket/ftp-users}"
FTP_GROUP="${FTP_GROUP:-ftpaccess}"
# Permissions used both when creating users and when repairing files that were
# uploaded to the bucket directly (e.g. via the AWS console).
FILE_PERMISSIONS="${FILE_PERMISSIONS:-644}"
DIRECTORY_PERMISSIONS="${DIRECTORY_PERMISSIONS:-750}"

log() { printf '[users] %s\n' "$*"; }

# Create the shared group and the parent directory for all user homes.
ensure_base() {
  if ! getent group "$FTP_GROUP" >/dev/null 2>&1; then
    groupadd "$FTP_GROUP"
  fi
  mkdir -p "$FTP_DIRECTORY"
  chown root:root "$FTP_DIRECTORY"
  chmod 755 "$FTP_DIRECTORY"
}

# provision_user <username> <password_hash>
# Idempotently creates the account (if missing), (re)sets its password and lays
# out the chrooted home directory, files/ area and .ssh/authorized_keys.
provision_user() {
  local username="$1" passwd="$2"
  if [[ -z "$username" || -z "$passwd" ]]; then
    log "Skipping invalid 'username:password' entry"
    return 0
  fi

  local home="$FTP_DIRECTORY/$username"

  if ! getent passwd "$username" >/dev/null 2>&1; then
    log "Creating user '$username'"
    useradd -d "$home" -s /usr/sbin/nologin "$username"
  fi
  usermod -aG "$FTP_GROUP" "$username"

  # Passwords are provided pre-hashed (chpasswd -e).
  printf '%s:%s\n' "$username" "$passwd" | chpasswd -e

  # Root must own the chroot target; the writable area is files/.
  mkdir -p "$home/files"
  chown "root:$FTP_GROUP" "$home"
  chmod 750 "$home"
  chown "$username:$FTP_GROUP" "$home/files"
  chmod 750 "$home/files"

  # .ssh/authorized_keys for public-key SFTP access.
  mkdir -p "$home/.ssh"
  touch "$home/.ssh/authorized_keys"
  chown -R "$username" "$home/.ssh"
  chmod 700 "$home/.ssh"
  chmod 600 "$home/.ssh/authorized_keys"
}

# fix_user_permissions <username>
# Repairs ownership/permissions on a user's files. Objects uploaded straight to
# S3 (e.g. through the console) appear as 000 root:root and are unreadable over
# FTP; this brings them back in line.
fix_user_permissions() {
  local username="$1"
  local files="$FTP_DIRECTORY/$username/files"
  local ssh="$FTP_DIRECTORY/$username/.ssh"

  [[ -d "$files" ]] || return 0

  find "$files/" -mindepth 1 \( ! -user "$username" -o ! -group "$username" \) \
    -print0 | xargs -0 -r chown "$username:$username"
  find "$files/" -mindepth 1 -type f ! -perm "$FILE_PERMISSIONS" \
    -print0 | xargs -0 -r chmod "$FILE_PERMISSIONS"
  find "$files/" -mindepth 1 -type d ! -perm "$DIRECTORY_PERMISSIONS" \
    -print0 | xargs -0 -r chmod "$DIRECTORY_PERMISSIONS"

  if [[ -d "$ssh" ]]; then
    chown -R "$username" "$ssh"
    chmod 700 "$ssh"
    [[ -f "$ssh/authorized_keys" ]] && chmod 600 "$ssh/authorized_keys"
  fi
}

# provision_users_from_string "<user:hash user2:hash2 ...>"
# Splits a USERS-style string on whitespace and provisions each entry. The
# username is everything before the first ':' and the hash everything after it.
provision_users_from_string() {
  local entry username passwd
  # shellcheck disable=SC2086 # intentional word-splitting on the USERS string
  for entry in $1; do
    username="${entry%%:*}"
    passwd="${entry#*:}"
    provision_user "$username" "$passwd" || log "Failed to provision '$username'"
  done
}

# When run directly, perform the one-shot initial provisioning.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ensure_base
  provision_users_from_string "${USERS:-}"
fi
