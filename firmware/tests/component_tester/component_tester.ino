// Component tester for the body ESP32, driven from the PC over USB serial.
// Nothing is switched on at boot: every pin stays an input until a command
// drives it. Pin numbers are given in each command, so this works even when
// the wiring has changed.
//
// Serial: 115200 baud, one command per line. Replies start with "OK" or "ERR".
//
//   help                      list commands
//   info                      restart reason, chip, free memory
//   out <pin> <0|1>           drive a pin LOW/HIGH (relay, SSR, LED)
//   pulse <pin> <ms> [0|1]    drive a pin to a level for ms, then release it
//   release <pin|all>         make a pin (or every driven pin) an input again
//   in <pin>                  read a pin with pull-up (float switch etc.)
//   scan                      read every safe pin once
//   watch <pin|off>           report every change on a pin
//   dht <pin> [22|11]         read a DHT temperature/humidity sensor
//   co2 <rx> <tx>             read an MH-Z19 style UART CO2 sensor
//   i2c <sda> <scl>           list I2C devices (0x68 DS3231, 0x44 SHT31, 0x23 BH1750)
//   rtc <sda> <scl>           read the DS3231 time and temperature
//   sht <sda> <scl>           read an SHT31 sensor

#include <Wire.h>
#include <DHT.h>
#include <DHTesp.h>
#include <RTClib.h>

const int SAFE[] = {4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33};
const int NSAFE = sizeof(SAFE) / sizeof(SAFE[0]);
bool driven[40] = {false};

int watchPin = -1;
int watchLast = -1;
String line;

bool isSafe(int pin) {
  for (int i = 0; i < NSAFE; i++) if (SAFE[i] == pin) return true;
  return false;
}

// Input-only pins (34-39) can be read but never driven.
bool isReadable(int pin) { return isSafe(pin) || (pin >= 34 && pin <= 39); }

String word(const String &s, int n) {
  int idx = 0, start = 0;
  String t = s + " ";
  for (int i = 0; i < (int)t.length(); i++) {
    if (t[i] == ' ') {
      if (i > start) {
        if (idx == n) return t.substring(start, i);
        idx++;
      }
      start = i + 1;
    }
  }
  return "";
}

const char *resetReason() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON:  return "POWER_ON";
    case ESP_RST_SW:       return "SOFTWARE";
    case ESP_RST_PANIC:    return "CRASH";
    case ESP_RST_INT_WDT:
    case ESP_RST_TASK_WDT:
    case ESP_RST_WDT:      return "WATCHDOG";
    case ESP_RST_BROWNOUT: return "BROWNOUT";
    case ESP_RST_EXT:      return "RESET_BUTTON";
    default:               return "OTHER";
  }
}

void releasePin(int pin) {
  pinMode(pin, INPUT);
  driven[pin] = false;
}

void cmdOut(int pin, int level) {
  if (!isSafe(pin)) { Serial.printf("ERR GPIO%d is not safe to drive\n", pin); return; }
  pinMode(pin, OUTPUT);
  digitalWrite(pin, level ? HIGH : LOW);
  driven[pin] = true;
  Serial.printf("OK out GPIO%d=%s\n", pin, level ? "HIGH" : "LOW");
}

void cmdPulse(int pin, long ms, int level) {
  if (!isSafe(pin)) { Serial.printf("ERR GPIO%d is not safe to drive\n", pin); return; }
  if (ms < 1 || ms > 30000) { Serial.println("ERR ms must be 1..30000"); return; }
  pinMode(pin, OUTPUT);
  digitalWrite(pin, level ? HIGH : LOW);
  delay(ms);
  digitalWrite(pin, level ? LOW : HIGH);  // stay driven at the other level
  driven[pin] = true;
  Serial.printf("OK pulse GPIO%d %s %ldms, now %s\n", pin, level ? "HIGH" : "LOW", ms, level ? "LOW" : "HIGH");
}

void cmdIn(int pin) {
  if (!isReadable(pin)) { Serial.printf("ERR GPIO%d is not readable\n", pin); return; }
  if (driven[pin]) { Serial.printf("ERR GPIO%d is driven, release it first\n", pin); return; }
  pinMode(pin, pin >= 34 ? INPUT : INPUT_PULLUP);
  delay(5);
  Serial.printf("OK in GPIO%d=%s\n", pin, digitalRead(pin) ? "HIGH" : "LOW");
}

