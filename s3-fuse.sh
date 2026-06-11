#!/usr/bin/env bash
#
# Mounts the S3 bucket with s3fs, configures vsftpd's passive address and runs
# the initial user provisioning.
set -euo pipefail

MOUNT_POINT="${MOUNT_POINT:-/home/aws/s3bucket}"
VSFTPD_CONF="${VSFTPD_CONF:-/etc/vsftpd.conf}"

log() { printf '[s3-fuse] %s\n' "$*"; }
die() { log "$*"; exit 1; }

# --- required configuration -------------------------------------------------
[[ -n "${FTP_BUCKET:-}" ]] || die "FTP_BUCKET is not set. Aborting!"

# Either an IAM role or a static AWS credential pair must be provided. When
# there is no IAM role, write the credentials to the s3fs password file.
if [[ -z "${IAM_ROLE:-}" ]]; then
  log "IAM_ROLE not set; expecting AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY."
  [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || die "AWS_ACCESS_KEY_ID is not set. Aborting!"
  [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] || die "AWS_SECRET_ACCESS_KEY is not set. Aborting!"

  umask 077
  printf '%s:%s\n' "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" > "$HOME/.passwd-s3fs"
  chmod 600 "$HOME/.passwd-s3fs"
fi

# --- passive-mode address ---------------------------------------------------

# Query the EC2 Instance Metadata Service (IMDSv2, falling back to IMDSv1) for
# the instance's public IPv4 address. Prints the address on success.
detect_ec2_public_ip() {
  local imds="http://169.254.169.254" token ip
  local -a auth=()
  token="$(curl -s --max-time 2 -X PUT "$imds/latest/api/token" \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' 2>/dev/null || true)"
  [[ -n "$token" ]] && auth=(-H "X-aws-ec2-metadata-token: $token")
  ip="$(curl -s --max-time 2 "${auth[@]}" "$imds/latest/meta-data/public-ipv4" 2>/dev/null || true)"
  [[ -n "$ip" ]] || return 1
  printf '%s' "$ip"
}

configure_pasv_address() {
  local ip
  if [[ -n "${PASV_ADDRESS:-}" ]]; then
    ip="$PASV_ADDRESS"
  elif ip="$(detect_ec2_public_ip)"; then
    log "Detected EC2 public IPv4: $ip"
  else
    die "PASV_ADDRESS is not set and EC2 metadata is unavailable. Aborting!"
  fi
  sed -i "s/^pasv_address=.*/pasv_address=$ip/" "$VSFTPD_CONF"
}

configure_pasv_address

# --- mount ------------------------------------------------------------------
mkdir -p "$MOUNT_POINT"

# -o nonempty lets s3fs mount over a directory that is not empty (see issue #1).
s3fs_opts=(
  -o allow_other
  -o mp_umask=0022
  -o nonempty
  -o stat_cache_expire=600
)
[[ -n "${IAM_ROLE:-}" ]] && s3fs_opts+=(-o iam_role="$IAM_ROLE")

log "Mounting s3://$FTP_BUCKET at $MOUNT_POINT"
# s3fs is resolved from PATH (/usr/bin or /usr/local/bin depending on the build).
if ! s3fs "$FTP_BUCKET" "$MOUNT_POINT" "${s3fs_opts[@]}"; then
  die "s3fs failed to mount '$FTP_BUCKET'. Aborting!"
fi

if command -v mountpoint >/dev/null 2>&1 && ! mountpoint -q "$MOUNT_POINT"; then
  die "'$MOUNT_POINT' is not mounted after s3fs. Aborting!"
fi

# Initial user provisioning.
/usr/local/users.sh
