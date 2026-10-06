# Hackathon Plan Final

## Project Title

**Hardening SPIFFE/SPIRE for Realistic In-Vehicle SDV Security**

### One-line summary

Extend the existing Eclipse SDV SPIFFE/SPIRE integration into a more production-relevant vehicle trust architecture by:

- fixing potential regorous policy loophole [Kenny]
- stronger workload attestation [Justin]
- negative/security integration tests [Oliver]
- secure local CDA communication (implement latest CDA unix socket communication) [Naufal],
- resilient offline behavior [Stretch Goal]
- and a path toward trusted offline software updates [Stretch Goal]

---

# 1. Starting Point

We are building from the existing Eclipse SDV Commercial Stack work in:

**PR #5 - Add SPIFFE-based authentication for service components**

The current PR already provides:

- SPIRE Server
- backend SPIRE Agent
- vehicle SPIRE Agent
- SPIFFE workload registration
- JWT-SVID authentication
- FMS authentication to Powertrain Mode Controller
- Powertrain Mode Controller authentication to OpenSOVD CDA
- Rego / Regorus authorization
- workload identity separation across service hops

The intent of the hackathon is **not to rebuild SPIFFE support**, but to harden and extend the existing integration.

---

# 2. Core Problem Statement

The existing integration proves that SPIFFE can authenticate SDV services.

The hackathon asks the next questions:

```text
Can we trust the identity platform itself?
            ↓
Can we prove which software workload is running?
            ↓
Can we prove who made an application request?
            ↓
Can we restrict exactly what that workload may do?
            ↓
Can this continue when the vehicle is disconnected?
            ↓
Can new software still be securely introduced while offline?
```

This is especially relevant to commercial vehicles, off-highway equipment, mining vehicles, remote fleets, and other systems that may remain disconnected from enterprise infrastructure for long periods.

---

# 3. Final Architecture Direction

## Identity and authorization model

Use **JWT-SVIDs for end-to-end application identity** where services do not have a direct TLS connection.

Examples:

```text
FMS
 │
 │ JWT-SVID
 │ aud = powertrain.mode-control
 ▼
MQTT / uProtocol
 ▼
Powertrain Mode Controller
```

and:

```text
Powertrain Mode Controller
 │
 │ JWT-SVID
 │ aud = sovd.cda
 ▼
OpenSOVD CDA
```

JWT-SVIDs remain useful because the identity travels with the application request even when a broker or other middleware sits between workloads.

---

## CDA transport security

Do **not** make HTTPS / mTLS support in CDA a core hackathon requirement.

OpenSOVD now supports serving the CDA HTTP API over a **Unix-domain socket**.

Use this for the local PMC -> CDA connection:

```text
Powertrain Mode Controller
        │
        │ HTTP over protected Unix-domain socket
        │
        │ Authorization: Bearer <JWT-SVID>
        ▼
OpenSOVD CDA
```

Benefits:

- CDA is no longer exposed on a TCP port
- access is local to the vehicle compute environment
- filesystem/socket permissions form the transport boundary
- JWT-SVID still provides application-level identity
- Rego policy still provides least-privilege authorization

This separates:

```text
Transport security
    -> Unix-domain socket

Application identity
    -> JWT-SVID

Authorization
    -> Regorus / Rego
```

---

# 4. Workstream 1 - Fixing potential regorous policy loophole
## Owner

**Kenny**

## Problem

The current Powertrain Mode Controller authorization logic appears to deny only when the Rego result is explicitly:

```text
false
```

An undefined, malformed, or unexpected authorization result may therefore risk falling through as allowed.

## Goal

Make authorization **fail closed**.

Expected behavior:

```text
result == true
    -> allow

anything else
    -> deny
```

The Rego policy should also explicitly define:

```rego
default allow := false
```

## Deliverables

- fix authorization handling
- explicit default-deny policy
- tests for:
  - known authorized identity
  - known unauthorized identity
  - unknown identity
  - undefined policy result
  - malformed authorization input

## Why it matters

This is a direct hardening of an existing Eclipse PR and is one of the clearest Mode A contributions.

---

# 5. Workstream 2 - Security and Negative Integration Tests

## Owner

**Oliver**

## Goal

Add reproducible integration tests proving that:

- valid attested workloads succeed
- unauthorized workloads fail
- invalid credentials fail
- offline behavior is deterministic and secure

## Core test matrix

