#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-rocm}"

cd "$(dirname -- "${BASH_SOURCE[0]}")"

EXT_DIR="$NAME/mkosi.output/$NAME"
OUT_FILE="output/$NAME.raw"

mkdir -p "$(dirname "$OUT_FILE")"

# Build the shared base (subtraction target for the overlay).
[ -d base/mkosi.output/base ] || (cd base && mkosi --force build)

# Build the requested sysext.
(cd "$NAME" && mkosi --force build)

# Drop the systemd-container runtime payload when a dependency pulls it in.
# It belongs to the host OS. An older extension must never shadow host helpers
# such as systemd-pull or systemd-import-generator without matching libraries.
sudo rm -f \
    "$EXT_DIR"/usr/bin/{importctl,machinectl,mount.ddi,portablectl,systemd-dissect,systemd-nspawn,systemd-vmspawn} \
    "$EXT_DIR"/usr/lib64/libnss_mymachines.so.2 \
    "$EXT_DIR"/usr/lib/systemd/{import-pubring.pgp,systemd-export,systemd-import,systemd-import-fs,systemd-importd,systemd-machined,systemd-mountfsd,systemd-mountwork,systemd-nsresourced,systemd-nsresourcework,systemd-pull} \
    "$EXT_DIR"/usr/lib/systemd/system-generators/systemd-import-generator \
    "$EXT_DIR"/usr/lib/tmpfiles.d/systemd-nspawn.conf

sudo rm -f \
    "$EXT_DIR"/usr/lib/systemd/{system,user}/{dbus-org.freedesktop.import1.service,dbus-org.freedesktop.machine1.service,machine.slice,machines.target,systemd-importd.service,systemd-importd.socket,systemd-machined.service,systemd-machined.socket,systemd-nspawn@.service,systemd-vmspawn@.service} \
    "$EXT_DIR"/usr/lib/systemd/system/{systemd-mountfsd.service,systemd-mountfsd.socket,systemd-nsresourced.service,systemd-nsresourced.socket,var-lib-machines.mount}

sudo rm -f \
    "$EXT_DIR"/usr/lib/systemd/system/{machines.target.wants/var-lib-machines.mount,remote-fs.target.wants/var-lib-machines.mount,sockets.target.wants/systemd-importd.socket,sockets.target.wants/systemd-machined.socket} \
    "$EXT_DIR"/usr/lib/systemd/user/{sockets.target.wants/systemd-importd.socket,sockets.target.wants/systemd-machined.socket}

# Drop compiled caches that would shadow host versions on overlay merge.
# Each cache covers all schemas/mime types/icons available system-wide; the
# sysext only sees a subset, so its cache is a strict regression for anything
# the host already had compiled.
sudo rm -f \
    "$EXT_DIR/usr/share/glib-2.0/schemas/gschemas.compiled" \
    "$EXT_DIR/usr/share/applications/mimeinfo.cache" \
    "$EXT_DIR"/usr/share/icons/*/icon-theme.cache \
    "$EXT_DIR/usr/lib64/gtk-3.0"/*/immodules.cache \
    "$EXT_DIR/usr/lib64/gtk-4.0"/*/immodules.cache

# Without SELinux relabel here, missing security.selinux xattrs silently
# break screen-unlock / sudo / polkit (SSH-side PAM is unaffected).
sudo setfiles -F -r "$EXT_DIR" \
    /etc/selinux/targeted/contexts/files/file_contexts "$EXT_DIR"

rm -f "$OUT_FILE"
sudo mksquashfs "$EXT_DIR" "$OUT_FILE" \
    -all-root -xattrs -comp zstd -Xcompression-level 19 -noappend
sudo chown "$(id -u):$(id -g)" "$OUT_FILE"

echo "Built: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
