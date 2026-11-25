/* Event policy: app callbacks only receive input while visible and focused. */
static int wm_key(u32 key){
 if(key==27){
  if(desk_menu)desk_menu=0;
  else if(desk_view==4)desk_view=1;
  else if(wm_focus>=0)wm_close();
  else return -1;
 }else if(key==17)return -1; /* Ctrl-Q leaves the layout intact */
 else if(key==9){desk_menu^=1;desk_choice=0;}
 else if(key==14)wm_cycle();
 else if(key==23)wm_close();
 else if(key==13){
  if(desk_menu||wm_focus<0)wm_open(desk_choice);
  else if(desk_view==1)desk_file_open();
 }else if(key==0x80||key==0x81){int delta=key==0x80?-1:1;
  if(wm_focus>=0&&desk_view==1&&!desk_menu){
   int n=desk_count(),rows=(W[wm_focus].h-110)/25;
   if(n){desk_file=(desk_file+delta+n)%n;
    if(desk_file<desk_scroll)desk_scroll=desk_file;
    if(desk_file>=desk_scroll+rows)desk_scroll=desk_file-rows+1;
   }
  }else desk_choice=(desk_choice+delta+4)%4;
 }else if(key==8&&desk_view==1){
  if(*X.cwd!=ROOT)*X.cwd=le32(desk_record(*X.cwd)+32);
  desk_file=desk_scroll=0;
 }else if(key==25)wm_minimize(); /* Ctrl-Y */
 else if(key==18)wm_restore();
 else if(key==5)wm_maximize();
 else if(wm_focus>=0){
  struct wm_window*w=&W[wm_focus];
  if(w->maximized)return 0;
  if(key=='w'||key=='a'||key=='s'||key=='d'){
   w->x+=key=='a'?-16:key=='d'?16:0;w->y+=key=='w'?-16:key=='s'?16:0;
  }else if(key==26||key==24){int delta=key==26?16:-16;w->w+=delta;w->h+=delta;}
  else return 0;
  wm_bounds(w);
 }else return 0;
 return desk_view==-1?-1:1;
}
static int wm_mouse_click(void){
 int x=*X.mouse_x,y=*X.mouse_y;
 if(y>=548){
  if(x<140){desk_menu^=1;desk_choice=0;}
  else if(x>=150){int id=(x-150)/200;
   if(id<WM_MAX&&W[id].open){
    if(id==wm_focus&&!W[id].hidden)wm_minimize();else wm_focus_window(id);
   }
  }
 }else if(desk_menu){
  if(x>=18&&x<260&&y>=286&&y<498)wm_open((y-286)/53);else desk_menu=0;
 }else{
  int hit=-1;
  for(int j=WM_MAX-1;j>=0;j--){int id=wm_order[j];struct wm_window*w=&W[id];
   if(w->open&&!w->hidden&&x>=w->x&&x<w->x+w->w&&y>=w->y&&y<w->y+w->h){hit=id;break;}
  }
  if(hit>=0){
   wm_focus_window(hit);struct wm_window*w=&W[hit];int rx=x-w->x,ry=y-w->y;
   if(ry<46&&rx>=w->w-45)wm_close();
   else if(ry<46&&rx>=w->w-91)wm_maximize();
   else if(ry<46&&rx>=w->w-137)wm_minimize();
   else if(!w->maximized&&(ry<46||(rx>=w->w-20&&ry>=w->h-20))){
    wm_drag=hit;wm_resizing=ry>=46;
    wm_grabx=wm_resizing?x-w->w:rx;wm_graby=wm_resizing?y-w->h:ry;
   }else if(desk_view==1&&rx>=20&&rx<w->w-20&&ry>=86&&ry<w->h-24){
    desk_file=desk_scroll+(ry-86)/25;desk_file_open();
   }
  }else if(x>=40&&x<280&&y>=122&&y<409&&(y-122)%75<62)wm_open((y-122)/75);
 }
 return desk_view==-1?-1:1;
}
static int wm_mouse_motion(void){
 if(wm_drag<0)return 0;
 if(!(*X.mouse_buttons&1)){wm_drag=-1;return 0;}
 struct wm_window*w=&W[wm_drag];
 int x=*X.mouse_x,y=*X.mouse_y;
 if(wm_resizing){
  w->w=x-wm_grabx;w->h=y-wm_graby;
  if(w->w>960-w->x)w->w=960-w->x;
  if(w->h>548-w->y)w->h=548-w->y;
 }else{w->x=x-wm_grabx;w->y=y-wm_graby;}
 wm_bounds(w);return 1;
}
static int desktop_run(void){
 if(!gfx_available()){xs("desktop requiere framebuffer RGB32.\n");return 1;}
 desk_x=(*X.fb_width-960)/2;desk_y=(*X.fb_height-600)/2+10;
 wm_init();wm_drag=-1;desk_menu=0;
 /* The shell may remove a folder or preview file while the WM is away. */
 for(int i=0;i<WM_MAX;i++){
  struct wm_window*w=&W[i];
  if(w->cwd!=ROOT&&(w->cwd>=480||le32(desk_record(w->cwd)+36)!=2)){
   w->cwd=ROOT;w->file=w->scroll=0;
  }
  if(w->view==4&&(w->preview<0||w->preview>=480||
      le32(desk_record(w->preview)+36)!=1))w->view=1;
 }
 wm_load(wm_focus);
 *X.mouse_gui=1;*X.mouse_click=*X.mouse_event=0;
 wm_paint();
 for(;;){
  u32 key=X.key();int changed;
  if(key==0x89)changed=wm_mouse_click();
  else if(key==0x8a)changed=wm_mouse_motion();
  else changed=wm_key(key);
  if(changed<0)break;
  if(changed)wm_paint();else if(key==0x8a)wm_cursor_update(0);
 }
 /* Terminal is an exit action, never store its sentinel in window state. */
 if(desk_view==-1&&wm_focus>=0)desk_view=W[wm_focus].view;
 wm_save();*X.mouse_gui=0;wm_cursor_valid=0;X.repaint();return 1;
}
