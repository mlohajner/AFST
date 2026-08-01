#!/usr/bin/env bash
set -euo pipefail

# --- config ---
WORKDIR="/tmp"
TS=$(date +%Y-%m-%dT%H-%M-%S)
SNAP_SRC="$WORKDIR/snapshot_src_${TS}.txt"
SNAP_DST="$WORKDIR/snapshot_dst_${TS}.txt"
DIFF="$WORKDIR/snapshot_${TS}.diff"
FILES="$WORKDIR/files_to_sync_${TS}.txt"

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

# --- snapshot ---
snapshot() {
	local dir="$1"
	(
		cd "$dir"
		find . -type f -printf '%P\t%T@\n' | sort
	)
}

printf "# Creating source snapshot...\n"
snapshot "$SRC" > "$SNAP_SRC"
printf "# Creating destination snapshot...\n"
snapshot "$DST" > "$SNAP_DST"
printf "# Comparing snapshots...\n"
diff "$SNAP_SRC" "$SNAP_DST" > "$DIFF" || true

# --- dif analytics ---
# < means: exists in SRC, non or different in DST
grep '^<' "$DIFF" | sed 's/^< //' | cut -d $'\t' -f1 > "$FILES"
COUNT=$(wc -l < "$FILES" || true)

# --- copy ---
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
