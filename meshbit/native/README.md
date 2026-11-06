# MESHBIT Native — offline mesh client

This is the native radio client for MESHBIT. The Worker-hosted PWA cannot provide reliable BLE discovery or multi-hop radio relay on iOS and Android; this Flutter app is the native implementation of that capability.

## Implemented in the native client

- Nearby discovery and advertising through the `nearby` transport in **BLE-only mode**. The MESH radio path does not use Wi-Fi, a router, internet access, or mobile data.
- Encrypted, PIN-verified peer sessions.
- Application-layer store-and-forward relay: AES-256-GCM ciphertext packets are stored in SQLite and forwarded to connected peers.
- Multi-hop forwarding with a maximum TTL of 12 and packet-ID deduplication.
- Seven-day local packet retention.
- A local inbox; only the intended recipient with the shared conversation key can decrypt. Sender and recipient IDs are inside the encrypted payload, not in the relay envelope.
- No server, Wi-Fi connection, internet access, or mobile-data connection is required after installation to exchange packets locally. Bluetooth must be enabled and the MESH screen must remain open.

## First-use flow

1. Install MESHBIT Native on each phone and allow Bluetooth permissions.
2. Open the app and tap **INICIAR MESH** on all participating phones.
3. Connect nearby phones. Compare the session PIN shown on both screens before accepting.
4. Share the recipient's **ID de este dispositivo** and the conversation key over a separate trusted channel. Generate one key and use the same 64-character hex key on both ends.
5. For a multi-hop test, keep node B connected to A and C. Put A and C out of direct radio range, send from A to C, and leave B running as a relay. The packet remains queued on B and is forwarded when a peer/route becomes available.

## Platform realities

- Android APK builds are uploaded by GitHub Actions as the `meshbit-native-android-apk` artifact.
- iOS support is included in the Flutter project and its Bluetooth/local-network usage declarations. A signed iPhone install/TestFlight release requires Apple signing credentials and a macOS build.
- MESH is designed for foreground use. Keep the app open on all participating phones. This avoids relying on iOS background scanning or advertising; the app does not promise relay while closed or suspended.
- The native app embeds the existing Worker-hosted chat in a separate **CHAT** screen; that screen needs internet. The **MESH** screen is native and works locally without internet or mobile data. The native client does not yet share the PWA identity vault or contacts.
- The `nearby` transport is a young third-party dependency. CI compilation/unit checks are not proof of a successful multi-phone field test; radio behavior needs physical Android and iPhone testing.

## Security notes

- Transport sessions use encrypted PIN-verification mode.
- Message payloads use AES-256-GCM with a user-shared 32-byte conversation key.
- Relays see packet ID, hop limit, nonce, authentication tag, ciphertext, and local storage timing; they do not see message text or sender/recipient IDs inside the ciphertext.
- This is not an independently audited Signal-style protocol. Key exchange is manual and must use a trusted channel.


## Offline MESH versus online chat

- **MESH** is the Bluetooth LE network and stays local. It works with no Wi-Fi and no 4G/5G, provided the participating phones have Bluetooth enabled and the app open.
- **CHAT** opens the existing web chat in an embedded view and requires an internet connection. It is a separate screen; it is not used to relay offline MESH packets.
- The BLE relay is a best-effort flooding mesh. Range depends on phones, surroundings, and BLE radio conditions; more participating phones can extend reach by forwarding packets.
