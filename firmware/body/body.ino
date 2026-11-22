// Mushroom farm body controller (plain ESP32).
//
// Reads the sensors, drives the relays/SSR, runs the automatic control and
// the RTC schedules, and talks to the HMI over UART with the same protocol as
// the students' original esp_32_body.ino (STATUS lines out, commands in), so
// firmware/hmi/hmi.ino works with it unchanged.
//
// What changed from the original:
//   - Relay pins are driven OFF first thing at boot.
//   - AM2302/DHT22 read with our own pulse timer (the stock libraries fail
//     checksum on this sensor's glitchy edges), keeping the last good value.
//   - CO2 replies are checksum-checked.
//   - Float switch is debounced (2 s).
//   - Settings live in Preferences under a new name, so the old firmware's
//     leftover values (CO2_ON=150 and so on) are not loaded. First boot starts
//     in MANUAL with everything OFF; press Auto on the HMI to start control.
//   - Safety limits: mist stops when the humidity reading is lost, the refill
//     pump stops after 15 min straight (source may be empty), a manual
//     sprinkler run stops after 10 min.
//   - DS3231 driven directly over I2C (no RTClib).
//   - The same commands also work from the USB serial monitor, for testing.
//
// Build: arduino-cli compile --fqbn esp32:esp32:esp32 firmware/body
// Pins: see firmware/tests/TEST-RESULTS.md

#include <Wire.h>
#include <Preferences.h>
#include <HardwareSerial.h>
#include "body_types.h"

// ---------------- Pins ----------------
#define DHT_PIN              4
#define FLOAT_PIN            18
#define SSR_MIST_PIN         12   // boot strapping pin: must stay LOW at boot
#define RELAY_REFILL_PIN     13
#define RELAY_SPRINKLER_PIN  19
#define RELAY_FAN_PIN        23
#define RELAY_LIGHT_PIN      25
#define CO2_RX_PIN           16
#define CO2_TX_PIN           17
#define HMI_RX_PIN           26
#define HMI_TX_PIN           27
#define RTC_SDA_PIN          21
#define RTC_SCL_PIN          22

// All outputs switch ON with HIGH (original firmware, confirmed for 12 and 13).
#define OUT_ON  HIGH
#define OUT_OFF LOW

const int OUTPUT_PINS[] = {SSR_MIST_PIN, RELAY_REFILL_PIN, RELAY_SPRINKLER_PIN, RELAY_FAN_PIN, RELAY_LIGHT_PIN};

// ---------------- Timing and limits ----------------
const unsigned long SENSOR_PERIOD_MS   = 2500;            // AM2302 needs >= 2 s between reads
const unsigned long STATUS_PERIOD_MS   = 2000;
const unsigned long DHT_STALE_MS       = 60UL * 1000;     // no good read for this long -> reading lost
const unsigned long CO2_STALE_MS       = 60UL * 1000;
const unsigned long FLOAT_DEBOUNCE_MS  = 2000;
const unsigned long REFILL_MAX_MS      = 15UL * 60 * 1000;
const unsigned long SPRINKLER_MANUAL_MAX_MS = 10UL * 60 * 1000;
// A button pressed on the HMI while in AUTO wins over the automatic control
// for this long, then AUTO takes over again.
const unsigned long MANUAL_HOLD_MS     = 15UL * 60 * 1000;
// No sensor has answered for this long -> the box supply is probably off.
const unsigned long BOX_POWER_GRACE_MS = 30UL * 1000;

HardwareSerial co2Serial(2);
HardwareSerial hmiSerial(1);
Preferences prefs;

// ---------------- Settings (saved) ----------------
float humOn  = 85.0;
float humOff = 95.0;
int   co2On  = 800;
int   co2Off = 700;
bool  autoMode = false;   // first boot: manual, everything off

Schedule sprSched[MAX_SCHEDULES];
Schedule lgtSched[MAX_SCHEDULES];
int nSpr = 0, nLgt = 0;

// ---------------- Live state ----------------
bool mistOn = false, refillOn = false, sprinklerOn = false, fanOn = false, lightOn = false;