void cmdScan() {
  Serial.print("OK scan");
  for (int i = 0; i < NSAFE; i++) {
    int p = SAFE[i];
    if (driven[p]) { Serial.printf(" %d=OUT", p); continue; }
    pinMode(p, INPUT_PULLUP);
  }
  delay(10);
  for (int i = 0; i < NSAFE; i++) {
    int p = SAFE[i];
    if (!driven[p]) Serial.printf(" %d=%c", p, digitalRead(p) ? 'H' : 'L');
  }
  Serial.println();
}

void cmdDht(int pin, int type) {
  if (!isReadable(pin)) { Serial.printf("ERR GPIO%d is not readable\n", pin); return; }
  DHT dht(pin, type == 11 ? DHT11 : DHT22);
  dht.begin();
  delay(2200);  // the DHT needs ~2 s after start
  float h = dht.readHumidity();
  float t = dht.readTemperature();
  if (isnan(h) || isnan(t)) Serial.printf("ERR dht GPIO%d no reply (wrong pin, type or wiring)\n", pin);
  else Serial.printf("OK dht GPIO%d temp=%.1fC rh=%.1f%%\n", pin, t, h);
}

// Read a DHT22 several times with the DHTesp library and report the success rate.
void cmdDhtEsp(int pin, int tries) {
  if (!isReadable(pin)) { Serial.printf("ERR GPIO%d is not readable\n", pin); return; }
  if (tries < 1 || tries > 20) tries = 5;
  DHTesp d;
  d.setup(pin, DHTesp::DHT22);
  int ok = 0;
  for (int i = 0; i < tries; i++) {
    delay(d.getMinimumSamplingPeriod() + 100);
    TempAndHumidity v = d.getTempAndHumidity();
    if (d.getStatus() == DHTesp::ERROR_NONE) {
      ok++;
      Serial.printf("  try %d: temp=%.1fC rh=%.1f%%\n", i + 1, v.temperature, v.humidity);
    } else {
      Serial.printf("  try %d: %s\n", i + 1, d.getStatusString());
    }
  }
  Serial.printf("OK dhtx GPIO%d %d/%d good reads\n", pin, ok, tries);
}

// Read a DHT22/AM2302 by timing the raw pulses ourselves (no library).
// Prints the high-pulse widths so a bad signal can be told apart from bad timing.
void cmdDhtRaw(int pin, int tries) {
  if (!isReadable(pin)) { Serial.printf("ERR GPIO%d is not readable\n", pin); return; }
  if (tries < 1 || tries > 20) tries = 3;
  int good = 0;
  for (int k = 0; k < tries; k++) {
    delay(2500);
    const int MAXE = 240;
    uint16_t dur[MAXE];
    uint8_t lvl[MAXE];
    int n = 0;
    const uint32_t mhz = ESP.getCpuFreqMHz();
    static portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;

    pinMode(pin, OUTPUT);
    digitalWrite(pin, LOW);
    delay(2);                       // start signal: >1 ms low
    portENTER_CRITICAL(&mux);
    pinMode(pin, INPUT_PULLUP);
    int last = digitalRead(pin);
    uint32_t edge = esp_cpu_get_cycle_count();
    while (n < MAXE) {
      uint32_t now = esp_cpu_get_cycle_count();
      int v = digitalRead(pin);
      uint32_t us = (now - edge) / mhz;
      if (v != last) {
        dur[n] = us; lvl[n] = last; n++;
        edge = now; last = v;
      } else if (us > 300) {
        break;
      }
    }
    portEXIT_CRITICAL(&mux);

    // High intervals: [before response][response ~80us][40 data bits]
    // A slow edge can toggle a few times around the threshold, splitting one level
    // into pieces. Merge any piece shorter than 8 us (and the piece after it)
    // back into the level before it.
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
    // The data starts after the ~80 us response pulse; anything after the
    // 40th bit is ignored.
    uint16_t highs[60];
    int nh = 0;
    for (int i = 0; i < n && nh < 60; i++) if (lvl[i] == 1) highs[nh++] = dur[i];
    int startAt = -1;
    for (int i = 0; i < nh; i++) if (highs[i] >= 60 && highs[i] <= 110) { startAt = i + 1; break; }
    Serial.printf("  try %d: %d edges, %d highs, data from #%d\n", k + 1, n, nh, startAt);
    if (startAt < 0 || nh - startAt < 40) { Serial.println("    too few bits"); continue; }

    uint8_t b[5] = {0};
    for (int i = 0; i < 40; i++) {
      int bit = highs[startAt + i] > 48 ? 1 : 0;
      b[i / 8] = (b[i / 8] << 1) | bit;
    }
    bool ok = (uint8_t)(b[0] + b[1] + b[2] + b[3]) == b[4];
    float rh = ((b[0] << 8) | b[1]) / 10.0;
    float t = (((b[2] & 0x7F) << 8) | b[3]) / 10.0;
    if (b[2] & 0x80) t = -t;
    Serial.printf("    bytes %02X %02X %02X %02X %02X  checksum %s  temp=%.1fC rh=%.1f%%\n",
                  b[0], b[1], b[2], b[3], b[4], ok ? "OK" : "BAD", t, rh);
    if (ok) good++;
  }
  Serial.printf("OK dhtraw GPIO%d %d/%d good reads\n", pin, good, tries);
}

