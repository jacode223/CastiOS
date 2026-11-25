/* USB HID boot keyboard: report-to-PS/2-set-1 translation, transport neutral.
 * Caller must supply a complete eight-byte report and an enqueue callback. */
struct hid_boot_keys {u8 last[8];};
static u8 hid_set1(u8 usage){
 static const u8 letters[26]={0x1e,0x30,0x2e,0x20,0x12,0x21,0x22,0x23,0x17,
  0x24,0x25,0x26,0x32,0x31,0x18,0x19,0x10,0x13,0x1f,0x14,0x16,0x2f,
  0x11,0x2d,0x15,0x2c};
 static const u8 digits[10]={0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b};
 if(usage>=4&&usage<=29)return letters[usage-4];
 if(usage>=30&&usage<=39)return digits[usage-30];
 switch(usage){
 case 40:return 0x1c;case 41:return 0x01;case 42:return 0x0e;
 case 43:return 0x0f;case 44:return 0x39;case 45:return 0x0c;
 case 46:return 0x0d;case 47:return 0x1a;case 48:return 0x1b;
 case 49:return 0x2b;case 51:return 0x27;case 52:return 0x28;
 case 53:return 0x29;case 54:return 0x33;case 55:return 0x34;
 case 56:return 0x35;case 57:return 0x3a;
 case 74:return 0x47;case 75:return 0x49;
 case 76:return 0x53;case 77:return 0x4f;case 78:return 0x51;
 case 79:return 0x4d;case 80:return 0x4b;case 81:return 0x50;
 case 82:return 0x48;
 default:return 0;
 }
}
static int hid_has(const u8*r,u8 key){for(int i=2;i<8;i++)if(r[i]==key)return 1;return 0;}
static int hid_has_earlier(const u8*r,int end,u8 key){for(int i=2;i<end;i++)if(r[i]==key)return 1;return 0;}
static void hid_boot_report(struct hid_boot_keys*s,const u8*r,void (*emit)(u32)){
 /* Rollover (usage 1..3): reject whole report without releasing keys. */
 for(int i=2;i<8;i++)if(r[i]&&r[i]<4)return;
 u8 old=s->last[0],now=r[0];
 if((old&0x11)&&!(now&0x11))emit(0x9d);
 if((old&0x22)&&!(now&0x22))emit(0xaa);
 for(int i=2;i<8;i++){
  u8 key=s->last[i];if(!key||hid_has_earlier(s->last,i,key)||hid_has(r,key))continue;
  u8 code=hid_set1(key);if(code&&code<0x80)emit(code|0x80);
 }
 if(!(old&0x11)&&(now&0x11))emit(0x1d);
 if(!(old&0x22)&&(now&0x22))emit(0x2a);
 for(int i=2;i<8;i++){
  u8 key=r[i];if(!key||hid_has_earlier(r,i,key)||hid_has(s->last,key))continue;
  u8 code=hid_set1(key);if(code)emit(code);
 }
 for(int i=0;i<8;i++)s->last[i]=r[i];
}

/* HID boot mouse report parser; transport must provide the received length.
 * This does not enumerate a mouse or connect it to the desktop by itself. */
struct hid_boot_mouse { u8 buttons; };
static int hid_boot_mouse_report(struct hid_boot_mouse *s,const u8 *report,u32 length,
                                void (*emit)(int,int,u8,u8)){
 if(!s||!report||!emit||length<3)return 0;
 u8 buttons=report[0]&7, pressed=(u8)(buttons & (u8)~s->buttons);
 int dx=report[1]<128?(int)report[1]:(int)report[1]-256;
 int dy=report[2]<128?(int)report[2]:(int)report[2]-256;
 s->buttons=buttons;
 emit(dx,dy,buttons,pressed);
 return 1;
}
