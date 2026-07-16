# Task 03 implementer report

## Architecture and state machine

- `ModelLibrary` is an actor and is the sole owner of installation state. It publishes immutable `ModelLibrarySnapshot` values through `AsyncStream` and removes terminated observers.
- A pinned installation record is promoted with each model. Actor reconstruction reports `.ready` only after the record matches the current manifest and every required file passes fresh size and SHA-256 verification.
- Each model permits one mutation at a time. Concurrent install/import/delete requests fail deterministically with `operationInProgress` rather than racing shared staging or installed paths.
- Mutations end in `.ready`, `.notInstalled`, or `.cancelled`; unsupported/unverified devices are rejected before staging is allocated.
- Downloads and imports write only below same-volume `.staging/<model-id>`. Required files are streamed through SHA-256 and size verification before directory promotion. Existing verified staged files are reused.
- Managed roots and ancestors are checked with `lstat` plus canonical descendants before mutation. Delete preflights installed, staging, and managed trash; cleans staging first; atomically renames the installed tree into trash; and publishes `.notInstalled` only after the rename. Trash removal is best-effort and stale trash is recovered on relaunch. Injected ordinary I/O failures prove every thrown staging cleanup or installed rename retains installed bytes and truthful `.ready`; installed is never recursively deleted in place.
- `URLSessionModelFileTransport` streams response chunks directly to a managed partial. It continues only from a validated `206 Content-Range`; a server returning `200` to a Range request truncates and safely restarts the file. Its public API accepts no credentials, configuration strips credential/cookie/cache stores and sensitive headers, redirects remain HTTPS-only (except explicit loopback tests), and non-server-trust authentication challenges are rejected.
- Production iOS downloads are owned by one app-scoped `BackgroundModelDownloadCoordinator` and one stable background session. A platform-independent durable ledger persists a unique UUID/task description before task creation, then binds the URLSession task identifier. `didFinishDownloadingTo` synchronously moves bytes to deterministic managed storage, applies backup/file-protection policy, and writes an atomic claim sidecar before returning. `didComplete` and relaunch reconciliation adopt the claim without process memory, clean unknown/pre-persist orphans, and idempotently promote full or Range-tail bodies through verified atomic rename. `BonsaiAppDelegate` bridges `handleEventsForBackgroundURLSession`; foreground/macOS/test configurations preserve the streaming partial-file path.
- Background completion delivery now uses a locked per-transfer state machine that retains terminal results until a waiter consumes them, ignores duplicate callbacks, and rejects a duplicate waiter with a typed transport error. Restored-task reconciliation observes the URLSession task state and explicitly resumes a durably bound suspended task. Session creation is a locked one-time operation, mutable delegate state is isolated in locked owners, and reconciliation is serialized through an actor gate.
- Managed reconstruction opens required files and installation records with `O_NOFOLLOW`, validates the opened descriptor against `lstat` device/inode identity, and reads/hash-checks only through that descriptor. Corrupt ledgers now classify malformed JSON, duplicate transfer IDs, and unsupported states, quarantine the original bytes, and recover with a clean empty ledger.

## Files changed

- Added model transport protocol and streaming URLSession implementation.
- Added the conditional iOS shared background coordinator, app-delegate event bridge, durable transfer ledger, and platform-independent ledger lifecycle tests.
- Added managed claimed-body storage and an atomic, idempotent background body promoter.
- Added bounded-memory SHA-256 verifier.
- Added actor-owned model library, snapshots, installation records, terminal states, atomic staging/promotion, and deletion.
- Added metadata-first folder and ZIP importer using pinned ZIPFoundation.
- Added unit tests, real loopback integration fixture/test, and direct ZIPFoundation test dependency.
- Regenerated the Xcode project from `mobile/project.yml`.

## RED and GREEN evidence

- Inherited RED: `ModelLibraryTests.corruptShardNeverBecomesReady` failed because `ModelLibrary`, `ModelFileTransport`, and `SHA256Verifier` did not exist.
- First GREEN: the same focused test passed after atomic staging, transport, and streaming verification were implemented.
- Additional behavior tests were introduced for successful install, qualification refusal without allocation, verified-file reuse, size/hash failure, cancellation, replacement, idempotent isolated deletion, terminal snapshots, copy-only folder import, valid ZIP import, and hostile import classes.
- Focused Task 3 suite passed after each implementation/refactor cycle.
- Spec-review RED tests covered relaunch reconstruction, overlapping mutations, symlinked ancestors, hostile raw ZIP metadata, generic ZIP rejection, transport privacy policy, redirects/authentication, and cancellation before session storage.
- Delete atomicity RED proved the old implementation removed a valid installation before rejecting a late staging symlink. GREEN verifies the installed bytes, external target, and `.ready` snapshot all remain unchanged.
- Archive importer RED proved malformed/truncated/duplicate extra fields and a required-file descendant collision were accepted. GREEN runs raw hostile ZIP bytes through `ModelLibrary.importModel` for five special Unix modes, two hard-link IDs, three malformed metadata shapes, and both required-path prefix directions.
- Background lifecycle RED first failed on the absent durable ledger, then on absent relaunch destination lookup. GREEN proves pre-task persistence, unique identities, reload, known-task reattachment, unknown/duplicate cancellation, missing-task resumability, and deterministic failed transitions.
- Delete crash-consistency RED failed on the intentionally absent filesystem seam. GREEN fault-injects ordinary staging-removal and installed-rename I/O errors, verifies retained `.ready` bytes, and verifies best-effort trash recovery on relaunch.
- Archive host RED showed DOS and NTFS made-by bytes bypassing both hard-link IDs and malformed/truncated/duplicate extras. GREEN exhaustively checks all 256 host-byte values: extra-field structure and hard-link IDs always reject, while Unix mode interpretation remains limited to Unix 3 and macOS 19.
- Claimed-body RED failed on absent policy/claim APIs. GREEN proves deterministic claim paths, atomic persistence across simulated memory loss, recursive policy application, unknown/pre-persist orphan cleanup, already-promoted recovery, and duplicate callback idempotence. A second RED/GREEN cycle adds verified atomic promotion for both full bodies and Range tails.
- Quality-review RED proved the completion registry, restored-task state policy, typed duplicate-waiter error, and bind-to-resume restoration contract were absent. GREEN covers terminal-before-registration, 200 concurrent register/resolve races, duplicate callback/waiter idempotence, restored state decisions, and a durable bind -> relaunch -> suspended-task resume reconciliation.
- No-follow RED proved symlinked required files and installation records were followed during reconstruction. GREEN covers both leaf-symlink cases plus descriptor-based bounded SHA verification. Ledger-corruption RED proved recovery types were absent; GREEN covers malformed bytes, duplicate IDs, and unsupported states without trapping.
- Final full `BonsaiMobile` regression: `/tmp/task3-quality-fixes-final-unit.xcresult` `Passed`; 86 test cases / 619 reported executions, 0 failures, 0 skips.

