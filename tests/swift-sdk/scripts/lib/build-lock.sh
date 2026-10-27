#
# One build lock, shared by run.sh, build-platforms.sh and persistence-matrix.sh.
#
# Two concurrent swift/xcodebuild invocations against this .build directory produce
# confusing failures — "build.db: database is locked", and dlopen crashes from a
# half-written framework — that read as SDK bugs.
#
# `mkdir` rather than `flock`: flock is not present on macOS, where this fixture runs, so
# a flock-based guard would be a silent no-op on the only platform that needs it.
#
# Sourced rather than copied into each script. It was copied three times before, and the
# copies had already diverged: one of them installed no EXIT trap, so an early exit left
# the lock behind and the next command sat in the ten-minute wait.
#
# Requires FIXTURE_DIR.

acquire_build_lock() {
  local lock="$FIXTURE_DIR/.build.lock" waited=0 owner

  # `mkdir` can never succeed against a plain file, so waiting ten minutes for one to go
  # away is ten minutes of nothing.
  if [[ -e "$lock" && ! -d "$lock" ]]; then
    echo "$lock exists but is not a directory; remove it and retry" >&2
    exit 1
  fi

  until mkdir "$lock" 2>/dev/null; do
    # A run that was killed (or a machine that rebooted) leaves the directory behind.
    # We used to break such locks in-band once the owner pid was gone — but every
    # variant of that races. Even the rename-then-revalidate "claim" version has a
    # window: a second waiter can displace a live lock, a third caller acquires the
    # empty path, and the restore `mv` then nests the displaced directory inside the
    # third caller's lock — two builds in .build at once. No in-band recovery can
    # close that, because recovery and acquisition are not one atomic step. So this
    # script never removes a lock it did not create: a dead owner fails loudly with
    # the diagnosis, and a human removes the directory.
    owner="$(cat "$lock/pid" 2>/dev/null || true)"
    if [[ $waited -ge 10 && -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
      echo "$lock is stale: owner process $owner is gone." >&2
      echo "Remove it with:  rm -rf '$lock'" >&2
      exit 1
    fi

    if [[ $waited -ge 600 ]]; then
      echo "another run has held $lock for 10 minutes; remove it if that run is gone" >&2
      exit 1
    fi
    # `${lock}`, braced: bash absorbs the following multi-byte character into the
    # variable name otherwise, and `set -u` then reports it as unbound.
    [[ $waited -eq 0 ]] && echo "waiting for another run to release ${lock}" >&2
    sleep 2
    waited=$((waited + 2))
  done

  echo "$$" > "$lock/pid"

  # Installed HERE, not by the caller: every exit path after this point — including the
  # argument and environment checks the callers run next — must release the lock.
  # Expand the path now, since `lock` is a local a single-quoted trap could not see.
  trap "rm -rf '$lock'" EXIT
}