void cmdCo2(int rx, int tx) {
  if (!isReadable(rx) || !isSafe(tx)) { Serial.println("ERR bad pins"); return; }
  HardwareSerial co2(2);
  co2.begin(9600, SERIAL_8N1, rx, tx);
  delay(50);
  while (co2.available()) co2.read();
  const byte req[9] = {0xFF, 0x01, 0x86, 0, 0, 0, 0, 0, 0x79};
  co2.write(req, 9);
  byte r[9];
  int n = 0;
  unsigned long t0 = millis();
  while (n < 9 && millis() - t0 < 1500) if (co2.available()) r[n++] = co2.read();
  co2.end();
  if (n < 9) { Serial.printf("ERR co2 no reply on RX=%d TX=%d (got %d bytes; try swapping rx/tx)\n", rx, tx, n); return; }
  byte sum = 0;
  for (int i = 1; i < 8; i++) sum += r[i];
  sum = 0xFF - sum + 1;
  if (r[0] != 0xFF || r[1] != 0x86 || sum != r[8]) {
    Serial.print("ERR co2 bad reply, raw:");
    for (int i = 0; i < 9; i++) Serial.printf(" %02X", r[i]);
    Serial.println();
    return;
  }
  Serial.printf("OK co2 ppm=%d\n", r[2] * 256 + r[3]);
}

bool startI2c(int sda, int scl) {
  if (!isSafe(sda) || !isSafe(scl)) { Serial.println("ERR bad pins"); return false; }
  Wire.end();
  Wire.begin(sda, scl);
  return true;
}

void cmdI2c(int sda, int scl) {
  if (!startI2c(sda, scl)) return;
  Serial.print("OK i2c");
  int found = 0;
  for (byte a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) { Serial.printf(" 0x%02X", a); found++; }
  }
  if (!found) Serial.print(" none");
  Serial.println();
}

void cmdRtc(int sda, int scl) {
  if (!startI2c(sda, scl)) return;
  RTC_DS3231 rtc;
  if (!rtc.begin(&Wire)) { Serial.println("ERR rtc not found"); return; }
  DateTime n = rtc.now();
  Serial.printf("OK rtc %04d-%02d-%02d %02d:%02d:%02d temp=%.2fC lostPower=%d\n",
                n.year(), n.month(), n.day(), n.hour(), n.minute(), n.second(),
                rtc.getTemperature(), rtc.lostPower() ? 1 : 0);
}

// rtcset <sda> <scl> <year> <month> <day> <hour> <minute> <second>
void cmdRtcSet(int sda, int scl, int y, int mo, int d, int h, int mi, int s) {
  if (!startI2c(sda, scl)) return;
  RTC_DS3231 rtc;
  if (!rtc.begin(&Wire)) { Serial.println("ERR rtc not found"); return; }
  if (y < 2024 || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 59) {
    Serial.println("ERR bad date/time");
    return;
  }
  rtc.adjust(DateTime(y, mo, d, h, mi, s));
  DateTime n = rtc.now();
  Serial.printf("OK rtcset now %04d-%02d-%02d %02d:%02d:%02d lostPower=%d\n",
                n.year(), n.month(), n.day(), n.hour(), n.minute(), n.second(),
                rtc.lostPower() ? 1 : 0);
}

