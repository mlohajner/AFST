#!/usr/bin/env bash
set -euo pipefail

# --- config ---
WORKDIR="/tmp"
SNAP_SRC="$WORKDIR/snapshot_src.txt"
SNAP_DST="$WORKDIR/snapshot_dst.txt"
DIFF="$WORKDIR/snapshot.diff"
FILES="$WORKDIR/files_to_sync.txt"

# --- checks ---
if [ $# -ne 2 ] || [ "$1" == "" ] || [ "$2" == "" ]; then
	printf " \ AFST \  Analytic File Sync Tool V1\n"
	printf "            😃 by Mario Lohajner 2025\n"
	printf "\n"
    printf "Usage: $0 SOURCE_DIR DEST_DIR\n\n"
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

printf "Creating source snapshot...\n"
snapshot "$SRC" > "$SNAP_SRC"
printf "Creating destination snapshot...\n"
snapshot "$DST" > "$SNAP_DST"
echo "Comparing snapshots...\n"
diff "$SNAP_SRC" "$SNAP_DST" > "$DIFF" || true

# --- dif analytics ---
# < means: exists in SRC, non or different in DST
grep '^<' "$DIFF" | sed 's/^< //' | cut -d $'\t' -f1 > "$FILES"
COUNT=$(wc -l < "$FILES" || true)

printf "Files to sync: $COUNT!\n"

# --- copy ---
printf "Syncing, please wait...\n"

while IFS= read -r relpath; do
	src_file="$SRC/$relpath"
	dst_file="$DST/$relpath"
#	preview
#	echo "$src_file -> $dst_file"
	mkdir -p "$(dirname "$dst_file")"
	cp -p "$src_file" "$dst_file"
done < "$FILES"

printf "$COUNT FILES DONE!!!\n\n"
#comment if you want cleanup
exit 0
printf "Cleanup...\n"
rm $SNAP_DST
rm $SNAP_SRC
rm $DIFF
rm $FILES
printf "Cleanup DONE!!!\n\n"
