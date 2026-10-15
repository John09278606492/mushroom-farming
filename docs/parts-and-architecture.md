# Smart Mushroom Farm: parts review and IoT plan

Assumes oyster mushrooms in a tropical climate (Philippines), one grow room or tent, and an app you build yourselves.

## 1. Fix or check these in your current list

| Part | Issue | What to do |
|---|---|---|
| Temperature & Humidity sensor | If it is a DHT11/DHT22, it drifts and saturates at the 85–95% RH that mushrooms need. | Replace with **SHT31 or SHT40/SHT45** (I2C) with a protective filter cap. |
| CO2 sensor (infrared) | Spawn run CO2 can go above 5,000 ppm; many cheap NDIR modules top out at 2,000 or 5,000. | Use **MH-Z19C (0–10,000 ppm)** or **Sensirion SCD30/SCD41**. Confirm the exact model you bought. |
| Mist maker "45V" + 48V supply | Most multi-head foggers are rated 48V, so it is probably fine, but check the label. | If it truly says 45V, turn the supply's V-ADJ pot down to 45V. Run the fogger with its float/ water level; never dry. |
| High-pressure pump 130 psi | Draws roughly 4–8A with a big start-up surge; your 12V supply must handle it. | Check the pump's voltage (12V or 24V) and size the supply at **≥1.5× total current**. Add a flyback diode. |
| Relay modules (5V) | ESP32 pins are 3.3V; some 5V relay boards will not trigger reliably. | Use opto-isolated boards with a JD-VCC jumper, power coils from 5V, drive IN pins from 3.3V. Test each channel. |
| SSR-10DD | DC-only SSR (it cannot switch AC). No built-in flyback protection. | Use it for a 12V/48V DC load you want to switch often or PWM (e.g. fan speed or fogger). Add a diode across inductive loads. |
| Buck converter | The 5" ESP32-S3 display with backlight can pull ~1A. | Use a buck rated **≥3A**. |
| Breadboard + jumpers | Fine for testing, but they corrode and loosen in high humidity. | For the final build move to perfboard/PCB with screw terminals, then conformal-coat it. |
| Float switch (1 only) | One switch can't tell "refill now" from "pump is about to run dry". | Add a **second float switch** for low-level cutoff. |

## 2. Hardware to add

**Networking (pick one)**
- Farm has Wi-Fi/fiber: any 2.4 GHz router; add a Wi-Fi extender if the grow room is far.
- No internet at the farm: a **4G LTE router or pocket Wi-Fi** with a prepaid SIM (easiest), or a SIM7600 module on the ESP32 (harder).

**Sensors**
- BH1750 light (lux) sensor for checking grow light schedules.
- DS18B20 waterproof probe for substrate/bag temperature during spawn run.
- Optional: YF-S201 water flow sensor (detects a clogged or dry pump), INA219/ACS712 current sensor (detects a dead fan or pump).

**Actuators**
- **Exhaust fan + intake fan** (12V DC or inline duct fan) for fresh air exchange. This is how you lower CO2. Your 12V cooling fan can be the air circulation fan.
- Misting line for the high-pressure pump: nozzles, high-pressure tubing, inline filter, and a 12V solenoid valve.
- 12V solenoid valve or the submersible pump for auto-refilling the reservoir.
- Grow light: 12V LED strip, 6500K white.
- Buzzer and status LED for local alarms.

**Power and safety**
- Main switch or small MCB, plus an **inline fuse per rail** (12V, 48V, 5V).
- Flyback diodes (1N5819/1N4007) across every pump, solenoid, and fan.
- Backup power: a DC mini-UPS or a 12V LiFePO4 battery with charger, so the ESP32s, sensors, and router survive brownouts. Pumps and the fogger can stay off during an outage.
- **IP65 enclosure** with cable glands, 16–18 AWG wire for pumps, ferrules, and optionally a DIN rail.

## 3. How to split the two ESP32s

- **ESP32 module = controller.** It reads every sensor, drives every relay/SSR, runs the automatic control loop, and keeps time with the DS3231. It must work even with no internet or a crashed display.
- **ESP32-S3 5" = local dashboard.** It shows readings, setpoints, and alarms, and lets you switch manual/auto at the farm. Its display uses most GPIOs, so keep sensors off it.
- They talk over Wi-Fi (MQTT or ESP-NOW), or a UART cable if they share an enclosure.

## 4. App architecture

```
Sensors -> ESP32 controller --(Wi-Fi/4G)--> Firebase Realtime DB <--> Your app
                  |                                 ^
                  +--> ESP32-S3 display (local)     |  setpoints, manual commands
```

**Recommended: Firebase Realtime Database (free plan)**
- ESP32 library: `Firebase ESP Client` (Mobizt). App: Flutter or Android with the Firebase SDK. Login comes from Firebase Auth.
- Suggested data layout:
  - `farm1/live` holds temp, rh, co2, lux, water level, and actuator states, updated every 5–10 s.
  - `farm1/history/<timestamp>` stores a reading every 5–15 min for charts.
  - `farm1/setpoints` holds target RH, max CO2, temp limits, and light schedule; the app writes and the ESP32 reads.
  - `farm1/control` holds mode (auto/manual) and manual on/off per device.
- Alternative: MQTT (HiveMQ Cloud or EMQX free tier). It is more "real IoT", but you also need your own database for history, so it is more work.

**Rules that keep it reliable**
- Control logic runs on the ESP32, never in the app. The app only changes setpoints.
- Use hysteresis (e.g. mist on below 85% RH, off at 92%) so relays don't chatter.
- Cache the last setpoints in ESP32 flash, so a reboot without internet still farms correctly.
- Add a hardware watchdog and auto-reconnect for Wi-Fi.

## 5. Starting setpoints (oyster mushroom)

| Stage | Temp | RH | CO2 | Light |
|---|---|---|---|---|
| Spawn run | 24–28 °C | 70–80% | can be high (5,000+ ppm) | dark |
| Fruiting | 22–28 °C | 85–95% | below 800–1,000 ppm | ~12 h/day, low lux |

Tune these for your species and strain.
