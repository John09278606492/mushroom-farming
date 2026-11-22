// =====================================================
// Smart Mushroom Farm — HMI (ESP32-S3 JC8048W550, 800x480, LVGL 9)
//
// Talks to the body ESP32 over UART with the same protocol as the
// students' original brain.ino (STATUS lines in, commands out).
// UI: dark smart-home dashboard, big cards, icons, live bars.
// Screen updates only touch what changed, so nothing blinks.
// =====================================================
#include <Arduino.h>
#include <HardwareSerial.h>
#include <Arduino_GFX_Library.h>
#include <Wire.h>
#include <TAMC_GT911.h>
#include <lvgl.h>
#include "src/icons/icons.h"
#include "ui_types.h"

extern "C" {
LV_FONT_DECLARE(lv_font_montserrat_16)
LV_FONT_DECLARE(lv_font_montserrat_20)
LV_FONT_DECLARE(lv_font_montserrat_28)
LV_FONT_DECLARE(lv_font_montserrat_40)
}
#define F14 &lv_font_montserrat_14
#define F16 &lv_font_montserrat_16
#define F20 &lv_font_montserrat_20
#define F28 &lv_font_montserrat_28
#define F40 &lv_font_montserrat_40

// =====================================================
// UART to the body
// =====================================================
#define LCD_TX_TO_SLAVE   43
#define LCD_RX_FROM_SLAVE 44
HardwareSerial bodySerial(1);

// =====================================================
// DISPLAY
// =====================================================
#define GFX_BL 2
#define SCREEN_W_PX 800
Arduino_ESP32RGBPanel *rgbpanel = new Arduino_ESP32RGBPanel(
  40,41,39,42, 45,48,47,21,14, 5,6,7,15,16,4, 8,3,46,9,1,
  0,8,4,8, 0,8,4,8, 1,16000000,
  false, 0, 0, SCREEN_W_PX * 10);  // bounce buffer: keeps the picture steady
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
#define BUF_LINES 40
static lv_color_t buf1[SCREEN_W * BUF_LINES];
static lv_display_t *disp;
static lv_indev_t *indev;
static uint32_t my_tick_get(void){return millis();}

void my_disp_flush(lv_display_t *d,const lv_area_t *a,uint8_t *px){
  gfx->draw16bitRGBBitmap(a->x1,a->y1,(uint16_t*)px,a->x2-a->x1+1,a->y2-a->y1+1);
  lv_display_flush_ready(d);
}
// Touch with a filter. The GT911 sometimes reports a short touch at a random
// spot (noise from the box), which pressed buttons nobody touched. A press only
// counts after 3 reads in a row land in the same place; while pressed, a sudden
// far jump is ignored; a release needs 2 empty reads in a row.
void my_touch_read(lv_indev_t *drv,lv_indev_data_t *data){
  static bool down=false;
  static int16_t px=0,py=0;      // point reported to LVGL
  static int16_t cx=-1,cy=-1;    // candidate for a new press
  static uint8_t same=0,empty=0;
  ts.read();
  bool t=ts.isTouched&&ts.touches>=1;
  int16_t x=ts.points[0].x,y=ts.points[0].y;
  if(t&&(x<0||x>=SCREEN_W||y<0||y>=SCREEN_H))t=false;

  if(t){
    empty=0;
    if(!down){
      if(cx>=0&&abs(x-cx)<30&&abs(y-cy)<30){if(same<255)same++;}else same=0;
      cx=x;cy=y;
      if(same>=2){down=true;px=x;py=y;}
    }else if(abs(x-px)<150&&abs(y-py)<150){
      px=x;py=y;                 // normal drag
    }
  }else{
    cx=-1;same=0;
    if(down&&++empty>=2)down=false;
  }
  data->point.x=px;data->point.y=py;
  data->state=down?LV_INDEV_STATE_PRESSED:LV_INDEV_STATE_RELEASED;
}

// =====================================================
// COLOURS
// =====================================================
#define C_BG     lv_color_hex(0x0B1220)
#define C_SURF   lv_color_hex(0x141C2F)
#define C_SURF2  lv_color_hex(0x1F2A44)
#define C_LINE   lv_color_hex(0x27324B)
#define C_TEXT   lv_color_hex(0xF1F5F9)
#define C_MUTED  lv_color_hex(0x8A97B1)
#define C_OK     lv_color_hex(0x4ADE80)
#define C_BAD    lv_color_hex(0xF87171)
#define C_WARN   lv_color_hex(0xFBBF24)
#define A_HUM    lv_color_hex(0x22D3EE)
#define A_TEMP   lv_color_hex(0xFB923C)
#define A_CO2    lv_color_hex(0xA78BFA)
#define A_SPR    lv_color_hex(0x34D399)
#define A_LIGHT  lv_color_hex(0xFACC15)
#define A_MIST   lv_color_hex(0x38BDF8)
#define A_FAN    lv_color_hex(0x2DD4BF)
#define A_WATER  lv_color_hex(0x60A5FA)
#define A_BRAND  lv_color_hex(0x34D399)

// =====================================================
// STATE FROM THE BODY
// =====================================================
float humidity=0,temperature=0;
int co2ppm=0;
bool lowWater=false,mistState=false,refillState=false;
bool sprinklerState=false,fanState=false,lightState=false;
bool autoMode=true;
String rtcTime="";
String sprSchedText="NONE",lgtSchedText="NONE";
float humOn=85,humOff=95;
int co2On=800,co2Off=700;
bool haveData=false;

bool bodyConnected=false;
unsigned long lastBodyRx=0;
#define BODY_TIMEOUT_MS 6000

// Schedules, parsed from SPR_SCHED / LGT_SCHED
Slot sprSlots[MAX_SLOTS],lgtSlots[MAX_SLOTS];

// Schedule editor
SchedTarget schedTarget=SCHED_SPR;
int schedIdx=0;bool schedEn=true;
int schedHr=6,schedMn=0,schedDur=3;
bool schedDays[7]={1,1,1,1,1,1,1};
// Clock editor
int rtcY=2026,rtcMo=1,rtcD=1,rtcH=0,rtcMi=0,rtcS=0;

void sendCommand(const String&cmd){
  if(!bodyConnected && cmd!="GET_STATUS")return;
  if(bodySerial.availableForWrite()>(int)cmd.length()+2)bodySerial.println(cmd);
}

// =====================================================
// TEXT HELPERS
// =====================================================
String getFieldValue(String data,String key){
  String sk=","+key+"=";int start=data.indexOf(sk);
  if(start>=0){start+=sk.length();}
  else{sk=key+"=";int p=data.indexOf(sk);if(p==7)start=7+sk.length();else return"";}
  int end=data.indexOf(',',start);if(end<0)end=data.length();
  return data.substring(start,end);
}
String formatTime12h(int h,int m){
  const char*ap=h>=12?"PM":"AM";int h2=h%12;if(h2==0)h2=12;
  char b[12];snprintf(b,sizeof(b),"%d:%02d %s",h2,m,ap);return String(b);
}
static const char* DAY_SHORT[7]={"Su","Mo","Tu","We","Th","Fr","Sa"};
String daysText(const bool d[7]){
  int n=0;for(int i=0;i<7;i++)n+=d[i];
  if(n==7)return "Every day";
  if(n==0)return "No days";
  if(n==5&&!d[0]&&!d[6])return "Weekdays";
  if(n==2&&d[0]&&d[6])return "Weekends";
  String s="";for(int i=0;i<7;i++)if(d[i]){if(s.length())s+=" ";s+=DAY_SHORT[i];}
  return s;
}
int dayOfWeek(int y,int m,int d){
  static const int t[]={0,3,2,5,0,3,5,1,4,6,2,4};
  if(m<3)y-=1;return (y+y/4-y/100+y/400+t[m-1]+d)%7;
}

int parseH12(const String&t,int&mn){
  int c=t.indexOf(':');if(c<0){mn=0;return 0;}
  int h=t.substring(0,c).toInt();mn=t.substring(c+1,c+3).toInt();
  bool pm=t.indexOf("PM")>=0;if(h==12)h=0;if(pm)h+=12;return h;
}
// Entry format from the body: "0:ON:6:00 AM:3m:SuMoTuWeThFrSa", entries split by '|'
void parseSlots(const String&txt,Slot*s){
  for(int i=0;i<MAX_SLOTS;i++)s[i].used=false;
  if(txt=="NONE"||txt.length()==0)return;
  int start=0;
  while(start<(int)txt.length()){
    int p=txt.indexOf('|',start);if(p<0)p=txt.length();
    String e=txt.substring(start,p);start=p+1;
    int c1=e.indexOf(':');int c2=e.indexOf(':',c1+1);
    int cl=e.lastIndexOf(':');int cp=e.lastIndexOf(':',cl-1);
    if(c1<0||c2<0||cp<=c2)continue;
    int idx=e.substring(0,c1).toInt();if(idx<0||idx>=MAX_SLOTS)continue;
    Slot&x=s[idx];x.used=true;x.en=e.substring(c1+1,c2)=="ON";
    x.hr=parseH12(e.substring(c2+1,cp),x.mn);
    x.dur=e.substring(cp+1,cl).toInt();
    String ds=e.substring(cl+1);
    for(int d=0;d<7;d++)x.days[d]=ds.indexOf(DAY_SHORT[d])>=0;
  }
}

