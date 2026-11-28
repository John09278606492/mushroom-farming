// Wi-Fi + Firebase Realtime Database sync. See cloud.h for how it fits in.
#include "cloud.h"

#if __has_include("secrets.h")
#include "secrets.h"
#define CLOUD_ENABLED 1
#else
#define CLOUD_ENABLED 0
#endif

#if !CLOUD_ENABLED

void cloudBegin() { Serial.println("CLOUD: no secrets.h, Wi-Fi off"); }
void cloudPublish(const Snapshot &) {}
bool cloudNextCommand(char *, size_t) { return false; }
bool cloudWifiUp() { return false; }
bool cloudOnline() { return false; }
const char *cloudStateText() { return "off"; }
int cloudWifiState() { return WIFI_NOT_SET; }
String cloudWifiName() { return ""; }
int cloudRssi() { return 0; }
void cloudSetWifi(const String &, const String &) {}
void cloudRequestScan() {}
bool cloudTakeScan(String &) { return false; }

#else

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <time.h>

static const char *FW_VERSION = "body-1.6";

// ---------------- timing ----------------
static const uint32_t LIVE_EVERY_MS      = 15000;   // heartbeat; changes go at once
static const uint32_t CONTROL_EVERY_MS   = 30000;   // fallback; the stream rings at once
static const uint32_t CONFIG_EVERY_MS    = 30000;   // setpoints + schedules
static const uint32_t HISTORY_EVERY_MS   = 10UL * 60 * 1000;
static const uint32_t NTP_EVERY_MS       = 6UL * 3600 * 1000;
static const uint32_t WIFI_RETRY_MS      = 30000;

// ---------------- shared with the main loop ----------------
static SemaphoreHandle_t snapMutex;
static Snapshot snap;
static bool haveSnap = false;
static QueueHandle_t cmdQueue;
static const int CMD_LEN = 64;

static volatile bool wifiUp = false;
static volatile bool online = false;
static volatile const char *stateText = "starting";

// Wi-Fi settings: from the HMI (saved in flash), else from secrets.h.
static SemaphoreHandle_t wifiMutex;
static String wifiSsid, wifiPass;          // in use
static String newSsid, newPass;            // waiting to be applied
static volatile bool haveNewWifi = false;
static volatile int wifiState = WIFI_NOT_SET;
static volatile bool scanWanted = false;
static String scanResult;                  // guarded by wifiMutex
static volatile bool scanReady = false;
static volatile uint8_t lastDisconnectReason = 0;
static volatile uint32_t linkUpAt = 0;     // joined the router, waiting for an address

// ---------------- cloud task state ----------------
static WiFiClientSecure dbTls, authTls;
static HTTPClient http;
static Preferences cprefs;

static String idToken, refreshToken;
static uint32_t tokenExpiresAt = 0;     // millis()

static bool controlSeen = false;        // first read after boot only records
static double modeAt = 0;
static double deviceAt[5] = {0, 0, 0, 0, 0};
static const char *DEVICE_KEYS[5] = {"mist", "fan", "refill", "sprinkler", "light"};
static const char *DEVICE_CMDS[5] = {"MIST", "FAN", "REFILL", "SPRINKLER", "LIGHT"};

static uint32_t uploadedSetpointsVer = 0, uploadedSchedulesVer = 0;

// =====================================================
// Small helpers
// =====================================================
static void pushCommand(const String &c) {
  char buf[CMD_LEN];
  strncpy(buf, c.c_str(), CMD_LEN - 1);
  buf[CMD_LEN - 1] = 0;
  xQueueSend(cmdQueue, buf, 0);
}

static bool getSnap(Snapshot &out) {
  if (xSemaphoreTake(snapMutex, pdMS_TO_TICKS(100)) != pdTRUE) return false;
  bool ok = haveSnap;
  if (ok) out = snap;
  xSemaphoreGive(snapMutex);
  return ok;
}

static uint32_t fnv1a(const String &s) {
  uint32_t h = 2166136261u;
  for (size_t i = 0; i < s.length(); i++) { h ^= (uint8_t)s[i]; h *= 16777619u; }
  return h;
}

// =====================================================
// Sign-in (Firebase Auth REST)
// =====================================================
static bool authPost(const String &url, const String &body, const char *contentType, JsonDocument &doc) {
  HTTPClient a;
  a.setTimeout(10000);
  if (!a.begin(authTls, url)) return false;
  a.addHeader("Content-Type", contentType);
  int code = a.POST(body);
  String resp = a.getString();
  a.end();
  if (code != 200) {
    Serial.printf("CLOUD: sign-in failed (%d) %s\n", code, resp.substring(0, 160).c_str());
    return false;
  }
  return deserializeJson(doc, resp) == DeserializationError::Ok;
}

static bool signIn() {
  JsonDocument doc;
  JsonDocument req;
  req["email"] = FB_EMAIL;
  req["password"] = FB_PASSWORD;
  req["returnSecureToken"] = true;
  String body;
  serializeJson(req, body);
  String url = String("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=") + FB_API_KEY;
  if (!authPost(url, body, "application/json", doc)) return false;
  idToken = (const char *)(doc["idToken"] | "");          // copy into the reserved buffer
  refreshToken = (const char *)(doc["refreshToken"] | "");
  uint32_t secs = doc["expiresIn"].as<String>().toInt();
  tokenExpiresAt = millis() + (secs > 300 ? secs - 300 : 60) * 1000UL;
  Serial.println("CLOUD: signed in");
  return idToken.length() > 0;
}

