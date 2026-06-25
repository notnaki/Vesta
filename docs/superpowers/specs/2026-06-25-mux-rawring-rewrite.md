# Halo multiplexer — raw-ring rewrite (tmux parity)

Date: 2026-06-25
Status: in progress
Supersedes the daemon/libvterm architecture in
`2026-06-24-halo-multiplexer-design.md` (that approach is what we're tearing out).

## Why the rewrite

The old daemon ran its own **libvterm**, kept an "authoritative screen," and on
attach called `screenSnapshot()` — which re-emitted every cell as plain UTF-8,
dropping colors / attributes / cursor / alt-screen state. That lossy snapshot
*was* the garbled output. Keeping that screen model correct across
detach/resize/mirror was the fragile part that broke reattach. ~6k lines of
vendored C (`CVterm`) existed only to power it.

## New architecture (dtach-style, no terminal parsing in the daemon)

Same three processes — survive-quit genuinely needs a daemon holding the PTY —
but the daemon is now **dumb bytes**:

- `halod`: one `forkpty`'d shell per paneID + a bounded **raw byte ring**
  (last N KB of output, no parsing). On attach: send the ring, then stream live
  output. Drains every PTY even with zero clients (no backpressure).
- `halo-attach`: unchanged dumb byte pump. stdin→daemon, daemon→stdout.
- **ghostty** does 100% of VT parsing, live and on reattach. Replaying the raw
  output tail reproduces the screen byte-exactly as ghostty rendered it live —
  colors, cursor, everything. Simpler *and* more correct than the snapshot.

Known ceiling: the ring is byte-bounded, so a reattach can replay a partial
escape sequence at the very front of the buffer (rare, one stray fragment that
ghostty resyncs past). Acceptable vs. the old guaranteed color loss.

## In scope now (tmux parity)

- Shells survive Halo quitting; clean reattach (raw-ring replay).
- Detach UX: close = detach (Cmd-W / quit keep the shell alive); explicit kill.
- `halo sessions` / `halo kill <id>` CLI (already wired via MuxClient).
- Prefix-key mode + named sessions + switcher (M1/M2, already done, untouched).

## Deferred — "the rest", revisit after parity ships

1. **Mirroring** (one paneID attached to multiple panes, live). Old M4. Needs
   size arbitration across clients + focus signaling (SIGUSR1/2 → focus frames).
   Removed for now; daemon currently broadcasts output to all client fds but
   resize is last-writer-wins, not focus-arbitrated.
2. **Remote attach** `halo attach ssh://host`. Old M5. The ssh-URL parser +
   deploy code (`RemoteAttach.swift`, `RemoteAttachCLI.swift`) is left compiling
   but unexercised against the new wire protocol — re-test before relying on it.
3. **Disk-spill scrollback** beyond the RAM ring + **history recovery after a
   daemon crash**. Old design wrote `<id>.log`. Dropped: in-memory ring only,
   like tmux (which also loses scrollback when its server dies).
4. **Inline-image replay across detach** (Kitty graphics placement cache). Old
   `ImageCache`. Live images still work (ghostty); only cross-detach replay is
   gone. tmux has none either.
5. **Native-scrollback restore** as a distinct restored region. Raw-ring replay
   already gives recent scrollback for free up to the ring size; a larger,
   disk-backed restore is the deferred upgrade.

## Files

Deleted: `Sources/CVterm/**`, `HaloMux/{ImageCache,SizeArbitration,ScrollbackRing}.swift`.
Rewritten: `halod/Session.swift`, `halod/Daemon.swift`, `halo-attach/main.swift`,
`HaloMux/MuxProtocol.swift` (dropped `snapshot`/`focus`/`needsUpdate` frames,
bumped protocol version). GUI untouched except removing `signalFocus` mirroring hook.
</content>
