#!/usr/bin/env bash
set -euo pipefail

NAME="${1:?usage: $0 <docker|syncthing|tailscale>}"
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${ROOT_DIR}/lts/base"
EXT_DIR="${ROOT_DIR}/lts/${NAME}/mkosi.output/${NAME}"
OUT_FILE="${ROOT_DIR}/output/${NAME}-lts.raw"
POLICY_FILE="${BASE_DIR}/mkosi.output/base/etc/selinux/targeted/contexts/files/file_contexts"

as_root() {
    if [[ ${EUID} -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

[[ -d "${ROOT_DIR}/lts/${NAME}" ]] || {
    printf 'Unknown LTS sysext: %s\n' "${NAME}" >&2
    exit 2
}

mkdir -p "$(dirname -- "${OUT_FILE}")"
# mkosi's sandbox expects the bootc home mountpoint to exist in the builder.
mkdir -p /var/home

# Build the CentOS base used for subtraction and SELinux file contexts.
if [[ ! -d "${BASE_DIR}/mkosi.output/base" ]]; then
    (cd "${BASE_DIR}" && mkosi --force build)
fi

(cd "${ROOT_DIR}/lts/${NAME}" && mkosi --force build)

# Do not let a partial extension shadow host-wide generated caches.
as_root rm -f \
    "${EXT_DIR}/usr/share/glib-2.0/schemas/gschemas.compiled" \
    "${EXT_DIR}/usr/share/applications/mimeinfo.cache" \
    "${EXT_DIR}"/usr/share/icons/*/icon-theme.cache \
    "${EXT_DIR}"/usr/lib64/gtk-3.0/*/immodules.cache \
    "${EXT_DIR}"/usr/lib64/gtk-4.0/*/immodules.cache

[[ -f "${POLICY_FILE}" ]] || {
    printf 'CentOS SELinux file contexts not found: %s\n' "${POLICY_FILE}" >&2
    exit 1
}

# Label the extension with the same CentOS policy used to build its base.
as_root setfiles -F -r "${EXT_DIR}" "${POLICY_FILE}" "${EXT_DIR}"

rm -f "${OUT_FILE}"
as_root mksquashfs "${EXT_DIR}" "${OUT_FILE}" \
    -all-root -xattrs -comp zstd -Xcompression-level 19 -noappend
as_root chown "$(id -u):$(id -g)" "${OUT_FILE}"

printf 'Built: %s (%s)\n' "${OUT_FILE}" "$(du -h "${OUT_FILE}" | cut -f1)"
