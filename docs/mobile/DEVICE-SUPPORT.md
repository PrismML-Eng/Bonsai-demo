# Bonsai Mobile device support

Support is evidence-gated per exact hardware identifier, model revision, runtime revision, and capability. A memory or storage estimate never promotes a device. The bundled support manifest currently contains no evidence references, so all otherwise eligible combinations remain unverified and model allocation stays blocked.

## Current release matrix

| Device | Raw hardware identifier | 1-bit Bonsai-27B | Ternary Bonsai-27B | Evidence |
|---|---|---|---|---|
| iPhone 16e | `iPhone17,5` | Unverified: physical release lane not completed | Unsupported: Ternary is prohibited on iPhone | None |
| Other iPhone | Exact identifier required | Unverified | Unsupported: Ternary is prohibited on iPhone | None |
| iPad | Exact identifier required | Unverified | Unverified; requires at least 16 GiB and a real pass | None |
| Mac | Exact hardware model required | Unverified | Unverified; Ternary requires at least 16 GiB and a real pass | None |

There are intentionally no supported rows. Earlier developer integration runs are useful engineering diagnostics, but they are not immutable Release-configuration physical-device artifacts with offline network inspection, clean-source provenance, and all required measurements.

## What a supported row requires

Every supported capability must resolve through `mobile/Resources/Evidence/support-manifest.json` to an immutable JSON artifact under `docs/mobile/evidence/`. The reviewed source artifact and its bundled mirror under `mobile/Resources/Evidence/` must be byte-identical. `mobile/scripts/sync_evidence_resources.py --write` creates the deterministic mirror, and the same command without `--write` is the freshness gate. Its SHA-256, raw hardware identifier, OS/app/model/runtime revisions, exact passing scenario, and capability must match. The artifact must prove text and the requested feature completed, cancellation completed within its deadline, three load/generate/unload cycles completed, no pressure termination occurred, airplane-mode operation passed, external online inspection observed zero outbound app connections, and the source/network-boundary audit found no inference or tool network path.

Missing, corrupt, stale, simulator, dirty-build, skipped, or infrastructure-failed evidence remains unverified. A deterministic measured incompatibility may be recorded as unsupported, but it is never converted into a supported capability.

Release archives use `mobile/scripts/build_mobile.sh`. It derives the exact Git commit and embeds it
as `BonsaiSourceCommit`; the Release pre-build gate rejects a missing or malformed
`BONSAI_SOURCE_COMMIT`. Evidence uses the same setting, and references match the decoded artifact's
OS build, app build, app commit, runtime, model revision, and raw hardware identity exactly.

## Evidence harness

The harness uses Release tests and never edits the support manifest automatically. A physical iOS model must already be installed in the app/test container; a host `BONSAI_MODEL_DIR` is not visible on an iPhone.

```bash
mobile/scripts/run_device_evidence.sh --help

mobile/scripts/run_device_evidence.sh \
  --device-id '<connected-device-UDID>' \
  --model oneBit27B \
  --model-revision '<40-hex-manifest-revision>' \
  --scenarios text,thinking,cancel,calculator,date,device,notes,vision-fast,vision-full,offline,load-unload \
  --network-capture '/path/to/network-inspection.json' \
  --source-audit '/path/to/revision-linked-source-audit.json'
```

The network inspection is a closed JSON attestation containing `schemaVersion`, observed airplane
mode, observed outbound-request count, `external_packet_capture`, and the immutable raw-capture
digest. The source audit is a closed JSON attestation bound to the exact source commit and its raw
audit digest. The runner validates both, embeds their observed facts and attestation-file digests,
then compares those digests again after extracting the XCTest attachment.

The harness generates the JSON attachment from measurements inside the just-run XCTest result bundle; it never accepts caller-authored evidence. `--dry-run` only inspects the quoted lane and is not evidence. Never commit UDIDs, local model paths, prompts, answers, note contents, attachment paths, or tokens.

## Remaining gates

- Connect, unlock, and sign for the iPhone 16e physical lane.
- Capture every metric from structured instrumentation instead of console text.
- Complete airplane-mode operation, external online capture, and source audit.
- Run Ternary on a qualified high-memory Mac or iPad.
- Pass unit, integration, UI/accessibility, generic iOS Release, and physical-device gates.
- Review each immutable artifact before adding its digest to the bundled manifest.
