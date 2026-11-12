'use strict';
// test.js - checks the songs and MiniVIC Jukebox in the emulator of MiniVIC Games (no audio:
// it reads the state of the player from memory and the AY writes)
//
//   node tests/test.js
//
// songs:   each one ends after the expected number of frames, plays again, never leaves the program,
//          fire goes back to the BIOS menu ($FD0F), worst work per frame under 16,667 cycles
// jukebox: list moves and wraps, RANDOM PLAY never repeats a song twice in a row and plays all of them,
//          one song goes back to the list at the end, EXIT goes back to the BIOS menu
// It also checks that the AY periods written are the ones of the note table (A4 = 142).

const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const { MiniVIC } = require(path.join(ROOT, '..', 'MiniVIC Games', 'tools', 'minivic'));
const { buildSong } = require(path.join(ROOT, 'tools', 'music'));
const songs = require(path.join(ROOT, 'songs'));

let fails = 0;
const ok = (cond, msg) => { console.log((cond ? '  ok   ' : '  FAIL ') + msg); if (!cond) fails++; };

function symbols(name) {
  const s = {};
  for (const l of fs.readFileSync(path.join(ROOT, 'build', name + '.lst'), 'utf8').split(/\r?\n/)) {
    const m = l.match(/^([0-9A-F]{4}) (\w+)$/);
    if (m) s[m[2]] = parseInt(m[1], 16);
  }
  return s;
}

// machine + work meter: cycles from the end of a WAIT_VBL to the next call
function machine(name) {
  const sym = symbols(name);
  const load = name === 'minivic_jukebox' ? 0x0FD0 : 0x1000;   // the jukebox is an application
  const m = new MiniVIC(fs.readFileSync(path.join(ROOT, 'bin', name + '.bin')), load, 0x1000);
  m.sym = sym;
  m.mem.set([0x4C, 0x0F, 0xFD], 0xFD0F);                // JT_SHOW_MENU: the BIOS menu, here a JMP to itself
  m.worst = 0;
  m.ay = [];
  const write = m.write.bind(m);
  const latch = [0, 0];
  m.write = (a, v) => {
    if (a === 0xD384) latch[0] = v; else if (a === 0xD380) latch[1] = v;
    else if (a === 0xD385) m.ay.push([0, latch[0], v]); else if (a === 0xD381) m.ay.push([1, latch[1], v]);
    write(a, v);
  };
  let start = null;
  const step = m.cpu.step.bind(m.cpu);
  const waitEnd = sym.WAIT_VBL + 5;                      // LDA VREG / BPL: the next instruction
  m.cpu.step = () => {
    const pc = m.cpu.pc;
    if (pc === waitEnd) start = m.cpu.cycles;
    if (pc === sym.WAIT_VBL && start !== null) { m.worst = Math.max(m.worst, m.cpu.cycles - start); start = null; }
    step();
  };
  m.frames = (n, joy) => {
    for (let i = 0; i < n; i++) {
      if (joy !== undefined) m.joy[0] = joy;
      m.runFrame();
      if (m.cpu.pc >= 0xE000) return i;                  // left the program (BIOS)
    }
    return -1;
  };
  m.zp = a => m.mem[a];
  m.press = bits => { m.frames(2, bits); m.frames(2, 0); };
  return m;
}

const SYM_ZP = { CUR: 0x5E, PLAYING: 0x5F, SHUFFLE: 0x60, LAST: 0x61, STATE: 0x63 };
const MUS_ON = 0x7E72;

// ---------------- songs ----------------
for (const s of songs) {
  console.log(s.id);
  const b = buildSong(s);
  const m = machine(s.id);
  m.frames(30);                                           // set-up
  ok(m.mem[MUS_ON] === 1, 'playing after the set-up');
  let f = 0;
  while (m.mem[MUS_ON] === 1 && f < b.frames + 600) { if (m.frames(1) >= 0) break; f++; }
  ok(Math.abs(f - b.frames) <= 30, `ends after ${f} frames (expected about ${b.frames})`);
  m.frames(100);
  ok(m.mem[MUS_ON] === 1, 'plays again after the pause');
  ok(m.worst < 16667, `worst work per frame ${m.worst} cycles`);
  const left = m.frames(5, 0x10);
  ok(left >= 0 && m.cpu.pc === 0xFD0F, 'fire -> BIOS menu ($FD0F)');
  const vol = m.ay.filter(([, r, v]) => r >= 8 && r <= 10 && v > 15);
  ok(vol.length === 0, 'AY volumes within 0-15');
}

// note table: A4 is index 46, period 142
{
  const src = fs.readFileSync(path.join(ROOT, 'asm', 'jingles.asm'), 'utf8');
  const lo = src.match(/NT_LO:\r?\n((?:  \.byte .*\r?\n)+)/)[1].match(/\$[0-9A-F]{2}/g).map(h => parseInt(h.slice(1), 16));
  const hi = src.match(/NT_HI:\r?\n((?:  \.byte .*\r?\n)+)/)[1].match(/\$[0-9A-F]{2}/g).map(h => parseInt(h.slice(1), 16));
  console.log('note table');
  ok(lo.length === 85 && hi.length === 85, '85 entries');
  ok(lo[46] + 256 * hi[46] === 142, 'A4 = 142 (440 Hz)');
  let mono = true;
  for (let i = 2; i < 85; i++) if (lo[i] + 256 * hi[i] >= lo[i - 1] + 256 * hi[i - 1]) mono = false;
  ok(mono, 'periods fall note after note');
}

