# Agent Instructions for kyanite-sysexts

System extensions for [kyanite](https://github.com/alyraffauf/kyanite). Each sysext is its own self-contained mkosi project; CI builds them in a matrix and publishes to per-sysext rolling releases.

## REPO LAYOUT

```
kyanite-sysexts/
├── build.sh                          # builds base on demand, then $NAME, then squashfs
├── base/                             # shared subtraction base
│   └── mkosi.conf                    # @core + common runtime libs
├── <name>/                           # one directory per sysext
│   ├── mkosi.conf                    # Distribution=fedora; BaseTrees=../base/...; Overlay=yes
│   ├── mkosi.extra/usr/lib/extension-release.d/extension-release.<name>
│   └── mkosi.sandbox/                # OPTIONAL: extra repo files (e.g. rpmfusion, docker.com, tailscale.com)
│       └── etc/yum.repos.d/*.repo
├── sysupdate.d/<name>.transfer       # systemd-sysupdate URL contract for the rolling release
└── .github/workflows/build-sysexts.yml
```

## CRITICAL RULES

1. Each sysext's `mkosi.conf` must be **self-contained**: declare `[Distribution]`, `[Output]`, `[Content]`, `[Build]` sections fully. There is no top-level mkosi.conf to inherit from (intentional — keeps each sysext isolatable).
2. `BaseTrees=../base/mkosi.output/base` — uniform path; relies on `OutputDirectory=mkosi.output` being set.
3. `Format=directory` everywhere; final squashfs packing happens in `build.sh`, not mkosi.
4. `extension-release.<name>` filename and the `ImageId=<name>` setting must match — systemd-sysext refuses to merge if they don't.
5. **Never ship `/usr/lib/os-release`, `/etc/os-release`, or compiled caches** (`gschemas.compiled`, `mimeinfo.cache`, etc.). `build.sh` strips these post-build to prevent overlay-shadowing host-fuller versions.

## ADDING A NEW SYSEXT

```bash
mkdir <name>
cp -r virt/{mkosi.conf,mkosi.extra} <name>/   # easiest template, edit Packages
$EDITOR <name>/mkosi.conf                      # rename ImageId; replace Packages
mv <name>/mkosi.extra/usr/lib/extension-release.d/extension-release.virt \
   <name>/mkosi.extra/usr/lib/extension-release.d/extension-release.<name>
cp sysupdate.d/virt.transfer sysupdate.d/<name>.transfer
$EDITOR sysupdate.d/<name>.transfer             # update Path / MatchPattern / CurrentSymlink
```

Then update **two places** in `.github/workflows/build-sysexts.yml`:
1. The `dorny/paths-filter` `filters:` block — add the new sysext's path filter.
2. The `ALL` env var in the `select` job's `matrix` step — append the new name.

For third-party repos, add `<name>/mkosi.sandbox/etc/yum.repos.d/<repo>.repo` with `gpgcheck=0` (build-time only; the package binaries themselves are still RPM-signed).

Local validation before pushing: `bash build.sh <name>` — must produce `output/<name>.raw` cleanly.

## SELECTIVE BUILD LOGIC

The `select` job in `build-sysexts.yml` decides which sysexts to (re)build per push:

- **schedule / workflow_dispatch**: build all (drift mitigation is the whole point of the cron).
- **push**: build only sysexts whose own files (`<name>/**` or `sysupdate.d/<name>.transfer`) changed.
- **push touching shared infra** (`build.sh`, `base/**`, the workflow itself): build all.

Triggered by `dorny/paths-filter@v3`; the matrix is computed dynamically via `fromJson()`.

## RELEASE CONVENTIONS

- One rolling release tag per sysext: `sysext-<name>`.
- Each push produces `<name>-<run_number>-<arch>.raw` plus a `SHA256SUMS` and `<name>.transfer`.
- Last 3 raw versions retained; older assets pruned by the workflow's final job.
- `<name>.transfer` is overwritten each build with the same content (it's the URL contract for `systemd-sysupdate`).

## TROUBLESHOOTING

- **`No match for argument: <pkg>`** during build: package isn't in the default Fedora repos. Add a `mkosi.sandbox/etc/yum.repos.d/<repo>.repo` entry.
- **Overlay-on-overlay errors in CI**: `volumes: - /tmp:/var/tmp` bind-mount in the workflow puts mkosi's workspace on the runner's ext4 (not the container's overlayfs). Already in place.
- **"Failed to read metadata for image NAME: No medium found"** on user merge: the `extension-release.<name>` file's `ID` / `VERSION_ID` mismatches the host. Or systemd-sysext's image-policy is rejecting unsigned squashfs (use `--image-policy=root=unprotected+encrypted+absent`).
- **glib aborts after merge / file picker can't see drives**: mkosi-built sysext is shipping a compiled cache or other host-shadowing file. `build.sh` should already strip the major offenders; check `unsquashfs -ll output/<name>.raw` for new patterns.

## REFERENCES

- [systemd-sysext(8)](https://www.freedesktop.org/software/systemd/man/systemd-sysext.html)
- [systemd-sysupdate(8)](https://www.freedesktop.org/software/systemd/man/systemd-sysupdate.html)
- [mkosi documentation](https://github.com/systemd/mkosi/blob/main/mkosi/resources/man/mkosi.1.md)
- [kyanite repo](https://github.com/alyraffauf/kyanite)