static bool refreshSignIn() {
  if (refreshToken.isEmpty()) return signIn();
  JsonDocument doc;
  String url = String("https://securetoken.googleapis.com/v1/token?key=") + FB_API_KEY;
  String body = "grant_type=refresh_token&refresh_token=" + refreshToken;
  if (!authPost(url, body, "application/x-www-form-urlencoded", doc)) return signIn();
  idToken = (const char *)(doc["id_token"] | "");
  refreshToken = (const char *)(doc["refresh_token"] | "");
  uint32_t secs = doc["expires_in"].as<String>().toInt();
  tokenExpiresAt = millis() + (secs > 300 ? secs - 300 : 60) * 1000UL;
  return idToken.length() > 0;
}

static bool ensureAuth() {
  if (idToken.length() && (int32_t)(millis() - tokenExpiresAt) < 0) return true;
  bool ok = idToken.length() ? refreshSignIn() : signIn();
  if (!ok) { idToken = ""; refreshToken = ""; }
  return ok;
}

// =====================================================
// Realtime Database REST
// =====================================================
static uint32_t failStreak = 0;   // Firebase calls failed in a row

// Returns the HTTP code (negative on a connection error).
static int db(const char *method, const String &path, const String &body, String *out) {
  String url = String(FB_DB_URL) + "/farm1/" + path + ".json?auth=" + idToken;
  // Writes don't need the data echoed back (204 No Content, less to read).
  if (strcmp(method, "GET")) url += "&print=silent";
  // A fresh connection for every call. Re-using one kept-alive HTTPS
  // connection is what made calls hang ("read timeout" -11, then -1): the
  // ESP32 can't tell when the other side has quietly dropped it.
  http.setReuse(false);
  http.setTimeout(3000);   // Firebase answers in 0.1-0.3 s; waiting longer only delays the retry
  http.setConnectTimeout(3000);
  int code = -1;
  // A connection that fails to open (-1) or hangs (-11) is retried at once
  // with a fresh one, so one bad moment doesn't cost a whole cycle.
  for (int attempt = 0; attempt < 2; attempt++) {
    if (attempt) vTaskDelay(pdMS_TO_TICKS(150));
    if (!http.begin(dbTls, url)) { code = -1; continue; }
    if (!strcmp(method, "GET")) code = http.GET();
    else if (!strcmp(method, "PUT")) code = http.PUT(body);
    else if (!strcmp(method, "POST")) code = http.POST(body);
    else code = http.sendRequest(method, body);
    if (out) *out = code > 0 ? http.getString() : String();
    else if (code > 0) http.getString();
    http.end();
    dbTls.stop();
    if (code > 0) break;
  }
  if (code == 204) code = 200;     // print=silent: written, nothing to return
  if (code == 401) idToken = "";   // token rejected: sign in again
  if (code <= 0) {
    // The kept-alive HTTPS connection died (router or server closed it):
    // drop it so the next call opens a fresh one instead of failing forever.
    dbTls.stop();
  }
  if (code == 200) {
    failStreak = 0;
  } else {
    failStreak++;
    static int lastCode = 0;
    static uint32_t lastLog = 0;
    if (code != lastCode || millis() - lastLog > 30000) {
      lastCode = code;
      lastLog = millis();
      // Free memory and the biggest free block: a TLS connection needs a
      // large block, so a small one here means memory, not the internet.
      Serial.printf("CLOUD: %s %s -> %d (streak %u, heap %u, biggest block %u, rssi %d)\n", method,
                    path.c_str(), code, failStreak, ESP.getFreeHeap(), ESP.getMaxAllocHeap(), WiFi.RSSI());
    }
  }
  online = (code == 200);
  return code;
}

// =====================================================
// Up: live, history, local changes
// =====================================================
static bool putLive(const Snapshot &s) {
  JsonDocument d;
  d["updatedAt"][".sv"] = "timestamp";
  if (s.thFresh) { d["temp"] = s.temperature; d["rh"] = s.humidity; }
  else { d["temp"] = nullptr; d["rh"] = nullptr; }
  d["co2"] = s.co2Fresh ? s.co2ppm : -1;
  d["lowWater"] = s.lowWater;
  d["mode"] = s.autoMode ? "auto" : "manual";
  JsonObject dev = d["devices"].to<JsonObject>();
  dev["mist"] = s.mist;
  dev["fan"] = s.fan;
  dev["refill"] = s.refill;
  dev["sprinkler"] = s.sprinkler;
  dev["light"] = s.light;
  if (s.time[0]) d["rtc"] = s.time;
  d["rssi"] = WiFi.RSSI();
  d["fw"] = FW_VERSION;
  d["boxPower"] = s.boxPower;
  d["refillTimedOut"] = s.refillTimedOut;
  d["heap"] = ESP.getFreeHeap();
  d["heapBlock"] = ESP.getMaxAllocHeap();
  d["uptimeMin"] = millis() / 60000;
  JsonObject sens = d["sensors"].to<JsonObject>();
  sens["th"] = s.thFresh;
  sens["co2"] = s.co2Fresh;
  sens["rtc"] = s.rtcOk;
  String body;
  serializeJson(d, body);
  return db("PUT", "live", body, nullptr) == 200;
}