// references ($FC): every track, expanded the way the player does it, gives back the same events
{
  const { compress, encode, parse, timeline } = require(path.join(ROOT, 'tools', 'music'));
  console.log('references');
  let bad = 0, raw = 0, packed = 0;
  for (const s of songs) {
    for (const [tr, text] of Object.entries(s.tracks)) {
      const ev = encode(parse(text, tr === 'drums'), timeline(s.tempo), tr === 'drums', s.id).bytes;
      const pk = compress(ev, 'L');
      const at = off => { let b = 0; for (let i = 0; i < pk.length; i++) { if (b === off) return i; b++; } return -1; };
      const out = [];
      let p = 0, ret = -1, left = 0;
      while (pk[p] !== 0xFF) {
        if (pk[p] === 0xFC) { ret = p + 4; left = pk[p + 3]; p = at(+pk[p + 1].match(/\+(\d+)/)[1]); continue; }
        out.push(pk[p], pk[p + 1]);
        p += 2;
        if (left && --left === 0) p = ret;
      }
      out.push(0xFF);
      if (out.join() !== ev.join()) { bad++; console.log(`  ${s.id}.${tr} differs`); }
      raw += ev.length; packed += pk.length;
    }
  }
  ok(bad === 0, `all tracks unchanged (${raw} -> ${packed} bytes)`);
}

// ---------------- jukebox ----------------
console.log('minivic_jukebox');
{
  const m = machine('minivic_jukebox');
  const N = songs.length;
  m.frames(30);
  ok(m.zp(SYM_ZP.CUR) === 0, 'cursor on RANDOM PLAY');
  m.press(1);                                              // up: wraps to EXIT
  ok(m.zp(SYM_ZP.CUR) === N + 1, 'up from the top -> EXIT');
  m.press(2);
  ok(m.zp(SYM_ZP.CUR) === 0, 'down from EXIT -> RANDOM PLAY');
  m.press(2); m.press(2); m.press(2);
  ok(m.zp(SYM_ZP.CUR) === 3, 'down 3 times -> song 3');
  m.frames(30, 2);                                         // held: a step now, then after 20 and 26 frames
  ok(m.zp(SYM_ZP.CUR) === 6, `held for 30 frames -> 3 more steps (cursor ${m.zp(SYM_ZP.CUR)})`);
  m.frames(2, 0);
  m.press(1);
  // song 5 (arcade start): plays, ends, back to the list on that song
  m.press(0x10);
  ok(m.zp(SYM_ZP.PLAYING) === 4 && m.zp(SYM_ZP.SHUFFLE) === 0 && m.mem[MUS_ON] === 1, 'fire -> song 5 playing');
  m.frames(60 * 8);
  ok(m.mem[MUS_ON] === 0 && m.zp(SYM_ZP.CUR) === 5, 'at the end: back to the list, on song 5');
  fs.writeFileSync(path.join(ROOT, 'shots', 'test_jukebox_back.png'), m.vdp.png(2));
  // random play
  while (m.zp(SYM_ZP.CUR) !== 0) m.press(1);
  m.press(0x10);
  ok(m.zp(SYM_ZP.SHUFFLE) === 1 && m.mem[MUS_ON] === 1, 'RANDOM PLAY started');
  m.frames(120);
  fs.writeFileSync(path.join(ROOT, 'shots', 'minivic_jukebox_play.png'), m.vdp.png(2));
  let playWorst = 0;                                       // work while a song goes on (not the screen changes)
  for (let i = 0; i < 600; i++) {
    const p0 = m.zp(SYM_ZP.PLAYING), on0 = m.mem[MUS_ON];
    m.worst = 0;
    m.frames(1);
    if (on0 && m.mem[MUS_ON] && p0 === m.zp(SYM_ZP.PLAYING)) playWorst = Math.max(playWorst, m.worst);
  }
  ok(playWorst < 16667, `worst work per frame while playing ${playWorst} cycles`);
  const seq = [m.zp(SYM_ZP.PLAYING)];
  for (let i = 0; i < 160; i++) { m.press(8); m.frames(3); seq.push(m.zp(SYM_ZP.PLAYING)); }
  const repeats = seq.filter((x, i) => i && x === seq[i - 1]).length;
  ok(repeats === 0, 'right = next random song, never the same twice in a row');
  ok(new Set(seq).size === N, `all ${N} songs come out (${seq.slice(0, 20).join(' ')} ...; missing: ${[...Array(N).keys()].filter(k => !seq.includes(k)).join(' ') || 'none'})`);
  // a random song that ends goes on to another one
  m.press(0x10);                                            // back to the list
  ok(m.mem[MUS_ON] === 0, 'fire -> back to the list, silence');
  m.press(0x10);                                            // RANDOM PLAY again (cursor still there)
  const first = m.zp(SYM_ZP.PLAYING);
  let guard = 0;
  while (m.zp(SYM_ZP.PLAYING) === first && guard++ < 60 * 100) m.frames(1);
  m.frames(10);
  ok(m.zp(SYM_ZP.PLAYING) !== first && m.mem[MUS_ON] === 1 && m.zp(SYM_ZP.SHUFFLE) === 1, `after song ${first + 1} ends, random play goes on with song ${m.zp(SYM_ZP.PLAYING) + 1}`);
  // exit
  m.press(0x10);
  m.press(1);                                              // RANDOM PLAY -> EXIT
  const left = m.frames(5, 0x10);
  ok(left >= 0 && m.cpu.pc === 0xFD0F, 'EXIT -> BIOS menu ($FD0F)');
}

console.log(fails ? `${fails} FAILED` : 'ALL OK');
process.exit(fails ? 1 : 0);