// =====================================================
// PARSE STATUS
// =====================================================
void parseStatus(String line){
  if(!line.startsWith("STATUS,"))return;
  lastBodyRx=millis();bodyConnected=true;haveData=true;
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
  v=getFieldValue(line,"SPR_SCHED");if(v.length()&&v!=sprSchedText){sprSchedText=v;parseSlots(v,sprSlots);}
  v=getFieldValue(line,"LGT_SCHED");if(v.length()&&v!=lgtSchedText){lgtSchedText=v;parseSlots(v,lgtSlots);}
}

// =====================================================
// "ONLY IF CHANGED" SETTERS — redraw nothing that did not change
// =====================================================
void setTextIf(lv_obj_t *l,const char *txt){
  if(!l)return;const char *cur=lv_label_get_text(l);
  if(cur&&strcmp(cur,txt)==0)return;lv_label_set_text(l,txt);
}
void setTextIf(lv_obj_t *l,const String &txt){setTextIf(l,txt.c_str());}
void setColorIf(lv_obj_t *o,lv_color_t c){
  if(!o)return;if(lv_color_eq(lv_obj_get_style_text_color(o,LV_PART_MAIN),c))return;
  lv_obj_set_style_text_color(o,c,0);
}
void setBgIf(lv_obj_t *o,lv_color_t c){
  if(!o)return;if(lv_color_eq(lv_obj_get_style_bg_color(o,LV_PART_MAIN),c))return;
  lv_obj_set_style_bg_color(o,c,0);
}
void setBorderIf(lv_obj_t *o,lv_color_t c){
  if(!o)return;if(lv_color_eq(lv_obj_get_style_border_color(o,LV_PART_MAIN),c))return;
  lv_obj_set_style_border_color(o,c,0);
}
void setTintIf(lv_obj_t *img,lv_color_t c){
  if(!img)return;if(lv_color_eq(lv_obj_get_style_image_recolor(img,LV_PART_MAIN),c))return;
  lv_obj_set_style_image_recolor(img,c,0);
}
void setBarIf(lv_obj_t *b,int v){
  if(!b)return;int lo=lv_bar_get_min_value(b),hi=lv_bar_get_max_value(b);
  if(v<lo)v=lo;if(v>hi)v=hi;
  if(lv_bar_get_value(b)==v)return;lv_bar_set_value(b,v,LV_ANIM_ON);
}
void setBarColorIf(lv_obj_t *b,lv_color_t c){
  if(!b)return;if(lv_color_eq(lv_obj_get_style_bg_color(b,LV_PART_INDICATOR),c))return;
  lv_obj_set_style_bg_color(b,c,LV_PART_INDICATOR);
}
void setChecked(lv_obj_t *o,bool on){
  if(!o)return;if(lv_obj_has_state(o,LV_STATE_CHECKED)==on)return;
  if(on)lv_obj_add_state(o,LV_STATE_CHECKED);else lv_obj_remove_state(o,LV_STATE_CHECKED);
}
void setHidden(lv_obj_t *o,bool hide){
  if(!o)return;if(lv_obj_has_flag(o,LV_OBJ_FLAG_HIDDEN)==hide)return;
  if(hide)lv_obj_add_flag(o,LV_OBJ_FLAG_HIDDEN);else lv_obj_remove_flag(o,LV_OBJ_FLAG_HIDDEN);
}