static void postHistory(const Snapshot &s) {
  if (!s.thFresh && !s.co2Fresh) return;   // nothing worth saving
  JsonDocument d;
  d["ts"][".sv"] = "timestamp";
  if (s.thFresh) { d["temp"] = s.temperature; d["rh"] = s.humidity; }
  if (s.co2Fresh) d["co2"] = s.co2ppm;
  String body;
  serializeJson(d, body);
  db("POST", "history", body, nullptr);
}

static void schedToJson(JsonObject o, const Schedule &x, bool hours) {
  o["enabled"] = x.enabled;
  o["hour"] = x.hour;
  o["minute"] = x.minute;
  o[hours ? "durationHr" : "durationMin"] = x.duration;
  JsonArray days = o["days"].to<JsonArray>();
  for (int d = 0; d < 7; d++) days.add(x.days[d]);
}

// Setpoints changed on the HMI: send them up. tempMin/tempMax/stage are
// app-only and stay as they are (PATCH).
static bool uploadSetpoints(const Snapshot &s) {
  JsonDocument d;
  d["humOn"] = s.humOn;
  d["humOff"] = s.humOff;
  d["co2On"] = s.co2On;
  d["co2Off"] = s.co2Off;
  d["updatedAt"][".sv"] = "timestamp";
  String body;
  serializeJson(d, body);
  return db("PATCH", "setpoints", body, nullptr) == 200;
}

static bool uploadSchedules(const Snapshot &s) {
  JsonDocument d;
  JsonObject spr = d["sprinkler"].to<JsonObject>();
  JsonObject lgt = d["light"].to<JsonObject>();
  for (int i = 0; i < s.nSpr; i++) {
    if (!s.spr[i].enabled && s.spr[i].hour == 0 && s.spr[i].minute == 0) continue;   // empty slot
    schedToJson(spr[String(i)].to<JsonObject>(), s.spr[i], false);
  }
  for (int i = 0; i < s.nLgt; i++) {
    if (!s.lgt[i].enabled && s.lgt[i].hour == 0 && s.lgt[i].minute == 0) continue;
    schedToJson(lgt[String(i)].to<JsonObject>(), s.lgt[i], true);
  }
  String body;
  serializeJson(d, body);
  return db("PUT", "schedules", body, nullptr) == 200;
}

// =====================================================
// Down: control, setpoints, schedules
// =====================================================
// The app writes control/devices/<name> plus control/at/<name> (server time)
// for each tap, and control/mode plus control/modeAt. A command is applied
// only when its time changes, so an old value is never replayed and nothing
// switches by itself after a reboot.
// Mirror of farm1/control in plain variables (no JSON kept in memory, so it
// never grows into the middle of the heap), updated by the stream and the
// fallback read.
struct ControlMirror {
  bool autoMode = false;
  double modeAt = 0;
  bool devices[5] = {false, false, false, false, false};
  double at[5] = {0, 0, 0, 0, 0};
  bool seen = false;          // anything received yet
};
static ControlMirror ctl;
static volatile bool controlDoorbell = false;   // fetch control with a normal read

static int deviceIndex(const char *key) {
  for (int i = 0; i < 5; i++) if (!strcmp(key, DEVICE_KEYS[i])) return i;
  return -1;
}

// Apply whatever changed (commands whose timestamp moved).
static void applyControl() {
  if (!ctl.seen) { controlSeen = true; return; }
  if (controlSeen && ctl.modeAt > 0 && ctl.modeAt != modeAt) pushCommand(ctl.autoMode ? "AUTO_ON" : "AUTO_OFF");
  modeAt = ctl.modeAt;

  for (int i = 0; i < 5; i++) {
    double at = ctl.at[i];
    if (controlSeen && at > 0 && at != deviceAt[i]) {
      pushCommand(String(DEVICE_CMDS[i]) + (ctl.devices[i] ? "_ON" : "_OFF"));
      // How long from the tap in the app (server time) to here (NTP time).
      struct timeval tv;
      gettimeofday(&tv, nullptr);
      double nowMs = (double)tv.tv_sec * 1000.0 + tv.tv_usec / 1000;
      if (tv.tv_sec > 1700000000) Serial.printf("CLOUD: %s from the app arrived %.0f ms after the tap\n", DEVICE_KEYS[i], nowMs - at);
    }
    deviceAt[i] = at;
  }
  if (!controlSeen) Serial.println("CLOUD: control read (old commands not replayed)");
  controlSeen = true;
}

