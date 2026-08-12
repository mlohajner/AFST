#!/usr/bin/env bash
set -euo pipefail

# --- config ---
WORKDIR="/tmp"
TS=$(date +%Y-%m-%dT%H-%M-%S)
SNAP_SRC="$WORKDIR/snapshot_src_${TS}.txt"
SNAP_DST="$WORKDIR/snapshot_dst_${TS}.txt"
DIFF="$WORKDIR/snapshot_${TS}.diff"
FILES="$WORKDIR/files_to_sync_${TS}.txt"
ERR_SRC="$WORKDIR/remote_err_src_${TS}.txt"
ERR_DST="$WORKDIR/remote_err_dst_${TS}.txt"

# ============================================================
# resolve_smb_share_path SHARE
#
# Runs ON THE REMOTE SIDE (called from --snapshot-only --smb-share).
# Reads /etc/samba/smb.conf locally (no network/ssh needed for this,
# it's already running on the box that owns the share) and returns
# the real "path =" for the given [SHARE] section.
#
# Known limitation: does not follow "include = ..." directives some
# smb.conf setups use to split config across files. Good enough for
# a standard single-file smb.conf; extend if your setup needs it.
# ============================================================
resolve_smb_share_path() {
	local share="$1" conf="/etc/samba/smb.conf"
	local in_section=0 sect line path=""
	[ -r "$conf" ] || return 1
	while IFS= read -r line; do
		line="${line%%;*}"; line="${line%%#*}"
		line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
		[ -z "$line" ] && continue
		if [[ "$line" =~ ^\[(.+)\]$ ]]; then
			sect="${BASH_REMATCH[1]}"
			[ "$sect" == "$share" ] && in_section=1 || in_section=0
			continue
		fi
		if [ "$in_section" -eq 1 ] && [[ "$line" =~ ^path[[:space:]]*=[[:space:]]*(.+)$ ]]; then
			path="${BASH_REMATCH[1]}"
			break
		fi
	done < "$conf"
	[ -n "$path" ] || return 1
	printf '%s' "$path"
}

