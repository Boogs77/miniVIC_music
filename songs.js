'use strict';
// songs.js - the songs of MiniVIC Sound, written as text for tools/music.js
//
// Public domain works (composers dead for more than 70 years, folk tunes) are arranged here from
// scratch; the other songs are original. Each song: id, title (2 lines), author, short name for
// the jukebox list, tempo (frames per 16th), instruments, tracks.

const { transpose, chordPat, ramp, mapNotes, midiOf } = require('./tools/music');

const songs = [];

// =====================================================================
// 1. In the Hall of the Mountain King - Edvard Grieg (1875), B minor
//    the theme 7 times, ever faster and louder, then the final chords
// =====================================================================
{
  const THEME = 'b3:2 c#4 d4 e4 f#4 d4 f#4:4 | f4:2 c#4 f4:4 e4:2 c4 e4:4 | ' +
                'b3:2 c#4 d4 e4 f#4 d4 f#4 b4 | a4 f#4 d4 f#4 a4:8';
  const BASS = 'b1:4 f#2 b1 f#2 | b1 f#2 b1 f#2 | b1 f#2 b1 f#2 | f#1 c#2 f#1 c#2';
  const H1 = 'r:2 d4:2 r d4 r d4 r d4 | r c#4 r c#4 r c4 r c4 | r d4 r d4 r d4 r d4 | r f#3 r f#3 r f#3 r f#3';
  const H2 = 'r:2 f#3:2 r f#3 r f#3 r f#3 | r f3 r f3 r e3 r e3 | r f#3 r f#3 r f#3 r f#3 | r d3 r d3 r d3 r d3';
  const R64 = 'r:16 r r r';
  const D_A = '[k:4 h k h]4';
  const D_B = '[k:2 h s h k h s h]4';
  const D_C = '[k:2 h s h k k s h]3 k:2 s s s s:1 s s s s s s s';
  const D_X = 'x:2 h s h k h s h [k:2 h s h k k s h]2 k:2 s s s s:1 s s s s s s s';
  // sections: 1 alone, 2 + chords, 3 octave up + kick, 4 in F# minor, 5-7 lead + octave below, end
  const lead = [THEME, THEME, transpose(THEME, 12), transpose(THEME, 7),
    'v14 ' + transpose(THEME, 12), transpose(THEME, 12), 'v15 ' + transpose(THEME, 12),
    'b4:2 r:6 b4:2 r:6 | b4:2 r:2 f#4:2 r:2 b4:2 r:2 f#4:2 r:2 | b4:16'].join(' | ');
  const counter = [transpose(THEME, -12), transpose(THEME, -12), THEME, transpose(THEME, -5),
    THEME, THEME, THEME,
    'b3:2 r:6 b3:2 r:6 | b3:2 r:2 f#3:2 r:2 b3:2 r:2 f#3:2 r:2 | b3:16'].join(' | ');
  songs.push({
    id: 'mountain_king', short: 'MOUNTAIN KING',
    title: ['IN THE HALL OF THE', 'MOUNTAIN KING'], author: 'EDVARD GRIEG 1875',
    tempo: ramp([[0, 13], [64, 12], [128, 11], [192, 10], [256, 9], [320, 7.5], [384, 6], [448, 5], [464, 5.5], [496, 11]]),
    inst: {
      lead: { v: 13, fl: 0, dm: 1, vib: 0, gap: 1 },
      harm1: { v: 9, fl: 0, dm: 1, gap: 1 },
      bass: { v: 12, fl: 3, dm: 3, gap: 1 },
      harm2: { v: 8, fl: 0, dm: 1, gap: 1 },
      counter: { v: 9, fl: 0, dm: 1, vib: 0, gap: 1 },
    },
    tracks: {
      lead, counter,
      bass: [BASS, BASS, BASS, transpose(BASS, 7), BASS, BASS, BASS,
        'b1:2 r:6 b1:2 r:6 | b1:2 r:2 f#1:2 r:2 b1:2 r:2 f#1:2 r:2 | b1:16'].join(' | '),
      harm1: [R64, H1, H1, transpose(H1, 7), H1, H1, H1,
        'd4:2 r:6 d4:2 r:6 | d4:2 r:2 c#4:2 r:2 d4:2 r:2 c#4:2 r:2 | d4:16'].join(' | '),
      harm2: [R64, H2, H2, transpose(H2, 7), H2, H2, H2,
        'f#3:2 r:6 f#3:2 r:6 | f#3:2 r:2 a#3:2 r:2 f#3:2 r:2 a#3:2 r:2 | f#3:16'].join(' | '),
      drums: [R64, R64, D_A, D_A, D_B, D_C, D_X,
        'x:2 .:6 x:2 .:6 | k:2 .:2 k:2 .:2 k:2 .:2 s:2 s:2 | x:16'].join(' | '),
    },
  });
}

