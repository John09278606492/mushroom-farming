#include <Wire.h>
#include <RTClib.h>
#include <DHT.h>
#include <HardwareSerial.h>
#include <EEPROM.h>

// =========================
// EEPROM
// =========================
#define EEPROM_SIZE       512
#define EEPROM_MAGIC_ADDR 0
#define EEPROM_MAGIC_VAL  0xB2
#define EEPROM_DATA_ADDR  1

// =========================
// PINS (unchanged)
// =========================
#define DHT_PIN              4
#define DHT_TYPE             DHT22
#define FLOAT_PIN            18
#define SSR_MIST_PIN         12
#define RELAY_REFILL_PIN     13
#define RELAY_SPRINKLER_PIN  19
#define RELAY_FAN_PIN        23
#define RELAY_LIGHT_PIN      25
#define CO2_RX_PIN           16
#define CO2_TX_PIN           17
#define MASTER_RX_PIN        26
#define MASTER_TX_PIN        27
#define RTC_SDA_PIN          21
#define RTC_SCL_PIN          22

#define SSR_ON   HIGH
#define SSR_OFF  LOW
#define RELAY_ON  HIGH
#define RELAY_OFF LOW

// =========================
// OBJECTS
// =========================
DHT dht(DHT_PIN, DHT_TYPE);
RTC_DS3231 rtc;
HardwareSerial co2Serial(2);
HardwareSerial lcdSerial(1);
bool rtcAvailable = false;

// =========================
// SETTINGS (persisted)
// =========================
float humidityOnThreshold  = 85.0;
float humidityOffThreshold = 95.0;
int   co2FanOnThreshold    = 800;
int   co2FanOffThreshold   = 700;
bool  autoMode             = true;

// =========================
// SCHEDULES (persisted)
// =========================
#define MAX_SCHEDULES 5

struct DeviceSchedule {
  bool enabled;
  int  hour;
  int  minute;
  int  durationMin;
  bool days[7];
};

DeviceSchedule sprinklerSchedules[MAX_SCHEDULES];
DeviceSchedule lightSchedules[MAX_SCHEDULES];
int numSprinklerSchedules = 0;
int numLightSchedules     = 0;

bool sprinklerFiredThisMinute[MAX_SCHEDULES] = {false};
bool lightFiredThisMinute[MAX_SCHEDULES]     = {false};
int  lastCheckedMinute = -1;

// =========================
// EEPROM
// =========================
struct SavedSettings {
  bool  autoMode;
  float humOn, humOff;
  int   co2On, co2Off;
  int   numSprScheds, numLightScheds;
  DeviceSchedule sprScheds[MAX_SCHEDULES];
  DeviceSchedule lightScheds[MAX_SCHEDULES];
};

void saveSettings() {
  SavedSettings d;
  d.autoMode=autoMode; d.humOn=humidityOnThreshold; d.humOff=humidityOffThreshold;
  d.co2On=co2FanOnThreshold; d.co2Off=co2FanOffThreshold;
  d.numSprScheds=numSprinklerSchedules; d.numLightScheds=numLightSchedules;
  for(int i=0;i<MAX_SCHEDULES;i++){d.sprScheds[i]=sprinklerSchedules[i];d.lightScheds[i]=lightSchedules[i];}
  EEPROM.write(EEPROM_MAGIC_ADDR,EEPROM_MAGIC_VAL);
  EEPROM.put(EEPROM_DATA_ADDR,d); EEPROM.commit();
  Serial.println("EEPROM SAVED");
}

bool loadSettings() {
  if(EEPROM.read(EEPROM_MAGIC_ADDR)!=EEPROM_MAGIC_VAL) return false;
  SavedSettings d; EEPROM.get(EEPROM_DATA_ADDR,d);
  autoMode=d.autoMode; humidityOnThreshold=d.humOn; humidityOffThreshold=d.humOff;
  co2FanOnThreshold=d.co2On; co2FanOffThreshold=d.co2Off;
  numSprinklerSchedules=d.numSprScheds; numLightSchedules=d.numLightScheds;
  for(int i=0;i<MAX_SCHEDULES;i++){sprinklerSchedules[i]=d.sprScheds[i];lightSchedules[i]=d.lightScheds[i];}
  if(numSprinklerSchedules<0||numSprinklerSchedules>MAX_SCHEDULES) numSprinklerSchedules=0;
  if(numLightSchedules<0||numLightSchedules>MAX_SCHEDULES) numLightSchedules=0;
  Serial.println("EEPROM LOADED"); return true;
}

// =========================
// STATES
// =========================
bool mistState=false, refillState=false, sprinklerState=false, fanState=false, lightState=false;
unsigned long lastSensorReadMs=0, lastStatusSendMs=0;
unsigned long sprinklerStopMs=0, lightStopMs=0;
float humidity=NAN, temperature=NAN;
int co2ppm=-1; bool lowWater=false;
byte co2Cmd[9]={0xFF,0x01,0x86,0,0,0,0,0,0x79};

