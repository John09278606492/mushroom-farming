# Hardware test results (body ESP32)

Tested on 2026-11-19 → 11-20 with `component_tester` uploaded over USB (COM6).
The box had been rewired by others, so every pin was checked by hand.

## Outputs

| Device | Driver | ESP32 pin | ON level | Result |
|---|---|---|---|---|
| Refill pump (submersible) | 2-ch relay HL-52S, relay 2 (IN2) | GPIO13 | HIGH | OK |
| Mist maker 48V | SSR-10DD (input 3+/4-) | GPIO12 | HIGH | OK (needs water over the black level sensor; LED red = no water, green = misting) |
| Sprinkler pump | 4-ch relay | GPIO19 | not confirmed | Relay clicks |
| Fan | 4-ch relay | GPIO23 | not confirmed | Relay clicks |
| Grow light | 4-ch relay | GPIO25 | not confirmed | Relay clicks |
| 4th channel of the 4-ch relay | ? | ? | ? | Not found yet |
| 2-ch relay, relay 1 (IN1) | none | none | - | No wire on IN1, unused |

## Problems found

1. **Loose dupont wires on the 4-channel relay header.** The LED blinked but the
   relay stopped clicking until the pins were pressed. This explains relays
   switching on and off by themselves. Replace or solder the connectors and
   hot-glue them.
2. **ESP32 is powered only by USB.** With the breaker on and no USB, the ESP32
   is off and the relays switch ON by themselves (fan, sprinkler). Feed 12V into
   the base board's DC jack (6.5-12V) so it runs from the box supply.
3. **USB back-feeds the box.** With the breaker off and USB plugged in, the
   laptop's 5V reaches the 12V rail and the cooling fan and sprinkler pump run
   slowly. Plug USB in only after the breaker is on until the DC jack is wired.
4. **Old firmware state** (from the flash read before testing): Manual mode
   (float switch ignored), sprinkler schedules at 6:00 AM (3 min) and 3:00 PM
   (1 min), HUM_OFF=86, CO2_ON=150 / CO2_OFF=100, RTC not found.
5. Loose screws and the DS3231 RTC board lying on the metal floor of the box:
   short-circuit risk.

## Sensors

| Sensor | Pin | Result |
|---|---|---|
| Float switch | GPIO18 (pull-up, LOW = water low) | OK. Bounces when the water moves; firmware needs a 1-2 s debounce |
| CO2 (MH-Z19 style UART) | RX 16 / TX 17, 9600 | OK, 718-1025 ppm indoors |
| Temp/humidity: ASAIR AM2302 (wired DHT22, built-in pull-up) | GPIO4, VCC 3.3V | OK: 26.4 °C / 96 % RH. The signal has short glitches on its edges that the Adafruit DHT and DHTesp libraries (esp32 core 4.0) reject as checksum errors. The tester's `dhtraw` reader merges glitches under 8 µs and gets about 6 of 10 reads with a good checksum and no wrong values. Use this reader in the firmware and keep the last good value |
| DS3231 RTC (+ AT24C32 EEPROM) | I2C SDA 21 / SCL 22 | OK: answers at 0x68 and 0x57. Was at 2000-01-11 with `lostPower=1`; set to PC time on 2026-11-21 (`rtcset`), now `lostPower=0`. Check the coin cell so it keeps time with the power off |

Do not power the AM2302 from 5V: its internal pull-up is tied to VCC, so GPIO4
would see 5V.

The sensors are powered from the box supply, so the breaker must be on when
reading them (CO2 gave no reply with the breaker off).

Safe shutdown order until the ESP32 has its own 12V feed: **breaker OFF first,
then unplug USB**. Unplugging USB first kills the ESP32 and the relays turn on.

Note: the DHT library crashes the ESP32 (interrupt watchdog) when it is pointed
at GPIO22 or the HMI UART pins, so `dhtfind` is not reliable past GPIO18.

## Not tested yet

- Relay polarity of the 4-ch board (does HIGH or LOW turn the load on?)
- The 4th channel of the 4-ch relay
- HMI UART link (26/27)

## Backup

The firmware that was on the board is saved as
`firmware/backup/body_esp32_flash_2026-11-19.bin` (local only, not in git).
Restore with:

```
esptool --port COM6 write-flash 0 firmware/backup/body_esp32_flash_2026-11-19.bin
```
