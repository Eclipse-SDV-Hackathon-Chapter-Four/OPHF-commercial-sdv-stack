# Eclipse SDV Hackathon - preparation workspace

Working environment for the Eclipse SDV hackathon. It collects the upstream
projects together with the local configuration needed to build and run them on
a corporate Windows machine.

## Layout

| Path | Contents |
| --- | --- |
| `commercial-sdv-stack/` | Eclipse SDV commercial SDV stack blueprint |
| `corp-ca/` | Corporate TLS proxy workaround for container builds |

## Getting started

Prerequisites: Docker Desktop (with BuildKit, the default) and PowerShell.
All commands below are PowerShell, run from the workspace root
(`E:\2026\eclipsehackathon\prep`) unless stated otherwise.

### 1. Trust the corporate proxy CA

Required once per machine, and again whenever the proxy CA is rotated. Without
this every container build fails while downloading dependencies.

```powershell
./corp-ca/export-corp-ca.ps1        # writes corp-ca/corp-ca-bundle.crt
./corp-ca/build-patched-bases.ps1   # builds the corp-ca/* base images
```

`export-corp-ca.ps1` must be run on the corporate network or VPN - it reads the
CA straight off the live TLS connections. It exits with a warning if it finds
nothing.

Check the patched images exist:

```powershell
docker images "corp-ca/*"
```

### 2. Configure local ports

```powershell
cd commercial-sdv-stack
Copy-Item .env.example .env
```

`.env` is gitignored, so edit it freely. The defaults work as-is; see
[Windows notes](#windows-notes) if a port fails to bind.

### 3. Build and start the stack

Both compose files are needed: the second one injects the CA-patched base
images.

```powershell
docker compose -f docker-compose.yaml -f docker-compose.corp-ca.yaml build
docker compose -f docker-compose.yaml -f docker-compose.corp-ca.yaml up -d
```

To avoid repeating the file list, set this once per shell instead:

```powershell
$env:COMPOSE_FILE = "docker-compose.yaml;docker-compose.corp-ca.yaml"
docker compose build
docker compose up -d
```

The first build compiles several Rust services from source and takes a while.
Later builds are cached.

> If you do not need to modify any service, you can skip steps 1 and 3 entirely
> and just `docker compose pull; docker compose up -d` - every service has a
> published image. The proxy only breaks *building*, not pulling.

### 4. Verify it is running

```powershell
docker compose ps
```

Expect 12 containers `running`, with `ecu-sim` and `mosquitto` reporting
`healthy`. Then check the services actually did something:

```powershell
docker compose logs --tail 5 sovd-cda                    # "CDA fully initialized and ready to serve requests"
docker compose logs --tail 5 powertrain-mode-controller  # "Successfully set powertrain mode to: ..."
docker compose logs --tail 5 fms                         # vehicle data arriving over MQTT
```

Web endpoints on the host:

| URL | Service |
| --- | --- |
| <http://localhost:8080> | Dozzle - logs for all containers |
| <http://localhost:3000> | Symphony portal |
| <http://localhost:8082/v1alpha2/> | Symphony API |
| <http://localhost:20002/vehicle/v15/> | SOVD classic diagnostic adapter |
| <http://localhost:8181> | ECU simulator control |
| `localhost:25555` | Kuksa Databroker (gRPC, remapped from 55555) |

### 5. Optional - trigger the ECU update demo

Needs a bash shell with `curl` and `jq` (Git Bash or WSL):

```bash
./scripts/trigger_ecu_update.sh
```

Registers a Symphony target, waits for you to press Enter, then removes it.
Watch `docker compose logs -f ecu-updater` to see it handled.

### 6. Shut down

```powershell
docker compose down          # stop containers, keep volumes
docker compose down -v       # also discard mosquitto data
```

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

The commands are in [Getting started](#getting-started) above; see
[corp-ca/README.md](corp-ca/README.md) for how the substitution works and how to
verify it.

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
