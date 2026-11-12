// Generates Flightpath Legends textures: piece fill/outline layers, markers and the logo (32-bit TGA),
// plus a PNG preview of a board for visual checking.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const OUT = process.argv[2];
const PREVIEW = process.argv[3];
fs.mkdirSync(OUT, { recursive: true });

const SIZE = 128; // texture size
const SS = 4; // supersampling
const HI = SIZE * SS;
const U = HI / 64; // shapes are designed on a 64x64 grid

// ---------------------------------------------------------------- shapes
const circle = (cx, cy, r, sub) => ({ t: "c", cx, cy, r, sub });
const ellipse = (cx, cy, rx, ry, sub) => ({ t: "e", cx, cy, rx, ry, sub });
const rect = (x1, y1, x2, y2, sub) => ({ t: "p", pts: [[x1, y1], [x2, y1], [x2, y2], [x1, y2]], sub });
const poly = (pts, sub) => ({ t: "p", pts, sub });

function inPoly(x, y, pts) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function inShape(s, x, y) {
  if (s.t === "c") return (x - s.cx) ** 2 + (y - s.cy) ** 2 <= s.r * s.r;
  if (s.t === "e") return ((x - s.cx) / s.rx) ** 2 + ((y - s.cy) / s.ry) ** 2 <= 1;
  return inPoly(x, y, s.pts);
}

const BASE = [rect(15, 50, 49, 57), ellipse(32, 50, 17, 3.2)];

const PIECES = {
  P: [...BASE, poly([[22, 50], [42, 50], [37, 30], [27, 30]]), ellipse(32, 30, 9, 3), circle(32, 20, 8)],
  R: [...BASE, poly([[20, 50], [44, 50], [41, 24], [23, 24]]), ellipse(32, 24, 12, 2.5),
    rect(18, 11, 46, 24), rect(23.5, 10, 28.5, 16, true), rect(35.5, 10, 40.5, 16, true)],
  N: [...BASE, poly([[20, 50], [45, 50], [46, 33], [43, 20], [36, 12], [31, 10], [29, 6], [26, 11],
    [21, 16], [13, 29], [12, 35], [16, 38], [21, 35], [27, 31], [29, 33], [22, 42]]), circle(29, 18, 1.8, true)],
  B: [...BASE, poly([[23, 50], [41, 50], [37, 42], [27, 42]]), ellipse(32, 42, 9, 2.6), ellipse(32, 30, 10, 13),
    circle(32, 13, 4), poly([[34, 20], [37.5, 23], [31, 31], [28, 28]], true)],
  Q: [...BASE, poly([[19, 50], [12, 17], [18.5, 32], [22, 13], [27, 31], [32, 10], [37, 31], [42, 13], [45.5, 32], [52, 17], [45, 50]]),
    circle(12, 16, 3.3), circle(22, 12, 3.3), circle(32, 8.5, 3.3), circle(42, 12, 3.3), circle(52, 16, 3.3),
    ellipse(32, 42, 13.5, 3)],
  K: [...BASE, poly([[21, 50], [43, 50], [48, 27], [16, 27]]), ellipse(32, 27, 16, 6.5), ellipse(32, 42, 12.5, 2.8),
    rect(29.8, 4, 34.2, 22), rect(25, 8.5, 39, 12.8)],
};

function rasterize(shapes) {
  const m = new Uint8Array(HI * HI);
  for (let y = 0; y < HI; y++) {
    for (let x = 0; x < HI; x++) {
      const gx = (x + 0.5) / U, gy = (y + 0.5) / U;
      let v = 0;
      for (const s of shapes) {
        if (inShape(s, gx, gy)) v = s.sub ? 0 : 1;
      }
      m[y * HI + x] = v;
    }
  }
  return m;
}

