#!/bin/bash
set -euo pipefail

unset -v latest
for file in "$P4CKP"/"$JNL_PREFIX".ckp.*.gz; do
    [ -e "$file" ] || continue
    [[ $file -nt ${latest-} ]] && latest=$file
done

if [ -n "${latest:-}" ]; then
    echo "Updating latest symlink to: $latest"
    ln -f -s "$latest" "$P4CKP/latest"
else
    echo "Error: Unable to find a checkpoint"
    exit 255
fi