// =====================================================================
// 2. Korobeiniki - Russian folk song (19th century), A minor
//    our own arrangement: polka oom-pah, a third below, faster and faster
// =====================================================================
{
  const A = 'e5:4 b4:2 c5 d5:4 c5:2 b4 | a4:4 a4:2 c5 e5:4 d5:2 c5 | b4:6 c5:2 d5:4 e5:4 | c5:4 a4:4 a4:8';
  const B = 'r:2 d5:4 f5:2 a5:4 g5:2 f5 | e5:6 c5:2 e5:4 d5:2 c5 | b4:4 b4:2 c5 d5:4 e5:4 | c5:4 a4:4 a4:4 r:4';
  const CH = ['E', 'Am', 'E', 'Am', 'Dm', 'Am', 'E', 'Am'];
  const MEL = A + ' | ' + B;
  // diatonic third below in A minor, G -> G# over the E chord
  const SCALE = [9, 11, 0, 2, 4, 5, 7];
  const third = mapNotes(MEL, (m, pos) => {
    let pc = m % 12; if (pc === 8) pc = 7;
    const d = SCALE.indexOf(pc);
    if (d < 0) return m - 3;
    const t = SCALE[(d + 5) % 7];
    let r = m - ((pc - t + 12) % 12);
    if (r % 12 === 7 && CH[Math.floor(pos / 16) % 8] === 'E') r++;
    return r;
  });
  const OOM = chordPat(CH, 'R2:4 r:4 F1:4 r:4');
  const PAH1 = chordPat(CH, 'r:4 T3:4 r:4 T3:4');
  const PAH2 = chordPat(CH, 'r:4 F3:4 r:4 F3:4');
  const INTRO_B = 'a2:4 r:4 e2:4 r:4 | a2:4 r:4 e2:4 r:4';
  const INTRO_H = 'r:4 c4:4 r:4 c4:4 | r:4 c4:4 r:4 c4:4';
  const INTRO_H2 = 'r:4 e4:4 r:4 e4:4 | r:4 e4:4 r:4 e4:4';
  const R32 = 'r:16 r:16';
  const D1 = '[k:4 h k h]8';
  const D2 = '[k:2 h s h k h s h]7 k:2 h s s:1 s s s s s s s s s';
  const END_L = 'a5:2 r:2 e5:2 r:2 a5:4 r:4';
  songs.push({
    id: 'korobeiniki', short: 'KOROBEINIKI',
    title: ['KOROBEINIKI', ''], author: 'RUSSIAN FOLK SONG',
    tempo: ramp([[0, 9], [32, 9], [160, 8], [288, 7], [416, 6], [544, 4.5], [560, 7]]),
    inst: {
      lead: { v: 13, fl: 6, dm: 3, vib: 14, gap: 1 },
      counter: { v: 9, fl: 4, dm: 3, vib: 14, gap: 1 },
      harm1: { v: 8, fl: 2, dm: 1, gap: 1 },
      harm2: { v: 7, fl: 2, dm: 1, gap: 1 },
      bass: { v: 12, fl: 4, dm: 3, gap: 1 },
    },
    tracks: {
      lead: [R32, MEL, MEL, transpose(MEL, 12), 'v15 ' + transpose(MEL, 12), END_L].join(' | '),
      counter: [R32, transpose(MEL, -12), third, MEL, transpose(third, 12), 'a4:2 r:2 c5:2 r:2 e5:4 r:4'].join(' | '),
      bass: [INTRO_B, OOM, OOM, OOM, OOM, 'a2:2 r:2 e2:2 r:2 a1:4 r:4'].join(' | '),
      harm1: [INTRO_H, PAH1, PAH1, PAH1, PAH1, 'c4:2 r:2 c4:2 r:2 c4:4 r:4'].join(' | '),
      harm2: [INTRO_H2, PAH2, PAH2, PAH2, PAH2, 'e4:2 r:2 e4:2 r:2 a4:4 r:4'].join(' | '),
      drums: ['k:4 h k h | k:4 h k s', D1, D1, D2, D2, 'x:2 .:2 k:2 .:2 x:8'].join(' | '),
    },
  });
}

// =====================================================================
// 3. The Entertainer - Scott Joplin (1902), C major, 2/4
//    the first strain twice, honky-tonk piano (lead doubled and detuned)
// =====================================================================
{
  const M1 = 'e5:1 c6:2 e5:1 c6:2 e5:1 c6:1';
  const M2 = '^:4 c6:1 d6 d#6 e6';
  const M3 = 'c6:1 d6 e6:2 b5:1 d6:2 c6:1';
  const P1 = [M1, M2, M3, '^:6 d5:1 d#5', M1, '^:6 a5:1 g5', 'f#5:1 a5 c6 e6:2 d6:1 c6 a5', 'd6:6 d5:1 d#5'];
  const P2a = [M1, M2, M3, '^:6 d5:1 d#5'];
  const P2b = [M1, M2, M3, '^:6 c6:1 d6', 'c6:1 e6 c6 d6 c6 e6 c6 d6', 'c6:1 e6 b5:1 d6:2 c6:1 ^:2', '^:4 g5:2 e5:2', 'c5:4 r:4'];
  const STRAIN1 = [...P1, ...P2a].join(' | ');
  const STRAIN2 = [...P1, ...P2b].join(' | ');
  const CH1 = ['C', 'C', 'G7', 'C', 'C', 'C', 'D7', 'G7', 'C', 'C', 'G7', 'C'];
  const CH2 = ['C', 'C', 'G7', 'C', 'C', 'C', 'D7', 'G7', 'C', 'C', 'G7', 'C', 'C', 'G7', 'C', 'C'];
  const bass = ch => chordPat(ch, 'R2:2 r:2 F1:2 r:2');
  const h1 = ch => chordPat(ch, 'r:2 T3:2 r:2 T3:2');
  const h2 = ch => chordPat(ch, 'r:2 F3:2 r:2 S3:2');
  const PICK = 'r:6 d5:1 d#5';
  songs.push({
    id: 'entertainer', short: 'THE ENTERTAINER',
    title: ['THE ENTERTAINER', ''], author: 'SCOTT JOPLIN 1902',
    tempo: ramp([[0, 10], [200, 10], [232, 13]]),
    inst: {
      lead: { v: 13, fl: 5, dm: 3, vib: 0, gap: 1 },
      bass: { v: 12, fl: 4, dm: 3, gap: 1 },
      harm1: { v: 9, fl: 3, dm: 3, gap: 1 },
      harm2: { v: 8, fl: 3, dm: 3, gap: 1 },
    },
    tracks: {
      lead: [PICK, STRAIN1, STRAIN2].join(' | '),
      bass: ['r:8', bass(CH1), bass(CH2)].join(' | ').replace(/r:2 g1:2 r:2$/, 'r:2 c2:2 r:2'),
      harm1: ['r:8', h1(CH1), h1(CH2)].join(' | '),
      harm2: ['r:8', h2(CH1), h2(CH2)].join(' | '),
    },
  });
}

