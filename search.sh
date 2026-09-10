#!/usr/bin/env bash
# Omarchy obsidian-search plugin: list searchable vault entries.
# The first lines carry headers (prefixed with #), then one tab-delimited
# row per entry: Name \t Type \t Path \t URI.
# Filtering happens client-side (FuzzySearch.js), so every entry is emitted.
#
# Headers:
#   #vault \t <vault name>
#   #vaultpath \t <absolute vault path>
#   #daily (no arguments; only emitted when the daily-notes or periodic-notes
#     plugin manages daily notes — the client opens it via obsidian://daily)
#
# The URI is the only script-generated field. It is URL-encoded, so it never
# contains literal tabs or newlines, and the client launches it with
# Util.execArgv (no shell). Display fields are stripped of tabs so a
# filename can never shift columns into the URI field.
#
# Usage: search.sh [VAULT_PATH] [--show-daily 0|1] [--show-templates 0|1]
#   --vault PATH  same as the positional VAULT_PATH argument
# The vault path may be given as an argument; otherwise it is auto-detected
# from the first vault in the Obsidian configuration. Daily notes and
# templates are resolved from the vault's own plugin settings
# (.obsidian/daily-notes.json, periodic-notes data, .obsidian/templates.json)
# instead of matching the words "daily"/"template" in file paths.

home="$HOME"
vault_config="$home/.config/obsidian/obsidian.json"

vault_path=""
show_daily=1
show_templates=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --vault=*)
    vault_path="${1#--vault=}"
    shift
    ;;
  --vault)
    vault_path="${2:-}"
    shift 2
    ;;
  --show-daily=* | --show-daily-notes=*)
    show_daily="${1#*=}"
    shift
    ;;
  --show-daily | --show-daily-notes)
    show_daily="${2:-1}"
    shift 2
    ;;
  --show-templates=*)
    show_templates="${1#*=}"
    shift
    ;;
  --show-templates)
    show_templates="${2:-1}"
    shift 2
    ;;
  --*)
    shift
    ;;
  *)
    if [[ -z "$vault_path" ]]; then
      vault_path="$1"
    fi
    shift
    ;;
  esac
done

[[ "$show_daily" == "1" || "$show_daily" == "true" ]] && show_daily=1 || show_daily=0
[[ "$show_templates" == "1" || "$show_templates" == "true" ]] && show_templates=1 || show_templates=0

vault_path="${vault_path/#\~/$home}"
if [[ -z "$vault_path" ]]; then
  [[ -f "$vault_config" ]] || exit 0
  vault_path="$(jq -r '.vaults | to_entries | .[0].value.path' "$vault_config" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  vault_path="${vault_path/#\~/$home}"
fi
[[ -n "$vault_path" && -d "$vault_path" ]] || exit 0

vault_name="$(basename "$vault_path")"
encoded_vault="$(printf '%s' "$vault_name" | jq -sRr @uri)"

printf '#vault\t%s\n' "$vault_name"
printf '#vaultpath\t%s\n' "$vault_path"

obsidian_dir="$vault_path/.obsidian"

is_truthy() {
  case "${1,,}" in
  1 | true | yes) return 0 ;;
  *) return 1 ;;
  esac
}

daily_dir=""
daily_enabled=0

periodic_data="$obsidian_dir/plugins/periodic-notes/data.json"
if [[ -f "$periodic_data" ]]; then
  p_enabled="$(jq -r '.daily.enabled // true' "$periodic_data" 2>/dev/null)"
  p_folder="$(jq -r '.daily.folder // empty' "$periodic_data" 2>/dev/null)"
  p_format="$(jq -r '.daily.format // empty' "$periodic_data" 2>/dev/null)"
  if is_truthy "$p_enabled" && [[ -n "$p_folder" || -n "$p_format" ]]; then
    daily_enabled=1
    daily_dir="$p_folder"
  fi
fi

