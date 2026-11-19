// Refill pump debug for the body ESP32.
// Finds out why the refill pump turns on by itself.
//
// Wiring (same as the original firmware):
//   Float switch: GPIO18 and GND
//   Refill relay IN: GPIO13   (relay VCC 5V, GND to ESP32 GND)
//
// Open Serial Monitor at 115200 baud and type a command, then press Enter:
//   0  relay OFF         (pump must stop)
//   1  relay ON          (pump must run)
//   a  auto: pump follows the float (water low = pump ON)
//   m  manual: pump ignores the float (starts here, relay OFF)
//   i  flip relay logic (active-HIGH <-> active-LOW) and test again
//
// The sketch also prints:
//   - why the ESP32 last restarted (BROWNOUT = power dip when the pump starts)
//   - every float change, and "glitches" (changes shorter than 200 ms = noise)

#define FLOAT_PIN         18
#define RELAY_REFILL_PIN  13

const unsigned long DEBOUNCE_MS = 200;

bool relayActiveHigh = true;   // original firmware: RELAY_ON = HIGH
bool autoMode = false;
bool relayOn = false;

bool lowWater = false;
bool lastRaw = false;
unsigned long rawChangedAt = 0;
unsigned long glitches = 0;
unsigned long lastStatus = 0;

const char *resetReasonText() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON:  return "POWER ON (normal)";
    case ESP_RST_SW:       return "SOFTWARE restart";
    case ESP_RST_PANIC:    return "CRASH (panic)";
    case ESP_RST_INT_WDT:
    case ESP_RST_TASK_WDT:
    case ESP_RST_WDT:      return "WATCHDOG (code froze)";
    case ESP_RST_BROWNOUT: return "BROWNOUT (voltage dropped! check power)";
    case ESP_RST_EXT:      return "EN/RESET button";
    default:               return "other";
  }
}

void writeRelay(bool on) {
  relayOn = on;
  bool level = relayActiveHigh ? on : !on;
  digitalWrite(RELAY_REFILL_PIN, level ? HIGH : LOW);
  Serial.printf("  relay %s  (GPIO13 = %s, %s)\n",
                on ? "ON " : "OFF", level ? "HIGH" : "LOW",
                relayActiveHigh ? "active-HIGH" : "active-LOW");
}

bool readRawLow() { return digitalRead(FLOAT_PIN) == LOW; }

void printStatus() {
  Serial.printf("[%6lus] float pin=%s -> %s | mode=%s | relay=%s | glitches=%lu\n",
                millis() / 1000,
                readRawLow() ? "LOW " : "HIGH",
                lowWater ? "WATER LOW" : "water OK ",
                autoMode ? "AUTO  " : "MANUAL",
                relayOn ? "ON " : "OFF",
                glitches);
}

void setup() {
  // Drive the relay OFF as early as possible.
  pinMode(RELAY_REFILL_PIN, OUTPUT);
  digitalWrite(RELAY_REFILL_PIN, relayActiveHigh ? LOW : HIGH);
  pinMode(FLOAT_PIN, INPUT_PULLUP);

  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("=== Refill pump debug ===");
  Serial.printf("Last restart: %s\n", resetReasonText());
  Serial.println("Commands: 0=OFF 1=ON a=auto m=manual i=flip relay logic");
  Serial.println("Starting in MANUAL with the relay OFF. The pump must be stopped now.");

  lastRaw = readRawLow();
  lowWater = lastRaw;
  writeRelay(false);
  printStatus();
}

void handleCommand(char c) {
  switch (c) {
    case '0': autoMode = false; Serial.println("> manual, OFF"); writeRelay(false); break;
    case '1': autoMode = false; Serial.println("> manual, ON");  writeRelay(true);  break;
    case 'a': autoMode = true;  Serial.println("> AUTO: pump follows the float"); writeRelay(lowWater); break;
    case 'm': autoMode = false; Serial.println("> manual, OFF"); writeRelay(false); break;
    case 'i':
      relayActiveHigh = !relayActiveHigh;
      Serial.printf("> relay logic is now %s\n", relayActiveHigh ? "active-HIGH" : "active-LOW");
      writeRelay(relayOn);
      break;
    default: return;
  }
  printStatus();
}

void loop() {
  while (Serial.available()) handleCommand((char)tolower(Serial.read()));

  bool raw = readRawLow();
  if (raw != lastRaw) {
    // A change that flips back before DEBOUNCE_MS is counted as a glitch.
    if (millis() - rawChangedAt < DEBOUNCE_MS) glitches++;
    lastRaw = raw;
    rawChangedAt = millis();
  }

  if (raw != lowWater && millis() - rawChangedAt >= DEBOUNCE_MS) {
    lowWater = raw;
    Serial.printf("FLOAT CHANGED -> %s\n", lowWater ? "WATER LOW" : "water OK");
    if (autoMode) writeRelay(lowWater);
    printStatus();
  }

  if (millis() - lastStatus >= 3000) {
    lastStatus = millis();
    printStatus();
  }
  delay(5);
}