// Chamfer distance (in hi-res pixels) from each pixel to the nearest pixel where mask == target.
function distanceTo(mask, target) {
  const INF = 1e9;
  const d = new Float32Array(HI * HI);
  for (let i = 0; i < d.length; i++) d[i] = mask[i] === target ? 0 : INF;
  const a = 1, b = Math.SQRT2;
  for (let y = 0; y < HI; y++) for (let x = 0; x < HI; x++) {
    const i = y * HI + x;
    let v = d[i];
    if (x > 0) v = Math.min(v, d[i - 1] + a);
    if (y > 0) {
      v = Math.min(v, d[i - HI] + a);
      if (x > 0) v = Math.min(v, d[i - HI - 1] + b);
      if (x < HI - 1) v = Math.min(v, d[i - HI + 1] + b);
    }
    d[i] = v;
  }
  for (let y = HI - 1; y >= 0; y--) for (let x = HI - 1; x >= 0; x--) {
    const i = y * HI + x;
    let v = d[i];
    if (x < HI - 1) v = Math.min(v, d[i + 1] + a);
    if (y < HI - 1) {
      v = Math.min(v, d[i + HI] + a);
      if (x < HI - 1) v = Math.min(v, d[i + HI + 1] + b);
      if (x > 0) v = Math.min(v, d[i + HI - 1] + b);
    }
    d[i] = v;
  }
  return d;
}

function downsample(hi) {
  const out = new Float32Array(SIZE * SIZE);
  for (let y = 0; y < SIZE; y++) for (let x = 0; x < SIZE; x++) {
    let s = 0;
    for (let j = 0; j < SS; j++) for (let i = 0; i < SS; i++) s += hi[(y * SS + j) * HI + x * SS + i];
    out[y * SIZE + x] = s / (SS * SS);
  }
  return out;
}

// ---------------------------------------------------------------- writers
function writeTGA(file, w, h, rgba) {
  const buf = Buffer.alloc(18 + w * h * 4);
  buf[2] = 2; // uncompressed true-colour
  buf.writeUInt16LE(w, 12);
  buf.writeUInt16LE(h, 14);
  buf[16] = 32;
  buf[17] = 0x28; // top-left origin, 8 alpha bits
  for (let i = 0; i < w * h; i++) {
    buf[18 + i * 4] = rgba[i * 4 + 2];
    buf[18 + i * 4 + 1] = rgba[i * 4 + 1];
    buf[18 + i * 4 + 2] = rgba[i * 4];
    buf[18 + i * 4 + 3] = rgba[i * 4 + 3];
  }
  fs.writeFileSync(file, buf);
}

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function writePNG(file, w, h, rgba) {
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    for (let i = 0; i < w * 4; i++) raw[y * (w * 4 + 1) + 1 + i] = rgba[y * w * 4 + i];
  }
  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0)),
  ]));
}

function alphaToRGBA(alpha, size) {
  const rgba = Buffer.alloc(size * size * 4);
  for (let i = 0; i < size * size; i++) {
    rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = 255;
    rgba[i * 4 + 3] = Math.round(Math.max(0, Math.min(1, alpha[i])) * 255);
  }
  return rgba;
}

// ---------------------------------------------------------------- pieces
const LINE = 2.6 * SS; // outline width in hi-res pixels (about 2.6 texture pixels)
const layers = {};
for (const [name, shapes] of Object.entries(PIECES)) {
  const mask = rasterize(shapes);
  const dOut = distanceTo(mask, 1); // distance from outside pixels to the shape
  const dIn = distanceTo(mask, 0); // distance from inside pixels to the edge
  const fillHi = new Float32Array(HI * HI);
  const lineHi = new Float32Array(HI * HI);
  for (let i = 0; i < HI * HI; i++) {
    fillHi[i] = mask[i];
    const inside = mask[i] === 1;
    lineHi[i] = (inside ? dIn[i] <= LINE * 0.55 : dOut[i] <= LINE * 0.45) ? 1 : 0;
  }
  const fill = downsample(fillHi), line = downsample(lineHi);
  layers[name] = { fill, line };
  writeTGA(path.join(OUT, name + "_fill.tga"), SIZE, SIZE, alphaToRGBA(fill, SIZE));
  writeTGA(path.join(OUT, name + "_line.tga"), SIZE, SIZE, alphaToRGBA(line, SIZE));
}

