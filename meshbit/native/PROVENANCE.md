# MESHBIT — code provenance and licensing boundaries

## Bitchat review

Bitchat was reviewed as a product, protocol, and UX reference only. **No source file from `permissionlesstech/bitchat-android` or `permissionlesstech/bitchat` has been copied into Meshbit.** Meshbit's Bluetooth transport, envelope format, routing, local storage, and interface are independently authored for this repository.

The two upstream repositories do not have the same license status:

- The iOS/macOS repository's `LICENSE` identifies the source as Unlicense / public domain.
- The Android repository contains a `LICENSE.md` with GNU GPL version 3, despite its README describing the project as public domain.

Removing a license notice from copied GPL code would not remove the license obligations. Meshbit avoids that issue by not incorporating the Android repository's source code. Feature ideas such as multi-hop BLE relay, hop limits, deduplication, conversation modes, and store-and-forward are design references, not copied implementation.

## Meshbit source

This file does not grant a license to copy or redistribute Meshbit source code. The project owner retains the rights to Meshbit-authored material unless a separate license is published.

## Third-party dependencies

Meshbit uses independent libraries through Flutter's package manager. Their own notices and licenses remain applicable to those components and must be included where required in distributed builds. Current direct dependencies include:

- `nearby` — BSD 3-Clause; used for BLE discovery and encrypted point-to-point sessions.
- `flutter_secure_storage` — BSD 3-Clause; used for platform-protected key storage.
- Flutter and the remaining direct dependencies — consult each resolved package's license metadata and preserve the required notices in release distributions.

No Bitchat GPL source is bundled by this project.
