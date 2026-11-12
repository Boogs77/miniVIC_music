'use strict';
// music.js - turns songs written as text into the tables of src/player.asm
//
// Track text (tokens separated by spaces, '|' is only for the eye):
//   c4:4  e#5:2  bb3      note, octave (C4 = middle C), length in 16ths (kept until changed)
//   r:4                   rest
//   ^:4                   tie: the previous note goes on
//   v12                   attack volume of the next notes
//   [ ... ]3              repeat 3 times (can be nested)
//   drums: k kick, s snare, h hi-hat, o open hat, x crash, t low tom, m high tom, c rim, '.' rest
// Lengths can be fractions (2/3 for a triplet 8th).
// Tempo: frames per 16th, a number or a function of the position in 16ths (accelerando, ritardando).

const CHROMA = { c: 0, d: 2, e: 4, f: 5, g: 7, a: 9, b: 11 };
const DRUMS = { k: 1, s: 2, h: 3, o: 4, x: 5, t: 6, m: 7, c: 8 };
const IDX_BASE = 23;                       // note index = MIDI - 23 (1 = C1 ... 84 = B7)

function expand(text) {                    // [ ... ]n repeats, innermost first
  let s = text.replace(/\|/g, ' ');
  const re = /\[([^\[\]]*)\](\d+)/;
  while (re.test(s)) s = s.replace(re, (_, body, n) => (' ' + body + ' ').repeat(+n));
  if (/[\[\]]/.test(s)) throw new Error('unbalanced [ ] in: ' + text.slice(0, 60));
  return s.trim().split(/\s+/).filter(Boolean);
}

function parseLen(t) {
  if (t.includes('/')) { const [a, b] = t.split('/'); return +a / +b; }
  return +t;
}

function midiOf(name, acc, oct) {
  let m = 12 * (oct + 1) + CHROMA[name];
  if (acc === '#') m++;
  if (acc === 'b') m--;
  return m;
}

function noteName(m) {
  const n = ['c', 'c#', 'd', 'd#', 'e', 'f', 'f#', 'g', 'g#', 'a', 'a#', 'b'][m % 12];
  return n + (Math.floor(m / 12) - 1);
}

