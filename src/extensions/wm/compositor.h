/* Composition plus a 672-byte cursor backing store. Mouse-only motion
 * restores just the old cursor rectangle rather than repainting the screen. */
static u32 wm_cursor_back[12*14];
static int wm_cursor_valid,wm_cursor_x,wm_cursor_y;
static void wm_cursor_update(int full){
 if(full)wm_cursor_valid=0;
 if(wm_cursor_valid){
  for(u32 row=0;row<14;row++){
   volatile u32*p=(volatile u32*)(*X.fb_address+(desk_y+wm_cursor_y+row)*(*X.fb_pitch)+4*(desk_x+wm_cursor_x));
   for(u32 col=0;col<12;col++)p[col]=wm_cursor_back[row*12+col];
  }
 }
 u32 x=*X.mouse_x,y=*X.mouse_y;
 wm_cursor_valid=x<948&&y<580;
 if(!wm_cursor_valid)return;
 wm_cursor_x=x;wm_cursor_y=y;
 for(u32 row=0;row<14;row++){
  volatile u32*p=(volatile u32*)(*X.fb_address+(desk_y+y+row)*(*X.fb_pitch)+4*(desk_x+x));
  for(u32 col=0;col<12;col++)wm_cursor_back[row*12+col]=p[col];
 }
 desk_cursor(x,y);
}
static void wm_paint(void){
 wm_save();u32 cwd=*X.cwd;int view=desk_view;
 wm_dx=wm_dy=0;gfx_rect(0,0,*X.fb_width,*X.fb_height,WM_COLOR_OUTSIDE);
 desk_box(0,0,960,600,WM_COLOR_BACKGROUND);
 desk_box(0,0,960,68,WM_COLOR_HEADER);
 desk_box(0,68,960,3,WM_COLOR_ACCENT);
 desk_text(20,16,"CastiOS | Escritorio",0xffffff);
 desk_text(20,42,"Tab Inicio | ^N foco | ^Y minimizar | ^R restaurar | ^E maximizar | ^Q salir",0xc5e8f4);
 for(int i=0;i<4;i++){
  desk_box(40,122+i*75,240,62,desk_choice==i?WM_COLOR_ACCENT:WM_COLOR_TILE);
  desk_box(40,122+i*75,5,62,WM_COLOR_ACCENT);
  desk_text(60,143+i*75,desk_names[i],0xffffff);
 }
 for(int j=0;j<WM_MAX;j++){
  int id=wm_order[j];struct wm_window*w=&W[id];
  if(!w->open||w->hidden)continue;
  wm_dx=w->x-290;wm_dy=w->y-95;desk_view=w->view;desk_file=w->file;
  desk_scroll=w->scroll;desk_preview=w->preview;*X.cwd=w->cwd;
  wm_rows=(w->h-110)/25;
  desk_box(290,95,w->w,w->h,0x0c1727);
  desk_box(294,99,w->w-8,w->h-8,WM_COLOR_WINDOW);
  desk_box(294,99,w->w-8,42,id==wm_focus?WM_COLOR_TITLE:WM_COLOR_MUTED);
  desk_text(313,112,desk_view==4?"Archivo":desk_names[id+1],0xffffff);
  u32 right=290+w->w;
  desk_box(right-137,104,38,30,WM_COLOR_BUTTON);desk_text(right-124,111,"_",0xffffff);
  desk_box(right-91,104,38,30,WM_COLOR_BUTTON);desk_text(right-78,111,w->maximized?"o":"+",0xffffff);
  desk_box(right-45,104,34,30,WM_COLOR_CLOSE);desk_text(right-33,111,"X",0xffffff);
  wm_app_paint();
  if(!w->maximized)desk_box(right-14,95+w->h-14,10,10,WM_COLOR_MUTED);
 }
 wm_dx=wm_dy=0;desk_view=view;*X.cwd=cwd;
 if(wm_focus>=0){desk_file=W[wm_focus].file;desk_scroll=W[wm_focus].scroll;desk_preview=W[wm_focus].preview;}
 desk_box(0,548,960,52,WM_COLOR_TASKBAR);desk_box(12,555,122,38,WM_COLOR_BUTTON);desk_text(29,566,"Inicio",0xffffff);
 for(int i=0;i<WM_MAX;i++)if(W[i].open){
  desk_box(150+i*200,555,190,38,i==wm_focus?WM_COLOR_ACCENT:W[i].hidden?0x1b3548:WM_COLOR_TILE);
  desk_text(160+i*200,566,desk_names[i+1],0xffffff);
  if(W[i].hidden)desk_text(320+i*200,566,"_",0xffffff);
 }
 if(desk_menu){desk_box(12,272,255,270,0x112538);
  for(int j=0;j<4;j++){
   if(j==desk_choice)desk_box(18,286+j*53,242,40,0x2b759f);
   desk_text(34,291+j*53,desk_names[j],0xffffff);
  }
 }
 wm_cursor_update(1);
}
