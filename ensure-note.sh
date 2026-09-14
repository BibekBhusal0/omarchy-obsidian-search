#!/usr/bin/env bash
# Create an empty note inside the vault only after proving containment.
# Usage: ensure-note.sh <vault-dir> <relative-path>
set -euo pipefail

vault="${1:?vault required}"
rel="${2:?relative path required}"

[[ "$vault" == /* ]] || exit 1
[[ -d "$vault" ]] || exit 1
[[ -n "$rel" && "${#rel}" -le 220 ]] || exit 1
[[ "$rel" != /* && "$rel" != *$'\n'* && "$rel" != *$'\r'* && "$rel" != *$'\t'* ]] || exit 1

rest="$rel"
while true; do
  seg="${rest%%/*}"
  [[ -n "$seg" && "$seg" != "." && "$seg" != ".." && "${#seg}" -le 100 ]] || exit 1
  [[ "$rest" == */* ]] || break
  rest="${rest#*/}"
done

vault_canon="$(/usr/bin/realpath -m -- "$vault")" || exit 1
[[ -n "$vault_canon" && "$vault_canon" == /* ]] || exit 1
dest_canon="$(/usr/bin/realpath -m -- "$vault_canon/$rel")" || exit 1
[[ "$dest_canon" == "$vault_canon"/* ]] || exit 1

parent="${dest_canon%/*}"
/usr/bin/mkdir -p -- "$parent" || exit 1
[[ -e "$dest_canon" ]] || /usr/bin/touch -- "$dest_canon" || exit 1
printf '%s\n' "$dest_canon"
