/* Host-side sanitizer probe for the exact kernel TrueType parser. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/mman.h>
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
static void zero(void*p,u32 n){memset(p,0,n);}
static void *memcopy(void*d,const void*s,u32 n){return memcpy(d,s,n);}
#include "../src/extensions/base.h"
#include "../src/extensions/truetype.h"
static void out(u32 n){(void)n;}
static void paint(void){}
int main(int argc,char**argv){
 if(argc!=2)return 2;
 void*p=mmap((void*)0x08200000,0x40000,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);if(p==MAP_FAILED){perror("mmap");return 2;}
 FILE*f=fopen(argv[1],"rb");if(!f)return 2;
 fseek(f,0,SEEK_END);u32 n=ftell(f);rewind(f);
 u8*source=malloc(n),*buf=malloc(n);if(fread(source,1,n,f)!=n)return 2;fclose(f);
 default_font=calloc(1,4096);X.font=calloc(1,4096);X.out=out;X.repaint=paint;
 load_font(source,n);int pixels=0;for(int i=0;i<4096;i++)pixels|=X.font[i];if(!pixels){fprintf(stderr,"no rendered glyphs\n");return 1;}
 for(u32 i=0;i<200;i++){
  memcpy(buf,source,n);u32 state=0x1273+i*33497;
  for(int j=0;j<12;j++){state=state*1664525+1013904223;u32 o=j<6?state%(n<4096?n:4096):state%n;buf[o]^=(u8)(state>>24);}
  load_font(buf,i%5? n : i*(n/200));
 }
 for(u32 size=0;size<128;size++)load_font(source,size);
 free(source);free(buf);free(default_font);free(X.font);munmap(p,0x40000);
 puts("OK: TrueType real + 200 mutaciones y truncados con ASan/UBSan.");return 0;
}
