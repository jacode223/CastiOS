/* Experimental xHCI root-port BOT backend. Clean-room implementation based on
 * Intel xHCI 1.2, sections 4.6, 4.9, 6.2, 6.4. No hub/UAS support yet. */
struct xring {u32 base; u16 pos; u8 cycle;};
struct xslot {
  u32 ctx, port;
  u8 id, speed, in_ep, out_ep;
  struct xring ctrl, in, out;
};
static struct {
  volatile u32 *op, *db, *ir;
  u32 bdf, dcbaa, input, buf, events, erst;
  u32 pages[90]; u8 np, used, slots, stride, ports, dead, cycle, ac64;
  u16 event;
  struct xring cmd;
  struct xslot dev[4];
} H;
static u32 xpage(void){
  if(H.used>=sizeof H.pages/sizeof H.pages[0])return 0;
  if(H.used==H.np){u32 p=X.alloc();if(!p)return 0;H.pages[H.np++]=p;}
  u32 p=H.pages[H.used++];zero((void*)p,4096);return p;
}
static void xptr(volatile u32 *p,u32 v){p[0]=v;if(H.ac64)p[1]=0;}
static void xring_init(struct xring *r,u32 p){r->base=p;r->pos=0;r->cycle=1;}
/* 64 entries per ring, last is a cycle-toggling Link TRB. */
static u32 xtrb(struct xring*r,u32 a,u32 b,u32 c,u32 d){
  u32 addr=r->base+16*r->pos;volatile u32*p=(volatile u32*)addr;
  p[0]=a;p[1]=b;p[2]=c;
  if(r->pos==62){volatile u32*l=(volatile u32*)(r->base+63*16);l[0]=r->base;l[1]=l[2]=0;
    barrier();l[3]=(6<<10)|2|r->cycle|(d&16);}
  barrier();p[3]=d|r->cycle;barrier();
  if(++r->pos==63){r->pos=0;r->cycle^=1;}
  return addr;
}
/* Consume unrelated port events too; never reuse DMA after a timed-out TD. */
static int xevent(u32 type,u32 slot,u32 ep,u32 ptr,u32 *res,u32 *evslot){
  u32 start=*X.ticks, short_rem=0;
  for(u32 n=0;n<30000000;n++){
    volatile u32 *p=(volatile u32*)(H.events+16*H.event);
    u32 ctl=p[3];
    if((ctl&1)==H.cycle){
      barrier();u32 a=p[0],b=p[1],s=p[2];
      if(++H.event==256){H.event=0;H.cycle^=1;}
      xptr(H.ir+6,(H.events+16*H.event)|8);
      if(type==32&&ep==1&&((ctl>>10)&63)==32&&(ctl>>24)==slot&&((ctl>>16)&31)==1&&(s>>24)==13&&a!=ptr)short_rem=s&0xffffff;
      if(((ctl>>10)&63)==type && (!slot || (ctl>>24)==slot) &&
         (!ep || ((ctl>>16)&31)==ep) && !b && (a==ptr||(type==32&&(s>>24)!=1&&(s>>24)!=13))){
        if(res)*res=short_rem?short_rem:s&0xffffff;
        if(evslot)*evslot=ctl>>24;
        return s>>24;
      }
    }
    if((u32)(*X.ticks-start)>=200)break;
    usb_wait_step(n);
  }
  H.dead=1;return -1;
}
static int xcmd(u32 type,u32 addr,u32 slot,u32 extra,u32 *returned){
  if(H.dead)return 0;
  u32 p=xtrb(&H.cmd,addr,0,0,(type<<10)|(slot<<24)|extra);
  barrier();H.db[0]=0;
  return xevent(33,0,0,p,0,returned)==1;
}
static volatile u32 *xport(u32 p){return H.op+0x100+p*4;}
static int xconnected(struct xslot*s){return H.op&&!H.dead&&(*xport(s->port)&1)&&(*xport(s->port)&2)&&!(*xport(s->port)&(1<<17));}
static u32 *xctx(u32 dci){return (u32*)(H.input+(dci+1)*H.stride);}
static void xep(u32 dci,u32 type,u32 mps,u32 burst,struct xring*r){
  u32*p=xctx(dci);p[1]=(3<<1)|(type<<3)|(burst<<8)|(mps<<16);
  p[2]=r->base|1;p[4]=type==4?8:mps;
}
static int xcontrol(struct xslot*s,u8 type,u8 req,u16 val,u16 idx,void*data,u16 n){
  if(!xconnected(s)||n>3072)return -1;
  int in=!!(type&128);u32 trt=n?(in?3:2):0;
  if(n&&!in)memcopy((void*)H.buf,data,n);
  if(n&&in)zero((void*)H.buf,n);
  xtrb(&s->ctrl,type|((u32)req<<8)|((u32)val<<16),idx|((u32)n<<16),8,(2<<10)|64|(trt<<16));
  if(n)xtrb(&s->ctrl,H.buf,0,n,(3<<10)|(in?1<<16:0)|(in?4:0));
  u32 p=xtrb(&s->ctrl,0,0,0,(4<<10)|32|((!n||!in)?1<<16:0));
  barrier();H.db[s->id]=1;
  u32 rem=0;int rc=xevent(32,s->id,1,p,&rem,0);
  if(rc!=1||rem>n){H.dead=1;return -1;}
  if(n&&in)memcopy(data,(void*)H.buf,n-rem);
  return n-rem;
}
static int xbulk(struct usbdev*d,int in,void*data,u32 n){
  struct xslot*s=&H.dev[d->hostindex];
  if(!xconnected(s)||n>3072)return -1;
  struct xring*r=in?&s->in:&s->out;u32 ep=in?s->in_ep:s->out_ep;
  if(!in)memcopy((void*)H.buf,data,n);
  u32 p=xtrb(r,H.buf,0,n,(1<<10)|32|4);
  barrier();H.db[s->id]=ep;
  u32 rem=0;int rc=xevent(32,s->id,ep,p,&rem,0);
  if((rc!=1&&rc!=13)||rem>n){H.dead=1;return -1;}
  if(in)memcopy(data,(void*)H.buf,n-rem);
  return n-rem;
}
static int xhci_stop(void){
  if(H.op){
    if(pcird(H.bdf,0)==0xffffffffU){H.op=0;return 0;}
    H.op[0]&=~1U;
    if(!waitreg(H.op+1,1,1,100))return 0;
  }
  H.op=0;H.dead=1;
  for(u32 i=0;i<H.np;i++)X.free(H.pages[i]);
  H.np=H.used=0;return 1;
}
static int xhci_start(u32 bdf){
  u32 bar=pcird(bdf,16),base=bar&~15U;
  if((bar&1)||((bar&6)==4&&pcird(bdf,20))||!base||base<0x2000000||base>0xffff0000)return 0;
  if(X.map(base)||X.map(base+0xffff))return 0;
  pcienable(bdf);volatile u32*cap=(volatile u32*)base;
  u32 off=cap[0]&255,db=cap[5]&~3U,rt=cap[6]&~31U;
  if(off<0x20||db>0xff00||rt>0xff00)return 0;
  u32 ext=(cap[4]>>16)*4;
  for(u32 n=0;ext>=0x20&&ext<0xff00&&n<64;n++){
    volatile u32*p=(volatile u32*)(base+ext);u32 v=*p;
    if((v&255)==1){*p=v|(1U<<24);if(!waitreg(p,1<<16,0,200))return 0;p[1]=0;}
    if(!((v>>8)&255))break;
    ext+=((v>>8)&255)*4;
  }
  H.op=(volatile u32*)(base+off);H.db=(volatile u32*)(base+db);
  H.ir=(volatile u32*)(base+rt+0x20);H.bdf=bdf;
  H.dead=1;H.used=0;H.event=0;H.cycle=1;
  H.op[0]&=~1U;if(!waitreg(H.op+1,1,1,100))return 0;
  H.op[0]=2;if(!waitreg(H.op,2,0,100)||!waitreg(H.op+1,1<<11,0,100))return 0;
  if(!(H.op[2]&1))return 0;
  H.ac64=cap[4]&1;H.stride=(cap[4]&4)?64:32;H.ports=cap[1]>>24;H.slots=cap[1]&255;
  if(H.slots>4)H.slots=4;
  if(!H.slots||!H.ports)return 0;
  H.dcbaa=xpage();H.input=xpage();H.buf=xpage();H.events=xpage();H.erst=xpage();
  u32 cr=xpage();if(!H.dcbaa||!H.input||!H.buf||!H.events||!H.erst||!cr)return 0;
  u32 scratch=((cap[2]>>27)&31)|(((cap[2]>>21)&31)<<5);
  if(scratch){
    if(scratch>64)return 0;
    u32 arr=xpage();if(!arr)return 0;*(u32*)H.dcbaa=arr;
    for(u32 i=0;i<scratch;i++){u32 p=xpage();if(!p)return 0;((u32*)arr)[i*2]=p;}
  }
  zero(H.dev,sizeof H.dev);xring_init(&H.cmd,cr);
  ((u32*)H.erst)[0]=H.events;((u32*)H.erst)[2]=256;
  H.op[14]=H.slots;xptr(H.op+12,H.dcbaa);xptr(H.op+6,cr|1);
  H.ir[2]=1;xptr(H.ir+4,H.erst);xptr(H.ir+6,H.events);H.ir[0]=1;
  barrier();H.op[0]=1;if(!waitreg(H.op+1,1,0,100))return 0;
  H.dead=0;return 1;
}
static int xaddress(struct xslot*s,u32 port,u32 slot_type){
  u32 id=0;u32 rings=xpage();s->ctx=xpage();if(!rings||!s->ctx)return 0;
  if(!xcmd(9,0,0,slot_type<<16,&id)||!id||id>H.slots)return 0;
  s->id=id;s->port=port;s->speed=(*xport(port)>>10)&15;
  if(s->speed<1||s->speed>4)return 0;
  xring_init(&s->ctrl,rings);xring_init(&s->in,rings+1024);xring_init(&s->out,rings+2048);
  ((u32*)H.dcbaa)[id*2]=s->ctx;
  zero((void*)H.input,4096);((u32*)H.input)[1]=3;
  u32*p=xctx(0);p[0]=((u32)s->speed<<20)|(1U<<27);p[1]=(port+1)<<16;
  xep(1,4,s->speed==4?512:s->speed==3?64:8,0,&s->ctrl);
  return xcmd(11,H.input,id,0,0);
}
static int xconfigure(struct xslot*s,struct usbdev*d,u32 bi,u32 bo){
  s->in_ep=d->epin*2+1;s->out_ep=d->epout*2;
  u32 max=s->in_ep>s->out_ep?s->in_ep:s->out_ep;
  zero((void*)H.input,4096);((u32*)H.input)[1]=1U|(1U<<s->in_ep)|(1U<<s->out_ep);
  u32*p=xctx(0);memcopy(p,(void*)s->ctx,H.stride);p[0]=(p[0]&0x07ffffff)|(max<<27);p[3]=0;
  xep(s->in_ep,6,d->mpsin,bi,&s->in);xep(s->out_ep,2,d->mpsout,bo,&s->out);
  return xcmd(12,H.input,s->id,0,0);
}
