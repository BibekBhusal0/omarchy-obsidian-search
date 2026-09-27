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

p="${vault%/}"
rest="$rel"
while true; do
  seg="${rest%%/*}"
  p="$p/$seg"
  [[ ! -L "$p" ]] || exit 1
  [[ "$rest" == */* ]] || break
  rest="${rest#*/}"
done

vault_canon="$(/usr/bin/realpath -m -- "$vault")" || exit 1
[[ -n "$vault_canon" && "$vault_canon" == /* ]] || exit 1
dest_canon="$(/usr/bin/realpath -m -- "$vault_canon/$rel")" || exit 1
[[ "$dest_canon" == "$vault_canon"/* ]] || exit 1

parent="${dest_canon%/*}"
[[ "$parent" == "$vault_canon" || "$parent" == "$vault_canon"/* ]] || exit 1

exec /usr/bin/python3 - "$vault_canon" "$rel" <<'EOF'
import os
import stat
import sys

vault, rel = sys.argv[1], sys.argv[2]
segs = rel.split("/")
try:
    dfd = os.open(vault, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
except OSError:
    sys.exit(1)
try:
    for seg in segs[:-1]:
        try:
            os.mkdir(seg, 0o777, dir_fd=dfd)
        except FileExistsError:
            pass
        try:
            nfd = os.open(seg, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, 0o777, dir_fd=dfd)
        except OSError:
            sys.exit(1)
        os.close(dfd)
        dfd = nfd
    base = segs[-1]
    try:
        fd = os.open(base, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o666, dir_fd=dfd)
        os.close(fd)
    except FileExistsError:
        try:
            fd = os.open(base, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dfd)
        except OSError:
            sys.exit(1)
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                sys.exit(1)
        finally:
            os.close(fd)
    sys.stdout.write(vault + "/" + "/".join(segs) + "\n")
finally:
    os.close(dfd)
EOF