float humidity = NAN, temperature = NAN;
unsigned long lastDhtOk = 0;
bool dhtEverOk = false;
uint32_t dhtGood = 0, dhtBad = 0;

int co2ppm = -1;
unsigned long lastCo2Ok = 0;

bool lowWater = false;
int  floatRaw = HIGH;
unsigned long floatChangedAt = 0;

bool rtcOk = false;
bool rtcNeedsSync = false;          // clock was set while the RTC did not answer
// Software clock: keeps time from millis() when the RTC does not answer.
bool swClockSet = false;
uint32_t swEpochAtSet = 0;
unsigned long swMillisAtSet = 0;

unsigned long mistHoldUntil = 0, fanHoldUntil = 0, refillHoldUntil = 0;

unsigned long refillStartedAt = 0;
bool refillTimedOut = false;
unsigned long sprinklerStopAt = 0;   // 0 = no timer
unsigned long lightStopAt = 0;
bool sprinklerTimed = false, lightTimed = false;

// =====================================================
// Outputs
// =====================================================
void writeOut(int pin, bool on) { digitalWrite(pin, on ? OUT_ON : OUT_OFF); }

void setMist(bool on)  { writeOut(SSR_MIST_PIN, on); mistOn = on; }
void setFan(bool on)   { writeOut(RELAY_FAN_PIN, on); fanOn = on; }
void setRefill(bool on) {
  if (on && !refillOn) refillStartedAt = millis();
  writeOut(RELAY_REFILL_PIN, on);
  refillOn = on;
}
void setSprinkler(bool on, unsigned long runMs) {
  writeOut(RELAY_SPRINKLER_PIN, on);
  sprinklerOn = on;
  sprinklerTimed = on && runMs > 0;
  sprinklerStopAt = sprinklerTimed ? millis() + runMs : 0;
}
void setLight(bool on, unsigned long runMs) {
  writeOut(RELAY_LIGHT_PIN, on);
  lightOn = on;
  lightTimed = on && runMs > 0;
  lightStopAt = lightTimed ? millis() + runMs : 0;
}

// =====================================================
// AM2302 / DHT22 reader (from the component tester)
// =====================================================
// Times the sensor's pulses directly. Its edges have short glitches, so any
// piece under 8 us is merged back into the level before it.
bool readDhtOnce(float &rh, float &t) {
  const int MAXE = 240;
  uint16_t dur[MAXE];
  uint8_t lvl[MAXE];
  int n = 0;
  const uint32_t mhz = ESP.getCpuFreqMHz();
  static portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;

  pinMode(DHT_PIN, OUTPUT);
  digitalWrite(DHT_PIN, LOW);
  delay(2);                                   // start signal
  portENTER_CRITICAL(&mux);
  pinMode(DHT_PIN, INPUT_PULLUP);
  int last = digitalRead(DHT_PIN);
  uint32_t edge = esp_cpu_get_cycle_count();
  while (n < MAXE) {
    uint32_t now = esp_cpu_get_cycle_count();
    int v = digitalRead(DHT_PIN);
    uint32_t us = (now - edge) / mhz;
    if (v != last) {
      dur[n] = us; lvl[n] = last; n++;
      edge = now; last = v;
    } else if (us > 300) {
      break;
    }
  }
  portEXIT_CRITICAL(&mux);

  int m = 0;
  for (int i = 0; i < n; i++) {
    if (m > 0 && dur[i] < 8) {
      dur[m - 1] += dur[i];
      if (i + 1 < n) { dur[m - 1] += dur[i + 1]; i++; }
      continue;
    }
    dur[m] = dur[i]; lvl[m] = lvl[i]; m++;
  }
  n = m;

  uint16_t highs[60];
  int nh = 0;
  for (int i = 0; i < n && nh < 60; i++) if (lvl[i] == 1) highs[nh++] = dur[i];
  int startAt = -1;
  for (int i = 0; i < nh; i++) if (highs[i] >= 60 && highs[i] <= 110) { startAt = i + 1; break; }
  if (startAt < 0 || nh - startAt < 40) return false;

  uint8_t b[5] = {0};
  for (int i = 0; i < 40; i++) b[i / 8] = (b[i / 8] << 1) | (highs[startAt + i] > 48 ? 1 : 0);
  if ((uint8_t)(b[0] + b[1] + b[2] + b[3]) != b[4]) return false;

  rh = ((b[0] << 8) | b[1]) / 10.0f;
  t = (((b[2] & 0x7F) << 8) | b[3]) / 10.0f;
  if (b[2] & 0x80) t = -t;
  // Plausible values only.
  return rh >= 0 && rh <= 100 && t > -20 && t < 70;
}