# ============================================================
# --snapshot-only mode
#
# This gets invoked on the REMOTE side via ssh during
# the handshake. It does snapshot itself and responds to far end.
#
# Calling form: afst --snapshot-only ARG
#   1) try ARG as a literal directory
#   2) if that fails, treat ARG as SHARE or SHARE/SUBPATH and
#      resolve SHARE via this box's own smb.conf
#   3) if that also fails -> exit 1, caller falls back to gvfs/find
# ============================================================
if [ "${1:-}" == "--snapshot-only" ]; then
	ARG="${2:-}"
	if [ -z "$ARG" ]; then
		echo "AFST ERROR: missing arg for --snapshot-only" >&2
		exit 1
	fi

	DIR="$ARG"
	if [ ! -d "$DIR" ]; then
		if [[ "$ARG" == */* ]]; then
			SHARE="${ARG%%/*}"
			SUBPATH="${ARG#*/}"
		else
			SHARE="$ARG"
			SUBPATH=""
		fi
		if SHAREROOT=$(resolve_smb_share_path "$SHARE"); then
			DIR="${SHAREROOT%/}/${SUBPATH}"
		fi
	fi

	if [ ! -d "$DIR" ]; then
		echo "AFST ERROR: invalid dir for --snapshot-only ('$ARG')" >&2
		exit 1
	fi
	(
		cd "$DIR"
		find . -type f -printf '%P\t%T@\n' | sort
	)
	exit 0
fi

# --- checks ---
if [ $# -ne 2 ] || [ "$1" == "" ] || [ "$2" == "" ]; then
	printf " \ AFST \  Analytic File Sync Tool V1\n"
	printf "            😃 by Mario Lohajner 2025-2026\n"
	printf "\n"
	printf "Usage: %s SOURCE_DIR DEST_DIR\n\n" "$0"
	exit 1
fi

SRC="$1"
DST="$2"

if [ ! -d "$SRC" ] || [ ! -d "$DST" ]; then
	printf "AFST ERROR:\nSOURCE and DEST must be existing directories!\n"
	exit 1
fi

mkdir -p "$WORKDIR"

# --- snapshot (local / gvfs fallback path) ---
snapshot() {
	local dir="$1"
	(
		cd "$dir"
		find . -type f -printf '%P\t%T@\n' | sort
	)
}

# ============================================================
# gvfs remote detection: sftp / ftp / smb / nfs
#
# gvfs mounts resolve to paths like:
#   .../gvfs/sftp:host=HOST,port=PORT,user=USER/actual/remote/path
#   .../gvfs/smb-share:server=HOST,share=SHARE,user=USER/subpath/in/share
#   .../gvfs/nfs:host=HOST,dir=EXPORTED_DIR/subpath (uncommon: NFS is
#       usually a native kernel mount, not gvfs/FUSE, in which case it
#       never matches here at all -- which is fine, since a native NFS
#       mount doesn't need offloading in the first place)
#
# For SRC/DST we need who to ssh into (user@host), plus either:
#  - the REAL absolute remote path (sftp, nfs -> we already have it), or
#  - share name + subpath (smb -> remote AFST resolves the real path
#    itself via its own /etc/samba/smb.conf, we don't guess it here)
#
# If the remote side is Windows (or just doesn't have afst), the ssh
# handshake below simply fails and that side falls back to the old
# gvfs/find path automatically -- no special-casing needed for that.
# ============================================================

# ssh user fallback when the mount itself doesn't carry one (smb, nfs)
: "${AFST_SSH_USER:=$USER}"

# Sets globals: RG_HOST (user@host) RG_ARG (single arg for --snapshot-only)
#   sftp/nfs -> RG_ARG = real absolute remote path
#   smb      -> RG_ARG = "SHARE" or "SHARE/SUBPATH" (remote resolves it)
parse_gvfs_remote() {
	RG_HOST=""; RG_ARG=""
	local path="$1" resolved
	resolved=$(realpath -m -- "$path")

# --- sftp / ftp ---
	if [[ "$resolved" =~ gvfs/s?ftp:host=([^,/]+)(,port=([0-9]+))?(,user=([^,/]+))?/(.*)$ ]]; then
		local host="${BASH_REMATCH[1]}"
		local user="${BASH_REMATCH[5]:-$AFST_SSH_USER}"
		RG_HOST="${user}@${host}"; RG_ARG="/${BASH_REMATCH[6]}"
		return 0
	fi

# --- smb ---
# .../gvfs/smb-share:server=HOST,share=SHARE[,user=USER]/subpath
# "share" is not a filesystem path -- hand it over as-is, remote
# AFST resolves it against its own smb.conf
	if [[ "$resolved" =~ gvfs/smb-share:server=([^,/]+),share=([^,/]+)(,user=([^,/]+))?/?(.*)$ ]]; then
		local host="${BASH_REMATCH[1]}"
		local user="${BASH_REMATCH[4]:-$AFST_SSH_USER}"
		local share="${BASH_REMATCH[2]}" subpath="${BASH_REMATCH[5]}"
		RG_HOST="${user}@${host}"
		if [ -n "$subpath" ]; then RG_ARG="${share}/${subpath}"; else RG_ARG="$share"; fi
		return 0
	fi

# --- nfs (only if mounted via gio, not a native kernel mount) ---
	if [[ "$resolved" =~ gvfs/nfs:host=([^,/]+),dir=([^,]+)/?(.*)$ ]]; then
		local host="${BASH_REMATCH[1]}"
		local exported_dir="${BASH_REMATCH[2]}"
		RG_HOST="${AFST_SSH_USER}@${host}"
		RG_ARG="${exported_dir%/}/${BASH_REMATCH[3]}"
		return 0
	fi

	return 1
}

REMOTE_SRC_HOST=""; REMOTE_SRC_ARG=""
REMOTE_DST_HOST=""; REMOTE_DST_ARG=""
if parse_gvfs_remote "$SRC"; then
	REMOTE_SRC_HOST="$RG_HOST"; REMOTE_SRC_ARG="$RG_ARG"
fi
if parse_gvfs_remote "$DST"; then
	REMOTE_DST_HOST="$RG_HOST"; REMOTE_DST_ARG="$RG_ARG"
fi

# Tries executing "afst --snapshot-only ARG" on the remote side in the background.
# stdout -> snapshot file, stderr -> error file (used to detect failed handshake,
# e.g. Windows box with no afst / no matching ssh command -> nonzero exit fast).
#
# IMPORTANT: sets the PID via the global RS_PID, does NOT echo/return it.
# If this were called as `PID=$(start_remote_snapshot ...)`, the `&` job
# would be launched inside the command-substitution subshell and become
# orphaned the instant that subshell exits -- `wait "$PID"` in the main
# shell would then fail with "pid X is not a child of this shell".
start_remote_snapshot() {
	local host="$1" arg="$2" outfile="$3" errfile="$4"
	ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "afst --snapshot-only '$arg'" \
		> "$outfile" 2> "$errfile" &
	RS_PID=$!
}

# --- snapshot phase: local + remote (if any) run in parallel ---
printf "# Creating source snapshot...\n"
if [ -n "$REMOTE_SRC_HOST" ]; then
	printf "#   (SOURCE looks remote -> handshake: %s '%s')\n" "$REMOTE_SRC_HOST" "$REMOTE_SRC_ARG"
	start_remote_snapshot "$REMOTE_SRC_HOST" "$REMOTE_SRC_ARG" "$SNAP_SRC" "$ERR_SRC"
	SRC_PID=$RS_PID
else
	snapshot "$SRC" > "$SNAP_SRC" &
	SRC_PID=$!
fi

printf "# Creating destination snapshot...\n"
if [ -n "$REMOTE_DST_HOST" ]; then
	printf "#   (DEST looks remote -> handshake: %s '%s')\n" "$REMOTE_DST_HOST" "$REMOTE_DST_ARG"
	start_remote_snapshot "$REMOTE_DST_HOST" "$REMOTE_DST_ARG" "$SNAP_DST" "$ERR_DST"
	DST_PID=$RS_PID
else
	snapshot "$DST" > "$SNAP_DST" &
	DST_PID=$!
fi

# --- wait for both sides, independently ---
SRC_RC=0; DST_RC=0
wait "$SRC_PID" || SRC_RC=$?
wait "$DST_PID" || DST_RC=$?

# AFST handshake failed
# (bad ssh, no afst, unresolvable dir/share on the remote's own smb.conf, etc.) -> do it the old way via gvfs.
# This is also naturally handles a Windows remote: no afst, often no
# matching ssh command at all -> ssh exits nonzero fast -> fallback here.
if [ -n "$REMOTE_SRC_HOST" ] && [ "$SRC_RC" -ne 0 ]; then
	printf "# SOURCE handshake failed, falling back to local/gvfs snapshot...\n"
	[ -s "$ERR_SRC" ] && cat "$ERR_SRC" >&2
	snapshot "$SRC" > "$SNAP_SRC"
fi
if [ -n "$REMOTE_DST_HOST" ] && [ "$DST_RC" -ne 0 ]; then
	printf "# DEST handshake failed, falling back to local/gvfs snapshot...\n"
	[ -s "$ERR_DST" ] && cat "$ERR_DST" >&2
	snapshot "$DST" > "$SNAP_DST"
fi

printf "# Comparing snapshots...\n"
diff "$SNAP_SRC" "$SNAP_DST" > "$DIFF" || true

# --- dif analytics ---
# < means: exists in SRC, non or different in DST
grep '^<' "$DIFF" | sed 's/^< //' | cut -d $'\t' -f1 > "$FILES"
COUNT=$(wc -l < "$FILES" || true)

# --- copy (unchanged: always via local paths / gvfs mount, exactly as before) ---
printf "# Syncing, please wait...\n"

CURRENT=$COUNT
if [ -t 1 ]; then
# --- CLI hot path: inline live countdown ---
	while IFS= read -r relpath; do
		src_file="$SRC/$relpath"
		dst_file="$DST/$relpath"
		printf "\r\033[K# Files to sync: %s" "$CURRENT"
		mkdir -p "$(dirname "$dst_file")"
		cp -p "$src_file" "$dst_file"
		CURRENT=$((CURRENT - 1))
	done < "$FILES"
	printf "\n"
else
# --- zenity/pipe hot path: normal status lines ---
	while IFS= read -r relpath; do
		src_file="$SRC/$relpath"
		dst_file="$DST/$relpath"
		printf "# Files to sync: %s\n" "$CURRENT"
		mkdir -p "$(dirname "$dst_file")"
		cp -p "$src_file" "$dst_file"
		CURRENT=$((CURRENT - 1))
	done < "$FILES"
fi

printf "%s FILES DONE!!!\n\n" "$COUNT"
#comment exit command if you want cleanup
exit 0
printf "# Cleanup...\n"
rm "$SNAP_DST"
rm "$SNAP_SRC"
rm "$DIFF"
rm "$FILES"
printf "# Cleanup DONE!!!\n\n"
