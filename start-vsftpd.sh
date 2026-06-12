#!/usr/bin/env bash
#
# Waits for the S3 bucket to be mounted before starting vsftpd, so the server
# never exposes the empty mount point while s3fs is still coming up.
set -euo pipefail

MOUNT_POINT="${MOUNT_POINT:-/home/aws/s3bucket}"
VSFTPD_CONF="${VSFTPD_CONF:-/etc/vsftpd.conf}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-60}"

log() { printf '[vsftpd] %s\n' "$*"; }

for _ in $(seq 1 "$WAIT_TIMEOUT"); do
  if mountpoint -q "$MOUNT_POINT"; then
    log "Mount ready; starting vsftpd"
    exec /usr/sbin/vsftpd "$VSFTPD_CONF"
  fi
  sleep 1
done

log "$MOUNT_POINT not mounted after ${WAIT_TIMEOUT}s; exiting so supervisor can retry"
exit 1
