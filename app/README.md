# Smart Mushroom Farm app (Android + iPhone)

One Flutter app for Android and iOS. The farmer can watch the grow room in real time and control it from the phone. It reads and writes Firebase Realtime Database using the layout in [`docs/firebase-schema.md`](../docs/firebase-schema.md).

## What it does

| Tab | What the user sees and does |
|---|---|
| **Home** | Online/offline status, alerts (low water, CO2 high, humidity low, too hot/cold, controller offline), live humidity / temperature / CO2 / water tank, **Auto ↔ Manual** switch, on/off switches for mist maker, exhaust fan, refill pump, sprinkler pump, grow light |
| **History** | Humidity, temperature and CO2 charts for 6 h / 24 h / 7 days, with min/avg/max and target lines |
| **Harvest** | Latest ESP32-CAM photo, AI harvest result (when the model is added), "Pinning started" day counter with the day 5–7 harvest window, "Mark as harvested" with weight log, past harvests |
| **Settings** | Growth stage presets (Spawn run / Fruiting), humidity + CO2 thresholds and temperature alert range, sprinkler and light schedules (5 each, per weekday), account / sign out |

How control works (same rules as the firmware):
- The app only sends **requests** (mode, on/off, thresholds, schedules). The ESP32 decides and reports back. A switch shows a spinner ("Sending…") until the controller confirms, and a message if it does not answer within 20 s.
- In **Auto**, the mist maker, exhaust fan and refill pump follow the thresholds, so their switches are locked. The sprinkler and light can still be switched.
- When the controller is **offline** (no update for 30 s), all controls are locked so nothing turns on unexpectedly later.
- If the low-level float switch trips, the sprinkler and mist switches are blocked.

**Demo mode** (button on the login screen) runs a simulated farm with the same rules. Use it to test the app, train users, or demo it to the panel before the hardware is online.

## Try it now (demo mode, no setup)

Flutter is installed at `C:\dev\flutter` (not on PATH). From this `app/` folder:

```bash
/c/dev/flutter/bin/flutter run -d chrome
```

## One-time setup

### 1. Tools

| For | Install |
|---|---|
| Android phone | [Android Studio](https://developer.android.com/studio) (it installs the Android SDK). Then run `flutter doctor --android-licenses`. |
| iPhone | A **Mac with Xcode**. iOS apps can only be built on macOS. Without a Mac, a cloud build service such as Codemagic can build it, but installing on an iPhone still needs an Apple ID (free: 7-day installs from Xcode) or a paid Apple Developer account (TestFlight / App Store). |
| Firebase | Node.js (already on this PC), then `npm install -g firebase-tools` and `dart pub global activate flutterfire_cli` |

Check everything with `flutter doctor`.

### 2. Firebase project (free Spark plan)

1. https://console.firebase.google.com → **Add project** (e.g. `smart-mushroom-farm`). Google Analytics is not needed.
2. **Build → Authentication → Get started → Email/Password → Enable.**
3. **Authentication → Users → Add user** for each farmer/student, and one more for the ESP32 (e.g. `esp32@farm.local`). There is no sign-up screen in the app on purpose.
4. **Build → Realtime Database → Create database**, location **Singapore (asia-southeast1)**, start in **locked mode**.
5. **Realtime Database → Rules**: paste the rules from [`docs/firebase-schema.md`](../docs/firebase-schema.md#security-rules-firebase-console--realtime-database--rules) and **Publish**.

### 3. Connect the app

```bash
firebase login
```

```bash
flutterfire configure --platforms=android,ios,web
```

Pick the project from step 2. This replaces the placeholder `lib/firebase_options.dart` (and adds the platform config files). The login screen will then show email/password sign-in.

The keys in `firebase_options.dart` are not passwords. Firebase protects the data with the security rules and sign-in.

## Run on a phone

Android (USB debugging on, phone plugged in):

```bash
/c/dev/flutter/bin/flutter run
```

Build an APK to share (Messenger, Google Drive):

```bash
/c/dev/flutter/bin/flutter build apk --release
```

The file is `build/app/outputs/flutter-apk/app-release.apk`.

iPhone (on a Mac): `open ios/Runner.xcworkspace`, set your Team under *Signing & Capabilities*, plug in the iPhone and press Run.

## Important: the controller must send data

The app shows **"No data from the controller yet"** until the ESP32 firmware writes to Firebase. The original firmware (`firmware/original/`) has no Wi-Fi or Firebase code yet; adding that sync is the next firmware step. The exact paths and fields it must use are in [`docs/firebase-schema.md`](../docs/firebase-schema.md).

## Code layout

```
lib/
  main.dart                 start-up, Firebase init, login vs demo
  firebase_options.dart     placeholder until `flutterfire configure`
  models/farm_models.dart   data classes = docs/firebase-schema.md
  logic/alerts.dart         alert rules and status colors (pure, tested)
  data/
    farm_repository.dart          interface
    firebase_farm_repository.dart real farm
    demo_farm_repository.dart     simulated farm (same rules as firmware)
    auth_service.dart             email/password sign-in
  state/farm_state.dart     live state, pending commands, timeouts
  ui/                       screens and widgets
test/                       unit + widget tests (`flutter test`)
```

## Tests

```bash
/c/dev/flutter/bin/flutter test
```

## Known limits

- **Notifications:** alerts show inside the app. Push notifications while the app is closed need Firebase Cloud Functions, which needs the paid Blaze plan (see `handoff.md` §6).
- **AI harvest model:** the Harvest tab shows the result from `farm1/harvest/latest`, but the TFLite model is not trained or added yet (`docs/harvest-detection-plan.md`).
- **History** depends on the firmware writing a reading to `farm1/history` every 10 minutes.
