/* Kernel services ABI, shared by FAT32, TrueType and EHCI. */
struct ext_api {
  void (*out)(u32);
  int (*read)(u32, u32, void *);
  u32 *caps;
  u32 (*alloc)(void);
  int (*map)(u32);
  volatile u32 *ticks;
  u8 *font;
  void (*repaint)(void);
  u32 *cwd;
  u8 *framebuffer;
  u32 (*key)(void);
  void (*clear)(void);
  volatile u32 *fb_address, *fb_pitch, *fb_width, *fb_height;
  int (*free)(u32);
  u8 *persistent_fs;
  int (*write_sector)(u32,u32,const void*);
  int (*flush_disk)(void);
  u32 *selected_disk, *volume_base;
  void *reserved_language_slot;
  void (*key_emit)(u32);
  u8 *mouse_gui;
  u32 *mouse_x, *mouse_y, *process_count;
  u8 *process_active;
  u8 *mouse_click, *mouse_event;
  const u8 *process_table;
  u8 *mouse_buttons;
};
static struct ext_api X;
static void xs(const char *s) {
  while (*s)
    X.out((u8)*s++);
}
static void xn(u32 x) {
  char b[11];
  int n = 0;
  do {
    b[n++] = (char)('0' + x % 10);
    x /= 10;
  } while (x);
  while (n)
    X.out(b[--n]);
}
static void xhex(u32 n) {
  for (int i = 28; i >= 0; i -= 4)
    X.out("0123456789abcdef"[(n >> i) & 15]);
}
static u16 le16(const void *p) {
  const u8 *b = p;
  return b[0] | b[1] << 8;
}
static u32 le32(const void *p) {
  const u8 *b = p;
  return b[0] | b[1] << 8 | b[2] << 16 | (u32)b[3] << 24;
}
static u16 be16(const void *p) {
  const u8 *b = p;
  return b[1] | b[0] << 8;
}
static u32 be32(const void *p) {
  const u8 *b = p;
  return b[3] | b[2] << 8 | b[1] << 16 | (u32)b[0] << 24;
}
static void st32(void *p, u32 v) {
  u8 *b = p;
  for (int i = 0; i < 4; i++)
    b[i] = (u8)(v >> (8 * i));
}
static void bput32(u8 *p, u32 v) {
  p[0] = v >> 24;
  p[1] = v >> 16;
  p[2] = v >> 8;
  p[3] = v;
}
static int xequal(const char *a, const char *b) {
  while (*a && *b) {
    u8 x = *a++, y = *b++;
    if (x >= 'A' && x <= 'Z')
      x += 32;
    if (y >= 'A' && y <= 'Z')
      y += 32;
    if (x != y)
      return 0;
  }
  return !*a && !*b;
}
static int xcopy(char *d, const char *s, u32 cap) {
  u32 n = 0;
  while (*s) {
    if (n + 1 >= cap)
      return 0;
    d[n++] = *s++;
  }
  d[n] = 0;
  return 1;
}
static int xprefix(const char *s, const char *p) {
  while (*p)
    if (*s++ != *p++)
      return 0;
  return 1;
}
static int xerr(const char *s) {
  xs("Error: ");
  xs(s);
  xs("\n");
  return 1;
}
static u32 pcird(u32 bdf, u32 off) {
  u32 v = (bdf << 8) | 0x80000000 | off;
  __asm__ volatile("outl %0,%w1" ::"a"(v), "d"((u16)0xcf8));
  __asm__ volatile("inl %w1,%0" : "=a"(v) : "d"((u16)0xcfc));
  return v;
}
static void pciwr(u32 bdf, u32 off, u32 v) {
  u32 a = (bdf << 8) | 0x80000000 | off;
  __asm__ volatile("outl %0,%w1" ::"a"(a), "d"((u16)0xcf8));
  __asm__ volatile("outl %0,%w1" ::"a"(v), "d"((u16)0xcfc));
}
static void pcienable(u32 bdf) {
  u32 a = (bdf << 8) | 0x80000004;
  u16 v;
  __asm__ volatile("outl %0,%w1" ::"a"(a), "d"((u16)0xcf8));
  __asm__ volatile("inw %w1,%0" : "=a"(v) : "d"((u16)0xcfc));
  v |= 6;
  __asm__ volatile("outw %0,%w1" ::"a"(v), "d"((u16)0xcfc));
}
static void barrier(void) { __asm__ volatile("" ::: "memory"); }
/* Poll briefly for fast MMIO completions, then sleep until the next PIT IRQ.
 * Do not HLT with interrupts disabled (e.g. recovery paths). */
static void usb_wait_step(u32 n){
  u32 flags;__asm__ volatile("pushfl; popl %0":"=r"(flags));
  if(n>=2048 && (flags&0x200))__asm__ volatile("hlt":::"memory");
  else __asm__ volatile("pause");
}
static int waitreg(volatile u32 *p, u32 mask, u32 value, u32 ticks) {
  u32 start = *X.ticks;
  for (u32 n = 0; n < 30000000; n++) {
    if ((*p & mask) == value)
      return 1;
    if ((u32)(*X.ticks - start) >= ticks)
      break;
    usb_wait_step(n);
  }
  return 0;
}
static void delay(u32 ticks) {
  u32 t = *X.ticks;
  for (u32 n = 0; n < 30000000 && (u32)(*X.ticks - t) < ticks; n++)
    usb_wait_step(n);
}
#define BLOB ((u8 *)0x08000000)
#define BLOB_MAX 1048576U
