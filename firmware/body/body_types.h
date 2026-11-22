// Types used by body.ino. They live in a header because the Arduino builder
// puts its generated function prototypes above any struct in the .ino.
#pragma once
#include <stdint.h>

#define MAX_SCHEDULES 5

struct Schedule {
  bool     enabled;
  uint8_t  hour;
  uint8_t  minute;
  uint16_t duration;      // sprinkler: minutes, light: hours
  bool     days[7];       // 0 = Sunday
};

struct Clock { int year, month, day, hour, minute, second; };
