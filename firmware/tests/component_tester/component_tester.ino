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
  else if (c == "co2" && w2.length()) cmdCo2(a, b);
  else if (c == "i2c" && w2.length()) cmdI2c(a, b);
  else if (c == "rtc" && w2.length()) cmdRtc(a, b);
  else if (c == "sht" && w2.length()) cmdSht(a, b);
  else if (c == "i2cfind") cmdI2cFind();
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