// =====================================================================
// 4. Toccata in D minor BWV 565 - J. S. Bach (about 1704)
//    organ: the opening three times, the diminished chord, a run, the cadence
// =====================================================================
{
  const OPEN = 'a5:1 g5:1 a5:10 r:4 g5:1 f5 e5 d5 c#5:4 d5:16 r:8';     // 48
  const RUN = 'a5:1 g5 f5 e5 g5 f5 e5 d5 f5 e5 d5 c#5 e5 d5 c#5 b4 ' +
              'd5 c#5 b4 a4 c#5 b4 a4 g4 f4 e4 d4 c#4 d4:4';            // 32
  const RUN2 = transpose('a5:1 g5 f5 e5 g5 f5 e5 d5 f5 e5 d5 c#5 e5 d5 c#5 b4', 0) +
               ' d5:1 e5 f5 g5 a5 b5 c#6 d6 e6:2 c#6:2 a5:4';               // 32
  const CHORD = 48 + 32;                                                     // build-up 48 + Dm 32
  songs.push({
    id: 'toccata', short: 'TOCCATA IN D MINOR',
    title: ['TOCCATA AND FUGUE', 'IN D MINOR'], author: 'J.S. BACH 1704',
    tempo: ramp([[0, 6], [144, 6], [144 + CHORD, 7], [144 + CHORD + 64, 6], [144 + CHORD + 64 + 16, 9], [144 + CHORD + 64 + 48, 11]]),
    inst: {
      lead: { v: 13, fl: 11, dm: 15, vib: 0, gap: 1 },
      counter: { v: 11, fl: 9, dm: 15, vib: 0, gap: 1 },
      harm1: { v: 10, fl: 8, dm: 15, gap: 0 },
      harm2: { v: 10, fl: 8, dm: 15, gap: 0 },
      bass: { v: 12, fl: 10, dm: 15, gap: 0 },
    },
    tracks: {
      lead: [OPEN, transpose(OPEN, -12), transpose(OPEN, -24),
        'r:18 bb4:30 | d5:32', RUN, RUN2,
        'g5:8 f5:8 | e5:16 c#5:16 | d5:32'].join(' | '),
      counter: [transpose(OPEN, -12), transpose(OPEN, -24), 'r:48',
        'r:12 g4:36 | a4:32', transpose(RUN, -12), transpose(RUN2, -12),
        'bb4:8 a4:8 | g4:16 e4:16 | f4:32'].join(' | '),
      harm1: ['r:16 r:16 r:16 | r:16 r:16 r:16 | r:16 r:16 r:16', 'c#4:48 | d4:32', 'r:32 | r:32',
        'd5:16 | c#5:16 a4:16 | a4:32'].join(' | '),
      harm2: ['r:48 | r:48 | r:48', 'r:6 e4:42 | f4:32', 'r:32 | r:32',
        'bb4:16 | g4:16 e4:16 | d4:32'].join(' | '),
      bass: ['r:28 d3:20 | r:28 d2:20 | r:28 d2:20', 'd2:48 | d2:32', 'd2:32 | a1:32',
        'g1:16 | a1:32 | d1:32'].join(' | '),
    },
  });
}

// =====================================================================
// 5. Arcade Start - original jingle, C major
// =====================================================================
songs.push({
  id: 'arcade_start', short: 'ARCADE START',
  title: ['ARCADE START', ''], author: 'ORIGINAL - MINIVIC SOUND',
  tempo: 4,
  inst: {
    lead: { v: 14, fl: 9, dm: 3, vib: 10, gap: 1 },
    harm1: { v: 8, fl: 4, dm: 1, gap: 0 },
    bass: { v: 12, fl: 7, dm: 3, gap: 1 },
  },
  tracks: {
    lead: 'r:8 | g5:2 c6 g5 e5 f5 a5 c6:4 | b5:2 a5 g5 f5 e5 g5 c6:4 | ' +
          'd6:3 c6:1 b5:2 g5:2 a5:2 b5:2 c6:2 d6:2 | e6:4 c6:2 g5:2 c6:8',
    harm1: 'r:8 | ' + chordPat(['C', 'F', 'G', 'C', 'G', 'G'], '[R4:1 T4 F4 T4]2') + ' | ' +
           chordPat(['C'], '[R4:1 T4 F4 T4]2') + ' | c5:8',
    bass: 'r:8 | ' + chordPat(['C', 'F', 'G', 'C', 'G', 'G', 'C'], 'R2:2 F2 O2 F2') + ' | c2:8',
    drums: 's:1 s s s s s s s | [k:2 h s h k k s h]3 | k:2 h s h x:8',
  },
});

