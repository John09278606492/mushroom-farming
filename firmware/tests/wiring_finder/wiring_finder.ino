// Wiring finder for the body ESP32.
// Use it when you don't know which GPIO goes to which part anymore.
//
// SAFETY FIRST:
//   - Unplug the pumps and the mist maker from their power (or take the
//     mist maker out of the water so it can't run dry). The relay LED and
//     click are enough to see which channel moves.
//   - Leave the sensors connected; this sketch only reads them.
//
// Open Serial Monitor at 115200 baud, line ending "Newline".
//
// 1) FIND INPUTS (float switch etc.) - starts automatically.
//    Every safe pin is read with a pull-up. Move the float up and down:
//    the pin that changes is printed, e.g. "GPIO18: HIGH -> LOW".
//
// 2) FIND OUTPUTS (relays/SSR) - type a pin number and press Enter, e.g. 13
//    That pin goes HIGH for 2 s, then LOW for 2 s, then back to input.
//    Watch which relay LED / channel clicks and write it down.
//    (Active-LOW relays turn ON during the LOW part instead.)
//
//    Type "s" to go back to scanning inputs.

const int PINS[] = {4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33};
const int N = sizeof(PINS) / sizeof(PINS[0]);
// Skipped on purpose: 0/2 (boot), 1/3 (USB serial), 6-11 (flash),
// 34-39 (input-only, no pull-up: they would read random noise).

int last[N];
String line;

void setAllInputs() {
  for (int i = 0; i < N; i++) {
    pinMode(PINS[i], INPUT_PULLUP);
  }
  delay(20);
  for (int i = 0; i < N; i++) last[i] = digitalRead(PINS[i]);
}

void printInputs() {
  Serial.print("Inputs now: ");
  for (int i = 0; i < N; i++) {
    Serial.printf("%d=%c ", PINS[i], last[i] ? 'H' : 'L');
  }
  Serial.println();
}

void pulseOutput(int pin) {
  bool ok = false;
  for (int i = 0; i < N; i++) if (PINS[i] == pin) ok = true;
  if (!ok) {
    Serial.printf("GPIO%d is not in the safe list.\n", pin);
    return;
  }
  Serial.printf(">>> GPIO%d HIGH for 2 s ... watch the relays\n", pin);
  pinMode(pin, OUTPUT);
  digitalWrite(pin, HIGH);
  delay(2000);
  Serial.printf(">>> GPIO%d LOW for 2 s\n", pin);
  digitalWrite(pin, LOW);
  delay(2000);
  pinMode(pin, INPUT_PULLUP);
  Serial.printf(">>> GPIO%d released. Which relay clicked? Write it down.\n", pin);
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("=== Wiring finder ===");
  Serial.println("Scanning inputs. Move the float switch up and down.");
  Serial.println("Type a GPIO number + Enter to pulse it as an output.");
  setAllInputs();
  printInputs();
}

void loop() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      line.trim();
      if (line == "s") {
        setAllInputs();
        printInputs();
      } else if (line.length()) {
        pulseOutput(line.toInt());
        setAllInputs();
      }
      line = "";
    } else {
      line += c;
    }
  }

  for (int i = 0; i < N; i++) {
    int v = digitalRead(PINS[i]);
    if (v != last[i]) {
      delay(30);  // ignore short bounces
      v = digitalRead(PINS[i]);
      if (v != last[i]) {
        Serial.printf("GPIO%d: %s -> %s\n", PINS[i], last[i] ? "HIGH" : "LOW", v ? "HIGH" : "LOW");
        last[i] = v;
      }
    }
  }
  delay(5);
}
