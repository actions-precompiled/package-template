# actions-precompiled package template

GitHub **template repository** for packaging upstream software as relocatable
Linux tarballs (amd64 + aarch64), with the same CI shape used by
[gettext-bin](https://github.com/actions-precompiled/gettext-bin),
[tesseract-bin](https://github.com/actions-precompiled/tesseract-bin), and
[quickshell-bin](https://github.com/actions-precompiled/quickshell-bin).

## What you get

| Piece | Role |
|-------|------|
| `package.toml` | Package name, upstream GitHub repo, image name, binary, version env |
| `create_releases` | uv script: plan versions, docker build, smoke, optional `gh release` |
| `Dockerfile` | Ubuntu 24.04 build image (edit apt deps) |
| `scripts/build_and_package.sh` | Clone/build/install/package inside the container |
| `.github/workflows/build.yml` | **One version per run** — arch matrix, artifacts, optional publish |
| `.github/workflows/dispatch-missing.yml` | Fan-out: one Build run per version (`recreate` → all upstream) |
| `mise.toml` | Pinned `uv` + `jq` for host |

## Quick start

1. **Use this template** on GitHub → new repo under `actions-precompiled` (or your org).
2. Edit **`package.toml`** (name, upstream, binary, …).
3. Edit **`Dockerfile`** apt packages and **`scripts/build_and_package.sh`** for the real build.
4. Enable Actions; keep **Immutable releases** off if you want `recreate`.
5. Push to `main` → Build runs for **latest** upstream (artifacts only).
6. **Dispatch Missing Builds** with `publish=true` to ship; use `recreate=true` to rebuild **all** tags.

## Local

```bash
mise install
# after package.toml points at a real upstream:
./create_releases --list-to-build          # missing only
./create_releases --list-to-build --all    # every upstream tag
./create_releases --dry-run v1.2.3
LOCAL: ./create_releases v1.2.3            # needs Docker
```

Environment (optional): `TARGETS`, `PUBLISH`, `SKIP_SMOKE`, `SKIP_IMAGE_BUILD`,
`RECREATE` / `FORCE_ALL`, `IMAGE_NAME`, `BUILD_OUTPUT_DIR`.

## CI

| Workflow | Trigger | Publishes? |
|----------|---------|------------|
| `build.yml` | push/PR → latest; dispatch → one version | only if `publish=true` |
| `dispatch-missing.yml` | manual | optional per Build |

Empty versions + `recreate=false` → missing only.  
Empty versions + **`recreate=true`** → **all** upstream tags; each Build can delete+recreate its release.

## Checklist for a new package

- [ ] `package.toml` filled in  
- [ ] `Dockerfile` has compile deps  
- [ ] `scripts/build_and_package.sh` produces `bin/<binary>` and a tarball named  
      `{name}-{version}-{linux-amd64|linux-aarch64}.tar.gz`  
- [ ] Smoke works (`--help` / `--version` or adjust `create_releases` smoke)  
- [ ] Repo settings: Actions enabled; Immutable releases off if using recreate  

## Layout of a tarball

```text
{name}-{version}-linux-amd64.tar.gz
└── {name}/
    ├── bin/{binary}
    ├── lib/          # optional bundled deps
    └── BUILDINFO.txt
```

## Related

- Pattern origin: actions-precompiled/*-bin repos  
- Older generic cross-compiler image: [buildenv](https://github.com/actions-precompiled/buildenv) (archived; packages may use their own Dockerfile)