// =====================================================================
// 6. Star Patrol - original shoot'em up theme, A minor
// =====================================================================
{
  const A = 'e5:4 a5:4 c6:4 b5:2 a5:2 | g5:2 a5:2 e5:4 r:4 c5:2 d5:2 | f5:4 a5:4 c6:4 a5:2 c6:2 | d6:6 c6:2 a5:4 f5:4 | ' +
            'g5:4 b5:4 d6:4 c6:2 b5:2 | a5:2 b5:2 g5:4 r:4 d5:2 e5:2 | g#5:4 b5:4 e6:4 d6:2 b5:2 | e6:12 r:4';
  const B = 'a5:2 c6 e6 c6 a5 c6 e6 g6 | f6:4 e6:4 c6:4 a5:4 | g5:2 b5 d6 b5 g5 b5 d6 f6 | e6:4 d6:4 b5:4 g#5:4 | ' +
            'a5:2 c6 e6 c6 a5 c6 e6 a6 | a6:4 g6:4 f6:4 c6:4 | d6:4 e6:4 f6:4 g6:4 | g#6:8 e6:8';
  const CA = ['Am', 'Am', 'F', 'F', 'G', 'G', 'E', 'E'];
  const CB = ['Am', 'F', 'G', 'E', 'Am', 'F', 'G', 'E'];
  const bass = ch => chordPat(ch, '[R1:2 O1]4');
  const arp = ch => chordPat(ch, '[R4:1 T4 F4 T4]4');
  const pad = ch => chordPat(ch, 'T4:16');
  const DA = '[k:2 h s h k h s h]7 k:2 h s h t:1 t m m s s s s';
  const DB = '[k:2 h s k k h s h]7 k:2 s s s s:1 s s s s s s s';
  songs.push({
    id: 'star_patrol', short: 'STAR PATROL',
    title: ['STAR PATROL', ''], author: 'ORIGINAL - MINIVIC SOUND',
    tempo: 6,
    inst: {
      lead: { v: 13, fl: 9, dm: 3, vib: 12, gap: 1 },
      harm1: { v: 7, fl: 3, dm: 1, gap: 0 },
      bass: { v: 12, fl: 7, dm: 1, gap: 1 },
      harm2: { v: 6, fl: 5, dm: 15, gap: 0 },
    },
    tracks: {
      lead: ['r:16 r:16', A, B, 'v14', A, B, 'a5:16'].join(' | '),
      harm1: ['r:16 r:16', arp(CA), arp(CB), arp(CA), arp(CB), 'a4:16'].join(' | '),
      harm2: ['r:16 r:16', pad(CA), pad(CB), pad(CA), pad(CB), 'c5:16'].join(' | '),
      bass: [bass(['Am', 'Am']), bass(CA), bass(CB), bass(CA), bass(CB), 'a1:16'].join(' | '),
      drums: ['k:2 h s h k:1 k h:2 s h | k:2 h s h k:1 k s:2 s:1 s s s', DA, DB, DA, DB, 'x:16'].join(' | '),
    },
  });
}

// =====================================================================
// 7. Neon Drive - original synth-pop, D minor (Dm Bb F C)
//    the counter melody is an echo of the lead, 3 sixteenths later
// =====================================================================
{
  const V = 'a4:6 d5:2 f5:4 e5:4 | d5:8 r:4 a4:2 c5:2 | d5:6 f5:2 bb5:4 a5:4 | f5:8 r:4 d5:2 f5:2 | ' +
            'a5:6 c6:2 a5:4 f5:4 | g5:4 a5:4 f5:4 c5:4 | e5:6 g5:2 c6:4 bb5:4 | a5:2 g5:2 e5:12';
  const C = 'f5:4 a5:4 d6:8 | c6:4 a5:4 f5:8 | f5:4 bb5:4 d6:8 | c6:4 bb5:4 a5:8 | ' +
            'c6:4 a5:4 f6:8 | e6:4 c6:4 a5:8 | g5:4 c6:4 e6:4 g6:4 | e6:8 d6:8';
  const CH = ['Dm', 'Dm', 'Bb', 'Bb', 'F', 'F', 'C', 'C'];
  const bass = ch => chordPat(ch, '[R2:2 O2]4');
  const arp = ch => chordPat(ch, '[R3:1 F3 O3 T4]4');
  const pad = ch => chordPat(ch, 'T4:16');
  const INTRO = ['Dm', 'Bb', 'F', 'C'];
  const DV = '[k:2 h s h k h s o]7 k:2 h s h k k s s';
  const DC = 'x:2 h s h k h s h [k:2 h s h k k s h]6 k:2 s s s s:1 s s s s s s s';
  const LEAD = ['r:16 r:16 r:16 r:16', V, C, V, C, 'd5:16 | d5:16'].join(' | ');
  songs.push({
    id: 'neon_drive', short: 'NEON DRIVE',
    title: ['NEON DRIVE', ''], author: 'ORIGINAL - MINIVIC SOUND',
    tempo: 8,
    inst: {
      lead: { v: 13, fl: 10, dm: 7, vib: 16, gap: 0 },
      counter: { v: 8, fl: 5, dm: 7, vib: 16, gap: 0 },
      harm1: { v: 8, fl: 3, dm: 1, gap: 0 },
      bass: { v: 12, fl: 6, dm: 3, gap: 1 },
      harm2: { v: 6, fl: 5, dm: 15, vib: 20, gap: 0 },
    },
    tracks: {
      lead: LEAD,
      counter: 'r:3 ' + LEAD.replace(/d5:16$/, 'd5:13'),
      harm1: [arp(INTRO), arp(CH), arp(CH), arp(CH), arp(CH), arp(['Dm']), 'd4:16'].join(' | '),
      harm2: [pad(INTRO), pad(CH), pad(CH), pad(CH), pad(CH), 'f4:32'].join(' | '),
      bass: [bass(INTRO), bass(CH), bass(CH), bass(CH), bass(CH), bass(['Dm']), 'd2:16'].join(' | '),
      drums: ['[k:2 h s h k h s h]3 k:2 h s h t:1 t m m s s s s', DV, DC, DV, DC, 'x:16 | .:16'].join(' | '),
    },
  });
}

