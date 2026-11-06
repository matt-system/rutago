# MESHBIT Native — offline mesh foundation

This is the native Flutter client for Android and iOS. It is separate from the Cloudflare PWA.

## Current implementation
- Native nearby discovery over hybrid BLE and local peer-to-peer networking using the `nearby` transport.
- User-approved incoming peer connections with a short authentication string (SAS) exposed by the transport.
- Durable SQLite packet queue, message IDs, duplicate suppression, TTL (12 hops), and store/forward relay.
- AES-256-GCM encrypted message payloads. Relay nodes forward opaque ciphertext.
- No account, phone number, email, or cloud server is required for local mesh transport.

## Important current limitations
- This is an initial native mesh foundation, not a security-audited messenger.
- The conversation key is currently shared out-of-band: generate a 32-byte key on one device and securely transfer it to the intended recipient. Do not send the key through the mesh.
- The first implementation routes by the recipient's installation ID. It does not yet implement automatic public-key contact discovery, group membership, Signal Double Ratchet, or audited key rotation.
- iOS background discovery/advertising is restricted by the operating system; foreground operation is the reliable first target. Android background relay also requires explicit foreground-service/lifecycle work.
- Real radio behavior must be tested on at least two physical phones. Emulators and static code checks cannot prove BLE/Wi-Fi peer operation.

## Build
Open this folder in a Flutter environment and run:
```sh
flutter pub get
flutter create --project-name meshbit --org app.meshbit --platforms=android,ios .
flutter run
```

Android APK CI is configured in `.github/workflows/meshbit-android.yml`.