// =====================================================
// BUILDING BLOCKS
// =====================================================
lv_obj_t* card(lv_obj_t*par,int x,int y,int w,int h,int pad=16){
  lv_obj_t*o=lv_obj_create(par);lv_obj_remove_style_all(o);
  lv_obj_set_pos(o,x,y);lv_obj_set_size(o,w,h);
  lv_obj_set_style_bg_color(o,C_SURF,0);lv_obj_set_style_bg_opa(o,LV_OPA_COVER,0);
  lv_obj_set_style_radius(o,18,0);
  lv_obj_set_style_border_color(o,C_LINE,0);lv_obj_set_style_border_width(o,1,0);
  lv_obj_set_style_pad_all(o,pad,0);
  lv_obj_remove_flag(o,LV_OBJ_FLAG_SCROLLABLE);lv_obj_remove_flag(o,LV_OBJ_FLAG_CLICKABLE);
  return o;
}
void makeTappable(lv_obj_t*o,lv_event_cb_t cb,int code=0){
  lv_obj_add_flag(o,LV_OBJ_FLAG_CLICKABLE);
  lv_obj_set_style_bg_color(o,C_SURF2,LV_STATE_PRESSED);
  lv_obj_add_event_cb(o,cb,LV_EVENT_CLICKED,(void*)(intptr_t)code);
}
lv_obj_t* txt(lv_obj_t*par,const char*t,const lv_font_t*f,lv_color_t c,int x,int y){
  lv_obj_t*l=lv_label_create(par);lv_label_set_text(l,t);
  lv_obj_set_style_text_font(l,f,0);lv_obj_set_style_text_color(l,c,0);
  lv_obj_set_pos(l,x,y);return l;
}
lv_obj_t* icon(lv_obj_t*par,const lv_image_dsc_t*src,lv_color_t c){
  lv_obj_t*i=lv_image_create(par);lv_image_set_src(i,src);
  lv_obj_set_style_image_recolor(i,c,0);lv_obj_set_style_image_recolor_opa(i,LV_OPA_COVER,0);
  return i;
}
// rounded, softly tinted square with an icon in it
lv_obj_t* badge(lv_obj_t*par,const lv_image_dsc_t*src,lv_color_t acc,int x,int y,int sz,lv_obj_t**iconOut=NULL){
  lv_obj_t*b=lv_obj_create(par);lv_obj_remove_style_all(b);
  lv_obj_set_pos(b,x,y);lv_obj_set_size(b,sz,sz);
  lv_obj_set_style_radius(b,sz/3.5,0);
  lv_obj_set_style_bg_color(b,lv_color_mix(acc,C_SURF,48),0);lv_obj_set_style_bg_opa(b,LV_OPA_COVER,0);
  lv_obj_remove_flag(b,LV_OBJ_FLAG_CLICKABLE);lv_obj_remove_flag(b,LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_t*i=icon(b,src,acc);lv_obj_center(i);
  if(iconOut)*iconOut=i;return b;
}
lv_obj_t* btn(lv_obj_t*par,const char*label,int x,int y,int w,int h,lv_color_t bg,lv_color_t fg,
              lv_event_cb_t cb,int code=0,const lv_font_t*f=F20){
  lv_obj_t*b=lv_button_create(par);lv_obj_remove_style_all(b);
  lv_obj_set_pos(b,x,y);lv_obj_set_size(b,w,h);
  lv_obj_set_style_radius(b,14,0);
  lv_obj_set_style_bg_color(b,bg,0);lv_obj_set_style_bg_opa(b,LV_OPA_COVER,0);
  lv_obj_set_style_bg_color(b,lv_color_mix(lv_color_white(),bg,50),LV_STATE_PRESSED);
  lv_obj_add_event_cb(b,cb,LV_EVENT_CLICKED,(void*)(intptr_t)code);
  lv_obj_t*l=lv_label_create(b);lv_label_set_text(l,label);
  lv_obj_set_style_text_font(l,f,0);lv_obj_set_style_text_color(l,fg,0);lv_obj_center(l);
  return b;
}
lv_obj_t* bar(lv_obj_t*par,int x,int y,int w,int h,int lo,int hi,lv_color_t acc){
  lv_obj_t*b=lv_bar_create(par);lv_obj_remove_style_all(b);
  lv_obj_set_pos(b,x,y);lv_obj_set_size(b,w,h);lv_bar_set_range(b,lo,hi);lv_bar_set_value(b,lo,LV_ANIM_OFF);
  lv_obj_set_style_bg_color(b,C_LINE,0);lv_obj_set_style_bg_opa(b,LV_OPA_COVER,0);lv_obj_set_style_radius(b,h/2,0);
  lv_obj_set_style_bg_color(b,acc,LV_PART_INDICATOR);lv_obj_set_style_bg_opa(b,LV_OPA_COVER,LV_PART_INDICATOR);
  lv_obj_set_style_radius(b,h/2,LV_PART_INDICATOR);
  lv_obj_set_style_anim_duration(b,700,0);
  return b;
}
// value + unit on one baseline
lv_obj_t* valueRow(lv_obj_t*par,int x,int y,const lv_font_t*vf,const char*unit,lv_obj_t**valOut){
  lv_obj_t*row=lv_obj_create(par);lv_obj_remove_style_all(row);
  lv_obj_set_pos(row,x,y);lv_obj_set_size(row,LV_SIZE_CONTENT,LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(row,LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(row,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_END,LV_FLEX_ALIGN_END);
  lv_obj_set_style_pad_column(row,6,0);
  lv_obj_remove_flag(row,LV_OBJ_FLAG_CLICKABLE);
  *valOut=lv_label_create(row);lv_label_set_text(*valOut,"--");
  lv_obj_set_style_text_font(*valOut,vf,0);lv_obj_set_style_text_color(*valOut,C_TEXT,0);
  lv_obj_t*u=lv_label_create(row);lv_label_set_text(u,unit);
  lv_obj_set_style_text_font(u,F20,0);lv_obj_set_style_text_color(u,C_MUTED,0);
  lv_obj_set_style_pad_bottom(u,vf==F40?6:3,0);
  return row;
}
// small rounded "chip" with text, returns the label
lv_obj_t* chip(lv_obj_t*par,lv_obj_t**boxOut){
  lv_obj_t*c=lv_obj_create(par);lv_obj_remove_style_all(c);
  lv_obj_set_size(c,LV_SIZE_CONTENT,LV_SIZE_CONTENT);
  lv_obj_set_style_radius(c,LV_RADIUS_CIRCLE,0);
  lv_obj_set_style_bg_color(c,C_SURF2,0);lv_obj_set_style_bg_opa(c,LV_OPA_COVER,0);
  lv_obj_set_style_pad_hor(c,12,0);lv_obj_set_style_pad_ver(c,5,0);
  lv_obj_remove_flag(c,LV_OBJ_FLAG_CLICKABLE);
  lv_obj_t*l=lv_label_create(c);lv_label_set_text(l,"");
  lv_obj_set_style_text_font(l,F14,0);lv_obj_set_style_text_color(l,C_MUTED,0);
  if(boxOut)*boxOut=c;return l;
}
lv_obj_t* roller(lv_obj_t*par,const char*opts,int x,int y,int w,lv_color_t acc){
  lv_obj_t*r=lv_roller_create(par);lv_roller_set_options(r,opts,LV_ROLLER_MODE_NORMAL);
  lv_roller_set_visible_row_count(r,3);
  lv_obj_set_pos(r,x,y);lv_obj_set_width(r,w);
  lv_obj_set_style_bg_color(r,C_SURF2,0);lv_obj_set_style_bg_opa(r,LV_OPA_COVER,0);
  lv_obj_set_style_border_width(r,0,0);lv_obj_set_style_radius(r,14,0);
  lv_obj_set_style_text_font(r,F20,0);lv_obj_set_style_text_color(r,C_MUTED,0);
  lv_obj_set_style_text_align(r,LV_TEXT_ALIGN_CENTER,0);
  lv_obj_set_style_bg_color(r,acc,LV_PART_SELECTED);lv_obj_set_style_bg_opa(r,LV_OPA_COVER,LV_PART_SELECTED);
  lv_obj_set_style_text_color(r,C_BG,LV_PART_SELECTED);
  lv_obj_set_style_radius(r,10,LV_PART_SELECTED);
  return r;
}

// =====================================================
// TOAST (short message at the bottom)
// =====================================================
lv_obj_t *toastBox=NULL,*toastLbl=NULL;lv_timer_t *toastTimer=NULL;
void toastHide(lv_timer_t*t){setHidden(toastBox,true);lv_timer_pause(t);}
void showToast(const char*msg){
  setTextIf(toastLbl,msg);setHidden(toastBox,false);
  lv_timer_reset(toastTimer);lv_timer_resume(toastTimer);
}
bool needBody(){
  if(bodyConnected)return true;
  showToast(LV_SYMBOL_WARNING "  Body controller not connected");return false;
}

// =====================================================
// PAGES
// =====================================================
lv_obj_t *pgHome,*pgSpr,*pgLgt,*pgMist,*pgFan,*pgSchedList,*pgSched,*pgRTC;
lv_obj_t *schedReturnPage=NULL;
#define MAX_PILLS 10
lv_obj_t *pillDot[MAX_PILLS],*pillLbl[MAX_PILLS];int nPills=0;

lv_obj_t* newPage(bool hidden=true){
  lv_obj_t*p=lv_obj_create(lv_screen_active());lv_obj_remove_style_all(p);
  lv_obj_set_size(p,SCREEN_W,SCREEN_H);lv_obj_set_pos(p,0,0);
  lv_obj_set_style_bg_color(p,C_BG,0);lv_obj_set_style_bg_opa(p,LV_OPA_COVER,0);
  lv_obj_remove_flag(p,LV_OBJ_FLAG_SCROLLABLE);
  if(hidden)lv_obj_add_flag(p,LV_OBJ_FLAG_HIDDEN);
  return p;
}
void connectionPill(lv_obj_t*par){
  if(nPills>=MAX_PILLS)return;
  lv_obj_t*p=lv_obj_create(par);lv_obj_remove_style_all(p);
  lv_obj_set_size(p,LV_SIZE_CONTENT,36);lv_obj_align(p,LV_ALIGN_TOP_RIGHT,-16,18);
  lv_obj_set_style_radius(p,LV_RADIUS_CIRCLE,0);
  lv_obj_set_style_bg_color(p,C_SURF,0);lv_obj_set_style_bg_opa(p,LV_OPA_COVER,0);
  lv_obj_set_style_border_color(p,C_LINE,0);lv_obj_set_style_border_width(p,1,0);
  lv_obj_set_style_pad_hor(p,14,0);
  lv_obj_set_flex_flow(p,LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(p,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_CENTER,LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_column(p,8,0);lv_obj_remove_flag(p,LV_OBJ_FLAG_CLICKABLE);
  lv_obj_t*d=lv_obj_create(p);lv_obj_remove_style_all(d);lv_obj_set_size(d,10,10);
  lv_obj_set_style_radius(d,LV_RADIUS_CIRCLE,0);lv_obj_set_style_bg_opa(d,LV_OPA_COVER,0);
  lv_obj_set_style_bg_color(d,C_BAD,0);
  lv_obj_t*l=lv_label_create(p);lv_label_set_text(l,"Body offline");
  lv_obj_set_style_text_font(l,F14,0);lv_obj_set_style_text_color(l,C_MUTED,0);
  pillDot[nPills]=d;pillLbl[nPills]=l;nPills++;
}
void cb_goHome(lv_event_t*e);
void header(lv_obj_t*p,const char*title,const char*sub,const lv_image_dsc_t*ic,lv_color_t acc,
            lv_obj_t**titleOut=NULL,lv_event_cb_t backCb=NULL){
  lv_obj_t*b=btn(p,LV_SYMBOL_LEFT,16,12,52,52,C_SURF,C_TEXT,backCb?backCb:cb_goHome,0,F20);
  lv_obj_set_style_border_color(b,C_LINE,0);lv_obj_set_style_border_width(b,1,0);
  lv_obj_set_style_radius(b,16,0);
  badge(p,ic,acc,80,12,52);
  lv_obj_t*t=txt(p,title,F28,C_TEXT,146,10);
  txt(p,sub,F14,C_MUTED,146,44);
  if(titleOut)*titleOut=t;
  connectionPill(p);
}
void showPage(lv_obj_t*p){
  lv_obj_t*all[]={pgHome,pgSpr,pgLgt,pgMist,pgFan,pgSchedList,pgSched,pgRTC};
  for(lv_obj_t*o:all)if(o&&o!=p)setHidden(o,true);
  setHidden(p,false);
}

// =====================================================
// HOME WIDGETS
// =====================================================
SensorCard scHum,scTemp,scCO2;

Tile tSpr,tLgt,tMist,tFan;
Tile* tiles[4]={&tSpr,&tLgt,&tMist,&tFan};

lv_obj_t *lblTime=NULL,*lblDate=NULL;
lv_obj_t *lblWater=NULL,*waterIcon=NULL,*refillLbl=NULL,*refillBox=NULL;
lv_obj_t *btnAuto=NULL,*btnManual=NULL;
lv_obj_t *lblSchedSpr=NULL,*lblSchedLgt=NULL;

void buildSensorCard(SensorCard&s,int x,const char*name,const lv_image_dsc_t*ic,lv_color_t acc,
                     const char*unit,int lo,int hi){
  lv_obj_t*c=card(pgHome,x,72,248,164);
  badge(c,ic,acc,0,0,52);
  txt(c,name,F16,C_TEXT,66,4);
  s.sub=txt(c,"",F14,C_MUTED,66,28);
  s.chipLbl=chip(c,&s.chipBox);lv_obj_align(s.chipBox,LV_ALIGN_TOP_RIGHT,0,0);setHidden(s.chipBox,true);
  valueRow(c,0,62,F40,unit,&s.val);
  s.bar=bar(c,0,120,216,10,lo,hi,acc);
}

void cb_tileSwitch(lv_event_t*e);
void buildTile(Tile&t,int x,const char*name,const lv_image_dsc_t*ic,lv_color_t acc,
               lv_event_cb_t openCb,const char*onCmd,const char*offCmd,int idx){
  t.acc=acc;t.holdUntil=0;t.onCmd=onCmd;t.offCmd=offCmd;
  t.card=card(pgHome,x,248,183,120);
  makeTappable(t.card,openCb);
  t.icon=icon(t.card,ic,C_MUTED);lv_obj_set_pos(t.icon,0,0);
  t.sw=lv_switch_create(t.card);lv_obj_set_size(t.sw,58,32);lv_obj_align(t.sw,LV_ALIGN_TOP_RIGHT,0,4);
  lv_obj_set_style_bg_color(t.sw,C_LINE,LV_PART_MAIN);
  lv_obj_set_style_bg_color(t.sw,acc,LV_PART_INDICATOR|LV_STATE_CHECKED);
  lv_obj_set_style_bg_color(t.sw,C_TEXT,LV_PART_KNOB);
  lv_obj_add_event_cb(t.sw,cb_tileSwitch,LV_EVENT_VALUE_CHANGED,(void*)(intptr_t)idx);
  lv_obj_set_ext_click_area(t.sw,10);
  txt(t.card,name,F20,C_TEXT,0,54);
  t.state=txt(t.card,"OFF",F14,C_MUTED,0,80);
  lv_obj_t*chev=txt(t.card,LV_SYMBOL_RIGHT,F14,C_MUTED,0,0);lv_obj_align(chev,LV_ALIGN_BOTTOM_RIGHT,0,-2);
}
void tileLook(Tile&t,bool on){
  setBgIf(t.card,on?lv_color_mix(t.acc,C_SURF,46):C_SURF);
  setBorderIf(t.card,on?t.acc:C_LINE);
  setTintIf(t.icon,on?t.acc:C_MUTED);
  setTextIf(t.state,on?"ON":"OFF");setColorIf(t.state,on?t.acc:C_MUTED);
}

// =====================================================
// DEVICE PAGES
// =====================================================
DevUI dSpr,dLgt,dMist,dFan;
lv_obj_t *lblSprList=NULL,*lblLgtList=NULL,*lblSprList2=NULL,*lblLgtList2=NULL;
lv_obj_t *lblHumOnV,*lblHumOffV,*rollerHumOn,*rollerHumOff;
lv_obj_t *lblCO2OnV,*lblCO2OffV,*rollerCO2On,*rollerCO2Off;

void buildDevPage(DevUI&d,const char*title,const char*sub,const lv_image_dsc_t*ic64,const lv_image_dsc_t*ic40,
                  lv_color_t acc,lv_event_cb_t onCb,lv_event_cb_t offCb,
                  const char*infoTitle,const lv_image_dsc_t*infoIc,lv_color_t infoAcc,const char*infoUnit,int lo,int hi){
  d.acc=acc;d.pg=newPage();
  header(d.pg,title,sub,ic40,acc);
  lv_obj_t*h=card(d.pg,16,76,368,232);
  d.hero=lv_obj_create(h);lv_obj_remove_style_all(d.hero);lv_obj_set_size(d.hero,96,96);
  lv_obj_set_style_radius(d.hero,LV_RADIUS_CIRCLE,0);lv_obj_set_style_bg_opa(d.hero,LV_OPA_COVER,0);
  lv_obj_set_style_bg_color(d.hero,C_SURF2,0);lv_obj_remove_flag(d.hero,LV_OBJ_FLAG_CLICKABLE);
  d.heroIcon=icon(d.hero,ic64,C_MUTED);lv_obj_center(d.heroIcon);
  txt(h,"Status",F14,C_MUTED,116,10);
  d.state=txt(h,"--",F40,C_MUTED,116,30);
  d.hint=txt(h,"",F14,C_MUTED,0,108);lv_obj_set_width(d.hint,336);
  lv_label_set_long_mode(d.hint,LV_LABEL_LONG_MODE_WRAP);
  btn(h,LV_SYMBOL_POWER "  ON",0,144,164,56,acc,C_BG,onCb);
  btn(h,"OFF",172,144,164,56,C_SURF2,C_TEXT,offCb);

  lv_obj_t*i=card(d.pg,16,320,368,148);
  badge(i,infoIc,infoAcc,0,0,44);
  txt(i,infoTitle,F16,C_TEXT,58,2);
  d.infoSub=txt(i,"",F14,C_MUTED,58,24);
  valueRow(i,0,58,F28,infoUnit,&d.infoVal);
  d.infoBar=(lo<hi)?bar(i,0,102,336,10,lo,hi,infoAcc):NULL;
}
void devLook(DevUI&d,bool on){
  setTextIf(d.state,!haveData?"--":on?"ON":"OFF");
  setColorIf(d.state,on?d.acc:C_MUTED);
  setBgIf(d.hero,on?lv_color_mix(d.acc,C_SURF,70):C_SURF2);
  setTintIf(d.heroIcon,on?d.acc:C_MUTED);
  setTextIf(d.hint,autoMode?"Auto mode is on: the controller may switch this by itself.":
                            "Manual mode: it stays the way you set it.");
}

// =====================================================
// SCHEDULE TEXT
// =====================================================
String slotsList(const Slot*s,bool hours,bool longForm){
  String r="";int n=0;
  for(int i=0;i<MAX_SLOTS;i++){
    if(!s[i].used)continue;
    if(n++)r+="\n";
    char b[96];
    snprintf(b,sizeof(b),"%s  %-8s  %d %s   %s%s",
      longForm?(String("Slot ")+i+":").c_str():"",formatTime12h(s[i].hr,s[i].mn).c_str(),
      s[i].dur,hours?"hr":"min",daysText(s[i].days).c_str(),s[i].en?"":"   (off)");
    r+=longForm?String(b):String(b+2);
  }
  if(n==0)r="No schedules set";
  return r;
}
String slotsShort(const Slot*s){
  String r="";int n=0;
  for(int i=0;i<MAX_SLOTS;i++){
    if(!s[i].used||!s[i].en)continue;
    if(n++)r+=", ";r+=formatTime12h(s[i].hr,s[i].mn);
  }
  return n?r:String("none");
}

// =====================================================
// UPDATE EVERYTHING FROM THE LATEST STATUS
// =====================================================
void updateConnection(){
  for(int i=0;i<nPills;i++){
    setBgIf(pillDot[i],bodyConnected?C_OK:C_BAD);
    setTextIf(pillLbl[i],bodyConnected?"Body online":"Body offline");
    setColorIf(pillLbl[i],bodyConnected?C_TEXT:C_MUTED);
  }
}
void sensorChip(SensorCard&s,const char*t,lv_color_t c){
  if(!t){setHidden(s.chipBox,true);return;}
  setHidden(s.chipBox,false);setTextIf(s.chipLbl,t);setColorIf(s.chipLbl,c);
}
void updateHome(){
  char b[48];
  // --- clock
  if(rtcTime.length()>=16){
    int y=rtcTime.substring(0,4).toInt(),mo=rtcTime.substring(5,7).toInt(),d=rtcTime.substring(8,10).toInt();
    int hh=rtcTime.substring(11,13).toInt(),mi=rtcTime.substring(14,16).toInt();
    setTextIf(lblTime,formatTime12h(hh,mi));
    static const char*MON[]={"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
    static const char*DOW[]={"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
    if(mo>=1&&mo<=12){snprintf(b,sizeof(b),"%s, %s %d %d",DOW[dayOfWeek(y,mo,d)],MON[mo-1],d,y);setTextIf(lblDate,b);}
    setTextIf(dLgt.infoVal,formatTime12h(hh,mi));
    setTextIf(dLgt.infoSub,lv_label_get_text(lblDate));
  }

  // --- sensors
  if(haveData){
    snprintf(b,sizeof(b),"%.1f",humidity);setTextIf(scHum.val,b);
    snprintf(b,sizeof(b),"%.1f",temperature);setTextIf(scTemp.val,b);
    snprintf(b,sizeof(b),"%d",co2ppm);setTextIf(scCO2.val,b);
    setBarIf(scHum.bar,(int)humidity);setBarIf(scTemp.bar,(int)(temperature*10));setBarIf(scCO2.bar,co2ppm);
    if(humidity<humOn){sensorChip(scHum,"Low",C_WARN);setBarColorIf(scHum.bar,C_WARN);}
    else if(humidity>humOff){sensorChip(scHum,"High",A_HUM);setBarColorIf(scHum.bar,A_HUM);}
    else{sensorChip(scHum,"Good",C_OK);setBarColorIf(scHum.bar,A_HUM);}
    if(co2ppm>co2On){sensorChip(scCO2,"High",C_WARN);setBarColorIf(scCO2.bar,C_WARN);}
    else{sensorChip(scCO2,"Good",C_OK);setBarColorIf(scCO2.bar,A_CO2);}
    sensorChip(scTemp,"Live",C_MUTED);
  }
  snprintf(b,sizeof(b),"Mist keeps %.0f - %.0f %%",humOn,humOff);setTextIf(scHum.sub,b);
  setTextIf(scTemp.sub,"Grow room air");
  snprintf(b,sizeof(b),"Fan on above %d ppm",co2On);setTextIf(scCO2.sub,b);

  // --- device tiles
  bool st[4]={sprinklerState,lightState,mistState,fanState};
  for(int i=0;i<4;i++){
    Tile&t=*tiles[i];
    if(t.holdUntil&&millis()<=t.holdUntil){
      if(st[i]==t.want)t.holdUntil=0;                       // body confirmed
      else if(millis()-t.sentAt>1000&&t.retries<2){         // lost on the wire: send again
        t.retries++;t.sentAt=millis();sendCommand(t.want?t.onCmd:t.offCmd);
      }
    }
    if(!t.holdUntil||millis()>t.holdUntil){t.holdUntil=0;setChecked(t.sw,st[i]);tileLook(t,st[i]);}
  }

  // --- water + mode + schedules
  setTextIf(lblWater,!haveData?"--":lowWater?"Low water":"Level OK");
  setColorIf(lblWater,lowWater?C_WARN:C_TEXT);
  setTintIf(waterIcon,lowWater?C_WARN:A_WATER);
  setHidden(refillBox,!(haveData&&refillState));
  setTextIf(refillLbl,"Refilling");setColorIf(refillLbl,A_WATER);
  setBgIf(btnAuto,autoMode?A_HUM:C_SURF2);setBgIf(btnManual,autoMode?C_SURF2:C_WARN);
  setColorIf(lv_obj_get_child(btnAuto,0),autoMode?C_BG:C_MUTED);
  setColorIf(lv_obj_get_child(btnManual,0),autoMode?C_MUTED:C_BG);
  setTextIf(lblSchedSpr,"Sprinkler: "+slotsShort(sprSlots));
  setTextIf(lblSchedLgt,"Light: "+slotsShort(lgtSlots));

  // --- device pages (live, never touching rollers/editors)
  devLook(dSpr,sprinklerState);devLook(dLgt,lightState);devLook(dMist,mistState);devLook(dFan,fanState);
  if(haveData){
    snprintf(b,sizeof(b),"%.1f",humidity);setTextIf(dSpr.infoVal,b);setTextIf(dMist.infoVal,b);
    setBarIf(dSpr.infoBar,(int)humidity);setBarIf(dMist.infoBar,(int)humidity);
    snprintf(b,sizeof(b),"%d",co2ppm);setTextIf(dFan.infoVal,b);setBarIf(dFan.infoBar,co2ppm);
  }
  setTextIf(dSpr.infoSub,lowWater?"Water tank is LOW":"Water tank OK");
  snprintf(b,sizeof(b),"Target %.0f - %.0f %%",humOn,humOff);setTextIf(dMist.infoSub,b);
  snprintf(b,sizeof(b),"ON above %d, OFF below %d",co2On,co2Off);setTextIf(dFan.infoSub,b);
  snprintf(b,sizeof(b),"%.0f %%",humOn);setTextIf(lblHumOnV,b);
  snprintf(b,sizeof(b),"%.0f %%",humOff);setTextIf(lblHumOffV,b);
  snprintf(b,sizeof(b),"%d ppm",co2On);setTextIf(lblCO2OnV,b);
  snprintf(b,sizeof(b),"%d ppm",co2Off);setTextIf(lblCO2OffV,b);
  setTextIf(lblSprList,slotsList(sprSlots,false,false));
  setTextIf(lblLgtList,slotsList(lgtSlots,true,false));
  setTextIf(lblSprList2,slotsList(sprSlots,false,true));
  setTextIf(lblLgtList2,slotsList(lgtSlots,true,true));
  updateConnection();
}

bool lastShownBody=false,bodyShownOnce=false;
void checkBodyConnection(){
  if(millis()-lastBodyRx>BODY_TIMEOUT_MS)bodyConnected=false;
  if(bodyShownOnce&&bodyConnected==lastShownBody)return;
  bodyShownOnce=true;lastShownBody=bodyConnected;updateConnection();
}

// =====================================================
// CALLBACKS
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
int getRollerInt(lv_obj_t *r){char buf[16];lv_roller_get_selected_str(r,buf,sizeof(buf));return atoi(buf);}

void send2(const char*cmd){if(!needBody())return;sendCommand(cmd);sendCommand("GET_STATUS");}

void cb_goHome(lv_event_t*e){LV_UNUSED(e);showPage(pgHome);updateHome();}
void cb_goSpr(lv_event_t*e){LV_UNUSED(e);showPage(pgSpr);updateHome();}
void cb_goLight(lv_event_t*e){LV_UNUSED(e);showPage(pgLgt);updateHome();}
void cb_goSchedList(lv_event_t*e){LV_UNUSED(e);showPage(pgSchedList);updateHome();}
void cb_goMist(lv_event_t*e){LV_UNUSED(e);showPage(pgMist);
  int onI=(int)humOn-50;if(onI<0)onI=0;if(onI>50)onI=50;
  int offI=(int)humOff-50;if(offI<0)offI=0;if(offI>50)offI=50;
  lv_roller_set_selected(rollerHumOn,onI,LV_ANIM_OFF);lv_roller_set_selected(rollerHumOff,offI,LV_ANIM_OFF);
  updateHome();}
void cb_goFan(lv_event_t*e){LV_UNUSED(e);showPage(pgFan);
  int onI=(co2On-100)/50;if(onI<0)onI=0;if(onI>38)onI=38;
  int offI=(co2Off-100)/50;if(offI<0)offI=0;if(offI>38)offI=38;
  lv_roller_set_selected(rollerCO2On,onI,LV_ANIM_OFF);lv_roller_set_selected(rollerCO2Off,offI,LV_ANIM_OFF);
  updateHome();}

void cb_sprOn(lv_event_t*e){LV_UNUSED(e);send2("SPRINKLER_ON");}
void cb_sprOff(lv_event_t*e){LV_UNUSED(e);send2("SPRINKLER_OFF");}
void cb_lgtOn(lv_event_t*e){LV_UNUSED(e);send2("LIGHT_ON");}
void cb_lgtOff(lv_event_t*e){LV_UNUSED(e);send2("LIGHT_OFF");}
void cb_mistOn(lv_event_t*e){LV_UNUSED(e);send2("MIST_ON");}
void cb_mistOff(lv_event_t*e){LV_UNUSED(e);send2("MIST_OFF");}
void cb_fanOn(lv_event_t*e){LV_UNUSED(e);send2("FAN_ON");}
void cb_fanOff(lv_event_t*e){LV_UNUSED(e);send2("FAN_OFF");}
void cb_autoOn(lv_event_t*e){LV_UNUSED(e);send2("AUTO_ON");}
void cb_autoOff(lv_event_t*e){LV_UNUSED(e);send2("AUTO_OFF");}

void cb_tileSwitch(lv_event_t*e){
  int i=(int)(intptr_t)lv_event_get_user_data(e);Tile&t=*tiles[i];
  bool on=lv_obj_has_state(t.sw,LV_STATE_CHECKED);
  if(!needBody()){setChecked(t.sw,!on);return;}
  // Show the new state now; follow STATUS again once the body confirms it,
  // or after 3 s if it never does.
  t.want=on;t.sentAt=millis();t.retries=0;t.holdUntil=millis()+3000;
  tileLook(t,on);
  sendCommand(on?t.onCmd:t.offCmd);sendCommand("GET_STATUS");
}

void cb_applyHum(lv_event_t*e){LV_UNUSED(e);if(!needBody())return;
  humOn=getRollerInt(rollerHumOn);humOff=getRollerInt(rollerHumOff);
  sendCommand("SET_HUM_ON="+String(humOn,1));sendCommand("SET_HUM_OFF="+String(humOff,1));sendCommand("GET_STATUS");
  showToast(LV_SYMBOL_OK "  Humidity thresholds sent");updateHome();}
void cb_applyCO2(lv_event_t*e){LV_UNUSED(e);if(!needBody())return;
  co2On=getRollerInt(rollerCO2On);co2Off=getRollerInt(rollerCO2Off);
  sendCommand("SET_CO2_ON="+String(co2On));sendCommand("SET_CO2_OFF="+String(co2Off));sendCommand("GET_STATUS");
  showToast(LV_SYMBOL_OK "  CO2 thresholds sent");updateHome();}

// ---------------- schedule editor
lv_obj_t *lblScTitle,*lblScIdx,*btnScEn,*lblScTime,*lblScDur,*btnScDays[7],*scBadgeIcon;
enum{SC_IDX_DN=1,SC_IDX_UP,SC_TGL,SC_HR_DN,SC_HR_UP,SC_MN_DN,SC_MN_UP,SC_D_DN,SC_D_UP,
     SC_ALL,SC_WKD,SC_SAVE,SC_CLR,SC_DAY0};
void loadSlot(){
  const Slot&s=(schedTarget==SCHED_SPR?sprSlots:lgtSlots)[schedIdx];
  if(s.used){schedEn=s.en;schedHr=s.hr;schedMn=s.mn;schedDur=s.dur;for(int d=0;d<7;d++)schedDays[d]=s.days[d];}
  else{schedEn=true;schedHr=6;schedMn=0;schedDur=schedTarget==SCHED_SPR?3:12;for(int d=0;d<7;d++)schedDays[d]=true;}
}
void updSchedDisp(){
  lv_color_t acc=schedTarget==SCHED_SPR?A_SPR:A_LIGHT;
  setTextIf(lblScTitle,schedTarget==SCHED_SPR?"Sprinkler schedule":"Light schedule");
  setTintIf(scBadgeIcon,acc);
  char b[32];snprintf(b,sizeof(b),"%d of %d",schedIdx+1,MAX_SLOTS);setTextIf(lblScIdx,b);
  const Slot&s=(schedTarget==SCHED_SPR?sprSlots:lgtSlots)[schedIdx];
  lv_obj_t*enL=lv_obj_get_child(btnScEn,0);
  setTextIf(enL,schedEn?LV_SYMBOL_OK "  Enabled":LV_SYMBOL_CLOSE "  Disabled");
  setBgIf(btnScEn,schedEn?lv_color_mix(C_OK,C_SURF,70):C_SURF2);setColorIf(enL,schedEn?C_OK:C_MUTED);
  setTextIf(lblScTime,formatTime12h(schedHr,schedMn));
  snprintf(b,sizeof(b),"%d %s",schedDur,schedTarget==SCHED_LGT?"hr":"min");setTextIf(lblScDur,b);
  for(int d=0;d<7;d++){
    setBgIf(btnScDays[d],schedDays[d]?acc:C_SURF2);
    setColorIf(lv_obj_get_child(btnScDays[d],0),schedDays[d]?C_BG:C_MUTED);
  }
  LV_UNUSED(s);
}
void openSched(SchedTarget t,lv_obj_t*from){
  schedTarget=t;schedIdx=0;schedReturnPage=from;loadSlot();showPage(pgSched);updSchedDisp();
}
void cb_sprSched(lv_event_t*e){LV_UNUSED(e);openSched(SCHED_SPR,lv_obj_has_flag(pgSchedList,LV_OBJ_FLAG_HIDDEN)?pgSpr:pgSchedList);}
void cb_lgtSched(lv_event_t*e){LV_UNUSED(e);openSched(SCHED_LGT,lv_obj_has_flag(pgSchedList,LV_OBJ_FLAG_HIDDEN)?pgLgt:pgSchedList);}
void cb_schedBack(lv_event_t*e){LV_UNUSED(e);showPage(schedReturnPage?schedReturnPage:pgHome);updateHome();}
void cb_sched(lv_event_t*e){
  int c=(int)(intptr_t)lv_event_get_user_data(e);
  switch(c){
    case SC_IDX_DN:schedIdx=(schedIdx+MAX_SLOTS-1)%MAX_SLOTS;loadSlot();break;
    case SC_IDX_UP:schedIdx=(schedIdx+1)%MAX_SLOTS;loadSlot();break;
    case SC_TGL:schedEn=!schedEn;break;
    case SC_HR_DN:schedHr=(schedHr+23)%24;break;
    case SC_HR_UP:schedHr=(schedHr+1)%24;break;
    case SC_MN_DN:schedMn=(schedMn+55)%60;break;
    case SC_MN_UP:schedMn=(schedMn+5)%60;break;
    case SC_D_DN:if(--schedDur<1)schedDur=1;break;
    case SC_D_UP:if(++schedDur>120)schedDur=120;break;
    case SC_ALL:for(int i=0;i<7;i++)schedDays[i]=true;break;
    case SC_WKD:for(int i=0;i<7;i++)schedDays[i]=(i>=1&&i<=5);break;
    case SC_SAVE:{
      if(!needBody())return;
      String ds="";for(int d=0;d<7;d++)if(schedDays[d])ds+=String(d);
      String pfx=schedTarget==SCHED_SPR?"SET_SPR_SCHED=":"SET_LGT_SCHED=";
      sendCommand(pfx+String(schedIdx)+","+String(schedEn?1:0)+","+String(schedHr)+","+
        String(schedMn)+","+String(schedDur)+","+ds);sendCommand("GET_STATUS");
      showToast(LV_SYMBOL_SAVE "  Schedule saved");break;}
    case SC_CLR:
      if(!needBody())return;
      sendCommand(schedTarget==SCHED_SPR?"CLEAR_SPR_SCHED":"CLEAR_LGT_SCHED");sendCommand("GET_STATUS");
      showToast(LV_SYMBOL_TRASH "  All slots cleared");break;
    default:
      if(c>=SC_DAY0&&c<SC_DAY0+7)schedDays[c-SC_DAY0]=!schedDays[c-SC_DAY0];
  }
  updSchedDisp();
}

// ---------------- clock editor
lv_obj_t *lblRtcCur,*lblRtcVal[6];
enum{RT_APPLY=100};
void clampRTC(){if(rtcY<2024)rtcY=2035;if(rtcY>2035)rtcY=2024;if(rtcMo<1)rtcMo=12;if(rtcMo>12)rtcMo=1;
  if(rtcD<1)rtcD=31;if(rtcD>31)rtcD=1;if(rtcH<0)rtcH=23;if(rtcH>23)rtcH=0;
  if(rtcMi<0)rtcMi=59;if(rtcMi>59)rtcMi=0;if(rtcS<0)rtcS=59;if(rtcS>59)rtcS=0;}
void updRtcLbl(){
  clampRTC();int v[6]={rtcY,rtcMo,rtcD,rtcH,rtcMi,rtcS};
  for(int i=0;i<6;i++){char b[8];snprintf(b,sizeof(b),i==0?"%04d":"%02d",v[i]);setTextIf(lblRtcVal[i],b);}
  setTextIf(lblRtcCur,rtcTime.length()?("Clock now:  "+rtcTime):String("Clock now:  --"));
}
void cb_goRTC(lv_event_t*e){LV_UNUSED(e);
  if(rtcTime.length()>=19){rtcY=rtcTime.substring(0,4).toInt();rtcMo=rtcTime.substring(5,7).toInt();
    rtcD=rtcTime.substring(8,10).toInt();rtcH=rtcTime.substring(11,13).toInt();
    rtcMi=rtcTime.substring(14,16).toInt();rtcS=rtcTime.substring(17,19).toInt();}
  showPage(pgRTC);updRtcLbl();}
void cb_rtc(lv_event_t*e){
  int c=(int)(intptr_t)lv_event_get_user_data(e);
  if(c==RT_APPLY){
    if(!needBody())return;clampRTC();char buf[40];
    snprintf(buf,sizeof(buf),"SET_RTC=%04d-%02d-%02d %02d:%02d:%02d",rtcY,rtcMo,rtcD,rtcH,rtcMi,rtcS);
    sendCommand(String(buf));sendCommand("GET_STATUS");showToast(LV_SYMBOL_OK "  Clock set");
    showPage(pgHome);updateHome();return;}
  int col=c/2,dir=(c%2)?1:-1;
  int*v[6]={&rtcY,&rtcMo,&rtcD,&rtcH,&rtcMi,&rtcS};*v[col]+=dir;updRtcLbl();
}

// =====================================================
// BUILD PAGES
// =====================================================
void buildHome(){
  pgHome=newPage(false);
  // header
  lv_obj_t*logo=icon(pgHome,&ic_mushroom_40,A_BRAND);lv_obj_set_pos(logo,16,16);
  txt(pgHome,"Mushroom Farm",F20,C_TEXT,66,12);
  txt(pgHome,"Smart grow room",F14,C_MUTED,66,38);
  lv_obj_t*clk=lv_obj_create(pgHome);lv_obj_remove_style_all(clk);
  lv_obj_set_pos(clk,380,8);lv_obj_set_size(clk,230,58);
  lv_obj_set_style_radius(clk,14,0);lv_obj_set_style_bg_opa(clk,LV_OPA_COVER,0);
  lv_obj_set_style_bg_color(clk,C_BG,0);
  // Opens on a long press only, so a stray touch cannot open the clock page.
  lv_obj_add_flag(clk,LV_OBJ_FLAG_CLICKABLE);
  lv_obj_set_style_bg_color(clk,C_SURF2,LV_STATE_PRESSED);
  lv_obj_add_event_cb(clk,cb_goRTC,LV_EVENT_LONG_PRESSED,NULL);
  lv_obj_remove_flag(clk,LV_OBJ_FLAG_SCROLLABLE);
  lblTime=txt(clk,"--:--",F28,C_TEXT,0,0);lv_obj_align(lblTime,LV_ALIGN_TOP_RIGHT,-10,0);
  lblDate=txt(clk,"Hold to set the clock",F14,C_MUTED,0,0);lv_obj_align(lblDate,LV_ALIGN_TOP_RIGHT,-10,34);
  connectionPill(pgHome);

  // sensors
  buildSensorCard(scHum,16,"Humidity",&ic_humidity_40,A_HUM,"%",0,100);
  buildSensorCard(scTemp,276,"Temperature",&ic_temp_40,A_TEMP,"C",100,400);
  buildSensorCard(scCO2,536,"CO2",&ic_co2_40,A_CO2,"ppm",0,2000);

  // devices
  buildTile(tSpr,16,"Sprinkler",&ic_sprinkler_40,A_SPR,cb_goSpr,"SPRINKLER_ON","SPRINKLER_OFF",0);
  buildTile(tLgt,211,"Grow light",&ic_light_40,A_LIGHT,cb_goLight,"LIGHT_ON","LIGHT_OFF",1);
  buildTile(tMist,406,"Mist maker",&ic_mist_40,A_MIST,cb_goMist,"MIST_ON","MIST_OFF",2);
  buildTile(tFan,601,"Exhaust fan",&ic_fan_40,A_FAN,cb_goFan,"FAN_ON","FAN_OFF",3);

  // water tank
  lv_obj_t*w=card(pgHome,16,380,236,88,14);
  badge(w,&ic_tank_40,A_WATER,0,4,52,&waterIcon);
  txt(w,"Water tank",F14,C_MUTED,64,2);
  lblWater=txt(w,"--",F20,C_TEXT,64,26);
  refillLbl=chip(w,&refillBox);lv_obj_align(refillBox,LV_ALIGN_TOP_RIGHT,0,-2);setHidden(refillBox,true);

  // mode
  lv_obj_t*m=card(pgHome,264,380,236,88,14);
  badge(m,&ic_auto_40,A_HUM,0,4,52);
  txt(m,"Mode",F14,C_MUTED,64,2);
  btnAuto=btn(m,"AUTO",64,24,70,34,C_SURF2,C_MUTED,cb_autoOn,0,F14);
  btnManual=btn(m,"MANUAL",138,24,70,34,C_SURF2,C_MUTED,cb_autoOff,0,F14);
  lv_obj_set_style_radius(btnAuto,10,0);lv_obj_set_style_radius(btnManual,10,0);

  // schedules
  lv_obj_t*s=card(pgHome,512,380,272,88,14);
  makeTappable(s,cb_goSchedList);
  badge(s,&ic_calendar_40,A_SPR,0,4,52);
  txt(s,"Schedules",F14,C_MUTED,64,2);
  lv_obj_t*chev=txt(s,LV_SYMBOL_RIGHT,F14,C_MUTED,0,0);lv_obj_align(chev,LV_ALIGN_TOP_RIGHT,0,2);
  lblSchedSpr=txt(s,"Sprinkler: none",F14,C_TEXT,64,24);
  lblSchedLgt=txt(s,"Light: none",F14,C_TEXT,64,42);
  lv_obj_set_width(lblSchedSpr,180);lv_label_set_long_mode(lblSchedSpr,LV_LABEL_LONG_MODE_DOTS);
  lv_obj_set_width(lblSchedLgt,180);lv_label_set_long_mode(lblSchedLgt,LV_LABEL_LONG_MODE_DOTS);
}

lv_obj_t* scheduleCard(lv_obj_t*par,int x,int y,int w,int h,const char*title,lv_color_t acc,
                       lv_obj_t**listOut,lv_event_cb_t editCb){
  lv_obj_t*c=card(par,x,y,w,h);
  badge(c,&ic_calendar_40,acc,0,0,44);
  txt(c,title,F20,C_TEXT,58,10);
  lv_obj_t*l=txt(c,"No schedules set",F16,C_TEXT,0,62);
  lv_obj_set_width(l,w-32);lv_label_set_long_mode(l,LV_LABEL_LONG_MODE_WRAP);
  lv_obj_set_style_text_line_space(l,10,0);
  *listOut=l;
  btn(c,LV_SYMBOL_EDIT "  Edit schedule",0,h-32-56,w-32,56,acc,C_BG,editCb);
  return c;
}
void thresholdCard(lv_obj_t*par,const char*title,lv_color_t acc,const char*onTxt,const char*offTxt,
                   const char*opts,lv_obj_t**onV,lv_obj_t**offV,lv_obj_t**rOn,lv_obj_t**rOff,lv_event_cb_t apply){
  lv_obj_t*c=card(par,396,76,388,392);
  txt(c,title,F20,C_TEXT,0,0);
  txt(c,onTxt,F14,C_MUTED,0,40);txt(c,offTxt,F14,C_MUTED,184,40);
  *onV=txt(c,"--",F28,acc,0,60);*offV=txt(c,"--",F28,acc,184,60);
  *rOn=roller(c,opts,0,104,170,acc);*rOff=roller(c,opts,184,104,170,acc);
  btn(c,LV_SYMBOL_OK "  Apply",0,300,356,56,acc,C_BG,apply);
}

void buildDevicePages(){
  buildDevPage(dSpr,"Sprinkler","Watering pump",&ic_sprinkler_64,&ic_sprinkler_40,A_SPR,cb_sprOn,cb_sprOff,
               "Humidity",&ic_humidity_40,A_HUM,"%",0,100);
  pgSpr=dSpr.pg;
  scheduleCard(pgSpr,396,76,388,392,"Schedule",A_SPR,&lblSprList,cb_sprSched);

  buildDevPage(dLgt,"Grow light","Lighting",&ic_light_64,&ic_light_40,A_LIGHT,cb_lgtOn,cb_lgtOff,
               "Clock",&ic_clock_40,A_WATER,"",0,0);
  pgLgt=dLgt.pg;
  scheduleCard(pgLgt,396,76,388,392,"Schedule",A_LIGHT,&lblLgtList,cb_lgtSched);

  buildDevPage(dMist,"Mist maker","Keeps the humidity up",&ic_mist_64,&ic_mist_40,A_MIST,cb_mistOn,cb_mistOff,
               "Humidity",&ic_humidity_40,A_HUM,"%",0,100);
  pgMist=dMist.pg;
  thresholdCard(pgMist,"Humidity thresholds",A_MIST,"Mist ON below (%)","Mist OFF above (%)",g_humOpts,
                &lblHumOnV,&lblHumOffV,&rollerHumOn,&rollerHumOff,cb_applyHum);

  buildDevPage(dFan,"Exhaust fan","Clears out the CO2",&ic_fan_64,&ic_fan_40,A_FAN,cb_fanOn,cb_fanOff,
               "CO2",&ic_co2_40,A_CO2,"ppm",0,2000);
  pgFan=dFan.pg;
  thresholdCard(pgFan,"CO2 thresholds",A_FAN,"Fan ON above (ppm)","Fan OFF below (ppm)",g_co2Opts,
                &lblCO2OnV,&lblCO2OffV,&rollerCO2On,&rollerCO2Off,cb_applyCO2);
}

void buildSchedListPage(){
  pgSchedList=newPage();
  header(pgSchedList,"Schedules","Sprinkler and grow light",&ic_calendar_40,A_SPR);
  scheduleCard(pgSchedList,16,76,378,392,"Sprinkler",A_SPR,&lblSprList2,cb_sprSched);
  scheduleCard(pgSchedList,406,76,378,392,"Grow light",A_LIGHT,&lblLgtList2,cb_lgtSched);
}

void buildSchedPage(){
  pgSched=newPage();
  lv_obj_t*b=btn(pgSched,LV_SYMBOL_LEFT,16,12,52,52,C_SURF,C_TEXT,cb_schedBack,0,F20);
  lv_obj_set_style_border_color(b,C_LINE,0);lv_obj_set_style_border_width(b,1,0);lv_obj_set_style_radius(b,16,0);
  badge(pgSched,&ic_calendar_40,A_SPR,80,12,52,&scBadgeIcon);
  lblScTitle=txt(pgSched,"Schedule",F28,C_TEXT,146,10);
  txt(pgSched,"Pick a slot, set it, then Save",F14,C_MUTED,146,44);
  connectionPill(pgSched);

  // slot row
  lv_obj_t*r=card(pgSched,16,76,768,72,12);
  txt(r,"Slot",F14,C_MUTED,6,4);lblScIdx=txt(r,"1 of 5",F20,C_TEXT,6,22);
  btn(r,LV_SYMBOL_LEFT,120,0,64,46,C_SURF2,C_TEXT,cb_sched,SC_IDX_DN);
  btn(r,LV_SYMBOL_RIGHT,192,0,64,46,C_SURF2,C_TEXT,cb_sched,SC_IDX_UP);
  btnScEn=btn(r,"Enabled",530,0,212,46,C_SURF2,C_OK,cb_sched,SC_TGL,F16);

  // time
  lv_obj_t*t=card(pgSched,16,160,378,124,14);
  txt(t,"Start time",F14,C_MUTED,0,0);lblScTime=txt(t,"6:00 AM",F28,C_TEXT,0,22);
  btn(t,"- hr",0,52+8,80,44,C_SURF2,C_TEXT,cb_sched,SC_HR_DN,F16);
  btn(t,"+ hr",88,52+8,80,44,C_SURF2,C_TEXT,cb_sched,SC_HR_UP,F16);
  btn(t,"- 5m",184,52+8,80,44,C_SURF2,C_TEXT,cb_sched,SC_MN_DN,F16);
  btn(t,"+ 5m",272,52+8,78,44,C_SURF2,C_TEXT,cb_sched,SC_MN_UP,F16);
  // duration
  lv_obj_t*d=card(pgSched,406,160,378,124,14);
  txt(d,"Duration",F14,C_MUTED,0,0);lblScDur=txt(d,"3 min",F28,C_TEXT,0,22);
  btn(d,LV_SYMBOL_MINUS,0,60,168,44,C_SURF2,C_TEXT,cb_sched,SC_D_DN);
  btn(d,LV_SYMBOL_PLUS,176,60,174,44,C_SURF2,C_TEXT,cb_sched,SC_D_UP);
  // days
  lv_obj_t*dy=card(pgSched,16,296,768,100,14);
  txt(dy,"Days",F14,C_MUTED,0,0);
  btn(dy,"Every day",520,-6,104,30,C_SURF2,C_MUTED,cb_sched,SC_ALL,F14);
  btn(dy,"Weekdays",632,-6,104,30,C_SURF2,C_MUTED,cb_sched,SC_WKD,F14);
  for(int i=0;i<7;i++)btnScDays[i]=btn(dy,DAY_SHORT[i],i*106,30,98,42,C_SURF2,C_MUTED,cb_sched,SC_DAY0+i,F16);
  // actions
  btn(pgSched,LV_SYMBOL_SAVE "  Save slot",16,408,372,60,A_SPR,C_BG,cb_sched,SC_SAVE);
  lv_obj_t*clr=btn(pgSched,LV_SYMBOL_TRASH "  Clear all slots",400,408,384,60,C_SURF,C_BAD,cb_sched,SC_CLR);
  lv_obj_set_style_border_color(clr,lv_color_mix(C_BAD,C_SURF,90),0);lv_obj_set_style_border_width(clr,1,0);
}

void buildRTCPage(){
  pgRTC=newPage();
  header(pgRTC,"Set clock","Date and time of the controller",&ic_clock_40,A_WATER);
  lv_obj_t*c=card(pgRTC,16,76,768,304,14);
  lblRtcCur=txt(c,"Clock now:  --",F16,C_MUTED,6,0);
  const char*col[]={"Year","Month","Day","Hour","Min","Sec"};
  for(int i=0;i<6;i++){
    int x=i*124;
    lv_obj_t*l=txt(c,col[i],F14,C_MUTED,0,36);lv_obj_set_width(l,116);lv_obj_set_pos(l,x,36);
    lv_obj_set_style_text_align(l,LV_TEXT_ALIGN_CENTER,0);
    btn(c,LV_SYMBOL_UP,x,62,116,60,C_SURF2,C_TEXT,cb_rtc,i*2+1);
    lblRtcVal[i]=txt(c,"--",F28,C_TEXT,x,134);lv_obj_set_width(lblRtcVal[i],116);
    lv_obj_set_style_text_align(lblRtcVal[i],LV_TEXT_ALIGN_CENTER,0);
    btn(c,LV_SYMBOL_DOWN,x,178,116,60,C_SURF2,C_TEXT,cb_rtc,i*2);
  }
  btn(pgRTC,LV_SYMBOL_OK "  Set the clock",16,394,768,70,A_WATER,C_BG,cb_rtc,RT_APPLY);
}

void buildToast(){
  toastBox=lv_obj_create(lv_layer_top());lv_obj_remove_style_all(toastBox);
  lv_obj_set_size(toastBox,LV_SIZE_CONTENT,LV_SIZE_CONTENT);
  lv_obj_align(toastBox,LV_ALIGN_BOTTOM_MID,0,-20);
  lv_obj_set_style_bg_color(toastBox,lv_color_hex(0x0F172A),0);lv_obj_set_style_bg_opa(toastBox,LV_OPA_COVER,0);
  lv_obj_set_style_border_color(toastBox,C_LINE,0);lv_obj_set_style_border_width(toastBox,1,0);
  lv_obj_set_style_radius(toastBox,LV_RADIUS_CIRCLE,0);
  lv_obj_set_style_pad_hor(toastBox,22,0);lv_obj_set_style_pad_ver(toastBox,12,0);
  lv_obj_remove_flag(toastBox,LV_OBJ_FLAG_CLICKABLE);
  toastLbl=lv_label_create(toastBox);lv_label_set_text(toastLbl,"");
  lv_obj_set_style_text_font(toastLbl,F16,0);lv_obj_set_style_text_color(toastLbl,C_TEXT,0);
  lv_obj_add_flag(toastBox,LV_OBJ_FLAG_HIDDEN);
  toastTimer=lv_timer_create(toastHide,2200,NULL);lv_timer_pause(toastTimer);
}

// =====================================================
// SETUP
// =====================================================
void setup(){
  Serial.begin(115200);delay(300);
  Serial.println("Starting LCD...");

  pinMode(GFX_BL,OUTPUT);digitalWrite(GFX_BL,HIGH);
  gfx->begin();gfx->fillScreen(0x0000);
  Wire.begin(TOUCH_SDA,TOUCH_SCL);ts.begin();ts.setRotation(ROTATION_INVERTED);

  lv_init();lv_tick_set_cb(my_tick_get);
  disp=lv_display_create(SCREEN_W,SCREEN_H);
  lv_display_set_flush_cb(disp,my_disp_flush);
  lv_display_set_buffers(disp,buf1,NULL,sizeof(buf1),LV_DISPLAY_RENDER_MODE_PARTIAL);
  indev=lv_indev_create();lv_indev_set_type(indev,LV_INDEV_TYPE_POINTER);
  lv_indev_set_read_cb(indev,my_touch_read);
  lv_display_set_theme(disp,lv_theme_default_init(disp,A_SPR,A_MIST,true,F14));
  lv_obj_set_style_bg_color(lv_screen_active(),C_BG,0);
  lv_obj_remove_flag(lv_screen_active(),LV_OBJ_FLAG_SCROLLABLE);

  initRollerOptions();
  parseSlots(sprSchedText,sprSlots);parseSlots(lgtSchedText,lgtSlots);
  buildHome();buildDevicePages();buildSchedListPage();buildSchedPage();buildRTCPage();buildToast();
  updateHome();
  checkBodyConnection();

  lv_mem_monitor_t mon;lv_mem_monitor(&mon);
  Serial.printf("LVGL memory: %u%% used, %u bytes free\n",(unsigned)mon.used_pct,(unsigned)mon.free_size);
  Serial.println("=== LCD READY (dashboard UI) ===");
  Serial.flush();

  // The body link uses the same pins as the USB serial port (43/44),
  // so nothing more is printed to USB after this point.
  bodySerial.begin(115200,SERIAL_8N1,LCD_RX_FROM_SLAVE,LCD_TX_TO_SLAVE);
  bodySerial.setPins(LCD_RX_FROM_SLAVE,LCD_TX_TO_SLAVE,-1,-1);
}

// =====================================================
// LOOP
// =====================================================
void loop(){
  // Read the body's lines without blocking.
  static String rx;
  bool gotStatus=false;
  while(bodySerial.available()){
    char c=(char)bodySerial.read();
    if(c=='\n'){
      // Noise on the wire can put junk in front of a line: start at "STATUS,".
      int k=rx.indexOf("STATUS,");
      if(k>=0){String line=rx.substring(k);line.trim();parseStatus(line);gotStatus=true;}
      rx="";
    }else if(c>=0x20&&c<=0x7E&&rx.length()<600){
      rx+=c;
    }
  }
  if(gotStatus)updateHome();

  // The body sends STATUS every 2 s; only ask when it has gone quiet.
  static unsigned long lastReq=0;
  if(millis()-lastBodyRx>2500&&millis()-lastReq>2500){lastReq=millis();bodySerial.println("GET_STATUS");}

  static unsigned long lastConnCheck=0;
  if(millis()-lastConnCheck>500){lastConnCheck=millis();checkBodyConnection();}

  lv_timer_handler();
  delay(5);
}