// Store one value at a control path like "devices/fan", "at/fan", "mode".
static void setControl(const String &path, JsonVariantConst v) {
  String p = path;
  while (p.startsWith("/")) p.remove(0, 1);
  if (p.isEmpty()) {                               // the whole node
    ControlMirror fresh;
    fresh.seen = true;
    ctl = fresh;
    if (v.isNull()) return;
    for (JsonPairConst kv : v.as<JsonObjectConst>()) setControl(kv.key().c_str(), kv.value());
    ctl.seen = true;
    return;
  }
  ctl.seen = true;
  int slash = p.indexOf('/');
  String head = slash < 0 ? p : p.substring(0, slash);
  String rest = slash < 0 ? "" : p.substring(slash + 1);
  if (head == "mode") ctl.autoMode = !strcmp(v | "", "auto");
  else if (head == "modeAt") ctl.modeAt = v | 0.0;
  else if (head == "devices" || head == "at") {
    if (rest.isEmpty()) {                          // the whole devices/at object
      for (JsonPairConst kv : v.as<JsonObjectConst>()) setControl(head + "/" + kv.key().c_str(), kv.value());
      return;
    }
    int i = deviceIndex(rest.c_str());
    if (i < 0) return;
    if (head == "devices") ctl.devices[i] = v | false;
    else ctl.at[i] = v | 0.0;
  }
}

static void readControl() {
  String resp;
  if (db("GET", "control", "", &resp) != 200) return;
  JsonDocument d;
  if (deserializeJson(d, resp) != DeserializationError::Ok) return;
  setControl("/", d.as<JsonVariantConst>());
  applyControl();
}

// One "data:" line of a put/patch event: {"path":"/...","data":...}
static void applyStreamData(const String &json, bool isPatch) {
  JsonDocument ev;
  if (deserializeJson(ev, json) != DeserializationError::Ok) { controlDoorbell = true; return; }
  String path = ev["path"] | "/";
  JsonVariantConst data = ev["data"];
  if (isPatch && data.is<JsonObjectConst>()) {
    String base = path == "/" ? "" : path;
    for (JsonPairConst kv : data.as<JsonObjectConst>()) setControl(base + "/" + kv.key().c_str(), kv.value());
  } else {
    setControl(path, data);
  }
  applyControl();
}

static void readSetpoints(const Snapshot &s) {
  String resp;
  if (db("GET", "setpoints", "", &resp) != 200) return;
  JsonDocument d;
  if (deserializeJson(d, resp) != DeserializationError::Ok || d.isNull()) {
    // Nothing in the cloud yet: start it from the controller's values.
    if (uploadSetpoints(s)) Serial.println("CLOUD: setpoints created from the controller");
    return;
  }
  double at = d["updatedAt"] | 0.0;
  double lastAt = cprefs.getDouble("spAt", -1);
  if (at == lastAt) return;
  cprefs.putDouble("spAt", at);
  float hOn = d["humOn"] | s.humOn, hOff = d["humOff"] | s.humOff;
  int cOn = d["co2On"] | s.co2On, cOff = d["co2Off"] | s.co2Off;
  if (!(hOn < hOff) || !(cOff < cOn)) { Serial.println("CLOUD: setpoints rejected (bad range)"); return; }
  if (hOn != s.humOn) pushCommand("SET_HUM_ON=" + String(hOn, 1));
  if (hOff != s.humOff) pushCommand("SET_HUM_OFF=" + String(hOff, 1));
  if (cOn != s.co2On) pushCommand("SET_CO2_ON=" + String(cOn));
  if (cOff != s.co2Off) pushCommand("SET_CO2_OFF=" + String(cOff));
}

static String slotCommand(int idx, JsonVariantConst o, bool hours) {
  String days;
  JsonArrayConst a = o["days"].as<JsonArrayConst>();
  for (int d = 0; d < 7 && d < (int)a.size(); d++) if (a[d].as<bool>()) days += String(d);
  int dur = hours ? (o["durationHr"] | 1) : (o["durationMin"] | 1);
  return String(idx) + "," + String(o["enabled"] | false ? 1 : 0) + "," + String(o["hour"] | 0) + "," +
         String(o["minute"] | 0) + "," + String(dur) + "," + days;
}

// RTDB returns slots as an array when keys are 0,1,2... and as an object
// otherwise; this reads slot i from either.
static JsonVariantConst slotAt(JsonVariantConst list, int i) {
  if (list.is<JsonArrayConst>()) return list[i];
  return list[String(i)];
}

static void readSchedules(const Snapshot &s) {
  String resp;
  if (db("GET", "schedules", "", &resp) != 200) return;
  JsonDocument d;
  if (deserializeJson(d, resp) != DeserializationError::Ok) return;
  if (d.isNull()) {
    if ((s.nSpr || s.nLgt) && uploadSchedules(s)) Serial.println("CLOUD: schedules created from the controller");
    return;
  }
  uint32_t h = fnv1a(resp);
  if (h == cprefs.getUInt("schHash", 0)) return;
  cprefs.putUInt("schHash", h);
  pushCommand("CLEAR_SPR_SCHED");
  pushCommand("CLEAR_LGT_SCHED");
  for (int i = 0; i < MAX_SCHEDULES; i++) {
    JsonVariantConst o = slotAt(d["sprinkler"], i);
    if (!o.isNull()) pushCommand("SET_SPR_SCHED=" + slotCommand(i, o, false));
    o = slotAt(d["light"], i);
    if (!o.isNull()) pushCommand("SET_LGT_SCHED=" + slotCommand(i, o, true));
  }
  Serial.println("CLOUD: schedules updated from the app");
}

