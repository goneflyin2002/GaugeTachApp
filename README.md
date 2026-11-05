# Gauge Setup (Flutter, Android)

Setup app for the GaugeTach BLE gauges (XIAO ESP32-C5 + TB6612FNG + X27 stepper).

Firmware: [GaugeTachFirmware](https://github.com/goneflyin2002/GaugeTachFirmware)

## First-time setup

This folder only holds the app code, so create the Flutter project around it:

```bash
flutter create --org com.goneflyin --platforms android gauge_app
```

Copy everything from this folder into the new `gauge_app` folder, letting it
overwrite `pubspec.yaml` and `lib/main.dart`. Then:

1. Open `android/app/src/main/AndroidManifest.xml` and add these lines just
   inside `<manifest ...>`, above `<application`:

   ```xml
   <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
   <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
   <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
   <uses-permission android:name="android.permission.INTERNET" />
   ```

   INTERNET is for firmware updates (debug builds have it anyway; release builds need it).

   While you're there, change `android:label="gauge_app"` to `android:label="Gauge Setup"`.

2. Run it on your phone (USB debugging on):

   ```bash
   flutter pub get
   flutter run
   ```

The app asks for Bluetooth permission the first time it scans.

## Screens

- **Gauges nearby**: lists every gauge advertising the GaugeTach service.
  Each one is named `GaugeTach-XXXX` (from its chip ID), so several gauges in
  one car can be told apart.
- **Live**: a drawn dial that follows the real needle, a slider to simulate
  RPM, Sweep and Home buttons, and jog buttons plus "Set zero here".
- **Setup**: cylinders / pulses per rev, input filtering, full scale, sweep.
- **Needle**: speed, acceleration, deadband, drive strength, direction, homing.
- **Calibrate**: up to 8 points for dials that aren't evenly spaced.
- **Firmware update** (icon at top right): checks `version.json` in the
  firmware repo on every connect, offers newer firmware, and installs it over
  Bluetooth. The gauge needs firmware 0.5.0 or later; flash that once over USB.

Changes take effect right away. The bar at the bottom offers **Save to gauge**
until they're stored in the gauge's flash.

## BLE protocol

| UUID (`6a1f000x-3c2d-4b8e-9f10-7e5a2c9d4b01`) | Type | Contents |
|---|---|---|
| `0001` | Service | GaugeTach |
| `0002` | Read | JSON of all settings, including `rev` |
| `0003` | Write | Serial-console commands, one per line (`set speed 300\nsave`) |
| `0004` | Notify | Live JSON 10x/s: `rpm raw needle target homed busy hold sim unsaved rev ota otapct otaerr` |
| `0005` | Write | OTA control: `begin <bytes>`, `end`, `abort` |
| `0006` | Write | OTA data chunks |

The app re-reads `0002` whenever `rev` in the status changes, so changes made
from the Serial Monitor show up in the app too.

All Bluetooth code is in `lib/ble/gauge_ble.dart`.

## License note

`flutter_blue_plus` 2.x is free for personal / hobby use (`License.nonprofit`
in `gauge_ble.dart`) but requires a paid commercial license for for-profit
use. If the gauge becomes a product, either buy that license or swap the BLE
package. Only `gauge_ble.dart` would change.
