# Meshbit — native release setup

## Native targets configured

- Android: internal APK for device testing, production AAB for Google Play.
- iOS: internal device build and production App Store build.
- Expo development client: required because Meshbit needs native Bluetooth code; Expo Go is not sufficient.
- EAS Build profiles: development, preview and production.

## Build commands

Run these from the `meshbit/` directory:

```bash
npm install
npx expo-doctor
npx eas-cli login
npx eas-cli build:configure
npx eas-cli build --platform android --profile development
npx eas-cli build --platform ios --profile development
```

For a distributable Android test APK:

```bash
npx eas-cli build --platform android --profile preview
```

For store artifacts:

```bash
npx eas-cli build --platform all --profile production
```

## Important status

This configuration prepares the native build pipeline; it does not mean the native binaries have already been compiled or published. An EAS account and Apple signing credentials are required for iOS device builds. Google Play signing is required for store release.

The current app intentionally remains a non-networked sandbox. Do not use it for private messages. End-to-end encryption and the bidirectional Bluetooth mesh transport are still not implemented. Native BLE requires CoreBluetooth on iOS and BluetoothLeScanner/BluetoothLeAdvertiser plus GATT client/server on Android. These must be implemented and tested on physical devices before enabling the chat UI.

## Release gates

1. Native build succeeds on both platforms.
2. BLE transport passes Android↔Android, iPhone↔iPhone and Android↔iPhone tests, including foreground/background behavior.
3. E2EE uses audited protocol/SDK integration, with device verification and key backup/recovery tests.
4. Server logs and storage contain ciphertext only.
5. Security review before public release.