```text
registered workload
+ valid JWT
+ allowed operation
    -> PASS

registered workload
+ valid JWT
+ forbidden operation
    -> DENY

unknown SPIFFE ID
    -> DENY

wrong JWT audience
    -> DENY

expired JWT
    -> DENY

modified image
    -> cannot obtain expected SPIFFE identity

backend SPIRE unavailable
+ cached valid credential
    -> behavior verified

backend SPIRE unavailable
+ expired credential
    -> fail securely
```

## Additional offline tests

Characterize:

- how long existing JWT-SVIDs remain usable
- what happens after JWT expiry
- behavior after service restart
- behavior after vehicle/stack restart
- behavior when backend connectivity returns

## Deliverables

- automated integration-test scripts
- expected results documented
- repeatable demo sequence
- pass/fail output suitable for presentation

---

# 6. Workstream 3 - Stronger Workload Attestation

## Owner

**Justin**

## Problem

The existing PR uses mutable and relatively weak selectors such as:

```text
docker:image_id:<image>:latest
docker:env:UP_LOCAL_ADDRESS=...
```

A mutable `:latest` tag is not a strong workload identity.

## Goal

Bind SPIFFE identity to the actual approved software artifact.

## Primary implementation

Prefer content-addressed selectors such as:

```text
docker:image_config_digest:sha256:...
```

Potentially combine with:

```text
docker:label:...
```

to preserve a stable semantic workload identity.

Example:

```text
SPIFFE ID:
spiffe://sdv.eclipse.org/vehicle/powertrain-mode-controller

Selectors:
docker:label:workload=powertrain-mode-controller
docker:image_config_digest=sha256:ABC123...
```

## Demo

```text
Approved PMC image
    -> attestation succeeds
    -> receives expected SPIFFE ID

Rebuilt / modified image
    -> digest changes
    -> attestation fails
    -> expected SPIFFE ID is not issued
```

## Stretch goal - Signed software identity

Explore image-signature verification so that identity can be based on:

```text
approved workload
+
approved signer
```

instead of relying only on a hard-coded digest.

Potential future model:

```text
PMC v1 -> signed by approved OEM signer -> trusted
PMC v2 -> signed by approved OEM signer -> trusted
malicious image -> unsigned / wrong signer -> rejected
```

This is especially relevant to offline software update.

---

# 7. Workstream 4 - Secure PMC -> CDA Communication

## Owner

**Naufal**

## Revised direction

The original plan was:

```text
Add CDA workload identity
+
switch JWT-SVID to X.509-SVID
+
add mTLS
```

This is no longer the preferred hackathon direction.

## Why

### FMS -> PMC

FMS and PMC communicate through an MQTT broker.

```text
FMS -> Broker <- PMC
```

mTLS would authenticate:

```text
FMS <-> Broker
PMC <-> Broker
```

but would not provide direct end-to-end FMS -> PMC identity.

JWT-SVID remains the better application-level identity mechanism.

### PMC -> CDA

The CDA does not currently provide HTTPS/mTLS as part of the baseline integration.

Adding complete TLS lifecycle support would require:

- TLS server implementation
- X.509-SVID retrieval
- certificate rotation
- trust-bundle refresh
- client SPIFFE-ID validation
- configuration
- tests
- private-key handling

That is too large for the core hackathon scope.

## Final task

Use the newly available OpenSOVD Unix-domain-socket support for the CDA.

Change:

```text
PMC
 │
 │ HTTP/TCP
 ▼
sovd-cda:20002
```

to:

```text
PMC
 │
 │ HTTP over Unix-domain socket
 ▼
/run/opensovd/cda.sock
 │
 ▼
CDA
```

Continue sending:

```text
Authorization: Bearer <JWT-SVID>
```

## Deliverables

- move CDA off its network TCP port for local communication
- expose CDA through a protected Unix socket
- update PMC HTTP client to use the Unix socket
- retain existing JWT-SVID validation and authorization
- document when mTLS would be appropriate instead

## Future mTLS use case

mTLS becomes much more appropriate when PMC and CDA are on:

- different compute nodes
- different ECUs
- different operating systems
- or otherwise separated by a real network

---

# 8. SPIRE Agent Socket Hardening

The SPIRE Workload API Unix socket is itself part of the trusted platform boundary.

The current blueprint mounts the Agent socket directory read/write into workloads.

Preferred model:

```text
SPIRE Agent
    │
    │ read/write
    ▼
Workload API socket directory
    │
    ├── read-only mount -> PMC
    ├── read-only mount -> CDA
    └── read-only mount -> other workloads
```

Goals:

