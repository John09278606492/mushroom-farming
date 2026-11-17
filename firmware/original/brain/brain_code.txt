#include <Arduino.h>
#include <HardwareSerial.h>
#include <Arduino_GFX_Library.h>
#include <Wire.h>
#include <TAMC_GT911.h>
#include <lvgl.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>

// =====================================================
// UART
// =====================================================
#define LCD_TX_TO_SLAVE   43
#define LCD_RX_FROM_SLAVE 44
HardwareSerial bodySerial(1);

// =====================================================
// DISPLAY
// =====================================================
#define GFX_BL 2
Arduino_ESP32RGBPanel *rgbpanel = new Arduino_ESP32RGBPanel(
  40,41,39,42, 45,48,47,21,14, 5,6,7,15,16,4, 8,3,46,9,1,
  0,8,4,8, 0,8,4,8, 1,16000000);
Arduino_RGB_Display *gfx = new Arduino_RGB_Display(800,480,rgbpanel,0,true);

// =====================================================
// TOUCH
// =====================================================
#define TOUCH_SDA 19
#define TOUCH_SCL 20
#define TOUCH_INT 18
#define TOUCH_RST 38
TAMC_GT911 ts = TAMC_GT911(TOUCH_SDA,TOUCH_SCL,TOUCH_INT,TOUCH_RST,800,480);

// =====================================================
// LVGL
// =====================================================
#define SCREEN_W 800
#define SCREEN_H 480
#define BUF_LINES 20
static lv_color_t buf1[SCREEN_W * BUF_LINES];
static lv_display_t *disp;
static lv_indev_t *indev;
static uint32_t my_tick_get(void){return millis();}

void my_disp_flush(lv_display_t *d,const lv_area_t *a,uint8_t *px){
  gfx->draw16bitRGBBitmap(a->x1,a->y1,(uint16_t*)px,a->x2-a->x1+1,a->y2-a->y1+1);
  lv_display_flush_ready(d);
}
void my_touch_read(lv_indev_t *drv,lv_indev_data_t *data){
  ts.read();
  if(ts.isTouched){data->state=LV_INDEV_STATE_PRESSED;data->point.x=ts.points[0].x;data->point.y=ts.points[0].y;}
  else data->state=LV_INDEV_STATE_RELEASED;
}

#define F14 &lv_font_montserrat_14

// =====================================================
// COLORS
// =====================================================
#define C_BG       lv_color_hex(0x0F172A)
#define C_CARD     lv_color_hex(0x1E293B)
#define C_BORDER   lv_color_hex(0x334155)
#define C_TEXT     lv_color_hex(0xE2E8F0)
#define C_SUBTEXT  lv_color_hex(0x94A3B8)
#define C_GREEN    lv_color_hex(0x22C55E)
#define C_RED      lv_color_hex(0xEF4444)
#define C_BLUE     lv_color_hex(0x3B82F6)
#define C_ORANGE   lv_color_hex(0xF59E0B)
#define C_CYAN     lv_color_hex(0x06B6D4)
#define C_PURPLE   lv_color_hex(0xA855F7)
#define C_DARKBTN  lv_color_hex(0x334155)

// =====================================================
// BLE SERVER — phone connects to ESP32 to unlock
// =====================================================
#define BLE_SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
#define BLE_CHARACTERISTIC_UUID "abcd1234-ab12-cd34-ef56-123456789abc"

Preferences prefs;
bool bleEnabled = true;
char bleName[33] = "MushroomFarm";  // BLE advertised name (editable)

// Connection state
volatile bool bleClientConnected = false;
volatile int  bleConnectedCount = 0;
volatile unsigned long bleLastDisconnect = 0;

// Grace period after disconnect before locking (handles brief drops)
#define BLE_GRACE_MS 5000

BLEServer *pServer = NULL;
BLECharacteristic *pCharacteristic = NULL;
bool bleAdvertising = false;

// PIN code for extra security (optional, 6 digits)


// Edit buffer for settings
char bleEditBuf[33] = "";
int bleEditPos = 0;

// Lock tracking
#define MAX_INTERACTIVE 100
lv_obj_t *interactiveObjs[MAX_INTERACTIVE];
int interactiveCount = 0;
void registerInteractive(lv_obj_t *obj){
  if(interactiveCount<MAX_INTERACTIVE)interactiveObjs[interactiveCount++]=obj;
}

// =====================================================
// PREFERENCES
// =====================================================
void loadPrefs(){
  prefs.begin("ble",true);
  String name=prefs.getString("blename","MushroomFarm");
  strncpy(bleName,name.c_str(),32);bleName[32]='\0';
  bleEnabled=prefs.getBool("enabled",true);
  prefs.end();
}
void savePrefs(){
  prefs.begin("ble",false);
  prefs.putString("blename",bleName);
  prefs.putBool("enabled",bleEnabled);
  prefs.end();
}

// =====================================================
// BLE SERVER CALLBACKS
// =====================================================
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *s){
    bleConnectedCount++;
    bleClientConnected = true;
    Serial.printf("BLE client connected (count=%d)\n", bleConnectedCount);
  }
  void onDisconnect(BLEServer *s){
    bleConnectedCount--;
    if(bleConnectedCount <= 0){
      bleConnectedCount = 0;
      bleClientConnected = false;
      bleLastDisconnect = millis();
      Serial.println("BLE client disconnected — grace period started");
    }
    // Restart advertising so phone can reconnect
    delay(100);
    s->getAdvertising()->start();
    Serial.println("BLE advertising restarted");
  }
};

