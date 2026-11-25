/* Shared helpers for PCI host enumeration and xHCI MSC configuration. */
#define USB_HOST_MAX 8
/* Enumerate PCI once, keeping a compact list for each supported HC type.
 * Try the next controller if an earlier one has no usable device. */
static u16 usb_pci[3][USB_HOST_MAX];static u8 usb_pci_n[3];
static void usb_pci_discover(void){
 zero(usb_pci_n,sizeof usb_pci_n);
 for(u32 b=0;b<256;b++)for(u32 d=0;d<32;d++){
   u32 a=(b<<8)|(d<<3);
   if((pcird(a,0)&65535)==65535)continue;
   u32 n=(pcird(a,12)&0x00800000)?8:1;
   for(u32 f=0;f<n;f++){
     u32 cl=pcird(a+f,8)>>8;if((cl>>8)!=0xc03)continue;
     u32 p=cl&255,i=p==0x20?0:p==0?1:p==0x30?2:3;
     if(i<3&&usb_pci_n[i]<USB_HOST_MAX)usb_pci[i][usb_pci_n[i]++]=a+f;
   }
 }
}
static int modern_enumerate(u32 port,u32 slot_type,u32 index,int legacy){
  struct xslot*s=&H.dev[index];struct usbdev d;zero(&d,sizeof d);
  u8 desc[1024];u32 speed=1;
  d.port=port;
  if(legacy){d.backend=2;d.mps0=8;}
  else{if(!xaddress(s,port,slot_type))return 0;d.backend=1;d.hostindex=index;d.address=s->id;speed=s->speed;}
  if(devcontrol(&d,0x80,6,0x100,0,desc,8)!=8)return 0;
  u32 mps=desc[7];
  if(legacy){
    if(mps!=8&&mps!=16&&mps!=32&&mps!=64)return 0;
    d.mps0=mps;
    if(devcontrol(&d,0,5,port+1,0,0,0)<0)return 0;
    d.address=port+1;delay(2);
  }else if(speed==1&&(mps==16||mps==32||mps==64)){
    zero((void*)H.input,4096);((u32*)H.input)[1]=2;
    u32*p=xctx(1);memcopy(p,(void*)(s->ctx+H.stride),H.stride);
    p[0]=0;p[1]=(p[1]&65535)|(mps<<16);p[2]=p[3]=p[4]=0;
    if(!xcmd(13,H.input,s->id,0,0))return 0;
  }
  if(devcontrol(&d,0x80,6,0x100,0,desc,18)!=18||desc[0]!=18)return 0;
  d.vid=le16(desc+8);d.pid=le16(desc+10);
  if(devcontrol(&d,0x80,6,0x200,0,desc,9)!=9)return 0;
  u32 size=le16(desc+2);if(size<9||size>sizeof desc)return 0;
  if(devcontrol(&d,0x80,6,0x200,0,desc,size)!=(int)size)return 0;
  d.cfg=desc[5];int iface=0,last=0;u32 bi=0,bo=0;
  for(u32 o=0;o+2<=size;){
    u32 len=desc[o],type=desc[o+1];if(len<2||len>size-o)return 0;
    if(type==4){
      if(d.epin&&d.epout)break;
      iface=len>=9&&desc[o+3]==0&&desc[o+5]==8&&desc[o+6]==6&&desc[o+7]==0x50;
      if(iface){d.iface=desc[o+2];d.epin=d.epout=0;bi=bo=0;}
      last=0;
    }else if(iface&&type==5&&len>=7&&(desc[o+3]&3)==2){
      u32 m=le16(desc+o+4),ep=desc[o+2]&15;
      if(!ep||!m||m>1024||(speed==1&&m>64)||(speed==3&&m!=512)||(speed==4&&m!=1024))return 0;
      last=(desc[o+2]&128)?1:2;
      if(last==1){d.epin=ep;d.mpsin=m;}else{d.epout=ep;d.mpsout=m;}
    }else if(iface&&type==48&&len>=6&&speed==4){
      if(last==1)bi=desc[o+2]&15;else if(last==2)bo=desc[o+2]&15;
    }else last=0;
    o+=len;
  }
  if(!d.epin||!d.epout)return 0;
  if((!legacy&&!xconfigure(s,&d,bi,bo))||devcontrol(&d,0,9,d.cfg,0,0,0)<0)return 0;
  return msc_probe(&d);
}
static void xhci_scan(u32 bdf){
  if(!xhci_start(bdf)){xs("USB xHCI: fallo inicializacion.\n");return;}
  u32 base=pcird(bdf,16)&~15U;volatile u32*cap=(volatile u32*)base;
  for(u32 p=0;p<H.ports;p++){volatile u32*r=xport(p);if(!(*r&(1<<9)))*r=(*r&0x0e00c200U)|(1<<9);}
  delay(10);
  u32 found=0;
  for(u32 p=0;p<H.ports&&U.count<4&&found<H.slots&&!H.dead;p++){
    volatile u32*r=xport(p);if(!(*r&1))continue;
    u32 slot_type=0, ext=(cap[4]>>16)*4;
    for(u32 n=0;ext>=0x20&&ext<0xff00&&n<64;n++){
      volatile u32*q=(volatile u32*)(base+ext);u32 v=*q;
      if((v&255)==2){u32 first=q[2]&255,num=(q[2]>>8)&255;if(p+1>=first&&p+1-first<num){slot_type=q[3]&31;break;}}
      if(!((v>>8)&255))break;
      ext+=((v>>8)&255)*4;
    }
    if(!(*r&2)){*r=(*r&0x0e00c200U)|(1<<4);if(!waitreg(r,1<<4,0,100)||!(*r&2))continue;}
    *r=(*r&0x0e00c200U)|0x00fe0000U;
    struct xslot*s=&H.dev[found];zero(s,sizeof *s);u32 old=H.used;
    if(modern_enumerate(p,slot_type,found,0))found++;
    else if(!H.dead){if(s->id&&!xcmd(10,0,s->id,0,0)){H.dead=1;break;}H.used=old;zero(s,sizeof *s);}
  }
  xs("USB xHCI: ");xn(found);xs(" disco(s) de 512 bytes detectado(s).\n");
}

static void uhci_scan(u32 bdf){
 if(!uhci_start(bdf)){xs("USB UHCI: fallo inicializacion.\n");return;}
 u32 found=0;delay(10);
 for(u32 p=0;p<2&&U.count<4&&!L.dead;p++){
  u32 off=16+2*p;if(!(lin(off)&1)||(lin(off)&256))continue;
  lout(off,1<<9);delay(6);lout(off,0);delay(1);lout(off,4|10);delay(1);
  if((lin(off)&5)!=5)continue;
  lout(off,4|10);
  if(modern_enumerate(p,0,0,1))found++;else lout(off,10);
 }
 xs("USB UHCI: ");xn(found);xs(" disco(s).\n");
}
