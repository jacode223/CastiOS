// clang-format off: dependency order is intentional.
#include "base.h"
#include "usb_hid.h"
#include "usb_ehci.h"
#include "fat32.h"
#include "rmfs.h"
#include "truetype.h"
#include "gfx.h"
#include "hsfs_large.h"
#include "pe32.h"
#include "desktop.h"
// clang-format on
static int work_ready;
static int arg_overflow;
static u32 pe_printed;
static void pe_show_import(void *ctx,const char *dll,const char *name){
 (void)ctx;
 if(pe_printed++>=24)return;
 xs("  ");xs(dll);xs("! ");xs(name);xs("\n");
}
static int asfs_load(const char *path, u8 *out, u32 limit) {
  u8 *base = (u8 *)0x200000;
  u32 dir = *path == '/' ? ROOT : *X.cwd;
  const char *s = path;
  int index = -1;
  while (*s) {
    while (*s == '/')
      s++;
    if (!*s)
      break;
    char name[32];
    u32 n = 0;
    while (*s && *s != '/') {
      if (n == 31) {
        ferror = "nombre ASFS largo";
        return -1;
      }
      name[n++] = *s++;
    }
    name[n] = 0;
    if (eq(name, "."))
      continue;
    if (eq(name, "..")) {
      if (dir != ROOT)
        dir = le32(base + 512 + dir * REC + 32);
      continue;
    }
    index = -1;
    for (u32 i = 0; i < COUNT; i++) {
      u8 *r = base + 512 + i * REC;
      if (*r && le32(r + 36) != 4 && le32(r + 32) == dir &&
          eq((char *)r, name)) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      ferror = "archivo ASFS no encontrado";
      return -1;
    }
    while (*s == '/')
      s++;
    if (*s) {
      u8 *r = base + 512 + index * REC;
      if (le32(r + 36) != 2) {
        ferror = "no es carpeta ASFS";
        return -1;
      }
      dir = index;
      index = -1;
    }
  }
  if (index < 0) {
    ferror = "se requiere archivo";
    return -1;
  }
  u8 *r = base + 512 + index * REC;
  if (le32(r + 36) == 2) {
    ferror = "es carpeta";
    return -1;
  }
  u32 left = le32(r + 40), total = left, pos = 0;
  if (left > limit) {
    ferror = "archivo supera 1 MiB";
    return -1;
  }
  u8 seen[COUNT];
  zero(seen, COUNT);
  u32 head = index;
  while (left) {
    if (index < 0 || index >= COUNT || seen[index]++) {
      ferror = "cadena ASFS invalida";
      return -1;
    }
    r = base + 512 + index * REC;
    if ((u32)index != head && (le32(r + 36) != 4 || le32(r + 32) != head)) {
      ferror = "extent ASFS invalido";
      return -1;
    }
    u32 take = left > LIMIT ? LIMIT : left;
    memcopy(out + pos, r + 64, take);
    pos += take;
    left -= take;
    if (left) {
      u32 next = le32(r + 44);
      if (!next || next > COUNT) {
        ferror = "cadena ASFS truncada";
        return -1;
      }
      index = next - 1;
    }
  }
  return (int)total;
}
static int path_load(const char *input, u8 *out, u32 limit) {
  char p[256];
  const char *relative;
  ferror = "ruta invalida";
  if (normalize(input, p) && xprefix(p, "/mnt/")) {
    struct fatvol *v = volume(p, &relative);
    struct fatent e;
    if (!v) {
      ferror = "volumen no montado";
      return -1;
    }
    if (!lookup(v, relative, &e))
      return -1;
    return fat_file(v, &e, out, limit, 0);
  }
  char ram_path[256];
  if (normalize(input,ram_path) && (xprefix(ram_path,"/ram/") || eq(ram_path,"/ram"))) return rm_load(ram_path,out,limit);
  return asfs_load(input, out, limit);
}
static const char *argword(const char *s, char *out, u32 cap) {
  while (*s == ' ')
    s++;
  u32 n = 0;
  while (*s && *s != ' ') {
    if (n + 1 < cap)
      out[n++] = *s;
    else
      arg_overflow = 1;
    s++;
  }
  out[n] = 0;
  while (*s == ' ')
    s++;
  return s;
}
static int services_cmd(const char *cmd, char *args) {
  ferror = "error";
  usb_cache_reset();fat_cached_valid=0;
  if (eq(cmd, "desktop")) return desktop_run();
  arg_overflow = 0;
  if (eq(cmd,"wmtheme")) {
    char path[256]; const char *tail=argword(args,path,sizeof path);
    u8 data[48]; u32 colors[11];
    if(arg_overflow || !*path || *tail) return xerr("uso: castctl wmtheme ARCHIVO.bin");
    int n=path_load(path,data,sizeof data);
    if(n!=48 || data[0]!='C' || data[1]!='T' || data[2]!='H' || data[3]!='1')
      return xerr("tema invalido: se esperaba CTH1 y 11 colores RGB");
    for(u32 i=0;i<11;i++) {
      colors[i]=le32(data+4+i*4);
      if(colors[i]>0xffffff) return xerr("color invalido; usa 0xRRGGBB");
    }
    for(u32 i=0;i<11;i++) wm_colors[i]=colors[i];
    xs("Tema cargado. Ejecuta desktop para verlo.\n"); return 1;
  }
  if(eq(cmd,"peinfo")){
    char path[256];const char *tail=argword(args,path,sizeof path);
    if(arg_overflow||!*path||*tail)return xerr("uso: peinfo RUTA.exe");
    if(!work_ready)return xerr("peinfo requiere perfil completo (200 MiB)");
    int n=path_load(path,BLOB,BLOB_MAX);
    if(n<0)return xerr(ferror);
    struct pe_image info;pe_printed=0;
    int result=pe_parse(BLOB,(u32)n,&info,0,0);
    if(result<0)return xerr(pe_error(result));
    xs("PE32 x86: base 0x");xhex(info.image_base);
    xs(" entrada RVA 0x");xhex(info.entry);
    xs(" imagen ");xn(info.image_size);xs(" bytes\nSecciones ");
    xn(info.section_count);xs(" | DLL importadas ");xn(info.import_count);
    xs(" | subsistema ");xn(info.subsystem);xs("\n");
    xs("Recursos: ");
    if(info.resource_size){xn(info.resource_types);xs(" tipos en directorio raiz; ");xn(info.resource_size);xs(" bytes\n");}
    else xs("sin directorio declarado\n");
    if(info.import_count){
      pe_parse(BLOB,(u32)n,&info,pe_show_import,0);
      if(pe_printed>24)xs("  ... importaciones adicionales omitidas\n");
    }
    xs("Inspeccion solamente: el cargador Win32 aun no ejecuta EXE.\n");
    return 1;
  }
  if(eq(cmd,"raminfo"))return rm_info();
  if (eq(cmd,"pwd") && vcwd[0] && xprefix(vcwd,"/ram")){xs(vcwd);xs("\n");return 1;}
  if (eq(cmd,"ls")||eq(cmd,"cd")||eq(cmd,"cat")||eq(cmd,"stat")||eq(cmd,"write")||eq(cmd,"append")||eq(cmd,"rm")||eq(cmd,"mkdir")||eq(cmd,"touch")){
    char path[256];char word[256];argword(args,word,256);
    if ((xprefix(word,"/ram")&&(word[4]=='/'||!word[4])) || (vcwd[0]&&xprefix(vcwd,"/ram")&&(!*word||*word!='/'))){
      if (!normalize(*word?word:".",path))return xerr("RMFS: ruta larga");
      return rm_command(cmd,args,path);
    }
    if(eq(cmd,"cd")&&vcwd[0]&&xprefix(vcwd,"/ram")){vcwd[0]=0;*X.cwd=ROOT;}
  }
  if((eq(cmd,"nano")||eq(cmd,"edit")) && ((xprefix(args,"/ram/") || (xprefix(vcwd,"/ram") && args[0]!='/'))))return xerr("RMFS: usa write/append; nano aun no soportado");
  if (eq(cmd, "usbscan")) {
    for (u32 i = 0; i < 4; i++)
      if (V[i].used && V[i].disk >= 4) {
        V[i].used = 0;
        if(xprefix(vcwd,"/mnt"))vcwd[0] = 0;
      }
    usb_scan();
    usb_info();
    return 1;
  }
  if (eq(cmd, "usbinfo")) {
    usb_info();
    return 1;
  }
  if (eq(cmd, "usbkbd")) {
    usb_kbd_info();
    return 1;
  }
  if (eq(cmd, "volumes")) {
    volumes();
    return 1;
  }
  if (eq(cmd, "mount")) {
    if (!*args) {
      for (u32 i = 0; i < 4; i++)
        if (V[i].used) {
          xs(V[i].point);
          xs(" FAT32 ro, sectores ");
          xn(V[i].total);
          xs("\n");
        }
      return 1;
    }
    char device[32], point[64];
    const char *s = argword(args, device, 32);
    const char *tail = argword(s, point, 64);
    u32 d, part;
    if (arg_overflow || *tail || !diskname(device, &d, &part))
      return xerr("uso: mount hdb1 /mnt/datos | mount usb0p1 /mnt/usb");
    if (!point[0]) {
      xcopy(point, "/mnt/", 64);
      xcopy(point + 5, device, 59);
    }
    return fat_mount(d, part, point);
  }
  if (eq(cmd, "umount")) {
    for (u32 i = 0; i < 4; i++)
      if (V[i].used && xequal(V[i].point, args)) {
        if (xprefix(vcwd, V[i].point))
          if(xprefix(vcwd,"/mnt"))vcwd[0] = 0;
        V[i].used = 0;
        xs("Volumen desmontado.\n");
        return 1;
      }
    return xerr("punto no montado");
  }
  if (eq(cmd, "font")) {
    if (!*X.framebuffer)
      return xerr("TTF requiere consola framebuffer");
    if (!default_font)
      return xerr("no hay memoria para fuente de respaldo");
    if (eq(args, "default")) {
      if (!default_font)
        return xerr("sin copia de fuente");
      memcopy(X.font, default_font, 4096);
      X.repaint();
      xs("Fuente bitmap restaurada.\n");
      return 1;
    }
    if (!work_ready)
      return xerr("TTF requiere 200 MiB y modulo NASM");
    if (!*args)
      return xerr("uso: font /mnt/datos/fuente.ttf | font default");
    int n = path_load(args, BLOB, BLOB_MAX);
    if (n < 0)
      return xerr(ferror);
    return load_font(BLOB, (u32)n);
  }
  if(eq(cmd,"cpbig")){
    if(!work_ready)return xerr("cpbig requiere 200 MiB");
    char src[256],dst[128];const char *tail=argword(args,src,256);tail=argword(tail,dst,128);
    if(arg_overflow||*tail||!*dst||xprefix(dst,"/ram"))return xerr("uso: cpbig /mnt/ARCHIVO /DESTINO");
    return hsfs_bigcopy(src,dst);
  }
  if(eq(cmd,"cp")){
    char from[256],to[256],path[256];const char*rest=argword(args,from,256);rest=argword(rest,to,256);
    if(*rest){
      char from2[256],to2[256];
      rest=argword(rest,from2,256);rest=argword(rest,to2,256);
      if(!work_ready||arg_overflow||*rest||!*from||!*to||!*from2||!*to2||
         xprefix(to,"/ram")||xprefix(to2,"/ram")||xprefix(to,"/mnt")||xprefix(to2,"/mnt"))
        return xerr("uso: cp /mnt/A /A /mnt/B /B (200 MiB)");
      const char *srcs[2]={from,from2},*dsts[2]={to,to2};
      return hsfs_bigcopy_many(srcs,dsts,2);
    }
    if(xprefix(to,"/ram/") || (xprefix(vcwd,"/ram")&&to[0]&&to[0]!='/')){
      if(!work_ready||arg_overflow||*rest||!normalize(to,path))return xerr("uso: cp ORIGEN /ram/DESTINO (200 MiB)");
      int n=path_load(from,BLOB,RM_SIZE);if(n<0)return xerr(ferror);
      u32 parent;char name[32];int id=rm_resolve(path,&parent,name);
      if(id==-4||id==-2)return xerr("RMFS: destino invalido");
      if(id<0){id=rm_alloc(parent,name,0);if(id<0)return xerr("RMFS: sin nodos");}
      if(!rm_store(R[id],BLOB,(u32)n,0))return xerr("RMFS: sin memoria");
      xs("Copiado a RMFS: ");xs(path);xs("\n");return 1;
    }
  }
  if (eq(cmd, "cp")) {
    if (!work_ready)
      return xerr("importacion requiere 200 MiB");
    char source[256], dest[128];
    const char *s = argword(args, source, 256);
    const char *tail = argword(s, dest, 128);
    char p[256];
    if (!normalize(source, p) && !xcopy(p, source, sizeof p))return xerr("cp: origen demasiado largo");
    if (arg_overflow || *tail || !*dest || xprefix(dest, "/mnt"))
      return xerr("uso: cp ORIGEN DESTINO (FAT32 solo lectura)");
    if(xprefix(p,"/mnt/")){
      struct fatvol *source_vol;struct fatent source_ent;
      if(!hsfs_source(source,&source_vol,&source_ent))
        return xerr("cp: origen FAT32 no encontrado");
      if(source_ent.size>BLOB_MAX)return hsfs_bigcopy(source,dest);
    }
    int n = path_load(source, BLOB, BLOB_MAX);
    if (n < 0)
      return xerr(ferror);
    memcopy((void *)FS, (void *)0x200000, 512 + COUNT * REC);
    cwd = *X.cwd;
    zero(fds, sizeof fds);
    dirty = 0;
    console = X.out;
    int fd = open_(dest, 577);
    if (fd < 0)
      return xerr("destino ASFS invalido");
    int result = write_(fd, BLOB, n);
    fds[fd].used = 0;
    if (result != n)
      return xerr("ASFS sin espacio; transaccion descartada");
    /* Small plain-text imports remain readable by the native TYPE/CAT. */
    if (n <= LIMIT) {
      int text = 1;
      for (int i = 0; i < n; i++)
        if ((BLOB[i] < 32 && BLOB[i] != 9 && BLOB[i] != 10 && BLOB[i] != 13) || BLOB[i] > 126)
          text = 0;
      if (text) {
        u8 *r = record(fds[fd].rec);
        wr(r + 36, 1);
        r[64 + n] = 0;
      }
    }
    changed();
    if (validate_fs(FS))
      return xerr("ASFS invalido; transaccion descartada");
    xs("Copiado: ");
    xs(dest);
    xs("\n");
    return 2;
  }
  if (eq(cmd, "pwd") && vcwd[0]) {
    xs(vcwd);
    xs("\n");
    return 1;
  }
  int reader =
      eq(cmd, "ls") || eq(cmd, "cat") || eq(cmd, "cd") || eq(cmd, "stat");
  char p[256];
  int normalized = normalize(*args ? args : ".", p);
  if (!reader) {
    if (eq(cmd, "nasm") && eq(args, "-v"))
      return 0;
    if (vcwd[0] && (!*args || *args != '/') &&
        (eq(cmd, "write") || eq(cmd, "append") || eq(cmd, "rm") ||
         eq(cmd, "mkdir") || eq(cmd, "touch") || eq(cmd, "nano") ||
         eq(cmd, "edit") || eq(cmd, "nasm") || eq(cmd, "asm")))
      return xerr("FAT32 es solo lectura; usa cp hacia ASFS");
    if (*args == '/' && xprefix(args, "/mnt") &&
        (eq(cmd, "write") || eq(cmd, "append") || eq(cmd, "rm") ||
         eq(cmd, "mkdir") || eq(cmd, "touch") || eq(cmd, "nano") ||
         eq(cmd, "edit")))
      return xerr("FAT32 es solo lectura");
    return 0;
  }
  if (!normalized)
    return 0;
  if (!(xprefix(p, "/mnt") && (!p[4] || p[4] == '/'))) {
    if (eq(cmd, "cd") && vcwd[0]) {
      vcwd[0] = 0;
      *X.cwd = ROOT;
      xcopy(args, p, 252);
    }
    return 0;
  }
  if (eq(p, "/mnt")) {
    if (eq(cmd, "cd")) {
      xcopy(vcwd, p, 256);
      return 1;
    }
    if (eq(cmd, "ls")) {
      for (u32 i = 0; i < 4; i++)
        if (V[i].used) {
          xs(V[i].point + 5);
          xs("/ FAT32 ro\n");
        }
      return 1;
    }
    return xerr("/mnt es un directorio");
  }
  const char *relative;
  struct fatvol *v = volume(p, &relative);
  struct fatent e;
  if (!v)
    return xerr("volumen no montado");
  if (!lookup(v, relative, &e))
    return xerr(ferror);
  if (eq(cmd, "cd")) {
    if (!(e.attr & 16))
      return xerr("no es directorio");
    xcopy(vcwd, p, 256);
    return 1;
  }
  if (eq(cmd, "ls")) {
    if (!(e.attr & 16)) {
      xs(e.name);
      xs(" ");
      xn(e.size);
      xs("\n");
      return 1;
    }
    if (directory(v, e.cluster, 0, 0, 1) < 0)
      return xerr(ferror);
    return 1;
  }
  if (eq(cmd, "stat")) {
    xs(p);
    xs(" bytes ");
    xn(e.size);
    xs(" cluster ");
    xn(e.cluster);
    xs(" FAT32 solo lectura\n");
    return 1;
  }
  if (fat_file(v, &e, 0, BLOB_MAX, 1) < 0)
    return xerr(ferror);
  X.out('\n');
  return 1;
}
static void services_init(struct ext_api *api, int ready) {
  memcopy(&X, api, sizeof X);
  zero(V, sizeof V);
  zero(&U, sizeof U);
  vcwd[0] = 0;
  zero(R, sizeof R);
  if (!*X.persistent_fs) xcopy(vcwd,"/ram",256);
  work_ready = ready;
  default_font = (u8 *)X.alloc();
  if (default_font)
    memcopy(default_font, X.font, 4096);
}
