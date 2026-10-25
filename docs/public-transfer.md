# Public source transfer

- Source: `MizanurOfcL55/flowShare`, commit `8dd32690d09705df6a8bb84b419cd0b2dbbf5c2f`.
- Destination: `mizanurofcl55-hue/FLOW-SHARE`, public `main` branch.
- All **168 tracked source files** were retrieved, including native runners, binary icons/fonts, golden images, lockfiles, tests and development evidence.
- Every retrieved file's Git blob SHA-1 matched the source tree before import. [source-manifest.json](evidence/source-manifest.json) records the original paths, sizes, modes and hashes.
- A scan for common private-key, GitHub token, AWS access-key and live API-token patterns found no matches. This is a targeted pattern scan, not an independent security audit.
- App and protocol source are unchanged. Public-facing README/docs, download instructions and the installed-app/release workflow are adapted for this repository; the release packaging helper and public documentation are added.
- The source repository remains unchanged. This is a copy of the complete current source tree, not a transfer of ownership or a rewrite of the original Git history.

## Public release verification

Public assets are built from this repository after import. The release workflow waits for all platform builds and automated checks, exercises the exact Android x86_64 APK, verifies build checksums, then verifies uploaded asset digests before publication. The release's `build-provenance.json` identifies exact build/test runs and the public source commit.

Historical evidence copied from the old repository is retained as historical evidence. Its artifact hashes should not be used to validate freshly rebuilt public APKs.

The repository is public, but the owner has not selected a project-wide open-source license. Bundled third-party license notices are preserved. No broader license grant is implied by this copy.