if [[ "$daily_enabled" -eq 0 ]]; then
  core_enabled="true"
  if [[ -f "$obsidian_dir/core-plugins.json" ]]; then
    core_enabled="$(jq -r '."daily-notes" // true' "$obsidian_dir/core-plugins.json" 2>/dev/null || echo true)"
  fi
  if is_truthy "$core_enabled"; then
    daily_enabled=1
    if [[ -f "$obsidian_dir/daily-notes.json" ]]; then
      c_folder="$(jq -r '.folder // empty' "$obsidian_dir/daily-notes.json" 2>/dev/null)"
      [[ -n "$c_folder" ]] && daily_dir="$c_folder"
    fi
  else
    daily_enabled=0
  fi
fi

daily_dir="${daily_dir#/}"
daily_dir="${daily_dir%/}"

templates_dir=""
if [[ -f "$obsidian_dir/templates.json" ]]; then
  templates_dir="$(jq -r '.folder // empty' "$obsidian_dir/templates.json" 2>/dev/null)"
fi
templates_dir="${templates_dir#/}"
templates_dir="${templates_dir%/}"

daily_template=""
if [[ -f "$obsidian_dir/daily-notes.json" ]]; then
  daily_template="$(jq -r '.template // empty' "$obsidian_dir/daily-notes.json" 2>/dev/null)"
fi
daily_template="${daily_template#/}"
daily_template="${daily_template%/}"

if [[ "$daily_enabled" -eq 1 ]]; then
  printf '#daily\n'
fi

# Single-pass listing: fd streams NUL-separated paths into one python3 process
# that classifies and percent-encodes every row. The previous per-file
# `jq -sRr @uri` spawn cost ~0.6s on a few hundred notes.
export OBS_ENCODED_VAULT="$encoded_vault" OBS_DAILY_DIR="$daily_dir" OBS_TEMPLATES_DIR="$templates_dir" OBS_DAILY_TEMPLATE="$daily_template" OBS_SHOW_DAILY="$show_daily" OBS_SHOW_TEMPLATES="$show_templates"
fd -0 -e md -e canvas -e base --type file --strip-cwd-prefix --base-directory="$vault_path" | python3 -c '
import os, sys, urllib.parse
evault = os.environ["OBS_ENCODED_VAULT"].encode()
daily = os.environ["OBS_DAILY_DIR"].encode()
tpl = os.environ["OBS_TEMPLATES_DIR"].encode()
daily_tpl = os.environ["OBS_DAILY_TEMPLATE"].encode()
show_daily = os.environ["OBS_SHOW_DAILY"] == "1"
show_tpl = os.environ["OBS_SHOW_TEMPLATES"] == "1"
def under(path, d):
    return bool(d) and path.startswith(d + b"/")
rows = []
for raw in sys.stdin.buffer.read().split(b"\0"):
    if not raw or b"\n" in raw or b"\r" in raw:
        continue
    in_daily = under(raw, daily)
    in_tpl = under(raw, tpl) or (bool(daily_tpl) and raw.startswith(daily_tpl))
    if (in_daily and not show_daily) or (in_tpl and not show_tpl):
        continue
    if raw.endswith(b".canvas"):
        sub, name = b"Canvas", raw[:-7]
    elif raw.endswith(b".base"):
        sub, name = b"Base", raw[:-5]
    else:
        name = raw[:-3] if raw.endswith(b".md") else raw
        sub = b"Daily Note" if in_daily else (b"Template" if in_tpl else b"Note")
    uri = b"obsidian://open?vault=" + evault + b"&file=" + urllib.parse.quote_from_bytes(raw, safe=b"").encode()
    disp = raw.replace(b"\t", b" ")
    rows.append(b"\t".join([name.replace(b"\t", b" "), sub, disp, uri]))
sys.stdout.buffer.write(b"\n".join(rows) + (b"\n" if rows else b""))
'
