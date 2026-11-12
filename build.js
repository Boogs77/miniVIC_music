'use strict';
// build.js - builds MiniVIC Sound
//
//   node build.js              every song + MiniVIC Jukebox: asm/, bin/, wav/, shots/
//   node build.js --no-wav     without the WAV previews
//   node build.js korobeiniki  only the songs named (and the jukebox)
//
// For each song: asm/<id>.asm (one file that assembles alone), bin/<id>.bin (loaded and started at $1000),
// wav/<id>.wav (the AY writes recorded in the emulator of MiniVIC Games and rendered) and
// shots/<id>.png. The jukebox: asm/minivic_jukebox.asm, bin/minivic_jukebox.bin, shots/minivic_jukebox_*.png
// (an application: loaded at $0FD0, started at $1000; copied to ../MiniVIC Apps as bin/jukebox.bin).
// vasm: the path in vasm.path, or the one of ../MiniVIC Games/vasm.path.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { buildSong, tablesAsm } = require('./tools/music');
const songs = require('./songs');

const ROOT = __dirname;
const GAMES = path.join(ROOT, '..', 'MiniVIC Games');
const args = process.argv.slice(2);
const noWav = args.includes('--no-wav');
const only = args.filter(a => !a.startsWith('--'));

const src = f => fs.readFileSync(path.join(ROOT, 'src', f), 'utf8').replace(/\r\n/g, '\n');
const vasmPath = ['vasm.path', path.join(GAMES, 'vasm.path')]
  .map(f => path.resolve(ROOT, f)).filter(f => fs.existsSync(f))
  .map(f => fs.readFileSync(f, 'utf8').split(/\r?\n/)[0].trim())[0];
if (!vasmPath || !fs.existsSync(vasmPath)) { console.error('vasm6502_oldstyle not found: write its path in vasm.path'); process.exit(1); }
for (const d of ['asm', 'bin', 'wav', 'shots', 'build']) fs.mkdirSync(path.join(ROOT, d), { recursive: true });

const str = (label, s) => `${label}: .byte "${s.replace(/"/g, "'")}", 0`;
const box = lines => {
  const w = 62;
  const row = t => ';   ' + t.padEnd(w - 3) + ';';
  return [';'.repeat(w + 2), ';' + ' '.repeat(w) + ';', ...lines.map(row), ';' + ' '.repeat(w) + ';', ';'.repeat(w + 2)].join('\n');
};
const common = () => [src('screen.asm'), src('player.asm'), src('font.asm'), tablesAsm()].join('\n');

function assemble(name, text) {
  const asm = path.join(ROOT, 'asm', name + '.asm');
  const bin = path.join(ROOT, 'bin', name + '.bin');
  fs.writeFileSync(asm, text.replace(/\n/g, '\r\n'));
  try {
    execFileSync(vasmPath, ['-Fbin', '-dotdir', '-c02', '-quiet', '-L', path.join(ROOT, 'build', name + '.lst'), '-o', bin, asm], { stdio: 'pipe' });
  } catch (e) {
    console.error(String(e.stdout || '') + String(e.stderr || ''));
    throw new Error('vasm failed on ' + name);
  }
  return fs.statSync(bin).size;
}

// ---------------- songs ----------------
const built = songs.map(s => ({ s, b: buildSong(s) }));
const report = [];
for (const { s, b } of built) {
  if (only.length && !only.includes(s.id)) continue;
  const text = [
    box([`MiniVIC Sound - ${s.title.filter(Boolean).join(' ')}`, s.author,
      'loaded and started at $1000 (song entry of the SD menu)',
      'fire = back to the menu; the song plays again and again',
      'built by build.js from songs.js: edit those, not this file']),
    src('defs.asm'), src('song_main.asm'), common(), b.asm,
    'SONG_HDR = SONG_' + s.id.toUpperCase(),
    str('TXT_T1', s.title[0]), str('TXT_T2', s.title[1] || ''), str('TXT_AU', s.author), '',
  ].join('\n');
  const size = assemble(s.id, text);
  report.push(`${s.id.padEnd(14)} ${(b.frames / 60).toFixed(1).padStart(5)} s  data ${String(b.bytes).padStart(5)} B  bin ${size} B`);
}