- application workloads cannot replace/manipulate the Agent socket path
- only the SPIRE Agent manages the Workload API endpoint
- workloads run unprivileged
- Docker/runtime control sockets are not exposed to normal workloads

This strengthens the assumption that workloads are communicating with the genuine local SPIRE Agent.

---

# 9. Offline Behavior - Final Position

Nested SPIRE is **not automatically required** just to survive temporary backend outages.

A normal vehicle SPIRE Agent can cache credentials and continue serving them while valid.

However:

```text
Vehicle Agent
    !=
signing authority
```

The Agent cannot mint arbitrary new SVIDs by itself.

This means two distinct offline requirements must be separated.

---

## Requirement A - Existing workload continues running offline

Example:

```text
PMC already registered
PMC already has / has previously requested its JWT-SVID
backend disappears
```

This can often be handled using:

- Agent caching
- appropriately configured credential lifetimes
- fail-secure behavior after expiry

For this case, nested SPIRE may be unnecessary.

---

## Requirement B - New software must be installed and trusted offline

This is different.

Example:

```text
PMC v1
digest = SHA256:A
```

Vehicle goes offline for weeks.

A technician arrives with:

```text
PMC v2
digest = SHA256:B
```

Strong workload attestation should reject v2 unless the identity system is updated to recognize the new approved artifact.

With only a vehicle Agent:

```text
Agent sees SHA256:B
    ↓
no matching registration
    ↓
cannot independently authorize new workload identity
```

The Agent cannot create a new registration entry or mint a fresh SVID independently.

This is the stronger justification for a vehicle-local SPIRE Server.

---

# 10. Vehicle-Local / Nested SPIRE - Revised Role

Nested SPIRE becomes a **conditional but strategically important** part of the design.

It is justified if the requirement is:

> The vehicle shall support trusted offline deployment of new software workloads and issuance of fresh, short-lived workload identities while disconnected from enterprise identity infrastructure.

Architecture:

```text
                ENTERPRISE

          Root / Backend SPIRE
                 Server
                   │
          delegated authority
                   │
                   X
            connectivity lost

---------------- VEHICLE ----------------

          Vehicle SPIRE Server
          delegated intermediate
                  authority
                     │
             Vehicle SPIRE Agent
                     │
          ┌──────────┴───────────┐
          ▼                      ▼
         PMC                    CDA
```

## What this enables

While the vehicle-local authority remains valid:

- new workloads can be registered
- new workloads can be attested
- fresh JWT-SVIDs can be issued
- fresh X.509-SVIDs can be issued
- short workload credential lifetimes can be retained
- services can restart while offline
- new software can start for the first time while offline

---

# 11. Important Nested-SPIRE Tradeoff

Nested SPIRE does not eliminate the long-lived credential problem.

It changes what is long-lived.

Without nested SPIRE:

```text
longer-lived workload credentials
```

may be required to tolerate long outages.

With nested SPIRE:

```text
longer-lived vehicle-local signing authority
        ↓
short-lived workload identities
```

The vehicle-local SPIRE Server therefore holds a more powerful credential.

For a production architecture this signing key should ideally be protected by:

- TPM
- HSM
- secure element
- or another hardware-backed key manager

rather than a normal filesystem key.

The local authority also has a finite validity period.

Eventually the vehicle must:

- reconnect to the enterprise authority,
- receive a securely authorized renewal,
- or otherwise re-establish delegated trust.

---

# 12. Trusted Offline Software Update

This is the strongest commercial-vehicle use case for vehicle-local identity infrastructure.

Example use cases:

- mining trucks
- remote construction equipment
- remote commercial fleets
- off-highway vehicles
- engines operating for weeks without network connectivity

## Proposed trust flow

```text
              OEM RELEASE SYSTEM

       OEM software signing authority
                  │
                signs
                  ▼
         Offline update package
                  │
          USB / service tool
                  ▼

----------------- VEHICLE -----------------

          Trusted Update Manager
                  │
          verifies OEM signature
                  │
                  ▼
            installs software
                  │
                  ▼
       updates workload authorization
                  │
                  ▼
        Vehicle SPIRE Server
                  │
                  ▼
           SPIRE Agent
                  │
        attests actual workload
                  │
                  ▼
        newly installed software
                  │
          receives fresh SVID
```

---

# 13. Software-Update Trust vs. Runtime Identity

SPIRE should **not** decide whether an offline software package is legitimate.

Separate:

```text
SOFTWARE SUPPLY-CHAIN TRUST
```

from:

