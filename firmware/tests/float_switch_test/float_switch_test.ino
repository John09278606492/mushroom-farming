// Float switch (water level) test for the body ESP32.
//
// Wiring (same as the original firmware, esp_32_body.ino):
//   Float switch wire 1 -> GPIO18
//   Float switch wire 2 -> GND
//   No resistor needed: the pin uses the ESP32's internal pull-up.
//
// Reading: LOW = water is low, HIGH = water is OK.
// If it reads the opposite way, flip the float upside down on its stem
// (most floats can be mounted either way), or set INVERT_FLOAT to true.
//
// Open Serial Monitor at 115200 baud. Lift and drop the float by hand
// and watch the messages. The on-board LED (GPIO2) lights while water is low.
//
// Optional: set TEST_REFILL_RELAY to true to also switch the refill relay
// (GPIO13) like the real firmware does. Leave it false for the first test.

#define FLOAT_PIN          18
#define RELAY_REFILL_PIN   13
#define LED_PIN            2

#define RELAY_ON           HIGH   // same as the original firmware
#define RELAY_OFF          LOW

const bool INVERT_FLOAT       = false;
const bool TEST_REFILL_RELAY  = false;
const unsigned long DEBOUNCE_MS = 200;   // float bounces when water moves
const unsigned long REPORT_MS   = 2000;

bool lowWater = false;
bool lastRaw = false;
unsigned long rawChangedAt = 0;
unsigned long lastReport = 0;
unsigned long changes = 0;

bool readRawLow() {
  bool low = (digitalRead(FLOAT_PIN) == LOW);
  return INVERT_FLOAT ? !low : low;
}

void applyOutputs() {
  digitalWrite(LED_PIN, lowWater ? HIGH : LOW);
  if (TEST_REFILL_RELAY) {
    digitalWrite(RELAY_REFILL_PIN, lowWater ? RELAY_ON : RELAY_OFF);
  }
}

void printState(const char *why) {
  Serial.printf("[%7lu ms] %-8s pin=%s  ->  %s%s\n",
                millis(), why,
                digitalRead(FLOAT_PIN) == LOW ? "LOW " : "HIGH",
                lowWater ? "WATER LOW" : "water OK",
                TEST_REFILL_RELAY ? (lowWater ? "  (refill ON)" : "  (refill OFF)") : "");
}

void setup() {
  Serial.begin(115200);
  delay(300);
  pinMode(FLOAT_PIN, INPUT_PULLUP);
  pinMode(LED_PIN, OUTPUT);
  pinMode(RELAY_REFILL_PIN, OUTPUT);
  digitalWrite(RELAY_REFILL_PIN, RELAY_OFF);

  Serial.println();
  Serial.println("=== Float switch test (GPIO18) ===");
  Serial.println("Lift the float up, then let it drop. Watch for changes.");
  if (TEST_REFILL_RELAY) Serial.println("Refill relay test is ON (GPIO13).");

  lastRaw = readRawLow();
  lowWater = lastRaw;
  applyOutputs();
  printState("start");
}

void loop() {
  bool raw = readRawLow();
  if (raw != lastRaw) {
    lastRaw = raw;
    rawChangedAt = millis();
  }

  // Accept a new state only after it has been steady for DEBOUNCE_MS.
  if (raw != lowWater && millis() - rawChangedAt >= DEBOUNCE_MS) {
    lowWater = raw;
    changes++;
    applyOutputs();
    printState("CHANGED");
    Serial.printf("           total changes: %lu\n", changes);
  }

  if (millis() - lastReport >= REPORT_MS) {
    lastReport = millis();
    printState("status");
  }

  delay(10);
}