// =========================
// OUTPUTS
// =========================
void setMist(bool on)      {digitalWrite(SSR_MIST_PIN,on?SSR_ON:SSR_OFF);            mistState=on;     }
void setRefill(bool on)    {digitalWrite(RELAY_REFILL_PIN,on?RELAY_ON:RELAY_OFF);     refillState=on;   }
void setSprinkler(bool on) {digitalWrite(RELAY_SPRINKLER_PIN,on?RELAY_ON:RELAY_OFF);  sprinklerState=on;}
void setFan(bool on)       {digitalWrite(RELAY_FAN_PIN,on?RELAY_ON:RELAY_OFF);        fanState=on;      }
void setLight(bool on)     {digitalWrite(RELAY_LIGHT_PIN,on?RELAY_ON:RELAY_OFF);      lightState=on;    }

// =========================
// SENSORS
// =========================
void readDHT(){float h=dht.readHumidity(),t=dht.readTemperature();if(!isnan(h)&&!isnan(t)){humidity=h;temperature=t;}}
void readFloatSwitch(){lowWater=(digitalRead(FLOAT_PIN)==LOW);}
void readCO2(){
  while(co2Serial.available())co2Serial.read();
  co2Serial.write(co2Cmd,9);delay(100);
  if(co2Serial.available()>=9){byte r[9];co2Serial.readBytes(r,9);if(r[0]==0xFF&&r[1]==0x86)co2ppm=(r[2]<<8)|r[3];}
}

