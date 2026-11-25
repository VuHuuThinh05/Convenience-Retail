#!/usr/bin/env bash
# Run Hive from the WSL home directory so its embedded Derby metastore is
# stable even when the project lives on /mnt/d.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[i]}" == '-f' && $((i + 1)) -lt ${#args[@]} ]]; then
        file="${args[i + 1]}"
        if [[ "$file" != /* ]]; then
            file="$project_root/$file"
        fi
        args[i + 1]="$file"
        ((i += 1))
    fi
done

cd "$HOME"
exec hive "${args[@]}"
