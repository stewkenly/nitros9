#!/bin/bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
export NITROS9DIR="$PWD"

if git grep -n -E '^(<<<<<<< |>>>>>>> |=======$)' -- ':!archive'; then
    echo "FAIL: unresolved merge conflict markers found"
    exit 1
fi

while IFS= read -r makefile; do
    recipe_dir="$(dirname "$makefile")"
    make -C "$recipe_dir" --no-print-directory -n clean >/dev/null
done < <(find recipes -mindepth 2 -maxdepth 3 -name makefile -print | sort)

echo "PASS: NitrOS-9 source/recipe sanity"
