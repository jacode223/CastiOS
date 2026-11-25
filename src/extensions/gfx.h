/* Kernel-side, validated primitives only. The parser lives at CPL3. */
struct gfx_draw {u32 op,x,y,w,h,color;char text[129];};
static int gfx_available(void){return *X.framebuffer && *X.fb_width>=1024 && *X.fb_height>=768 && *X.fb_pitch>=*X.fb_width*4;}
static int gfx_rect(u32 x,u32 y,u32 w,u32 h,u32 rgb){
 if(!gfx_available()||x>=*X.fb_width||y>=*X.fb_height||!w||!h||w>*X.fb_width-x||h>*X.fb_height-y||w>4096||h>2160)return 0;
 for(u32 row=0;row<h;row++){volatile u32*p=(volatile u32*)(*X.fb_address+(y+row)*(*X.fb_pitch)+4*x);for(u32 col=0;col<w;col++)p[col]=rgb&0xffffff;}
 return 1;
}
static int gfx_text(u32 x,u32 y,const char*s,u32 rgb){
 if(!gfx_available()||x>=*X.fb_width||y>=*X.fb_height)return 0;
 u32 count=0;
 while(count<129 && s[count])count++;
 if(count>128 || count>(*X.fb_width-x)/8 || 16>*X.fb_height-y)return 0;
 for(u32 i=0;i<count;i++){
  u32 at=x+i*8;
  const u8*g=X.font+((u8)s[i])*16;
  for(u32 row=0;row<16;row++)for(u32 col=0;col<8;col++)if(g[row]&(0x80>>col))*(volatile u32*)(*X.fb_address+(y+row)*(*X.fb_pitch)+4*(at+col))=rgb&0xffffff;
 }return 1;
}
static int services_draw(const struct gfx_draw*d){
 if(d->op==12)return gfx_rect(d->x,d->y,d->w,d->h,d->color);
 if(d->op==13)return gfx_text(d->x,d->y,d->text,d->color);
 return 0;
}