// ---------------------------------------------------------------- markers (64x64)
function radial(fn, size) {
  const a = new Float32Array(size * size);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    let s = 0;
    for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) {
      const dx = x + (i + 0.5) / 4 - size / 2, dy = y + (j + 0.5) / 4 - size / 2;
      s += fn(Math.sqrt(dx * dx + dy * dy) / (size / 2));
    }
    a[y * size + x] = s / 16;
  }
  return a;
}
writeTGA(path.join(OUT, "dot.tga"), 64, 64, alphaToRGBA(radial((r) => (r <= 0.92 ? 1 : 0), 64), 64));
writeTGA(path.join(OUT, "ring.tga"), 64, 64, alphaToRGBA(radial((r) => (r <= 1 && r >= 0.82 ? 1 : 0), 64), 64));

// ---------------------------------------------------------------- token parts (128x128)
// Grayscale + alpha so the addon can tint them per faction.
function field(size, fn) {
  const rgba = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    let r = 0, g = 0, b = 0, a = 0;
    for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) {
      const u = ((x + (i + 0.5) / 4) / size) * 2 - 1, v = ((y + (j + 0.5) / 4) / size) * 2 - 1;
      const [cr, cg, cb, ca] = fn(u, v);
      r += cr * ca; g += cg * ca; b += cb * ca; a += ca;
    }
    const k = (y * size + x) * 4;
    rgba[k] = a ? Math.round((r / a) * 255) : 255;
    rgba[k + 1] = a ? Math.round((g / a) * 255) : 255;
    rgba[k + 2] = a ? Math.round((b / a) * 255) : 255;
    rgba[k + 3] = Math.round((a / 16) * 255);
  }
  return rgba;
}
const clamp01 = (t) => Math.max(0, Math.min(1, t));
const smooth = (e0, e1, x) => { const t = clamp01((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t); };
const tokenParts = {
  // Circular mask for the portrait.
  mask: (u, v) => [1, 1, 1, Math.hypot(u, v) <= 0.90 ? 1 : 0],
  // Bevelled metal ring: light from the top-left, darker bottom-right, engraved centre line.
  token_ring: (u, v) => {
    const r = Math.hypot(u, v);
    if (r < 0.84 || r > 0.995) return [0, 0, 0, 0];
    const t = (r - 0.84) / (0.995 - 0.84); // 0 inner .. 1 outer
    const light = 0.5 + 0.5 * (-(u + v) / Math.SQRT2) / Math.max(r, 1e-6) * Math.cos((t - 0.5) * Math.PI);
    let shade = 0.55 + 0.45 * light;
    if (Math.abs(t - 0.5) < 0.08) shade *= 0.7; // engraved groove
    if (t < 0.12 || t > 0.9) shade *= 0.6; // dark edges
    return [shade, shade, shade, 1];
  },
  // Thin dark band just inside the ring for depth.
  token_rim: (u, v) => {
    const r = Math.hypot(u, v);
    return [1, 1, 1, r > 0.78 && r < 0.86 ? 0.9 : 0];
  },
  // Glassy highlight over the top of the portrait.
  token_shine: (u, v) => {
    const r = Math.hypot(u, v);
    if (r > 0.84) return [1, 1, 1, 0];
    const d = Math.hypot(u + 0.15, v + 0.55) / 0.55;
    return [1, 1, 1, 0.55 * (1 - smooth(0.4, 1, d))];
  },
  shadow: (u, v) => [0, 0, 0, 1 - smooth(0.2, 1, Math.hypot(u, v))],
  burst: (u, v) => {
    const r = Math.hypot(u, v);
    const rays = 0.5 + 0.5 * Math.cos(Math.atan2(v, u) * 8);
    return [1, 1, 1, clamp01((1 - smooth(0, 1, r)) * (0.75 + 0.25 * rays))];
  },
  // Diagonal sword-slash streak, tapered at both ends.
  slash: (u, v) => {
    const along = (u - v) / Math.SQRT2; // -1.4 .. 1.4 along the diagonal
    const across = Math.abs(u + v) / Math.SQRT2;
    const taper = clamp01(1 - Math.abs(along) / 1.2);
    const width = 0.12 * taper;
    return [1, 1, 1, width > 0 ? clamp01(1 - across / width) * taper : 0];
  },
};
for (const [name, fn] of Object.entries(tokenParts)) {
  const rgba = field(SIZE, fn);
  writeTGA(path.join(OUT, name + ".tga"), SIZE, SIZE, rgba);
}

// ---------------------------------------------------------------- logo (knight on a gold-rimmed tile)
{
  const S = SIZE, rgba = Buffer.alloc(S * S * 4);
  const { fill, line } = layers.N;
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const i = y * S + x;
    // rounded-square background
    const cx = Math.abs(x + 0.5 - S / 2), cy = Math.abs(y + 0.5 - S / 2);
    const R = 18, half = S / 2 - 2;
    const qx = Math.max(cx - (half - R), 0), qy = Math.max(cy - (half - R), 0);
    const dist = Math.sqrt(qx * qx + qy * qy) - R + Math.max(Math.min(cx - (half - R), 0), Math.min(cy - (half - R), 0)) * 0;
    const inside = Math.max(0, Math.min(1, 0.5 - dist));
    const rim = Math.max(0, Math.min(1, 0.5 - Math.abs(dist + 4) + 3)) * inside;
    let r = 30, g = 22, b = 14; // dark wood
    const checker = ((Math.floor(x / (S / 4)) + Math.floor(y / (S / 4))) % 2) ? 1.25 : 1;
    r *= checker; g *= checker; b *= checker;
    // gold rim
    r = r * (1 - rim) + 235 * rim; g = g * (1 - rim) + 185 * rim; b = b * (1 - rim) + 60 * rim;
    // knight: gold fill, dark outline
    const f = fill[i], l = line[i];
    r = r * (1 - f) + 250 * f; g = g * (1 - f) + 205 * f; b = b * (1 - f) + 80 * f;
    r = r * (1 - l) + 25 * l; g = g * (1 - l) + 15 * l; b = b * (1 - l) + 5 * l;
    rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = Math.round(inside * 255);
  }
  writeTGA(path.join(OUT, "logo.tga"), S, S, rgba);
  if (PREVIEW) writePNG(path.join(PREVIEW, "logo.png"), S, S, rgba);
}

