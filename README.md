# kyanite-sysexts

System extensions for [kyanite](https://github.com/alyraffauf/kyanite) — opt-in payloads that overlay onto a running kyanite system without rebasing the bootc image.

Built with [mkosi](https://github.com/systemd/mkosi); merged at runtime via [`systemd-sysext`](https://www.freedesktop.org/software/systemd/man/systemd-sysext.html); auto-updated via [`systemd-sysupdate`](https://www.freedesktop.org/software/systemd/man/systemd-sysupdate.html).

## Available sysexts

| Sysext      | Provides                                                                  | Repo                       |
| ----------- | ------------------------------------------------------------------------- | -------------------------- |
| `docker`    | Docker CE + buildx, compose, model plugins                                | docker.com                 |
| `rocm`      | AMD ROCm runtime + HIP, OpenCL, rocm-smi (for GPU compute / ML workloads) | Fedora                     |
| `steam`     | Native Steam, Gamescope, MangoHud, GameMode (i686 multilib stack)         | rpmfusion-nonfree + Fedora |
| `syncthing` | Native Syncthing daemon                                                   | Fedora                     |
| `tailscale` | Tailscale mesh-VPN client + daemon                                        | pkgs.tailscale.com         |
| `virt`      | QEMU/KVM + libvirt + edk2-ovmf + virtio drivers                           | Fedora                     |

Each is published as a rolling release (e.g. `sysext-rocm`); the last 3 versions are retained for rollback.

## Install on kyanite

```bash
ujust install-sysext NAME    # downloads transfer config, fetches latest version, merges into /usr
ujust update-sysext NAME     # pulls newer version via systemd-sysupdate
ujust remove-sysext NAME     # unmerge + remove
```

Each sysext may need a one-time post-install step (enable a service, add yourself to a group). Listed in the kyanite README's [Optional Extensions](https://github.com/alyraffauf/kyanite#optional-extensions) section.

## How it works

For each sysext, mkosi:

1. Builds a curated **base** rootfs (Fedora + a fixed set of common packages — see [`base/mkosi.conf`](base/mkosi.conf)).
2. Layers the sysext's packages on top via overlay (`Overlay=yes`, `BaseTrees=../base/...`).
3. mkosi subtracts files that are byte-identical to base, leaving only the *delta*.
4. We apply the host SELinux policy contexts (`setfiles`) and pack the delta as a zstd squashfs.
5. CI publishes the resulting `.raw` to a GitHub release; `systemd-sysupdate` pulls and atomically swaps versions.

The base is intentionally curated rather than derived from kyanite's exact image: full-image extraction would exceed GHA disk limits. The trade-off is that sysext output is slightly larger than strictly necessary, but reproducible across hosts.

## Adding a new sysext

```
mkdir <name>/
$EDITOR <name>/mkosi.conf                                                        # Distribution, Packages, BaseTrees
$EDITOR <name>/mkosi.extra/usr/lib/extension-release.d/extension-release.<name>  # ID, VERSION_ID, etc.
$EDITOR sysupdate.d/<name>.transfer                                              # rolling-release URL pattern
```

Optional: for packages from third-party repos, add `<name>/mkosi.sandbox/etc/yum.repos.d/<repo>.repo` (mkosi auto-detects the sandbox tree and feeds it to dnf at build time).

Then add `<name>` to the `matrix.name` list in [`.github/workflows/build-sysexts.yml`](.github/workflows/build-sysexts.yml) and the `dorny/paths-filter` block. Push, and CI publishes a new `sysext-<name>` rolling release.

## Local builds

Requires [mkosi](https://github.com/systemd/mkosi) (in Fedora 44+ as `dnf install mkosi`) and `squashfs-tools`. Run:

```bash
bash build.sh <name>     # builds base if not cached, then builds the sysext, outputs to output/<name>.raw
```

Output is a squashfs `.raw` ready to drop into `/var/lib/extensions/` for testing. Note: SELinux relabeling needs `sudo`.

## Caveats

- **Fedora major version pinning**: each sysext's `extension-release` declares `VERSION_ID=44`. Bumping kyanite to fc45 means rebuilding every sysext against fc45 — not automated. Treat it as a coordinated change.
- **No `gschemas.compiled` / `mimeinfo.cache` / `icon-theme.cache`**: stripped from the sysext output to avoid shadowing host's much-larger versions. Sysexts that need new GSettings schemas to actually be queryable would need a different approach; none of ours rely on this.
- **Host file conflicts**: sysext-merge fails if the sysext ships specific files explicitly forbidden by systemd (`/usr/lib/os-release`, `/etc/os-release`, etc.). `build.sh` and our base set are tuned to avoid these.
- **Compiled cache regen**: most caches (udev, tmpfiles, font cache) regenerate on next boot. Our `ujust install-sysext` recipe forces `udevadm` reload immediately so things like controllers work without a reboot.

## License

Apache 2.0 (matching kyanite). Individual sysexts inherit their package licenses.
