# AFST2 — Analytic File Sync Tool v2

AFST2 is the same tool, same usage, same philosophy as the original AFST — with one significant twist.

## Usage

```
afst2 SOURCE_DIR DEST_DIR
```

That's it. Same as original AFST: point it at a source and a destination, it snapshots both, diffs them, and copies over whatever's new or changed in SOURCE. No flags to learn, no config files required to get started.

## Philosophy (unchanged)

- **mtime-based, one-way sync.** A file is queued for copying if it's missing or different (by modification time) on the DEST side. Nothing on DEST is ever deleted or overwritten in the other direction. This is by design, not an oversight.
- **Snapshot → diff → copy.** Three dumb, transparent, inspectable steps. No magic, no daemon, no persistent state beyond the snapshot files it leaves behind in `/tmp`.
- **Fails loud, does nothing clever behind your back.** If something's wrong, AFST2 tells you and stops, rather than guessing.

If you've used AFST before, you already know how to use AFST2. The mental model hasn't changed.

## The Key difference
### Remote-Aware Snapshotting / offloading

Here's what's actually new.

In the original AFST, if either SOURCE or DEST lives behind a network mount (gvfs/sftp/smb/nfs), the snapshot phase has to walk that entire directory tree **through the mount**. On large trees this can be slow: the remote machine could just do that work locally, on its own filesystem, in a fraction of the time.

**AFST2 fixes this — but only if you let it.**

### What this requires

For the speed-up to kick in, **AFST2 must also be installed on the remote side**, reachable via SSH, and callable as `afst2 --snapshot-only <path>`.

This is the key structural difference from original: AFST2 is no longer purely a local tool that happens to read remote mounts. It's designed to run as a peer on both ends of the sync.

### How it works

1. AFST2 detects that SOURCE and/or DEST resolves through a gvfs mount (sftp, smb, or nfs) and figures out the real user@host and remote path (or SMB share name) behind it.
2. It attempts a handshake: `ssh user@host "afst2 --snapshot-only <path-or-share>"`.
3. **If that handshake works**, the remote side snapshots itself — locally, natively, no network filesystem overhead — while, **at the same time**, the local side is independently snapshotting whichever end stays local. Both snapshots run **asynchronously, in parallel**.
4. AFST2 waits for both snapshots to complete, then collects them.
5. From this point on — diff, file selection, copy — **everything is identical to the original AFST.** The twist is entirely contained in phase 1-4; nothing downstream changes.

The result: maximum snapshot speed, minimum network traffic (a single small snapshot listing travels the wire instead of a `find`-over-the-network for every file), and no behavioral surprises once syncing actually starts.

### The fallback (this is the part that makes it safe)

The handshake is deliberately unforgiving in one direction: **if it doesn't cleanly succeed, AFST2 doesn't try to be clever about it.**

If, for any reason:
- the other side isn't reachable over SSH,
- AFST2 isn't installed there,
- the remote is Windows (no matching SSH command at all),
- the path or SMB share can't be resolved on the remote's own end,
- or anything else goes sideways

— **AFST2 falls back to the standard snapshot method**: a local `find` walking the network mount, exactly as original AFST always did. Nothing breaks, nothing hangs waiting on something that isn't going to answer. You lose the speed-up for that run, not the sync.

This fallback is evaluated **per side, independently.** SOURCE and DEST are judged separately - one can succeed via the fast path while the other falls back, and the sync still completes correctly either way. This also means AFST2 works unmodified even when invoked from a third machine where *both* SOURCE and DEST are remote to it.

### In short

| | AFST (v1) | AFST2 |
|---|---|---|
| Local ↔ Local | `find` locally | same |
| Local ↔ Remote (mount) | `find` over the mount | `find` runs *on the remote*, via SSH handshake - falls back to original behavior if the handshake fails |
| Snapshot timing | sequential | source and destination snapshot **in parallel** whenever both are being taken |
| Diff / copy / everything else | - | **unchanged** |

If you never install AFST2 on the remote side, or the handshake never succeeds, AFST2 *is* original AFST. The upgrade is opt-in by nature, you don't have to configure anything to keep it safe, only to make it fast.
