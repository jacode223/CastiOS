/* Shared WM state. Layout survives desktop exit during this boot session. */
#define WM_MAX 3
#define WM_MIN_W 630
#define WM_MIN_H 430
struct wm_window {
 int open,hidden,maximized,x,y,w,h,rx,ry,rw,rh;
 u32 cwd;
 int file,scroll,preview,view;
};
static struct wm_window W[WM_MAX];
static int wm_order[WM_MAX],wm_focus=-1,wm_dx,wm_dy,wm_drag=-1;
static int wm_grabx,wm_graby,wm_resizing,wm_initialized,wm_rows=12;
static u32 desk_x,desk_y;
static int desk_view,desk_menu,desk_choice,desk_file,desk_scroll,desk_preview;
static const char *desk_names[]={"Terminal","Archivos","Procesos","Sistema"};
static void desk_box(u32 x,u32 y,u32 w,u32 h,u32 c){gfx_rect(desk_x+x+wm_dx,desk_y+y+wm_dy,w,h,c);}
static void desk_text(u32 x,u32 y,const char*s,u32 c){gfx_text(desk_x+x+wm_dx,desk_y+y+wm_dy,s,c);}