void initBLE(){
  BLEDevice::init(bleName);

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(BLE_SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    BLE_CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("MushroomFarm Lock");
  pService->start();

  BLEAdvertising *pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(BLE_SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->setMinPreferred(0x06);
  pAdv->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  bleAdvertising = true;

  Serial.printf("BLE server started: '%s'\n", bleName);
}

// Is unlocked?
bool isBLEUnlocked(){
  if(!bleEnabled) return true;
  if(bleClientConnected) return true;
  // Grace period after disconnect
  if(bleLastDisconnect > 0 && (millis() - bleLastDisconnect < BLE_GRACE_MS)) return true;
  return false;
}

// =====================================================
// ROLLER OPTIONS
// =====================================================
static char g_humOpts[256];
static char g_co2Opts[512];
void initRollerOptions(){
  g_humOpts[0]='\0';
  for(int i=50;i<=100;i++){char l[8];snprintf(l,sizeof(l),"%d",i);
    strncat(g_humOpts,l,sizeof(g_humOpts)-strlen(g_humOpts)-1);
    if(i<100)strncat(g_humOpts,"\n",sizeof(g_humOpts)-strlen(g_humOpts)-1);}
  g_co2Opts[0]='\0';
  for(int i=100;i<=2000;i+=50){char l[8];snprintf(l,sizeof(l),"%d",i);
    strncat(g_co2Opts,l,sizeof(g_co2Opts)-strlen(g_co2Opts)-1);
    if(i<2000)strncat(g_co2Opts,"\n",sizeof(g_co2Opts)-strlen(g_co2Opts)-1);}
}

// =====================================================
// STATUS
// =====================================================
float humidity=0,temperature=0;
int co2ppm=0;
bool lowWater=false,mistState=false,refillState=false;
bool sprinklerState=false,fanState=false,lightState=false;
bool autoMode=true;
String rtcTime="--:--:--";
String sprSchedText="NONE",lgtSchedText="NONE";
float humOn=85,humOff=95;
int co2On=800,co2Off=700;

enum SchedTarget{SCHED_SPR,SCHED_LGT};
SchedTarget schedTarget=SCHED_SPR;
int schedIdx=0;bool schedEn=true;
int schedHr=6,schedMn=0,schedDur=3;
bool schedDays[7]={1,1,1,1,1,1,1};
int rtcY=2025,rtcMo=1,rtcD=1,rtcH=0,rtcMi=0,rtcS=0;

bool bodyConnected=false;
unsigned long lastBodyRx=0;
#define BODY_TIMEOUT_MS 6000

void sendCommand(const String&cmd){
  if(!bodyConnected){bodySerial.flush();return;}
  if(bodySerial.availableForWrite()>(int)cmd.length()+2)bodySerial.println(cmd);
}

// =====================================================
// PAGES & WIDGETS
// =====================================================
lv_obj_t *pgHome=NULL,*pgSprinkler=NULL,*pgLight=NULL;
lv_obj_t *pgMist=NULL,*pgFan=NULL,*pgSched=NULL,*pgRTC=NULL;
lv_obj_t *pgSettings=NULL;

lv_obj_t *lblHumV=NULL,*lblTempV=NULL,*lblCO2V=NULL;
lv_obj_t *lblTimeV=NULL,*lblDateV=NULL;
lv_obj_t *lblSprV=NULL,*lblLightV=NULL,*lblMistV=NULL,*lblFanV=NULL;
lv_obj_t *lblWaterV=NULL,*lblModeV=NULL;
lv_obj_t *lblSprSchedV=NULL,*lblLgtSchedV=NULL;
lv_obj_t *lblLockStatus=NULL,*lblBodyStatus=NULL;

lv_obj_t *lblSprSt=NULL,*lblSprSchedP=NULL;
lv_obj_t *lblLgtSt=NULL,*lblLgtSchedP=NULL;
lv_obj_t *lblMistSt=NULL,*lblHumOnV=NULL,*lblHumOffV=NULL;
lv_obj_t *rollerHumOn=NULL,*rollerHumOff=NULL;
lv_obj_t *lblFanSt=NULL,*lblCO2OnV=NULL,*lblCO2OffV=NULL;
lv_obj_t *rollerCO2On=NULL,*rollerCO2Off=NULL;
lv_obj_t *lblScTitle=NULL,*lblScIdx=NULL,*lblScEn=NULL;
lv_obj_t *lblScTime=NULL,*lblScDur=NULL;
lv_obj_t *btnScDays[7]={NULL};
lv_obj_t *lblRtcCur=NULL,*lblRtcSet=NULL;
lv_obj_t *lblSetName=NULL,*lblSetStatus=NULL,*lblSetEdit=NULL;
lv_obj_t *lblSetEnabled=NULL,*lblSetInfo=NULL;

// =====================================================
// HELPERS
// =====================================================
String getFieldValue(String data,String key){
  String sk=","+key+"=";int start=data.indexOf(sk);
  if(start>=0){start+=sk.length();}
  else{sk=key+"=";int p=data.indexOf(sk);if(p==7)start=7+sk.length();else return"";}
  int end=data.indexOf(',',start);if(end<0)end=data.length();
  return data.substring(start,end);
}
String formatTime12h(int h,int m){
  String ap="AM";int h2=h;if(h2==0)h2=12;else if(h2==12)ap="PM";else if(h2>12){h2-=12;ap="PM";}
  char b[12];snprintf(b,sizeof(b),"%d:%02d %s",h2,m,ap.c_str());return String(b);
}
int getRollerInt(lv_obj_t *r){char buf[16];lv_roller_get_selected_str(r,buf,sizeof(buf));return atoi(buf);}

// =====================================================
// SCHEDULE TABLE FOR HOME
// =====================================================
void updateSchedTable(){
  if(!lblSprSchedV || !lblLgtSchedV) return;

  // Build sprinkler rows — split by | into separate lines
  String sprDisp = "";
  if(sprSchedText == "NONE" || sprSchedText.length() == 0){
    sprDisp = "  No schedules set";
  } else {
    String rem = sprSchedText;
    int slot = 0;
    while(rem.length() > 0){
      int pipe = rem.indexOf('|');
      String entry;
      if(pipe >= 0){ entry = rem.substring(0, pipe); rem = rem.substring(pipe + 1); }
      else { entry = rem; rem = ""; }
      if(slot > 0) sprDisp += "\n";
      sprDisp += "  Slot " + String(slot) + ": " + entry;
      slot++;
    }
  }

  // Build light rows — split by | into separate lines
  String lgtDisp = "";
  if(lgtSchedText == "NONE" || lgtSchedText.length() == 0){
    lgtDisp = "  No schedules set";
  } else {
    String rem = lgtSchedText;
    int slot = 0;
    while(rem.length() > 0){
      int pipe = rem.indexOf('|');
      String entry;
      if(pipe >= 0){ entry = rem.substring(0, pipe); rem = rem.substring(pipe + 1); }
      else { entry = rem; rem = ""; }
      if(slot > 0) lgtDisp += "\n";
      lgtDisp += "  Slot " + String(slot) + ": " + entry;
      slot++;
    }
  }

  lv_label_set_text(lblSprSchedV, ("SPRINKLER:\n" + sprDisp).c_str());
  lv_label_set_text(lblLgtSchedV, ("LIGHT:\n" + lgtDisp).c_str());
}

// =====================================================
// PARSE STATUS
// =====================================================
void parseStatus(String line){
  if(!line.startsWith("STATUS,"))return;
  lastBodyRx=millis();bodyConnected=true;
  String v;
  v=getFieldValue(line,"AUTO");     if(v.length())autoMode=v.toInt();
  v=getFieldValue(line,"H");        if(v.length())humidity=v.toFloat();
  v=getFieldValue(line,"T");        if(v.length())temperature=v.toFloat();
  v=getFieldValue(line,"CO2");      if(v.length())co2ppm=v.toInt();
  v=getFieldValue(line,"LOWWATER"); if(v.length())lowWater=v.toInt();
  v=getFieldValue(line,"MIST");     if(v.length())mistState=v.toInt();
  v=getFieldValue(line,"REFILL");   if(v.length())refillState=v.toInt();
  v=getFieldValue(line,"SPRINKLER");if(v.length())sprinklerState=v.toInt();
  v=getFieldValue(line,"FAN");      if(v.length())fanState=v.toInt();
  v=getFieldValue(line,"LIGHT");    if(v.length())lightState=v.toInt();
  v=getFieldValue(line,"HUM_ON");   if(v.length())humOn=v.toFloat();
  v=getFieldValue(line,"HUM_OFF");  if(v.length())humOff=v.toFloat();
  v=getFieldValue(line,"CO2_ON");   if(v.length())co2On=v.toInt();
  v=getFieldValue(line,"CO2_OFF");  if(v.length())co2Off=v.toInt();
  v=getFieldValue(line,"TIME");     if(v.length())rtcTime=v;
  v=getFieldValue(line,"SPR_SCHED");if(v.length())sprSchedText=v;
  v=getFieldValue(line,"LGT_SCHED");if(v.length())lgtSchedText=v;
}

// =====================================================
// LOCK
// =====================================================
bool lastAppliedLock = false;
void applyLockState(){
  bool unlocked = isBLEUnlocked();
  for(int i=0;i<interactiveCount;i++){
    if(!interactiveObjs[i])continue;
    if(unlocked){
      lv_obj_clear_state(interactiveObjs[i],LV_STATE_DISABLED);
      lv_obj_set_style_opa(interactiveObjs[i],LV_OPA_COVER,0);
    } else {
      lv_obj_add_state(interactiveObjs[i],LV_STATE_DISABLED);
      lv_obj_set_style_opa(interactiveObjs[i],LV_OPA_40,0);
    }
  }
  if(lblLockStatus){
    if(!bleEnabled){lv_label_set_text(lblLockStatus,"NO LOCK");lv_obj_set_style_text_color(lblLockStatus,C_SUBTEXT,0);}
    else if(unlocked){
      if(bleClientConnected) lv_label_set_text(lblLockStatus,"UNLOCKED (connected)");
      else lv_label_set_text(lblLockStatus,"UNLOCKED (grace)");
      lv_obj_set_style_text_color(lblLockStatus,C_GREEN,0);
    }
    else{lv_label_set_text(lblLockStatus,"LOCKED - connect BLE");lv_obj_set_style_text_color(lblLockStatus,C_RED,0);}
  }
  lastAppliedLock = unlocked;
}
void checkLockChange(){if(isBLEUnlocked() != lastAppliedLock) applyLockState();}

void checkBodyConnection(){
  if(millis()-lastBodyRx>BODY_TIMEOUT_MS) bodyConnected=false;
  if(lblBodyStatus){
    if(bodyConnected){lv_label_set_text(lblBodyStatus,"BODY:OK");lv_obj_set_style_text_color(lblBodyStatus,C_GREEN,0);}
    else{lv_label_set_text(lblBodyStatus,"BODY:N/C");lv_obj_set_style_text_color(lblBodyStatus,C_RED,0);}
  }
}

// =====================================================
// STYLE HELPERS
// =====================================================
void styleCard(lv_obj_t *o,int w,int h){
  lv_obj_set_size(o,w,h);lv_obj_set_style_bg_color(o,C_CARD,0);lv_obj_set_style_bg_opa(o,LV_OPA_COVER,0);
  lv_obj_set_style_radius(o,12,0);lv_obj_set_style_border_color(o,C_BORDER,0);
  lv_obj_set_style_border_width(o,1,0);lv_obj_set_style_pad_all(o,10,0);
  lv_obj_clear_flag(o,LV_OBJ_FLAG_SCROLLABLE);
}
void stylePage(lv_obj_t *p){
  lv_obj_set_size(p,SCREEN_W,SCREEN_H);lv_obj_set_pos(p,0,0);
  lv_obj_set_style_bg_color(p,C_BG,0);lv_obj_set_style_bg_opa(p,LV_OPA_COVER,0);
  lv_obj_set_style_pad_all(p,0,0);lv_obj_set_style_border_width(p,0,0);
  lv_obj_set_style_radius(p,0,0);lv_obj_clear_flag(p,LV_OBJ_FLAG_SCROLLABLE);
}
lv_obj_t* makeLabel(lv_obj_t *par,const char*txt,int x,int y,lv_color_t col){
  lv_obj_t *l=lv_label_create(par);lv_label_set_text(l,txt);
  lv_obj_set_pos(l,x,y);lv_obj_set_style_text_color(l,col,0);lv_obj_set_style_text_font(l,F14,0);return l;
}
void styleRoller(lv_obj_t *r){
  lv_obj_set_style_bg_color(r,C_CARD,0);lv_obj_set_style_text_color(r,C_TEXT,0);
  lv_obj_set_style_border_color(r,C_BORDER,0);
  lv_obj_set_style_bg_color(r,C_BLUE,LV_PART_SELECTED);
  lv_obj_set_style_text_color(r,lv_color_white(),LV_PART_SELECTED);
}

lv_obj_t* makeBtn(lv_obj_t *par,const char*txt,int x,int y,int w,int h,lv_event_cb_t cb){
  lv_obj_t *b=lv_btn_create(par);lv_obj_set_size(b,w,h);lv_obj_set_pos(b,x,y);
  lv_obj_set_style_bg_color(b,C_BLUE,0);lv_obj_set_style_radius(b,8,0);
  lv_obj_set_style_bg_color(b,lv_color_hex(0x2563EB),LV_STATE_PRESSED);
  lv_obj_set_style_shadow_width(b,6,0);lv_obj_set_style_shadow_opa(b,LV_OPA_20,0);
  lv_obj_add_event_cb(b,cb,LV_EVENT_CLICKED,NULL);
  lv_obj_t *l=lv_label_create(b);lv_label_set_text(l,txt);
  lv_obj_set_style_text_color(l,lv_color_white(),0);lv_obj_center(l);
  registerInteractive(b);return b;
}
lv_obj_t* makeDarkBtn(lv_obj_t *par,const char*txt,int x,int y,int w,int h,lv_event_cb_t cb){
  lv_obj_t *b=lv_btn_create(par);lv_obj_set_size(b,w,h);lv_obj_set_pos(b,x,y);
  lv_obj_set_style_bg_color(b,C_DARKBTN,0);lv_obj_set_style_radius(b,8,0);
  lv_obj_set_style_bg_color(b,lv_color_hex(0x475569),LV_STATE_PRESSED);
  lv_obj_add_event_cb(b,cb,LV_EVENT_CLICKED,NULL);
  lv_obj_t *l=lv_label_create(b);lv_label_set_text(l,txt);
  lv_obj_set_style_text_color(l,C_TEXT,0);lv_obj_center(l);
  registerInteractive(b);return b;
}
lv_obj_t* makeGreenBtn(lv_obj_t *par,const char*txt,int x,int y,int w,int h,lv_event_cb_t cb){
  lv_obj_t *b=lv_btn_create(par);lv_obj_set_size(b,w,h);lv_obj_set_pos(b,x,y);
  lv_obj_set_style_bg_color(b,C_GREEN,0);lv_obj_set_style_radius(b,8,0);
  lv_obj_add_event_cb(b,cb,LV_EVENT_CLICKED,NULL);
  lv_obj_t *l=lv_label_create(b);lv_label_set_text(l,txt);
  lv_obj_set_style_text_color(l,lv_color_white(),0);lv_obj_center(l);
  registerInteractive(b);return b;
}
lv_obj_t* makeRedBtn(lv_obj_t *par,const char*txt,int x,int y,int w,int h,lv_event_cb_t cb){
  lv_obj_t *b=lv_btn_create(par);lv_obj_set_size(b,w,h);lv_obj_set_pos(b,x,y);
  lv_obj_set_style_bg_color(b,C_RED,0);lv_obj_set_style_radius(b,8,0);
  lv_obj_add_event_cb(b,cb,LV_EVENT_CLICKED,NULL);
  lv_obj_t *l=lv_label_create(b);lv_label_set_text(l,txt);
  lv_obj_set_style_text_color(l,lv_color_white(),0);lv_obj_center(l);
  registerInteractive(b);return b;
}
lv_obj_t* makeNavBtn(lv_obj_t *par,const char*txt,int x,int y,int w,int h,lv_event_cb_t cb){
  lv_obj_t *b=lv_btn_create(par);lv_obj_set_size(b,w,h);lv_obj_set_pos(b,x,y);
  lv_obj_set_style_bg_color(b,C_DARKBTN,0);lv_obj_set_style_radius(b,8,0);
  lv_obj_set_style_bg_color(b,lv_color_hex(0x475569),LV_STATE_PRESSED);
  lv_obj_add_event_cb(b,cb,LV_EVENT_CLICKED,NULL);
  lv_obj_t *l=lv_label_create(b);lv_label_set_text(l,txt);
  lv_obj_set_style_text_color(l,C_TEXT,0);lv_obj_center(l);return b;
}

// =====================================================
// NAVIGATION
// =====================================================
void hideAll(){
  if(pgHome)lv_obj_add_flag(pgHome,LV_OBJ_FLAG_HIDDEN);
  if(pgSprinkler)lv_obj_add_flag(pgSprinkler,LV_OBJ_FLAG_HIDDEN);
  if(pgLight)lv_obj_add_flag(pgLight,LV_OBJ_FLAG_HIDDEN);
  if(pgMist)lv_obj_add_flag(pgMist,LV_OBJ_FLAG_HIDDEN);
  if(pgFan)lv_obj_add_flag(pgFan,LV_OBJ_FLAG_HIDDEN);
  if(pgSched)lv_obj_add_flag(pgSched,LV_OBJ_FLAG_HIDDEN);
  if(pgRTC)lv_obj_add_flag(pgRTC,LV_OBJ_FLAG_HIDDEN);
  if(pgSettings)lv_obj_add_flag(pgSettings,LV_OBJ_FLAG_HIDDEN);
}
void goHome(){hideAll();lv_obj_clear_flag(pgHome,LV_OBJ_FLAG_HIDDEN);}

void updateHome(){
  if(!lblHumV)return;
  lv_label_set_text(lblHumV,(String(humidity,1)+" %").c_str());
  lv_label_set_text(lblTempV,(String(temperature,1)+" C").c_str());
  lv_label_set_text(lblCO2V,(String(co2ppm)+" ppm").c_str());
  String dateStr="----",timeStr="--:--";
  if(rtcTime.length()>=16){dateStr=rtcTime.substring(0,10);timeStr=rtcTime.substring(11,16);}
  lv_label_set_text(lblDateV,dateStr.c_str());lv_label_set_text(lblTimeV,timeStr.c_str());
  lv_label_set_text(lblSprV,sprinklerState?"ON":"OFF");
  lv_obj_set_style_text_color(lblSprV,sprinklerState?C_GREEN:C_RED,0);
  lv_label_set_text(lblLightV,lightState?"ON":"OFF");
  lv_obj_set_style_text_color(lblLightV,lightState?C_GREEN:C_RED,0);
  lv_label_set_text(lblMistV,mistState?"ON":"OFF");
  lv_obj_set_style_text_color(lblMistV,mistState?C_GREEN:C_RED,0);
  lv_label_set_text(lblFanV,fanState?"ON":"OFF");
  lv_obj_set_style_text_color(lblFanV,fanState?C_GREEN:C_RED,0);
  lv_label_set_text(lblWaterV,lowWater?"LOW!":"OK");
  lv_obj_set_style_text_color(lblWaterV,lowWater?C_ORANGE:C_GREEN,0);
  lv_label_set_text(lblModeV,autoMode?"AUTO":"MANUAL");
  lv_obj_set_style_text_color(lblModeV,autoMode?C_CYAN:C_ORANGE,0);
  updateSchedTable();
}

lv_obj_t* makeWidget(lv_obj_t *par,int x,int y,int w,int h,lv_color_t accent,lv_event_cb_t cb){
  lv_obj_t *card=lv_obj_create(par);lv_obj_set_pos(card,x,y);styleCard(card,w,h);
  lv_obj_set_style_border_color(card,accent,0);lv_obj_set_style_border_width(card,2,0);
  if(cb){lv_obj_add_flag(card,LV_OBJ_FLAG_CLICKABLE);lv_obj_add_event_cb(card,cb,LV_EVENT_CLICKED,NULL);
    lv_obj_set_style_bg_color(card,lv_color_hex(0x283548),LV_STATE_PRESSED);registerInteractive(card);}
  lv_obj_t *bar=lv_obj_create(card);lv_obj_set_size(bar,w-24,3);lv_obj_set_pos(bar,-2,-6);
  lv_obj_set_style_bg_color(bar,accent,0);lv_obj_set_style_bg_opa(bar,LV_OPA_COVER,0);
  lv_obj_set_style_radius(bar,2,0);lv_obj_set_style_border_width(bar,0,0);return card;
}

// =====================================================
// ALL CALLBACKS (same as before)
// =====================================================
void cb_goHome(lv_event_t*e){LV_UNUSED(e);goHome();updateHome();}
void cb_goSpr(lv_event_t*e){LV_UNUSED(e);hideAll();lv_obj_clear_flag(pgSprinkler,LV_OBJ_FLAG_HIDDEN);
  lv_label_set_text(lblSprSt,sprinklerState?"STATUS: ON":"STATUS: OFF");
  lv_obj_set_style_text_color(lblSprSt,sprinklerState?C_GREEN:C_RED,0);
  lv_label_set_text(lblSprSchedP,("Schedule: "+sprSchedText).c_str());}
void cb_sprOn(lv_event_t*e){LV_UNUSED(e);sendCommand("SPRINKLER_ON");sendCommand("GET_STATUS");}
void cb_sprOff(lv_event_t*e){LV_UNUSED(e);sendCommand("SPRINKLER_OFF");sendCommand("GET_STATUS");}
void cb_sprSched(lv_event_t*e){LV_UNUSED(e);schedTarget=SCHED_SPR;hideAll();lv_obj_clear_flag(pgSched,LV_OBJ_FLAG_HIDDEN);updSchedDisp();}

void cb_goLight(lv_event_t*e){LV_UNUSED(e);hideAll();lv_obj_clear_flag(pgLight,LV_OBJ_FLAG_HIDDEN);
  lv_label_set_text(lblLgtSt,lightState?"STATUS: ON":"STATUS: OFF");
  lv_obj_set_style_text_color(lblLgtSt,lightState?C_GREEN:C_RED,0);
  lv_label_set_text(lblLgtSchedP,("Schedule: "+lgtSchedText).c_str());}
void cb_lgtOn(lv_event_t*e){LV_UNUSED(e);sendCommand("LIGHT_ON");sendCommand("GET_STATUS");}
void cb_lgtOff(lv_event_t*e){LV_UNUSED(e);sendCommand("LIGHT_OFF");sendCommand("GET_STATUS");}
void cb_lgtSched(lv_event_t*e){LV_UNUSED(e);schedTarget=SCHED_LGT;hideAll();lv_obj_clear_flag(pgSched,LV_OBJ_FLAG_HIDDEN);updSchedDisp();}

void cb_goMist(lv_event_t*e){LV_UNUSED(e);hideAll();lv_obj_clear_flag(pgMist,LV_OBJ_FLAG_HIDDEN);
  lv_label_set_text(lblMistSt,mistState?"MIST: ON":"MIST: OFF");
  lv_obj_set_style_text_color(lblMistSt,mistState?C_GREEN:C_RED,0);
  lv_label_set_text(lblHumOnV,("ON below: "+String(humOn,0)+"%").c_str());
  lv_label_set_text(lblHumOffV,("OFF above: "+String(humOff,0)+"%").c_str());
  int onI=(int)humOn-50;if(onI<0)onI=0;if(onI>50)onI=50;
  int offI=(int)humOff-50;if(offI<0)offI=0;if(offI>50)offI=50;
  lv_roller_set_selected(rollerHumOn,onI,LV_ANIM_OFF);lv_roller_set_selected(rollerHumOff,offI,LV_ANIM_OFF);}
void cb_mistOn(lv_event_t*e){LV_UNUSED(e);sendCommand("MIST_ON");sendCommand("GET_STATUS");}
void cb_mistOff(lv_event_t*e){LV_UNUSED(e);sendCommand("MIST_OFF");sendCommand("GET_STATUS");}
void cb_applyHum(lv_event_t*e){LV_UNUSED(e);
  humOn=getRollerInt(rollerHumOn);humOff=getRollerInt(rollerHumOff);
  sendCommand("SET_HUM_ON="+String(humOn,1));sendCommand("SET_HUM_OFF="+String(humOff,1));sendCommand("GET_STATUS");
  lv_label_set_text(lblHumOnV,("ON below: "+String(humOn,0)+"%").c_str());
  lv_label_set_text(lblHumOffV,("OFF above: "+String(humOff,0)+"%").c_str());}

void cb_goFan(lv_event_t*e){LV_UNUSED(e);hideAll();lv_obj_clear_flag(pgFan,LV_OBJ_FLAG_HIDDEN);
  lv_label_set_text(lblFanSt,fanState?"FAN: ON":"FAN: OFF");
  lv_obj_set_style_text_color(lblFanSt,fanState?C_GREEN:C_RED,0);
  lv_label_set_text(lblCO2OnV,("ON above: "+String(co2On)+" ppm").c_str());
  lv_label_set_text(lblCO2OffV,("OFF below: "+String(co2Off)+" ppm").c_str());
  int onI=(co2On-100)/50;if(onI<0)onI=0;if(onI>38)onI=38;
  int offI=(co2Off-100)/50;if(offI<0)offI=0;if(offI>38)offI=38;
  lv_roller_set_selected(rollerCO2On,onI,LV_ANIM_OFF);lv_roller_set_selected(rollerCO2Off,offI,LV_ANIM_OFF);}
void cb_fanOn(lv_event_t*e){LV_UNUSED(e);sendCommand("FAN_ON");sendCommand("GET_STATUS");}
void cb_fanOff(lv_event_t*e){LV_UNUSED(e);sendCommand("FAN_OFF");sendCommand("GET_STATUS");}
void cb_applyCO2(lv_event_t*e){LV_UNUSED(e);
  co2On=getRollerInt(rollerCO2On);co2Off=getRollerInt(rollerCO2Off);
  sendCommand("SET_CO2_ON="+String(co2On));sendCommand("SET_CO2_OFF="+String(co2Off));sendCommand("GET_STATUS");
  lv_label_set_text(lblCO2OnV,("ON above: "+String(co2On)+" ppm").c_str());
  lv_label_set_text(lblCO2OffV,("OFF below: "+String(co2Off)+" ppm").c_str());}

void cb_autoOn(lv_event_t*e){LV_UNUSED(e);sendCommand("AUTO_ON");sendCommand("GET_STATUS");}
void cb_autoOff(lv_event_t*e){LV_UNUSED(e);sendCommand("AUTO_OFF");sendCommand("GET_STATUS");}

void cb_goRTC(lv_event_t*e){LV_UNUSED(e);
  if(rtcTime.length()>=19){rtcY=rtcTime.substring(0,4).toInt();rtcMo=rtcTime.substring(5,7).toInt();
    rtcD=rtcTime.substring(8,10).toInt();rtcH=rtcTime.substring(11,13).toInt();
    rtcMi=rtcTime.substring(14,16).toInt();rtcS=rtcTime.substring(17,19).toInt();}
  hideAll();lv_obj_clear_flag(pgRTC,LV_OBJ_FLAG_HIDDEN);
  lv_label_set_text(lblRtcCur,("Current: "+rtcTime).c_str());
  char b[48];snprintf(b,sizeof(b),"Set: %04d-%02d-%02d %02d:%02d:%02d",rtcY,rtcMo,rtcD,rtcH,rtcMi,rtcS);
  lv_label_set_text(lblRtcSet,b);}
void clampRTC(){if(rtcY<2024)rtcY=2035;if(rtcY>2035)rtcY=2024;if(rtcMo<1)rtcMo=12;if(rtcMo>12)rtcMo=1;
  if(rtcD<1)rtcD=31;if(rtcD>31)rtcD=1;if(rtcH<0)rtcH=23;if(rtcH>23)rtcH=0;
  if(rtcMi<0)rtcMi=59;if(rtcMi>59)rtcMi=0;if(rtcS<0)rtcS=59;if(rtcS>59)rtcS=0;}
void updRtcLbl(){clampRTC();char b[48];
  snprintf(b,sizeof(b),"Set: %04d-%02d-%02d %02d:%02d:%02d",rtcY,rtcMo,rtcD,rtcH,rtcMi,rtcS);
  lv_label_set_text(lblRtcSet,b);}
void cb_rtc(lv_event_t*e){
  lv_obj_t *b=(lv_obj_t*)lv_event_get_target(e);lv_obj_t *l=lv_obj_get_child(b,0);
  if(!l)return;String s=lv_label_get_text(l);
  if(s=="YR+")rtcY++;else if(s=="YR-")rtcY--;else if(s=="MO+")rtcMo++;else if(s=="MO-")rtcMo--;
  else if(s=="DY+")rtcD++;else if(s=="DY-")rtcD--;else if(s=="HR+")rtcH++;else if(s=="HR-")rtcH--;
  else if(s=="MI+")rtcMi++;else if(s=="MI-")rtcMi--;else if(s=="SE+")rtcS++;else if(s=="SE-")rtcS--;
  else if(s=="APPLY"){clampRTC();char buf[40];
    snprintf(buf,sizeof(buf),"SET_RTC=%04d-%02d-%02d %02d:%02d:%02d",rtcY,rtcMo,rtcD,rtcH,rtcMi,rtcS);
    sendCommand(String(buf));sendCommand("GET_STATUS");goHome();updateHome();return;}
  else if(s=="BACK"){goHome();updateHome();return;}
  updRtcLbl();}

void updSchedDisp(){
  if(!lblScTitle)return;
  lv_label_set_text(lblScTitle,schedTarget==SCHED_SPR?"SPRINKLER SCHEDULE":"LIGHT SCHEDULE");
  lv_label_set_text(lblScIdx,("Slot #"+String(schedIdx)).c_str());
  lv_label_set_text(lblScEn,schedEn?"ENABLED":"DISABLED");
  lv_obj_set_style_text_color(lblScEn,schedEn?C_GREEN:C_RED,0);
  lv_label_set_text(lblScTime,formatTime12h(schedHr,schedMn).c_str());
  if(schedTarget==SCHED_LGT)
    lv_label_set_text(lblScDur,(String(schedDur)+" hr").c_str());
  else
    lv_label_set_text(lblScDur,(String(schedDur)+" min").c_str());
  for(int d=0;d<7;d++)lv_obj_set_style_bg_color(btnScDays[d],schedDays[d]?C_BLUE:C_DARKBTN,0);
}
void cb_sched(lv_event_t*e){
  lv_obj_t *b=(lv_obj_t*)lv_event_get_target(e);lv_obj_t *l=lv_obj_get_child(b,0);
  if(!l)return;String s=lv_label_get_text(l);
  if(s=="HR+")schedHr=(schedHr+1)%24;else if(s=="HR-")schedHr=(schedHr+23)%24;
  else if(s=="MN+")schedMn=(schedMn+5)%60;else if(s=="MN-")schedMn=(schedMn+55)%60;
  else if(s=="D+"){schedDur++;if(schedDur>120)schedDur=120;}
  else if(s=="D-"){schedDur--;if(schedDur<1)schedDur=1;}
  else if(s=="#-"){schedIdx--;if(schedIdx<0)schedIdx=4;}
  else if(s=="#+"){schedIdx++;if(schedIdx>4)schedIdx=0;}
  else if(s=="TGL")schedEn=!schedEn;
  else if(s=="Su")schedDays[0]=!schedDays[0];else if(s=="Mo")schedDays[1]=!schedDays[1];
  else if(s=="Tu")schedDays[2]=!schedDays[2];else if(s=="We")schedDays[3]=!schedDays[3];
  else if(s=="Th")schedDays[4]=!schedDays[4];else if(s=="Fr")schedDays[5]=!schedDays[5];
  else if(s=="Sa")schedDays[6]=!schedDays[6];
  else if(s=="ALL"){for(int i=0;i<7;i++)schedDays[i]=true;}
  else if(s=="WKD"){for(int i=0;i<7;i++)schedDays[i]=(i>=1&&i<=5);}
  else if(s=="SAVE"){String ds="";for(int d=0;d<7;d++)if(schedDays[d])ds+=String(d);
    String pfx=schedTarget==SCHED_SPR?"SET_SPR_SCHED=":"SET_LGT_SCHED=";
    sendCommand(pfx+String(schedIdx)+","+String(schedEn?1:0)+","+String(schedHr)+","+
      String(schedMn)+","+String(schedDur)+","+ds);sendCommand("GET_STATUS");}
  else if(s=="CLR"){sendCommand(schedTarget==SCHED_SPR?"CLEAR_SPR_SCHED":"CLEAR_LGT_SCHED");sendCommand("GET_STATUS");}
  else if(s=="BACK"){goHome();updateHome();return;}
  updSchedDisp();}

// =====================================================
// SETTINGS — BLE name editor
// =====================================================
void updSettingsDisp(){
  if(!lblSetName)return;
  lv_label_set_text(lblSetName,("BLE Name: "+String(bleName)).c_str());
  lv_label_set_text(lblSetEnabled,bleEnabled?"BLE Lock: ON":"BLE Lock: OFF");
  lv_obj_set_style_text_color(lblSetEnabled,bleEnabled?C_GREEN:C_RED,0);
  char d[36];snprintf(d,sizeof(d),"> %s_",bleEditBuf);
  lv_label_set_text(lblSetEdit,d);
  lv_label_set_text(lblSetInfo,
    bleClientConnected ? "Phone connected - UNLOCKED" :
    "Waiting for phone to connect...");
  lv_obj_set_style_text_color(lblSetInfo,bleClientConnected?C_GREEN:C_ORANGE,0);
}
void cb_goSettings(lv_event_t*e){LV_UNUSED(e);
  strncpy(bleEditBuf,bleName,32);bleEditBuf[32]='\0';bleEditPos=strlen(bleEditBuf);
  hideAll();lv_obj_clear_flag(pgSettings,LV_OBJ_FLAG_HIDDEN);updSettingsDisp();}
void cb_settings(lv_event_t*e){
  lv_obj_t *b=(lv_obj_t*)lv_event_get_target(e);lv_obj_t *l=lv_obj_get_child(b,0);
  if(!l)return;String s=lv_label_get_text(l);
  if(s=="BACK"){goHome();updateHome();return;}
  else if(s=="TOGGLE"){bleEnabled=!bleEnabled;savePrefs();if(!bleEnabled){applyLockState();}}
  else if(s=="SAVE"){strncpy(bleName,bleEditBuf,32);bleName[32]='\0';savePrefs();
    lv_label_set_text(lblSetStatus,"Saved! Reboot to apply name");lv_obj_set_style_text_color(lblSetStatus,C_ORANGE,0);}
  else if(s=="DEL"){if(bleEditPos>0){bleEditPos--;bleEditBuf[bleEditPos]='\0';}}
  else if(s=="CLR"){bleEditPos=0;bleEditBuf[0]='\0';}
  else if(s=="SPC"){if(bleEditPos<32){bleEditBuf[bleEditPos]=' ';bleEditPos++;bleEditBuf[bleEditPos]='\0';}}
  else if(s.length()==1&&bleEditPos<32){bleEditBuf[bleEditPos]=s.charAt(0);bleEditPos++;bleEditBuf[bleEditPos]='\0';}
  updSettingsDisp();}

// =====================================================
// BUILD ALL PAGES
// =====================================================
void buildHome(){
  pgHome=lv_obj_create(lv_scr_act());stylePage(pgHome);
  makeLabel(pgHome,"MUSHROOM FARM",16,4,C_TEXT);
  lblLockStatus=makeLabel(pgHome,"LOCKED",350,6,C_RED);
  lblBodyStatus=makeLabel(pgHome,"BODY:N/C",560,6,C_RED);
  makeNavBtn(pgHome,"SETTINGS",690,2,100,22,cb_goSettings);

  lv_obj_t *c1=makeWidget(pgHome,12,26,188,72,C_CYAN,NULL);
  makeLabel(c1,"HUMIDITY",0,0,C_SUBTEXT);lblHumV=makeLabel(c1,"-- %",0,20,C_TEXT);
  lv_obj_t *c2=makeWidget(pgHome,208,26,188,72,C_ORANGE,NULL);
  makeLabel(c2,"TEMPERATURE",0,0,C_SUBTEXT);lblTempV=makeLabel(c2,"-- C",0,20,C_TEXT);
  lv_obj_t *c3=makeWidget(pgHome,404,26,188,72,C_PURPLE,NULL);
  makeLabel(c3,"CO2",0,0,C_SUBTEXT);lblCO2V=makeLabel(c3,"-- ppm",0,20,C_TEXT);
  lv_obj_t *c4=makeWidget(pgHome,600,26,188,72,C_BLUE,cb_goRTC);
  makeLabel(c4,"CLOCK (tap)",0,0,C_SUBTEXT);
  lblTimeV=makeLabel(c4,"--:--",0,18,C_TEXT);lblDateV=makeLabel(c4,"----",0,40,C_SUBTEXT);

  lv_obj_t *d1=makeWidget(pgHome,12,106,188,72,C_GREEN,cb_goSpr);
  makeLabel(d1,"SPRINKLER >",0,0,C_SUBTEXT);lblSprV=makeLabel(d1,"OFF",0,20,C_RED);
  lv_obj_t *d2=makeWidget(pgHome,208,106,188,72,C_ORANGE,cb_goLight);
  makeLabel(d2,"LIGHT >",0,0,C_SUBTEXT);lblLightV=makeLabel(d2,"OFF",0,20,C_RED);
  lv_obj_t *d3=makeWidget(pgHome,404,106,188,72,C_CYAN,cb_goMist);
  makeLabel(d3,"MIST >",0,0,C_SUBTEXT);lblMistV=makeLabel(d3,"OFF",0,20,C_RED);
  lv_obj_t *d4=makeWidget(pgHome,600,106,188,72,C_PURPLE,cb_goFan);
  makeLabel(d4,"FAN >",0,0,C_SUBTEXT);lblFanV=makeLabel(d4,"OFF",0,20,C_RED);

  lv_obj_t *w1=makeWidget(pgHome,12,186,188,60,C_BLUE,NULL);
  makeLabel(w1,"WATER LEVEL",0,0,C_SUBTEXT);lblWaterV=makeLabel(w1,"OK",0,18,C_GREEN);
  lv_obj_t *w2=makeWidget(pgHome,208,186,188,60,C_CYAN,NULL);
  makeLabel(w2,"MODE",0,0,C_SUBTEXT);lblModeV=makeLabel(w2,"AUTO",0,18,C_CYAN);
  makeBtn(pgHome,"AUTO ON",420,190,170,26,cb_autoOn);
  makeBtn(pgHome,"AUTO OFF",600,190,170,26,cb_autoOff);

  lv_obj_t *sc=lv_obj_create(pgHome);lv_obj_set_pos(sc,12,255);styleCard(sc,776,210);
  lv_obj_set_style_border_color(sc,C_GREEN,0);
  lv_obj_add_flag(sc,LV_OBJ_FLAG_SCROLLABLE);
  makeLabel(sc,"ACTIVE SCHEDULES",0,0,C_SUBTEXT);

  lblSprSchedV=makeLabel(sc,"SPRINKLER:\n  No schedules set",0,22,C_TEXT);
  lv_obj_set_width(lblSprSchedV,360);lv_label_set_long_mode(lblSprSchedV,LV_LABEL_LONG_WRAP);

  lblLgtSchedV=makeLabel(sc,"LIGHT:\n  No schedules set",380,22,C_TEXT);
  lv_obj_set_width(lblLgtSchedV,360);lv_label_set_long_mode(lblLgtSchedV,LV_LABEL_LONG_WRAP);
}

void buildSprinklerPage(){
  pgSprinkler=lv_obj_create(lv_scr_act());stylePage(pgSprinkler);lv_obj_add_flag(pgSprinkler,LV_OBJ_FLAG_HIDDEN);
  makeLabel(pgSprinkler,"SPRINKLER CONTROL",16,12,C_TEXT);
  lblSprSt=makeLabel(pgSprinkler,"STATUS: OFF",16,40,C_RED);
  makeGreenBtn(pgSprinkler,"TURN ON",16,75,240,60,cb_sprOn);
  makeRedBtn(pgSprinkler,"TURN OFF",270,75,240,60,cb_sprOff);
  makeBtn(pgSprinkler,"EDIT SCHEDULE",524,75,260,60,cb_sprSched);
  lv_obj_t *card=lv_obj_create(pgSprinkler);lv_obj_set_pos(card,16,155);styleCard(card,768,250);
  lv_obj_set_style_border_color(card,C_GREEN,0);makeLabel(card,"CURRENT SCHEDULE",0,0,C_SUBTEXT);
  lblSprSchedP=makeLabel(card,"Schedule: NONE",0,22,C_TEXT);
  lv_obj_set_width(lblSprSchedP,740);lv_label_set_long_mode(lblSprSchedP,LV_LABEL_LONG_WRAP);
  makeNavBtn(pgSprinkler,"< HOME",16,425,160,45,cb_goHome);
}
void buildLightPage(){
  pgLight=lv_obj_create(lv_scr_act());stylePage(pgLight);lv_obj_add_flag(pgLight,LV_OBJ_FLAG_HIDDEN);
  makeLabel(pgLight,"LIGHT CONTROL",16,12,C_TEXT);
  lblLgtSt=makeLabel(pgLight,"STATUS: OFF",16,40,C_RED);
  makeGreenBtn(pgLight,"TURN ON",16,75,240,60,cb_lgtOn);
  makeRedBtn(pgLight,"TURN OFF",270,75,240,60,cb_lgtOff);
  makeBtn(pgLight,"EDIT SCHEDULE",524,75,260,60,cb_lgtSched);
  lv_obj_t *card=lv_obj_create(pgLight);lv_obj_set_pos(card,16,155);styleCard(card,768,250);
  lv_obj_set_style_border_color(card,C_ORANGE,0);makeLabel(card,"CURRENT SCHEDULE",0,0,C_SUBTEXT);
  lblLgtSchedP=makeLabel(card,"Schedule: NONE",0,22,C_TEXT);
  lv_obj_set_width(lblLgtSchedP,740);lv_label_set_long_mode(lblLgtSchedP,LV_LABEL_LONG_WRAP);
  makeNavBtn(pgLight,"< HOME",16,425,160,45,cb_goHome);
}
void buildMistPage(){
  pgMist=lv_obj_create(lv_scr_act());stylePage(pgMist);lv_obj_add_flag(pgMist,LV_OBJ_FLAG_HIDDEN);
  makeLabel(pgMist,"MIST / HUMIDITY",16,12,C_TEXT);
  lblMistSt=makeLabel(pgMist,"MIST: OFF",16,40,C_RED);
  makeGreenBtn(pgMist,"TURN ON",16,75,240,60,cb_mistOn);
  makeRedBtn(pgMist,"TURN OFF",270,75,240,60,cb_mistOff);
  lv_obj_t *card=lv_obj_create(pgMist);lv_obj_set_pos(card,16,155);styleCard(card,768,250);
  lv_obj_set_style_border_color(card,C_CYAN,0);makeLabel(card,"HUMIDITY THRESHOLDS",0,0,C_SUBTEXT);
  makeLabel(card,"Mist ON below (%):",0,28,C_TEXT);
  lblHumOnV=makeLabel(card,"ON below: 85%",0,50,C_CYAN);
  rollerHumOn=lv_roller_create(card);lv_roller_set_options(rollerHumOn,g_humOpts,LV_ROLLER_MODE_NORMAL);
  lv_obj_set_size(rollerHumOn,110,130);lv_obj_set_pos(rollerHumOn,220,20);
  lv_roller_set_visible_row_count(rollerHumOn,3);styleRoller(rollerHumOn);registerInteractive(rollerHumOn);
  makeLabel(card,"Mist OFF above (%):",380,28,C_TEXT);
  lblHumOffV=makeLabel(card,"OFF above: 95%",380,50,C_CYAN);
  rollerHumOff=lv_roller_create(card);lv_roller_set_options(rollerHumOff,g_humOpts,LV_ROLLER_MODE_NORMAL);
  lv_obj_set_size(rollerHumOff,110,130);lv_obj_set_pos(rollerHumOff,600,20);
  lv_roller_set_visible_row_count(rollerHumOff,3);styleRoller(rollerHumOff);registerInteractive(rollerHumOff);
  makeBtn(card,"APPLY THRESHOLDS",220,170,310,50,cb_applyHum);
  makeNavBtn(pgMist,"< HOME",16,425,160,45,cb_goHome);
}
void buildFanPage(){
  pgFan=lv_obj_create(lv_scr_act());stylePage(pgFan);lv_obj_add_flag(pgFan,LV_OBJ_FLAG_HIDDEN);
  makeLabel(pgFan,"FAN / CO2 CONTROL",16,12,C_TEXT);
  lblFanSt=makeLabel(pgFan,"FAN: OFF",16,40,C_RED);
  makeGreenBtn(pgFan,"TURN ON",16,75,240,60,cb_fanOn);
  makeRedBtn(pgFan,"TURN OFF",270,75,240,60,cb_fanOff);
  lv_obj_t *card=lv_obj_create(pgFan);lv_obj_set_pos(card,16,155);styleCard(card,768,250);
  lv_obj_set_style_border_color(card,C_PURPLE,0);makeLabel(card,"CO2 THRESHOLDS (PPM)",0,0,C_SUBTEXT);
  makeLabel(card,"Fan ON above (ppm):",0,28,C_TEXT);
  lblCO2OnV=makeLabel(card,"ON above: 800 ppm",0,50,C_PURPLE);
  rollerCO2On=lv_roller_create(card);lv_roller_set_options(rollerCO2On,g_co2Opts,LV_ROLLER_MODE_NORMAL);
  lv_obj_set_size(rollerCO2On,130,130);lv_obj_set_pos(rollerCO2On,220,20);
  lv_roller_set_visible_row_count(rollerCO2On,3);styleRoller(rollerCO2On);registerInteractive(rollerCO2On);
  makeLabel(card,"Fan OFF below (ppm):",380,28,C_TEXT);
  lblCO2OffV=makeLabel(card,"OFF below: 700 ppm",380,50,C_PURPLE);
  rollerCO2Off=lv_roller_create(card);lv_roller_set_options(rollerCO2Off,g_co2Opts,LV_ROLLER_MODE_NORMAL);
  lv_obj_set_size(rollerCO2Off,130,130);lv_obj_set_pos(rollerCO2Off,600,20);
  lv_roller_set_visible_row_count(rollerCO2Off,3);styleRoller(rollerCO2Off);registerInteractive(rollerCO2Off);
  makeBtn(card,"APPLY THRESHOLDS",220,170,310,50,cb_applyCO2);
  makeNavBtn(pgFan,"< HOME",16,425,160,45,cb_goHome);
}
void buildSchedPage(){
  pgSched=lv_obj_create(lv_scr_act());stylePage(pgSched);lv_obj_add_flag(pgSched,LV_OBJ_FLAG_HIDDEN);
  lblScTitle=makeLabel(pgSched,"SCHEDULE",16,8,C_TEXT);
  lv_obj_t *topCard=lv_obj_create(pgSched);lv_obj_set_pos(topCard,16,35);styleCard(topCard,768,50);
  makeLabel(topCard,"Slot:",0,8,C_SUBTEXT);lblScIdx=makeLabel(topCard,"Slot #0",50,8,C_TEXT);
  makeDarkBtn(pgSched,"#-",200,42,70,38,cb_sched);makeDarkBtn(pgSched,"#+",280,42,70,38,cb_sched);
  lblScEn=makeLabel(topCard,"ENABLED",380,8,C_GREEN);
  makeDarkBtn(pgSched,"TGL",560,42,100,38,cb_sched);
  lv_obj_t *tc=lv_obj_create(pgSched);lv_obj_set_pos(tc,16,100);styleCard(tc,370,90);
  lv_obj_set_style_border_color(tc,C_BLUE,0);makeLabel(tc,"TIME",0,0,C_SUBTEXT);
  lblScTime=makeLabel(tc,"6:00 AM",0,22,C_TEXT);
  makeDarkBtn(pgSched,"HR-",30,155,80,40,cb_sched);makeDarkBtn(pgSched,"HR+",120,155,80,40,cb_sched);
  makeDarkBtn(pgSched,"MN-",220,155,80,40,cb_sched);makeDarkBtn(pgSched,"MN+",310,155,80,40,cb_sched);
  lv_obj_t *dc=lv_obj_create(pgSched);lv_obj_set_pos(dc,404,100);styleCard(dc,380,90);
  lv_obj_set_style_border_color(dc,C_ORANGE,0);makeLabel(dc,"DURATION",0,0,C_SUBTEXT);
  lblScDur=makeLabel(dc,"3 min",0,22,C_TEXT);
  makeDarkBtn(pgSched,"D-",420,155,100,40,cb_sched);makeDarkBtn(pgSched,"D+",540,155,100,40,cb_sched);
  makeLabel(pgSched,"DAYS:",16,210,C_SUBTEXT);
  const char*dn[]={"Su","Mo","Tu","We","Th","Fr","Sa"};
  for(int d=0;d<7;d++)btnScDays[d]=makeDarkBtn(pgSched,dn[d],16+d*110,235,102,48,cb_sched);
  makeDarkBtn(pgSched,"ALL",16,295,120,40,cb_sched);makeDarkBtn(pgSched,"WKD",150,295,120,40,cb_sched);
  makeBtn(pgSched,"SAVE",16,360,230,60,cb_sched);
  makeDarkBtn(pgSched,"CLR",270,360,160,60,cb_sched);
  makeNavBtn(pgSched,"BACK",460,360,160,60,cb_goHome);updSchedDisp();
}
void buildRTCPage(){
  pgRTC=lv_obj_create(lv_scr_act());stylePage(pgRTC);lv_obj_add_flag(pgRTC,LV_OBJ_FLAG_HIDDEN);
  makeLabel(pgRTC,"SET RTC CLOCK",16,10,C_TEXT);
  lblRtcCur=makeLabel(pgRTC,"Current: --",16,45,C_SUBTEXT);
  lblRtcSet=makeLabel(pgRTC,"Set: --",16,75,C_ORANGE);
  const char*col[]={"YEAR","MONTH","DAY","HOUR","MIN","SEC"};
  const char*pBtn[]={"YR+","MO+","DY+","HR+","MI+","SE+"};
  const char*mBtn[]={"YR-","MO-","DY-","HR-","MI-","SE-"};
  int cx[]={16,144,272,400,528,656};
  for(int i=0;i<6;i++){makeLabel(pgRTC,col[i],cx[i]+20,115,C_SUBTEXT);
    makeDarkBtn(pgRTC,pBtn[i],cx[i],140,118,65,cb_rtc);makeDarkBtn(pgRTC,mBtn[i],cx[i],220,118,65,cb_rtc);}
  makeBtn(pgRTC,"APPLY",180,330,210,65,cb_rtc);makeNavBtn(pgRTC,"BACK",420,330,190,65,cb_goHome);
}

void buildSettingsPage(){
  pgSettings=lv_obj_create(lv_scr_act());stylePage(pgSettings);lv_obj_add_flag(pgSettings,LV_OBJ_FLAG_HIDDEN);
  makeLabel(pgSettings,"SETTINGS - BLE LOCK",16,6,C_TEXT);

  // Instructions
  lv_obj_t *infoCard=lv_obj_create(pgSettings);lv_obj_set_pos(infoCard,16,28);styleCard(infoCard,768,60);
  lv_obj_set_style_border_color(infoCard,C_BLUE,0);
  makeLabel(infoCard,"How to unlock: Open nRF Connect or LightBlue app on",0,0,C_SUBTEXT);
  makeLabel(infoCard,"your phone, find this device name, tap CONNECT.",0,18,C_SUBTEXT);

  lblSetName=makeLabel(pgSettings,"BLE Name: MushroomFarm",16,98,C_CYAN);
  lblSetEnabled=makeLabel(pgSettings,"BLE Lock: ON",350,98,C_GREEN);
  lblSetStatus=makeLabel(pgSettings,"",550,98,C_GREEN);
  lblSetEdit=makeLabel(pgSettings,"> _",16,118,C_ORANGE);
  lblSetInfo=makeLabel(pgSettings,"Waiting for phone...",16,138,C_ORANGE);

  int ky=158,kw=68,kh=34,gap=4;char txt[2]={0,0};
  const char *rows[]={"ABCDEFGHIJ","KLMNOPQRST","UVWXYZ0123","456789'-._","abcdefghij","klmnopqrst"};
  for(int r=0;r<6;r++){for(int i=0;i<10;i++){txt[0]=rows[r][i];
    makeDarkBtn(pgSettings,txt,16+i*(kw+gap),ky,kw,kh,cb_settings);}ky+=kh+gap;}

  ky+=4;
  makeDarkBtn(pgSettings,"SPC",16,ky,80,38,cb_settings);
  makeRedBtn(pgSettings,"DEL",104,ky,80,38,cb_settings);
  makeRedBtn(pgSettings,"CLR",192,ky,80,38,cb_settings);
  makeBtn(pgSettings,"SAVE",280,ky,100,38,cb_settings);
  makeDarkBtn(pgSettings,"TOGGLE",396,ky,110,38,cb_settings);
  makeNavBtn(pgSettings,"BACK",520,ky,100,38,cb_goHome);
}

// =====================================================
// SETUP
// =====================================================
void setup(){
  Serial.begin(115200);delay(500);
  Serial.println("Starting LCD...");
  loadPrefs();

  pinMode(GFX_BL,OUTPUT);digitalWrite(GFX_BL,HIGH);
  gfx->begin();gfx->fillScreen(0x0000);
  Wire.begin(TOUCH_SDA,TOUCH_SCL);ts.begin();ts.setRotation(ROTATION_INVERTED);

  lv_init();lv_tick_set_cb(my_tick_get);
  disp=lv_display_create(SCREEN_W,SCREEN_H);
  lv_display_set_flush_cb(disp,my_disp_flush);
  lv_display_set_buffers(disp,buf1,NULL,sizeof(buf1),LV_DISPLAY_RENDER_MODE_PARTIAL);
  indev=lv_indev_create();lv_indev_set_type(indev,LV_INDEV_TYPE_POINTER);
  lv_indev_set_read_cb(indev,my_touch_read);
  lv_obj_set_style_bg_color(lv_scr_act(),C_BG,0);

  initRollerOptions();
  buildHome();buildSprinklerPage();buildLightPage();
  buildMistPage();buildFanPage();buildSchedPage();
  buildRTCPage();buildSettingsPage();
  applyLockState();

  bodySerial.begin(115200,SERIAL_8N1,LCD_RX_FROM_SLAVE,LCD_TX_TO_SLAVE);
  bodySerial.setPins(LCD_RX_FROM_SLAVE,LCD_TX_TO_SLAVE,-1,-1);

  initBLE();
  Serial.println("=== LCD READY ===");
}

// =====================================================
// LOOP
// =====================================================
void loop(){
  while(bodySerial.available()){
    String line=bodySerial.readStringUntil('\n');line.trim();
    if(line.length()>0){parseStatus(line);updateHome();}
  }
  if(Serial.available()){
    String cmd=Serial.readStringUntil('\n');cmd.trim();
    if(cmd.equalsIgnoreCase("UNLOCK")){bleClientConnected=true;applyLockState();}
    else if(cmd.equalsIgnoreCase("LOCK")){bleClientConnected=false;bleLastDisconnect=0;applyLockState();}
    else{cmd.toUpperCase();if(cmd=="GET")sendCommand("GET_STATUS");else if(cmd.length()>0)sendCommand(cmd);}
  }
  static unsigned long lastReq=0;
  if(millis()-lastReq>3000){lastReq=millis();bodySerial.println("GET_STATUS");}

  checkLockChange();
  checkBodyConnection();
  lv_timer_handler();
  delay(5);
}