// After the controller uploads, remember what the cloud now holds, so the
// next read does not apply our own values back.
static void rememberCloudConfig() {
  String resp;
  if (db("GET", "setpoints/updatedAt", "", &resp) == 200) cprefs.putDouble("spAt", resp.toDouble());
  if (db("GET", "schedules", "", &resp) == 200) cprefs.putUInt("schHash", fnv1a(resp));
}

// =====================================================
// Command stream (Firebase REST streaming, Server-Sent Events)
// =====================================================
// One open connection on farm1/control. Firebase pushes an event the moment
// the app writes a command; the event only rings a "doorbell" and the normal
// readControl() then fetches and applies it. So a tap in the app reaches the
// relays in about a second instead of waiting for the next poll.
static WiFiClientSecure streamTls;
static bool streamUp = false;
static uint32_t streamLastByte = 0, streamLastTry = 0;
static uint32_t streamTokenAt = 0;        // which token the stream was opened with
static String streamLine;
static int streamEvent = 0;               // 0 other, 1 put, 2 patch

// Read one line (without \r\n) or give up at the deadline.
static bool readLineUntil(WiFiClientSecure &c, String &line, uint32_t deadline) {
  line = "";
  while ((int32_t)(millis() - deadline) < 0) {
    while (c.available()) {
      char ch = c.read();
      if (ch == '\n') return true;
      if (ch != '\r' && line.length() < 600) line += ch;
    }
    if (!c.connected()) return false;
    vTaskDelay(pdMS_TO_TICKS(10));
  }
  return false;
}

static bool streamOpen() {
  String url = String(FB_DB_URL) + "/farm1/control.json?auth=" + idToken;
  for (int hop = 0; hop < 3; hop++) {             // Firebase may redirect (307) once
    int s = url.indexOf("://") + 3, p = url.indexOf('/', s);
    String host = url.substring(s, p), path = url.substring(p);
    streamTls.stop();
    if (!streamTls.connect(host.c_str(), 443)) return false;
    streamTls.print("GET " + path + " HTTP/1.1\r\nHost: " + host +
                    "\r\nAccept: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n");
    String line;
    uint32_t deadline = millis() + 8000;
    if (!readLineUntil(streamTls, line, deadline)) return false;
    bool redirect = line.indexOf(" 307") > 0 || line.indexOf(" 302") > 0;
    bool ok = line.indexOf(" 200") > 0;
    String location;
    while (readLineUntil(streamTls, line, deadline) && line.length()) {   // headers until the blank line
      if (line.startsWith("Location:") || line.startsWith("location:")) { location = line.substring(9); location.trim(); }
    }
    if (ok) return true;
    if (redirect && location.length()) { url = location; continue; }
    Serial.printf("CLOUD: stream refused (%s)\n", line.c_str());
    return false;
  }
  return false;
}

static void streamClose() {
  streamTls.stop();
  streamUp = false;
}

// Called often from the cloud loop; never waits for data.
static void streamPoll() {
  if (!streamUp || streamTokenAt != tokenExpiresAt) {
    if (streamUp) streamClose();                  // new sign-in token: reopen with it
    if (millis() - streamLastTry < 10000) return;
    streamLastTry = millis();
    streamUp = streamOpen();
    streamTokenAt = tokenExpiresAt;
    streamLastByte = millis();
    if (streamUp) {
      Serial.println("CLOUD: command stream open");
      // The first event is the whole control node: that catches up on anything missed.
    }
    return;
  }
  if (!streamTls.connected()) { Serial.println("CLOUD: command stream closed, reopening"); streamClose(); return; }
  while (streamTls.available()) {
    char ch = streamTls.read();
    streamLastByte = millis();
    if (ch == '\n') {
      if (streamLine.startsWith("event:")) {
        String ev = streamLine.substring(6);
        ev.trim();
        streamEvent = ev == "put" ? 1 : ev == "patch" ? 2 : 0;
        if (ev == "auth_revoked" || ev == "cancel") { idToken = ""; streamClose(); }
      } else if (streamLine.startsWith("data:") && streamEvent) {
        // The event carries the change itself: apply it, no extra request.
        if (streamLine.length() >= 2000) controlDoorbell = true;   // cut off: fetch it instead
        else applyStreamData(streamLine.substring(5), streamEvent == 2);
        streamEvent = 0;
      }
      streamLine = "";
    } else if (ch != '\r' && streamLine.length() < 2000) {
      streamLine += ch;
    }
  }
  // Firebase sends a keep-alive about every 30 s; silence means a dead link.
  if (millis() - streamLastByte > 75000) { Serial.println("CLOUD: command stream silent, reopening"); streamClose(); }
}

// The state the app cares about most; pushed as soon as it changes.
static bool sameVisibleState(const Snapshot &a, const Snapshot &b) {
  return a.autoMode == b.autoMode && a.mist == b.mist && a.refill == b.refill && a.sprinkler == b.sprinkler &&
         a.fan == b.fan && a.light == b.light && a.lowWater == b.lowWater;
}

