/* Single-process i386 ABI adapter for the bundled, static NASM build.
 * Runs at CPL0: trusted development tool, NOT a sandbox or Linux emulator.
 * All writes use a private ASFS snapshot; shell commits only after exit(0).
 */
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
#define FS ((u8*)0x4000000)
#define COUNT 480
#define REC 8192
#define LIMIT 8000
#define FILE_MAX (COUNT*LIMIT)
#define FD_MAX 128
#define ROOT 0xffffffffU
#define HEAP_START 0x09000000U
#define HEAP_END 0x0a000000U
#define MAP_START 0x0a000000U
#define MAP_END 0x0b000000U
static u32 heap, mapped, cwd, dirty;
static void (*console)(u32);
struct fd {u32 used, rec, pos, flags;} ;
/* The bundled NASM process has a dedicated mapped arena at 0x0b000000.
 * Keep descriptors there; the 0x20000..0x30000 kernel code area is full. */
#define fds ((struct fd*)0x0b000000U)
struct regs {u32 di,si,bp,sp,bx,dx,cx,ax;};
/* x86 string instructions avoid a branch and index updates per byte. */
static void *memcopy(void*d,const void*s,u32 n){void*ret=d;__asm__ volatile("cld; rep movsb":"+D"(d),"+S"(s),"+c"(n)::"memory","cc");return ret;}
static void zero(void*d,u32 n){__asm__ volatile("cld; rep stosb":"+D"(d),"+c"(n):"a"(0):"memory","cc");}
static u32 strlen_(const char*s){u32 n=0;while(s[n])n++;return n;}
static int eq(const char*a,const char*b){while(*a&&*a==*b){a++;b++;}return *a==*b;}
static u32 rd(const void*p){return *(const u32*)p;}
static void wr(void*p,u32 n){*(u32*)p=n;}
static u8 *record(u32 i){return FS+512+i*REC;}
static void free_tail(u32 head){u8*r=record(head);u32 n=rd(r+44);wr(r+44,0);while(n){r=record(n-1);n=rd(r+44);zero(r,REC);}}
/* Logical offsets map to private 8000-byte extents. Link values are index+1,
 * zero denotes EOF. Continuations have kind 4 and identify their owner. */
static u8 *chunk(u32 head,u32 ordinal,int create){
 u8*r=record(head);
 while(ordinal--){u32 n=rd(r+44);if(!n){if(!create)return (void*)0;
  u32 i;for(i=0;i<COUNT&&*record(i);i++);if(i==COUNT)return (void*)0;
  u8*q=record(i);zero(q,REC);q[0]=255;wr(q+32,head);wr(q+36,4);wr(r+44,i+1);n=i+1;
 }r=record(n-1);}return r;
}
/* Resolve relative paths and directories, including . and ..; reject names
 * outside the on-disk grammar rather than manufacturing invalid records. */
