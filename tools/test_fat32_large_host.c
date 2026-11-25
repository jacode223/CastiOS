/* Host-side test of the actual FAT32 implementation; no controller emulation. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
typedef uint32_t u32;typedef uint16_t u16;typedef uint8_t u8;
static void zero(void*p,u32 n){memset(p,0,n);}
static void *memcopy(void*d,const void*s,u32 n){return memcpy(d,s,n);}
static u32 strlen_(const char*s){return (u32)strlen(s);}
static int xequal(const char*a,const char*b){return !strcasecmp(a,b);}
static int xcopy(char*d,const char*s,u32 n){if(strlen(s)>=n)return 0;strcpy(d,s);return 1;}
static int xprefix(const char*s,const char*p){return !strncmp(s,p,strlen(p));}
static u16 le16(const void*p){const u8*b=p;return b[0]|b[1]<<8;}
static u32 le32(const void*p){const u8*b=p;return (u32)b[0]|(u32)b[1]<<8|(u32)b[2]<<16|(u32)b[3]<<24;}
static void st32(void*p,u32 v){u8*b=p;for(int i=0;i<4;i++)b[i]=v>>(8*i);}
static void st16(void*p,u16 v){u8*b=p;b[0]=v;b[1]=v>>8;}
static void noop(u32 v){(void)v;}
static void xn(u32 v){(void)v;}
static void xs(const char*s){(void)s;}
static int xerr(const char*s){fprintf(stderr,"FAT: %s\n",s);return 1;}
static u32 caps[4];
static struct {u32*caps;int(*read)(u32,u32,void*);void(*out)(u32);}X={caps,0,noop};
struct usbdev{u32 cap,valid;};static struct{u32 count;struct usbdev d[4];}U;
static int usb_connected(struct usbdev*d){return d->valid;}
static int usb_read(u32 d,u32 lba,void*p){return X.read(d,lba,p);}
#define ferror casti_ferror
#include "../src/extensions/fat32.h"
#define TOTAL 125000000U /* 64 GB */
#define SPC 64U
#define FATSZ 15260U
#define RESERVED 32U
static u32 reads,fatreads;
static int cyclic;
static int medium(u32 d,u32 lba,void*out){
 (void)d;u8*b=out;zero(b,512);reads++;
 if(lba==0){b[0]=0xeb;st16(b+11,512);b[13]=SPC;st16(b+14,RESERVED);b[16]=2;st32(b+32,TOTAL);st32(b+36,FATSZ);st32(b+44,2);st16(b+510,0xaa55);return 0;}
 if(lba>=RESERVED&&lba<RESERVED+FATSZ){fatreads++;u32 first=(lba-RESERVED)*128;for(u32 i=0;i<128;i++){u32 cl=first+i;st32(b+i*4,cl==2?0x0fffffff:cl==6000?(cyclic?3:0x0fffffff):cl+1);}return 0;}
 if(lba==RESERVED+FATSZ*2){memcpy(b,"HELLO   TXT",11);st16(b+26,3);st32(b+28,5);return 0;}
 if(lba==RESERVED+FATSZ*2+SPC){memcpy(b,"hello",5);return 0;}
 return 0;
}
int main(void){
 X.read=medium;caps[0]=TOTAL;U.count=1;U.d[0]=(struct usbdev){TOTAL,1};
 fat_mount(4,0,"/mnt/usb");assert(V[0].used&&V[0].total==TOTAL&&V[0].spc==SPC);
 struct fatent e;assert(lookup(&V[0],"/HELLO.TXT",&e));assert(e.size==5);u8 out[8];assert(fat_file(&V[0],&e,out,8,0)==5&&!memcmp(out,"hello",5));
 struct chain_guard g={0};fat_cached_valid=0;fatreads=0;
 for(u32 c=3;c<=6000;c++){assert(!visited(&g,c,V[0].clusters));u32 next=nextcl(&V[0],c);assert(next==(c==6000?0xffffffffU:c+1));}
 assert(fatreads==47); /* 5998 clusters, 47 FAT sectors, not 5998 reads */
 g=(struct chain_guard){0};assert(!visited(&g,3,100));assert(visited(&g,3,100));
 g=(struct chain_guard){0};int detected=0;for(u32 i=0;i<40;i++)if(visited(&g,10+i%7,100)){detected=1;break;}assert(detected);
 U.d[0].valid=0;assert(diskcap(4)==0);assert(dread(4,0,out)==-1);
 printf("OK: FAT32 64 GB, mount/read, 5998 clusters, FAT cache (47 reads), cycle guard, detach.\n");
 return 0;
}
