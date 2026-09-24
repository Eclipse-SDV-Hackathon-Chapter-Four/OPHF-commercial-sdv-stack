# Corporate TLS proxy (Cummins Prisma) workaround for container builds

The corporate network runs a TLS-intercepting proxy. It re-signs HTTPS
connections with `CN=Cummins-Prisma-subCA` / `CN=Cummins-Prisma-Root-CA`, which
container images do not trust. Builds therefore fail with:

```
error: download of config.json failed
Caused by: curl failed
Caused by: [60] SSL peer certificate ... self-signed certificate in certificate chain (19)
```

There is no "skip verification" switch for cargo, so the CA has to be installed
inside the build stage. This directory does that **without modifying a single
upstream Dockerfile**, by building CA-patched copies of the base images and
substituting them via BuildKit named contexts.

## Files

| File | Purpose |
| --- | --- |
| `export-corp-ca.ps1` | Probes the registries over TLS, extracts the Cummins CA certs from the presented chains, writes `corp-ca-bundle.crt`. |
| `corp-ca-bundle.crt` | The generated PEM bundle (2 certs: Prisma root + subCA). |
| `Dockerfile.ca-patch` | Wraps any base image: installs the CA into the system trust store, the Java keystore, and exports `CARGO_HTTP_CAINFO`, `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, etc. |
| `build-patched-bases.ps1` | Builds `corp-ca/<image>:<tag>` for every base image the stack uses. |
| `../commercial-sdv-stack/docker-compose.corp-ca.yaml` | Compose override wiring the patched bases into each service via `additional_contexts`. |

## Usage

```powershell
# 1. one-time (repeat whenever the proxy CA rotates)
./corp-ca/export-corp-ca.ps1
./corp-ca/build-patched-bases.ps1

# 2. build / run the stack
cd commercial-sdv-stack
docker compose -f docker-compose.yaml -f docker-compose.corp-ca.yaml build
docker compose -f docker-compose.yaml -f docker-compose.corp-ca.yaml up -d
```

To avoid typing both files every time:

```powershell
$env:COMPOSE_FILE = "docker-compose.yaml;docker-compose.corp-ca.yaml"
```

## How the substitution works

`Dockerfile`s such as `uservices/fms/Dockerfile` start with

```dockerfile
FROM ghcr.io/rust-cross/rust-musl-cross:x86_64-musl AS builder-amd64
```

The override declares a BuildKit named context with exactly that key:

```yaml
additional_contexts:
  ghcr.io/rust-cross/rust-musl-cross:x86_64-musl: docker-image://corp-ca/rust-musl-cross:x86_64-musl
```

BuildKit then resolves that `FROM` to the local patched image instead of pulling
from the registry. Upstream sources stay untouched, so rebasing / pulling
upstream changes is unaffected, and CI (which has no proxy) simply omits the
override file.

## Verify

```powershell
docker run --rm corp-ca/rust-musl-cross:x86_64-musl `
  sh -c "curl -sS -o /dev/null -w '%{http_code}\n' https://index.crates.io/config.json"
# -> 200
```

## Notes

* Only `crates.io` was observed to be intercepted; `github.com`, `pypi.org`,
  `services.gradle.org` and Maven Central presented genuine public chains.
  `export-corp-ca.ps1` re-checks all of them and only exports Cummins certs.
* The `corp-ca/*` images are local-only tags; they are never pushed.
* If you don't need to rebuild the images at all, `docker compose pull` +
  `docker compose up -d` sidesteps the issue entirely, since `ecu-updater`,
  `sovd-cda` etc. all have published `image:` tags.