// =====================================================
// Clock from the internet
// =====================================================
static void checkNtp() {
  struct tm t;
  if (!getLocalTime(&t, 0) || t.tm_year + 1900 < 2025) return;
  char buf[48];
  snprintf(buf, sizeof(buf), "SET_RTC=%04d-%02d-%02d %02d:%02d:%02d", t.tm_year + 1900, t.tm_mon + 1, t.tm_mday,
           t.tm_hour, t.tm_min, t.tm_sec);
  pushCommand(buf);
}

// =====================================================
// Wi-Fi: settings, failure reasons, scan
// =====================================================
static bool isPlaceholder(const char *s) { return !s[0] || strstr(s, "FILL IN") != nullptr; }
static bool firebaseConfigured() { return !isPlaceholder(FB_PASSWORD) && !isPlaceholder(FB_API_KEY); }

static void loadWifiSettings() {
  String s = cprefs.getString("ssid", "");
  if (s.length()) {
    wifiSsid = s;
    wifiPass = cprefs.getString("pass", "");
  } else if (!isPlaceholder(WIFI_SSID)) {
    wifiSsid = WIFI_SSID;
    wifiPass = isPlaceholder(WIFI_PASSWORD) ? "" : WIFI_PASSWORD;
  }
}

// fresh = new settings; a retry keeps showing the last failure reason.
static void startWifi(bool fresh = true) {
  WiFi.disconnect();
  if (wifiSsid.isEmpty()) { wifiState = WIFI_NOT_SET; return; }
  if (fresh || wifiState == WIFI_CONNECTED || wifiState == WIFI_NOT_SET) wifiState = WIFI_CONNECTING;
  vTaskDelay(pdMS_TO_TICKS(200));   // let the disconnect finish before joining again
  wl_status_t r = WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
  Serial.printf("CLOUD: joining \"%s\" (begin=%d, password %u chars)\n", wifiSsid.c_str(), (int)r, wifiPass.length());
}

// Why the last attempt failed, so the HMI can say "wrong password".
static void onWifiEvent(arduino_event_id_t event, arduino_event_info_t info) {
  if (event == ARDUINO_EVENT_WIFI_STA_CONNECTED) {
    linkUpAt = millis() | 1;
  } else if (event == ARDUINO_EVENT_WIFI_STA_GOT_IP) {
    linkUpAt = 0;
    wifiState = WIFI_CONNECTED;
  } else if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
    uint8_t r = info.wifi_sta_disconnected.reason;
    linkUpAt = 0;
    if (r != lastDisconnectReason) Serial.printf("CLOUD: wifi disconnected, reason %u\n", r);
    lastDisconnectReason = r;
    if (r == WIFI_REASON_NO_AP_FOUND) wifiState = WIFI_NOT_FOUND;
    else if (r == WIFI_REASON_AUTH_FAIL || r == WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT ||
             r == WIFI_REASON_HANDSHAKE_TIMEOUT || r == WIFI_REASON_AUTH_EXPIRE ||
             r == WIFI_REASON_MIC_FAILURE)
      wifiState = WIFI_WRONG_PASSWORD;
    else if (r == WIFI_REASON_NO_AP_FOUND_W_COMPATIBLE_SECURITY || r == WIFI_REASON_NO_AP_FOUND_IN_AUTHMODE_THRESHOLD ||
             r == WIFI_REASON_ASSOC_FAIL || r == WIFI_REASON_CONNECTION_FAIL)
      wifiState = WIFI_FAILED;
    else if (wifiState == WIFI_CONNECTED) wifiState = WIFI_CONNECTING;   // dropped: retrying
  }
}

static String hexOf(const String &s) {
  static const char *H = "0123456789ABCDEF";
  String out;
  for (size_t i = 0; i < s.length(); i++) { uint8_t b = s[i]; out += H[b >> 4]; out += H[b & 15]; }
  return out;
}

// Strongest networks first, each name once, at most 10, names in hex so any
// character survives the UART link.
static void doScan() {
  bool wasConnected = WiFi.status() == WL_CONNECTED;
  if (!wasConnected) WiFi.disconnect();   // the ESP32 cannot scan while it is still trying to join
  int n = WiFi.scanNetworks(false, false);
  const int MAXN = 40;
  if (n > MAXN) n = MAXN;
  String names[MAXN];
  int rssi[MAXN];
  int m = 0;
  for (int i = 0; i < n; i++) {
    String name = WiFi.SSID(i);
    if (name.isEmpty()) continue;                       // hidden network
    int r = WiFi.RSSI(i);
    int k = 0;
    while (k < m && names[k] != name) k++;
    if (k < m) { if (r > rssi[k]) rssi[k] = r; continue; }   // same name: keep the strongest
    names[m] = name; rssi[m] = r; m++;
  }
  WiFi.scanDelete();
  // Strongest first.
  for (int i = 1; i < m; i++)
    for (int j = i; j > 0 && rssi[j] > rssi[j - 1]; j--) {
      int t = rssi[j]; rssi[j] = rssi[j - 1]; rssi[j - 1] = t;
      String s = names[j]; names[j] = names[j - 1]; names[j - 1] = s;
    }
  int count = m < 10 ? m : 10;
  String items;
  for (int i = 0; i < count; i++) items += String(rssi[i]) + ":" + hexOf(names[i]) + ";";
  if (!wasConnected) startWifi(false);
  xSemaphoreTake(wifiMutex, portMAX_DELAY);
  scanResult = "WIFI_LIST," + String(count) + "," + items;
  scanReady = true;
  xSemaphoreGive(wifiMutex);
}

