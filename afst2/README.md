# AFST2 - Analytic File Sync Tool 2 (NOT version 2)

The **2** denotes the two-sided/cooperative architecture:  
While AFST operates single-sided, AFST2 allows both ends to participate in the operation.  
Otherwise, AFST2 is the same tool, with the same usage and philosophy as the [original AFST](../README.md)

## The Key difference
### Remote-aware snapshotting & offload

In the original AFST, if either SOURCE or DEST lives behind a network mount (gvfs/sftp/smb/nfs), the snapshot phase has to walk that entire directory tree **through the mount**. On large trees this can be slow: the remote machine could just do that work locally, on its own filesystem, in a fraction of the time. **AFST2 fixes this - but only if you let it.**

### What this requires

For the speed-up to kick in, **AFST2 must also be installed on the remote side** and reachable via SSH.

**AFST2 is no longer strictly a local tool that reads remote mounts.**  
It's redesigned to run as a peer on both ends of the sync.
For this you need to add AFST on remote end:
1) link afst2.sh as "afst" in your $PATH on the remote
2) configure SSH key authentification for your remote end

### How it works

1. AFST2 detects that either SOURCE or DEST resolves through a gvfs mount (sftp, smb, or nfs) and figures out the real user@host and remote path (or SMB share name) behind it.
2. As a "handshake" it initiates: `ssh user@host "afst --snapshot-only <path-or-share>"`.
3. **If that handshake works**, the remote side snapshots itself - locally, natively, no network filesystem overhead,
   **at the same time**, the local side is independently snapshotting whichever end stays local.
   Both snapshots run **asynchronously, in parallel**.
4. AFST2 waits for both snapshots to complete and gather data.
5. From this point on, diff, file selection, copy **everything is identical to the original AFST.**

### The result:  
Maximum snapshot speed, minimum network traffic -remote end "pulls its weight".  
(a single snapshot listing travels the wire instead of a `find`-over-the-network), and no behavioral surprises once syncing actually starts.  
In effect, this is distributed execution, with the remote end, naturally, taking care of the remote snapshot in parallel.

### The fallback (this is the part that makes it safe)

The handshake is deliberately unforgiving in one direction:  
**if it doesn't cleanly succeed, AFST2 doesn't try to be clever about it.**  
If, for any reason:
- the other side isn't reachable over SSH,
- AFST2 isn't installed there,
- the remote is Windows (no matching SSH command at all),
- the path or SMB share can't be resolved on the remote's own end,
- or anything else goes sideways

Fallback is evaluated for both SOURCE and DESTINATION - one can succeed via the "fast path" while the other falls back, and the sync still completes correctly.  
This also means AFST2 works even when invoked from a third machine where *both* SOURCE and DEST are remote to it.

### In short

| | AFST | AFST2 |
|---|---|---|
| Local ↔ Local | `find` locally | same |
| Local ↔ Remote (mount) | `find` over the mount | `find` runs *on the remote*, via SSH handshake - falls back to original behavior if the handshake fails |
| Snapshot timing | sequential | source and destination snapshot **in parallel** whenever both are being taken |
| Diff / copy / everything else | - | **unchanged** |

If you never install AFST2 on the remote side, or the handshake never succeeds, **AFST2 is original AFST**.  
The upgrade is opt-in by nature, you don't have to configure anything to keep it safe, only to make it even faster and more efficient.
