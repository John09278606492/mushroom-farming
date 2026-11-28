# Firebase Realtime Database schema

The contract between the **ESP32 controller firmware** and the **mobile app** (`app/`). Both sides must use exactly these paths and field names.

Rules that come from the handoff (do not change):
- Control logic runs on the ESP32. The app only writes **desired** values (mode, manual device commands, setpoints, schedules). The ESP32 applies them and reports the **actual** state in `live`.
- The ESP32 caches setpoints and schedules in flash, so it keeps farming without internet.

Everything lives under one farm root: `farm1/`.

## `farm1/live` (ESP32 → app, every 10 s)

| Field | Type | Meaning |
|---|---|---|
| `updatedAt` | number (ms) | Write `{".sv": "timestamp"}` (server time). The app marks the controller **offline** if this is older than 60 s. |
| `temp` | number | °C |
| `rh` | number | % relative humidity |
| `co2` | number | ppm (`-1` if the sensor has no reading) |
| `lowWater` | bool | Refill float switch says the reservoir is low |
| `waterCutoff` | bool | Low-level cutoff float switch (2nd float). `true` = pumps are blocked. Omit if not installed. |
| `mode` | string | `"auto"` or `"manual"` (actual mode) |
| `devices/mist` | bool | Ultrasonic mist maker (SSR) |
| `devices/fan` | bool | Exhaust / CO2 fan relay |
| `devices/refill` | bool | Submersible refill pump |
| `devices/sprinkler` | bool | High-pressure misting pump |
| `devices/light` | bool | Grow light |
| `rtc` | string | `"YYYY-MM-DD HH:MM:SS"` from the DS3231 |
| `rssi` | number | Wi-Fi signal (dBm), optional |
| `fw` | string | Firmware version, optional |
| `boxPower` | bool | A sensor answered recently (box supply looks on), optional |
| `refillTimedOut` | bool | Refill pump stopped after 15 min straight, optional |
| `sensors/th`, `sensors/co2`, `sensors/rtc` | bool | Each sensor answered recently, optional |

`temp` and `rh` are `null` when the AM2302 has had no good reading for 60 s.

## `farm1/control` (app → ESP32)

| Field | Type | Meaning |
|---|---|---|
| `mode` | string | Desired mode: `"auto"` or `"manual"` |
| `modeAt` | number (ms) | Server timestamp of the last mode tap |
| `devices/<name>` | bool | Desired on/off for `mist`, `fan`, `refill`, `sprinkler`, `light` |
| `at/<name>` | number (ms) | Server timestamp of the last tap on that device |
| `updatedAt` | number (ms) | Server timestamp of the last command |

How the ESP32 applies commands (`firmware/body/cloud.cpp`):
- A command runs only when its timestamp (`modeAt`, `at/<name>`) changes. The first read after a reboot only records the timestamps, so nothing switches by itself and the HMI's later changes are not overwritten by an old app value.
- Each command becomes the same text command the HMI sends (`FAN_ON`, `AUTO_OFF`, …), so the HMI and the app behave the same.
- **Auto mode:** `mist`, `fan` and `refill` follow the thresholds; a tap on one of them holds it for 15 min, then auto takes over again. `sprinkler` and `light` follow their schedules, and a tap still works (a manual sprinkler run stops after 10 min).
- **Manual mode:** every device follows the taps.
- **Safety:** if `waterCutoff` is true, the ESP32 lets `refill` keep running (to fill the reservoir) but forces `sprinkler` and `mist` OFF, in every mode. (Needs the 2nd float switch; not installed yet.)

Setpoints and schedules go both ways: the ESP32 applies `setpoints` when `updatedAt` changes and `schedules` when their content changes, and writes them back when they are changed on the HMI.

The app shows a command as "pending" until `live/devices/<name>` matches `control/devices/<name>`.

## `farm1/setpoints` (app → ESP32)

| Field | Type | Default | Meaning |
|---|---|---|---|
| `humOn` | number | 85 | Mist ON below this % RH |
| `humOff` | number | 95 | Mist OFF above this % RH |
| `co2On` | number | 800 | Fan ON above this ppm |
| `co2Off` | number | 700 | Fan OFF below this ppm |
| `tempMax` | number | 28 | Alert only (app): temperature too high |
| `tempMin` | number | 22 | Alert only (app): temperature too low |
| `stage` | string | `"fruiting"` | `"spawn_run"` or `"fruiting"`; label for the preset the user picked |
| `updatedAt` | number (ms) | | Server timestamp |

Validation: `humOn < humOff`, `co2Off < co2On`.

## `farm1/schedules` (app → ESP32)

```
farm1/schedules/sprinkler/<0..4> = { enabled, hour, minute, durationMin, days }
farm1/schedules/light/<0..4>     = { enabled, hour, minute, durationHr,  days }
```

- `hour` 0–23, `minute` 0–59.
- `days`: list of 7 bools, index 0 = Sunday … 6 = Saturday (same as `RTClib dayOfTheWeek()`).
- Sprinkler duration is in **minutes** (1–120), light duration is in **hours** (1–24), matching the original firmware.
- Up to 5 slots per device (`MAX_SCHEDULES`). A missing slot means "not set".

## `farm1/history/<pushId>` (ESP32 → app, every 10 min)

`{ "ts": <server timestamp ms>, "temp": 26.1, "rh": 89.0, "co2": 640 }`

Use `push()` so keys sort by time. The app queries `orderByChild("ts").startAt(<now - range>)`.

## `farm1/camera/latest` (ESP32-CAM → app)

`{ "ts": <server timestamp ms>, "image": "<base64 JPEG, VGA 640×480>" }`

## `farm1/harvest/latest` (app → app)

`{ "ts": <ms>, "label": "not_ready" | "ready" | "over_mature" | "empty", "confidence": 0.0–1.0 }`

Written by the app's image model when it is added (see `docs/harvest-detection-plan.md`).

## `farm1/batches/<pushId>` (app)

`{ "pinnedAt": <ms>, "harvestedAt": <ms or null>, "weightG": <number or null>, "notes": "" }`

The app's pinning timer: "Pinning started" creates a batch; "Harvested" closes it and logs the weight.

## Security rules (Firebase console → Realtime Database → Rules)

Only signed-in users (the app users and the ESP32's own account) can read or write:

```json
{
  "rules": {
    "farm1": {
      ".read": "auth != null",
      ".write": "auth != null",
      "history": { ".indexOn": ["ts"] }
    }
  }
}
```
