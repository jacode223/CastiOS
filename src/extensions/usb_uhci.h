/* Experimental UHCI full-speed root-port MSC, polled DMA with bounded waits.
 * Reference: Intel UHCI design guide / OSDev UHCI. No hub or interrupt HID. */
static struct {u32 bdf,frames,tds,buf;u16 io;u8 dead;} L;
static u16 lin(u32 o){u16 v;__asm__ volatile("inw %w1,%0":"=a"(v):"d"((u16)(L.io+o)));return v;}
static void lout(u32 o,u16 v){__asm__ volatile("outw %0,%w1"::"a"(v),"d"((u16)(L.io+o)));}
static int lwait(u32 o,u16 mask,u16 val,u32 ticks){
 u32 start=*X.ticks;for(u32 n=0;n<30000000;n++){
  if((lin(o)&mask)==val)return 1;
  if((u32)(*X.ticks-start)>=ticks)break;
  usb_wait_step(n);
 }return 0;
}
static int uhci_stop(void){
 if(!L.io)return 1;
 if(pcird(L.bdf,0)==0xffffffffU)return 0;
 lout(0,0);if(!lwait(2,32,32,100))return 0;L.io=0;
 if(L.frames)X.free(L.frames);
 if(L.tds)X.free(L.tds);
 if(L.buf)X.free(L.buf);
 L.frames=L.tds=L.buf=0;return 1;
}
static int lconnected(struct usbdev*d){return L.io&&!L.dead&&(lin(16+d->port*2)&7)==5;}
/* DMA frame schedule is stopped before touching descriptors or buffer again. */
static int lpacket(u32 addr,u32 ep,u32 mps,u32 pid,void*data,u32 n,u8*toggle){
 if(!L.io||L.dead||!mps||mps>64||n>3072)return -1;
 u32 cnt=n?(n+mps-1)/mps:1;if(cnt>255)return -1;
 volatile u32*qh=(volatile u32*)L.tds;volatile u32*td=qh+4;
 if(pid!=0x69&&n)memcopy((void*)L.buf,data,n);
 for(u32 i=0,off=0;i<cnt;i++){
  u32 take=n-off;if(take>mps)take=mps;
  volatile u32*t=td+4*i;t[0]=(i+1==cnt)?1:(L.tds+16*(i+2))|4;
  t[1]=(3<<27)|(1<<23)|(pid==0x69?1<<29:0)|0x7ff;
  t[2]=pid|(addr<<8)|(ep<<15)|(((*toggle^(i&1))&1)<<19)|(((take-1)&2047)<<21);
  t[3]=L.buf+off;off+=take;
 }
 qh[0]=1;qh[1]=L.tds+16;barrier();lout(2,0x3f);lout(0,0xc1);
 u32 actual=0,completed=0,start=*X.ticks;int ok=0;
 for(u32 spin=0;spin<30000000;spin++){
  while(completed<cnt){u32 st=td[completed*4+1];if(st&(1<<23))break;
   if(st&0x7e0000)goto done;
   u32 got=(st+1)&2047,take=n-actual;if(take>mps)take=mps;
   if(got>take)goto done;
   actual+=got;completed++;
   if(got<take||completed==cnt){ok=1;goto done;}
  }
  if((u32)(*X.ticks-start)>=200)break;
  usb_wait_step(spin);
 }
 done:lout(0,0);if(!lwait(2,32,32,100)){L.dead=1;return -1;}
 if(!ok)return -1;
 if(pid==0x69&&actual)memcopy(data,(void*)L.buf,actual);
 *toggle^=completed&1;return actual;
}
static int lcontrol(struct usbdev*d,u8 type,u8 req,u16 val,u16 idx,void*data,u16 n){
 u8 s[8]={type,req,val,val>>8,idx,idx>>8,n,n>>8},t=0;
 if(lpacket(d->address,0,d->mps0,0x2d,s,8,&t)!=8)return -1;
 t=1;int got=0;
 if(n){got=lpacket(d->address,0,d->mps0,(type&128)?0x69:0xe1,data,n,&t);if(got<0)return -1;}
 t=1;if(lpacket(d->address,0,d->mps0,(n&&(type&128))?0xe1:0x69,0,0,&t)<0)return -1;
 return got;
}
static int lbulk(struct usbdev*d,int in,void*data,u32 n){
 return lpacket(d->address,in?d->epin:d->epout,in?d->mpsin:d->mpsout,in?0x69:0xe1,data,n,in?&d->tin:&d->tout);
}
static int uhci_start(u32 bdf){
 u32 bar=pcird(bdf,0x20);if(!(bar&1)||(bar&~31U)>0xffe0||!(bar&~31U))return 0;
 L.bdf=bdf;L.io=bar&~31U;L.dead=1;
 u32 a=(bdf<<8)|0x80000004;u16 v;
 __asm__ volatile("outl %0,%w1"::"a"(a),"d"((u16)0xcf8));
 __asm__ volatile("inw %w1,%0":"=a"(v):"d"((u16)0xcfc));v|=5;
 __asm__ volatile("outw %0,%w1"::"a"(v),"d"((u16)0xcfc));
 pciwr(bdf,0xc0,0x8f00);lout(4,0);lout(0,0);
 if(!lwait(2,32,32,100))return 0;
 lout(0,2);if(!lwait(0,2,0,100))return 0;
 if(!L.frames)L.frames=X.alloc();
 if(!L.tds)L.tds=X.alloc();
 if(!L.buf)L.buf=X.alloc();
 if(!L.frames||!L.tds||!L.buf)return 0;
 u32*f=(u32*)L.frames;for(u32 i=0;i<1024;i++)f[i]=L.tds|2;
 ((u32*)L.tds)[0]=((u32*)L.tds)[1]=1;
 __asm__ volatile("outl %0,%w1"::"a"(L.frames),"d"((u16)(L.io+8)));
 __asm__ volatile("outb %0,%w1"::"a"((u8)64),"d"((u16)(L.io+12)));
 lout(6,0);lout(2,0x3f);lout(0,0xc1);L.dead=0;return 1;
}