// =====================================================
// Task
// =====================================================
static void cloudTask(void *) {
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  // Accept older routers too (default minimum is WPA2, which skips WPA/WEP/open).
  WiFi.setMinSecurity(WIFI_AUTH_OPEN);
  // Power saving makes the radio doze between beacons; replies get lost and
  // HTTPS calls time out. The controller is mains-powered, so keep it awake.
  WiFi.setSleep(false);
  WiFi.onEvent(onWifiEvent);
  dbTls.setInsecure();     // TODO: pin the Google root certificate
  authTls.setInsecure();
  // Give up on a stuck TLS handshake after 10 s (the default is 120 s,
  // which kept the app "Offline" for minutes after one lost packet).
  dbTls.setHandshakeTimeout(6);
  streamTls.setInsecure();
  streamTls.setHandshakeTimeout(10);
  authTls.setHandshakeTimeout(15);
  cprefs.begin("cloud", false);
  // Long-lived buffers get their full size now, before any HTTPS connection
  // comes and goes. Growing them later would leave them in the middle of the
  // heap and split the big free block that each HTTPS connection needs.
  streamLine.reserve(2048);
  idToken.reserve(1400);
  refreshToken.reserve(600);
  loadWifiSettings();
  startWifi();
  configTzTime("PST-8", "pool.ntp.org", "time.google.com");   // Philippines, UTC+8

  uint32_t lastLive = 0, lastControl = 0, lastConfig = 0, lastWifiTry = millis();
  uint32_t lastHistory = 0, lastNtp = 0;
  bool ntpDone = false, firstConfig = true;

  for (;;) {
    if (haveNewWifi) {
      xSemaphoreTake(wifiMutex, portMAX_DELAY);
      wifiSsid = newSsid;
      wifiPass = newPass;
      haveNewWifi = false;
      xSemaphoreGive(wifiMutex);
      cprefs.putString("ssid", wifiSsid);
      cprefs.putString("pass", wifiPass);
      Serial.printf("CLOUD: new Wi-Fi \"%s\" saved, connecting\n", wifiSsid.c_str());
      idToken = "";
      startWifi();
      lastWifiTry = millis();
    }
    if (scanWanted) { scanWanted = false; doScan(); lastWifiTry = millis(); }

    if (WiFi.status() != WL_CONNECTED) {
      wifiUp = false; online = false;
      stateText = wifiSsid.isEmpty() ? "wifi not set" : "no wifi";
      // Joined the router but no address after 20 s: a Wi-Fi that wants a
      // login page or a registered device. Say so instead of "Connecting".
      if (linkUpAt && millis() - linkUpAt > 20000 && wifiState != WIFI_NO_IP) {
        wifiState = WIFI_NO_IP;
        Serial.println("CLOUD: router joined but it gives no IP address (login or registration Wi-Fi?)");
      }
      if (!wifiSsid.isEmpty() && millis() - lastWifiTry > WIFI_RETRY_MS) {
        lastWifiTry = millis();
        startWifi(false);
      }
      vTaskDelay(pdMS_TO_TICKS(500));
      continue;
    }
    wifiState = WIFI_CONNECTED;
    if (!wifiUp) Serial.printf("CLOUD: wifi up, ip %s, rssi %d\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
    wifiUp = true;

    if (!ntpDone || millis() - lastNtp > NTP_EVERY_MS) {
      struct tm t;
      if (getLocalTime(&t, 0) && t.tm_year + 1900 >= 2025) { checkNtp(); ntpDone = true; lastNtp = millis(); }
    }

    if (!firebaseConfigured()) {
      // Wi-Fi works (clock from the internet) but Firebase needs FB_PASSWORD.
      online = false;
      stateText = "no firebase password";
      vTaskDelay(pdMS_TO_TICKS(500));
      continue;
    }
    if (!ensureAuth()) {
      online = false;
      stateText = "sign-in failed";
      for (int i = 0; i < 20 && !haveNewWifi && !scanWanted; i++) vTaskDelay(pdMS_TO_TICKS(500));
      continue;
    }

    // Many failures in a row with Wi-Fi up: start over (fresh HTTPS and a
    // fresh Wi-Fi join), instead of retrying a connection that is stuck.
    if (failStreak >= 5) {
      Serial.printf("CLOUD: %u failures in a row, resetting the connection (heap %u, biggest block %u)\n",
                    failStreak, ESP.getFreeHeap(), ESP.getMaxAllocHeap());
      failStreak = 0;
      http.end();
      dbTls.stop();
      authTls.stop();
      startWifi(false);
      lastWifiTry = millis();
      vTaskDelay(pdMS_TO_TICKS(1000));
      continue;
    }

    Snapshot s;
    if (!getSnap(s)) { vTaskDelay(pdMS_TO_TICKS(200)); continue; }
    uint32_t now = millis();

    // Safety net: if the biggest free block gets too small for a new HTTPS
    // connection, close the stream for a moment to give its memory back.
    static uint32_t lastHeapCheck = 0;
    if (millis() - lastHeapCheck > 5000) {
      lastHeapCheck = millis();
      static uint32_t lastHeapLog = 0;
      if (millis() - lastHeapLog > 60000) {
        lastHeapLog = millis();
        Serial.printf("CLOUD: memory heap %u, biggest block %u, uptime %lu min\n", ESP.getFreeHeap(),
                      ESP.getMaxAllocHeap(), millis() / 60000);
      }
      if (streamUp && ESP.getMaxAllocHeap() < 45000) {
        Serial.printf("CLOUD: memory split (biggest block %u), closing the stream to recover\n", ESP.getMaxAllocHeap());
        streamClose();
      }
    }
    streamPoll();
    // A command from the app (stream doorbell) comes first, then the state the
    // app sees: pushed at once when it changed, else as a heartbeat.
    if (controlDoorbell || now - lastControl >= CONTROL_EVERY_MS) {
      controlDoorbell = false;
      lastControl = now;
      readControl();
      if (!getSnap(s)) continue;                  // the command may have changed the state
    }
    static Snapshot lastPushed;
    static bool pushedOnce = false;
    bool changed = !pushedOnce || !sameVisibleState(s, lastPushed);
    if (changed || now - lastLive >= LIVE_EVERY_MS) {
      uint32_t t0 = millis();
      if (putLive(s)) {
        // Only a write that worked counts; a failed one is tried again on
        // the next pass (200 ms later), not after the 15 s heartbeat.
        lastLive = now;
        lastPushed = s;
        pushedOnce = true;
        if (changed) Serial.printf("CLOUD: change sent to the app in %lu ms\n", millis() - t0);
      }
    }

    if (s.setpointsVer != uploadedSetpointsVer) {
      if (uploadSetpoints(s)) { uploadedSetpointsVer = s.setpointsVer; rememberCloudConfig(); }
    }
    if (s.schedulesVer != uploadedSchedulesVer) {
      if (uploadSchedules(s)) { uploadedSchedulesVer = s.schedulesVer; rememberCloudConfig(); }
    }
    if (firstConfig || now - lastConfig >= CONFIG_EVERY_MS) {
      firstConfig = false;
      lastConfig = now;
      readSetpoints(s);
      readSchedules(s);
    }

    if (lastHistory == 0 || now - lastHistory >= HISTORY_EVERY_MS) {
      if (s.thFresh || s.co2Fresh) { lastHistory = now; postHistory(s); }
    }

    stateText = online ? "online" : "firebase error";
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

// =====================================================
// Public
// =====================================================
void cloudBegin() {
  snapMutex = xSemaphoreCreateMutex();
  wifiMutex = xSemaphoreCreateMutex();
  cmdQueue = xQueueCreate(24, CMD_LEN);
  xTaskCreatePinnedToCore(cloudTask, "cloud", 16384, nullptr, 1, nullptr, 0);
  Serial.println(firebaseConfigured() ? "CLOUD: starting" : "CLOUD: starting (Firebase password not set, Wi-Fi only)");
}

int cloudWifiState() { return wifiState; }
int cloudRssi() { return WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0; }

String cloudWifiName() {
  if (!wifiMutex) return "";
  xSemaphoreTake(wifiMutex, portMAX_DELAY);
  String s = haveNewWifi ? newSsid : wifiSsid;
  xSemaphoreGive(wifiMutex);
  return s;
}

void cloudSetWifi(const String &ssid, const String &password) {
  if (!wifiMutex) return;
  xSemaphoreTake(wifiMutex, portMAX_DELAY);
  newSsid = ssid;
  newPass = password;
  haveNewWifi = true;
  wifiState = WIFI_CONNECTING;
  xSemaphoreGive(wifiMutex);
}

void cloudRequestScan() { scanWanted = true; }

bool cloudTakeScan(String &line) {
  if (!scanReady || !wifiMutex) return false;
  xSemaphoreTake(wifiMutex, portMAX_DELAY);
  line = scanResult;
  scanReady = false;
  xSemaphoreGive(wifiMutex);
  return true;
}

void cloudPublish(const Snapshot &s) {
  if (!snapMutex) return;
  if (xSemaphoreTake(snapMutex, pdMS_TO_TICKS(20)) != pdTRUE) return;
  if (!haveSnap) {
    // Start "already uploaded" so the boot values are not pushed over the app's.
    uploadedSetpointsVer = s.setpointsVer;
    uploadedSchedulesVer = s.schedulesVer;
  }
  snap = s;
  haveSnap = true;
  xSemaphoreGive(snapMutex);
}

bool cloudNextCommand(char *buf, size_t len) {
  if (!cmdQueue) return false;
  char tmp[CMD_LEN];
  if (xQueueReceive(cmdQueue, tmp, 0) != pdTRUE) return false;
  strncpy(buf, tmp, len - 1);
  buf[len - 1] = 0;
  return true;
}

bool cloudWifiUp() { return wifiUp; }
bool cloudOnline() { return online; }
const char *cloudStateText() { return (const char *)stateText; }

#endif
