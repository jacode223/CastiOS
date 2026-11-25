/* Bounded, unhinted TrueType glyf rasterizer for fixed console cells.
 * No font bytecode execution; composite/non-ASCII glyphs keep bitmap fallback.
 */
struct point {
  int x, y;
  u8 on;
};
struct edge {
  int x1, y1, x2, y2;
};
struct tt {
  const u8 *b;
  u32 n, head, hhea, maxp, loca, glyf, glen, hmtx, cmap, cmend, ng, nh;
  int asc, desc, fmt;
};
static u8 *default_font;
static int font_bounds(struct tt *t, u32 off, u32 n) {
  return off <= t->n && n <= t->n - off;
}
static u32 ttable(struct tt *t, u32 tag, u32 min, u32 *length) {
  u32 nt = be16(t->b + 4);
  for (u32 i = 0; i < nt; i++) {
    const u8 *p = t->b + 12 + i * 16;
    if (be32(p) == tag) {
      u32 o = be32(p + 8), n = be32(p + 12);
      if (n < min || !font_bounds(t, o, n))
        return 0;
      if (length)
        *length = n;
      return o;
    }
  }
  return 0;
}
static u32 tt_index(struct tt *t, u32 code) {
  const u8 *b = t->b;
  u32 c = t->cmap;
  if (be16(b + c) == 12) {
    u32 n = be32(b + c + 12);
    for (u32 i = 0; i < n; i++) {
      u32 o = c + 16 + i * 12, a = be32(b + o), z = be32(b + o + 4);
      if (code >= a && code <= z)
        return be32(b + o + 8) + code - a;
    }
    return 0;
  }
  u32 seg = be16(b + c + 6) / 2, end = c + 14, start = end + seg * 2 + 2,
      delta = start + seg * 2, range = delta + seg * 2;
  for (u32 i = 0; i < seg; i++)
    if (code <= be16(b + end + i * 2)) {
      if (code < be16(b + start + i * 2))
        return 0;
      u32 r = be16(b + range + i * 2), g;
      if (!r)
        return (code + be16(b + delta + i * 2)) & 65535;
      u32 o = range + i * 2 + r + (code - be16(b + start + i * 2)) * 2;
      if (o < t->cmap || o + 2 > t->cmend)
        return 0;
      g = be16(b + o);
      return g ? (g + be16(b + delta + i * 2)) & 65535 : 0;
    }
  return 0;
}
static int tt_init(struct tt *t, const u8 *b, u32 n) {
  zero(t, sizeof *t);
  t->b = b;
  t->n = n;
  if (n < 12 || be32(b) != 0x00010000 || be16(b + 4) > 128 ||
      12U + be16(b + 4) * 16U > n)
    return 0;
  t->head = ttable(t, 0x68656164, 54, 0);
  t->hhea = ttable(t, 0x68686561, 36, 0);
  t->maxp = ttable(t, 0x6d617870, 6, 0);
  t->glyf = ttable(t, 0x676c7966, 1, &t->glen);
  if (!t->head || !t->hhea || !t->maxp || !t->glyf)
    return 0;
  t->ng = be16(b + t->maxp + 4);
  t->nh = be16(b + t->hhea + 34);
  t->fmt = (short)be16(b + t->head + 50);
  t->asc = (short)be16(b + t->hhea + 4);
  t->desc = (short)be16(b + t->hhea + 6);
  if (!t->ng || !t->nh || t->nh > t->ng || (t->fmt != 0 && t->fmt != 1) ||
      t->asc - t->desc < 16 || be32(b + t->head + 12) != 0x5f0f3cf5)
    return 0;
  t->loca = ttable(t, 0x6c6f6361, (t->ng + 1) * (t->fmt ? 4 : 2), 0);
  t->hmtx = ttable(t, 0x686d7478, t->nh * 4 + (t->ng - t->nh) * 2, 0);
  u32 len, c = ttable(t, 0x636d6170, 4, &len);
  if (!t->loca || !t->hmtx || !c || be16(b + c + 2) > 64 ||
      4U + be16(b + c + 2) * 8U > len)
    return 0;
  for (u32 i = 0; i < be16(b + c + 2); i++) {
    const u8 *p = b + c + 4 + i * 8;
    u32 o = be32(p + 4);
    if (o > len || len - o < 4)
      continue;
    u32 f = be16(b + c + o);
    if (f == 4) {
      if (len - o < 16)
        continue;
      u32 sz = be16(b + c + o + 2), segs = be16(b + c + o + 6) / 2;
      if (len - o < 16 || sz < 16 || sz > len - o || !segs || segs > 8192 ||
          16 + segs * 8 > sz)
        continue;
      t->cmap = c + o;
      t->cmend = c + o + sz;
    } else if (f == 12 && len - o >= 16) {
      u32 sz = be32(b + c + o + 4), groups = be32(b + c + o + 12);
      if (sz < 16 || sz > len - o || groups > 65536 || groups > (sz - 16) / 12)
        continue;
      t->cmap = c + o;
      t->cmend = c + o + sz;
      break;
    }
  }
  return t->cmap != 0;
}
static int edgeadd(struct edge *edges, u32 *n, struct point a, struct point b) {
  if (a.y == b.y)
    return 1;
  if (*n == 4096)
    return 0;
  edges[(*n)++] = (struct edge){a.x, a.y, b.x, b.y};
  return 1;
}
static struct point midpt(struct point a, struct point b) {
  return (struct point){(a.x + b.x) / 2, (a.y + b.y) / 2, 1};
}
static int quadratic(struct edge *edges, u32 *n, struct point a, struct point c,
                     struct point b) {
  struct point last = a;
  for (int s = 1; s <= 8; s++) {
    int r = 8 - s;
    struct point p = {(r * r * a.x + 2 * r * s * c.x + s * s * b.x) / 64,
                      (r * r * a.y + 2 * r * s * c.y + s * s * b.y) / 64, 1};
    if (!edgeadd(edges, n, last, p))
      return 0;
    last = p;
  }
  return 1;
}
static int raster_glyph(struct tt *t, u32 gid, u8 *out) {
  const u8 *b = t->b;
  if (gid >= t->ng)
    return -1;
  u32 o, z;
  if (t->fmt) {
    o = be32(b + t->loca + gid * 4);
    z = be32(b + t->loca + (gid + 1) * 4);
  } else {
    o = be16(b + t->loca + gid * 2) * 2;
    z = be16(b + t->loca + (gid + 1) * 2) * 2;
  }
  if (z < o || z > t->glen)
    return -1;
  if (z == o) {
    zero(out, 16);
    return 1;
  }
  if (z - o < 10)
    return -1;
  const u8 *p = b + t->glyf + o, *end = b + t->glyf + z;
  int contours = (short)be16(p);
  if (contours < 0)
    return 0;
  if (!contours) {
    zero(out, 16);
    return 1;
  }
  if (contours > 64 || 10 + contours * 2 + 2 > end - p)
    return -1;
  u16 ends[64];
  for (int i = 0; i < contours; i++) {
    ends[i] = be16(p + 10 + i * 2);
    if (i && ends[i] <= ends[i - 1])
      return -1;
  }
  u32 count = ends[contours - 1] + 1;
  if (count > 1024)
    return -1;
  p += 10 + contours * 2;
  u32 instructions = be16(p);
  p += 2;
  if (instructions > (u32)(end - p))
    return -1;
  p += instructions;
  struct point *points = (struct point *)0x08200000;
  u8 *flags = (u8 *)0x08208000;
  struct edge *edges = (struct edge *)0x08210000;
  for (u32 i = 0; i < count;) {
    if (p == end)
      return -1;
    u8 f = *p++;
    u32 run = 1;
    if (f & 8) {
      if (p == end)
        return -1;
      run += *p++;
    }
    if (run > count - i)
      return -1;
    while (run--)
      flags[i++] = f;
  }
  int x = 0, y = 0;
  for (u32 i = 0; i < count; i++) {
    u8 f = flags[i];
    int dx = 0;
    if (f & 2) {
      if (p == end)
        return -1;
      dx = *p++;
      if (!(f & 16))
        dx = -dx;
    } else if (!(f & 16)) {
      if (end - p < 2)
        return -1;
      dx = (short)be16(p);
      p += 2;
    }
    x += dx;
    if (x < -32768 || x > 32767)
      return -1;
    points[i].x = x;
    points[i].on = f & 1;
  }
  for (u32 i = 0; i < count; i++) {
    u8 f = flags[i];
    int dy = 0;
    if (f & 4) {
      if (p == end)
        return -1;
      dy = *p++;
      if (!(f & 32))
        dy = -dy;
    } else if (!(f & 32)) {
      if (end - p < 2)
        return -1;
      dy = (short)be16(p);
      p += 2;
    }
    y += dy;
    if (y < -32768 || y > 32767)
      return -1;
    points[i].y = y;
  }
  u32 adv = be16(b + t->hmtx + (gid < t->nh ? gid : t->nh - 1) * 4);
  if (adv < 16)
    return 0;
  int scale = (15 * 65536) / (t->asc - t->desc), fit = (8 * 65536) / (int)adv;
  if (fit < scale)
    scale = fit;
  int xoff = (8 * 256 - (int)adv * scale / 256) / 2,
      base = t->asc * scale / 256;
  for (u32 i = 0; i < count; i++) {
    points[i].x = xoff + points[i].x * scale / 256;
    points[i].y = base - points[i].y * scale / 256;
    if (points[i].x < -8192 || points[i].x > 16384 || points[i].y < -8192 ||
        points[i].y > 16384)
      return -1;
  }
  u32 ne = 0, first = 0;
  for (int c = 0; c < contours; c++) {
    u32 last = ends[c], i = first, stop = last;
    struct point a;
    if (points[first].on) {
      a = points[first];
      i++;
    } else if (points[last].on) {
      a = points[last];
      stop--;
    } else
      a = midpt(points[first], points[last]);
    struct point origin = a;
    while (i <= stop) {
      struct point q = points[i++];
      if (q.on) {
        if (!edgeadd(edges, &ne, a, q))
          return -1;
        a = q;
      } else {
        struct point next = i <= stop ? points[i] : origin, endpoint;
        if (next.on) {
          endpoint = next;
          if (i <= stop)
            i++;
        } else
          endpoint = midpt(q, next);
        if (!quadratic(edges, &ne, a, q, endpoint))
          return -1;
        a = endpoint;
      }
    }
    if (!edgeadd(edges, &ne, a, origin))
      return -1;
    first = last + 1;
  }
  zero(out, 16);
  for (int py = 0; py < 16; py++)
    for (int px = 0; px < 8; px++) {
      int xx = px * 256 + 128, yy = py * 256 + 128, winding = 0;
      for (u32 i = 0; i < ne; i++) {
        struct edge e = edges[i];
        if ((e.y1 <= yy && yy < e.y2) || (e.y2 <= yy && yy < e.y1)) {
          int cross = e.x1 + (yy - e.y1) * (e.x2 - e.x1) / (e.y2 - e.y1);
          if (cross > xx)
            winding += e.y2 > e.y1 ? 1 : -1;
        }
      }
      if (winding)
        out[py] |= 128 >> px;
    }
  return 1;
}
static int load_font(const u8 *data, u32 n) {
  struct tt t;
  if (!tt_init(&t, data, n))
    return xerr("TTF invalida o sin tablas TrueType compatibles");
  u8 *bitmap = (u8 *)0x08230000;
  memcopy(bitmap, default_font, 4096);
  u32 fallback = 0;
  for (u32 c = 32; c < 127; c++) {
    u32 gid = tt_index(&t, c);
    if (!gid) {
      fallback++;
      continue;
    }
    int result = raster_glyph(&t, gid, bitmap + c * 16);
    if (result < 0)
      return xerr("contorno TTF corrupto o demasiado complejo");
    if (!result)
      fallback++;
  }
  if (fallback == 95)
    return xerr("la TTF no contiene glifos ASCII utilizables");
  memcopy(X.font, bitmap, 4096);
  X.repaint();
  xs("TTF aplicada a la terminal (ASCII; ");
  xn(fallback);
  xs(" glifos con fallback).\n");
  return 1;
}