void readDht() {
  float rh, t;
  if (readDhtOnce(rh, t)) {
    humidity = rh;
    temperature = t;
    lastDhtOk = millis();
    dhtEverOk = true;
    dhtGood++;
  } else {
    dhtBad++;
  }
}

bool dhtFresh() { return dhtEverOk && millis() - lastDhtOk < DHT_STALE_MS; }

// =====================================================
// CO2 (MH-Z19 style UART)
// =====================================================
// Never waits: reads the reply to the previous request, then sends the next
// one. The sensor answers within a few ms, long before the next call.
void pollCo2() {
  static const byte req[9] = {0xFF, 0x01, 0x86, 0, 0, 0, 0, 0, 0x79};
  while (co2Serial.available() >= 9) {
    if (co2Serial.peek() != 0xFF) { co2Serial.read(); continue; }
    byte r[9];
    co2Serial.readBytes(r, 9);
    if (r[1] != 0x86) continue;
    byte sum = 0;
    for (int i = 1; i < 8; i++) sum += r[i];
    sum = 0xFF - sum + 1;
    if (sum != r[8]) continue;
    co2ppm = r[2] * 256 + r[3];
    lastCo2Ok = millis();
  }
  while (co2Serial.available()) co2Serial.read();
  co2Serial.write(req, 9);
}

bool co2Fresh() { return co2ppm >= 0 && millis() - lastCo2Ok < CO2_STALE_MS; }

// The sensors run on the box supply. If none of them has answered lately,
// the breaker is off and the ESP32 runs on USB alone: automatic control must
// not switch pumps on (they would run weakly off the laptop's USB).
bool boxPowered() {
  unsigned long now = millis();
  bool th = dhtEverOk && now - lastDhtOk < BOX_POWER_GRACE_MS;
  bool co2 = co2ppm >= 0 && now - lastCo2Ok < BOX_POWER_GRACE_MS;
  return th || co2;
}

bool holding(unsigned long until) { return until != 0 && (long)(millis() - until) < 0; }
unsigned long holdFromNow() { return (millis() + MANUAL_HOLD_MS) | 1; }

// =====================================================
// Float switch (LOW = water low), debounced
// =====================================================
void readFloat() {
  int v = digitalRead(FLOAT_PIN);
  if (v != floatRaw) { floatRaw = v; floatChangedAt = millis(); }
  if (millis() - floatChangedAt >= FLOAT_DEBOUNCE_MS) {
    bool low = (floatRaw == LOW);
    if (!low) refillTimedOut = false;   // water came back: allow refill again
    lowWater = low;
  }
}

// =====================================================
// DS3231 RTC, direct I2C
// =====================================================
const uint8_t RTC_ADDR = 0x68;

uint8_t bcd2bin(uint8_t v) { return (v >> 4) * 10 + (v & 0x0F); }
uint8_t bin2bcd(uint8_t v) { return ((v / 10) << 4) | (v % 10); }

bool rtcRead(Clock &c) {
  Wire.beginTransmission(RTC_ADDR);
  Wire.write(0);
  if (Wire.endTransmission() != 0) return false;
  if (Wire.requestFrom((int)RTC_ADDR, 7) != 7) return false;
  uint8_t s = Wire.read(), mi = Wire.read(), h = Wire.read();
  Wire.read();  // day of week: computed from the date instead
  uint8_t d = Wire.read(), mo = Wire.read(), y = Wire.read();
  c.second = bcd2bin(s & 0x7F);
  c.minute = bcd2bin(mi & 0x7F);
  c.hour = (h & 0x40) ? (bcd2bin(h & 0x1F) % 12 + ((h & 0x20) ? 12 : 0)) : bcd2bin(h & 0x3F);
  c.day = bcd2bin(d & 0x3F);
  c.month = bcd2bin(mo & 0x1F);
  c.year = 2000 + bcd2bin(y);
  return c.month >= 1 && c.month <= 12 && c.day >= 1 && c.day <= 31 && c.hour < 24 && c.minute < 60;
}

