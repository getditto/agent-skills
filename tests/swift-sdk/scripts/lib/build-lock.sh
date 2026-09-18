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
    # Break a lock whose owner is gone rather than waiting out a process that will never
    # exit. The grace period lets a holder that has just won the `mkdir` write its pid
    # before anyone judges it dead.
    owner="$(cat "$lock/pid" 2>/dev/null || true)"
    if [[ $waited -ge 10 && -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
      echo "removing a stale ${lock} left by process $owner" >&2
      # Rename first: only one contender's `mv` can succeed, so a second one cannot
      # delete the fresh lock the winner is about to create.
      if mv "$lock" "$lock.stale.$$" 2>/dev/null; then
        rm -rf "$lock.stale.$$"
      fi
      continue
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