// =====================================================================
// 8. Jingles - original: level clear, then game over
// =====================================================================
{
  const GAP = 24;
  songs.push({
    id: 'jingles', short: 'JINGLES',
    title: ['LEVEL CLEAR', 'AND GAME OVER'], author: 'ORIGINAL - MINIVIC SOUND',
    tempo: p => (p < 32 + GAP ? 4 : 9),
    inst: {
      lead: { v: 14, fl: 8, dm: 3, vib: 12, gap: 1 },
      harm1: { v: 8, fl: 4, dm: 3, gap: 0 },
      harm2: { v: 7, fl: 4, dm: 7, gap: 0 },
      bass: { v: 12, fl: 6, dm: 3, gap: 1 },
    },
    tracks: {
      lead: `c5:2 g5 e5 c6 b5 d6 g6:4 | f6:2 e6 d6 b5 c6:8 | r:${GAP} | ` +
            'e5:4 d#5 d5 c#5 | c5:8 b4:4 g#4:4 | a4:16',
      harm1: `c4:1 e4 g4 e4 c4 e4 g4 e4 b3 d4 g4 d4 b3 d4 g4 d4 | b3 d4 g4 d4 b3 d4 f4 d4 c4:8 | r:${GAP} | ` +
             'c4:16 | c4:8 b3:8 | c4:16',
      harm2: `e4:8 d4:8 | d4:8 e4:8 | r:${GAP} | a3:16 | a3:8 g#3:8 | e3:16`,
      bass: `c2:4 g2 g1 d2 | g1:4 d2 c2:8 | r:${GAP} | a2:16 | f2:8 e2:8 | a1:16`,
      drums: `k:2 h s h k h s h | k:2 h s h x:8 | .:${GAP} | t:16 | t:8 t:8 | x:16`,
    },
  });
}

// =====================================================================
// 9. Flight of the Bumblebee - N. Rimsky-Korsakov (1900), A minor, 2/4
//    the chromatic descent, the theme in A minor and D minor, two octaves
// =====================================================================
{
  const INTRO = 'e6:1 d#6 d6 c#6 d6 c#6 c6 b5 | c6 b5 a#5 a5 g#5 g5 f#5 f5 | ' +
                'e5 d#5 d5 c#5 d5 c#5 c5 b4 | c5 b4 a#4 a4 g#4 g4 f#4 f4';
  const T1 = 'a4:1 g#4 g4 f#4 f4 a#4 a4 g#4 | a4 g#4 g4 f#4 f4 f#4 g4 g#4';
  const T = [T1, T1, 'a4:1 g#4 g4 f#4 g4 f#4 f4 e4 | f4 f#4 g4 g#4 a4 a#4 a4 g#4',
    'a4:1 g#4 g4 f#4 g4 f#4 f4 e4 | f4 f#4 g4 g#4 a4 a#4 b4 c5'].join(' | ');          // 8 bars
  const CODA = 'a4:1 a#4 b4 c5 c#5 d5 d#5 e5 | f5 f#5 g5 g#5 a5:4 | e5:2 r:2 a4:2 r:2 | a5:2 r:6';
  const CA = ['Am', 'E7', 'Am', 'E7', 'Am', 'E7', 'Am', 'E7'];
  const CD = ['Dm', 'A7', 'Dm', 'A7', 'Dm', 'A7', 'Dm', 'A7'];
  const CC = ['Am', 'E7', 'Am', 'Am'];
  const acc = (pat, intro) => [intro, ...[CA, CA, CD, CD, CA].map(c => chordPat(c, pat)), chordPat(CC, pat)].join(' | ');
  songs.push({
    id: 'bumblebee', short: 'FLIGHT OF THE BUMBLEBEE',
    title: ['FLIGHT OF THE', 'BUMBLEBEE'], author: 'N. RIMSKY-KORSAKOV 1900',
    tempo: 5,
    inst: {
      lead: { v: 13, fl: 9, dm: 7, vib: 0, gap: 0 },
      harm1: { v: 8, fl: 3, dm: 1, gap: 1 },
      harm2: { v: 7, fl: 3, dm: 1, gap: 1 },
      bass: { v: 12, fl: 5, dm: 1, gap: 1 },
    },
    tracks: {
      lead: [INTRO, T, transpose(T, 12), transpose(T, 5), transpose(T, 17), T, CODA].join(' | '),
      bass: acc('R2:2 r:2 F1:2 r:2', 'e2:8 | e2:8 | e2:8 | e2:8'),
      harm1: acc('r:2 T3:2 r:2 T3:2', 'r:32'),
      harm2: acc('r:2 F3:2 r:2 F3:2', 'r:32'),
      drums: ['[h:1 h h h h h h h]4', '[k:2 h s h]40', 'k:2 h s h | k:2 h s s | x:4 .:4 | k:2 .:6'].join(' | '),
    },
  });
}

// =====================================================================
// 10. Rondo alla turca (Piano Sonata K. 331) - W. A. Mozart (1783), A minor, 2/4
// =====================================================================
{
  const A7 = 'c5:2 r:2 d5:1 c5 b4 c5 | e5:2 r:2 f5:1 e5 d#5 e5 | b5:1 a5 g#5 a5 b5 a5 g#5 a5 | c6:4 a5:2 b5:2 | ' +
             'c6:2 b5:2 a5:2 g#5:2 | a5:2 e5:2 f5:2 d5:2 | c5:4 b4:3 a4:1';
  const AP = A7 + ' | a4:4 b4:1 a4 g#4 a4';                 // the next A follows
  const AR = A7 + ' | a4:4 r:4';
  const B = 'e5:2 f5:2 g5:2 g5:2 | a5:1 g5 f5 e5 d5:4 | e5:2 f5:2 g5:2 g5:2 | a5:1 g5 f5 e5 d5:4 | ' +
            'c5:2 d5:2 e5:2 e5:2 | f5:1 e5 d5 c5 b4:4 | c5:2 d5:2 e5:2 e5:2 | f5:1 e5 d5 c5 b4 a4 g#4 a4';
  const CODA = 'c#5:2 e5:2 a5:2 e5:2 | c#5:2 e5:2 a5:2 e5:2 | c#6:2 a5:2 e5:2 c#5:2 | a5:4 r:4';
  const CHA = ['Am', 'Am', 'E', 'Am', 'Am', 'Dm', 'E', 'Am'];
  const CHB = ['C', 'G', 'C', 'G', 'Am', 'E', 'Am', 'E'];
  const FORM = [CHA, CHA, CHB, CHA, CHA, CHB, CHA, ['A', 'A', 'A', 'A']];
  const acc = pat => ['r:4', ...FORM.map(c => chordPat(c, pat))].join(' | ');
  songs.push({
    id: 'alla_turca', short: 'RONDO ALLA TURCA',
    title: ['RONDO ALLA TURCA', ''], author: 'W.A. MOZART 1783',
    tempo: ramp([[0, 6], [452, 6], [484, 9]]),
    inst: {
      lead: { v: 13, fl: 5, dm: 3, vib: 0, gap: 1 },
      bass: { v: 12, fl: 4, dm: 3, gap: 1 },
      harm1: { v: 8, fl: 3, dm: 3, gap: 1 },
      harm2: { v: 7, fl: 3, dm: 3, gap: 1 },
    },
    tracks: {
      lead: ['b4:1 a4 g#4 a4', AP, AR, B, AP, AR, B, AR, CODA].join(' | '),
      bass: acc('R2:2 r:2 F1:2 r:2'),
      harm1: acc('r:2 T3:2 T3:2 T3:2'),
      harm2: acc('r:2 F3:2 F3:2 F3:2'),
      drums: ['.:4', '[k:2 h k h]56', 'k:2 h k h | k:2 h k h | k:2 s s s | x:4 .:4'].join(' | '),
    },
  });
}