int dayOfWeek(int y, int m, int d) {   // 0 = Sunday
  static const int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
  if (m < 3) y--;
  return (y + y / 4 - y / 100 + y / 400 + t[m - 1] + d) % 7;
}

bool rtcWrite(const Clock &c) {
  Wire.beginTransmission(RTC_ADDR);
  Wire.write(0);
  Wire.write(bin2bcd(c.second));
  Wire.write(bin2bcd(c.minute));
  Wire.write(bin2bcd(c.hour));          // 24 h mode
  Wire.write(bin2bcd(dayOfWeek(c.year, c.month, c.day) + 1));
  Wire.write(bin2bcd(c.day));
  Wire.write(bin2bcd(c.month));
  Wire.write(bin2bcd(c.year - 2000));
  if (Wire.endTransmission() != 0) return false;
  // Clear the oscillator-stopped flag.
  Wire.beginTransmission(RTC_ADDR);
  Wire.write(0x0F);
  if (Wire.endTransmission() != 0) return false;
  if (Wire.requestFrom((int)RTC_ADDR, 1) != 1) return false;
  uint8_t st = Wire.read();
  Wire.beginTransmission(RTC_ADDR);
  Wire.write(0x0F);
  Wire.write(st & 0x7F);
  return Wire.endTransmission() == 0;
}

// Days since 1970-01-01 (Howard Hinnant's algorithm).
long daysFromCivil(int y, int m, int d) {
  y -= m <= 2;
  long era = (y >= 0 ? y : y - 399) / 400;
  unsigned yoe = (unsigned)(y - era * 400);
  unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + (long)doe - 719468;
}

uint32_t toEpoch(const Clock &c) {
  return (uint32_t)daysFromCivil(c.year, c.month, c.day) * 86400UL + c.hour * 3600UL + c.minute * 60UL + c.second;
}

Clock fromEpoch(uint32_t t) {
  long z = t / 86400 + 719468;
  long era = z / 146097;
  unsigned doe = (unsigned)(z - era * 146097);
  unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  int y = (int)yoe + era * 400;
  unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  unsigned mp = (5 * doy + 2) / 153;
  int d = doy - (153 * mp + 2) / 5 + 1;
  int m = mp < 10 ? mp + 3 : mp - 9;
  uint32_t s = t % 86400;
  return Clock{y + (m <= 2), m, d, (int)(s / 3600), (int)(s / 60 % 60), (int)(s % 60)};
}

void setSoftClock(const Clock &c) {
  swEpochAtSet = toEpoch(c);
  swMillisAtSet = millis();
  swClockSet = true;
}

// Current time: from the RTC when it answers, otherwise from the software
// clock (set by SET_RTC or the last good RTC read). False when neither.
bool getNow(Clock &c) {
  if (rtcRead(c)) {
    rtcOk = true;
    if (rtcNeedsSync && swClockSet) {
      // The clock was set while the RTC was unreachable: copy it over now.
      Clock sw = fromEpoch(swEpochAtSet + (millis() - swMillisAtSet) / 1000);
      if (rtcWrite(sw)) { rtcNeedsSync = false; c = sw; Serial.println("RTC BACK, time copied to it"); }
    }
    setSoftClock(c);
    return true;
  }
  rtcOk = false;
  if (!swClockSet) return false;
  c = fromEpoch(swEpochAtSet + (millis() - swMillisAtSet) / 1000);
  return true;
}

String timeString() {
  Clock c;
  if (!getNow(c)) return "RTC_ERR";
  char buf[24];
  snprintf(buf, sizeof(buf), "%04d-%02d-%02d %02d:%02d:%02d", c.year, c.month, c.day, c.hour, c.minute, c.second);
  return String(buf);
}

