/* Window lifecycle, focus and geometry; no framebuffer access here. */
static void wm_save(void){
 if(wm_focus>=0){struct wm_window*w=&W[wm_focus];
  w->cwd=*X.cwd;w->file=desk_file;w->scroll=desk_scroll;
  w->preview=desk_preview;w->view=desk_view;
 }
}
static void wm_load(int id){
 wm_focus=id;
 if(id<0){desk_view=0;return;}
 struct wm_window*w=&W[id];
 *X.cwd=w->cwd;desk_file=w->file;desk_scroll=w->scroll;
 desk_preview=w->preview;desk_view=w->view;
}
static void wm_focus_window(int id){
 wm_save();int at=0;
 while(at<WM_MAX&&wm_order[at]!=id)at++;
 if(at==WM_MAX)return;
 for(int j=at;j<WM_MAX-1;j++)wm_order[j]=wm_order[j+1];
 wm_order[WM_MAX-1]=id;W[id].hidden=0;wm_load(id);
}
static void wm_pick_focus(void){
 wm_load(-1);
 for(int j=WM_MAX-1;j>=0;j--){int id=wm_order[j];
  if(W[id].open&&!W[id].hidden){wm_load(id);return;}
 }
}
static void wm_bounds(struct wm_window*w){
 if(w->w<WM_MIN_W)w->w=WM_MIN_W;
 if(w->w>960)w->w=960;
 if(w->h<WM_MIN_H)w->h=WM_MIN_H;
 if(w->h>484)w->h=484;
 if(w->x<0)w->x=0;
 if(w->x>960-w->w)w->x=960-w->w;
 if(w->y<64)w->y=64;
 if(w->y>548-w->h)w->y=548-w->h;
}
static void wm_open(int app){
 if(!app){desk_view=-1;return;}
 int id=app-1;struct wm_window*w=&W[id];
 if(!w->open){w->open=1;w->cwd=*X.cwd;w->view=app;w->file=w->scroll=0;}
 wm_focus_window(id);desk_menu=0;
}
static void wm_close(void){
 if(wm_focus<0)return;
 wm_save();W[wm_focus].open=W[wm_focus].hidden=0;
 wm_drag=-1;wm_pick_focus();
}
static void wm_minimize(void){
 if(wm_focus<0)return;
 wm_save();W[wm_focus].hidden=1;wm_drag=-1;wm_pick_focus();
}
static void wm_restore(void){
 for(int j=WM_MAX-1;j>=0;j--){int id=wm_order[j];
  if(W[id].open&&W[id].hidden){wm_focus_window(id);return;}
 }
}
static void wm_maximize(void){
 if(wm_focus<0)return;
 struct wm_window*w=&W[wm_focus];
 if(w->maximized){w->x=w->rx;w->y=w->ry;w->w=w->rw;w->h=w->rh;}
 else{w->rx=w->x;w->ry=w->y;w->rw=w->w;w->rh=w->h;
  w->x=0;w->y=64;w->w=960;w->h=484;
 }
 w->maximized^=1;wm_bounds(w);wm_drag=-1;
}
static void wm_cycle(void){
 for(int j=0;j<WM_MAX;j++){int id=wm_order[j];
  if(W[id].open&&!W[id].hidden){wm_focus_window(id);return;}
 }
}
static void wm_init(void){
 if(wm_initialized)return;
 zero(W,sizeof W);
 for(int i=0;i<WM_MAX;i++){
  wm_order[i]=i;W[i].x=290-i*65;W[i].y=95+i*12;
  W[i].w=WM_MIN_W;W[i].h=WM_MIN_H;wm_bounds(&W[i]);
 }
 wm_initialized=1;
}