```text
RUNTIME WORKLOAD IDENTITY
```

## Software-update system answers

> Was this software authorized by the OEM to be installed?

## SPIRE answers

> Is the process requesting this identity actually the approved installed workload?

These should form a chain, not replace each other.

---

# 14. Signed Offline Identity Manifest

A useful future extension is to package identity metadata together with the software update.

Example:

```text
update-package/
├── powertrain-mode-controller-v2.tar
├── identity-manifest.json
├── authorization.rego
└── signature
```

Example manifest:

```json
{
  "workload": "powertrain-mode-controller",
  "spiffe_id": "spiffe://sdv.eclipse.org/vehicle/powertrain-mode-controller",
  "image_digest": "sha256:ABC123...",
  "version": "2.1.0"
}
```

The trusted update manager would:

```text
verify package signature
        ↓
install image
        ↓
update SPIRE registration
        ↓
update authorization policy
        ↓
start workload
        ↓
SPIRE Agent attests exact image
        ↓
Vehicle SPIRE Server issues SVID
```

This provides a clean path to offline deployment of new trusted software.

---

# 15. Hackathon Scope - Must Have

The hackathon should prioritize finished, reviewable work.

## Priority 1 - Authorization hardening

- fail closed
- explicit default deny
- negative tests

## Priority 2 - Strong workload attestation

- image digest selectors
- demonstrate modified image rejection

## Priority 3 - Integration test framework

- positive authentication
- negative authorization
- wrong identity
- wrong audience
- expired credential
- modified workload
- backend disconnect

## Priority 4 - Secure CDA local transport

- update to OpenSOVD Unix-socket-capable CDA
- PMC communicates with CDA over Unix-domain socket
- preserve JWT-SVID authorization

## Priority 5 - Workload API socket hardening

- restrict application access to SPIRE Agent socket
- remove unnecessary write access

---

# 16. Hackathon Scope - Investigate / Demonstrate

## Offline behavior characterization

Measure and document:

```text
backend online
    ↓
JWT issued
    ↓
backend disconnected
    ↓
credential remains valid
    ↓
credential expires
    ↓
authentication fails securely
    ↓
backend restored
    ↓
fresh credential issued
```

Determine whether an Agent-only architecture is sufficient for ordinary connectivity outages.

---

# 17. Stretch Goals

## Stretch A - Signed container images

Use verified image signatures / approved signer identity rather than only digest matching.

## Stretch B - Vehicle-local SPIRE Server

Implement nested/local SPIRE if core tasks are complete.

Primary demo justification:

> Newly installed workload can obtain a fresh identity while the vehicle is disconnected from the backend.

## Stretch C - Offline signed identity manifest

Prototype an update package that contains:

- software artifact
- digest
- SPIFFE identity assignment
- authorization policy
- OEM signature

## Stretch D - X.509-SVID / mTLS

Do not target co-located PMC -> CDA for this.

Reserve for a networked multi-node architecture:

```text
Compute Node A
PMC
 │
 │ SPIFFE X.509-SVID + mTLS
 ▼
Compute Node B
CDA
```

---

# 18. Demo Sequence

A strong demo should tell a security story rather than only show successful traffic.

## Demo 1 - Valid workload

```text
Approved PMC image
      ↓
SPIRE attests workload
      ↓
PMC obtains SPIFFE identity
      ↓
JWT-SVID created
      ↓
CDA validates JWT
      ↓
Rego authorizes operation
      ↓
SOVD request succeeds
```

---

## Demo 2 - Unauthorized operation

```text
Valid workload identity
      ↓
request forbidden diagnostic action
      ↓
Rego evaluates false
      ↓
request denied
```

Example denied actions could include:

- unrelated ECU access
- ClearDTC
- programming
- calibration
- sensitive diagnostic operation

---

## Demo 3 - Modified workload

```text
Approved digest = SHA256:A

modified image = SHA256:B
      ↓
selector mismatch
      ↓
expected SPIFFE identity not issued
      ↓
authenticated SOVD access impossible
```

---

## Demo 4 - Backend disconnect

```text
Backend SPIRE connected
      ↓
credential issued

disconnect backend
      ↓
cached credential remains usable

credential expires
      ↓
authentication fails securely

restore backend
      ↓
fresh identity available
```

---

## Demo 5 - CDA network isolation

Show:

```text
Before:
PMC -> http://sovd-cda:20002

After:
PMC -> /run/opensovd/cda.sock
```

CDA is no longer reachable through a normal application TCP endpoint.

---

## Demo 6 - Optional offline update