// =====================================================
// Settings storage
// =====================================================
void saveSettings() {
  prefs.putBool("auto", autoMode);
  prefs.putFloat("humOn", humOn);
  prefs.putFloat("humOff", humOff);
  prefs.putInt("co2On", co2On);
  prefs.putInt("co2Off", co2Off);
  prefs.putInt("nSpr", nSpr);
  prefs.putInt("nLgt", nLgt);
  prefs.putBytes("spr", sprSched, sizeof(sprSched));
  prefs.putBytes("lgt", lgtSched, sizeof(lgtSched));
  Serial.println("SETTINGS SAVED");
}

void clearScheds(Schedule *s, int &n) {
  n = 0;
  for (int i = 0; i < MAX_SCHEDULES; i++) {
    s[i] = Schedule{false, 0, 0, 3, {false, false, false, false, false, false, false}};
  }
}

void loadSettings() {
  clearScheds(sprSched, nSpr);
  clearScheds(lgtSched, nLgt);
  if (!prefs.isKey("auto")) {
    Serial.println("SETTINGS: first boot, using defaults (MANUAL, all off)");
    saveSettings();
    return;
  }
  autoMode = prefs.getBool("auto", false);
  humOn = prefs.getFloat("humOn", 85);
  humOff = prefs.getFloat("humOff", 95);
  co2On = prefs.getInt("co2On", 800);
  co2Off = prefs.getInt("co2Off", 700);
  nSpr = constrain(prefs.getInt("nSpr", 0), 0, MAX_SCHEDULES);
  nLgt = constrain(prefs.getInt("nLgt", 0), 0, MAX_SCHEDULES);
  if (prefs.getBytesLength("spr") == sizeof(sprSched)) prefs.getBytes("spr", sprSched, sizeof(sprSched));
  if (prefs.getBytesLength("lgt") == sizeof(lgtSched)) prefs.getBytes("lgt", lgtSched, sizeof(lgtSched));
  Serial.println("SETTINGS LOADED");
}

// =====================================================
// Control
// =====================================================
void runAuto() {
  if (!autoMode) return;
  bool holdMist = holding(mistHoldUntil);
  bool holdFan = holding(fanHoldUntil);
  bool holdRefill = holding(refillHoldUntil);

  if (!boxPowered()) {
    // Breaker off: keep the automatic outputs off.
    if (!holdMist && mistOn) setMist(false);
    if (!holdFan && fanOn) setFan(false);
    if (!holdRefill && refillOn) setRefill(false);
    return;
  }

  // Humidity -> mist. No reading -> mist off (never run blind).
  if (!holdMist) {
    if (dhtFresh()) {
      if (humidity < humOn && !mistOn) setMist(true);
      else if (humidity > humOff && mistOn) setMist(false);
    } else if (mistOn) {
      setMist(false);
    }
  }

  // Low water -> refill, with a time limit in case the source is empty.
  if (!holdRefill) {
    if (lowWater && !refillOn && !refillTimedOut) setRefill(true);
    else if (!lowWater && refillOn) setRefill(false);
  }

  // CO2 -> fan.
  if (!holdFan && co2Fresh()) {
    if (co2ppm > co2On && !fanOn) setFan(true);
    else if (co2ppm < co2Off && fanOn) setFan(false);
  }
}

void runSafety() {
  unsigned long now = millis();
  if (refillOn && now - refillStartedAt >= REFILL_MAX_MS) {
    setRefill(false);
    refillTimedOut = true;
    Serial.println("SAFETY: refill pump ran 15 min, stopped (check the water source)");
  }
  if (sprinklerOn && sprinklerTimed && (long)(now - sprinklerStopAt) >= 0) setSprinkler(false, 0);
  if (lightOn && lightTimed && (long)(now - lightStopAt) >= 0) setLight(false, 0);
}

int lastSchedMinute = -1;

void runSchedules() {
  Clock c;
  if (!getNow(c)) return;
  int stamp = c.hour * 60 + c.minute;
  if (stamp == lastSchedMinute) return;     // each start time fires once
  lastSchedMinute = stamp;
  int dow = dayOfWeek(c.year, c.month, c.day);

  for (int i = 0; i < nSpr; i++) {
    const Schedule &s = sprSched[i];
    if (s.enabled && s.days[dow] && s.hour == c.hour && s.minute == c.minute) {
      setSprinkler(true, (unsigned long)s.duration * 60UL * 1000UL);
      Serial.printf("SPR SCHED#%d FIRED %d min\n", i, s.duration);
    }
  }
  for (int i = 0; i < nLgt; i++) {
    const Schedule &s = lgtSched[i];
    if (s.enabled && s.days[dow] && s.hour == c.hour && s.minute == c.minute) {
      setLight(true, (unsigned long)s.duration * 3600UL * 1000UL);
      Serial.printf("LGT SCHED#%d FIRED %d h\n", i, s.duration);
    }
  }
}

