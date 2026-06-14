#!/usr/bin/env bats
#
# Tests for the live-reload reconcile step in add_users_in_container.sh, which
# reads the USERS list from the config file mounted by s3-fuse.sh. System
# commands are replaced by the recording stubs in tests/stubs.

setup() {
  TESTDIR="$(mktemp -d)"
  export STUB_LOG="$TESTDIR/calls.log"
  : > "$STUB_LOG"
  export FTP_DIRECTORY="$TESTDIR/ftp-users"
  export CONFIG_MOUNT="$TESTDIR/config"
  mkdir -p "$CONFIG_MOUNT"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # Source the live-reload script as a library (the run-loop is guarded), with
  # the user library pointed at the repo copy.
  export USERS_LIB="$BATS_TEST_DIRNAME/../users.sh"
  source "$BATS_TEST_DIRNAME/../add_users_in_container.sh"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "reconcile_users provisions users listed in the mounted config file" {
  printf 'USERS=alice:$1$a$h1 bob:$6$b$h2\nFTP_BUCKET=x\n' > "$CONFIG_MOUNT/env.list"
  reconcile_users
  grep -q "useradd -d $FTP_DIRECTORY/alice " "$STUB_LOG"
  grep -q "useradd -d $FTP_DIRECTORY/bob " "$STUB_LOG"
  grep -Fq 'chpasswd -e <<< bob:$6$b$h2' "$STUB_LOG"
}

@test "reconcile_users is a no-op when the config file is missing" {
  run reconcile_users
  [ "$status" -eq 0 ]
  ! grep -q "useradd" "$STUB_LOG"
}

@test "reconcile_users ignores other keys in the config file" {
  printf 'FTP_BUCKET=mybucket\nUSERS=carol:$1$c$h\nCONFIG_BUCKET=cfg\n' > "$CONFIG_MOUNT/env.list"
  reconcile_users
  grep -q "useradd -d $FTP_DIRECTORY/carol " "$STUB_LOG"
  ! grep -q "mybucket" "$STUB_LOG"
}

@test "sourcing add_users_in_container.sh does not start the reconcile loop" {
  # setup already sourced it; reconcile must not have run on source.
  ! grep -q "useradd" "$STUB_LOG"
  declare -F reconcile_users >/dev/null
}
