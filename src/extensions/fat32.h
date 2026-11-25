/* Bounded read-only FAT32, MBR primary/GPT/superfloppy. */
struct fatvol {
  u32 used, disk, start, total, fat, data, spc, clusters, root, fatsz;
  char point[48];
};
struct fatent {
  u32 cluster, size;
  u8 attr;
  char name[256], shortname[13];
};
static struct fatvol V[4];
static char vcwd[256];
/* One-sector FAT cache and Brent cycle detector: constant extra RAM. */
static u32 fat_cached_lba, fat_cached_disk, fat_cached_valid;
struct chain_guard {u32 anchor, power, length, hops;};
static u8 sec[512], fsec[512];
static const char *ferror;
static u32 diskcap(u32 d) {
  return d < 4 ? X.caps[d]
               : (d - 4 < U.count && usb_connected(&U.d[d - 4]) ? U.d[d - 4].cap : 0);
}
static int dread(u32 d, u32 lba, void *b) {
  if (lba >= diskcap(d))
    return -1;
  return d < 4 ? X.read(d, lba, b) : usb_read(d - 4, lba, b);
}
static u32 crc_byte(u32 c, u8 b) {
  c ^= b;
  for (int n = 0; n < 8; n++)
    c = (c >> 1) ^ ((0U - (c & 1)) & 0xedb88320U);
  return c;
}
static u32 gpt_scan_disk=0xffffffffU,gpt_scan_table,gpt_scan_count;
static int gpt_entry(u32 d,const u8*chosen,u32 *start,u32 *length){
  if(le32(chosen+36)||le32(chosen+44))return 0;
  u32 any=0;for(int i=0;i<16;i++)any|=chosen[i];
  *start=le32(chosen+32);u32 end=le32(chosen+40);
  if(!any||!*start||end<*start||end>=diskcap(d))return 0;
  *length=end-*start+1;return 1;
}
static int partition(u32 d, u32 n, u32 *start, u32 *length) {
  u32 cap = diskcap(d);
  if (!cap || dread(d, 0, sec))
    return 0;
  if (!n) {
    *start = 0;
    *length = cap;
    return 1;
  }
  if (le16(sec + 510) != 0xaa55)
    return 0;
  if (sec[450] != 0xee) {
    if (n > 4)
      return 0;
    u8 *p = sec + 446 + (n - 1) * 16;
    *start = le32(p + 8);
    *length = le32(p + 12);
    return p[4] && *start && *length && *start < cap && *length <= cap - *start;
  }
  if (dread(d, 1, sec))
    return 0;
  if (le32(sec) != 0x20494645 || le32(sec + 4) != 0x54524150 ||
      le32(sec + 12) < 92 || le32(sec + 12) > 512)
    return 0;
  u32 size = le32(sec + 12), expected = le32(sec + 16);
  st32(sec + 16, 0);
  u32 c = ~0U;
  for (u32 i = 0; i < size; i++)
    c = crc_byte(c, sec[i]);
  if ((c ^ ~0U) != expected || le32(sec + 28) || le32(sec + 24) != 1 ||
      le32(sec + 76))
    return 0;
  u32 table = le32(sec + 72), count = le32(sec + 80), entsz = le32(sec + 84),
      arraycrc = le32(sec + 88);
  if (!count || count > 128 || entsz != 128 || !n || n > count ||
      table >= cap || (count * 128 + 511) / 512 > cap - table)
    return 0;
  c = ~0U;
  u8 chosen[128];
  zero(chosen, 128);
  for (u32 i = 0; i < (count * 128 + 511) / 512; i++) {
    if (dread(d, table + i, sec))
      return 0;
    u32 take = count * 128 - i * 512;
    if (take > 512)
      take = 512;
    for (u32 j = 0; j < take; j++)
      c = crc_byte(c, sec[j]);
    if ((n - 1) / 4 == i)
      memcopy(chosen, sec + ((n - 1) % 4) * 128, 128);
  }
  if ((c ^ ~0U) != arraycrc)return 0;
  if(gpt_scan_disk==d){gpt_scan_table=table;gpt_scan_count=count;}
  return gpt_entry(d,chosen,start,length);
}
static int fat_mount(u32 d, u32 part, const char *point) {
  u32 s, len;
  if (!partition(d, part, &s, &len) || dread(d, s, sec))
    return xerr("particion ausente, corrupta o inaccesible");
  if (le16(sec + 510) != 0xaa55 || le16(sec + 11) != 512 || le16(sec + 17) ||
      le16(sec + 22) || le16(sec + 42))
    return xerr("no es FAT32 de sectores 512");
  u32 spc = sec[13], reserved = le16(sec + 14), nf = sec[16],
      sz = le32(sec + 36), total = le32(sec + 32), flags = le16(sec + 40),
      root = le32(sec + 44) & 0x0fffffff;
  if (!spc || spc > 128 || (spc & (spc - 1)) || !reserved || nf < 1 || nf > 2 ||
      !sz || total > len || reserved >= total || sz > (total - reserved) / nf)
    return xerr("BPB FAT32 invalido");
  if (reserved >= total || nf * sz >= total - reserved)
    return xerr("geometria FAT32 invalida");
  u32 clusters = (total - reserved - nf * sz) / spc;
  if (clusters < 65525 || clusters > 0x0fffffee ||
      sz < ((clusters + 2) + 127) / 128 || root < 2 || root > clusters + 1)
    return xerr("clusters FAT32 invalidos");
  u32 active = (flags & 128) ? flags & 15 : 0;
  if (active >= nf)
    return xerr("FAT activa invalida");
  u32 i;
  for (i = 0; i < 4 && V[i].used; i++)
    ;
  if (i == 4)
    return xerr("maximo cuatro montajes");
  for (u32 j = 0; j < 4; j++)
    if (V[j].used && xequal(V[j].point, point))
      return xerr("punto ocupado");
  if (!xprefix(point, "/mnt/") || !point[5] || strlen_(point) >= 48)
    return xerr("usa /mnt/NOMBRE (maximo 42 caracteres)");
  for (u32 j = 5; point[j]; j++)
    if (point[j] == '/' || point[j] == ' ' || point[j] == '.')
      return xerr("nombre de montaje invalido");
  V[i] = (struct fatvol){1,
                         d,
                         s,
                         total,
                         s + reserved + active * sz,
                         s + reserved + nf * sz,
                         spc,
                         clusters,
                         root,
                         sz,
                         {0}};
  xcopy(V[i].point, point, 48);
  xs("Montado FAT32 solo lectura: ");
  xs(point);
  xs("\n");
  return 1;
}
static int vread(struct fatvol *v, u32 lba, u8 *b) {
  if (lba < v->start || lba - v->start >= v->total || dread(v->disk, lba, b)) {
    ferror = "error de lectura o dispositivo desconectado";
    return 0;
  }
  return 1;
}
static u32 nextcl(struct fatvol *v, u32 cl) {
  if (cl < 2 || cl > v->clusters + 1) {
    ferror = "cluster fuera de rango";
    return 0;
  }
  u32 offset = cl >> 7;
  if (offset >= v->fatsz) return 0;
  u32 lba=v->fat+offset;
  if(!fat_cached_valid||fat_cached_disk!=v->disk||fat_cached_lba!=lba){
    fat_cached_valid=0;
    if(!vread(v,lba,fsec))return 0;
    fat_cached_lba=lba;fat_cached_disk=v->disk;fat_cached_valid=1;
  }
  u32 n = le32(fsec + (cl & 127) * 4) & 0xfffffff;
  if (n >= 0xffffff8)
    return 0xffffffff;
  if (n < 2 || n > v->clusters + 1) {
    ferror = "cadena FAT32 corrupta";
    return 0;
  }
  return n;
}
static int visited(struct chain_guard*g,u32 cl,u32 max){
  if(!g->hops){g->anchor=cl;g->power=1;g->hops=1;return 0;}
  if(cl==g->anchor||g->hops>=max){ferror="bucle en cadena FAT32";return 1;}
  g->hops++;g->length++;
  if(g->length==g->power){g->anchor=cl;g->power*=2;g->length=0;}
  return 0;
}
static u8 shortsum(const u8 *p) {
  u8 s = 0;
  for (int i = 0; i < 11; i++)
    s = ((s & 1) ? 128 : 0) + (s >> 1) + p[i];
  return s;
}
static void shortname(const u8 *p, char *s) {
  u32 n = 0;
  for (u32 i = 0; i < 8 && p[i] != ' '; i++)
    s[n++] = (char)p[i];
  if (p[8] != ' ') {
    s[n++] = '.';
    for (u32 i = 8; i < 11 && p[i] != ' '; i++)
      s[n++] = (char)p[i];
  }
  s[n] = 0;
}
static int directory(struct fatvol *v, u32 cl, const char *find,
                     struct fatent *out, int print) {
  struct chain_guard guard={0};
  fat_cached_valid=0;
  char lfn[256];
  int expect = 0, checksum = 0, lfnok = 0;
  for (;;) {
    if (cl < 2 || cl > v->clusters + 1) {
      ferror = "cluster de directorio invalido";
      return -1;
    }
    if (visited(&guard,cl,v->clusters))
      return -1;
    for (u32 s = 0; s < v->spc; s++) {
      if (!vread(v, v->data + (cl - 2) * v->spc + s, sec))
        return -1;
      for (int pos = 0; pos < 512; pos += 32) {
        u8 *p = sec + pos;
        if (!p[0])
          return 0;
        if (p[0] == 0xe5) {
          expect = 0;
          lfnok = 0;
          continue;
        }
        if (p[11] == 15) {
          u32 seq = p[0] & 31;
          if (p[0] & 64) {
            zero(lfn, 256);
            expect = seq;
            checksum = p[13];
            lfnok = seq && seq <= 20;
          }
          if (!lfnok || seq != (u32)expect || p[13] != checksum || p[12] ||
              le16(p + 26)) {
            lfnok = 0;
            expect = 0;
            continue;
          }
          const u8 where[13] = {1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30};
          for (int j = 0; j < 13; j++) {
            u32 off = (seq - 1) * 13 + j;
            u16 c = le16(p + where[j]);
            if (off < 255) {
              if (c == 0 || c == 0xffff)
                lfn[off] = 0;
              else if (c >= 32 && c < 127)
                lfn[off] = c;
              else
                lfnok = 0;
            }
          }
          expect--;
          continue;
        }
        if (p[11] & 8) {
          lfnok = 0;
          expect = 0;
          continue;
        }
        struct fatent e;
        zero(&e, sizeof e);
        shortname(p, e.shortname);
        xcopy(e.name,
              lfnok && expect == 0 && shortsum(p) == checksum && lfn[0]
                  ? lfn
                  : e.shortname,
              256);
        expect = 0;
        lfnok = 0;
        if (xequal(e.shortname, ".") || xequal(e.shortname, ".."))
          continue;
        e.cluster = (((u32)le16(p + 20) << 16) | le16(p + 26)) & 0xfffffff;
        e.size = le32(p + 28);
        e.attr = p[11];
        if (print) {
          xs(e.name);
          if (e.attr & 16)
            X.out('/');
          xs("  ");
          xn(e.size);
          if (!xequal(e.name, e.shortname)) {
            xs(" [");
            xs(e.shortname);
            xs("]");
          }
          xs("\n");
        }
        if (find && (xequal(e.name, find) || xequal(e.shortname, find))) {
          *out = e;
          return 1;
        }
      }
    }
    cl = nextcl(v, cl);
    if (!cl)
      return -1;
    if (cl == 0xffffffff)
      return 0;
  }
}
static int normalize(const char *input, char *out) {
  char tmp[512];
  if (*input == '/') {
    if (!xcopy(tmp, input, 512))
      return 0;
  } else {
    if (!vcwd[0])
      return 0;
    u32 n = strlen_(vcwd), m = strlen_(input);
    if (n + 1 + m >= 512)
      return 0;
    memcopy(tmp, vcwd, n);
    tmp[n++] = '/';
    memcopy(tmp + n, input, m + 1);
  }
  u32 n = 0, stack[128], count = 0;
  out[n++] = '/';
  const char *s = tmp;
  while (*s) {
    while (*s == '/')
      s++;
    if (!*s)
      break;
    const char *b = s;
    while (*s && *s != '/')
      s++;
    u32 len = s - b;
    if (len == 1 && b[0] == '.')
      continue;
    if (len == 2 && b[0] == '.' && b[1] == '.') {
      if (count)
        n = stack[--count];
      continue;
    }
    if (n + len + 1 >= 256 || count == 128)
      return 0;
    stack[count++] = n;
    if (n > 1)
      out[n++] = '/';
    memcopy(out + n, b, len);
    n += len;
  }
  out[n] = 0;
  return 1;
}
static struct fatvol *volume(const char *p, const char **relative) {
  for (u32 i = 0; i < 4; i++)
    if (V[i].used) {
      u32 n = strlen_(V[i].point);
      if (xprefix(p, V[i].point) && (p[n] == '/' || !p[n])) {
        *relative = p + n;
        return &V[i];
      }
    }
  return 0;
}
static int lookup(struct fatvol *v, const char *relative, struct fatent *out) {
  struct fatent e;
  zero(&e, sizeof e);
  e.cluster = v->root;
  e.attr = 16;
  const char *s = relative;
  while (*s) {
    while (*s == '/')
      s++;
    if (!*s)
      break;
    char part[256];
    u32 n = 0;
    while (*s && *s != '/') {
      if (n == 255) {
        ferror = "nombre largo";
        return 0;
      }
      part[n++] = *s++;
    }
    part[n] = 0;
    if (!(e.attr & 16)) {
      ferror = "no es directorio";
      return 0;
    }
    int found = directory(v, e.cluster, part, &e, 0);
    if (found <= 0) {
      if (!found)
        ferror = "archivo no encontrado";
      return 0;
    }
  }
  *out = e;
  return 1;
}
static int fat_file(struct fatvol *v, struct fatent *e, u8 *out, u32 limit,
                    int display) {
  if (e->attr & 16) {
    ferror = "es un directorio";
    return -1;
  }
  if (e->size > limit) {
    ferror = "archivo supera limite";
    return -1;
  }
  if (!e->size)
    return 0;
  u32 cl = e->cluster, left = e->size, offset = 0;
  struct chain_guard guard={0};fat_cached_valid=0;
  while (left) {
    if (visited(&guard,cl,v->clusters))
      return -1;
    if (cl < 2 || cl > v->clusters + 1) {
      ferror = "cluster invalido";
      return -1;
    }
    for (u32 s = 0; s < v->spc && left; s++) {
      if (!vread(v, v->data + (cl - 2) * v->spc + s, sec))
        return -1;
      u32 take = left < 512 ? left : 512;
      if (display) {
        for (u32 j = 0; j < take; j++)
          if (sec[j] >= 32 || sec[j] == '\n' || sec[j] == '\t')
            X.out(sec[j]);
      } else
        memcopy(out + offset, sec, take);
      left -= take;
      offset += take;
    }
    if (left) {
      cl = nextcl(v, cl);
      if (!cl || cl == 0xffffffff) {
        ferror = "cadena truncada";
        return -1;
      }
    }
  }
  return (int)offset;
}
static int diskname(const char *s, u32 *d, u32 *part) {
  const char *p = s;
  if (p[0] == 'h' && p[1] == 'd' && p[2] >= 'a' && p[2] <= 'd') {
    *d = p[2] - 'a';
    p += 3;
  } else if (xprefix(p, "usb") && p[3] >= '0' && p[3] <= '3') {
    *d = 4 + p[3] - '0';
    p += 4;
    if (*p == 'p') {
      p++;
      if (*p < '0' || *p > '9')
        return 0;
    }
  } else
    return 0;
  *part = 0;
  if (!*p)
    return 1;
  while (*p >= '0' && *p <= '9') {
    if (*part > 128)
      return 0;
    *part = *part * 10 + *p++ - '0';
  }
  return !*p && *part && *part <= 128;
}
static void volumes(void) {
  for (u32 d = 0; d < 4 + U.count; d++) {
    u32 cap = diskcap(d);
    if (!cap)
      continue;
    if (d < 4) {
      xs("hd");
      X.out('a' + d);
    } else {
      xs("usb");
      xn(d - 4);
    }
    xs("  sectores ");
    xn(cap);
    xs("\n");
    if (dread(d, 0, sec) || le16(sec + 510) != 0xaa55)
      continue;
    int gpt = sec[450] == 0xee;
    if(gpt){
      /* Validate GPT CRC once, then print up to four entries per sector. */
      gpt_scan_disk=d;gpt_scan_count=0;u32 start,len;
      partition(d,1,&start,&len);gpt_scan_disk=0xffffffffU;
      for(u32 p=0;p<gpt_scan_count;p+=4){
        if(dread(d,gpt_scan_table+p/4,sec))break;
        for(u32 i=0;i<4&&p+i<gpt_scan_count;i++){
          if(!gpt_entry(d,sec+i*128,&start,&len))continue;
          xs("  particion ");xn(p+i+1);xs(" LBA ");xn(start);xs(" sectores ");xn(len);xs("\n");
        }
      }
      continue;
    }
    for (u32 p = 1; p <= 4; p++) {
      u32 start, len;
      if (!partition(d, p, &start, &len))continue;
      xs("  particion ");xn(p);xs(" LBA ");xn(start);xs(" sectores ");xn(len);xs("\n");
    }
  }
}
