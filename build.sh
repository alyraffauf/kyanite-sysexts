#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-rocm}"
KYANITE_IMAGE="${KYANITE_IMAGE:-ghcr.io/alyraffauf/kyanite:stable}"

cd "$(dirname -- "${BASH_SOURCE[0]}")"

EXT_DIR="mkosi.output/$NAME"
OUT_FILE="output/$NAME.raw"
BASE_DIR="mkosi.kyanite-base"

mkdir -p "$(dirname "$OUT_FILE")"

# Pull and extract kyanite-main as the subtraction base for mkosi's overlay.
if [ ! -d "$BASE_DIR" ]; then
    podman pull "$KYANITE_IMAGE"
    CONTAINER=$(podman create "$KYANITE_IMAGE")
    mkdir -p "$BASE_DIR"
    podman export "$CONTAINER" | tar -x -C "$BASE_DIR"
    podman rm "$CONTAINER"
fi

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
