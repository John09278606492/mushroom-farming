// Wi-Fi + Firebase Realtime Database sync for the body controller.
//
// Runs in its own FreeRTOS task on core 0, so slow HTTPS calls never stall
// the control loop or the HMI link on core 1. The two sides only meet here:
//   - the main loop hands over a Snapshot of its state (cloudPublish)
//   - the cloud task hands back plain text commands, the same ones the HMI
//     sends (cloudNextCommand), so the main loop applies them with its own
//     handleCommand and every safety rule still holds.
//
// Paths and fields follow docs/firebase-schema.md.
#pragma once
#include <Arduino.h>
#include "body_types.h"

struct Snapshot {
  bool  autoMode;
  bool  thFresh;   float humidity, temperature;
  bool  co2Fresh;  int co2ppm;
  bool  lowWater;
  bool  mist, refill, sprinkler, fan, light;
  bool  rtcOk;
  bool  boxPower;
  bool  refillTimedOut;
  char  time[24];  // "YYYY-MM-DD HH:MM:SS" or "" when unknown
  float humOn, humOff;
  int   co2On, co2Off;
  Schedule spr[MAX_SCHEDULES];
  Schedule lgt[MAX_SCHEDULES];
  int   nSpr, nLgt;
  // Bumped by the main loop when the HMI or USB changes these, so the cloud
  // task uploads them and the app shows the same values.
  uint32_t setpointsVer;
  uint32_t schedulesVer;
};

// Starts Wi-Fi and the sync task. Does nothing when secrets.h is missing.
void cloudBegin();

// Main loop: share the latest state (cheap, call every status cycle).
void cloudPublish(const Snapshot &s);

// Main loop: next command from the app, if any. Returns false when empty.
bool cloudNextCommand(char *buf, size_t len);

// Short state for logs and the STATUS line.
bool cloudWifiUp();
bool cloudOnline();          // signed in and the last Firebase call worked
const char *cloudStateText();

// ---------------- Wi-Fi settings from the HMI ----------------
// Wi-Fi state shown on the HMI.
enum WifiState { WIFI_NOT_SET = 0, WIFI_CONNECTING = 1, WIFI_CONNECTED = 2,
                 WIFI_WRONG_PASSWORD = 3, WIFI_NOT_FOUND = 4, WIFI_FAILED = 5,
                 WIFI_NO_IP = 6 };   // joined the router but it gave no address (login/registration Wi-Fi)
int cloudWifiState();
String cloudWifiName();      // the network in use ("" when none)
int cloudRssi();             // dBm, 0 when not connected

// Save new Wi-Fi details (kept across reboots) and connect to them.
void cloudSetWifi(const String &ssid, const String &password);

// Ask for a Wi-Fi scan; the result arrives later through cloudTakeScan as
// one ready-to-send line: "WIFI_LIST,<count>,<rssi>:<ssid hex>;..."
void cloudRequestScan();
bool cloudTakeScan(String &line);