// ---------------------------------------------------------------- board preview
if (PREVIEW) {
  const sq = 64, W = sq * 8;
  const img = Buffer.alloc(W * W * 4);
  const light = [0.93, 0.85, 0.71], dark = [0.62, 0.43, 0.27];
  const wFill = [0.97, 0.95, 0.90], wLine = [0.08, 0.07, 0.06], bFill = [0.20, 0.19, 0.18], bLine = [0.92, 0.90, 0.85];
  const layout = ["rnbqkbnr", "pppppppp", "........", "....P...", "..B.n...", "........", "PPPP.PPP", "RNBQK.NR"];
  const sample = (a, u, v) => { // bilinear-ish nearest sample of 128px layer at 64px
    const x = Math.min(SIZE - 1, Math.floor(u * SIZE)), y = Math.min(SIZE - 1, Math.floor(v * SIZE));
    return a[y * SIZE + x];
  };
  for (let y = 0; y < W; y++) for (let x = 0; x < W; x++) {
    const file = Math.floor(x / sq), rank = Math.floor(y / sq);
    let c = ((file + rank) % 2 === 0) ? light : dark;
    c = c.map((v) => v * 255);
    const ch = layout[rank][file];
    if (ch !== ".") {
      const white = ch === ch.toUpperCase();
      const L = layers[ch.toUpperCase()];
      const inset = 0.04;
      const u = ((x % sq) / sq - inset) / (1 - 2 * inset), v = ((y % sq) / sq - inset) / (1 - 2 * inset);
      if (u >= 0 && u < 1 && v >= 0 && v < 1) {
        const f = sample(L.fill, u, v), l = sample(L.line, u, v);
        const fc = (white ? wFill : bFill).map((t) => t * 255), lc = (white ? wLine : bLine).map((t) => t * 255);
        c = c.map((v0, k) => v0 * (1 - f) + fc[k] * f).map((v0, k) => v0 * (1 - l) + lc[k] * l);
      }
    }
    const i = (y * W + x) * 4;
    img[i] = c[0]; img[i + 1] = c[1]; img[i + 2] = c[2]; img[i + 3] = 255;
  }
  writePNG(path.join(PREVIEW, "board_preview.png"), W, W, img);
}
console.log("textures written to " + OUT);