// =====================================================================
// 11. Can-can (Galop infernal, Orpheus in the Underworld) - J. Offenbach (1858), C major, 2/4
//    three times, the last two an octave up and faster
// =====================================================================
{
  const P6 = 'c5:8 | d5:2 f5:2 e5:2 d5:2 | g5:4 g5:4 | g5:2 a5:2 e5:2 f5:2 | d5:4 d5:4 | d5:2 f5:2 e5:2 d5:2';
  const P1 = P6 + ' | c5:2 c6:2 b5:2 a5:2 | g5:2 f5:2 e5:2 d5:2';
  const P2 = P6 + ' | c5:2 g4:2 d5:2 e5:2 | c5:8';
  const P = P1 + ' | ' + P2;
  const CH = ['C', 'G7', 'C', 'C', 'G7', 'G7', 'C', 'G7', 'C', 'G7', 'C', 'C', 'G7', 'G7', 'G7', 'C'];
  const acc = (pat, intro) => [intro, chordPat(CH, pat), chordPat(CH, pat), chordPat(CH, pat), chordPat(['C', 'C'], pat)].join(' | ');
  songs.push({
    id: 'can_can', short: 'CAN-CAN',
    title: ['CAN-CAN', '(GALOP INFERNAL)'], author: 'JACQUES OFFENBACH 1858',
    tempo: ramp([[0, 6], [144, 6], [272, 5], [400, 4], [416, 7]]),
    inst: {
      lead: { v: 13, fl: 8, dm: 3, vib: 12, gap: 1 },
      bass: { v: 12, fl: 5, dm: 3, gap: 1 },
      harm1: { v: 8, fl: 3, dm: 1, gap: 1 },
      harm2: { v: 7, fl: 3, dm: 1, gap: 1 },
    },
    tracks: {
      lead: ['r:16', P, transpose(P, 12), 'v15 ' + transpose(P, 12), 'c6:2 r:2 g5:2 r:2 | c6:2 r:6'].join(' | '),
      counter: ['r:16', transpose(P, -12), P, P, 'c5:2 r:2 g4:2 r:2 | c5:2 r:6'].join(' | '),
      bass: acc('R2:2 r:2 F1:2 r:2', 'c2:2 r:2 g1:2 r:2 | c2:2 r:2 g1:2 r:2'),
      harm1: acc('r:2 T4:2 r:2 T4:2', 'r:16'),
      harm2: acc('r:2 F3:2 r:2 F3:2', 'r:16'),
      drums: ['k:2 s k s | k:2 s s:1 s s s', '[k:2 s k s]47 k:2 s s:1 s s s', 'x:2 .:2 k:2 .:2 | x:2 .:6'].join(' | '),
    },
  });
}

// =====================================================================
// 12. William Tell Overture, the finale - G. Rossini (1829), E major, 2/4
//    the fanfare, the galop twice, the second theme, the galop an octave up
// =====================================================================
{
  const INTRO = 'e4:2 g#4:2 b4:2 e5:2 | g#5:2 r:2 g#5:2 r:2 | b5:8 | r:8';
  const BBB = 'b4:1 b4 b4:2 b4:1 b4 b4:2';
  const P1 = BBB + ' | b4:1 b4 e5:2 f#5:2 g#5:2 | b4:1 b4 b4:2 b4:1 b4 e5:2 | g#5:1 g#5 f#5:2 d#5:2 b4:2';
  const P2 = BBB + ' | b4:1 b4 e5:2 f#5:2 g#5:2 | e5:1 g#5 b5:2 a5:1 f#5 d#5:2 | e5:4 r:4';
  const B = 'd#5:1 d#5 d#5:2 d#5:1 d#5 d#5:2 | d#5:1 d#5 f#5:2 a5:2 b5:2 | ' +
            'e5:1 e5 e5:2 e5:1 e5 e5:2 | e5:1 e5 g#5:2 b5:2 e6:2';
  const END = 'e6:2 r:2 b5:2 r:2 | e6:2 r:2 e5:2 r:2 | e6:8 | r:8';
  const CP = ['E', 'E', 'E', 'B7', 'E', 'E', 'B7', 'E'];
  const CB = ['B7', 'B7', 'E', 'E', 'B7', 'B7', 'E', 'E'];
  const acc = pat => [['E', 'E', 'E', 'B7'], CP, CP, CB, CP, CP, ['E', 'B7', 'E', 'E']].map(c => chordPat(c, pat)).join(' | ');
  const PP = P1 + ' | ' + P2;
  songs.push({
    id: 'william_tell', short: 'WILLIAM TELL OVERTURE',
    title: ['WILLIAM TELL', 'OVERTURE - FINALE'], author: 'GIOACHINO ROSSINI 1829',
    tempo: ramp([[0, 6], [32, 5], [352, 5], [384, 8]]),
    inst: {
      lead: { v: 14, fl: 9, dm: 3, vib: 12, gap: 1 },
      bass: { v: 12, fl: 6, dm: 3, gap: 1 },
      harm1: { v: 8, fl: 3, dm: 1, gap: 1 },
      harm2: { v: 7, fl: 3, dm: 1, gap: 1 },
    },
    tracks: {
      lead: [INTRO, PP, PP, B, B, transpose(PP, 12), transpose(PP, 12), END].join(' | '),
      bass: acc('R2:2 F1:2 R2:2 F1:2'),
      harm1: acc('T4:1 T4 r:2 T4:1 T4 r:2'),
      harm2: acc('F3:1 F3 r:2 F3:1 F3 r:2'),
      drums: ['x:8 | .:8 | .:8 | s:1 s s s s s s s', '[k:2 s:1 s k:2 s:1 s]40', 'x:2 .:2 k:2 .:2 | x:2 .:2 k:2 .:2 | x:8 | .:8'].join(' | '),
    },
  });
}

