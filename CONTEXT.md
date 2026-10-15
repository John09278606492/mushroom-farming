# Project context (read this first)

Summary of decisions made so far for the Smart Mushroom Farm IoT project. Written for any AI assistant or collaborator picking this up. The full reasoning is in [`docs/conversation-log.md`](docs/conversation-log.md); detailed engineering notes are in [`docs/parts-and-architecture.md`](docs/parts-and-architecture.md).

## Goal

An IoT-controlled mushroom grow room (assumed oyster mushrooms, tropical climate, Philippines) that controls humidity, CO2 and temperature automatically, plus a mobile app (built by val) to monitor and control it remotely. Parts are bought on Shopee PH.

## Final parts list (one grow room)

The owner's original list, with only the needed changes applied.

| Part | Qty | Note |
|---|---|---|
| 12V Power Supply | 1 pc | Must handle the high-pressure pump's start-up surge (≥10A recommended) |
| 48V Power Supply | 1 pc | For the mist maker |
| Ultrasonic Mist Maker 45V | 1 pc | |
| Cooling Fan 12V | 2 pcs | Air circulation |
| 130 psi 6L/Min High Pressure Diaphragm Self Priming Water Pump | 1 pc | |
| Ultra Quiet Mini Lift 5m 800L/H Brushless Submersible Water Pump 12V | 1 pc | |
| Carbon Dioxide Air Gas Sensor Module Infrared | 1 pc | Ideally reads to 10,000 ppm (e.g. MH-Z19C) |
| Water Level Sensor Float Switch | **2 pcs** | **CHANGED:** second switch is a low-level cutoff so pumps never run dry |
| DS3231 RTC High Precision Real Time Clock | 1 pc | |
| ESP32-S3 5 inch Bluetooth WiFi Development Board with IPS | 1 pc | Local display |
| ESP32 Module | 1 pc | Main controller |
| 10A 4 Channel Relay Module | 1 pc | |
| 2 Channel Relay Module | 1 pc | |
| SSR 10DD | 1 pc | DC-only SSR |
| DC-DC 24V/12V to 5V Step Down Buck Converter | 2 pcs | 1 spare; ≥3A rating |
| DC Barrel Male and Female Connector | 5 pairs | |
| Jumper Wire Male-Male | 1 pack (40) | |
| Jumper Wire Male-Female | 1 pack (40) | |
| Jumper Wire Female-Female | 1 pack (40) | **NEW** (a "3-in-1 jumper wire set" covers all three) |
| Full Size Breadboard 830 | 1 pc | Prototyping only |
| 15A Terminal Block 12 Screw | 2 pcs | |
| SHT31 Temperature Humidity Sensor Module | 1 pc | **CHANGED:** replaces DHT11/DHT22, which fail at 85–95% RH |
| 4G LTE Pocket WiFi with SIM slot | 1 pc | **NEW:** internet for remote app access; skip if the farm has Wi-Fi |
| 12V DC Exhaust Fan | 1 pc | **NEW:** fresh air exchange to lower CO2 |

Optional upgrades discussed but not required: intake fan, misting nozzle kit + tubing + filter + solenoid valve, BH1750 light sensor, DS18B20 probe, mini UPS, fuses/breaker, flyback diodes, IP65 enclosure, perfboard + conformal coating, 12V LED grow light. See the conversation log for the full upgrade list with Shopee search terms.

## ESP32 role split

- **ESP32 module = controller.** Reads all sensors, drives all relays/SSR, runs the automatic control loop, keeps time with the DS3231. Must keep farming with no internet and no display.
- **ESP32-S3 5" = local dashboard only.** Shows readings, setpoints and alarms; manual/auto switching at the farm. Keep sensors off it (the display uses most of its GPIOs).
- They talk over Wi-Fi (MQTT or ESP-NOW) or UART if in the same enclosure.

## App architecture

```
Sensors -> ESP32 controller --(Wi-Fi/4G)--> Firebase Realtime DB <--> Mobile app
                  |                                 ^
                  +--> ESP32-S3 display (local)     |  setpoints, manual commands
```

- **Firebase Realtime Database** (free plan) + Firebase Auth. ESP32 library: `Firebase ESP Client` (Mobizt). App: Flutter or Android.
- Data layout:
  - `farm1/live`: temp, rh, co2, lux, water level, actuator states (every 5–10 s)
  - `farm1/history/<timestamp>`: a reading every 5–15 min for charts
  - `farm1/setpoints`: target RH, max CO2, temp limits, light schedule (app writes, ESP32 reads)
  - `farm1/control`: mode (auto/manual) and manual on/off per device
- Rules: control logic lives on the ESP32, never in the app; use hysteresis (e.g. mist on below 85% RH, off at 92%); cache setpoints in flash; watchdog + Wi-Fi auto-reconnect.
- Alternative considered: MQTT (HiveMQ Cloud / EMQX), rejected for now because it needs a separate database for history.

## Starting setpoints (oyster mushroom)

| Stage | Temp | RH | CO2 | Light |
|---|---|---|---|---|
| Spawn run | 24–28 °C | 70–80% | can be high (5,000+ ppm) | dark |
| Fruiting | 22–28 °C | 85–95% | below 800–1,000 ppm | ~12 h/day, low lux |

## Status / next steps

- Hardware list finalized (above); purchasing on Shopee.
- Not started yet: ESP32 firmware, wiring diagram, Firebase project setup, mobile app.