static int resolve(const char *s,u32 *parent,char *name){
 u32 dir=*s=='/'?ROOT:cwd;int found=-1;
 for(;;){while(*s=='/')s++;if(!*s){*parent=dir;name[0]=0;return dir==ROOT?-2:(int)dir;}
  u32 n=0;while(*s&&*s!='/'){
   char c=*s++;if(n==31||!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='.'||c=='_'||c=='-'))return -22;
   name[n++]=c;
  }name[n]=0;
  if(eq(name,"."))found=dir==ROOT?-2:(int)dir;
  else if(eq(name,"..")){dir=dir==ROOT?ROOT:rd(record(dir)+32);found=dir==ROOT?-2:(int)dir;}
  else {found=-1;for(u32 i=0;i<COUNT;i++)if(*record(i)&&rd(record(i)+32)==dir&&eq((char*)record(i),name)){found=i;break;}}
  if(!*s){*parent=dir;return found;}
  while(*s=='/')s++;
  if(!*s){if(found==-2){name[0]=0;*parent=ROOT;return -2;}return found>=0&&rd(record(found)+36)==2?found:-20;}
  if(found==-2){dir=ROOT;continue;}
  if(found<0||rd(record(found)+36)!=2)return -20;
  dir=found;
 }
}
static int open_(const char*path,u32 flags){
 u32 parent;char name[32];int index=resolve(path,&parent,name);
 if(index==-2)return -21;
 if(index < -1)return index;
 if(index<0){
  if(!(flags&64))return -2;
  for(index=0;index<COUNT&&*record(index);index++);
  if(index==COUNT)return -28;
 }else if((flags&192)==192)return -17;
 if(*record(index)&&rd(record(index)+36)==2)return -21;
 int f;for(f=3;f<FD_MAX&&fds[f].used;f++);if(f==FD_MAX)return -24;
 u8*r=record(index);
 if(!*r){zero(r,REC);memcopy(r,name,strlen_(name)+1);wr(r+32,parent);wr(r+36,3);dirty=1;}
 if((flags&512)&&(flags&3)){free_tail(index);wr(r+40,0);zero(r+64,REC-64);dirty=1;}
 fds[f]=(struct fd){1,index,(flags&1024)?rd(r+40):0,flags};return f;
}
static int read_(u32 f,void*buf,u32 n){
 if(f>=FD_MAX||!fds[f].used||(fds[f].flags&3)==1)return -9;
 u8*r=record(fds[f].rec);u32 size=rd(r+40),pos=fds[f].pos;
 if(pos>=size)return 0;
 if(n>size-pos)n=size-pos;
 u32 total=n;u8*out=buf;
 while(n){u32 off=pos%LIMIT,take=LIMIT-off;if(take>n)take=n;u8*q=chunk(fds[f].rec,pos/LIMIT,0);if(!q)return -5;
  memcopy(out,q+64+off,take);out+=take;pos+=take;n-=take;}
 fds[f].pos+=total;return total;
}
static int write_(u32 f,const void*buf,u32 n){
 if(f==1||f==2){const u8*b=buf;for(u32 i=0;i<n;i++)console(b[i]);return n;}
 if(f>=FD_MAX||!fds[f].used||!(fds[f].flags&3))return -9;
 u8*r=record(fds[f].rec);u32 pos=fds[f].pos;
 if(pos>FILE_MAX||n>FILE_MAX-pos)return -27;
 u32 old=rd(r+40),end=pos+n;if(!n)return 0;
 u32 have=(old+LIMIT-1)/LIMIT;if(!have)have=1;
 u32 need=(end+LIMIT-1)/LIMIT,free=0;
 for(u32 i=0;i<COUNT;i++)if(!*record(i))free++;
 if(need>have&&need-have>free)return -28;
 /* Allocate first, then write: failure cannot leave a half-linked chain. */
 if(need&&!chunk(fds[f].rec,need-1,1))return -28;
 for(u32 at=old;at<pos;){u32 off=at%LIMIT,take=LIMIT-off;if(take>pos-at)take=pos-at;u8*q=chunk(fds[f].rec,at/LIMIT,0);zero(q+64+off,take);at+=take;}
 u32 remain=n;const u8*in=buf;
 while(remain){u32 off=pos%LIMIT,take=LIMIT-off;if(take>remain)take=remain;u8*q=chunk(fds[f].rec,pos/LIMIT,0);
  memcopy(q+64+off,in,take);in+=take;pos+=take;remain-=take;}
 fds[f].pos+=n;if(end>old)wr(r+40,end);
 u32 length=rd(r+40);u8*q=r;u32 left=length;
 for(;;){u32 used=left>LIMIT?LIMIT:left;if(q!=r)wr(q+40,used);q[64+used]=0;if(left<=LIMIT)break;left-=LIMIT;q=record(rd(q+44)-1);}
 dirty=1;return n;
}
static int stat_(int index,void*out,int wide){
 u8 *b=out;u32 kind=index>=0?rd(record(index)+36):2;
 u32 size=index>=0?rd(record(index)+40):0;
 zero(b,wide?96:64);
 if(wide){wr(b,1);wr(b+12,index+1);wr(b+16,(kind==2?0040000:0100000)|0644);wr(b+20,1);wr(b+44,size);wr(b+52,4096);wr(b+56,(size+511)/512);wr(b+88,index+1);}
 else {wr(b,1);*(u16*)(b+8)=(kind==2?0040000:0100000)|0644;*(u16*)(b+10)=1;wr(b+20,size);wr(b+24,4096);wr(b+28,(size+511)/512);}
 return 0;
}
static int pathstat(const char*path,void*out,int wide){u32 p;char n[32];int i=resolve(path,&p,n);if(i==-2)return stat_(-1,out,wide);return i<0?-2:stat_(i,out,wide);}
static int seek_(u32 fd,int off,int mode){
 if(fd>=FD_MAX||!fds[fd].used)return -9;
 int base=mode==0?0:mode==1?(int)fds[fd].pos:mode==2?(int)rd(record(fds[fd].rec)+40):-1;
 if(base<0||off < -base||off>FILE_MAX-base)return -22;
 return fds[fd].pos=base+off;
}
static int map_(u32 addr,u32 size,u32 flags,u32 fd,u32 offset){
 if(!size||size>MAP_END-MAP_START)return -12;
 u32 p=(mapped+4095)&~4095U,n=(size+4095)&~4095U;
 if(addr&&(flags&16))return -22;
 if(p>MAP_END-n)return -12;
 mapped=p+n;zero((void*)p,n);
 if(!(flags&32)){if(fd>=FD_MAX||!fds[fd].used)return -9;u32 old=fds[fd].pos;fds[fd].pos=offset;int ret=read_(fd,(void*)p,size);fds[fd].pos=old;if(ret<0)return ret;}
 return p;
}
/* GDT entry six is reserved by CastiOS for glibc's i386 TLS descriptor. */
static int tls(u32 *u,u8*gdt){
 u32 ent=u[0];if(ent!=ROOT&&ent!=6)return -22;u32 base=u[1],limit=u[2];
 u8*d=gdt+6*8;*(u16*)d=limit;*(u16*)(d+2)=base;d[4]=base>>16;d[5]=0xf2;d[6]=(limit>>16)&15;
 if(u[3]&16)d[6]|=0x80;
 if(u[3]&1)d[6]|=0x40;
 d[7]=base>>24;u[0]=6;return 0;
}
static u8 *gdt_;
static void syscall_(struct regs*r){
 int v=-38;u32 b=r->bx,c=r->cx,d=r->dx;
 switch(r->ax){
 case 3:v=read_(b,(void*)c,d);break;
 case 4:v=write_(b,(void*)c,d);break;
 case 5:v=open_((char*)b,c);break;
 case 6:if(b<FD_MAX&&fds[b].used){fds[b].used=0;v=0;}else v=-9;break;
 case 10:{u32 p;char n[32];int i=resolve((char*)b,&p,n);if(i<0)v=-2;else if(rd(record(i)+36)==2)v=-21;else{free_tail(i);zero(record(i),REC);dirty=1;v=0;}break;}
 case 19:v=seek_(b,(int)c,d);break;
 case 20:case 64:case 224:v=1;break;
 case 24:case 47:case 49:case 50:case 199:case 200:case 201:case 202:v=0;break;
 case 33:{u32 p;char n[32];v=resolve((char*)b,&p,n)>=0?0:-2;break;}
 case 45:if(!b)v=heap;else if(b>=HEAP_START&&b<HEAP_END){if(b>heap)zero((void*)heap,b-heap);heap=b;v=b;}else v=heap;break;
 case 54:v=-25;break;
 case 91:case 125:case 174:case 175:case 186:case 219:case 311:case 386:v=0;break;
 case 106:case 107:v=pathstat((char*)b,(void*)c,0);break;
 case 108:if(b<3)v=stat_(-1,(void*)c,0);else v=b<FD_MAX&&fds[b].used?stat_(fds[b].rec,(void*)c,0):-9;break;
 case 122:zero((void*)b,390);memcopy((void*)b,"CastiOS",8);memcopy((void*)(b+130),"0.11",5);memcopy((void*)(b+260),"i686",5);v=0;break;
 case 140:if(c!=((int)d<0?0xffffffffU:0))v=-22;else {v=seek_(b,(int)d,r->di);if(v>=0){wr((void*)r->si,v);wr((void*)(r->si+4),0);v=0;}}break;
 case 146:{u32 *io=(u32*)c;v=0;for(u32 i=0;i<d;i++){int n=write_(b,(void*)io[i*2],io[i*2+1]);if(n<0){v=n;break;}v+=n;}break;}
 case 183:{char*p=(char*)b;if(c<2)v=-34;else{p[0]='/';p[1]=0;v=2;}break;}
 case 191:wr((void*)c,0xffffffffU);wr((void*)(c+4),0xffffffffU);v=0;break;
 case 192:v=map_(b,c,r->si,r->di,r->bp*4096);break;
 case 195:case 196:v=pathstat((char*)b,(void*)c,1);break;
 case 197:if(b<3)v=stat_(-1,(void*)c,1);else v=b<FD_MAX&&fds[b].used?stat_(fds[b].rec,(void*)c,1):-9;break;
 case 240:v=0;break;
 case 243:v=tls((u32*)b,gdt_);break;
 case 258:v=1;break;
 case 265:wr((void*)c,1700000000);wr((void*)(c+4),0);v=0;break;
 case 295:v=(int)b==-100?open_((char*)c,d):-9;break;
 case 300:v=(int)b==-100?pathstat((char*)c,(void*)d,1):-9;break;
 case 305:v=-2;break;
 case 355:{u8*p=(u8*)b;for(u32 i=0;i<c;i++)p[i]=(u8)(i*73+41);v=c;break;}
 case 340:if(r->si){wr((void*)r->si,0xffffffffU);wr((void*)(r->si+4),0x7fffffff);wr((void*)(r->si+8),0xffffffffU);wr((void*)(r->si+12),0x7fffffff);}v=0;break;
 case 383:{
  u32 p;char n[32];int index;
  if(!*(char*)c&&(d&4096))index=b<3?-3:b<FD_MAX&&fds[b].used?(int)fds[b].rec:-1;
  else index=resolve((char*)c,&p,n);
  if(index<0&&index!=-2&&index!=-3){v=index==-1?-2:index;break;}
  u8 *st=(u8*)r->di;zero(st,256);wr(st,0x7ff);wr(st+4,4096);wr(st+16,1);
  *(u16*)(st+28)=(index==-3?0020000:index==-2||rd(record(index)+36)==2?0040000:0100000)|0644;
  if(index>=0){wr(st+40,rd(record(index)+40));wr(st+48,(rd(record(index)+40)+511)/512);}v=0;break;
 }
 case 403:wr((void*)c,1700000000);wr((void*)(c+4),0);wr((void*)(c+8),0);wr((void*)(c+12),0);v=0;break;
 default:console('[');console('?');/* visible unsupported syscall */
  {u32 n=r->ax;char a[12];int j=0;do{a[j++]='0'+n%10;n/=10;}while(n);while(j)console(a[--j]);}console(']');break;
 }
 r->ax=v;
}
/* Returns initial ESP. Layout is ordinary i386 argc/argv/envp/auxv, with
 * no AT_SYSINFO so libc uses int 0x80 rather than a Linux vDSO. */
