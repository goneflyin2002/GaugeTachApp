# Gauge Setup (Flutter, Android)

Setup app for the GaugeTach BLE gauges (XIAO ESP32-C5 + TB6612FNG + X27 stepper).

Firmware: [GaugeTachFirmware](https://github.com/goneflyin2002/GaugeTachFirmware)

## Building

This repo is the complete Flutter project.

1. Clone it (VS Code: Ctrl+Shift+P → `Git: Clone` →
   `https://github.com/goneflyin2002/gauge_app`).
2. Plug in the phone with USB debugging on, then in the project folder:

   ```bash
   flutter pub get
   flutter run
   ```

The app asks for Bluetooth permission the first time it scans.

### Android permissions

Already in `android/app/src/main/AndroidManifest.xml`. If the project is ever
regenerated with `flutter create`, add them back just inside `<manifest ...>`,
above `<application`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.INTERNET" />
```

INTERNET is for firmware updates (debug builds have it anyway; release builds
need it). The app label is set by `android:label="Gauge Setup"`.

## Screens

- **Gauges nearby**: lists every gauge advertising the GaugeTach service.
  Each one is named `GaugeTach-XXXX` (from its chip ID), so several gauges in
  one car can be told apart.
- **Live**: a drawn dial that follows the real needle, a slider to simulate
  RPM, Sweep and Home buttons, and jog buttons plus "Set zero here".
- **Setup**: cylinders / pulses per rev, input filtering, full scale, sweep,
  power-up sweep, and **Park needle when ignition turns off** (firmware 0.6.0+,
  needs ignition sense on D9; shows the live ignition state).
- **Needle**: speed, acceleration, deadband, 10-sweep step-loss test, drive
  strength, direction, homing.
- **Calibrate**: up to 8 points for dials that aren't evenly spaced.
- **Firmware update** (icon at top right): checks `version.json` in the
  firmware repo on every connect, offers newer firmware, and installs it over
  Bluetooth. The gauge needs firmware 0.5.0 or later; flash that once over USB.

Changes take effect right away. The bar at the bottom offers **Save to gauge**
until they're stored in the gauge's flash.

The phone's navigation and status bars are hidden while the app is open;
swipe up from the bottom edge to show them briefly.

## Code layout

| Path | Contents |
|---|---|
| `lib/ble/gauge_ble.dart` | All Bluetooth code: scanning, connection, command sending, OTA transfer |
| `lib/models/gauge_models.dart` | Settings and live-status data from the gauge |
| `lib/ota/firmware_release.dart` | Reads `version.json`, downloads the `.bin` |
| `lib/screens/` | Scan, gauge (Live / Setup / Needle / Calibrate), firmware update |
| `lib/widgets/` | Dial drawing, number-entry settings rows |

Sending: only one Bluetooth write is in flight at a time. Waiting commands are
merged (nudges add up, the RPM slider keeps only its newest value) and go out
together, so fast tapping can't back the gauge up.

## BLE protocol

| UUID (`6a1f000x-3c2d-4b8e-9f10-7e5a2c9d4b01`) | Type | Contents |
|---|---|---|
| `0001` | Service | GaugeTach |
| `0002` | Read | JSON of all settings, including `fw` and `rev` |
| `0003` | Write | Serial-console commands, one per line (`set speed 300\nsave`) |
| `0004` | Notify | Live JSON 10x/s: `rpm raw needle target homed busy hold sim unsaved rev ota otapct otaerr ignon parked` |
| `0005` | Write | OTA control: `begin <bytes>`, `end`, `abort` |
| `0006` | Write | OTA data chunks |

The app re-reads `0002` whenever `rev` in the status changes, so changes made
from the Serial Monitor show up in the app too.

## License note

`flutter_blue_plus` 2.x is free for personal / hobby use (`License.nonprofit`
in `gauge_ble.dart`) but requires a paid commercial license for for-profit
use. If the gauge becomes a product, either buy that license or swap the BLE
package. Only `gauge_ble.dart` would change.
