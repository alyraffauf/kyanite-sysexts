#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-rocm}"

cd "$(dirname -- "${BASH_SOURCE[0]}")"

EXT_DIR="mkosi.output/$NAME"
OUT_FILE="output/$NAME.raw"

mkdir -p "$(dirname "$OUT_FILE")"

# mkosi v26 builds every sub-image in mkosi.images/ on each invocation and
# has no working --image filter. Stash the others so only base + $NAME run.
STASH=$(mktemp -d)
for d in mkosi.images/*/; do
    n=$(basename "$d")
    if [[ "$n" != "base" && "$n" != "$NAME" ]]; then
        mv "$d" "$STASH/"
    fi
done
trap 'mv "$STASH"/* mkosi.images/ 2>/dev/null; rmdir "$STASH" 2>/dev/null' EXIT

mkosi --force build

# Without SELinux relabel here, missing security.selinux xattrs silently
# break screen-unlock / sudo / polkit (SSH-side PAM is unaffected).
sudo setfiles -F -r "$EXT_DIR" \
    /etc/selinux/targeted/contexts/files/file_contexts "$EXT_DIR"

rm -f "$OUT_FILE"
sudo mksquashfs "$EXT_DIR" "$OUT_FILE" \
    -all-root -xattrs -comp zstd -Xcompression-level 19 -noappend
sudo chown "$(id -u):$(id -g)" "$OUT_FILE"

echo "Built: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
