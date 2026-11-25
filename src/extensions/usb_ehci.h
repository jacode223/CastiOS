/* USB2 root-port high-speed MSC/SCSI/BOT and one periodic HID boot keyboard. */
struct usbdev {
  u32 cap, port;
  u16 vid, pid, mpsin, mpsout;
  u8 backend, hostindex, mps0;
  u8 address, epin, epout, cfg, iface, tin, tout, valid;
  u32 errors;
};
struct usbkbd {
  u32 port;
  u16 vid,pid,mps;
  u8 address,iface,epin,interval,valid;
  struct hid_boot_keys keys;
};
static struct {
  volatile u32 *op;
  u32 dma, bdf, ports, tag;
  int dead, scanned;
  struct usbdev d[4];
  u32 count;
  struct usbkbd kbd[4];
  u32 kbd_count;
  u32 frame_dma, hid_dma, mouse_dma;
  struct usbkbd mouse;
  struct hid_boot_mouse mouse_keys;
  u8 mouse_count, mouse_toggle;
  u8 hid_active, hid_toggle;
} U;
#include "usb_xhci.h"
#include "usb_uhci.h"
static int async_stop(void) {
  if (!U.op)
    return 0;
  U.op[0] &= ~32U;
  if (!waitreg(U.op + 1, 1U << 15, 0, 100)) {
    U.op[0] &= ~1U;
    waitreg(U.op + 1, 1U << 12, 1U << 12, 100);
    U.dead = 1;
    return 0;
  }
  return 1;
}
static void qtd(u32 *p, u32 next, u32 pid, u32 bytes, u32 toggle, u32 buf) {
  zero(p, 64);
  p[0] = next;
  p[1] = 1;
  p[2] = 0x80 | (pid << 8) | (3 << 10) | (bytes << 16) | (toggle << 31);
  p[3] = buf;
  for (int i = 1; i < 5; i++)
    p[3 + i] = (buf & ~4095U) + i * 4096;
}
static void usb_keyboard_stop(void) {
  if (U.hid_active && U.op) {
    U.op[0] &= ~16U;
    if (!waitreg(U.op + 1, 1U << 14, 0, 100))
      U.dead = 1;
  }
  U.hid_active = 0;
}
static void hid_qh_arm(struct usbkbd *k, u32 dma, u32 bytes, u32 toggle, u32 next) {
  u32 *qh=(u32 *)dma, *td=(u32 *)(dma+128);
  zero(qh,128); qh[0]=next;
  qh[1]=k->address|((u32)k->epin<<8)|(2U<<12)|(1U<<14)|((u32)k->mps<<16);
  qh[2]=(1U<<30)|1U; qh[4]=dma+128; qh[5]=1;
  qtd(td,1,1,bytes,toggle,dma+512);
}
static void hid_mouse_emit(int dx,int dy,u8 buttons,u8 pressed){
  int x=(int)*X.mouse_x+dx, y=(int)*X.mouse_y+dy;
  if(x<0)x=0;
  if(x>959)x=959;
  if(y<0)y=0;
  if(y>599)y=599;
  *X.mouse_x=(u32)x; *X.mouse_y=(u32)y;
  *X.mouse_buttons=buttons; *X.mouse_click|=pressed&1;
  *X.mouse_event=1;
}
static void usb_keyboard_start(void) {
  if ((!U.kbd_count&&!U.mouse_count)||U.dead||!U.op)return;
  if (!U.frame_dma) U.frame_dma=X.alloc();
  if (U.kbd_count&&!U.hid_dma) U.hid_dma=X.alloc();
  if (U.mouse_count&&!U.mouse_dma) U.mouse_dma=X.alloc();
  if (!U.frame_dma||(U.kbd_count&&!U.hid_dma)||(U.mouse_count&&!U.mouse_dma))return;
  U.hid_toggle=U.mouse_toggle=0;
  if(U.mouse_count)hid_qh_arm(&U.mouse,U.mouse_dma,3,0,1);
  if(U.kbd_count)hid_qh_arm(&U.kbd[0],U.hid_dma,8,0,U.mouse_count?(U.mouse_dma|2):1);
  u32 *frames=(u32 *)U.frame_dma;
  u32 head=U.kbd_count?U.hid_dma:U.mouse_dma;
  for(u32 i=0;i<1024;i++)frames[i]=head|2;
  barrier(); U.op[5]=U.frame_dma; U.op[0]|=16U; U.hid_active=1;
}
static void usb_keyboard_poll(void) {
  if(!U.hid_active||U.dead)return;
  u32 kt=U.kbd_count&&U.kbd[0].valid?((volatile u32 *)(U.hid_dma+128))[2]:0x80;
  u32 mt=U.mouse_count&&U.mouse.valid?((volatile u32 *)(U.mouse_dma+128))[2]:0x80;
  if(U.kbd_count&&U.kbd[0].valid&&!(U.op[0x44/4+U.kbd[0].port]&1))kt=0;
  if(U.mouse_count&&U.mouse.valid&&!(U.op[0x44/4+U.mouse.port]&1))mt=0;
  if((kt&0x80)&&(mt&0x80))return;
  usb_keyboard_stop(); if(U.dead)return;
  if(!(kt&0x80)){
    if((kt&0x7c)||((kt>>16)&0x7fff)||!(U.op[0x44/4+U.kbd[0].port]&1)){
      const u8 release[8]={0};hid_boot_report(&U.kbd[0].keys,release,X.key_emit);U.kbd[0].valid=0;
    }else{
      hid_boot_report(&U.kbd[0].keys,(const u8 *)(U.hid_dma+512),X.key_emit);
      U.hid_toggle^=1;
      hid_qh_arm(&U.kbd[0],U.hid_dma,8,U.hid_toggle,U.mouse_count&&U.mouse.valid?(U.mouse_dma|2):1);
    }
  }
  if(!(mt&0x80)){
    if((mt&0x7c)||((mt>>16)&0x7fff)||!(U.op[0x44/4+U.mouse.port]&1)){
      U.mouse.valid=0; U.mouse_keys.buttons=0; *X.mouse_buttons=0;
    }else{
      hid_boot_mouse_report(&U.mouse_keys,(const u8 *)(U.mouse_dma+512),3,hid_mouse_emit);
      U.mouse_toggle^=1;hid_qh_arm(&U.mouse,U.mouse_dma,3,U.mouse_toggle,1);
    }
  }
  /* A failed queue head must not keep the other input device from polling. */
  if(U.kbd_count&&U.kbd[0].valid){
    ((u32 *)U.hid_dma)[0]=U.mouse_count&&U.mouse.valid?(U.mouse_dma|2):1;
    u32 *frames=(u32 *)U.frame_dma;for(u32 i=0;i<1024;i++)frames[i]=U.hid_dma|2;
  }else if(U.mouse_count&&U.mouse.valid){
    u32 *frames=(u32 *)U.frame_dma;for(u32 i=0;i<1024;i++)frames[i]=U.mouse_dma|2;
  }else return;
  barrier();U.op[0]|=16U;U.hid_active=1;
}
static int ehci_transfer(u32 addr, u32 ep, u32 mps, int in, void *data, u32 n,
                         const u8 *setup, u8 *toggle) {
  if (U.dead || !U.op || !U.dma || n > 3072 || !mps || mps > 512 ||
      !async_stop())
    return -1;
  u32 *qh = (u32 *)U.dma, *a = (u32 *)(U.dma + 128), *b = (u32 *)(U.dma + 192),
      *c = (u32 *)(U.dma + 256);
  u8 *buf = (u8 *)(U.dma + 512);
  zero(qh, 96);
  qh[0] = U.dma | 2;
  qh[1] = addr | (ep << 8) | (2 << 12) | (1 << 14) | (1 << 15) | (mps << 16) |
          (4U << 28);
  qh[2] = 1U << 30;
  qh[4] = U.dma + 128;
  qh[5] = 1;
  volatile u32 *last;
  u32 *datatd;
  if (setup) {
    memcopy((void *)(U.dma + 384), setup, 8);
    qtd(a, U.dma + (n ? 192 : 256), 2, 8, 0, U.dma + 384);
    qtd(b, U.dma + 256, in ? 1 : 0, n, 1, U.dma + 512);
    b[1] = U.dma + 256;
    qtd(c, 1, (!n || !in) ? 1 : 0, 0, 1, U.dma + 512);
    last = c;
    datatd = b;
  } else {
    qtd(a, 1, in ? 1 : 0, n, *toggle, U.dma + 512);
    last = a;
    datatd = a;
  }
  if (n && !in)
    memcopy(buf, data, n);
  U.op[6] = U.dma;
  barrier();
  U.op[1] = 0x3f;
  U.op[0] |= 33;
  u32 start = *X.ticks;
  int done = 0;
  for (u32 k = 0; k < 30000000; k++) {
    barrier();
    if (!(last[2] & 0x80)) {
      done = 1;
      break;
    }
    if ((a[2] | (setup && n ? b[2] : 0) | last[2]) & 0x7c)
      break;
    if ((u32)(*X.ticks - start) > 200)
      break;
    usb_wait_step(k);
  }
  if (!async_stop())
    return -1;
  if (!done || ((a[2] | (setup && n ? b[2] : 0) | last[2]) & 0x7c))
    return -1;
  u32 remaining = n ? ((datatd[2] >> 16) & 0x7fff) : 0;
  if (remaining > n)
    return -1;
  u32 actual = n - remaining;
  if (n && in)
    memcopy(data, buf, actual);
  if (!setup) {
    u32 packets = (actual + mps - 1) / mps;
    if (actual < n && actual % mps == 0)
      packets++;
    *toggle ^= packets & 1;
  }
  return (int)actual;
}
static int ucontrol(u32 addr, u8 type, u8 req, u16 val, u16 idx, void *data,
                    u16 n) {
  u8 s[8] = {type, req, val, val >> 8, idx, idx >> 8, n, n >> 8};
  u8 t = 0;
  return ehci_transfer(addr, 0, 64, !!(type & 128), data, n, s, &t);
}
static int usb_connected(struct usbdev *d){
  if(!d->valid)return 0;
  if(d->backend==1)return xconnected(&H.dev[d->hostindex]);
  if(d->backend==2)return lconnected(d);
  return U.op&&!U.dead&&((U.op[0x44/4+d->port]&3)==1);
}
static int devcontrol(struct usbdev*d,u8 type,u8 req,u16 val,u16 idx,void*data,u16 n){
  if(d->backend==2)return lcontrol(d,type,req,val,idx,data,n);
  return d->backend==1?xcontrol(&H.dev[d->hostindex],type,req,val,idx,data,n):ucontrol(d->address,type,req,val,idx,data,n);
}
static int ubulk(struct usbdev *d, int in, void *p, u32 n) {
  if(!usb_connected(d))return -1;
  if(d->backend==1)return xbulk(d,in,p,n);
  if(d->backend==2)return lbulk(d,in,p,n);
  volatile u32 *port = U.op + 0x44 / 4 + d->port;
  if (!d->valid || !(*port & 1))
    return -1;
  return ehci_transfer(d->address, in ? d->epin : d->epout, in?d->mpsin:d->mpsout, in, p, n, 0,
                       in ? &d->tin : &d->tout);
}
/* BOT reset recovery: clear both halted pipes and restart their data toggles.
 * Never retry a detached device; a rescan must reassign its address. */