// events: {k:'n', m:midi | drum, len} {k:'r', len} {k:'t', len} {k:'v', v}
function parse(text, drums = false) {
  const ev = [];
  let len = 4;
  for (const tok of expand(text)) {
    let m;
    if ((m = tok.match(/^v(\d+)$/))) { ev.push({ k: 'v', v: +m[1] }); continue; }
    const [head, lt] = tok.split(':');
    if (lt !== undefined) len = parseLen(lt);
    if (!(len > 0)) throw new Error('bad length: ' + tok);
    if (head === 'r' || (drums && head === '.')) { ev.push({ k: 'r', len }); continue; }
    if (head === '^') { ev.push({ k: 't', len }); continue; }
    if (drums) {
      if (!DRUMS[head]) throw new Error('unknown drum: ' + tok);
      ev.push({ k: 'n', m: DRUMS[head], len });
      continue;
    }
    if (!(m = head.match(/^([a-g])(#|b)?(\d)$/))) throw new Error('bad note: ' + tok);
    ev.push({ k: 'n', m: midiOf(m[1], m[2], +m[3]), len });
  }
  return ev;
}

// maps every note of a track text: fn(midi, position in 16ths) -> midi
function mapNotes(text, fn) {
  let len = 4, pos = 0;
  return expand(text).map(tok => {
    if (/^v\d+$/.test(tok)) return tok;
    const [head, lt] = tok.split(':');
    if (lt !== undefined) len = parseLen(lt);
    const at = pos;
    pos += len;
    const m = head.match(/^([a-g])(#|b)?(\d)$/);
    if (!m) return tok;
    return noteName(fn(midiOf(m[1], m[2], +m[3]), at)) + (lt !== undefined ? ':' + lt : '');
  }).join(' ');
}
const transpose = (text, n) => mapNotes(text, m => m + n);

// chord patterns: tokens R<oct> root, T third, F fifth, S seventh (or octave), O octave above, N ninth
const QUAL = { '': [4, 7, 12], m: [3, 7, 12], '7': [4, 7, 10], m7: [3, 7, 10], maj7: [4, 7, 11], dim: [3, 6, 9], sus4: [5, 7, 12] };
function chord(name) {
  const m = name.match(/^([A-G])(#|b)?(.*)$/);
  if (!m || !(m[3] in QUAL)) throw new Error('bad chord: ' + name);
  return { root: CHROMA[m[1].toLowerCase()] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0), iv: QUAL[m[3]] };
}
function chordPat(chords, pat) {
  return chords.map(cn => {
    const c = chord(cn);
    return pat.replace(/\b([RTFSON])(\d)(?=[\s:\]]|$)/g, (_, w, o) => {
      const r = 12 * (+o + 1) + c.root;
      const add = { R: 0, T: c.iv[0], F: c.iv[1], S: c.iv[2], O: 12, N: 14 }[w];
      return noteName(r + add);
    });
  }).join(' | ');
}

// absolute time in frames of a position (16ths), tempo = frames per 16th
function timeline(tempo) {
  if (typeof tempo === 'number') return p => p * tempo;
  const cache = new Map();
  return p => {
    if (cache.has(p)) return cache.get(p);
    const STEP = 1 / 24;
    let t = 0, x = 0;
    while (x + STEP <= p + 1e-9) { t += tempo(x + STEP / 2) * STEP; x += STEP; }
    t += tempo(x) * (p - x);
    cache.set(p, t);
    return t;
  };
}
// piecewise linear tempo through points [pos, frames per 16th]
function ramp(points) {
  return p => {
    if (p <= points[0][0]) return points[0][1];
    for (let i = 1; i < points.length; i++) {
      const [p1, v1] = points[i], [p0, v0] = points[i - 1];
      if (p < p1) return p1 === p0 ? v1 : v0 + (v1 - v0) * (p - p0) / (p1 - p0);
    }
    return points[points.length - 1][1];
  };
}

// one track -> bytes (note index / drum, frames), length in 16ths
function encode(events, T, drums, where) {
  const out = [];
  let pos = 0;
  const push = (code, frames) => {
    while (frames > 255) { out.push(code, 255); frames -= 255; code = 0xFE; }
    if (frames < 1) throw new Error(`${where}: an event is shorter than one frame at 16th ${pos}`);
    out.push(code, frames);
  };
  for (const e of events) {
    if (e.k === 'v') { out.push(0xFD, e.v); continue; }
    const frames = Math.round(T(pos + e.len)) - Math.round(T(pos));
    if (e.k === 'r') push(0, frames);
    else if (e.k === 't') push(0xFE, frames);
    else {
      let code = e.m;
      if (!drums) {
        code = e.m - IDX_BASE;
        if (code < 1 || code > 84) throw new Error(`${where}: note out of range ${noteName(e.m)}`);
        if (e.m > 96) console.warn(`  warning ${where}: ${noteName(e.m)} is very high (coarse tuning)`);
      }
      push(code, frames);
    }
    pos += e.len;
  }
  out.push(0xFF);
  return { bytes: out, len16: pos };
}

// repeated passages -> references: $FC lo hi n plays n events found earlier in the same track
// (only events written out in full, never starting with a tie: the player looks ahead for $FE)
// bytes -> byte tokens (numbers, or strings for the address of a reference), label = start of the track
function compress(bytes, label) {
  const ev = [];
  for (let i = 0; i + 1 < bytes.length; i += 2) ev.push(bytes[i] * 256 + bytes[i + 1]);
  const lit = new Array(ev.length).fill(-1);       // byte offset of each event written in full
  const out = [];
  let i = 0;
  while (i < ev.length) {
    let best = 0, bj = -1;
    if (ev[i] >> 8 !== 0xFE) {
      for (let j = 0; j < i; j++) {
        if (lit[j] < 0 || ev[j] !== ev[i]) continue;
        let n = 0;
        while (n < 255 && i + n < ev.length && j + n < i && ev[j + n] === ev[i + n] &&
               lit[j + n] === lit[j] + 2 * n) n++;
        if (n > best) { best = n; bj = j; }
      }
    }
    if (best >= 3) {
      const a = `${label}+${lit[bj]}`;
      out.push(0xFC, `<(${a})`, `>(${a})`, best);
      i += best;
    } else {
      lit[i] = out.length;
      out.push(ev[i] >> 8, ev[i] & 255);
      i++;
    }
  }
  out.push(0xFF);
  return out;
}

const TRACKS = ['lead', 'harm1', 'bass', 'harm2', 'counter', 'drums'];
const INST_DEF = {
  lead: { v: 13, fl: 8, dm: 7, vib: 16, gap: 1 },
  harm1: { v: 9, fl: 4, dm: 3, vib: 0, gap: 1 },
  bass: { v: 12, fl: 7, dm: 3, vib: 0, gap: 1 },
  harm2: { v: 8, fl: 4, dm: 3, vib: 0, gap: 1 },
  counter: { v: 10, fl: 6, dm: 7, vib: 16, gap: 1 },
};

const hex = b => (typeof b === 'string' ? b : '$' + b.toString(16).toUpperCase().padStart(2, '0'));
function byteLines(bytes, per = 16) {
  const l = [];
  for (let i = 0; i < bytes.length; i += per) l.push('  .byte ' + bytes.slice(i, i + per).map(hex).join(','));
  return l.join('\n');
}

// song -> { asm, frames, label }
function buildSong(song) {
  const T = timeline(song.tempo);
  const P = song.id.toUpperCase();
  const lines = [`; ---- ${song.title.join(' ')} (${song.author}) ----`, `SONG_${P}:`];
  const ptr = [], data = [], lens = {};
  let frames = 0, raw = 0, size = 0;
  for (const tr of TRACKS) {
    const text = song.tracks[tr];
    if (!text) { ptr.push('0'); continue; }
    const enc = encode(parse(text, tr === 'drums'), T, tr === 'drums', `${song.id}.${tr}`);
    lens[tr] = enc.len16;
    frames = Math.max(frames, Math.round(T(enc.len16)));
    const label = `S_${P}_${tr.toUpperCase()}`;
    const packed = compress(enc.bytes, label);
    raw += enc.bytes.length;
    size += packed.length;
    ptr.push(label);
    data.push(`${label}:`, byteLines(packed));
  }
  const vals = Object.values(lens);
  if (Math.max(...vals) !== Math.min(...vals)) {
    console.warn(`  warning ${song.id}: tracks of different length (16ths): ` +
      Object.entries(lens).map(([k, v]) => `${k} ${+v.toFixed(2)}`).join(', '));
  }
  lines.push('  .word ' + ptr.join(', '));
  for (const tr of TRACKS.slice(0, 5)) {
    const i = { ...INST_DEF[tr], ...(song.inst && song.inst[tr]) };
    lines.push(`  .byte ${i.v}, ${i.fl}, ${i.dm}, ${i.vib}, ${i.gap}      ; ${tr}`);
  }
  lines.push(...data);
  return { asm: lines.join('\n') + '\n', frames, len16: Math.max(...vals), bytes: size, raw };
}

// AY periods (1 MHz clock: f = 62500 / period) and the drum kit
function tablesAsm() {
  const lo = [0], hi = [0];
  for (let i = 1; i <= 84; i++) {
    const f = 440 * Math.pow(2, (i + IDX_BASE - 69) / 12);
    const p = Math.min(4095, Math.round(62500 / f));
    lo.push(p & 255); hi.push(p >> 8);
  }
  // drum:       -    kick  snare hat   open  crash tomL  tomH  rim
  const kit = {
    DR_NP:  [0, 0, 6, 1, 1, 2, 0, 0, 3],          // noise period
    DR_MIX: [0x12, 0x10, 0x00, 0x02, 0x02, 0x02, 0x10, 0x10, 0x00], // channel B: bit 1 tone off, bit 4 noise off
    DR_V0:  [0, 15, 14, 10, 10, 15, 14, 14, 12],  // volume at the hit
    DR_DM:  [0, 0, 0, 0, 1, 3, 1, 1, 0],          // the volume drops when (age AND mask) = 0
    DR_DS:  [0, 1, 1, 3, 1, 1, 1, 1, 4],          // by this much
    DR_TP:  [0, 280, 350, 0, 0, 0, 500, 330, 100],// tone period at the hit
    DR_SL:  [0, 70, 20, 0, 0, 0, 12, 8, 0],       // added to the period every frame
  };
  const out = [
    '; AY periods, 1 MHz clock (f = 62500 / period): index = MIDI note - 23 (1 = C1 ... 84 = B7), 0 = rest',
    'NT_LO:', byteLines(lo), 'NT_HI:', byteLines(hi),
    '; drums: 0 none, 1 kick, 2 snare, 3 hi-hat, 4 open hat, 5 crash, 6 low tom, 7 high tom, 8 rim',
  ];
  for (const [k, v] of Object.entries(kit)) {
    if (k === 'DR_TP') {
      out.push('DR_TPL: .byte ' + v.map(x => hex(x & 255)).join(','));
      out.push('DR_TPH: .byte ' + v.map(x => hex(x >> 8)).join(','));
    } else out.push(`${k}: .byte ` + v.map(hex).join(','));
  }
  return out.join('\n') + '\n';
}

module.exports = { compress, encode, timeline, parse, expand, mapNotes, transpose, chordPat, ramp, buildSong, tablesAsm, noteName, midiOf };
