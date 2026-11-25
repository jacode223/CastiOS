#include <assert.h>
#include <stdio.h>
typedef unsigned char u8;
typedef unsigned int u32;
#include "../src/extensions/usb_hid.h"
static u8 queue[64];static int count;
static void emit(u32 code){assert(count<64);queue[count++]=(u8)code;}
static int mx,my,mb,mp,mc;
static void mouse_emit(int x,int y,u8 buttons,u8 pressed){mx=x;my=y;mb=buttons;mp=pressed;mc++;}
int main(void){
 struct hid_boot_keys state={{0}};
 u8 a[8]={2,0,4},repeat[8]={2,0,4},release[8]={0};
 hid_boot_report(&state,a,emit);
 assert(count==2&&queue[0]==0x2a&&queue[1]==0x1e);
 hid_boot_report(&state,repeat,emit);assert(count==2);
 hid_boot_report(&state,release,emit);
 assert(count==4&&queue[2]==0xaa&&queue[3]==0x9e);
 u8 bad[8]={0,0,1};hid_boot_report(&state,bad,emit);assert(count==4);
 u8 arrow[8]={0,0,82};hid_boot_report(&state,arrow,emit);
 assert(count==5&&queue[4]==0x48);
 struct hid_boot_keys dup={{0}}; u8 doubled[8]={0,0,4,4},none[8]={0}; count=0;
 hid_boot_report(&dup,doubled,emit); assert(count==1&&queue[0]==0x1e);
 hid_boot_report(&dup,none,emit); assert(count==2&&queue[1]==0x9e);
 struct hid_boot_mouse mouse={0}; u8 mr[3]={1,255,2}, short_report[2]={0};
 assert(!hid_boot_mouse_report(&mouse,short_report,2,mouse_emit)&&mc==0);
 assert(hid_boot_mouse_report(&mouse,mr,3,mouse_emit));
 assert(mc==1&&mx==-1&&my==2&&mb==1&&mp==1);
 assert(hid_boot_mouse_report(&mouse,mr,3,mouse_emit)&&mp==0);
 mr[0]=0;assert(hid_boot_mouse_report(&mouse,mr,3,mouse_emit)&&mb==0&&mp==0);
 puts("USB HID: teclas, shift, repeticion, liberacion y rollover OK.");
}
