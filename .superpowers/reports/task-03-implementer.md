# Task 03 implementer report

## Architecture and state machine

- `ModelLibrary` is an actor and is the sole owner of installation state. It publishes immutable `ModelLibrarySnapshot` values through `AsyncStream` and removes terminated observers.
- A pinned installation record is promoted with each model. Actor reconstruction reports `.ready` only after the record matches the current manifest and every required file passes fresh size and SHA-256 verification.
- Each model permits one mutation at a time. Concurrent install/import/delete requests fail deterministically with `operationInProgress` rather than racing shared staging or installed paths.
- Mutations end in `.ready`, `.notInstalled`, or `.cancelled`; unsupported/unverified devices are rejected before staging is allocated.
- Downloads and imports write only below same-volume `.staging/<model-id>`. Required files are streamed through SHA-256 and size verification before directory promotion. Existing verified staged files are reused.
- Managed roots and ancestors are checked with `lstat` plus canonical descendants before mutation. Roots are recursively excluded from backup and receive iOS complete-until-first-authentication protection. Delete is model-scoped, idempotent, and refuses symlinked managed boundaries.
- `URLSessionModelFileTransport` streams response chunks directly to a managed partial. It continues only from a validated `206 Content-Range`; a server returning `200` to a Range request truncates and safely restarts the file. Its public API accepts no credentials, configuration strips credential/cookie/cache stores and sensitive headers, redirects remain HTTPS-only (except explicit loopback tests), and non-server-trust authentication challenges are rejected.
- Production iOS downloads use a stable background-session identifier and download tasks; foreground/test configurations preserve the streaming partial-file path. Session invalidation and pre-task cancellation are synchronized so every continuation completes exactly once.

## Files changed

- Added model transport protocol and streaming URLSession implementation.
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
- Final full `BonsaiMobile` regression: `/tmp/task3-unit-post-refactor.xcresult` `Passed`; 53 test cases / 65 parameterized invocations, 0 failures, 0 skips.

## Real loopback Range evidence

- The Python fixture binds only to `127.0.0.1` and deliberately closes the first 1,500,000-byte response after 500,000 bytes.
- The first client operation failed as intended while retaining a 500,000-byte managed partial.
- The next request was observed as `Range: bytes=500000-`; the server returned a validated 206 response and final size/SHA-256 passed.
- A second 777-byte partial emitted `Range: bytes=777-`; the `/ignore` endpoint deliberately returned 200, proving the client truncated instead of concatenating. Final size/SHA-256 passed.
- During debugging, the initial post-resume verifier failure was isolated to cached `URL.resourceValues` metadata: request logs and `wc -c` both proved the file was complete. Switching verification to fresh `FileManager.attributesOfItem` fixed the exact rerun without changing transport behavior.
- Cancellation testing uses the throttled `/slow` endpoint: cancelling mid-transfer preserves the partial, a single Range resume completes and verifies it, and cancellation immediately after task creation completes in under one second without leaking a continuation.
- Final `RuntimeProbe` scheme (`/tmp/task3-integration-post-refactor.xcresult`): 3 real loopback passes, 1 explicit no-model skip, 0 failures. Result-bundle scans found no continuation-misuse, leaked-continuation, compiler-warning, or error markers.

## Import attack coverage

- Missing required files and unexpected files.
- Duplicate archive paths and required-path prefix collisions.
- POSIX absolute paths, Windows absolute-like paths, `..` traversal, empty components, and canonical descendant checks.
- Folder and archive symlinks, folder hard links, non-regular/special entries, and executable entries.
- Raw central-directory Unix metadata for symlinks, FIFO/socket/device entries, and hard-link metadata is rejected before ZIPFoundation extraction APIs run. Only the explicit `.bonsaimodel.zip` package extension is accepted.
- Directory/file and parent-prefix collisions are rejected even when ZIPFoundation represents directory entries separately.
- Declared-size limits, high compression-ratio rejection, size mismatch, and SHA-256 mismatch.
- Metadata and paths are validated before each archive entry is written; archives are never extracted wholesale.

## Final verification

- SwiftLint strict: 0 violations in 25 Swift files.
- XcodeGen determinism: two consecutive generations produced pbxproj SHA-1 `7216d35cc939939229f3b5a25127109914cf4195`.
- `git diff --check`, Python fixture bytecode compilation, and bootstrap shell syntax: passed.
- Generic iOS build could not start because this Xcode installation does not have the iOS 26.5 platform component installed; Xcode marks `Any iOS Device` ineligible. The production target passes the available macOS Swift 6 build/test lane.

## Commit and remaining risks

- Base implementation commit: `aa97ccf125a1d33d281ca7d8974f7ce87fa590d6` (`feat(mobile): manage verified model installations`). The spec-review hardening commit SHA is returned to the orchestrator.
- Real multi-gigabyte Hub downloads and security-scoped Files/AirDrop access require later real-device evidence. This task proves the transport/storage boundary with real loopback I/O and exercises import content locally.
- iPhone compilation and device file-protection behavior remain unverified until the missing iOS platform is installed and Task 9 device testing is performed.
