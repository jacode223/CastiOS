/* Runtime desktop palette, loaded only after validation of a NASM flat file. */
#ifndef CASTIOS_WM_THEME_H
#define CASTIOS_WM_THEME_H
static u32 wm_colors[11] = {0x0b1628, 0x172f47, 0x102539, 0x297eb0, 0x24536d, 0x2976a4, 0x52677b, 0xe5ebf2, 0x12283d, 0x286282, 0xb5424c};
#define WM_COLOR_OUTSIDE wm_colors[0]
#define WM_COLOR_BACKGROUND wm_colors[1]
#define WM_COLOR_HEADER wm_colors[2]
#define WM_COLOR_ACCENT wm_colors[3]
#define WM_COLOR_TILE wm_colors[4]
#define WM_COLOR_TITLE wm_colors[5]
#define WM_COLOR_MUTED wm_colors[6]
#define WM_COLOR_WINDOW wm_colors[7]
#define WM_COLOR_TASKBAR wm_colors[8]
#define WM_COLOR_BUTTON wm_colors[9]
#define WM_COLOR_CLOSE wm_colors[10]
#endif
