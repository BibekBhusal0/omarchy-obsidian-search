#!/usr/bin/env bash
# Omarchy obsidian-search plugin: list searchable vault entries.
# The first line carries the vault name (prefixed with #vault\t), then one
# tab-delimited row per entry: Name \t Path \t Action.
# Filtering happens client-side (FuzzySearch.js), so every entry is emitted.
#
# Usage: search.sh [VAULT_PATH]
# The vault path may be given as an argument; otherwise it is auto-detected
# from the first vault in the Obsidian configuration.

home="$HOME"
vault_config="$home/.config/obsidian/obsidian.json"

vault_path="${1:-}"
if [[ -z "$vault_path" ]]; then
  [[ -f "$vault_config" ]] || exit 0
  vault_path="$(jq -r '.vaults | to_entries | .[0].value.path' "$vault_config" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
[[ -n "$vault_path" && -d "$vault_path" ]] || exit 0

vault_name="$(basename "$vault_path")"
encoded_vault="$(printf '%s' "$vault_name" | jq -sRr @uri)"

printf '#vault\t%s\n' "$vault_name"

url_encode() {
  printf '%s' "$1" | jq -sRr @uri
}

fd_cmd=(fd -e md -e canvas -e base --type file --strip-cwd-prefix --base-directory="$vault_path")
while IFS= read -r relative_path; do
  path_lower="${relative_path,,}"
  [[ "$path_lower" != *daily* && "$path_lower" != *template* ]] || continue

  encoded_file="$(url_encode "$relative_path")"
  uri="obsidian://open?vault=$encoded_vault&file=$encoded_file"

  subtext="Note"
  case "$relative_path" in
    *.canvas) subtext="Canvas" ;;
    *.base) subtext="Base" ;;
  esac

  clean_name="${relative_path%.md}"
  clean_name="${clean_name%.canvas}"
  clean_name="${clean_name%.base}"

  printf '%s\t%s\t%s\t%s\n' \
    "$clean_name" \
    "$subtext" \
    "$relative_path" \
    "obsidian \"$uri\""
done < <("${fd_cmd[@]}")
