# Hardening SPIFFE/SPIRE for In-Vehicle SDV Security

**Oxidized Powertrain Hack Force (OPHF)** — Eclipse SDV Hackathon, Chapter 4

We are extending—not rebuilding—the SPIFFE/SPIRE integration introduced in Commercial SDV Blueprint PR #5. Our goal is to make the in-vehicle identity and authorization pattern more robust, testable, and practical for intermittently connected commercial vehicles.

## Presentation

[Slide Deck](./spire_hackathon_webdeck.html)

## Team at a glance

| Team member | Hackathon responsibility |
| --- | --- |
| Tim Viola | Coordinator and prioritisation |
| Naufal Shemshudeen | CDA plugin and Unix-socket updates |
| Justin Harper | SPIRE workload-attestation updates |
| Kenny Jarnagin | Security review and policy testing |
| Oliver Redgrove | Demo tests and hardware demo |

## Challenge alignment

Starting from PR #5, we will strengthen workload attestation, close an authorization-policy gap, make the CDA integration easier to find and use, and demonstrate both successful and rejected requests. The result is a clearer vehicle-ready security pattern, not a replacement for the existing integration.

## Hackathon architecture

The vehicle SPIRE Agent attests the Powertrain Mode Controller (PMC) and issues a short-lived JWT-SVID. The PMC presents that identity to the Classic Diagnostic Adapter (CDA), which validates it and evaluates Regorus policy before permitting a diagnostic operation.

For the local PMC-to-CDA hop, CDA will use HTTP over a protected Unix-domain socket rather than exposing a normal TCP port. JWT-SVID remains the application identity; Regorus remains the least-privilege policy gate.

## Objectives and issue tracking

| Objective | Issues | Assignee(s) |
| --- | --- | --- |
| Repository setup and judge-facing work plan | [#1](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/1) *(closed)*; [#2](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/2) | #1: Justin Harper; #2: Tim Viola |
| Make the SPIFFE/SPIRE CDA work visible and port it into the demo/OpenSOVD server path | [#3](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/3); [#11](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/11) | #3: Tim Viola; #11: unassigned |
| Fail-closed Regorus authorization and explicit default-deny behavior | [#4](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/4) | Kenny Jarnagin |
| Bind SPIFFE identity to the approved workload artifact using content-addressed attestation | [#6](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/6) | Justin Harper |
| Secure the local PMC-to-CDA connection with the CDA Unix socket while retaining JWT-SVID authorization | [#7](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/7) | Naufal Shemshudeen |
| Produce repeatable positive, negative, and connectivity-loss integration tests | [#8](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/8) | Oliver Redgrove |
| Harden access to the SPIRE Workload API socket | [#9](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/9) | Unassigned |
| Investigate secure behavior during backend loss and the path to trusted offline software updates | [#10](https://github.com/Eclipse-SDV-Hackathon-Chapter-Four/OPHF-commercial-sdv-stack/issues/10) | Unassigned |

## How we work

We use GitHub issues and pull requests for traceability, work in small owner-led changes, and require peer review before merge. Tests and documentation are part of the submission quality bar.

## Why this matters

OAuth remains useful for delegated access and external APIs. Inside the vehicle, SPIFFE/SPIRE addresses a different question: **which approved workload is actually running?** It can issue that workload a short-lived identity, while Regorus decides locally which diagnostic operations it may perform—even when enterprise connectivity is unavailable.

## Demo flow

1. The vehicle SPIRE Agent establishes trust with the backend SPIRE Server.
2. The approved PMC workload is attested and receives a JWT-SVID for `sovd.cda`.
3. PMC calls CDA through the protected Unix-domain socket with that JWT-SVID.
4. CDA validates the identity and Regorus allows only the permitted SOVD action.
5. Negative demos show that an unauthorized operation, invalid token, wrong audience, or modified workload is denied.

## Intended outcome

The hackathon contribution demonstrates a hardened in-vehicle trust chain:

`attested workload → SPIFFE identity → JWT-SVID → Regorus policy → permitted diagnostic action`

It also establishes a practical path to characterize offline operation and, longer term, to support trusted offline deployment of new vehicle software.