If nested SPIRE is implemented:

```text
vehicle disconnected
      ↓
install signed PMC v2
      ↓
update local approved workload registration
      ↓
start PMC v2
      ↓
Agent attests new image
      ↓
local SPIRE Server issues fresh identity
      ↓
PMC v2 successfully accesses permitted CDA function
```

This would be the strongest commercial-vehicle-specific demo.

---

# 19. Team Split

| Owner | Primary Task |
|---|---|
| **Kenny** | Fail-closed authorization and policy hardening |
| **Oliver** | Integration tests and offline-behavior characterization |
| **Justin** | Strong workload attestation and signed-image stretch |
| **Naufal** | Secure PMC -> CDA Unix-domain-socket integration |
| **Shared** | Vehicle-local SPIRE investigation / offline update architecture |

---

# 20. Repository / Documentation Deliverables

Suggested structure:

```text
docs/
    security-architecture.md
    workload-attestation.md
    offline-behavior.md
    offline-update-trust-model.md

scripts/
    register-workloads.sh
    run-security-tests.sh
    disconnect-backend.sh
    restore-backend.sh

tests/
    valid-identity/
    unauthorized-operation/
    wrong-audience/
    expired-token/
    modified-image/
    backend-disconnected/

config/
    spire/
    policy/
```

README should provide a simple reproduction path.

---

# 21. Presentation Story

## Slide 1 - Starting point

> Eclipse already demonstrated SPIFFE authentication in the Commercial SDV Stack.

Show PR #5 architecture.

---

## Slide 2 - What is missing for a real vehicle?

```text
Mutable workload identity
Potential fail-open authorization
Network-exposed CDA
Limited negative testing
Backend-connectivity assumptions
Offline software-update problem
```

---

## Slide 3 - What we changed

```text
Fail-closed authorization
        +
content-addressed workload identity
        +
negative security tests
        +
local-only CDA transport
        +
offline-behavior validation
```

Optional:

```text
+
vehicle-local identity authority
```

---

## Slide 4 - Trust chain

```text
Trusted vehicle platform
        ↓
SPIRE Agent
        ↓
Attested software workload
        ↓
SPIFFE identity
        ↓
JWT-SVID
        ↓
Rego authorization
        ↓
Permitted SOVD operation
```

---

## Slide 5 - Commercial vehicle differentiator

```text
Remote vehicle
      ↓
weeks without connectivity
      ↓
offline software update
      ↓
new software installed
      ↓
software signature verified
      ↓
runtime workload attested
      ↓
fresh workload identity issued
```

Message:

> **The vehicle becomes a bounded autonomous trust domain rather than requiring continuous enterprise connectivity.**

---

# 22. Key Architecture Conclusions

## 1. JWT-SVID is not inferior to X.509-SVID

JWT-SVID is well suited for end-to-end application identity over middleware such as MQTT.

## 2. mTLS should not be forced into every connection

mTLS authenticates transport endpoints.

It does not automatically provide end-to-end identity across brokers.

## 3. Unix-domain sockets are a strong local transport boundary

For co-located PMC and CDA, local-only HTTP over a protected Unix socket is preferable to unnecessarily exposing CDA on TCP.

## 4. SPIRE Agent caching solves temporary outages

Nested SPIRE is not automatically necessary for short outages.

## 5. Offline software update changes the requirement

If entirely new software must:

- be installed,
- start for the first time,
- be attested,
- and receive a fresh short-lived identity

while the backend is unreachable, then a vehicle-local signing authority becomes much more valuable.

## 6. Vehicle-local authority is a security tradeoff

It improves autonomy but introduces a powerful local signing key that must be protected and periodically renewed.

## 7. Update authorization and runtime identity must remain separate

The update system authorizes software installation.

SPIRE verifies the runtime workload and issues identity.

---

# 23. Final Project Positioning

> **We are taking the existing SPIFFE/SPIRE integration in the Eclipse SDV Commercial Stack and hardening it into a realistic vehicle trust architecture.**

The project demonstrates:

- fail-closed authorization,
- exact software workload attestation,
- end-to-end workload identity,
- least-privilege diagnostic authorization,
- local-only OpenSOVD access,
- deterministic behavior during connectivity loss,
- and a path toward secure offline deployment of new software.

The strongest long-term commercial-vehicle vision is:

> **A vehicle should be able to verify an authorized offline software update, attest the newly installed workload, issue it a short-lived runtime identity, and enforce least-privilege access even when disconnected from enterprise infrastructure.**
