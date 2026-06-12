#!/usr/bin/env bats
#
# Unit tests for the user-provisioning library (users.sh). System commands
# (useradd, getent, chpasswd, ...) are replaced by recording stubs in
# tests/stubs so the logic can be exercised without root or real accounts.

setup() {
  TESTDIR="$(mktemp -d)"
  export STUB_LOG="$TESTDIR/calls.log"
  : > "$STUB_LOG"
  export FTP_DIRECTORY="$TESTDIR/ftp-users"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # shellcheck source=../users.sh
  source "$BATS_TEST_DIRNAME/../users.sh"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "ensure_base creates the base directory and group" {
  ensure_base
  [ -d "$FTP_DIRECTORY" ]
  grep -q "groupadd ftpaccess" "$STUB_LOG"
}

@test "ensure_base does not recreate an existing group" {
  STUB_EXISTING_GROUPS="ftpaccess" ensure_base
  ! grep -q "groupadd" "$STUB_LOG"
}

@test "provision_user creates a new account and home layout" {
  provision_user alice '$1$salt$hashA'
  grep -q "useradd -d $FTP_DIRECTORY/alice -s /usr/sbin/nologin alice" "$STUB_LOG"
  grep -q "usermod -aG ftpaccess alice" "$STUB_LOG"
  [ -d "$FTP_DIRECTORY/alice/files" ]
  [ -d "$FTP_DIRECTORY/alice/.ssh" ]
  [ -f "$FTP_DIRECTORY/alice/.ssh/authorized_keys" ]
}

@test "provision_user sets the (pre-hashed) password" {
  provision_user bob '$6$salt$hashB'
  grep -Fq 'chpasswd -e <<< bob:$6$salt$hashB' "$STUB_LOG"
}

@test "provision_user updates an existing account without useradd" {
  STUB_EXISTING_USERS="carol" provision_user carol '$1$s$h'
  ! grep -q "useradd" "$STUB_LOG"
  grep -Fq 'chpasswd -e <<< carol:$1$s$h' "$STUB_LOG"
}

@test "provision_user skips entries with an empty password" {
  provision_user dave ""
  ! grep -q "useradd" "$STUB_LOG"
  ! grep -q "chpasswd" "$STUB_LOG"
}

@test "provision_users_from_string provisions every entry and keeps hashes intact" {
  provision_users_from_string 'eve:$1$a$h1 frank:$6$b$h2'
  grep -q "useradd -d $FTP_DIRECTORY/eve " "$STUB_LOG"
  grep -q "useradd -d $FTP_DIRECTORY/frank " "$STUB_LOG"
  grep -Fq 'chpasswd -e <<< eve:$1$a$h1' "$STUB_LOG"
  grep -Fq 'chpasswd -e <<< frank:$6$b$h2' "$STUB_LOG"
}

@test "fix_user_permissions is a no-op when the files dir is missing" {
  run fix_user_permissions ghost
  [ "$status" -eq 0 ]
  ! grep -q "chown" "$STUB_LOG"
}

@test "fix_user_permissions repairs ownership of S3-uploaded files" {
  # 'daemon' is a stock account on Debian/Ubuntu; fix_user_permissions uses
  # find -user/-group, which require the name to resolve in the OS passwd db
  # (in production the FTP user always exists by the time this runs).
  mkdir -p "$FTP_DIRECTORY/daemon/files"
  echo data > "$FTP_DIRECTORY/daemon/files/object.txt"
  fix_user_permissions daemon
  grep -q "chown daemon:daemon" "$STUB_LOG"
}

@test "sourcing users.sh defines functions but does not provision" {
  # setup already sourced the library; provisioning must not have run on source.
  ! grep -q "useradd" "$STUB_LOG"
  declare -F provision_user >/dev/null
  declare -F fix_user_permissions >/dev/null
  declare -F ensure_base >/dev/null
}

@test "running users.sh directly provisions from USERS" {
  run env USERS='ivan:$1$x$y' FTP_DIRECTORY="$FTP_DIRECTORY" \
    STUB_LOG="$STUB_LOG" PATH="$BATS_TEST_DIRNAME/stubs:$PATH" \
    bash "$BATS_TEST_DIRNAME/../users.sh"
  [ "$status" -eq 0 ]
  grep -q "useradd -d $FTP_DIRECTORY/ivan " "$STUB_LOG"
}
