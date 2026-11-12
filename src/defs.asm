; ---------------- hardware ----------------
VREG        = $B001          ; TMS9918A: registers / status
VDATA       = $B000          ; TMS9918A: VRAM data
AY_R_LATCH  = $D380          ; right AY-3-8910
AY_R_WRITE  = $D381
AY_L_LATCH  = $D384          ; left AY-3-8910
AY_L_WRITE  = $D385
PORTB_JOY   = $D580          ; joystick 2 |P2|P1|RG|LF|DW|UP (active low)
PORTA_JOY   = $D581          ; joystick 1
DDRB_JOY    = $D582
DDRA_JOY    = $D583
JT_SHOW_MENU = $FD0F         ; back to the BIOS menu (JMP, never RTS)

; ---------------- VRAM (Graphics I) ----------------
VR_PAT      = $0000          ; patterns
VR_NAME     = $1800          ; name table 32 x 24
VR_SAT      = $1B00          ; sprite attributes
VR_COL      = $2000          ; colours, one byte per 8 characters

; ---------------- joystick bits (1 = pressed) ----------------
J_UP        = $01
J_DOWN      = $02
J_LEFT      = $04
J_RIGHT     = $08
J_FIRE      = $30            ; either button

; ---------------- zero page (the BIOS uses $00-$4F) ----------------
ZP_PTR      = $50            ; 2 bytes: player
TXT_PTR     = $52            ; 2 bytes: text
T0          = $54
T1          = $55
T2          = $56
T3          = $57
RND         = $58            ; 8-bit LFSR
JOY         = $59            ; joysticks 1 OR 2, 1 = pressed
JOY_OLD     = $5A
JNEW        = $5B            ; pressed in this frame
TXT_MODE    = $5C            ; 0 normal, 1 highlighted, 2 yellow letters
WAITC       = $5D
CUR         = $5E            ; jukebox: cursor
PLAYING     = $5F            ; jukebox: song playing (0-based)
SHUFFLE     = $60            ; jukebox: 1 = random play
LAST        = $61            ; jukebox: last random song
REPT        = $62            ; jukebox: joystick repeat counter
STATE       = $63            ; jukebox: 0 list, 1 playing

; ---------------- RAM of the player ----------------
SH_L        = $7E00          ; shadow of the left AY registers (16)
SH_R        = $7E10          ; shadow of the right AY registers (16)
TR_PL       = $7E20          ; 6 tracks: pointer low
TR_PH       = $7E26          ;           pointer high
TR_CT       = $7E2C          ;           frames left of the event
TR_ACT      = $7E32          ;           1 = playing
TR_NOTE     = $7E38          ;           note (0 = rest)
TR_VOL      = $7E3E          ;           volume
TR_AGE      = $7E44          ;           frames since the note started
TR_V0       = $7E4A          ; 5 tone tracks: attack volume
TR_FL       = $7E50          ;           lowest volume of the decay
TR_DM       = $7E56          ;           decay mask
TR_VIB      = $7E5C          ;           vibrato delay (0 = off)
TR_GAP      = $7E62          ;           1 = silent last frame
TR_VPH      = $7E68          ; 6 tracks: vibrato phase
HAS3        = $7E70          ; 1 = the song has harmony 2
HAS4        = $7E71          ; 1 = the song has a counter melody
MUS_ON      = $7E72          ; 1 = a song is playing
DR_PL       = $7E73          ; drum tone period
DR_PH       = $7E74
BAR_LV      = $7E78          ; 6 levels shown by the bars
TR_RL       = $7E90          ; 6 tracks: return address after a reference ($FC), low
TR_RH       = $7E96          ;           high
TR_RN       = $7E9C          ;           events left in the reference (0 = none)
BT_T        = $64            ; bars: track
BT_H        = $65            ;       height in pixels
BT_COL      = $66            ;       column
BT_R        = $67            ;       row 0-3
BT_G        = $68            ;       character