## Real loopback Range evidence

- The Python fixture binds only to `127.0.0.1` and deliberately closes the first 1,500,000-byte response after 500,000 bytes.
- The first client operation failed as intended while retaining a 500,000-byte managed partial.
- The next request was observed as `Range: bytes=500000-`; the server returned a validated 206 response and final size/SHA-256 passed.
- A second 777-byte partial emitted `Range: bytes=777-`; the `/ignore` endpoint deliberately returned 200, proving the client truncated instead of concatenating. Final size/SHA-256 passed.
- During debugging, the initial post-resume verifier failure was isolated to cached `URL.resourceValues` metadata: request logs and `wc -c` both proved the file was complete. Switching verification to fresh `FileManager.attributesOfItem` fixed the exact rerun without changing transport behavior.
- Cancellation testing uses the throttled `/slow` endpoint: cancelling mid-transfer preserves the partial, a single Range resume completes and verifies it, and cancellation immediately after task creation completes in under one second without leaking a continuation.
- Final `RuntimeProbe` scheme (`/tmp/task3-quality-fixes-final-integration.xcresult`): 3 real loopback passes, 1 explicit no-model skip, 0 failures. Final unit and integration scans found no continuation-misuse or leaked-continuation markers; the only warning is Xcode's expected AppIntents metadata skip for a target without AppIntents.

## Import attack coverage

- Missing required files and unexpected files.
- Duplicate archive paths and required-path prefix collisions.
- POSIX absolute paths, Windows absolute-like paths, `..` traversal, empty components, and canonical descendant checks.
- Folder and archive symlinks, folder hard links, non-regular/special entries, and executable entries.
- Central extra fields are structurally parsed for every made-by host byte. Both hard-link metadata IDs plus malformed, truncated, and duplicate fields reject independent of host; Unix mode types reject only for Unix-like hosts. All raw fixtures pass through `ModelLibrary.importModel` before ZIPFoundation extraction. Only the explicit `.bonsaimodel.zip` package extension is accepted.
- Directory/file and canonical required-path prefix collisions are rejected in both directions, even when ZIPFoundation represents directory entries separately. A complete validation pass finishes before the first archive write.
- Declared-size limits, high compression-ratio rejection, size mismatch, and SHA-256 mismatch.
- Archives are never extracted wholesale.

## Final verification

- SwiftLint strict: 0 violations in 39 Swift files.
- XcodeGen determinism: two consecutive generations produced pbxproj SHA-1 `681ddc271f3a962a58051303842465ff4914ccab`.
- `git diff --check`, Python fixture bytecode compilation, and bootstrap shell syntax: passed.
- Static iOS-source assertions confirm there is no lazy session, no broad coordinator `@unchecked Sendable`, and no payload-less `ModelLibraryError.operationInProgress` call. Generic iOS build still cannot start because this Xcode installation does not have the iOS 26.5 platform component installed; Xcode marks `Any iOS Device` ineligible. The platform-independent lifecycle state machines pass the available macOS Swift 6 build/test lane.

## Commit and remaining risks

- Base implementation commit: `aa97ccf125a1d33d281ca7d8974f7ce87fa590d6`; prior hardening commits: `e6e09c79283cb17c8c215d0a0dfb1cbe26bca6a2` and `0ff20e3ff3ef974d700ebf32901740cfcdd2bdf9`. The final crash-consistency hardening commit SHA is returned to the orchestrator.
- Real multi-gigabyte Hub downloads and security-scoped Files/AirDrop access require later real-device evidence. This task proves the transport/storage boundary with real loopback I/O and exercises import content locally.
- The conditional iOS coordinator/app-delegate source, physical background relaunch, iPhone compilation, and device file-protection behavior remain unverified until the missing iOS platform is installed and Task 9 real-device testing is performed. macOS verifies the ledger state machine and unchanged streaming transport, not iOS runtime behavior.