void cmdSht(int sda, int scl) {
  if (!startI2c(sda, scl)) return;
  for (byte addr : {0x44, 0x45}) {
    Wire.beginTransmission(addr);
    Wire.write(0x24);
    Wire.write(0x00);
    if (Wire.endTransmission() != 0) continue;
    delay(20);
    if (Wire.requestFrom((int)addr, 6) != 6) continue;
    byte d[6];
    for (int i = 0; i < 6; i++) d[i] = Wire.read();
    float t = -45 + 175.0 * ((d[0] << 8) | d[1]) / 65535.0;
    float h = 100.0 * ((d[3] << 8) | d[4]) / 65535.0;
    Serial.printf("OK sht 0x%02X temp=%.1fC rh=%.1f%%\n", addr, t, h);
    return;
  }
  Serial.println("ERR sht not found");
}

// Pins that are not relay outputs, used when searching for a sensor.
const int SEARCH[] = {4, 5, 14, 15, 16, 17, 18, 21, 22, 26, 27, 32, 33};
const int NSEARCH = sizeof(SEARCH) / sizeof(SEARCH[0]);

// Try every SDA/SCL pair and report any I2C device found.
void cmdI2cFind() {
  int hits = 0;
  for (int i = 0; i < NSEARCH; i++) {
    for (int j = 0; j < NSEARCH; j++) {
      if (i == j) continue;
      int sda = SEARCH[i], scl = SEARCH[j];
      if (driven[sda] || driven[scl]) continue;
      Wire.end();
      Wire.begin(sda, scl);
      Wire.setTimeOut(20);
      for (byte a = 1; a < 127; a++) {
        Wire.beginTransmission(a);
        if (Wire.endTransmission() == 0) {
          Serial.printf("FOUND i2c 0x%02X on SDA=%d SCL=%d\n", a, sda, scl);
          hits++;
        }
      }
    }
  }
  Wire.end();
  for (int i = 0; i < NSEARCH; i++) if (!driven[SEARCH[i]]) pinMode(SEARCH[i], INPUT);
  Serial.printf("OK i2cfind done, %d hit(s)\n", hits);
}

// Try a DHT22 and a DHT11 on every search pin.
void cmdDhtFind() {
  int hits = 0;
  for (int i = 0; i < NSEARCH; i++) {
    int p = SEARCH[i];
    if (driven[p]) continue;
    for (int type : {22, 11}) {
      DHT dht(p, type == 11 ? DHT11 : DHT22);
      dht.begin();
      delay(2200);
      float h = dht.readHumidity(), t = dht.readTemperature();
      if (!isnan(h) && !isnan(t)) {
        Serial.printf("FOUND dht%d GPIO%d temp=%.1fC rh=%.1f%%\n", type, p, t, h);
        hits++;
        break;
      }
    }
    pinMode(p, INPUT);
  }
  Serial.printf("OK dhtfind done, %d hit(s)\n", hits);
}

// Bit-banged I2C address scan that does not use the Wire library at all.
static int swSda, swScl;
static void swRelease(int p) { pinMode(p, INPUT_PULLUP); }
static void swLow(int p) { pinMode(p, OUTPUT); digitalWrite(p, LOW); }
static void swDelay() { delayMicroseconds(10); }  // ~50 kHz
static void swStart() { swRelease(swSda); swRelease(swScl); swDelay(); swLow(swSda); swDelay(); swLow(swScl); swDelay(); }
static void swStop() { swLow(swSda); swDelay(); swRelease(swScl); swDelay(); swRelease(swSda); swDelay(); }
static bool swWrite(uint8_t b) {
  for (int i = 7; i >= 0; i--) {
    if (b & (1 << i)) swRelease(swSda); else swLow(swSda);
    swDelay(); swRelease(swScl); swDelay(); swLow(swScl);
  }
  swRelease(swSda); swDelay(); swRelease(swScl); swDelay();
  bool ack = digitalRead(swSda) == LOW;
  swLow(swScl); swDelay();
  return ack;
}

void cmdSwI2c(int sda, int scl) {
  if (!isSafe(sda) || !isSafe(scl)) { Serial.println("ERR bad pins"); return; }
  Wire.end();
  swSda = sda; swScl = scl;
  swRelease(sda); swRelease(scl);
  delay(2);
  Serial.printf("  idle levels: SDA=%d SCL=%d (both should be 1)\n", digitalRead(sda), digitalRead(scl));
  Serial.print("OK swi2c");
  int found = 0;
  for (uint8_t a = 0x08; a < 0x78; a++) {
    swStart();
    bool ack = swWrite(a << 1);
    swStop();
    if (ack) { Serial.printf(" 0x%02X", a); found++; }
  }
  if (!found) Serial.print(" none");
  Serial.println();
  pinMode(sda, INPUT); pinMode(scl, INPUT);
}

