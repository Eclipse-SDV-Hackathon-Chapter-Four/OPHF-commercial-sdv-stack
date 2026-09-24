# Eclipse SDV Hackathon - preparation workspace

Working environment for the Eclipse SDV hackathon. It collects the upstream
projects together with the local configuration needed to build and run them on
a corporate Windows machine.

## Layout

| Path | Contents |
| --- | --- |
| `commercial-sdv-stack/` | Eclipse SDV commercial SDV stack blueprint |
| `corp-ca/` | Corporate TLS proxy workaround for container builds |

## corp-ca

The corporate network runs a TLS-intercepting proxy that re-signs HTTPS with an
internal CA. Container images do not trust it, so `docker compose build` fails
while fetching the crates.io index:

```
error: download of config.json failed
Caused by: curl failed
Caused by: [60] SSL peer certificate ... self-signed certificate in certificate chain (19)
```

`cargo` has no "skip verification" switch, so the CA has to be installed inside
the build stage. `corp-ca/` does that by building CA-patched copies of the base
images and substituting them through BuildKit named contexts, so **no upstream
Dockerfile is modified**.

```powershell
# one-time, and again whenever the proxy CA rotates
./corp-ca/export-corp-ca.ps1
./corp-ca/build-patched-bases.ps1

# then build/run the stack with the override
cd commercial-sdv-stack
docker compose -f docker-compose.yaml -f docker-compose.corp-ca.yaml build
docker compose -f docker-compose.yaml -f docker-compose.corp-ca.yaml up -d
```

See [corp-ca/README.md](corp-ca/README.md) for details.

## Windows notes

Two further issues are specific to running the stack on a Windows host. Both are
fixed inside `commercial-sdv-stack`, but they are worth knowing about:

* **Reserved host ports.** The Databroker's default port 55555 falls inside a
  WinNAT/Hyper-V excluded port range, producing `bind: An attempt was made to
  access a socket in a way forbidden by its access permissions`. It is remapped
  via `DATABROKER_PORT` in `.env`. List the reserved ranges with
  `netsh int ipv4 show excludedportrange protocol=tcp`; the exclusions move
  after a reboot.
* **Line endings.** With `core.autocrlf=true`, shell scripts are checked out as
  CRLF and Linux containers then fail with `/bin/bash: - : invalid option`.
  A `.gitattributes` pins them to LF.

## Security note

`corp-ca/corp-ca-bundle.crt` holds the public CA certificates presented by the
corporate proxy. It contains no private keys, but it does expose internal PKI
subject names. Keep this repository private and do not push it to a public
remote.