static u32 prepare(u8*elf,u32 size,u32 argc,u32*argv,u32 current,void(*out)(u32),u8*gdt){
 console=out;gdt_=gdt;cwd=current;heap=HEAP_START;mapped=MAP_START;dirty=0;zero(fds,FD_MAX*sizeof(struct fd));
 if(size<52||rd(elf)!=0x464c457f||elf[4]!=1||*(u16*)(elf+16)!=2||*(u16*)(elf+18)!=3)return 0;
 u32 ph=rd(elf+28),num=*(u16*)(elf+44);if(*(u16*)(elf+42)!=32||num>32||ph>size||num*32>size-ph)return 0;
 for(u32 i=0;i<num;i++){
  u8*p=elf+ph+i*32;if(rd(p)!=1)continue;
  u32 off=rd(p+4),addr=rd(p+8),file=rd(p+16),mem=rd(p+20);
  if(addr<0x08000000||addr>HEAP_START||mem>HEAP_START-addr||file>mem||off>size||file>size-off)return 0;
  zero((void*)addr,mem);memcopy((void*)addr,elf+off,file);
 }
 u32 *sp=(u32*)0x0bff0000;*--sp=0;*--sp=0;
 #define AUX(k,v) do{*--sp=(v);*--sp=(k);}while(0)
 for(u32 i=0;i<16;i++)((u8*)0x0bfe0000)[i]=i*73+41;
 AUX(25,0x0bfe0000);AUX(6,4096);AUX(3,0x08048000+ph);AUX(4,32);AUX(5,num);AUX(9,rd(elf+24));AUX(11,0);AUX(12,0);AUX(13,0);AUX(14,0);AUX(23,0);
 *--sp=0;*--sp=0;for(u32 i=argc;i;i--)*--sp=argv[i-1];*--sp=argc;
 return (u32)sp;
}
static u32 changed(void){if(dirty){u32 sum=0;for(u32 i=512;i<512+COUNT*REC;i++)sum+=FS[i];wr(FS+16,sum);}return dirty;}
/* Mount validator also works without the NASM high-memory mappings. Reject
 * orphan/shared extents, loops, duplicate names, invalid parents and lengths. */