// =========================
// RTC
// =========================
String getTimeString(){
  if(!rtcAvailable)return"RTC_ERR";
  DateTime now=rtc.now(); char buf[25];
  snprintf(buf,sizeof(buf),"%04d-%02d-%02d %02d:%02d:%02d",now.year(),now.month(),now.day(),now.hour(),now.minute(),now.second());
  return String(buf);
}
String getDayName(int d){const char*n[]={"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};return(d>=0&&d<7)?n[d]:"?";}
String formatTime12h(int hour,int minute){
  String ap="AM";int h=hour;
  if(h==0)h=12;else if(h==12)ap="PM";else if(h>12){h-=12;ap="PM";}
  char buf[10];snprintf(buf,sizeof(buf),"%d:%02d%s",h,minute,ap.c_str());return String(buf);
}

// =========================
// SCHEDULE CHECKER — ALWAYS runs
// =========================
void resetMinuteFlags(int m){
  if(m!=lastCheckedMinute){lastCheckedMinute=m;
    for(int i=0;i<MAX_SCHEDULES;i++){sprinklerFiredThisMinute[i]=false;lightFiredThisMinute[i]=false;}}
}

void checkScheduleArray(DeviceSchedule s[],int cnt,bool fired[],int day,int hr,int mn,
  void(*setDev)(bool),unsigned long &stopMs,const char*name){
  for(int i=0;i<cnt;i++){
    if(!s[i].enabled||fired[i]||!s[i].days[day])continue;
    if(hr==s[i].hour&&mn==s[i].minute){
      setDev(true);stopMs=millis()+(unsigned long)s[i].durationMin*60UL*1000UL;fired[i]=true;
      Serial.printf("%s SCHED#%d FIRED %dmin\n",name,i,s[i].durationMin);
    }
  }
}

void checkAllSchedules(){
  if(!rtcAvailable)return;
  DateTime now=rtc.now();int d=now.dayOfTheWeek(),h=now.hour(),m=now.minute();
  resetMinuteFlags(m);

  // Sprinkler — duration in MINUTES
  for(int i=0;i<numSprinklerSchedules;i++){
    if(!sprinklerSchedules[i].enabled||sprinklerFiredThisMinute[i]||!sprinklerSchedules[i].days[d])continue;
    if(h==sprinklerSchedules[i].hour&&m==sprinklerSchedules[i].minute){
      setSprinkler(true);
      sprinklerStopMs=millis()+(unsigned long)sprinklerSchedules[i].durationMin*60UL*1000UL;
      sprinklerFiredThisMinute[i]=true;
      Serial.printf("SPR SCHED#%d FIRED %dmin\n",i,sprinklerSchedules[i].durationMin);
    }
  }

  // Light — duration in HOURS
  for(int i=0;i<numLightSchedules;i++){
    if(!lightSchedules[i].enabled||lightFiredThisMinute[i]||!lightSchedules[i].days[d])continue;
    if(h==lightSchedules[i].hour&&m==lightSchedules[i].minute){
      setLight(true);
      lightStopMs=millis()+(unsigned long)lightSchedules[i].durationMin*3600UL*1000UL;
      lightFiredThisMinute[i]=true;
      Serial.printf("LGT SCHED#%d FIRED %dhr\n",i,lightSchedules[i].durationMin);
    }
  }

  if(sprinklerState&&sprinklerStopMs>0&&millis()>=sprinklerStopMs){setSprinkler(false);sprinklerStopMs=0;}
  if(lightState&&lightStopMs>0&&millis()>=lightStopMs){setLight(false);lightStopMs=0;}
}

// =========================
// AUTO LOGIC — threshold only
// =========================
void runAutoLogic(){
  if(!autoMode)return;
  if(!isnan(humidity)){
    if(humidity<humidityOnThreshold&&!mistState)setMist(true);
    else if(humidity>humidityOffThreshold&&mistState)setMist(false);
  }
  if(lowWater&&!refillState)setRefill(true);
  else if(!lowWater&&refillState)setRefill(false);
  if(co2ppm>=0){
    if(co2ppm>co2FanOnThreshold&&!fanState)setFan(true);
    else if(co2ppm<co2FanOffThreshold&&fanState)setFan(false);
  }
}

// =========================
// BUILD SCHEDULE STRING
// =========================
String buildSchedStr(DeviceSchedule s[],int cnt,bool isHours=false){
  if(cnt==0)return"NONE";
  String r="";
  for(int i=0;i<cnt;i++){
    
    if(i>0)r+="|";
    r+=String(i)+":"+String(s[i].enabled?"ON":"OFF")+":";
    r+=formatTime12h(s[i].hour,s[i].minute)+":";
    r+=String(s[i].durationMin)+(isHours?"h":"m")+":";
    for(int d=0;d<7;d++)if(s[i].days[d])r+=getDayName(d);
  }
  return r;
}

// =========================
// STATUS
// =========================
void sendStatusToMaster(){
  String p="STATUS,"
    "AUTO="+String(autoMode?1:0)+","
    "H="+String(isnan(humidity)?0:humidity,1)+","
    "T="+String(isnan(temperature)?0:temperature,1)+","
    "CO2="+String(co2ppm<0?0:co2ppm)+","
    "LOWWATER="+String(lowWater?1:0)+","
    "MIST="+String(mistState?1:0)+","
    "REFILL="+String(refillState?1:0)+","
    "SPRINKLER="+String(sprinklerState?1:0)+","
    "FAN="+String(fanState?1:0)+","
    "LIGHT="+String(lightState?1:0)+","
    "HUM_ON="+String(humidityOnThreshold,0)+","
    "HUM_OFF="+String(humidityOffThreshold,0)+","
    "CO2_ON="+String(co2FanOnThreshold)+","
    "CO2_OFF="+String(co2FanOffThreshold)+","
    "SPR_SCHED="+buildSchedStr(sprinklerSchedules,numSprinklerSchedules,false)+","
    "LGT_SCHED="+buildSchedStr(lightSchedules,numLightSchedules,true)+","
    "TIME="+getTimeString();
  lcdSerial.println(p);
  Serial.println(p);
}

// =========================
// PARSE SCHEDULE
// =========================
void applySchedule(DeviceSchedule s[],int &cnt,String cmd){
  int cp;
  cp=cmd.indexOf(',');if(cp<0)return;int idx=cmd.substring(0,cp).toInt();cmd=cmd.substring(cp+1);
  if(idx<0||idx>=MAX_SCHEDULES)return;
  cp=cmd.indexOf(',');if(cp<0)return;bool en=cmd.substring(0,cp).toInt();cmd=cmd.substring(cp+1);
  cp=cmd.indexOf(',');if(cp<0)return;int hr=cmd.substring(0,cp).toInt();cmd=cmd.substring(cp+1);
  cp=cmd.indexOf(',');if(cp<0)return;int mn=cmd.substring(0,cp).toInt();cmd=cmd.substring(cp+1);
  cp=cmd.indexOf(',');if(cp<0)return;int dur=cmd.substring(0,cp).toInt();cmd=cmd.substring(cp+1);
  bool days[7]={false};
  for(int i=0;i<(int)cmd.length();i++){int d=cmd.charAt(i)-'0';if(d>=0&&d<7)days[d]=true;}
  s[idx].enabled=en;s[idx].hour=hr;s[idx].minute=mn;s[idx].durationMin=dur;
  for(int d=0;d<7;d++)s[idx].days[d]=days[d];
  if(idx>=cnt)cnt=idx+1;
}

void clearScheds(DeviceSchedule s[],int &cnt){
  cnt=0;for(int i=0;i<MAX_SCHEDULES;i++){
    s[i].enabled=false;s[i].hour=0;s[i].minute=0;s[i].durationMin=3;
    for(int d=0;d<7;d++)s[i].days[d]=false;}
}

// =========================
// COMMAND HANDLER
// =========================
void handleCommand(String cmd){
  cmd.trim();if(cmd.length()==0)return;
  String up=cmd;up.toUpperCase();
  Serial.println("CMD: "+cmd);
  bool handled=true;

  if      (up=="AUTO_ON")       {autoMode=true; saveSettings();}
  else if (up=="AUTO_OFF")      {autoMode=false;saveSettings();}
  else if (up=="MIST_ON")       setMist(true);
  else if (up=="MIST_OFF")      setMist(false);
  else if (up=="REFILL_ON")     setRefill(true);
  else if (up=="REFILL_OFF")    setRefill(false);
  else if (up=="SPRINKLER_ON")  {setSprinkler(true); sprinklerStopMs=0;}
  else if (up=="SPRINKLER_OFF") {setSprinkler(false);sprinklerStopMs=0;}
  else if (up=="FAN_ON")        setFan(true);
  else if (up=="FAN_OFF")       setFan(false);
  else if (up=="LIGHT_ON")      {setLight(true); lightStopMs=0;}
  else if (up=="LIGHT_OFF")     {setLight(false);lightStopMs=0;}
  else if (up=="GET_STATUS")    {sendStatusToMaster();return;}
  else if (up.startsWith("SET_RTC=")&&rtcAvailable){
    String ts=cmd.substring(8);
    rtc.adjust(DateTime(ts.substring(0,4).toInt(),ts.substring(5,7).toInt(),
      ts.substring(8,10).toInt(),ts.substring(11,13).toInt(),
      ts.substring(14,16).toInt(),ts.substring(17,19).toInt()));
  }
  else if (up.startsWith("SET_HUM_ON="))  {humidityOnThreshold=cmd.substring(11).toFloat(); saveSettings();}
  else if (up.startsWith("SET_HUM_OFF=")) {humidityOffThreshold=cmd.substring(12).toFloat();saveSettings();}
  else if (up.startsWith("SET_CO2_ON="))  {co2FanOnThreshold=cmd.substring(11).toInt();     saveSettings();}
  else if (up.startsWith("SET_CO2_OFF=")) {co2FanOffThreshold=cmd.substring(12).toInt();    saveSettings();}
  else if (up.startsWith("SET_SPR_SCHED=")) {applySchedule(sprinklerSchedules,numSprinklerSchedules,cmd.substring(14));saveSettings();}
  else if (up=="CLEAR_SPR_SCHED")          {clearScheds(sprinklerSchedules,numSprinklerSchedules);saveSettings();}
  else if (up.startsWith("SET_LGT_SCHED=")){applySchedule(lightSchedules,numLightSchedules,cmd.substring(14));saveSettings();}
  else if (up=="CLEAR_LGT_SCHED")          {clearScheds(lightSchedules,numLightSchedules);saveSettings();}
  else {handled=false;}

  if(handled) sendStatusToMaster();
}

void readCommands(){while(lcdSerial.available())handleCommand(lcdSerial.readStringUntil('\n'));}

// =========================
// SETUP
// =========================
void setup(){
  Serial.begin(115200);
  EEPROM.begin(EEPROM_SIZE);
  Wire.begin(RTC_SDA_PIN,RTC_SCL_PIN);
  rtcAvailable=rtc.begin();
  Serial.println(rtcAvailable?"RTC OK":"RTC NOT FOUND");
  dht.begin();
  pinMode(FLOAT_PIN,INPUT_PULLUP);
  pinMode(SSR_MIST_PIN,OUTPUT);pinMode(RELAY_REFILL_PIN,OUTPUT);
  pinMode(RELAY_SPRINKLER_PIN,OUTPUT);pinMode(RELAY_FAN_PIN,OUTPUT);pinMode(RELAY_LIGHT_PIN,OUTPUT);
  setMist(false);setRefill(false);setSprinkler(false);setFan(false);setLight(false);
  if(!loadSettings()){clearScheds(sprinklerSchedules,numSprinklerSchedules);clearScheds(lightSchedules,numLightSchedules);saveSettings();}
  co2Serial.begin(9600,SERIAL_8N1,CO2_RX_PIN,CO2_TX_PIN);
  lcdSerial.begin(115200,SERIAL_8N1,MASTER_RX_PIN,MASTER_TX_PIN);
  Serial.println("BODY READY");
}

// =========================
// LOOP
// =========================
void loop(){
  readCommands();
  if(millis()-lastSensorReadMs>=2000){
    lastSensorReadMs=millis();
    readDHT();readFloatSwitch();readCO2();
    runAutoLogic();
    checkAllSchedules();
  }
  if(millis()-lastStatusSendMs>=2000){lastStatusSendMs=millis();sendStatusToMaster();}
}