static int usb_bot_recover(struct usbdev *d) {
  if (!usb_connected(d)) {
    d->valid = 0;
    return -1;
  }
  /* xHCI endpoint reset/dequeue recovery is not implemented: require rescan. */
  if(d->backend==1){d->valid=0;return -1;}
  if (devcontrol(d, 0x21, 0xff, 0, d->iface, 0, 0) < 0 ||
      devcontrol(d, 0x02, 1, 0, 0x80 | d->epin, 0, 0) < 0 ||
      devcontrol(d, 0x02, 1, 0, d->epout, 0, 0) < 0) {
    d->valid = 0;
    return -1;
  }
  d->tin = d->tout = 0;
  return 0;
}
static int usCSI(struct usbdev *d, const u8 *cdb, u32 cdbn, void *data, u32 n) {
  u8 cbw[31], csw[13];
  zero(cbw, 31);
  st32(cbw, 0x43425355);
  u32 tag = ++U.tag;
  st32(cbw + 4, tag);
  st32(cbw + 8, n);
  cbw[12] = n ? 0x80 : 0;
  cbw[14] = cdbn;
  memcopy(cbw + 15, cdb, cdbn);
  int actual=0;
  if (ubulk(d, 0, cbw, 31) != 31 || (n && (actual=ubulk(d, 1, data, n))<0) ||
      ubulk(d, 1, csw, 13) != 13) {
    d->errors++;
    usb_bot_recover(d);
    return -1;
  }
  if (le32(csw) != 0x53425355 || le32(csw + 4) != tag || le32(csw + 8) > n ||
      csw[12] > 2) {
    d->errors++;
    usb_bot_recover(d);
    return -1;
  }
  if (csw[12] || le32(csw + 8) || (u32)actual!=n) {
    if(csw[12]==2)usb_bot_recover(d);
    d->errors++;
    return -1;
  }
  return 0;
}
static int usb_read_blocks(u32 which, u32 lba, void *p,u32 count) {
  if (which >= U.count || !usb_connected(&U.d[which]) || !count || count>6 || lba >= U.d[which].cap || count>U.d[which].cap-lba)
    return -1;
  u8 c[10] = {0x28, 0, 0, 0, 0, 0, 0, 0, 1, 0};
  bput32(c + 2, lba);c[8]=count;
  struct usbdev *d = &U.d[which];
  for (int attempt = 0; attempt < 3 && d->valid; attempt++) {
    if (!usCSI(d, c, 10, p, count*512))
      return 0;
    if (!d->valid)
      break;
    u8 sense[18], request[6] = {3, 0, 0, 0, 18, 0};
    usCSI(d, request, 6, sense, 18); /* clears unit attention, if present */
    delay(2);
  }
  return -1;
}
/* A read-ahead page is optional and allocated only for USB storage. */
static u32 usb_cache, cache_disk, cache_lba, cache_count;
static void usb_cache_reset(void){cache_count=0;cache_lba=0xffffffffU;}
static int usb_read(u32 which,u32 lba,void *p){
  if(which>=U.count||!usb_connected(&U.d[which])||lba>=U.d[which].cap){cache_count=0;return -1;}
  if(cache_count&&which==cache_disk&&lba>=cache_lba&&lba-cache_lba<cache_count){
    memcopy(p,(void*)(usb_cache+(lba-cache_lba)*512),512);return 0;
  }
  cache_count=0;
  /* Do not prefetch random FAT/GPT sectors: detect sequential requests first. */
  u32 count=1;
  if(usb_cache&&cache_disk==which&&cache_lba!=0xffffffffU&&lba==cache_lba+1){
    count=U.d[which].cap-lba;if(count>6)count=6;
    if(U.d[which].backend==2&&count>2)count=2;
  }
  if(!usb_cache)usb_cache=X.alloc();
  if(usb_cache&&count>1&&!usb_read_blocks(which,lba,(void*)usb_cache,count)){
    cache_disk=which;cache_lba=lba;cache_count=count;memcopy(p,(void*)usb_cache,512);return 0;
  }
  cache_disk=which;cache_lba=lba;
  return usb_read_blocks(which,lba,p,1);
}
static int msc_probe(struct usbdev*d){
  d->valid=1;
  u8 cap[8], c[10]={0x25}, sense[18], req[6]={3,0,0,0,18,0},tur[6]={0};
  for(int tries=0;tries<8&&d->valid;tries++){
    if(usCSI(d,tur,6,0,0)&&d->valid)usCSI(d,req,6,sense,18);
    if(d->valid&&!usCSI(d,c,10,cap,8)){
      if(be32(cap+4)!=512){xs("USB: sector logico distinto de 512 no soportado.\n");return 0;}
      if(be32(cap)==0xffffffffU){xs("USB: capacidad supera LBA32.\n");return 0;}
      d->cap=be32(cap)+1;U.d[U.count++]=*d;return 1;
    }
    if(d->valid){usCSI(d,req,6,sense,18);delay(10);}
  }
  xs("USB: MSC no listo o fallo SCSI.\n");return 0;
}
static int usb_enumerate(u32 port) {
  struct usbdev d;
  zero(&d, sizeof d);
  d.port = port;
  d.address = port + 1;
  u8 desc[1024];
  if (ucontrol(0, 0x80, 6, 0x100, 0, desc, 18) != 18 || desc[0] != 18 ||
      desc[7] != 64)
    return 0;
  d.vid = le16(desc + 8);
  d.pid = le16(desc + 10);
  if (ucontrol(0, 0, 5, d.address, 0, 0, 0) < 0)
    return 0;
  delay(2);
  if (ucontrol(d.address, 0x80, 6, 0x200, 0, desc, 9) != 9)
    return 0;
  u32 size = le16(desc + 2);
  if (size < 9 || size > sizeof desc)
    return 0;
  if (ucontrol(d.address, 0x80, 6, 0x200, 0, desc, size) != (int)size)
    return 0;
  d.cfg = desc[5];
  int iface = 0;
  u8 hid_iface=0,hid_ep=0,hid_interval=0,mouse_iface=0,mouse_ep=0,mouse_interval=0;
  u16 hid_mps=0,mouse_mps=0;
  int hid_active=0,mouse_active=0;
  for (u32 o = 0; o + 2 <= size;) {
    u32 len = desc[o];
    if (len < 2 || len > size - o)
      return 0;
    if (desc[o + 1] == 4) {
      hid_active=len>=9&&desc[o+3]==0&&desc[o+5]==3&&desc[o+6]==1&&desc[o+7]==1;
      if(hid_active)hid_iface=desc[o+2];
      mouse_active=len>=9&&desc[o+3]==0&&desc[o+5]==3&&desc[o+6]==1&&desc[o+7]==2;
      if(mouse_active)mouse_iface=desc[o+2];
      iface = len >= 9 && desc[o + 3] == 0 && desc[o + 5] == 8 &&
              desc[o + 6] == 6 && desc[o + 7] == 0x50;
      if (iface) {
        d.iface = desc[o+2];
        d.epin = 0;
        d.epout = 0;
      }
    }
    if(hid_active&&desc[o+1]==5&&len>=7&&(desc[o+2]&128)&&
       (desc[o+3]&3)==3&&le16(desc+o+4)>=8&&le16(desc+o+4)<=64){
      hid_ep=desc[o+2]&15;hid_mps=le16(desc+o+4);hid_interval=desc[o+6];
    }
    if(mouse_active&&desc[o+1]==5&&len>=7&&(desc[o+2]&128)&&
       (desc[o+3]&3)==3&&le16(desc+o+4)>=3&&le16(desc+o+4)<=64){
      mouse_ep=desc[o+2]&15;mouse_mps=le16(desc+o+4);mouse_interval=desc[o+6];
    }
    if (iface && desc[o + 1] == 5 && len >= 7 && (desc[o + 3] & 3) == 2 &&
        le16(desc + o + 4) == 512) {
      u8 ep = desc[o + 2];
      if (ep & 128)
        d.epin = ep & 15, d.mpsin=512;
      else
        d.epout = ep & 15, d.mpsout=512;
    }
    o += len;
  }
  /* Keep the existing mass-storage path for composite devices. */
  if(hid_ep&&!(d.epin&&d.epout)&&U.kbd_count<4){
    if(ucontrol(d.address,0,9,d.cfg,0,0,0)<0)return 0;
    if(ucontrol(d.address,0x21,11,0,hid_iface,0,0)<0)return 0;
    /* SET_IDLE is optional on some boot keyboards. */
    ucontrol(d.address,0x21,10,0,hid_iface,0,0);
    struct usbkbd *k=&U.kbd[U.kbd_count++];
    zero(k,sizeof *k);k->port=port;k->vid=d.vid;k->pid=d.pid;
    k->address=d.address;k->iface=hid_iface;k->epin=hid_ep;
    k->mps=hid_mps;k->interval=hid_interval;k->valid=1;
    return 1;
  }
  if(mouse_ep&&!(d.epin&&d.epout)&&!U.mouse_count){
    if(ucontrol(d.address,0,9,d.cfg,0,0,0)<0)return 0;
    if(ucontrol(d.address,0x21,11,0,mouse_iface,0,0)<0)return 0;
    ucontrol(d.address,0x21,10,0,mouse_iface,0,0);
    struct usbkbd *m=&U.mouse;zero(m,sizeof *m);
    m->port=port;m->vid=d.vid;m->pid=d.pid;m->address=d.address;
    m->iface=mouse_iface;m->epin=mouse_ep;m->mps=mouse_mps;m->interval=mouse_interval;m->valid=1;
    U.mouse_count=1;return 1;
  }
  if(U.count==4)return 0;
  if (!d.epin || !d.epout || ucontrol(d.address, 0, 9, d.cfg, 0, 0, 0) < 0)
    return 0;
  return msc_probe(&d);
}
#include "usb_storage_hosts.h"
static void ehci_scan(u32 bdf) {
  if(U.mouse_count){ U.mouse_keys.buttons=0; *X.mouse_buttons=0; }
  if (U.hid_active && U.kbd_count) {
    const u8 release[8] = {0};
    hid_boot_report(&U.kbd[0].keys, release, X.key_emit);
  }
  if (U.op && pcird(U.bdf, 0) == 0xffffffffU) {
    U.op = 0; /* PCI hot-unplug: old MMIO BAR is no longer owned. */
    U.hid_active = 0;
  }
  usb_keyboard_stop();
  if (U.op) {
    U.op[0] &= ~1U;
    if (!waitreg(U.op + 1, 1 << 12, 1 << 12, 100)) {
      xs("USB: controlador no responde; reinicia.\n");
      U.dead = 1;
      U.count = 0;
      zero(U.d, sizeof U.d);
      U.kbd_count=0;
      zero(U.kbd,sizeof U.kbd);
      U.scanned = 1;
      return;
    }
  }
  U.count = 0;
  zero(U.d, sizeof U.d);
  U.kbd_count=0;
  zero(U.kbd,sizeof U.kbd);
  U.mouse_count=0; zero(&U.mouse,sizeof U.mouse); zero(&U.mouse_keys,sizeof U.mouse_keys);
  U.dead = 0;
  U.scanned = 1;
  U.op = 0;
  if (bdf == 65536) {
    xs("USB: no hay EHCI.\n");
    return;
  }
  u32 base = pcird(bdf, 16);
  if ((base & 7) || !(base & ~15U) || base < 0x2000000 || base > 0xffffe000) {
    xs("USB: BAR EHCI incompatible.\n");
    return;
  }
  base &= ~15U;
  if (base > 0xfffff000U || X.map(base) || X.map(base + 4095)) {
    xs("USB: fallo MMIO.\n");
    return;
  }
  pcienable(bdf);
  volatile u32 *cap = (volatile u32 *)base;
  u32 off = cap[0] & 255;
  if (off < 16 || off > 64)
    return;
  u32 eecp = (cap[2] >> 8) & 255;
  for (int n = 0; eecp >= 0x40 && eecp <= 0xfc && n < 48; n++) {
    u32 v = pcird(bdf, eecp);
    if ((v & 255) == 1) {
      pciwr(bdf, eecp, v | (1U << 24));
      u32 start = *X.ticks;
      for(u32 spin=0;pcird(bdf,eecp)&(1<<16);spin++){
        usb_wait_step(spin);
        if ((u32)(*X.ticks - start) > 200) {
          xs("USB: BIOS retiene EHCI.\n");
          return;
        }
      }
      if (eecp <= 0xf8)
        pciwr(bdf, eecp + 4, 0);
      break;
    }
    u32 next = (v >> 8) & 255;
    if (next == eecp)
      break;
    eecp = next;
  }
  U.op = (volatile u32 *)(base + off);
  U.bdf = bdf;
  U.ports = cap[1] & 15;
  if (!U.ports || U.ports > 15) goto fail;
  U.op[0] &= ~1U;
  if (!waitreg(U.op + 1, 1 << 12, 1 << 12, 100))
    goto fail;
  U.op[0] = 2;
  if (!waitreg(U.op, 2, 0, 100))
    goto fail;
  if (!U.dma)
    U.dma = X.alloc();
  if (!U.dma)
    goto fail;
  zero((void *)U.dma, 4096);
  U.op[2] = 0;
  U.op[4] = 0;
  U.op[6] = U.dma;
  U.op[0] = 1;
  U.op[0x40 / 4] = 1;
  for(u32 p=0;p<U.ports;p++)if(cap[1]&16){volatile u32*r=U.op+0x44/4+p;*r=(*r&~0x2aU)|(1<<12);}
  delay(10);
  for (u32 p = 0; p < U.ports; p++) {
    volatile u32 *r = U.op + 0x44 / 4 + p;
    if (!(*r & 1))
      continue;
    *r = (*r & ~(0x2aU | (1 << 13))) | (1 << 8);
    delay(6);
    *r = (*r & ~(0x2aU | (1 << 8)));
    if (!waitreg(r, 1 << 8, 0, 100))
      continue;
    delay(2);
    if (!(*r & 4)){ *r=(*r&~0x2aU)|(1<<13);continue; }
    *r=(*r&~0x2aU)|0x2aU; /* clear stale connection/enable change */
    if(!usb_enumerate(p))*r=(*r&~(0x2aU|4));
  }
  usb_keyboard_start();
  xs("USB EHCI: ");
  xn(U.count);
  xs(" disco(s) de 512 bytes detectado(s).\n");
  xs("USB HID: ");xn(U.kbd_count);xs(" teclado(s) detectado(s); ");
  xs(U.hid_active ? "lectura periodica activa.\n" : "sin entrada periodica.\n");
  xs("USB HID: ");xn(U.mouse_count);xs(" raton(es) detectado(s).\n");
  return;
fail:
  U.dead = 1;
  U.count = 0;
  zero(U.d, sizeof U.d);
  U.kbd_count = 0;
  zero(U.kbd, sizeof U.kbd);
  xs("USB: fallo de inicializacion EHCI.\n");
}
static void usb_scan(void){
  usb_cache_reset();if(usb_cache){X.free(usb_cache);usb_cache=0;}
  usb_pci_discover();
  int safe=xhci_stop(),lsafe=uhci_stop();
  if(!usb_pci_n[0])ehci_scan(65536);
  for(u32 i=0;i<usb_pci_n[0];i++){
    ehci_scan(usb_pci[0][i]);if(U.count||U.kbd_count||U.mouse_count||U.dead)break;
  }
  if(lsafe){
    for(u32 i=0;i<usb_pci_n[1]&&U.count<4;i++){
      u32 old=U.count;uhci_scan(usb_pci[1][i]);
      if(U.count>old||!uhci_stop())break;
    }
  }else xs("USB UHCI: DMA no detenido.\n");
  if(safe){
    for(u32 i=0;i<usb_pci_n[2]&&U.count<4;i++){
      u32 old=U.count;xhci_scan(usb_pci[2][i]);
      if(U.count>old||!xhci_stop())break;
    }
  }else xs("USB xHCI: DMA no detenido, reinicia.\n");
  xs("USB total: ");xn(U.count);xs(" disco(s).\n");
}
static void usb_info(void) {
  if (!U.scanned) {
    xs("Ejecuta usbscan para detectar USB EHCI/UHCI/xHCI.\n");
    return;
  }
  for (u32 i = 0; i < U.count; i++) {
    struct usbdev *d = &U.d[i];
    xs("usb");
    xn(i);
    xs(" VID/PID ");
    xhex(d->vid);
    X.out('/');
    xhex(d->pid);
    xs(" puerto ");
    xn(d->port + 1);
    xs(" sectores ");
    xn(d->cap);
    xs(d->backend==1?" xHCI":d->backend==2?" UHCI":" EHCI");
    int connected = usb_connected(d);
    xs(d->valid && connected ? " listo, solo lectura" : " desconectado/error");
    xs(" fallos="); xn(d->errors); xs("\n");
  }
  if (!U.count)
    xs("Sin discos USB compatibles.\n");
}
static void usb_kbd_info(void){
 if(!U.scanned){xs("Ejecuta usbscan para buscar teclados USB HID.\n");return;}
 for(u32 i=0;i<U.kbd_count;i++){
  struct usbkbd*k=&U.kbd[i];
  xs("Teclado HID puerto ");xn(k->port+1);
  xs(" VID/PID ");xhex(k->vid);X.out('/');xhex(k->pid);
  xs(" EP interrupt IN ");xn(k->epin);xs(" intervalo ");xn(k->interval);
  xs(U.hid_active && !i && k->valid ? "; entrada activa.\n" : "; sin entrada.\n");
 }
 if(!U.kbd_count)xs("Sin teclados HID boot en EHCI.\n");
}
