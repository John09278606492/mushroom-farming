# Original Arduino code (from val's external drive)

A copy of `D:\C DRIVE OLD FILES\Arduino` (folder dated 2026-04-14 to 2026-05-07). It is the students' working prototype from before the IoT plan in [`handoff.md`](../../handoff.md). It has **no Wi-Fi, Firebase, or camera code**. The two boards talk over UART only.

The folder structure is kept as it was so the sketches still open in the Arduino IDE.

| Folder | Board | Role |
|---|---|---|
| `esp_32/esp_32_body/` | ESP32 module | **Controller ("body")**: sensors, relays/SSR, auto logic, RTC schedules, EEPROM settings |
| `brain/` | ESP32-S3 5" 800×480 RGB display (GT911 touch) | **HMI ("brain")**: LVGL touch UI, BLE lock, sends commands to the body |
| `libraries/lv_conf.h` | – | LVGL config used by `brain` (16-bit color, Montserrat 14) |

### Which file is current

| File | Status |
|---|---|
| `esp_32/esp_32_body/esp_32_body.ino` | **Current** controller sketch (367 lines) |
| `esp_32/esp_32_body/body_code.txt` | Same as the `.ino` (line endings differ only) |
| `esp_32/esp_32_body/updated_code.txt`, `Old.txt` | Older versions |
| `brain/brain.ino` | **Current** HMI sketch (892 lines) |
| `brain/brain_code.txt` | Identical copy of `brain.ino` |
| `brain/New Text Document.txt`, `Old.txt` | Older versions (no BLE lock, different UART pins 17/13) |

## Controller (body) pin map

| GPIO | Connected to | Note |
|---|---|---|
| 4 | DHT22 data | Temp + humidity (the plan replaces this with SHT31 on I2C) |
| 18 | Float switch | `INPUT_PULLUP`, LOW = low water. Only 1 float switch |
| 12 | SSR-10DD → mist maker | HIGH = ON. GPIO12 is a boot strapping pin: if it is pulled HIGH at boot the ESP32 won't start |
| 13 | Relay → refill pump (submersible) | HIGH = ON |
| 19 | Relay → sprinkler (high-pressure pump) | HIGH = ON |
| 23 | Relay → fan | HIGH = ON |
| 25 | Relay → light | HIGH = ON |
| 16 / 17 | CO2 sensor UART2 RX / TX | 9600 baud, MH-Z19 command `FF 01 86 …` |
| 26 / 27 | UART1 RX / TX to the HMI | 115200 baud |
| 21 / 22 | I2C SDA / SCL → DS3231 RTC | |

The HMI side uses ESP32-S3 GPIO 44 (RX) / 43 (TX) for the same UART link.

## What the controller does

- Every 2 s: reads DHT22, float switch and CO2, runs auto logic, checks schedules, sends a status line to the HMI.
- **Auto mode** (hysteresis):
  - Mist ON below `HUM_ON` (default 85%), OFF above `HUM_OFF` (95%).
  - Fan ON above `CO2_ON` (800 ppm), OFF below `CO2_OFF` (700 ppm).
  - Refill pump ON while the float switch reads low water.
- **Schedules** (DS3231 RTC, up to 5 each, per weekday): sprinkler (duration in minutes) and light (duration in **hours**, stored in the same `durationMin` field).
- Settings and schedules are saved to EEPROM, so they survive a reboot.

## UART protocol (HMI ⇄ controller, newline-terminated)

Controller → HMI, every 2 s and after each command:
```
STATUS,AUTO=1,H=88.2,T=26.1,CO2=640,LOWWATER=0,MIST=0,REFILL=0,SPRINKLER=0,FAN=0,LIGHT=1,HUM_ON=85,HUM_OFF=95,CO2_ON=800,CO2_OFF=700,SPR_SCHED=0:ON:6:00AM:3m:SunMon...,LGT_SCHED=NONE,TIME=2026-04-14 18:30:00
```

HMI → controller commands:
`AUTO_ON` `AUTO_OFF` `MIST_ON|OFF` `REFILL_ON|OFF` `SPRINKLER_ON|OFF` `FAN_ON|OFF` `LIGHT_ON|OFF` `GET_STATUS`
`SET_RTC=YYYY-MM-DD HH:MM:SS` `SET_HUM_ON=<f>` `SET_HUM_OFF=<f>` `SET_CO2_ON=<n>` `SET_CO2_OFF=<n>`
`SET_SPR_SCHED=<idx>,<en>,<hr>,<min>,<dur>,<days 0-6>` `CLEAR_SPR_SCHED` `SET_LGT_SCHED=...` `CLEAR_LGT_SCHED`

## HMI (brain) features

Home dashboard (humidity, temp, CO2, clock, sprinkler/light/mist/fan state, water level, mode, active schedules), a page per device with ON/OFF buttons, humidity and CO2 threshold rollers, a schedule editor, an RTC setter, and a **BLE lock**: the touch controls stay disabled until a phone connects over BLE (nRF Connect / LightBlue) to the advertised name (`MushroomFarm` by default).

## Libraries used (kept locally, not pushed to GitHub)

The full `libraries/` folder (~208 MB) is in this local copy but is in `.gitignore`. Install these versions in the Arduino IDE Library Manager:

| Library | Version |
|---|---|
| lvgl | 9.5.0 (needs `libraries/lv_conf.h`) |
| GFX Library for Arduino (Arduino_GFX) | 1.6.5 |
| TAMC_GT911 | 1.0.2 |
| RTClib (Adafruit) | 2.1.4 |
| DHT sensor library (Adafruit) | 1.4.7 |
| Adafruit Unified Sensor | 1.1.15 |
| Adafruit BusIO | 1.17.4 |

BLE, Preferences, EEPROM, Wire and HardwareSerial come with the ESP32 board package.

## Compared with the IoT plan (handoff.md)

| Plan | Original code |
|---|---|
| SHT31 temp/RH | DHT22 |
| 2 float switches (refill + low-level cutoff) | 1 float switch; pumps have no dry-run cutoff |
| Wi-Fi + Firebase + mobile app | None (UART + BLE lock only) |
| ESP32-CAM harvest detection | None |
| Exhaust fan for CO2 | 1 "fan" relay (CO2-driven) |

The plan is to build the new firmware on top of this code instead of starting from zero.