// =====================================================
// STATUS line (same fields as the original, plus a few extras the HMI ignores)
// =====================================================
String time12(int h, int m) {
  const char *ap = h < 12 ? "AM" : "PM";
  int h12 = h % 12 == 0 ? 12 : h % 12;
  char buf[10];
  snprintf(buf, sizeof(buf), "%d:%02d%s", h12, m, ap);
  return String(buf);
}

String schedText(const Schedule *s, int n, bool hours) {
  if (n == 0) return "NONE";
  static const char *DN[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
  String r;
  for (int i = 0; i < n; i++) {
    if (i > 0) r += "|";
    r += String(i) + ":" + (s[i].enabled ? "ON" : "OFF") + ":" + time12(s[i].hour, s[i].minute) + ":" +
         String(s[i].duration) + (hours ? "h" : "m") + ":";
    for (int d = 0; d < 7; d++) if (s[i].days[d]) r += DN[d];
  }
  return r;
}

void sendStatus() {
  bool hOk = dhtFresh(), cOk = co2Fresh();
  String p = "STATUS,";
  p += "AUTO=" + String(autoMode ? 1 : 0);
  p += ",H=" + String(hOk ? humidity : 0, 1);
  p += ",T=" + String(hOk ? temperature : 0, 1);
  p += ",CO2=" + String(cOk ? co2ppm : 0);
  p += ",LOWWATER=" + String(lowWater ? 1 : 0);
  p += ",MIST=" + String(mistOn ? 1 : 0);
  p += ",REFILL=" + String(refillOn ? 1 : 0);
  p += ",SPRINKLER=" + String(sprinklerOn ? 1 : 0);
  p += ",FAN=" + String(fanOn ? 1 : 0);
  p += ",LIGHT=" + String(lightOn ? 1 : 0);
  p += ",HUM_ON=" + String(humOn, 0);
  p += ",HUM_OFF=" + String(humOff, 0);
  p += ",CO2_ON=" + String(co2On);
  p += ",CO2_OFF=" + String(co2Off);
  p += ",SPR_SCHED=" + schedText(sprSched, nSpr, false);
  p += ",LGT_SCHED=" + schedText(lgtSched, nLgt, true);
  p += ",SENS_TH=" + String(hOk ? 1 : 0);
  p += ",SENS_CO2=" + String(cOk ? 1 : 0);
  p += ",SENS_RTC=" + String(rtcOk ? 1 : 0);
  p += ",REFILL_TIMEOUT=" + String(refillTimedOut ? 1 : 0);
  p += ",BOX_POWER=" + String(boxPowered() ? 1 : 0);
  p += ",HOLD_MIST=" + String(holding(mistHoldUntil) ? 1 : 0);
  p += ",HOLD_FAN=" + String(holding(fanHoldUntil) ? 1 : 0);
  p += ",HOLD_REFILL=" + String(holding(refillHoldUntil) ? 1 : 0);
  p += ",TIME=" + timeString();
  hmiSerial.println(p);
  Serial.println(p);
}

// =====================================================
// Commands (from the HMI or the USB serial monitor)
// =====================================================
// "<idx>,<en>,<hr>,<min>,<dur>,<days as digits 0-6>"
void applySchedule(Schedule *s, int &n, const String &args) {
  int v[5];
  int from = 0;
  for (int k = 0; k < 5; k++) {
    int c = args.indexOf(',', from);
    if (c < 0) return;
    v[k] = args.substring(from, c).toInt();
    from = c + 1;
  }
  int idx = v[0];
  if (idx < 0 || idx >= MAX_SCHEDULES) return;
  Schedule x{};
  x.enabled = v[1] != 0;
  x.hour = constrain(v[2], 0, 23);
  x.minute = constrain(v[3], 0, 59);
  x.duration = constrain(v[4], 1, 1440);
  String days = args.substring(from);
  for (unsigned i = 0; i < days.length(); i++) {
    int d = days.charAt(i) - '0';
    if (d >= 0 && d < 7) x.days[d] = true;
  }
  s[idx] = x;
  if (idx >= n) n = idx + 1;
}

void handleCommand(String cmd) {
  cmd.trim();
  if (cmd.length() == 0) return;
  String up = cmd;
  up.toUpperCase();
  Serial.println("CMD: " + cmd);
  bool ok = true;

  if (up == "AUTO_ON") {
    autoMode = true;
    refillTimedOut = false;
    mistHoldUntil = fanHoldUntil = refillHoldUntil = 0;
    saveSettings();
  } else if (up == "AUTO_OFF") {
    autoMode = false;
    mistHoldUntil = fanHoldUntil = refillHoldUntil = 0;
    saveSettings();
  }
  // In AUTO, a button press holds that device for MANUAL_HOLD_MS.
  else if (up == "MIST_ON")    { setMist(true);   if (autoMode) mistHoldUntil = holdFromNow(); }
  else if (up == "MIST_OFF")   { setMist(false);  if (autoMode) mistHoldUntil = holdFromNow(); }
  else if (up == "REFILL_ON")  { refillTimedOut = false; setRefill(true); if (autoMode) refillHoldUntil = holdFromNow(); }
  else if (up == "REFILL_OFF") { setRefill(false); if (autoMode) refillHoldUntil = holdFromNow(); }
  else if (up == "SPRINKLER_ON") setSprinkler(true, SPRINKLER_MANUAL_MAX_MS);
  else if (up == "SPRINKLER_OFF") setSprinkler(false, 0);
  else if (up == "FAN_ON")     { setFan(true);  if (autoMode) fanHoldUntil = holdFromNow(); }
  else if (up == "FAN_OFF")    { setFan(false); if (autoMode) fanHoldUntil = holdFromNow(); }
  else if (up == "LIGHT_ON") setLight(true, 0);
  else if (up == "LIGHT_OFF") setLight(false, 0);
  else if (up == "GET_STATUS") { sendStatus(); return; }
  else if (up.startsWith("SET_RTC=")) {
    // YYYY-MM-DD HH:MM:SS
    String ts = cmd.substring(8);
    Clock c{ts.substring(0, 4).toInt(), ts.substring(5, 7).toInt(), ts.substring(8, 10).toInt(),
            ts.substring(11, 13).toInt(), ts.substring(14, 16).toInt(), ts.substring(17, 19).toInt()};
    bool valid = c.year >= 2024 && c.month >= 1 && c.month <= 12 && c.day >= 1 && c.day <= 31 &&
                 c.hour < 24 && c.minute < 60 && c.second < 60;
    if (!valid) {
      Serial.println("RTC SET: bad time");
    } else {
      setSoftClock(c);   // the clock works from now on, RTC or not
      lastSchedMinute = -1;
      if (rtcWrite(c)) {
        rtcNeedsSync = false;
        Serial.println("RTC SET");
      } else {
        rtcNeedsSync = true;
        Serial.println("RTC not answering: time kept in memory, copied to the RTC when it is back");
      }
    }
  }
  else if (up.startsWith("SET_HUM_ON="))  { humOn = constrain(cmd.substring(11).toFloat(), 30, 100); saveSettings(); }
  else if (up.startsWith("SET_HUM_OFF=")) { humOff = constrain(cmd.substring(12).toFloat(), 30, 100); saveSettings(); }
  else if (up.startsWith("SET_CO2_ON="))  { co2On = constrain(cmd.substring(11).toInt(), 300, 10000); saveSettings(); }
  else if (up.startsWith("SET_CO2_OFF=")) { co2Off = constrain(cmd.substring(12).toInt(), 300, 10000); saveSettings(); }
  else if (up.startsWith("SET_SPR_SCHED=")) { applySchedule(sprSched, nSpr, cmd.substring(14)); saveSettings(); }
  else if (up == "CLEAR_SPR_SCHED") { clearScheds(sprSched, nSpr); saveSettings(); }
  else if (up.startsWith("SET_LGT_SCHED=")) { applySchedule(lgtSched, nLgt, cmd.substring(14)); saveSettings(); }
  else if (up == "CLEAR_LGT_SCHED") { clearScheds(lgtSched, nLgt); saveSettings(); }
  else if (up == "INFO") {
    Serial.printf("INFO dht good=%u bad=%u fresh=%d  co2 fresh=%d  rtc=%d softclock=%d  box=%d  float raw=%s\n",
                  dhtGood, dhtBad, dhtFresh(), co2Fresh(), rtcOk, swClockSet, boxPowered(),
                  floatRaw == LOW ? "LOW" : "HIGH");
    return;
  }
  else ok = false;

  if (ok) sendStatus();
  else Serial.println("UNKNOWN COMMAND");
}

// The HMI link picks up noise (bursts of non-ASCII bytes) and the HMI's own
// boot messages share its TX pin. Keep printable characters only, then start
// the command at the first known keyword so junk in front does not hide it.
const char *const COMMAND_WORDS[] = {
  "AUTO_", "MIST_", "REFILL_", "SPRINKLER_", "FAN_", "LIGHT_", "GET_STATUS",
  "SET_RTC=", "SET_HUM_", "SET_CO2_", "SET_SPR_SCHED=", "SET_LGT_SCHED=",
  "CLEAR_SPR_SCHED", "CLEAR_LGT_SCHED", "INFO",
};

void handleLine(String line) {
  String up = line;
  up.toUpperCase();
  int start = -1;
  for (const char *w : COMMAND_WORDS) {
    int i = up.indexOf(w);
    if (i >= 0 && (start < 0 || i < start)) start = i;
  }
  if (start < 0) {
    if (line.length()) Serial.println("IGNORED: " + line);
    return;
  }
  handleCommand(line.substring(start));
}

void readLines(Stream &in, String &buf) {
  while (in.available()) {
    int c = in.read();
    if (c == '\n') { handleLine(buf); buf = ""; }
    else if (c >= 0x20 && c <= 0x7E && buf.length() < 200) buf += (char)c;
  }
}

// =====================================================
// Setup / loop
// =====================================================
void setup() {
  // Outputs OFF before anything else, so no relay clicks on at boot.
  for (int p : OUTPUT_PINS) {
    digitalWrite(p, OUT_OFF);
    pinMode(p, OUTPUT);
    digitalWrite(p, OUT_OFF);
  }

  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("BODY BOOT");

  pinMode(FLOAT_PIN, INPUT_PULLUP);
  floatRaw = digitalRead(FLOAT_PIN);
  floatChangedAt = millis();
  lowWater = (floatRaw == LOW);

  pinMode(DHT_PIN, INPUT_PULLUP);

  Wire.begin(RTC_SDA_PIN, RTC_SCL_PIN);
  Wire.setTimeOut(20);   // a missing RTC must not stall the loop
  Clock c;
  rtcOk = getNow(c);
  Serial.println(rtcOk ? "RTC OK " + timeString() : String("RTC NOT FOUND"));

  prefs.begin("farm", false);
  loadSettings();

  co2Serial.begin(9600, SERIAL_8N1, CO2_RX_PIN, CO2_TX_PIN);
  hmiSerial.begin(115200, SERIAL_8N1, HMI_RX_PIN, HMI_TX_PIN);

  Serial.printf("BODY READY mode=%s\n", autoMode ? "AUTO" : "MANUAL");
}

void loop() {
  static String hmiBuf, usbBuf;
  readLines(hmiSerial, hmiBuf);
  readLines(Serial, usbBuf);

  static unsigned long lastSensor = 0, lastStatus = 0;
  unsigned long now = millis();

  readFloat();

  if (now - lastSensor >= SENSOR_PERIOD_MS) {
    lastSensor = now;
    readDht();
    pollCo2();
    runAuto();
    runSchedules();
  }
  runSafety();

  if (now - lastStatus >= STATUS_PERIOD_MS) {
    lastStatus = millis();
    sendStatus();
  }
  delay(5);
}
