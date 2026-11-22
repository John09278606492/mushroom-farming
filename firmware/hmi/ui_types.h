// Types used by hmi.ino. They live in a header because the Arduino builder
// puts function prototypes above the code, before any struct in the .ino.
#pragma once
#include <lvgl.h>

#define MAX_SLOTS 5
struct Slot{bool used,en;int hr,mn,dur;bool days[7];};

enum SchedTarget{SCHED_SPR,SCHED_LGT};

// sensor card on the home page
struct SensorCard{lv_obj_t *val,*sub,*chipBox,*chipLbl,*bar;};

// device tile on the home page
// After a tap the switch shows the wanted state until the body confirms it
// (or holdUntil passes); the command is re-sent if the body has not obeyed.
struct Tile{lv_obj_t *card,*icon,*state,*sw;lv_color_t acc;unsigned long holdUntil;
            const char*onCmd;const char*offCmd;
            bool want;unsigned long sentAt;uint8_t retries;};

// device page (sprinkler, light, mist, fan)
struct DevUI{lv_obj_t *pg,*hero,*heroIcon,*state,*hint,*infoVal,*infoSub,*infoBar;lv_color_t acc;};