void help() {
  Serial.println("OK commands: info | out <pin> <0|1> | pulse <pin> <ms> [0|1] | release <pin|all> |");
  Serial.println("   in <pin> | scan | watch <pin|off> | dht <pin> [22|11] | co2 <rx> <tx> |");
  Serial.println("   i2c <sda> <scl> | rtc <sda> <scl> | sht <sda> <scl>");
}

void handle(String s) {
  s.trim();
  s.toLowerCase();
  if (!s.length()) return;
  String c = word(s, 0);
  int a = word(s, 1).toInt();
  int b = word(s, 2).toInt();
  String w1 = word(s, 1), w2 = word(s, 2), w3 = word(s, 3);

  if (c == "help") help();
  else if (c == "info") Serial.printf("OK info reset=%s chip=%s heap=%u\n", resetReason(), ESP.getChipModel(), ESP.getFreeHeap());
  else if (c == "out" && w2.length()) cmdOut(a, b);
  else if (c == "pulse" && w2.length()) cmdPulse(a, w2.toInt(), w3.length() ? w3.toInt() : 1);
  else if (c == "release" && w1 == "all") {
    for (int p = 0; p < 40; p++) if (driven[p]) releasePin(p);
    Serial.println("OK released all");
  }
  else if (c == "release" && w1.length()) { releasePin(a); Serial.printf("OK released GPIO%d\n", a); }
  else if (c == "in" && w1.length()) cmdIn(a);
  else if (c == "scan") cmdScan();
  else if (c == "watch" && w1 == "off") { watchPin = -1; Serial.println("OK watch off"); }
  else if (c == "watch" && w1.length()) {
    if (!isReadable(a)) { Serial.println("ERR bad pin"); return; }
    watchPin = a;
    pinMode(a, a >= 34 ? INPUT : INPUT_PULLUP);
    delay(5);
    watchLast = digitalRead(a);
    Serial.printf("OK watch GPIO%d now=%s\n", a, watchLast ? "HIGH" : "LOW");
  }
  else if (c == "dht" && w1.length()) cmdDht(a, w2.length() ? b : 22);
  else if (c == "dhtx" && w1.length()) cmdDhtEsp(a, w2.length() ? b : 5);
  else if (c == "dhtraw" && w1.length()) cmdDhtRaw(a, w2.length() ? b : 3);
  else if (c == "co2" && w2.length()) cmdCo2(a, b);
  else if (c == "i2c" && w2.length()) cmdI2c(a, b);
  else if (c == "rtc" && w2.length()) cmdRtc(a, b);
  else if (c == "sht" && w2.length()) cmdSht(a, b);
  else if (c == "i2cfind") cmdI2cFind();
  else if (c == "swi2c" && w2.length()) cmdSwI2c(a, b);
  else if (c == "rtcset" && word(s, 8).length())
    cmdRtcSet(a, b, word(s, 3).toInt(), word(s, 4).toInt(), word(s, 5).toInt(),
              word(s, 6).toInt(), word(s, 7).toInt(), word(s, 8).toInt());
  else if (c == "dhtfind") cmdDhtFind();
  else Serial.printf("ERR unknown command: %s (type help)\n", s.c_str());
}

// Relay/SSR pins from the original firmware (all switch ON with HIGH).
// They are driven LOW right at boot: a floating or pulled-up input is
// enough to switch an active-HIGH relay on.
const int RELAY_PINS[] = {12, 13, 19, 23, 25};

void setup() {
  for (int p : RELAY_PINS) {
    pinMode(p, OUTPUT);
    digitalWrite(p, LOW);
    driven[p] = true;
  }
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.printf("TESTER READY reset=%s\n", resetReason());
  help();
}

void loop() {
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\n' || ch == '\r') { handle(line); line = ""; }
    else if (line.length() < 80) line += ch;
  }
  if (watchPin >= 0) {
    int v = digitalRead(watchPin);
    if (v != watchLast) {
      delay(30);
      v = digitalRead(watchPin);
      if (v != watchLast) {
        Serial.printf("CHANGE GPIO%d %s -> %s\n", watchPin, watchLast ? "HIGH" : "LOW", v ? "HIGH" : "LOW");
        watchLast = v;
      }
    }
  }
  delay(2);
}