// =====================================================================
// 13. Fur Elise (Bagatelle WoO 59) - L. van Beethoven (1810), A minor, 3/8
// =====================================================================
{
  const A = 'e5:1 d#5 e5 b4 d5 c5 | a4:2 r:1 c4 e4 a4 | b4:2 r:1 e4 g#4 b4 | c5:2 r:1 e4 e5 d#5 | ' +
            'e5:1 d#5 e5 b4 d5 c5 | a4:2 r:1 c4 e4 a4 | b4:2 r:1 e4 c5 b4';
  const AB = 'r:6 | a2:1 e3 a3 r:3 | e2:1 e3 g#3 r:3 | a2:1 e3 a3 r:3 | r:6 | a2:1 e3 a3 r:3 | e2:1 e3 g#3 r:3 | a2:1 e3 a3 r:3';
  const E1 = 'a4:4 e5:1 d#5', E2 = 'a4:2 r:1 b4 c5 d5', EF = 'a4:6';
  const B = 'e5:3 g4:1 f5 e5 | d5:3 f4:1 e5 d5 | c5:3 e4:1 d5 c5 | b4:2 r:1 e4 e5 r:1 | ' +
            'r:1 e5 e6 r:1 r:1 d#5 | e5:1 r:1 r:1 d#5 e5 d#5 | e5:1 d#5 e5 d#5 e5 d#5';
  const BB = 'c3:1 g3 c4 r:3 | g2:1 g3 b3 r:3 | a2:1 e3 a3 r:3 | e2:1 e3 e4 r:3 | r:6 | r:6 | r:6';
  songs.push({
    id: 'fur_elise', short: 'FUR ELISE',
    title: ['FUR ELISE', ''], author: 'L. VAN BEETHOVEN 1810',
    tempo: ramp([[0, 8], [320, 8], [328, 13]]),
    inst: {
      lead: { v: 13, fl: 4, dm: 7, vib: 0, gap: 1 },
      bass: { v: 10, fl: 3, dm: 7, gap: 1 },
    },
    tracks: {
      lead: ['e5:1 d#5', A, E1, A, E2, B, A, E1, A, E2, B, A, EF].join(' | '),
      bass: ['r:2', AB, AB, BB, AB, AB, BB, AB].join(' | '),
    },
  });
}

// =====================================================================
// 14. Maze Chase - original, C minor: a loop with a bouncing bass
// =====================================================================
{
  const A = 'c5:2 eb5 g5 c6 b5:2 g5 eb5:4 | ab4:2 c5 eb5 ab5 g5:4 eb5:4 | bb4:2 d5 f5 bb5 a5:2 f5 d5:4 | g5:2 f5 eb5 d5 b4:4 g4:4';
  const B = 'c6:1 b5 c6 b5 c6:4 g5:4 eb5:4 | ab5:1 g5 ab5 g5 ab5:4 eb5:4 c5:4 | bb5:1 a5 bb5 a5 bb5:4 f5:4 d5:4 | g5:2 ab5 g5 f5 eb5:2 d5 c5 b4';
  const CH = ['Cm', 'Ab', 'Bb', 'G'];
  const loop = (pat, n) => Array(n).fill(chordPat(CH, pat)).join(' | ');
  songs.push({
    id: 'maze_chase', short: 'MAZE CHASE',
    title: ['MAZE CHASE', ''], author: 'ORIGINAL - MINIVIC SOUND',
    tempo: 5,
    inst: {
      lead: { v: 13, fl: 9, dm: 3, vib: 12, gap: 1 },
      harm1: { v: 7, fl: 3, dm: 1, gap: 0 },
      bass: { v: 12, fl: 6, dm: 1, gap: 1 },
      harm2: { v: 6, fl: 5, dm: 15, gap: 0 },
    },
    tracks: {
      lead: ['r:64', A, A, B, B, 'v14', A, A, B, B, 'c5:2 r:2 g4:2 r:2 c5:4 r:4'].join(' | '),
      bass: [loop('[R2:2 O2]4', 9), 'c2:2 r:2 g1:2 r:2 c2:4 r:4'].join(' | '),
      harm1: ['r:64', loop('[R4:1 T4 F4 O4]4', 8), 'eb4:2 r:2 d4:2 r:2 c4:4 r:4'].join(' | '),
      harm2: ['r:64', loop('T3:16', 8), 'g3:4 r:12'].join(' | '),
      drums: ['[k:2 h s h k h s h]3 k:2 h s h t:1 t m m s s s s', '[k:2 h s h k h s h]31 k:2 s s s s:1 s s s s s s s',
        'k:2 .:2 k:2 .:2 x:8'].join(' | '),
    },
  });
}