// ---------------- jukebox ----------------
{
  const N = built.length;
  const lab = (pre, i) => `${pre}${i}`;
  const t = [`NSONGS = ${N}`, `RND_MASK = ${(1 << Math.ceil(Math.log2(N))) - 1}`];
  const table = (name, f) => {
    t.push(`${name}_LO: .byte ` + built.map((_, i) => '<' + f(i)).join(','));
    t.push(`${name}_HI: .byte ` + built.map((_, i) => '>' + f(i)).join(','));
  };
  table('SONG', i => 'SONG_' + built[i].s.id.toUpperCase());
  table('T1', i => lab('JT1_', i));
  table('T2', i => lab('JT2_', i));
  table('AU', i => lab('JAU_', i));
  const items = ['RANDOM PLAY', ...built.map(({ s }, i) => `${String(i + 1).padStart(2)}  ${s.short}`), 'EXIT TO THE MENU'];
  t.push('ITEM_LO: .byte ' + items.map((_, i) => '<' + lab('JIT_', i)).join(','));
  t.push('ITEM_HI: .byte ' + items.map((_, i) => '>' + lab('JIT_', i)).join(','));
  built.forEach(({ s }, i) => {
    t.push(str(lab('JT1_', i), s.title[0]), str(lab('JT2_', i), s.title[1] || ''), str(lab('JAU_', i), s.author));
  });
  items.forEach((it, i) => t.push(str(lab('JIT_', i), it)));
  t.push(str('TXT_OFN', ` OF ${N}`));
  const text = [
    box(['MiniVIC Jukebox - every song of MiniVIC Sound',
      'list: up / down = choose, fire = play, RANDOM PLAY',
      'playing: fire = list, right = next, left = again',
      'loaded at $0FD0, started at $1000 (application, MiniVIC Apps)',
      'built by build.js from songs.js: edit those, not this file']),
    src('defs.asm'), src('jukebox_main.asm'), common(), ...built.map(x => x.b.asm), t.join('\n'), '',
  ].join('\n');
  const size = assemble('minivic_jukebox', text);
  report.push(`${'jukebox'.padEnd(14)} ${N} songs              bin ${size} B`);
}
console.log(report.join('\n'));

// ---------------- screenshots ----------------
const { MiniVIC } = require(path.join(GAMES, 'tools', 'minivic'));
function shot(name, out, frames, joyScript = []) {
  const load = name === 'minivic_jukebox' ? 0x0FD0 : 0x1000;   // the jukebox is an application
  const m = new MiniVIC(fs.readFileSync(path.join(ROOT, 'bin', name + '.bin')), load, 0x1000);
  for (let f = 0; f < frames; f++) {
    for (const [at, bits] of joyScript) if (at === f) m.joy[0] = bits;
    m.runFrame();
    if (m.cpu.pc >= 0xE000) throw new Error(`${name}: left the program at frame ${f}`);
  }
  fs.writeFileSync(path.join(ROOT, 'shots', out + '.png'), m.vdp.png(2));
  return m;
}
for (const { s } of built) {
  if (only.length && !only.includes(s.id)) continue;
  shot(s.id, s.id, 150);
}
shot('minivic_jukebox', 'minivic_jukebox_list', 60, [[30, 2], [32, 0], [34, 2], [36, 0]]);
shot('minivic_jukebox', 'minivic_jukebox_play', 220, [[30, 0x10], [32, 0]]);
console.log('screenshots in shots/');

// ---------------- WAV previews ----------------
if (!noWav) {
  for (const { s, b } of built) {
    if (only.length && !only.includes(s.id)) continue;
    const sec = (b.frames / 60 + 1).toFixed(1);
    execFileSync('node', [path.join(GAMES, 'tools', 'aywav.js'), path.join(ROOT, 'bin', s.id + '.bin'), sec,
      path.join(ROOT, 'wav', s.id + '.wav'), '1000', '1000'], { stdio: 'inherit' });
  }
}
