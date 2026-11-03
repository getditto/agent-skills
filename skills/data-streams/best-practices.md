# Best practices

1. **Decide stream vs document first.** If anyone needs the bytes later, offline, queried or
   converged, it is a document (or an attachment). Streams are for now-or-never data.
2. **Say "preview" out loud.** Version floor (Kotlin 5.1.0, Swift 5.2.0 via SPI), per-file
   opt-in, and "may change without notice" belong in the code review and the PR.
3. **One owner per role.** A receiver session owns the acceptor *and* its streams; a sender
   session owns one stream per peer and topic. Both are closable and closed before `Ditto`.
4. **Open candidates where you get them**, or `take()` and close the taken one. Never let
   an exception escape the bind callback: an unopened candidate is a timed-out connector.
5. **Match reliability to the data**, not to a feeling of safety: unreliable for frames the
   next frame supersedes, reliable for things that must arrive in order. Tolerate
   duplicates in both.
6. **Connect once, send many.** Cache `maxSendSize`, check it per send, pick one send mode.
7. **Bounded queues everywhere.** Drop oldest on a slow link; never buffer unboundedly on
   either side of the driver-thread callback.
8. **Own reconnection.** Streams never reconnect. Keep one connect loop per (peer, topic)
   with capped exponential backoff and jitter, and stop it when the peer leaves presence.
9. **Deterministic roles for symmetric peers**: lower peer key connects, higher accepts.
10. **Enable NGN before the instance exists** and keep `replication_over_ngn` identical on
    every replicating peer. Modify the live transport config; never replace it.
11. **Keep your own keys.** Index streams by `(peerKey, topic)` you already know rather
    than reading them back from the stream.
12. **Test with two real peers** (two devices, or two instances in one process over a
    loopback TCP listener as the fixtures do). Presence, binding order and reliability
    mismatches only show up with a second peer.