// =====================================================================
// 15. Dungeon Boss - original, E minor: an ostinato with a tritone, heavy drums
// =====================================================================
{
  const OST = 'e2:2 e2 e3 e2 g2 e2 a#2 b2';
  const A = 'e5:6 f5:2 e5:4 b4:4 | c5:6 b4:2 a#4:8 | e5:6 f5:2 g5:4 a#5:4 | b5:12 r:4';
  const B = 'g5:4 f#5:4 e5:4 d#5:4 | e5:4 f#5:4 g5:4 a5:4 | a5:6 g5:2 f#5:4 e5:4 | d#5:4 e5:4 f#5:8';
  const CA = ['Em', 'Am', 'Em', 'B'], CB = ['Em', 'C', 'Am', 'B'];
  const BASS_A = [OST, transpose(OST, 5), OST, transpose(OST, 7)].join(' | ');
  const BASS_B = chordPat(CB, '[R1:2 R1 O1 R1]2');
  const FORM = ['A', 'A', 'B', 'A', 'B', 'A'];
  const harm = pat => ['r:32', ...FORM.map(f => chordPat(f === 'A' ? CA : CB, pat)), 'e4:16 | e4:16'].join(' | ');
  const LEAD = ['r:32', ...FORM.map(f => (f === 'A' ? A : B)), 'e5:4 r:4 e4:4 r:4 | e5:16'].join(' | ');
  const DA = '[k:2 k:2 s:2 k:2 k:2 k:2 s:2 h:2]3 t:2 t:2 m:2 m:2 s:1 s s s s s s s';
  songs.push({
    id: 'dungeon_boss', short: 'DUNGEON BOSS',
    title: ['DUNGEON BOSS', ''], author: 'ORIGINAL - MINIVIC SOUND',
    tempo: 6,
    inst: {
      lead: { v: 13, fl: 10, dm: 7, vib: 12, gap: 0 },
      counter: { v: 10, fl: 8, dm: 7, vib: 0, gap: 0 },
      harm1: { v: 7, fl: 6, dm: 15, gap: 0 },
      harm2: { v: 7, fl: 6, dm: 15, gap: 0 },
      bass: { v: 13, fl: 6, dm: 1, gap: 1 },
    },
    tracks: {
      lead: LEAD,
      counter: transpose(LEAD, -12),
      bass: [OST, OST, ...FORM.map(f => (f === 'A' ? BASS_A : BASS_B)), 'e2:4 r:4 e1:4 r:4 | e1:16'].join(' | '),
      harm1: harm('F3:16'),
      harm2: harm('R3:16'),
      drums: ['k:2 .:6 k:2 .:6 | k:2 .:2 k:2 .:2 s:1 s s s s s s s', ...FORM.map(() => DA), 'x:2 .:6 k:2 .:6 | x:16'].join(' | '),
    },
  });
}

// =====================================================================
// 16. High Score - original, F major: a fanfare, then the tune for the name entry
// =====================================================================
{
  const FAN = 'c5:2 f5:2 a5:2 c6:4 a5:2 c6:4 | f6:16';
  const A = 'a5:4 g5:2 f5:2 c5:4 f5:4 | g5:4 a5:2 bb5:2 a5:8 | bb5:4 a5:2 g5:2 d5:4 g5:4 | a5:4 g5:2 f5:2 e5:8 | ' +
            'a5:4 g5:2 f5:2 c6:4 a5:4 | bb5:4 a5:2 g5:2 d6:8 | c6:4 bb5:2 a5:2 g5:4 e5:4 | f5:12 r:4';
  const B = 'd6:4 c6:2 bb5:2 a5:4 f5:4 | c6:4 bb5:2 a5:2 g5:8 | bb5:4 a5:2 g5:2 f5:4 d5:4 | e5:4 f5:2 g5:2 c6:8';
  const CA = ['F', 'C', 'Gm', 'C', 'F', 'Bb', 'C7', 'F'], CB = ['Bb', 'C', 'Gm', 'C'];
  const acc = (pat, fan, end) => [fan, chordPat(CA, pat), chordPat(CB, pat), chordPat(CA, pat), end].join(' | ');
  songs.push({
    id: 'high_score', short: 'HIGH SCORE',
    title: ['HIGH SCORE', ''], author: 'ORIGINAL - MINIVIC SOUND',
    tempo: ramp([[0, 6], [32, 7], [352, 7], [368, 10]]),
    inst: {
      lead: { v: 13, fl: 8, dm: 3, vib: 14, gap: 1 },
      harm1: { v: 8, fl: 3, dm: 1, gap: 1 },
      harm2: { v: 7, fl: 3, dm: 1, gap: 1 },
      bass: { v: 12, fl: 6, dm: 3, gap: 1 },
    },
    tracks: {
      lead: [FAN, A, B, A, 'f5:2 a5 c6 f6:10'].join(' | '),
      bass: acc('R2:4 F2:4 O2:4 F2:4', 'f2:2 r:2 c3:2 r:2 f2:8 | f1:16', 'f2:2 c3 f3:12'),
      harm1: acc('[r:2 T4:2]4', 'a4:8 c5:8 | c5:16', 'c5:16'),
      harm2: acc('[r:2 F3:2]4', 'f4:8 f4:8 | a4:16', 'a4:16'),
      drums: ['s:1 s s s s s s s s:2 s s s | x:16', '[k:2 h s h k h s h]19 k:2 h s h t:1 t m m s s s s', 'k:2 s:2 x:12'].join(' | '),
    },
  });
}

module.exports = songs;