static int validate_fs(u8*base){
 int old=0;
 if(rd(base)!=0x35465348||rd(base+4)!=5U||rd(base+8)!=COUNT||rd(base+12)!=REC)return -1;
 u32 sum=0;for(u32 i=512;i<512+COUNT*REC;i++)sum+=base[i];if(sum!=rd(base+16))return -2;
 u8 visited[COUNT];zero(visited,COUNT);
 for(u32 i=0;i<COUNT;i++){
  u8*r=base+512+i*REC;if(!*r)continue;u32 kind=rd(r+36),length=rd(r+40);
  if(kind==4){if(old||r[0]!=255||rd(r+32)>=COUNT||length>LIMIT)return -3;continue;}
  if(kind==5){u32 start=rd(r+48),sectors=rd(r+52),parent=rd(r+32),steps=0;
   if(r[31]||!length||length>104857600U||start<16384||sectors!=(length+511)/512||start>0x0fffffffU-sectors||rd(r+44))return -13;
   for(u32 j=0;j<i;j++){u8*q=base+512+j*REC;if(!*q||rd(q+36)==4)continue;
    if(rd(q+32)==parent&&eq((char*)r,(char*)q))return -6;
    if(rd(q+36)==5){u32 other=rd(q+48),end=other+rd(q+52);if(start<end&&other<start+sectors)return -14;}}
   while(parent!=ROOT){if(parent>=COUNT||++steps>COUNT)return -7;u8*q=base+512+parent*REC;if(!*q||rd(q+36)!=2)return -7;parent=rd(q+32);}
   visited[i]=1;continue;}
  if(kind<1||kind>3||r[31]||length>FILE_MAX||(old&&length>LIMIT)||(kind==2&&(length||rd(r+44))))return -4;
  for(u32 j=0;j<32&&r[j];j++){u8 c=r[j];if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='.'||c=='_'||c=='-'))return -5;}
  if(eq((char*)r,".")||eq((char*)r,".."))return -5;
  for(u32 j=0;j<i;j++){u8*q=base+512+j*REC;if(*q&&rd(q+36)!=4&&rd(q+32)==rd(r+32)&&eq((char*)r,(char*)q))return -6;}
  u32 parent=rd(r+32),steps=0;
  while(parent!=ROOT){if(parent>=COUNT||++steps>COUNT)return -7;u8*q=base+512+parent*REC;if(!*q||rd(q+36)!=2)return -7;parent=rd(q+32);}
  u8*q=r;u32 left=length;
  for(;;){u32 index=(q-base-512)/REC;if(visited[index]++)return -8;
   u32 used=left>LIMIT?LIMIT:left;
   if(kind==1&&q[64+used])return -9;
   if(q!=r&&(rd(q+36)!=4||q[0]!=255||rd(q+32)!=i||rd(q+40)!=used))return -10;
   u32 next=rd(q+44);
   if(left<=LIMIT){if(next)return -11;break;}
   if(!next||next>COUNT)return -11;
   q=base+512+(next-1)*REC;left-=LIMIT;
  }
 }
 for(u32 i=0;i<COUNT;i++)if(base[512+i*REC]&&!visited[i])return -12;
 
 return 0;
}
#include "extensions/services.h"
/* Fixed entry table consumed by src/nasm.asm. */
__attribute__((section(".entry"),used)) void *entries[]={prepare,syscall_,changed,validate_fs,services_init,services_cmd,services_draw,usb_keyboard_poll};
