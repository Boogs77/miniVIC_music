;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   MiniVIC Jukebox - every song of MiniVIC Sound              ;
;   list: up / down = choose, fire = play, RANDOM PLAY         ;
;   playing: fire = list, right = next, left = again           ;
;   loaded at $0FD0, started at $1000 (application, MiniVIC Apps);
;   built by build.js from songs.js: edit those, not this file ;
;                                                              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

; ===============================================================
;  MiniVIC Jukebox: list of the songs, random play
;  an application of the SD menu: loaded at $0FD0, started at $1000
;    list:     up / down = choose, fire = play
;              RANDOM PLAY = songs at random: each one once per round, never twice in a row
;              EXIT = back to the menu of the BIOS
;    playing:  fire = back to the list, right = next song, left = again
;  the build adds NSONGS, RND_MASK and the tables SONG_*, T1_*, T2_*, AU_*, ITEM_*
; ===============================================================
LIST_ROW  = 3                   ; row of the first item (up to 18 items: rows 3-20)
DL_I      = $69                 ; list: item
DL_ROW    = $6A                 ;       row
NUMBUF    = $7E80               ; "SONG n OF m"
PLAYED    = $7EB0               ; random play: 1 = already played in this round (up to 16 songs)
PCOUNT    = $7EC0               ;              songs played in this round

 .org $0FD0
  RTS                           ; NMI trampoline of the applications (the VDP interrupt is off)
 .org $1000
RESET:
  SEI
  CLD
  LDX #$FF
  TXS
  LDA #$A5
  STA RND
  STZ DDRA_JOY
  STZ DDRB_JOY
  JSR SND_RESET
  JSR VDP_INIT
  STZ CUR
  STZ SHUFFLE
  LDA #$FF
  STA LAST
  LDA #NSONGS                   ; the first draw starts a new round
  STA PCOUNT
  STZ REPT
  JSR READ_JOY                  ; a button still held does not count
  STZ JNEW

; ---------------------------------------------------------------
; the list
; ---------------------------------------------------------------
LIST:
  JSR SND_RESET
  JSR CLS
  JSR JB_HEADER
  STZ TXT_MODE
  LDA #<TXT_HELP1
  STA TXT_PTR
  LDA #>TXT_HELP1
  STA TXT_PTR+1
  LDA #22
  JSR PRINT_C
  JSR DRAW_LIST
.ll:
  JSR WAIT_VBL                  ; the LFSR runs every frame: the wait is the seed
  JSR READ_JOY
  JSR MENU_MOVE
  BCC .ll_fire
  JSR DRAW_LIST
.ll_fire:
  LDA JNEW
  AND #J_FIRE
  BEQ .ll
  LDA CUR
  BEQ .ll_rnd
  CMP #NSONGS+1
  BEQ .ll_exit
  DEC A
  STA PLAYING
  STZ SHUFFLE
  JMP PLAY
.ll_rnd:
  LDA #1
  STA SHUFFLE
  JSR PICK_RANDOM
  JMP PLAY
.ll_exit:
  JSR SND_RESET
  JMP JT_SHOW_MENU

; up / down with repeat: C = 1 if the cursor moved
MENU_MOVE:
  LDA JOY
  AND #(J_UP|J_DOWN)
  BNE .mm_held
  STZ REPT
  CLC
  RTS
.mm_held:
  LDA JNEW
  AND #(J_UP|J_DOWN)
  BEQ .mm_rep
  LDA #20                       ; first repeat after 20 frames
  STA REPT
  BRA .mm_go
.mm_rep:
  DEC REPT
  BEQ .mm_r2
  CLC
  RTS
.mm_r2:
  LDA #6                        ; then every 6 frames
  STA REPT
.mm_go:
  LDA JOY
  AND #J_UP
  BEQ .mm_down
  LDA CUR
  BNE .mm_u1
  LDA #NSONGS+2
.mm_u1:
  DEC A
  STA CUR
  SEC
  RTS
.mm_down:
  LDA CUR
  INC A
  CMP #NSONGS+2
  BCC .mm_d1
  LDA #0
.mm_d1:
  STA CUR
  SEC
  RTS

; all the items, the cursor on a highlighted row
DRAW_LIST:
  LDX #0
.dl:
  STX DL_I
  TXA
  CLC
  ADC #LIST_ROW
  STA DL_ROW
  LDY #$20
  STZ TXT_MODE
  CPX CUR
  BNE .dl_fill
  LDY #$A0                      ; highlighted space
  LDA #1
  STA TXT_MODE
.dl_fill:
  LDA DL_ROW
  JSR FILL_ROW
  LDX DL_I
  LDA ITEM_LO,X
  STA TXT_PTR
  LDA ITEM_HI,X
  STA TXT_PTR+1
  LDA DL_ROW
  LDX #4
  JSR PRINT_AT
  LDX DL_I
  INX
  CPX #NSONGS+2
  BNE .dl
  RTS

; a random song: every song once per round, never the same twice in a row
PICK_RANDOM:
  LDA PCOUNT
  CMP #NSONGS
  BCC .pr_draw
  LDX #NSONGS-1                 ; all played: a new round
.pr_clr:
  STZ PLAYED,X
  DEX
  BPL .pr_clr
  STZ PCOUNT
  LDX LAST                      ; the last song waits for the next round
  CPX #NSONGS
  BCS .pr_draw
  LDA #1
  STA PLAYED,X
  INC PCOUNT
.pr_draw:
  LDX #8                        ; 8 steps of the LFSR: a fresh byte
.pr_mix:
  JSR NEXT_RND
  DEX
  BNE .pr_mix
  AND #RND_MASK
.pr_mod:
  CMP #NSONGS
  BCC .pr_in
  SBC #NSONGS
  BRA .pr_mod
.pr_in:
  TAX
.pr_find:                       ; from there, the next song not played yet
  LDA PLAYED,X
  BEQ .pr_got
  INX
  CPX #NSONGS
  BCC .pr_find
  LDX #0
  BRA .pr_find
.pr_got:
  LDA #1
  STA PLAYED,X
  INC PCOUNT
  STX LAST
  STX PLAYING
  RTS

JB_HEADER:
  LDA #<TXT_JB
  STA TXT_PTR
  LDA #>TXT_JB
  STA TXT_PTR+1
  JSR DRAW_HEADER_T
  LDA #23
  LDY #$6B
  JMP FILL_ROW

; ---------------------------------------------------------------
; playing the song PLAYING
; ---------------------------------------------------------------
PLAY:
  JSR SND_RESET
  JSR BARS_RESET
  JSR CLS
  JSR JB_HEADER
  STZ TXT_MODE
  LDA #<TXT_NOW
  STA TXT_PTR
  LDA #>TXT_NOW
  STA TXT_PTR+1
  LDA SHUFFLE
  BEQ .pl_mode
  LDA #<TXT_RANDOM
  STA TXT_PTR
  LDA #>TXT_RANDOM
  STA TXT_PTR+1
.pl_mode:
  LDA #4
  JSR PRINT_C
  LDA #2                        ; title in yellow
  STA TXT_MODE
  LDX PLAYING
  LDA T1_LO,X
  STA TXT_PTR
  LDA T1_HI,X
  STA TXT_PTR+1
  LDA #6
  JSR PRINT_C
  LDX PLAYING
  LDA T2_LO,X
  STA TXT_PTR
  LDA T2_HI,X
  STA TXT_PTR+1
  LDA #7
  JSR PRINT_C
  STZ TXT_MODE
  LDX PLAYING
  LDA AU_LO,X
  STA TXT_PTR
  LDA AU_HI,X
  STA TXT_PTR+1
  LDA #9
  JSR PRINT_C
  JSR DRAW_BAR_LABELS
  ; "SONG n OF m": "SONG ", the number (1 or 2 digits), TXT_OFN
  LDX #0
.pl_nb:
  LDA TXT_SONG,X
  STA NUMBUF,X
  INX
  CPX #5
  BNE .pl_nb
  LDA PLAYING
  INC A
  CMP #10
  BCC .pl_one
  SBC #10                       ; at most 19 songs: tens = '1'
  PHA
  LDA #$31
  STA NUMBUF,X
  INX
  PLA
.pl_one:
  ORA #$30
  STA NUMBUF,X
  INX
  LDY #0
.pl_of:
  LDA TXT_OFN,Y
  STA NUMBUF,X
  INX
  INY
  CMP #0
  BNE .pl_of
  LDA #<NUMBUF
  STA TXT_PTR
  LDA #>NUMBUF
  STA TXT_PTR+1
  LDA #18
  JSR PRINT_C
  LDA #<TXT_KEYS1
  STA TXT_PTR
  LDA #>TXT_KEYS1
  STA TXT_PTR+1
  LDA #20
  JSR PRINT_C
  LDA #<TXT_KEYS2
  STA TXT_PTR
  LDA #>TXT_KEYS2
  STA TXT_PTR+1
  LDA #21
  JSR PRINT_C
  LDX PLAYING
  LDA SONG_HI,X
  TAY
  LDA SONG_LO,X
  TAX
  JSR MUS_START
.pl_loop:
  JSR WAIT_VBL
  JSR MUS_TICK
  JSR AY_FLUSH
  JSR DRAW_BARS
  JSR READ_JOY
  LDA JNEW
  AND #J_FIRE
  BEQ .pl_r
  JMP LIST
.pl_r:
  LDA JNEW
  AND #J_RIGHT
  BEQ .pl_l
  JMP NEXT_SONG
.pl_l:
  LDA JNEW
  AND #J_LEFT
  BEQ .pl_end
  JMP PLAY
.pl_end:
  LDA MUS_ON
  BNE .pl_loop
  LDA #60                       ; 1 s of silence
  STA WAITC
.pl_wait:
  JSR WAIT_VBL
  JSR DRAW_BARS
  JSR READ_JOY
  LDA JNEW
  AND #J_FIRE
  BEQ .pl_w2
  JMP LIST
.pl_w2:
  DEC WAITC
  BNE .pl_wait
  LDA SHUFFLE
  BNE NEXT_SONG
  JMP LIST                      ; one song: back to the list, on that song

NEXT_SONG:
  LDA SHUFFLE
  BEQ .ns_seq
  JSR PICK_RANDOM
  JMP PLAY
.ns_seq:
  LDA PLAYING
  INC A
  CMP #NSONGS
  BCC .ns_1
  LDA #0
.ns_1:
  STA PLAYING
  INC A
  STA CUR
  JMP PLAY

TXT_JB:     .byte "MINIVIC JUKEBOX", 0
TXT_HELP1:  .byte "UP DOWN = CHOOSE   FIRE = PLAY", 0
TXT_SONG:   .byte "SONG "
TXT_NOW:    .byte "NOW PLAYING", 0
TXT_RANDOM: .byte "RANDOM PLAY", 0
TXT_KEYS1:  .byte "FIRE = LIST   RIGHT = NEXT", 0
TXT_KEYS2:  .byte "LEFT = PLAY AGAIN", 0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   MiniVIC Sound - screen, text, volume bars, joystick        ;
;                                                              ;
;   TMS9918A Graphics I, 32 x 24, VDP interrupt always off:    ;
;   the frame is found by reading the status (bit 7)           ;
;   characters: $20-$5F text, $60-$68 / $70-$78 bars           ;
;   (green / yellow), $69 blank, $6A note, $6B line,           ;
;   $6C arrow, $A0-$DF highlighted text, $E0-$FF yellow        ;
;   letters ($E0 = space)                                      ;
;                                                              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

BAR_ROW   = 12                  ; top row of the 4-row bars
BAR_COL0  = 5                   ; column of the first bar (4 columns each)

; ---------------------------------------------------------------
; VDP: registers, VRAM cleared, characters, colours, no sprites
; ---------------------------------------------------------------
VDP_INIT:
  LDX #0
.vi_r:
  LDA VDP_REGS,X
  STA VREG
  TXA
  ORA #$80
  STA VREG
  INX
  CPX #8
  BNE .vi_r
  LDA #0                        ; 16 KB of VRAM to 0
  TAY
  JSR SET_VADDR
  LDY #$40
  LDX #0
.vi_c:
  STZ VDATA
  INX
  BNE .vi_c
  DEY
  BNE .vi_c
  ; text $20-$5F and its highlighted copy $A0-$DF
  LDA #<(VR_PAT+$100)
  LDY #>(VR_PAT+$100)
  LDX #64
  JSR LOAD_FONT
  LDA #<(VR_PAT+$500)
  LDY #>(VR_PAT+$500)
  LDX #64
  JSR LOAD_FONT
  ; yellow letters $E0-$FF ($E0 stays blank: space)
  LDA #<(VR_PAT+$708)
  LDY #>(VR_PAT+$708)
  JSR SET_VADDR
  LDA #<(FONT+$108)
  STA TXT_PTR
  LDA #>(FONT+$108)
  STA TXT_PTR+1
  LDX #31
  JSR COPY_GLYPHS
  ; bars and symbols, green $60 and yellow $70
  LDA #<(VR_PAT+$300)
  LDY #>(VR_PAT+$300)
  JSR LOAD_GLYPHS
  LDA #<(VR_PAT+$380)
  LDY #>(VR_PAT+$380)
  JSR LOAD_GLYPHS
  ; colours
  LDA #<VR_COL
  LDY #>VR_COL
  JSR SET_VADDR
  LDX #0
.vi_col:
  LDA COLTAB,X
  STA VDATA
  INX
  CPX #32
  BNE .vi_col
  ; no sprites
  LDA #<VR_SAT
  LDY #>VR_SAT
  JSR SET_VADDR
  LDA #$D0
  STA VDATA
  JSR CLS
  LDA #$C0                      ; display on, interrupt off
  STA VREG
  LDA #$81
  STA VREG
  RTS

LOAD_FONT:                      ; A/Y = VRAM address, X = glyphs from FONT
  JSR SET_VADDR
  LDA #<FONT
  STA TXT_PTR
  LDA #>FONT
  STA TXT_PTR+1
  JMP COPY_GLYPHS

LOAD_GLYPHS:                    ; A/Y = VRAM address of the 13 symbols
  JSR SET_VADDR
  LDA #<GLYPHS
  STA TXT_PTR
  LDA #>GLYPHS
  STA TXT_PTR+1
  LDX #13
  ; falls into COPY_GLYPHS

COPY_GLYPHS:                    ; X glyphs of 8 bytes from TXT_PTR
.cg_g:
  LDY #0
.cg_b:
  LDA (TXT_PTR),Y
  STA VDATA
  INY
  CPY #8
  BNE .cg_b
  LDA TXT_PTR
  CLC
  ADC #8
  STA TXT_PTR
  BCC .cg_n
  INC TXT_PTR+1
.cg_n:
  DEX
  BNE .cg_g
  RTS

SET_VADDR:                      ; VRAM write address: A = low, Y = high
  STA VREG
  TYA
  ORA #$40
  STA VREG
  RTS

; A = row, X = column: VRAM write address of that cell
SET_POS:
  PHA
  LSR A
  LSR A
  LSR A
  CLC
  ADC #((>VR_NAME)|$40)
  STA T1
  PLA
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STX T0
  ORA T0
  STA VREG
  LDA T1
  STA VREG
  RTS

CLS:                            ; the whole name table to spaces
  LDA #<VR_NAME
  LDY #>VR_NAME
  JSR SET_VADDR
  LDY #3
  LDX #0
  LDA #$20
.cl_l:
  STA VDATA
  INX
  BNE .cl_l
  DEY
  BNE .cl_l
  RTS

; A = row, Y = character: the whole row
FILL_ROW:
  STY T2
  LDX #0
  JSR SET_POS
  LDX #32
  LDA T2
.fr_l:
  STA VDATA
  DEX
  BNE .fr_l
  RTS

; A = row, X = column, TXT_PTR = text (0 at the end), TXT_MODE = style
PRINT_AT:
  JSR SET_POS
PUTS:
  LDY #0
.p_l:
  LDA (TXT_PTR),Y
  BEQ .p_end
  JSR MAP_CHAR
  STA VDATA
  INY
  BNE .p_l
.p_end:
  RTS

; A = row, TXT_PTR = text: centred on the row
PRINT_C:
  PHA
  LDY #0
.pc_len:
  LDA (TXT_PTR),Y
  BEQ .pc_go
  INY
  BNE .pc_len
.pc_go:
  TYA
  EOR #$FF
  SEC
  ADC #32                       ; 32 - length
  LSR A
  TAX
  PLA
  JMP PRINT_AT

MAP_CHAR:                       ; character in the style TXT_MODE
  LDX TXT_MODE
  BEQ .mc_end
  CPX #1
  BNE .mc_yel
  ORA #$80
  RTS
.mc_yel:
  CMP #$20
  BNE .mc_y2
  LDA #$E0
  RTS
.mc_y2:
  CMP #$40
  BCC .mc_end
  ORA #$A0
.mc_end:
  RTS

; ---------------------------------------------------------------
; frame: waits for the vblank flag of the VDP, steps the LFSR
; ---------------------------------------------------------------
WAIT_VBL:
  LDA VREG
  BPL WAIT_VBL
NEXT_RND:
  LDA RND
  ASL A
  BCC .nr_s
  EOR #$1D
.nr_s:
  STA RND
  RTS

; both joysticks, 1 = pressed; JNEW = pressed in this frame
READ_JOY:
  LDA PORTA_JOY
  EOR #$FF
  AND #$3F
  STA T0
  LDA PORTB_JOY
  EOR #$FF
  AND #$3F
  ORA T0
  STA JOY
  EOR JOY_OLD
  AND JOY
  STA JNEW
  LDA JOY
  STA JOY_OLD
  RTS

; ---------------------------------------------------------------
; volume bars of the 6 tracks (they fall by 1 per frame)
; ---------------------------------------------------------------
DRAW_BARS:
  LDX #5
.db_lv:
  LDA TR_VOL,X
  CMP BAR_LV,X
  BCS .db_set
  LDA BAR_LV,X
  DEC A
.db_set:
  STA BAR_LV,X
  DEX
  BPL .db_lv
  LDX #0
.db_t:
  STX BT_T
  LDA BAR_LV,X
  ASL A
  STA BT_H                      ; height 0-30 pixels
  TXA
  ASL A
  ASL A
  CLC
  ADC #BAR_COL0
  STA BT_COL
  STZ BT_R
.db_r:
  LDA #3
  SEC
  SBC BT_R
  ASL A
  ASL A
  ASL A
  STA BT_G                      ; pixels below this row
  LDA BT_H
  SEC
  SBC BT_G
  BCS .db_p
  LDA #0
.db_p:
  CMP #9
  BCC .db_q
  LDA #8
.db_q:
  STA BT_G
  LDA BT_R
  CMP #2
  LDA #$70                      ; top two rows yellow
  BCC .db_c
  LDA #$60
.db_c:
  CLC
  ADC BT_G
  STA BT_G
  LDA BT_R
  CLC
  ADC #BAR_ROW
  LDX BT_COL
  JSR SET_POS
  LDA BT_G
  STA VDATA
  NOP
  NOP
  STA VDATA
  NOP
  NOP
  STA VDATA
  INC BT_R
  LDA BT_R
  CMP #4
  BNE .db_r
  LDX BT_T
  INX
  CPX #6
  BNE .db_t
  RTS

BARS_RESET:
  LDX #5
.br_l:
  STZ BAR_LV,X
  DEX
  BPL .br_l
  RTS

; the frame of the bars: labels under them
DRAW_BAR_LABELS:
  STZ TXT_MODE
  LDA #<TXT_LABELS
  STA TXT_PTR
  LDA #>TXT_LABELS
  STA TXT_PTR+1
  LDA #BAR_ROW+4
  LDX #BAR_COL0
  JMP PRINT_AT

; header shared by the programs: lines and MINIVIC SOUND
DRAW_HEADER:
  LDA #<TXT_HEAD
  STA TXT_PTR
  LDA #>TXT_HEAD
  STA TXT_PTR+1
DRAW_HEADER_T:                  ; TXT_PTR = text of the header
  LDA #0
  LDY #$6B
  JSR FILL_ROW
  LDA #2
  LDY #$6B
  JSR FILL_ROW
  LDA #2
  STA TXT_MODE
  LDA #1
  JMP PRINT_C

TXT_LABELS: .byte "LD  H1  BS  H2  CM  DR", 0
TXT_HEAD:   .byte "MINIVIC SOUND", 0

;           R0   R1   R2   R3   R4   R5   R6   R7
VDP_REGS:  .byte $00, $80, $06, $80, $00, $36, $07, $F4

; colour of each group of 8 characters (foreground * 16 + background)
COLTAB:
  .byte $44, $44, $44, $44                   ; $00-$1F
  .byte $F4, $F4, $F4, $F4, $F4, $F4, $F4, $F4 ; $20-$5F text
  .byte $34, $34                             ; $60-$6F green bars, symbols
  .byte $B4, $B4                             ; $70-$7F yellow bars
  .byte $44, $44, $44, $44                   ; $80-$9F
  .byte $47, $47, $47, $47, $47, $47, $47, $47 ; $A0-$DF highlighted
  .byte $B4, $B4, $B4, $B4                   ; $E0-$FF yellow letters

; $60-$68 bar 0-8 pixels high, $69 blank, $6A note, $6B line, $6C arrow
GLYPHS:
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$7E
  .byte $00,$00,$00,$00,$00,$00,$7E,$7E
  .byte $00,$00,$00,$00,$00,$7E,$7E,$7E
  .byte $00,$00,$00,$00,$7E,$7E,$7E,$7E
  .byte $00,$00,$00,$7E,$7E,$7E,$7E,$7E
  .byte $00,$00,$7E,$7E,$7E,$7E,$7E,$7E
  .byte $00,$7E,$7E,$7E,$7E,$7E,$7E,$7E
  .byte $7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$1C,$16,$12,$10,$70,$F0,$60
  .byte $00,$00,$00,$FF,$FF,$00,$00,$00
  .byte $40,$60,$70,$78,$70,$60,$40,$00

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   MiniVIC Sound - 6-track music player for 2 x AY-3-8910     ;
;                                                              ;
;   tracks: 0 lead, 1 harmony 1, 2 bass, 3 harmony 2,          ;
;           4 counter melody, 5 drums                          ;
;   channels:                                                  ;
;     left  A = lead          right A = counter (or lead +1    ;
;     left  B = harmony 1               step: chorus)          ;
;     left  C = bass          right B = drums (noise + tone)   ;
;                             right C = harmony 2 (or bass)    ;
;                                                              ;
;   song header: 6 track pointers (0 = no track), then 5 x 5   ;
;   instrument bytes (attack volume, floor, decay mask,        ;
;   vibrato delay (0 = off), gap before the next note)         ;
;   track: .byte note, frames ... ; note 0 = rest, $FE = tie,  ;
;   $FD v = attack volume v, $FF = end of the track            ;
;   call MUS_TICK once per frame, then AY_FLUSH                ;
;                                                              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; silence: shadows to 0, mixer all off, written to the chips
SND_RESET:
  STZ MUS_ON
  LDX #15
.sr_l:
  STZ SH_L,X
  STZ SH_R,X
  DEX
  BPL .sr_l
  LDA #$3F
  STA SH_L+7
  STA SH_R+7
  JMP AY_FLUSH

; writes registers 0-10 of the two shadows to the two AYs
AY_FLUSH:
  LDX #10
.af_l:
  LDA SH_L,X
  STX AY_L_LATCH
  STA AY_L_WRITE
  LDA SH_R,X
  STX AY_R_LATCH
  STA AY_R_WRITE
  DEX
  BPL .af_l
  RTS

; ---------------------------------------------------------------
; starts a song: X = low byte, Y = high byte of its header
; ---------------------------------------------------------------
MUS_START:
  STX ZP_PTR
  STY ZP_PTR+1
  LDY #0
  LDX #0
.ms_trk:
  LDA (ZP_PTR),Y
  STA TR_PL,X
  INY
  LDA (ZP_PTR),Y
  STA TR_PH,X
  INY
  ORA TR_PL,X
  BEQ .ms_abs                   ; A = 0: no track
  LDA #1
.ms_abs:
  STA TR_ACT,X
  LDA #1
  STA TR_CT,X                   ; the first tick reads the first event
  STZ TR_NOTE,X
  STZ TR_VOL,X
  STZ TR_AGE,X
  STZ TR_VPH,X
  STZ TR_RN,X
  INX
  CPX #6
  BNE .ms_trk
  LDX #0                        ; Y = 12: instruments of tracks 0-4
.ms_ins:
  LDA (ZP_PTR),Y
  STA TR_V0,X
  INY
  LDA (ZP_PTR),Y
  STA TR_FL,X
  INY
  LDA (ZP_PTR),Y
  STA TR_DM,X
  INY
  LDA (ZP_PTR),Y
  STA TR_VIB,X
  INY
  LDA (ZP_PTR),Y
  STA TR_GAP,X
  INY
  INX
  CPX #5
  BNE .ms_ins
  LDA TR_ACT+3
  STA HAS3
  LDA TR_ACT+4
  STA HAS4
  STZ DR_PL
  STZ DR_PH
  LDA #$38                      ; left: 3 tones
  STA SH_L+7
  LDA #1
  STA MUS_ON
  RTS

; ---------------------------------------------------------------
; reads the next event of track X
; ---------------------------------------------------------------
MUS_FETCH:
  LDA TR_PL,X
  STA ZP_PTR
  LDA TR_PH,X
  STA ZP_PTR+1
.mf_again:
  LDA (ZP_PTR)
  CMP #$FC
  BNE .mf_ff
  ; $FC lo hi n: play n events at lo/hi, then go on after these 4 bytes
  LDA ZP_PTR
  CLC
  ADC #4
  STA TR_RL,X
  LDA ZP_PTR+1
  ADC #0
  STA TR_RH,X
  LDY #3
  LDA (ZP_PTR),Y
  STA TR_RN,X
  LDY #1
  LDA (ZP_PTR),Y
  PHA
  INY
  LDA (ZP_PTR),Y
  STA ZP_PTR+1
  PLA
  STA ZP_PTR
  BRA .mf_again
.mf_ff:
  CMP #$FF
  BNE .mf_1
  STZ TR_ACT,X                  ; end of the track
  STZ TR_NOTE,X
  STZ TR_VOL,X
  RTS
.mf_1:
  LDY #1
  CMP #$FD
  BNE .mf_2
  LDA (ZP_PTR),Y                ; new attack volume
  STA TR_V0,X
  JSR ADV_EV
  BRA .mf_again
.mf_2:
  LDA (ZP_PTR),Y
  STA TR_CT,X                   ; length in frames
  LDA (ZP_PTR)
  PHA
  JSR ADV_EV
  LDA ZP_PTR
  STA TR_PL,X
  LDA ZP_PTR+1
  STA TR_PH,X
  PLA
  CMP #$FE
  BEQ .mf_end                   ; tie: the note goes on
  STA TR_NOTE,X
  STZ TR_AGE,X
  STZ TR_VPH,X
  CMP #0
  BEQ .mf_rest
  CPX #5
  BEQ .mf_drum
  LDA TR_V0,X
  STA TR_VOL,X
.mf_end:
  RTS
.mf_rest:
  STZ TR_VOL,X
  RTS
.mf_drum:
  TAY
  LDA DR_V0,Y
  STA TR_VOL,X
  LDA DR_TPL,Y
  STA DR_PL
  LDA DR_TPH,Y
  STA DR_PH
  RTS

ADV_EV:                         ; next event: ZP_PTR += 2, back from a reference after its last event
  JSR ADV2
  LDA TR_RN,X
  BEQ .ae
  DEC TR_RN,X
  BNE .ae
  LDA TR_RL,X
  STA ZP_PTR
  LDA TR_RH,X
  STA ZP_PTR+1
.ae:
  RTS

ADV2:                           ; ZP_PTR += 2
  LDA ZP_PTR
  CLC
  ADC #2
  STA ZP_PTR
  BCC .a2
  INC ZP_PTR+1
.a2:
  RTS

; ---------------------------------------------------------------
; one frame of music: advances the tracks and fills the shadows
; ---------------------------------------------------------------
MUS_TICK:
  LDA MUS_ON
  BNE .mt_go
  RTS
.mt_go:
  LDX #4                        ; tone tracks 4..0
.mt_trk:
  LDA TR_ACT,X
  BEQ .mt_next
  DEC TR_CT,X
  BNE .mt_age
  JSR MUS_FETCH
  BRA .mt_next
.mt_age:
  INC TR_AGE,X
  LDA TR_CT,X                   ; last frame of the note: short gap?
  CMP #1
  BNE .mt_dec
  LDA TR_GAP,X
  BEQ .mt_dec
  LDA TR_PL,X
  STA ZP_PTR
  LDA TR_PH,X
  STA ZP_PTR+1
  LDA (ZP_PTR)
  CMP #$FE                      ; no gap before a tie
  BEQ .mt_dec
  STZ TR_VOL,X
  BRA .mt_next
.mt_dec:
  LDA TR_AGE,X                  ; decay down to the floor
  AND TR_DM,X
  BNE .mt_next
  LDA TR_VOL,X
  CMP TR_FL,X
  BEQ .mt_next
  BCC .mt_next
  DEC TR_VOL,X
.mt_next:
  DEX
  BPL .mt_trk
  ; ---- track 5: drums
  LDX #5
  LDA TR_ACT,X
  BEQ .mt_dr_end
  DEC TR_CT,X
  BNE .mt_dr_age
  JSR MUS_FETCH
  BRA .mt_dr_end
.mt_dr_age:
  INC TR_AGE,X
  LDY TR_NOTE,X
  BEQ .mt_dr_end
  LDA DR_PL                     ; tone slide (kick, toms)
  CLC
  ADC DR_SL,Y
  STA DR_PL
  BCC .mt_dr_s
  INC DR_PH
.mt_dr_s:
  LDA TR_AGE,X
  AND DR_DM,Y
  BNE .mt_dr_end
  LDA TR_VOL,X
  SEC
  SBC DR_DS,Y
  BCS .mt_dr_v
  LDA #0
.mt_dr_v:
  STA TR_VOL,X
.mt_dr_end:
  ; ---- left A = lead, right A = counter melody or lead + 1 (chorus)
  LDX #0
  JSR TRACK_PERIOD
  LDA T0
  STA SH_L+0
  LDA T1
  STA SH_L+1
  LDA TR_VOL
  STA SH_L+8
  LDA HAS4
  BNE .mt_cnt
  LDA T0
  CLC
  ADC #1
  STA SH_R+0
  LDA T1
  ADC #0
  STA SH_R+1
  LDA TR_VOL
  STA SH_R+8
  BRA .mt_h1
.mt_cnt:
  LDX #4
  JSR TRACK_PERIOD
  LDA T0
  STA SH_R+0
  LDA T1
  STA SH_R+1
  LDA TR_VOL+4
  STA SH_R+8
.mt_h1:
  ; ---- left B = harmony 1
  LDX #1
  JSR TRACK_PERIOD
  LDA T0
  STA SH_L+2
  LDA T1
  STA SH_L+3
  LDA TR_VOL+1
  STA SH_L+9
  ; ---- left C = bass, right C = harmony 2 or bass
  LDX #2
  JSR TRACK_PERIOD
  LDA T0
  STA SH_L+4
  LDA T1
  STA SH_L+5
  LDA TR_VOL+2
  STA SH_L+10
  LDA HAS3
  BNE .mt_h2
  LDA T0
  STA SH_R+4
  LDA T1
  STA SH_R+5
  LDA TR_VOL+2
  STA SH_R+10
  BRA .mt_dr
.mt_h2:
  LDX #3
  JSR TRACK_PERIOD
  LDA T0
  STA SH_R+4
  LDA T1
  STA SH_R+5
  LDA TR_VOL+3
  STA SH_R+10
.mt_dr:
  ; ---- right B = drums
  LDY TR_NOTE+5
  LDA DR_NP,Y
  STA SH_R+6
  LDA DR_MIX,Y
  ORA #$28                      ; noise A and C off
  STA SH_R+7
  LDA DR_PL
  STA SH_R+2
  LDA DR_PH
  AND #$0F
  STA SH_R+3
  LDA TR_VOL+5
  STA SH_R+9
  ; ---- song over?
  LDX #5
.mt_any:
  LDA TR_ACT,X
  BNE .mt_end
  DEX
  BPL .mt_any
  STZ MUS_ON
  LDX #2                        ; all the volumes to 0
.mt_sil:
  STZ SH_L+8,X
  STZ SH_R+8,X
  DEX
  BPL .mt_sil
.mt_end:
  RTS

; ---------------------------------------------------------------
; period of track X in T0/T1, with the vibrato of long notes
; ---------------------------------------------------------------
TRACK_PERIOD:
  LDY TR_NOTE,X
  LDA NT_LO,Y
  STA T0
  LDA NT_HI,Y
  STA T1
  LDA TR_VIB,X
  BEQ .tp_end
  CMP TR_AGE,X
  BCS .tp_end                   ; the note is younger than the delay
  INC TR_VPH,X                  ; 10 frames per wave (6 Hz)
  LDA TR_VPH,X
  CMP #10
  BCC .tp_ph
  LDA #0
  STA TR_VPH,X
.tp_ph:
  TAY
  LDA T0                        ; depth = period / 128
  ASL A
  LDA T1
  ROL A
  BEQ .tp_end
  STA T2
  LDA VIB_TAB,Y
  BEQ .tp_end
  BMI .tp_minus
  LDA T0
  CLC
  ADC T2
  STA T0
  BCC .tp_end
  INC T1
  RTS
.tp_minus:
  LDA T0
  SEC
  SBC T2
  STA T0
  BCS .tp_end
  DEC T1
.tp_end:
  RTS

VIB_TAB:  .byte 0, 1, 1, 1, 0, 0, $FF, $FF, $FF, 0

; font 5x7 (from the miniVIC games): ASCII $20-$5F, 8 bytes each
FONT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $20,$20,$20,$00,$20,$20,$00,$00
  .byte $50,$50,$50,$00,$00,$00,$00,$00
  .byte $50,$50,$F8,$50,$F8,$50,$50,$00
  .byte $20,$78,$A0,$70,$28,$F0,$20,$00
  .byte $C0,$C8,$10,$20,$40,$98,$18,$00
  .byte $40,$A0,$A0,$40,$A8,$90,$68,$00
  .byte $20,$20,$40,$00,$00,$00,$00,$00
  .byte $20,$40,$80,$80,$80,$40,$20,$00
  .byte $20,$10,$08,$08,$08,$10,$20,$00
  .byte $20,$A8,$70,$20,$70,$A8,$20,$00
  .byte $00,$20,$20,$F8,$20,$20,$00,$00
  .byte $00,$00,$00,$00,$20,$20,$40,$00
  .byte $00,$00,$00,$F8,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$20,$00,$00
  .byte $00,$08,$10,$20,$40,$80,$00,$00
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00
  .byte $20,$60,$20,$20,$20,$20,$70,$00
  .byte $70,$88,$08,$30,$40,$80,$F8,$00
  .byte $F8,$08,$10,$30,$08,$88,$70,$00
  .byte $10,$30,$50,$90,$F8,$10,$10,$00
  .byte $F8,$80,$F0,$08,$08,$88,$70,$00
  .byte $38,$40,$80,$F0,$88,$88,$70,$00
  .byte $F8,$08,$10,$20,$40,$40,$40,$00
  .byte $70,$88,$88,$70,$88,$88,$70,$00
  .byte $70,$88,$88,$78,$08,$10,$E0,$00
  .byte $00,$00,$20,$00,$20,$00,$00,$00
  .byte $00,$00,$20,$00,$20,$20,$40,$00
  .byte $10,$20,$40,$80,$40,$20,$10,$00
  .byte $00,$00,$F8,$00,$F8,$00,$00,$00
  .byte $40,$20,$10,$08,$10,$20,$40,$00
  .byte $70,$88,$10,$20,$20,$00,$20,$00
  .byte $70,$88,$A8,$B8,$B0,$80,$78,$00
  .byte $20,$50,$88,$88,$F8,$88,$88,$00
  .byte $F0,$88,$88,$F0,$88,$88,$F0,$00
  .byte $70,$88,$80,$80,$80,$88,$70,$00
  .byte $F0,$88,$88,$88,$88,$88,$F0,$00
  .byte $F8,$80,$80,$F0,$80,$80,$F8,$00
  .byte $F8,$80,$80,$F0,$80,$80,$80,$00
  .byte $78,$80,$80,$80,$98,$88,$78,$00
  .byte $88,$88,$88,$F8,$88,$88,$88,$00
  .byte $70,$20,$20,$20,$20,$20,$70,$00
  .byte $08,$08,$08,$08,$08,$88,$70,$00
  .byte $88,$90,$A0,$C0,$A0,$90,$88,$00
  .byte $80,$80,$80,$80,$80,$80,$F8,$00
  .byte $88,$D8,$A8,$A8,$88,$88,$88,$00
  .byte $88,$88,$C8,$A8,$98,$88,$88,$00
  .byte $70,$88,$88,$88,$88,$88,$70,$00
  .byte $F0,$88,$88,$F0,$80,$80,$80,$00
  .byte $70,$88,$88,$88,$A8,$90,$68,$00
  .byte $F0,$88,$88,$F0,$A0,$90,$88,$00
  .byte $70,$88,$80,$70,$08,$88,$70,$00
  .byte $F8,$20,$20,$20,$20,$20,$20,$00
  .byte $88,$88,$88,$88,$88,$88,$70,$00
  .byte $88,$88,$88,$88,$50,$50,$20,$00
  .byte $88,$88,$88,$A8,$A8,$D8,$88,$00
  .byte $88,$88,$50,$20,$50,$88,$88,$00
  .byte $88,$88,$50,$20,$20,$20,$20,$00
  .byte $F8,$08,$10,$20,$40,$80,$F8,$00
  .byte $F8,$C0,$C0,$C0,$C0,$C0,$F8,$00
  .byte $00,$80,$40,$20,$10,$08,$00,$00
  .byte $F8,$18,$18,$18,$18,$18,$F8,$00
  .byte $00,$00,$20,$50,$88,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$F8,$00

; AY periods, 1 MHz clock (f = 62500 / period): index = MIDI note - 23 (1 = C1 ... 84 = B7), 0 = rest
NT_LO:
  .byte $00,$77,$0C,$A7,$47,$ED,$98,$47,$FC,$B4,$70,$31,$F4,$BC,$86,$53
  .byte $24,$F6,$CC,$A4,$7E,$5A,$38,$18,$FA,$DE,$C3,$AA,$92,$7B,$66,$52
  .byte $3F,$2D,$1C,$0C,$FD,$EF,$E1,$D5,$C9,$BE,$B3,$A9,$9F,$96,$8E,$86
  .byte $7F,$77,$71,$6A,$64,$5F,$59,$54,$50,$4B,$47,$43,$3F,$3C,$38,$35
  .byte $32,$2F,$2D,$2A,$28,$26,$24,$22,$20,$1E,$1C,$1B,$19,$18,$16,$15
  .byte $14,$13,$12,$11,$10
NT_HI:
  .byte $00,$07,$07,$06,$06,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03
  .byte $03,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00
; drums: 0 none, 1 kick, 2 snare, 3 hi-hat, 4 open hat, 5 crash, 6 low tom, 7 high tom, 8 rim
DR_NP: .byte $00,$00,$06,$01,$01,$02,$00,$00,$03
DR_MIX: .byte $12,$10,$00,$02,$02,$02,$10,$10,$00
DR_V0: .byte $00,$0F,$0E,$0A,$0A,$0F,$0E,$0E,$0C
DR_DM: .byte $00,$00,$00,$00,$01,$03,$01,$01,$00
DR_DS: .byte $00,$01,$01,$03,$01,$01,$01,$01,$04
DR_TPL: .byte $00,$18,$5E,$00,$00,$00,$F4,$4A,$64
DR_TPH: .byte $00,$01,$01,$00,$00,$00,$01,$01,$00
DR_SL: .byte $00,$46,$14,$00,$00,$00,$0C,$08,$00

; ---- IN THE HALL OF THE MOUNTAIN KING (EDVARD GRIEG 1875) ----
SONG_MOUNTAIN_KING:
  .word S_MOUNTAIN_KING_LEAD, S_MOUNTAIN_KING_HARM1, S_MOUNTAIN_KING_BASS, S_MOUNTAIN_KING_HARM2, S_MOUNTAIN_KING_COUNTER, S_MOUNTAIN_KING_DRUMS
  .byte 13, 0, 1, 0, 1      ; lead
  .byte 9, 0, 1, 0, 1      ; harm1
  .byte 12, 3, 3, 0, 1      ; bass
  .byte 8, 0, 1, 0, 1      ; harm2
  .byte 9, 0, 1, 0, 1      ; counter
S_MOUNTAIN_KING_LEAD:
  .byte $24,$1A,$26,$1A,$27,$1A,$29,$19,$2B,$1A,$27,$1A,$2B,$33,$2A,$19
  .byte $26,$1A,$2A,$32,$29,$1A,$25,$19,$29,$32,$24,$19,$26,$19,$27,$19
  .byte $29,$19,$2B,$18,$27,$19,$2B,$18,$30,$19,$2E,$18,$2B,$19,$27,$18
  .byte $2B,$19,$2E,$60,$24,$18,$26,$18,$27,$18,$29,$18,$2B,$17,$27,$18
  .byte $2B,$2F,$2A,$17,$26,$18,$2A,$2E,$29,$18,$25,$17,$29,$2E,$24,$17
  .byte $26,$17,$27,$17,$29,$16,$2B,$17,$27,$17,$2B,$16,$30,$17,$2E,$16
  .byte $2B,$17,$27,$16,$2B,$16,$2E,$59,$30,$16,$32,$16,$33,$16,$35,$15
  .byte $37,$16,$33,$16,$37,$2B,$36,$15,$32,$16,$36,$2A,$35,$16,$31,$15
  .byte $35,$2A,$30,$15,$32,$15,$33,$15,$35,$15,$37,$14,$33,$15,$37,$14
  .byte $3C,$15,$3A,$14,$37,$15,$33,$14,$37,$15,$3A,$50,$2B,$14,$2D,$14
  .byte $2E,$14,$30,$14,$32,$13,$2E,$14,$32,$27,$31,$13,$2D,$14,$31,$27
  .byte $30,$13,$2C,$13,$30,$26,$2B,$13,$2D,$13,$2E,$13,$30,$13,$32,$12
  .byte $2E,$13,$32,$12,$37,$13,$35,$12,$32,$13,$2E,$12,$32,$13,$35,$48
  .byte $FD,$0E,$30,$12,$32,$12,$33,$12,$35,$11,$37,$12,$33,$11,$37,$23
  .byte $36,$11,$32,$11,$36,$22,$35,$11,$31,$11,$35,$21,$30,$10,$32,$11
  .byte $33,$10,$35,$10,$37,$10,$33,$10,$37,$10,$3C,$10,$3A,$10,$37,$0F
  .byte $33,$10,$37,$0F,$3A,$3D,$30,$0F,$32,$0F,$33,$0F,$35,$0E,$37,$0F
  .byte $33,$0E,$37,$1D,$36,$0E,$32,$0E,$36,$1C,$35,$0E,$31,$0E,$35,$1B
  .byte $30,$0D,$32,$0E,$33,$0D,$35,$0D,$37,$0D,$33,$0D,$37,$0D,$3C,$0D
  .byte $3A,$0D,$37,$0C,$33,$0D,$37,$0C,$3A,$31,$FD,$0F,$30,$0C,$32,$0C
  .byte $33,$0C,$35,$0B,$37,$0C,$33,$0C,$37,$17,$36,$0B,$32,$0C,$36,$16
  .byte $35,$0C,$31,$0B,$35,$16,$30,$0B,$32,$0B,$33,$0B,$35,$0A,$37,$0B
  .byte $33,$0B,$37,$0A,$3C,$0B,$3A,$0A,$37,$0B,$33,$0A,$37,$0A,$3A,$29
  .byte $30,$0A,$00,$1F,$30,$0B,$00,$20,$30,$0B,$00,$0C,$2B,$0D,$00,$0D
  .byte $30,$0F,$00,$0E,$2B,$10,$00,$10,$30,$9A,$FF
S_MOUNTAIN_KING_HARM1:
  .byte $00,$CE,$00,$CA,$00,$C6,$00,$C2,$00,$18,$27,$18,$00,$18,$27,$18
  .byte $00,$17,$27,$18,$00,$17,$27,$18,$00,$17,$26,$18,$00,$17,$26,$17
  .byte $00,$18,$25,$17,$00,$17,$25,$17,$00,$17,$27,$17,$00,$17,$27,$16
  .byte $00,$17,$27,$17,$00,$16,$27,$17,$00,$16,$1F,$17,$00,$16,$1F,$16
  .byte $00,$17,$1F,$16,$00,$16,$1F,$16,$00,$16,$27,$16,$00,$16,$27,$15
  .byte $00,$16,$27,$16,$00,$15,$27,$16,$00,$15,$26,$16,$00,$15,$26,$15
  .byte $00,$16,$25,$15,$00,$15,$25,$15,$00,$15,$27,$15,$00,$15,$27,$15
  .byte $00,$14,$27,$15,$00,$14,$27,$15,$00,$14,$1F,$15,$00,$14,$1F,$15
  .byte $00,$14,$1F,$14,$00,$14,$1F,$14,$00,$14,$2E,$14,$00,$14,$2E,$14
  .byte $00,$13,$2E,$14,$00,$13,$2E,$14,$00,$13,$2D,$14,$00,$13,$2D,$14
  .byte $00,$13,$2C,$13,$00,$13,$2C,$13,$00,$13,$2E,$13,$00,$13,$2E,$13
  .byte $00,$12,$2E,$13,$00,$12,$2E,$13,$00,$12,$26,$13,$00,$12,$26,$13
  .byte $00,$12,$26,$12,$00,$12,$26,$12,$00,$12,$27,$12,$00,$12,$27,$11
  .byte $00,$12,$27,$11,$00,$12,$27,$11,$00,$11,$26,$11,$00,$11,$26,$11
  .byte $00,$11,$25,$11,$00,$10,$25,$11,$00,$10,$27,$11,$00,$10,$27,$10
  .byte $00,$10,$27,$10,$FC,<(S_MOUNTAIN_KING_HARM1+236),>(S_MOUNTAIN_KING_HARM1+236),$03,$1F,$0F,$00,$10,$1F,$0F,$00,$10
  .byte $1F,$0F,$00,$0F,$1F,$0F,$00,$0F,$27,$0F,$00,$0F,$27,$0E,$00,$0F
  .byte $27,$0E,$00,$0F,$27,$0E,$00,$0E,$26,$0E,$00,$0E,$26,$0E,$00,$0E
  .byte $25,$0E,$00,$0D,$25,$0E,$00,$0D,$27,$0E,$00,$0D,$27,$0D,$00,$0D
  .byte $27,$0D,$FC,<(S_MOUNTAIN_KING_HARM1+298),>(S_MOUNTAIN_KING_HARM1+298),$03,$1F,$0C,$00,$0D,$1F,$0C,$00,$0D,$1F,$0C
  .byte $00,$0C,$1F,$0C,$00,$0C,$27,$0C,$00,$0C,$27,$0B,$00,$0C,$27,$0C
  .byte $00,$0B,$27,$0C,$00,$0B,$26,$0C,$00,$0B,$26,$0B,$00,$0C,$25,$0B
  .byte $00,$0B,$25,$0B,$00,$0B,$27,$0B,$00,$0B,$27,$0A,$00,$0B,$27,$0B
  .byte $00,$0A,$27,$0B,$00,$0A,$1F,$0B,$00,$0A,$1F,$0A,$00,$0B,$1F,$0A
  .byte $00,$0A,$1F,$0A,$27,$0A,$00,$1F,$27,$0B,$00,$20,$27,$0B,$00,$0C
  .byte $26,$0D,$00,$0D,$27,$0F,$00,$0E,$26,$10,$00,$10,$27,$9A,$FF
S_MOUNTAIN_KING_BASS:
  .byte $0C,$34,$13,$33,$0C,$34,$13,$33,$0C,$33,$13,$32,$0C,$33,$13,$32
  .byte $0C,$32,$13,$32,$0C,$31,$13,$31,$07,$31,$0E,$31,$07,$30,$0E,$30
  .byte $0C,$30,$13,$30,$0C,$2F,$13,$2F,$0C,$2F,$13,$2E,$0C,$2F,$13,$2E
  .byte $0C,$2E,$13,$2D,$0C,$2E,$13,$2D,$07,$2D,$0E,$2C,$07,$2D,$0E,$2C
  .byte $0C,$2C,$13,$2B,$0C,$2C,$13,$2B,$0C,$2B,$13,$2A,$0C,$2B,$13,$2A
  .byte $0C,$2A,$13,$2A,$0C,$29,$13,$29,$07,$29,$0E,$29,$07,$28,$0E,$28
  .byte $13,$28,$1A,$28,$13,$27,$1A,$27,$13,$27,$1A,$27,$13,$26,$1A,$26
  .byte $13,$26,$1A,$26,$13,$25,$1A,$25,$0E,$25,$15,$25,$0E,$24,$15,$24
  .byte $0C,$24,$13,$23,$0C,$23,$13,$23,$0C,$22,$13,$22,$0C,$22,$13,$21
  .byte $0C,$21,$13,$20,$0C,$20,$13,$20,$07,$1F,$0E,$1F,$07,$1F,$0E,$1E
  .byte $0C,$1E,$13,$1D,$0C,$1D,$13,$1D,$0C,$1C,$13,$1C,$0C,$1C,$13,$1B
  .byte $0C,$1B,$13,$1A,$0C,$1A,$13,$1A,$07,$19,$0E,$19,$07,$19,$0E,$18
  .byte $0C,$18,$13,$17,$0C,$18,$13,$17,$0C,$17,$13,$16,$0C,$17,$13,$16
  .byte $0C,$16,$13,$15,$0C,$16,$13,$15,$07,$15,$0E,$14,$07,$15,$0E,$14
  .byte $0C,$0A,$00,$1F,$0C,$0B,$00,$20,$0C,$0B,$00,$0C,$07,$0D,$00,$0D
  .byte $0C,$0F,$00,$0E,$07,$10,$00,$10,$0C,$9A,$FF
S_MOUNTAIN_KING_HARM2:
  .byte $00,$CE,$00,$CA,$00,$C6,$00,$C2,$00,$18,$1F,$18,$00,$18,$1F,$18
  .byte $00,$17,$1F,$18,$00,$17,$1F,$18,$00,$17,$1E,$18,$00,$17,$1E,$17
  .byte $00,$18,$1D,$17,$00,$17,$1D,$17,$00,$17,$1F,$17,$00,$17,$1F,$16
  .byte $00,$17,$1F,$17,$00,$16,$1F,$17,$00,$16,$1B,$17,$00,$16,$1B,$16
  .byte $00,$17,$1B,$16,$00,$16,$1B,$16,$00,$16,$1F,$16,$00,$16,$1F,$15
  .byte $00,$16,$1F,$16,$00,$15,$1F,$16,$00,$15,$1E,$16,$00,$15,$1E,$15
  .byte $00,$16,$1D,$15,$00,$15,$1D,$15,$00,$15,$1F,$15,$00,$15,$1F,$15
  .byte $00,$14,$1F,$15,$00,$14,$1F,$15,$00,$14,$1B,$15,$00,$14,$1B,$15
  .byte $00,$14,$1B,$14,$00,$14,$1B,$14,$00,$14,$26,$14,$00,$14,$26,$14
  .byte $00,$13,$26,$14,$00,$13,$26,$14,$00,$13,$25,$14,$00,$13,$25,$14
  .byte $00,$13,$24,$13,$00,$13,$24,$13,$00,$13,$26,$13,$00,$13,$26,$13
  .byte $00,$12,$26,$13,$00,$12,$26,$13,$00,$12,$22,$13,$00,$12,$22,$13
  .byte $00,$12,$22,$12,$00,$12,$22,$12,$00,$12,$1F,$12,$00,$12,$1F,$11
  .byte $00,$12,$1F,$11,$00,$12,$1F,$11,$00,$11,$1E,$11,$00,$11,$1E,$11
  .byte $00,$11,$1D,$11,$00,$10,$1D,$11,$00,$10,$1F,$11,$00,$10,$1F,$10
  .byte $00,$10,$1F,$10,$FC,<(S_MOUNTAIN_KING_HARM2+236),>(S_MOUNTAIN_KING_HARM2+236),$03,$1B,$0F,$00,$10,$1B,$0F,$00,$10
  .byte $1B,$0F,$00,$0F,$1B,$0F,$00,$0F,$1F,$0F,$00,$0F,$1F,$0E,$00,$0F
  .byte $1F,$0E,$00,$0F,$1F,$0E,$00,$0E,$1E,$0E,$00,$0E,$1E,$0E,$00,$0E
  .byte $1D,$0E,$00,$0D,$1D,$0E,$00,$0D,$1F,$0E,$00,$0D,$1F,$0D,$00,$0D
  .byte $1F,$0D,$FC,<(S_MOUNTAIN_KING_HARM2+298),>(S_MOUNTAIN_KING_HARM2+298),$03,$1B,$0C,$00,$0D,$1B,$0C,$00,$0D,$1B,$0C
  .byte $00,$0C,$1B,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0B,$00,$0C,$1F,$0C
  .byte $00,$0B,$1F,$0C,$00,$0B,$1E,$0C,$00,$0B,$1E,$0B,$00,$0C,$1D,$0B
  .byte $00,$0B,$1D,$0B,$00,$0B,$1F,$0B,$00,$0B,$1F,$0A,$00,$0B,$1F,$0B
  .byte $00,$0A,$1F,$0B,$00,$0A,$1B,$0B,$00,$0A,$1B,$0A,$00,$0B,$1B,$0A
  .byte $00,$0A,$1B,$0A,$1F,$0A,$00,$1F,$1F,$0B,$00,$20,$1F,$0B,$00,$0C
  .byte $23,$0D,$00,$0D,$1F,$0F,$00,$0E,$23,$10,$00,$10,$1F,$9A,$FF
S_MOUNTAIN_KING_COUNTER:
  .byte $18,$1A,$1A,$1A,$1B,$1A,$1D,$19,$1F,$1A,$1B,$1A,$1F,$33,$1E,$19
  .byte $1A,$1A,$1E,$32,$1D,$1A,$19,$19,$1D,$32,$18,$19,$1A,$19,$1B,$19
  .byte $1D,$19,$1F,$18,$1B,$19,$1F,$18,$24,$19,$22,$18,$1F,$19,$1B,$18
  .byte $1F,$19,$22,$60,$18,$18,$1A,$18,$1B,$18,$1D,$18,$1F,$17,$1B,$18
  .byte $1F,$2F,$1E,$17,$1A,$18,$1E,$2E,$1D,$18,$19,$17,$1D,$2E,$18,$17
  .byte $1A,$17,$1B,$17,$1D,$16,$1F,$17,$1B,$17,$1F,$16,$24,$17,$22,$16
  .byte $1F,$17,$1B,$16,$1F,$16,$22,$59,$24,$16,$26,$16,$27,$16,$29,$15
  .byte $2B,$16,$27,$16,$2B,$2B,$2A,$15,$26,$16,$2A,$2A,$29,$16,$25,$15
  .byte $29,$2A,$24,$15,$26,$15,$27,$15,$29,$15,$2B,$14,$27,$15,$2B,$14
  .byte $30,$15,$2E,$14,$2B,$15,$27,$14,$2B,$15,$2E,$50,$1F,$14,$21,$14
  .byte $22,$14,$24,$14,$26,$13,$22,$14,$26,$27,$25,$13,$21,$14,$25,$27
  .byte $24,$13,$20,$13,$24,$26,$1F,$13,$21,$13,$22,$13,$24,$13,$26,$12
  .byte $22,$13,$26,$12,$2B,$13,$29,$12,$26,$13,$22,$12,$26,$13,$29,$48
  .byte $24,$12,$26,$12,$27,$12,$29,$11,$2B,$12,$27,$11,$2B,$23,$2A,$11
  .byte $26,$11,$2A,$22,$29,$11,$25,$11,$29,$21,$24,$10,$26,$11,$27,$10
  .byte $29,$10,$2B,$10,$27,$10,$2B,$10,$30,$10,$2E,$10,$2B,$0F,$27,$10
  .byte $2B,$0F,$2E,$3D,$24,$0F,$26,$0F,$27,$0F,$29,$0E,$2B,$0F,$27,$0E
  .byte $2B,$1D,$2A,$0E,$26,$0E,$2A,$1C,$29,$0E,$25,$0E,$29,$1B,$24,$0D
  .byte $26,$0E,$27,$0D,$29,$0D,$2B,$0D,$27,$0D,$2B,$0D,$30,$0D,$2E,$0D
  .byte $2B,$0C,$27,$0D,$2B,$0C,$2E,$31,$24,$0C,$26,$0C,$27,$0C,$29,$0B
  .byte $2B,$0C,$27,$0C,$2B,$17,$2A,$0B,$26,$0C,$2A,$16,$29,$0C,$25,$0B
  .byte $29,$16,$24,$0B,$26,$0B,$27,$0B,$29,$0A,$2B,$0B,$27,$0B,$2B,$0A
  .byte $30,$0B,$2E,$0A,$2B,$0B,$27,$0A,$2B,$0A,$2E,$29,$24,$0A,$00,$1F
  .byte $24,$0B,$00,$20,$24,$0B,$00,$0C,$1F,$0D,$00,$0D,$24,$0F,$00,$0E
  .byte $1F,$10,$00,$10,$24,$9A,$FF
S_MOUNTAIN_KING_DRUMS:
  .byte $00,$CE,$00,$CA,$00,$C6,$00,$C2,$00,$BE,$00,$BA,$00,$B6,$00,$B2
  .byte $01,$2C,$03,$2B,$01,$2C,$03,$2B,$01,$2B,$03,$2A,$01,$2B,$03,$2A
  .byte $01,$2A,$03,$2A,$01,$29,$03,$29,$01,$29,$03,$29,$01,$28,$03,$28
  .byte $01,$28,$03,$28,$01,$27,$03,$27,$01,$27,$03,$27,$01,$26,$03,$26
  .byte $01,$26,$03,$26,$01,$25,$03,$25,$01,$25,$03,$25,$01,$24,$03,$24
  .byte $01,$12,$03,$12,$02,$12,$03,$11,$01,$12,$03,$11,$02,$12,$03,$11
  .byte $01,$11,$03,$11,$02,$11,$FC,<(S_MOUNTAIN_KING_DRUMS+94),>(S_MOUNTAIN_KING_DRUMS+94),$03,$02,$10,$03,$11,$01,$10
  .byte $03,$11,$02,$10,$03,$10,$01,$10,$03,$10,$FC,<(S_MOUNTAIN_KING_DRUMS+114),>(S_MOUNTAIN_KING_DRUMS+114),$03,$03,$0F
  .byte $02,$10,$03,$0F,$01,$10,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F
  .byte $02,$0F,$03,$0E,$01,$0F,$01,$0E,$02,$0F,$03,$0E,$01,$0E,$03,$0E
  .byte $02,$0E,$03,$0E,$01,$0E,$01,$0E,$02,$0D,$03,$0E,$01,$0D,$03,$0E
  .byte $02,$0D,$03,$0D,$01,$0D,$01,$0D,$FC,<(S_MOUNTAIN_KING_DRUMS+176),>(S_MOUNTAIN_KING_DRUMS+176),$03,$02,$0C,$02,$0D
  .byte $02,$0C,$02,$06,$02,$07,$02,$06,$02,$06,$02,$06,$FC,<(S_MOUNTAIN_KING_DRUMS+198),>(S_MOUNTAIN_KING_DRUMS+198),$03
  .byte $05,$0C,$03,$0C,$02,$0C,$03,$0B,$01,$0C,$03,$0C,$02,$0B,$03,$0C
  .byte $01,$0B,$03,$0C,$02,$0B,$03,$0B,$01,$0C,$01,$0B,$02,$0B,$03,$0B
  .byte $01,$0B,$03,$0B,$02,$0B,$03,$0A,$01,$0B,$01,$0B,$02,$0A,$03,$0B
  .byte $01,$0A,$02,$0B,$02,$0A,$02,$0A,$02,$06,$02,$05,$02,$05,$02,$05
  .byte $FC,<(S_MOUNTAIN_KING_DRUMS+266),>(S_MOUNTAIN_KING_DRUMS+266),$03,$02,$05,$05,$0A,$00,$1F,$05,$0B,$00,$20,$01,$0B
  .byte $00,$0C,$01,$0D,$00,$0D,$01,$0F,$00,$0E,$02,$10,$02,$10,$05,$9A
  .byte $FF

; ---- KOROBEINIKI  (RUSSIAN FOLK SONG) ----
SONG_KOROBEINIKI:
  .word S_KOROBEINIKI_LEAD, S_KOROBEINIKI_HARM1, S_KOROBEINIKI_BASS, S_KOROBEINIKI_HARM2, S_KOROBEINIKI_COUNTER, S_KOROBEINIKI_DRUMS
  .byte 13, 6, 3, 14, 1      ; lead
  .byte 8, 2, 1, 0, 1      ; harm1
  .byte 12, 4, 3, 0, 1      ; bass
  .byte 7, 2, 1, 0, 1      ; harm2
  .byte 9, 4, 3, 14, 1      ; counter
S_KOROBEINIKI_LEAD:
  .byte $00,$90,$00,$90,$35,$24,$30,$12,$31,$12,$33,$23,$31,$12,$30,$12
  .byte $2E,$23,$2E,$12,$31,$12,$35,$23,$33,$11,$31,$12,$30,$34,$31,$12
  .byte $33,$22,$35,$23,$31,$22,$2E,$23,$2E,$44,$00,$11,$33,$22,$36,$11
  .byte $3A,$21,$38,$11,$36,$11,$35,$32,$31,$11,$35,$21,$33,$10,$31,$11
  .byte $30,$21,$30,$10,$31,$11,$33,$20,$35,$21,$31,$20,$2E,$21,$2E,$20
  .byte $00,$20,$35,$20,$30,$10,$31,$10,$33,$1F,$31,$10,$30,$10,$2E,$1F
  .byte $2E,$10,$31,$10,$35,$1F,$33,$0F,$31,$10,$30,$2E,$31,$10,$33,$1E
  .byte $35,$1F,$31,$1E,$2E,$1F,$2E,$3C,$00,$0F,$33,$1E,$36,$0F,$3A,$1D
  .byte $38,$0F,$36,$0F,$35,$2C,$31,$0F,$35,$1D,$33,$0E,$31,$0F,$30,$1D
  .byte $30,$0E,$31,$0F,$33,$1C,$35,$1D,$31,$1C,$2E,$1D,$2E,$1C,$00,$1C
  .byte $41,$1C,$3C,$0E,$3D,$0E,$3F,$1B,$3D,$0E,$3C,$0E,$3A,$1B,$3A,$0E
  .byte $3D,$0E,$41,$1B,$3F,$0D,$3D,$0E,$3C,$28,$3D,$0E,$3F,$1A,$41,$1B
  .byte $3D,$1A,$3A,$1B,$3A,$34,$00,$0D,$3F,$1A,$42,$0D,$46,$19,$44,$0D
  .byte $42,$0D,$41,$26,$3D,$0D,$41,$19,$3F,$0C,$3D,$0D,$3C,$19,$3C,$0C
  .byte $3D,$0D,$3F,$18,$41,$19,$3D,$18,$3A,$19,$3A,$18,$00,$18,$FD,$0F
  .byte $41,$18,$3C,$0C,$3D,$0C,$3F,$17,$3D,$0C,$3C,$0B,$3A,$18,$3A,$0B
  .byte $3D,$0C,$41,$16,$3F,$0C,$3D,$0B,$3C,$22,$3D,$0B,$3F,$16,$41,$15
  .byte $3D,$16,$3A,$16,$3A,$2A,$00,$0A,$3F,$15,$42,$0B,$46,$14,$44,$0A
  .byte $42,$0A,$41,$1F,$3D,$0A,$41,$13,$3F,$0A,$3D,$0A,$3C,$13,$3C,$0A
  .byte $3D,$0A,$3F,$13,$41,$12,$3D,$13,$3A,$13,$3A,$12,$00,$12,$3A,$09
  .byte $00,$0A,$35,$0B,$00,$0B,$3A,$18,$00,$1B,$FF
S_KOROBEINIKI_HARM1:
  .byte $00,$24,$25,$24,$00,$24,$25,$24,$FC,<(S_KOROBEINIKI_HARM1+0),>(S_KOROBEINIKI_HARM1+0),$04,$00,$24,$21,$24
  .byte $00,$23,$21,$24,$00,$23,$25,$24,$00,$23,$25,$23,$00,$23,$21,$23
  .byte $00,$22,$21,$23,$00,$22,$25,$23,$00,$22,$25,$22,$00,$22,$1E,$22
  .byte $00,$21,$1E,$22,$00,$21,$25,$22,$00,$21,$25,$21,$00,$21,$21,$21
  .byte $00,$20,$21,$21,$00,$20,$25,$21,$00,$20,$25,$20,$00,$20,$21,$20
  .byte $00,$1F,$21,$20,$00,$1F,$25,$20,$00,$1F,$25,$1F,$00,$1F,$21,$1F
  .byte $00,$1E,$21,$1F,$00,$1E,$25,$1F,$00,$1E,$25,$1E,$00,$1E,$1E,$1E
  .byte $00,$1D,$1E,$1E,$00,$1D,$25,$1E,$00,$1D,$25,$1D,$00,$1D,$21,$1D
  .byte $00,$1C,$21,$1D,$00,$1C,$25,$1D,$00,$1C,$25,$1C,$00,$1C,$21,$1C
  .byte $00,$1B,$21,$1C,$00,$1B,$25,$1C,$00,$1B,$25,$1B,$00,$1B,$21,$1B
  .byte $00,$1A,$21,$1B,$00,$1A,$25,$1B,$00,$1A,$25,$1A,$00,$1A,$1E,$1A
  .byte $00,$19,$1E,$1A,$00,$19,$25,$1A,$00,$19,$25,$19,$00,$19,$21,$19
  .byte $00,$18,$21,$19,$00,$18,$25,$19,$00,$18,$25,$18,$00,$18,$21,$18
  .byte $00,$17,$21,$17,$00,$18,$25,$17,$00,$16,$25,$17,$00,$16,$21,$17
  .byte $00,$16,$21,$15,$00,$16,$25,$16,$00,$15,$25,$15,$00,$15,$1E,$15
  .byte $00,$14,$1E,$14,$00,$15,$25,$14,$00,$13,$25,$14,$00,$13,$21,$14
  .byte $00,$13,$21,$12,$00,$13,$25,$13,$00,$12,$25,$12,$25,$09,$00,$0A
  .byte $25,$0B,$00,$0B,$25,$18,$00,$1B,$FF
S_KOROBEINIKI_BASS:
  .byte $16,$24,$00,$24,$11,$24,$00,$24,$FC,<(S_KOROBEINIKI_BASS+0),>(S_KOROBEINIKI_BASS+0),$04,$11,$24,$00,$24
  .byte $0C,$23,$00,$24,$16,$23,$00,$24,$11,$23,$00,$23,$11,$23,$00,$23
  .byte $0C,$22,$00,$23,$16,$22,$00,$23,$11,$22,$00,$22,$0F,$22,$00,$22
  .byte $0A,$21,$00,$22,$16,$21,$00,$22,$11,$21,$00,$21,$11,$21,$00,$21
  .byte $0C,$20,$00,$21,$16,$20,$00,$21,$11,$20,$00,$20,$11,$20,$00,$20
  .byte $0C,$1F,$00,$20,$16,$1F,$00,$20,$11,$1F,$00,$1F,$11,$1F,$00,$1F
  .byte $0C,$1E,$00,$1F,$16,$1E,$00,$1F,$11,$1E,$00,$1E,$0F,$1E,$00,$1E
  .byte $0A,$1D,$00,$1E,$16,$1D,$00,$1E,$11,$1D,$00,$1D,$11,$1D,$00,$1D
  .byte $0C,$1C,$00,$1D,$16,$1C,$00,$1D,$11,$1C,$00,$1C,$11,$1C,$00,$1C
  .byte $0C,$1B,$00,$1C,$16,$1B,$00,$1C,$11,$1B,$00,$1B,$11,$1B,$00,$1B
  .byte $0C,$1A,$00,$1B,$16,$1A,$00,$1B,$11,$1A,$00,$1A,$0F,$1A,$00,$1A
  .byte $0A,$19,$00,$1A,$16,$19,$00,$1A,$11,$19,$00,$19,$11,$19,$00,$19
  .byte $0C,$18,$00,$19,$16,$18,$00,$19,$11,$18,$00,$18,$11,$18,$00,$18
  .byte $0C,$17,$00,$17,$16,$18,$00,$17,$11,$16,$00,$17,$11,$16,$00,$17
  .byte $0C,$16,$00,$15,$16,$16,$00,$16,$11,$15,$00,$15,$0F,$15,$00,$15
  .byte $0A,$14,$00,$14,$16,$15,$00,$14,$11,$13,$00,$14,$11,$13,$00,$14
  .byte $0C,$13,$00,$12,$16,$13,$00,$13,$11,$12,$00,$12,$16,$09,$00,$0A
  .byte $11,$0B,$00,$0B,$0A,$18,$00,$1B,$FF
S_KOROBEINIKI_HARM2:
  .byte $00,$24,$29,$24,$00,$24,$29,$24,$FC,<(S_KOROBEINIKI_HARM2+0),>(S_KOROBEINIKI_HARM2+0),$04,$00,$24,$24,$24
  .byte $00,$23,$24,$24,$00,$23,$29,$24,$00,$23,$29,$23,$00,$23,$24,$23
  .byte $00,$22,$24,$23,$00,$22,$29,$23,$00,$22,$29,$22,$00,$22,$22,$22
  .byte $00,$21,$22,$22,$00,$21,$29,$22,$00,$21,$29,$21,$00,$21,$24,$21
  .byte $00,$20,$24,$21,$00,$20,$29,$21,$00,$20,$29,$20,$00,$20,$24,$20
  .byte $00,$1F,$24,$20,$00,$1F,$29,$20,$00,$1F,$29,$1F,$00,$1F,$24,$1F
  .byte $00,$1E,$24,$1F,$00,$1E,$29,$1F,$00,$1E,$29,$1E,$00,$1E,$22,$1E
  .byte $00,$1D,$22,$1E,$00,$1D,$29,$1E,$00,$1D,$29,$1D,$00,$1D,$24,$1D
  .byte $00,$1C,$24,$1D,$00,$1C,$29,$1D,$00,$1C,$29,$1C,$00,$1C,$24,$1C
  .byte $00,$1B,$24,$1C,$00,$1B,$29,$1C,$00,$1B,$29,$1B,$00,$1B,$24,$1B
  .byte $00,$1A,$24,$1B,$00,$1A,$29,$1B,$00,$1A,$29,$1A,$00,$1A,$22,$1A
  .byte $00,$19,$22,$1A,$00,$19,$29,$1A,$00,$19,$29,$19,$00,$19,$24,$19
  .byte $00,$18,$24,$19,$00,$18,$29,$19,$00,$18,$29,$18,$00,$18,$24,$18
  .byte $00,$17,$24,$17,$00,$18,$29,$17,$00,$16,$29,$17,$00,$16,$24,$17
  .byte $00,$16,$24,$15,$00,$16,$29,$16,$00,$15,$29,$15,$00,$15,$22,$15
  .byte $00,$14,$22,$14,$00,$15,$29,$14,$00,$13,$29,$14,$00,$13,$24,$14
  .byte $00,$13,$24,$12,$00,$13,$29,$13,$00,$12,$29,$12,$29,$09,$00,$0A
  .byte $29,$0B,$00,$0B,$2E,$18,$00,$1B,$FF
S_KOROBEINIKI_COUNTER:
  .byte $00,$90,$00,$90,$29,$24,$24,$12,$25,$12,$27,$23,$25,$12,$24,$12
  .byte $22,$23,$22,$12,$25,$12,$29,$23,$27,$11,$25,$12,$24,$34,$25,$12
  .byte $27,$22,$29,$23,$25,$22,$22,$23,$22,$44,$00,$11,$27,$22,$2A,$11
  .byte $2E,$21,$2C,$11,$2A,$11,$29,$32,$25,$11,$29,$21,$27,$10,$25,$11
  .byte $24,$21,$24,$10,$25,$11,$27,$20,$29,$21,$25,$20,$22,$21,$22,$20
  .byte $00,$20,$31,$20,$2D,$10,$2E,$10,$30,$1F,$2E,$10,$2D,$10,$2A,$1F
  .byte $2A,$10,$2E,$10,$31,$1F,$30,$0F,$2E,$10,$2D,$2E,$2E,$10,$30,$1E
  .byte $31,$1F,$2E,$1E,$2A,$1F,$2A,$3C,$00,$0F,$30,$1E,$33,$0F,$36,$1D
  .byte $35,$0F,$33,$0F,$31,$2C,$2E,$0F,$31,$1D,$30,$0E,$2E,$0F,$2D,$1D
  .byte $2D,$0E,$2E,$0F,$30,$1C,$31,$1D,$2E,$1C,$2A,$1D,$2A,$1C,$00,$1C
  .byte $35,$1C,$30,$0E,$31,$0E,$33,$1B,$31,$0E,$30,$0E,$2E,$1B,$2E,$0E
  .byte $31,$0E,$35,$1B,$33,$0D,$31,$0E,$30,$28,$31,$0E,$33,$1A,$35,$1B
  .byte $31,$1A,$2E,$1B,$2E,$34,$00,$0D,$33,$1A,$36,$0D,$3A,$19,$38,$0D
  .byte $36,$0D,$35,$26,$31,$0D,$35,$19,$33,$0C,$31,$0D,$30,$19,$30,$0C
  .byte $31,$0D,$33,$18,$35,$19,$31,$18,$2E,$19,$2E,$18,$00,$18,$3D,$18
  .byte $39,$0C,$3A,$0C,$3C,$17,$3A,$0C,$39,$0B,$36,$18,$36,$0B,$3A,$0C
  .byte $3D,$16,$3C,$0C,$3A,$0B,$39,$22,$3A,$0B,$3C,$16,$3D,$15,$3A,$16
  .byte $36,$16,$36,$2A,$00,$0A,$3C,$15,$3F,$0B,$42,$14,$41,$0A,$3F,$0A
  .byte $3D,$1F,$3A,$0A,$3D,$13,$3C,$0A,$3A,$0A,$39,$13,$39,$0A,$3A,$0A
  .byte $3C,$13,$3D,$12,$3A,$13,$36,$13,$36,$12,$00,$12,$2E,$09,$00,$0A
  .byte $31,$0B,$00,$0B,$35,$18,$00,$1B,$FF
S_KOROBEINIKI_DRUMS:
  .byte $01,$24,$03,$24,$01,$24,$03,$24,$FC,<(S_KOROBEINIKI_DRUMS+0),>(S_KOROBEINIKI_DRUMS+0),$03,$02,$24,$01,$24
  .byte $03,$24,$01,$23,$03,$24,$01,$23,$03,$24,$01,$23,$03,$23,$01,$23
  .byte $03,$23,$01,$22,$03,$23,$01,$22,$03,$23,$01,$22,$03,$22,$01,$22
  .byte $03,$22,$01,$21,$03,$22,$01,$21,$03,$22,$01,$21,$03,$21,$01,$21
  .byte $03,$21,$01,$20,$03,$21,$01,$20,$03,$21,$01,$20,$03,$20,$01,$20
  .byte $03,$20,$01,$1F,$03,$20,$01,$1F,$03,$20,$01,$1F,$03,$1F,$01,$1F
  .byte $03,$1F,$01,$1E,$03,$1F,$01,$1E,$03,$1F,$01,$1E,$03,$1E,$01,$1E
  .byte $03,$1E,$01,$1D,$03,$1E,$01,$1D,$03,$1E,$01,$1D,$03,$1D,$01,$1D
  .byte $03,$1D,$01,$1C,$03,$1D,$01,$1C,$03,$1D,$01,$1C,$03,$1C,$01,$0E
  .byte $03,$0E,$02,$0E,$03,$0E,$01,$0E,$03,$0D,$FC,<(S_KOROBEINIKI_DRUMS+146),>(S_KOROBEINIKI_DRUMS+146),$04,$02,$0E
  .byte $03,$0E,$01,$0D,$03,$0E,$02,$0D,$FC,<(S_KOROBEINIKI_DRUMS+160),>(S_KOROBEINIKI_DRUMS+160),$04,$03,$0E,$01,$0D
  .byte $03,$0D,$02,$0E,$03,$0D,$FC,<(S_KOROBEINIKI_DRUMS+174),>(S_KOROBEINIKI_DRUMS+174),$04,$01,$0D,$03,$0D,$02,$0D
  .byte $03,$0D,$FC,<(S_KOROBEINIKI_DRUMS+186),>(S_KOROBEINIKI_DRUMS+186),$04,$01,$0D,$03,$0C,$02,$0D,$03,$0D,$FC,<(S_KOROBEINIKI_DRUMS+198)
  .byte >(S_KOROBEINIKI_DRUMS+198),$04,$01,$0C,$03,$0D,$02,$0C,$03,$0D,$FC,<(S_KOROBEINIKI_DRUMS+210),>(S_KOROBEINIKI_DRUMS+210),$04,$01,$0C
  .byte $03,$0C,$02,$0D,$03,$0C,$FC,<(S_KOROBEINIKI_DRUMS+222),>(S_KOROBEINIKI_DRUMS+222),$03,$02,$06,$02,$06,$02,$06
  .byte $FC,<(S_KOROBEINIKI_DRUMS+234),>(S_KOROBEINIKI_DRUMS+234),$03,$FC,<(S_KOROBEINIKI_DRUMS+234),>(S_KOROBEINIKI_DRUMS+234),$03,$02,$06,$01,$0C,$03,$0C,$02,$0C
  .byte $03,$0C,$01,$0B,$03,$0C,$02,$0C,$03,$0B,$01,$0C,$03,$0C,$02,$0B
  .byte $03,$0C,$01,$0B,$03,$0B,$02,$0C,$03,$0B,$FC,<(S_KOROBEINIKI_DRUMS+274),>(S_KOROBEINIKI_DRUMS+274),$04,$01,$0B
  .byte $03,$0B,$02,$0B,$03,$0A,$FC,<(S_KOROBEINIKI_DRUMS+286),>(S_KOROBEINIKI_DRUMS+286),$03,$03,$0B,$01,$0A,$03,$0B
  .byte $02,$0A,$FC,<(S_KOROBEINIKI_DRUMS+298),>(S_KOROBEINIKI_DRUMS+298),$04,$03,$0B,$01,$0A,$03,$0A,$02,$0A,$03,$0A
  .byte $01,$0B,$FC,<(S_KOROBEINIKI_DRUMS+314),>(S_KOROBEINIKI_DRUMS+314),$03,$01,$0A,$03,$09,$02,$0A,$03,$0A,$FC,<(S_KOROBEINIKI_DRUMS+326)
  .byte >(S_KOROBEINIKI_DRUMS+326),$04,$01,$09,$03,$0A,$02,$09,$03,$09,$01,$0A,$03,$09,$02,$09
  .byte $02,$05,$02,$05,$02,$04,$02,$05,$02,$04,$FC,<(S_KOROBEINIKI_DRUMS+354),>(S_KOROBEINIKI_DRUMS+354),$04,$02,$05
  .byte $05,$09,$00,$0A,$01,$0B,$00,$0B,$05,$33,$FF

; ---- THE ENTERTAINER  (SCOTT JOPLIN 1902) ----
SONG_ENTERTAINER:
  .word S_ENTERTAINER_LEAD, S_ENTERTAINER_HARM1, S_ENTERTAINER_BASS, S_ENTERTAINER_HARM2, 0, 0
  .byte 13, 5, 3, 0, 1      ; lead
  .byte 9, 3, 3, 0, 1      ; harm1
  .byte 12, 4, 3, 0, 1      ; bass
  .byte 8, 3, 3, 0, 1      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_ENTERTAINER_LEAD:
  .byte $00,$3C,$33,$0A,$34,$0A,$35,$0A,$3D,$14,$35,$0A,$3D,$14,$35,$0A
  .byte $3D,$0A,$FE,$28,$3D,$0A,$3F,$0A,$40,$0A,$41,$0A,$3D,$0A,$3F,$0A
  .byte $41,$14,$3C,$0A,$3F,$14,$3D,$0A,$FE,$3C,$FC,<(S_ENTERTAINER_LEAD+2),>(S_ENTERTAINER_LEAD+2),$08,$FE,$3C
  .byte $3A,$0A,$38,$0A,$37,$0A,$3A,$0A,$3D,$0A,$41,$14,$3F,$0A,$3D,$0A
  .byte $3A,$0A,$3F,$3C,$FC,<(S_ENTERTAINER_LEAD+2),>(S_ENTERTAINER_LEAD+2),$14,$FC,<(S_ENTERTAINER_LEAD+2),>(S_ENTERTAINER_LEAD+2),$14,$FC,<(S_ENTERTAINER_LEAD+2),>(S_ENTERTAINER_LEAD+2),$08
  .byte $FE,$3C,$FC,<(S_ENTERTAINER_LEAD+48),>(S_ENTERTAINER_LEAD+48),$0A,$FC,<(S_ENTERTAINER_LEAD+2),>(S_ENTERTAINER_LEAD+2),$14,$3D,$0A,$3F,$0A,$3D,$0A
  .byte $41,$0A,$3D,$0A,$3F,$0B,$3D,$0A,$41,$0B,$3D,$0A,$3F,$0B,$3D,$0B
  .byte $41,$0B,$3C,$0B,$3F,$16,$3D,$0B,$FE,$17,$FE,$2F,$38,$18,$35,$18
  .byte $31,$32,$00,$33,$FF
S_ENTERTAINER_HARM1:
  .byte $00,$50,$00,$14,$1D,$14,$00,$14,$1D,$14,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$00,$14
  .byte $24,$14,$00,$14,$24,$14,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+2)
  .byte >(S_ENTERTAINER_HARM1+2),$04,$00,$14,$1F,$14,$00,$14,$1F,$14,$FC,<(S_ENTERTAINER_HARM1+14),>(S_ENTERTAINER_HARM1+14),$04,$FC,<(S_ENTERTAINER_HARM1+2)
  .byte >(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+14),>(S_ENTERTAINER_HARM1+14),$04,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+2)
  .byte >(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+14),>(S_ENTERTAINER_HARM1+14),$04,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+2)
  .byte >(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+34),>(S_ENTERTAINER_HARM1+34),$04,$FC,<(S_ENTERTAINER_HARM1+14),>(S_ENTERTAINER_HARM1+14),$04,$FC,<(S_ENTERTAINER_HARM1+2)
  .byte >(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$FC,<(S_ENTERTAINER_HARM1+14),>(S_ENTERTAINER_HARM1+14),$04,$FC,<(S_ENTERTAINER_HARM1+2),>(S_ENTERTAINER_HARM1+2),$04,$00,$14
  .byte $1D,$15,$00,$15,$1D,$15,$00,$16,$24,$16,$00,$16,$24,$17,$00,$17
  .byte $1D,$18,$00,$18,$1D,$18,$00,$19,$1D,$19,$00,$19,$1D,$1A,$FF
S_ENTERTAINER_BASS:
  .byte $00,$50,$0D,$14,$00,$14,$08,$14,$00,$14,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$14,$14
  .byte $00,$14,$0F,$14,$00,$14,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+2)
  .byte >(S_ENTERTAINER_BASS+2),$04,$0F,$14,$00,$14,$0A,$14,$00,$14,$FC,<(S_ENTERTAINER_BASS+14),>(S_ENTERTAINER_BASS+14),$04,$FC,<(S_ENTERTAINER_BASS+2)
  .byte >(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+14),>(S_ENTERTAINER_BASS+14),$04,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+2)
  .byte >(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+14),>(S_ENTERTAINER_BASS+14),$04,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+2)
  .byte >(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+34),>(S_ENTERTAINER_BASS+34),$04,$FC,<(S_ENTERTAINER_BASS+14),>(S_ENTERTAINER_BASS+14),$04,$FC,<(S_ENTERTAINER_BASS+2)
  .byte >(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$FC,<(S_ENTERTAINER_BASS+14),>(S_ENTERTAINER_BASS+14),$04,$FC,<(S_ENTERTAINER_BASS+2),>(S_ENTERTAINER_BASS+2),$04,$0D,$14
  .byte $00,$15,$08,$15,$00,$15,$14,$16,$00,$16,$0F,$16,$00,$17,$0D,$17
  .byte $00,$18,$08,$18,$00,$18,$0D,$19,$00,$19,$0D,$19,$00,$1A,$FF
S_ENTERTAINER_HARM2:
  .byte $00,$50,$00,$14,$20,$14,$00,$14,$25,$14,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$00,$14
  .byte $27,$14,$00,$14,$2A,$14,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+2)
  .byte >(S_ENTERTAINER_HARM2+2),$04,$00,$14,$22,$14,$00,$14,$25,$14,$FC,<(S_ENTERTAINER_HARM2+14),>(S_ENTERTAINER_HARM2+14),$04,$FC,<(S_ENTERTAINER_HARM2+2)
  .byte >(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+14),>(S_ENTERTAINER_HARM2+14),$04,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+2)
  .byte >(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+14),>(S_ENTERTAINER_HARM2+14),$04,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+2)
  .byte >(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+34),>(S_ENTERTAINER_HARM2+34),$04,$FC,<(S_ENTERTAINER_HARM2+14),>(S_ENTERTAINER_HARM2+14),$04,$FC,<(S_ENTERTAINER_HARM2+2)
  .byte >(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$FC,<(S_ENTERTAINER_HARM2+14),>(S_ENTERTAINER_HARM2+14),$04,$FC,<(S_ENTERTAINER_HARM2+2),>(S_ENTERTAINER_HARM2+2),$04,$00,$14
  .byte $20,$15,$00,$15,$25,$15,$00,$16,$27,$16,$00,$16,$2A,$17,$00,$17
  .byte $20,$18,$00,$18,$25,$18,$00,$19,$20,$19,$00,$19,$25,$1A,$FF

; ---- TOCCATA AND FUGUE IN D MINOR (J.S. BACH 1704) ----
SONG_TOCCATA:
  .word S_TOCCATA_LEAD, S_TOCCATA_HARM1, S_TOCCATA_BASS, S_TOCCATA_HARM2, S_TOCCATA_COUNTER, 0
  .byte 13, 11, 15, 0, 1      ; lead
  .byte 10, 8, 15, 0, 0      ; harm1
  .byte 12, 10, 15, 0, 0      ; bass
  .byte 10, 8, 15, 0, 0      ; harm2
  .byte 11, 9, 15, 0, 1      ; counter
S_TOCCATA_LEAD:
  .byte $3A,$06,$38,$06,$3A,$3C,$00,$18,$38,$06,$36,$06,$35,$06,$33,$06
  .byte $32,$18,$33,$60,$00,$30,$2E,$06,$2C,$06,$2E,$3C,$00,$18,$2C,$06
  .byte $2A,$06,$29,$06,$27,$06,$26,$18,$27,$60,$00,$30,$22,$06,$20,$06
  .byte $22,$3C,$00,$18,$20,$06,$1E,$06,$1D,$06,$1B,$06,$1A,$18,$1B,$60
  .byte $00,$30,$00,$6E,$2F,$C0,$33,$DA,$3A,$07,$38,$07,$36,$07,$35,$07
  .byte $FC,<(S_TOCCATA_LEAD+74),>(S_TOCCATA_LEAD+74),$03,$33,$07,$36,$06,$35,$07,$33,$07,$32,$07,$35,$07
  .byte $33,$06,$32,$07,$30,$07,$33,$07,$32,$06,$30,$07,$2E,$07,$32,$07
  .byte $30,$06,$2E,$07,$2C,$07,$2A,$06,$29,$07,$27,$06,$26,$07,$27,$1A
  .byte $3A,$06,$38,$07,$36,$06,$35,$07,$38,$06,$36,$07,$35,$06,$33,$07
  .byte $36,$06,$35,$06,$33,$07,$32,$06,$35,$06,$33,$06,$32,$07,$30,$06
  .byte $33,$06,$35,$06,$36,$07,$38,$06,$3A,$06,$3C,$06,$3E,$06,$3F,$07
  .byte $41,$0C,$3E,$0C,$3A,$18,$38,$36,$36,$42,$35,$98,$32,$A8,$33,$FF
  .byte $FE,$61,$FF
S_TOCCATA_HARM1:
  .byte $00,$60,$00,$60,$00,$60,$FC,<(S_TOCCATA_HARM1+0),>(S_TOCCATA_HARM1+0),$03,$FC,<(S_TOCCATA_HARM1+0),>(S_TOCCATA_HARM1+0),$03,$26,$FF
  .byte $FE,$2F,$27,$DA,$00,$D8,$00,$C8,$33,$78,$32,$98,$2E,$A8,$2E,$FF
  .byte $FE,$61,$FF
S_TOCCATA_BASS:
  .byte $00,$A8,$1B,$78,$00,$A8,$0F,$78,$00,$A8,$0F,$78,$0F,$FF,$FE,$2F
  .byte $0F,$DA,$0F,$D8,$0A,$C8,$08,$78,$0A,$FF,$FE,$41,$03,$FF,$FE,$61
  .byte $FF
S_TOCCATA_HARM2:
  .byte $00,$FF,$FE,$21,$00,$FF,$FE,$21,$00,$FF,$FE,$21,$00,$24,$29,$FF
  .byte $FE,$0B,$2A,$DA,$00,$D8,$00,$C8,$2F,$78,$2C,$98,$29,$A8,$27,$FF
  .byte $FE,$61,$FF
S_TOCCATA_COUNTER:
  .byte $2E,$06,$2C,$06,$2E,$3C,$00,$18,$2C,$06,$2A,$06,$29,$06,$27,$06
  .byte $26,$18,$27,$60,$00,$30,$22,$06,$20,$06,$22,$3C,$00,$18,$20,$06
  .byte $1E,$06,$1D,$06,$1B,$06,$1A,$18,$1B,$60,$00,$30,$00,$FF,$FE,$21
  .byte $00,$49,$2C,$E5,$2E,$DA,$2E,$07,$2C,$07,$2A,$07,$29,$07,$FC,<(S_TOCCATA_COUNTER+56)
  .byte >(S_TOCCATA_COUNTER+56),$03,$27,$07,$2A,$06,$29,$07,$27,$07,$26,$07,$29,$07,$27,$06
  .byte $26,$07,$24,$07,$27,$07,$26,$06,$24,$07,$22,$07,$26,$07,$24,$06
  .byte $22,$07,$20,$07,$1E,$06,$1D,$07,$1B,$06,$1A,$07,$1B,$1A,$2E,$06
  .byte $2C,$07,$2A,$06,$29,$07,$2C,$06,$2A,$07,$29,$06,$27,$07,$2A,$06
  .byte $29,$06,$27,$07,$26,$06,$29,$06,$27,$06,$26,$07,$24,$06,$27,$06
  .byte $29,$06,$2A,$07,$2C,$06,$2E,$06,$30,$06,$32,$06,$33,$07,$35,$0C
  .byte $32,$0C,$2E,$18,$2F,$36,$2E,$42,$2C,$98,$29,$A8,$2A,$FF,$FE,$61
  .byte $FF

; ---- ARCADE START  (ORIGINAL - MINIVIC SOUND) ----
SONG_ARCADE_START:
  .word S_ARCADE_START_LEAD, S_ARCADE_START_HARM1, S_ARCADE_START_BASS, 0, 0, S_ARCADE_START_DRUMS
  .byte 14, 9, 3, 10, 1      ; lead
  .byte 8, 4, 1, 0, 0      ; harm1
  .byte 12, 7, 3, 0, 1      ; bass
  .byte 8, 4, 3, 0, 1      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_ARCADE_START_LEAD:
  .byte $00,$20,$38,$08,$3D,$08,$38,$08,$35,$08,$36,$08,$3A,$08,$3D,$10
  .byte $3C,$08,$3A,$08,$38,$08,$36,$08,$35,$08,$38,$08,$3D,$10,$3F,$0C
  .byte $3D,$04,$3C,$08,$38,$08,$3A,$08,$3C,$08,$3D,$08,$3F,$08,$41,$10
  .byte $3D,$08,$38,$08,$3D,$20,$FF
S_ARCADE_START_HARM1:
  .byte $00,$20,$25,$04,$29,$04,$2C,$04,$29,$04,$FC,<(S_ARCADE_START_HARM1+2),>(S_ARCADE_START_HARM1+2),$04,$2A,$04
  .byte $2E,$04,$31,$04,$2E,$04,$FC,<(S_ARCADE_START_HARM1+14),>(S_ARCADE_START_HARM1+14),$04,$2C,$04,$30,$04,$33,$04
  .byte $30,$04,$FC,<(S_ARCADE_START_HARM1+26),>(S_ARCADE_START_HARM1+26),$04,$FC,<(S_ARCADE_START_HARM1+2),>(S_ARCADE_START_HARM1+2),$04,$FC,<(S_ARCADE_START_HARM1+2),>(S_ARCADE_START_HARM1+2),$04,$FC,<(S_ARCADE_START_HARM1+26)
  .byte >(S_ARCADE_START_HARM1+26),$04,$FC,<(S_ARCADE_START_HARM1+26),>(S_ARCADE_START_HARM1+26),$04,$FC,<(S_ARCADE_START_HARM1+26),>(S_ARCADE_START_HARM1+26),$04,$FC,<(S_ARCADE_START_HARM1+26),>(S_ARCADE_START_HARM1+26),$04,$FC,<(S_ARCADE_START_HARM1+2)
  .byte >(S_ARCADE_START_HARM1+2),$04,$FC,<(S_ARCADE_START_HARM1+2),>(S_ARCADE_START_HARM1+2),$04,$31,$20,$FF
S_ARCADE_START_BASS:
  .byte $00,$20,$0D,$08,$14,$08,$19,$08,$14,$08,$12,$08,$19,$08,$1E,$08
  .byte $19,$08,$14,$08,$1B,$08,$20,$08,$1B,$08,$FC,<(S_ARCADE_START_BASS+2),>(S_ARCADE_START_BASS+2),$04,$FC,<(S_ARCADE_START_BASS+18)
  .byte >(S_ARCADE_START_BASS+18),$04,$FC,<(S_ARCADE_START_BASS+18),>(S_ARCADE_START_BASS+18),$04,$FC,<(S_ARCADE_START_BASS+2),>(S_ARCADE_START_BASS+2),$04,$0D,$20,$FF
S_ARCADE_START_DRUMS:
  .byte $02,$04,$02,$04,$02,$04,$FC,<(S_ARCADE_START_DRUMS+0),>(S_ARCADE_START_DRUMS+0),$03,$02,$04,$02,$04,$01,$08
  .byte $03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$FC,<(S_ARCADE_START_DRUMS+18),>(S_ARCADE_START_DRUMS+18),$03,$FC,<(S_ARCADE_START_DRUMS+16)
  .byte >(S_ARCADE_START_DRUMS+16),$05,$FC,<(S_ARCADE_START_DRUMS+18),>(S_ARCADE_START_DRUMS+18),$03,$FC,<(S_ARCADE_START_DRUMS+16),>(S_ARCADE_START_DRUMS+16),$05,$FC,<(S_ARCADE_START_DRUMS+18),>(S_ARCADE_START_DRUMS+18),$03,$FC,<(S_ARCADE_START_DRUMS+16)
  .byte >(S_ARCADE_START_DRUMS+16),$03,$05,$20,$FF

; ---- STAR PATROL  (ORIGINAL - MINIVIC SOUND) ----
SONG_STAR_PATROL:
  .word S_STAR_PATROL_LEAD, S_STAR_PATROL_HARM1, S_STAR_PATROL_BASS, S_STAR_PATROL_HARM2, 0, S_STAR_PATROL_DRUMS
  .byte 13, 9, 3, 12, 1      ; lead
  .byte 7, 3, 1, 0, 0      ; harm1
  .byte 12, 7, 1, 0, 1      ; bass
  .byte 6, 5, 15, 0, 0      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_STAR_PATROL_LEAD:
  .byte $00,$60,$00,$60,$35,$18,$3A,$18,$3D,$18,$3C,$0C,$3A,$0C,$38,$0C
  .byte $3A,$0C,$35,$18,$00,$18,$31,$0C,$33,$0C,$36,$18,$3A,$18,$3D,$18
  .byte $3A,$0C,$3D,$0C,$3F,$24,$3D,$0C,$3A,$18,$36,$18,$38,$18,$3C,$18
  .byte $3F,$18,$3D,$0C,$3C,$0C,$3A,$0C,$3C,$0C,$38,$18,$00,$18,$33,$0C
  .byte $35,$0C,$39,$18,$3C,$18,$41,$18,$3F,$0C,$3C,$0C,$41,$48,$00,$18
  .byte $3A,$0C,$3D,$0C,$41,$0C,$3D,$0C,$FC,<(S_STAR_PATROL_LEAD+80),>(S_STAR_PATROL_LEAD+80),$03,$44,$0C,$42,$18
  .byte $41,$18,$3D,$18,$3A,$18,$38,$0C,$3C,$0C,$3F,$0C,$3C,$0C,$FC,<(S_STAR_PATROL_LEAD+102)
  .byte >(S_STAR_PATROL_LEAD+102),$03,$42,$0C,$41,$18,$3F,$18,$3C,$18,$39,$18,$FC,<(S_STAR_PATROL_LEAD+80),>(S_STAR_PATROL_LEAD+80),$04
  .byte $FC,<(S_STAR_PATROL_LEAD+80),>(S_STAR_PATROL_LEAD+80),$03,$46,$0C,$46,$18,$44,$18,$42,$18,$3D,$18,$3F,$18
  .byte $41,$18,$42,$18,$44,$18,$45,$30,$41,$30,$FD,$0E,$FC,<(S_STAR_PATROL_LEAD+4),>(S_STAR_PATROL_LEAD+4),$2A
  .byte $FC,<(S_STAR_PATROL_LEAD+80),>(S_STAR_PATROL_LEAD+80),$03,$FC,<(S_STAR_PATROL_LEAD+92),>(S_STAR_PATROL_LEAD+92),$09,$FC,<(S_STAR_PATROL_LEAD+102),>(S_STAR_PATROL_LEAD+102),$03,$FC,<(S_STAR_PATROL_LEAD+114),>(S_STAR_PATROL_LEAD+114),$05
  .byte $FC,<(S_STAR_PATROL_LEAD+80),>(S_STAR_PATROL_LEAD+80),$04,$FC,<(S_STAR_PATROL_LEAD+80),>(S_STAR_PATROL_LEAD+80),$03,$FC,<(S_STAR_PATROL_LEAD+132),>(S_STAR_PATROL_LEAD+132),$0B,$3A,$60,$FF
S_STAR_PATROL_HARM1:
  .byte $00,$60,$00,$60,$2E,$06,$31,$06,$35,$06,$31,$06,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$2A,$06,$2E,$06,$31,$06,$2E,$06
  .byte $FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$2C,$06,$30,$06
  .byte $33,$06,$30,$06,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04
  .byte $29,$06,$2D,$06,$30,$06,$2D,$06,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+4),>(S_STAR_PATROL_HARM1+4),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+40),>(S_STAR_PATROL_HARM1+40),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+76),>(S_STAR_PATROL_HARM1+76),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04
  .byte $FC,<(S_STAR_PATROL_HARM1+112),>(S_STAR_PATROL_HARM1+112),$04,$2E,$60,$FF
S_STAR_PATROL_BASS:
  .byte $0A,$0C,$16,$0C,$0A,$0C,$16,$0C,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04
  .byte $FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04
  .byte $FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$06,$0C,$12,$0C,$06,$0C,$12,$0C,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04
  .byte $FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04,$08,$0C,$14,$0C,$08,$0C,$14,$0C
  .byte $FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$05,$0C,$11,$0C
  .byte $05,$0C,$11,$0C,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04
  .byte $FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04
  .byte $FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04
  .byte $FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04
  .byte $FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04
  .byte $FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04
  .byte $FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04
  .byte $FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04
  .byte $FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04
  .byte $FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04
  .byte $FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04
  .byte $FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+0),>(S_STAR_PATROL_BASS+0),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04,$FC,<(S_STAR_PATROL_BASS+36),>(S_STAR_PATROL_BASS+36),$04
  .byte $FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+56),>(S_STAR_PATROL_BASS+56),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04,$FC,<(S_STAR_PATROL_BASS+76),>(S_STAR_PATROL_BASS+76),$04
  .byte $0A,$60,$FF
S_STAR_PATROL_HARM2:
  .byte $00,$60,$00,$60,$31,$60,$31,$60,$2E,$60,$2E,$60,$30,$60,$30,$60
  .byte $2D,$60,$2D,$60,$31,$60,$2E,$60,$30,$60,$FC,<(S_STAR_PATROL_HARM2+18),>(S_STAR_PATROL_HARM2+18),$04,$2D,$60
  .byte $FC,<(S_STAR_PATROL_HARM2+4),>(S_STAR_PATROL_HARM2+4),$0B,$FC,<(S_STAR_PATROL_HARM2+18),>(S_STAR_PATROL_HARM2+18),$04,$2D,$60,$31,$60,$FF
S_STAR_PATROL_DRUMS:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$06,$01,$06,$FC,<(S_STAR_PATROL_DRUMS+2),>(S_STAR_PATROL_DRUMS+2),$03
  .byte $FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$06,$02,$0C,$02,$06,$02,$06,$02,$06,$02,$06,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$06,$06,$06,$06,$07,$06
  .byte $07,$06,$FC,<(S_STAR_PATROL_DRUMS+22),>(S_STAR_PATROL_DRUMS+22),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04
  .byte $FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C
  .byte $FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$01,$0C,$02,$0C
  .byte $02,$0C,$FC,<(S_STAR_PATROL_DRUMS+20),>(S_STAR_PATROL_DRUMS+20),$05,$FC,<(S_STAR_PATROL_DRUMS+22),>(S_STAR_PATROL_DRUMS+22),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+90),>(S_STAR_PATROL_DRUMS+90),$04,$FC,<(S_STAR_PATROL_DRUMS+22),>(S_STAR_PATROL_DRUMS+22),$04,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0)
  .byte >(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03
  .byte $01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04
  .byte $FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$03,$01,$0C
  .byte $FC,<(S_STAR_PATROL_DRUMS+0),>(S_STAR_PATROL_DRUMS+0),$04,$FC,<(S_STAR_PATROL_DRUMS+172),>(S_STAR_PATROL_DRUMS+172),$03,$FC,<(S_STAR_PATROL_DRUMS+20),>(S_STAR_PATROL_DRUMS+20),$05,$FC,<(S_STAR_PATROL_DRUMS+22),>(S_STAR_PATROL_DRUMS+22),$04
  .byte $05,$60,$FF

; ---- NEON DRIVE  (ORIGINAL - MINIVIC SOUND) ----
SONG_NEON_DRIVE:
  .word S_NEON_DRIVE_LEAD, S_NEON_DRIVE_HARM1, S_NEON_DRIVE_BASS, S_NEON_DRIVE_HARM2, S_NEON_DRIVE_COUNTER, S_NEON_DRIVE_DRUMS
  .byte 13, 10, 7, 16, 0      ; lead
  .byte 8, 3, 1, 0, 0      ; harm1
  .byte 12, 6, 3, 0, 1      ; bass
  .byte 6, 5, 15, 20, 0      ; harm2
  .byte 8, 5, 7, 16, 0      ; counter
S_NEON_DRIVE_LEAD:
  .byte $00,$80,$00,$80,$00,$80,$00,$80,$2E,$30,$33,$10,$36,$20,$35,$20
  .byte $33,$40,$00,$20,$2E,$10,$31,$10,$33,$30,$36,$10,$3B,$20,$3A,$20
  .byte $36,$40,$00,$20,$33,$10,$36,$10,$3A,$30,$3D,$10,$3A,$20,$36,$20
  .byte $38,$20,$3A,$20,$36,$20,$31,$20,$35,$30,$38,$10,$3D,$20,$3B,$20
  .byte $3A,$10,$38,$10,$35,$60,$36,$20,$3A,$20,$3F,$40,$3D,$20,$3A,$20
  .byte $36,$40,$36,$20,$3B,$20,$3F,$40,$3D,$20,$3B,$20,$3A,$40,$3D,$20
  .byte $3A,$20,$42,$40,$41,$20,$3D,$20,$3A,$40,$38,$20,$3D,$20,$41,$20
  .byte $44,$20,$41,$40,$3F,$40,$FC,<(S_NEON_DRIVE_LEAD+8),>(S_NEON_DRIVE_LEAD+8),$37,$33,$80,$33,$80,$FF
S_NEON_DRIVE_HARM1:
  .byte $1B,$08,$22,$08,$27,$08,$2A,$08,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$23,$08,$2A,$08,$2F,$08,$33,$08,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$1E,$08,$25,$08,$2A,$08,$2E,$08
  .byte $FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$19,$08,$20,$08
  .byte $25,$08,$29,$08,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04,$FC,<(S_NEON_DRIVE_HARM1+20),>(S_NEON_DRIVE_HARM1+20),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04,$FC,<(S_NEON_DRIVE_HARM1+40),>(S_NEON_DRIVE_HARM1+40),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04,$FC,<(S_NEON_DRIVE_HARM1+60),>(S_NEON_DRIVE_HARM1+60),$04
  .byte $FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04,$FC,<(S_NEON_DRIVE_HARM1+0),>(S_NEON_DRIVE_HARM1+0),$04
  .byte $27,$80,$FF
S_NEON_DRIVE_BASS:
  .byte $0F,$10,$1B,$10,$0F,$10,$1B,$10,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$17,$10,$23,$10
  .byte $17,$10,$23,$10,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$12,$10,$1E,$10,$12,$10,$1E,$10
  .byte $FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$0D,$10,$19,$10,$0D,$10,$19,$10,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04,$FC,<(S_NEON_DRIVE_BASS+12),>(S_NEON_DRIVE_BASS+12),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04,$FC,<(S_NEON_DRIVE_BASS+24),>(S_NEON_DRIVE_BASS+24),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04,$FC,<(S_NEON_DRIVE_BASS+36),>(S_NEON_DRIVE_BASS+36),$04
  .byte $FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$FC,<(S_NEON_DRIVE_BASS+0),>(S_NEON_DRIVE_BASS+0),$04,$0F,$80,$FF
S_NEON_DRIVE_HARM2:
  .byte $2A,$80,$33,$80,$2E,$80,$29,$80,$2A,$80,$2A,$80,$33,$80,$33,$80
  .byte $2E,$80,$2E,$80,$29,$80,$FC,<(S_NEON_DRIVE_HARM2+6),>(S_NEON_DRIVE_HARM2+6),$08,$FC,<(S_NEON_DRIVE_HARM2+6),>(S_NEON_DRIVE_HARM2+6),$08,$FC,<(S_NEON_DRIVE_HARM2+6)
  .byte >(S_NEON_DRIVE_HARM2+6),$08,$29,$80,$2A,$FF,$FE,$01,$FF
S_NEON_DRIVE_COUNTER:
  .byte $00,$18,$00,$80,$00,$80,$00,$80,$00,$80,$2E,$30,$33,$10,$36,$20
  .byte $35,$20,$33,$40,$00,$20,$2E,$10,$31,$10,$33,$30,$36,$10,$3B,$20
  .byte $3A,$20,$36,$40,$00,$20,$33,$10,$36,$10,$3A,$30,$3D,$10,$3A,$20
  .byte $36,$20,$38,$20,$3A,$20,$36,$20,$31,$20,$35,$30,$38,$10,$3D,$20
  .byte $3B,$20,$3A,$10,$38,$10,$35,$60,$36,$20,$3A,$20,$3F,$40,$3D,$20
  .byte $3A,$20,$36,$40,$36,$20,$3B,$20,$3F,$40,$3D,$20,$3B,$20,$3A,$40
  .byte $3D,$20,$3A,$20,$42,$40,$41,$20,$3D,$20,$3A,$40,$38,$20,$3D,$20
  .byte $41,$20,$44,$20,$41,$40,$3F,$40,$FC,<(S_NEON_DRIVE_COUNTER+10),>(S_NEON_DRIVE_COUNTER+10),$37,$33,$80,$33,$68
  .byte $FF
S_NEON_DRIVE_DRUMS:
  .byte $01,$10,$03,$10,$02,$10,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04
  .byte $FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04
  .byte $06,$08,$06,$08,$07,$08,$07,$08,$02,$08,$02,$08,$02,$08,$02,$08
  .byte $FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0)
  .byte >(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0)
  .byte >(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03
  .byte $04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04
  .byte $FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$01,$10,$01,$10,$02,$10
  .byte $02,$10,$05,$10,$FC,<(S_NEON_DRIVE_DRUMS+2),>(S_NEON_DRIVE_DRUMS+2),$03,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04
  .byte $FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10
  .byte $FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122)
  .byte >(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+0)
  .byte >(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+124),>(S_NEON_DRIVE_DRUMS+124),$03,$02,$10,$FC,<(S_NEON_DRIVE_DRUMS+40)
  .byte >(S_NEON_DRIVE_DRUMS+40),$04,$FC,<(S_NEON_DRIVE_DRUMS+40),>(S_NEON_DRIVE_DRUMS+40),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10
  .byte $FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0)
  .byte >(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0)
  .byte >(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03
  .byte $04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$03,$04,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04
  .byte $FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$05,$FC,<(S_NEON_DRIVE_DRUMS+2),>(S_NEON_DRIVE_DRUMS+2),$03,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04
  .byte $FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10
  .byte $FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122)
  .byte >(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+0),>(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+0)
  .byte >(S_NEON_DRIVE_DRUMS+0),$04,$FC,<(S_NEON_DRIVE_DRUMS+122),>(S_NEON_DRIVE_DRUMS+122),$03,$03,$10,$FC,<(S_NEON_DRIVE_DRUMS+124),>(S_NEON_DRIVE_DRUMS+124),$03,$02,$10,$FC,<(S_NEON_DRIVE_DRUMS+40)
  .byte >(S_NEON_DRIVE_DRUMS+40),$04,$FC,<(S_NEON_DRIVE_DRUMS+40),>(S_NEON_DRIVE_DRUMS+40),$04,$05,$80,$00,$80,$FF

; ---- LEVEL CLEAR AND GAME OVER (ORIGINAL - MINIVIC SOUND) ----
SONG_JINGLES:
  .word S_JINGLES_LEAD, S_JINGLES_HARM1, S_JINGLES_BASS, S_JINGLES_HARM2, 0, S_JINGLES_DRUMS
  .byte 14, 8, 3, 12, 1      ; lead
  .byte 8, 4, 3, 0, 0      ; harm1
  .byte 12, 6, 3, 0, 1      ; bass
  .byte 7, 4, 7, 0, 0      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_JINGLES_LEAD:
  .byte $31,$08,$38,$08,$35,$08,$3D,$08,$3C,$08,$3F,$08,$44,$10,$42,$08
  .byte $41,$08,$3F,$08,$3C,$08,$3D,$20,$00,$60,$35,$24,$34,$24,$33,$24
  .byte $32,$24,$31,$48,$30,$24,$2D,$24,$2E,$90,$FF
S_JINGLES_HARM1:
  .byte $25,$04,$29,$04,$2C,$04,$29,$04,$FC,<(S_JINGLES_HARM1+0),>(S_JINGLES_HARM1+0),$04,$24,$04,$27,$04
  .byte $2C,$04,$27,$04,$FC,<(S_JINGLES_HARM1+12),>(S_JINGLES_HARM1+12),$04,$FC,<(S_JINGLES_HARM1+12),>(S_JINGLES_HARM1+12),$04,$24,$04,$27,$04
  .byte $2A,$04,$27,$04,$25,$20,$00,$60,$25,$90,$25,$48,$24,$48,$25,$90
  .byte $FF
S_JINGLES_BASS:
  .byte $0D,$10,$14,$10,$08,$10,$0F,$10,$08,$10,$0F,$10,$0D,$20,$00,$60
  .byte $16,$90,$12,$48,$11,$48,$0A,$90,$FF
S_JINGLES_HARM2:
  .byte $29,$20,$27,$20,$27,$20,$29,$20,$00,$60,$22,$90,$22,$48,$21,$48
  .byte $1D,$90,$FF
S_JINGLES_DRUMS:
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$FC,<(S_JINGLES_DRUMS+0),>(S_JINGLES_DRUMS+0),$04,$FC,<(S_JINGLES_DRUMS+0),>(S_JINGLES_DRUMS+0),$04
  .byte $05,$20,$00,$60,$06,$90,$06,$48,$06,$48,$05,$90,$FF

; ---- FLIGHT OF THE BUMBLEBEE (N. RIMSKY-KORSAKOV 1900) ----
SONG_BUMBLEBEE:
  .word S_BUMBLEBEE_LEAD, S_BUMBLEBEE_HARM1, S_BUMBLEBEE_BASS, S_BUMBLEBEE_HARM2, 0, S_BUMBLEBEE_DRUMS
  .byte 13, 9, 7, 0, 0      ; lead
  .byte 8, 3, 1, 0, 1      ; harm1
  .byte 12, 5, 1, 0, 1      ; bass
  .byte 7, 3, 1, 0, 1      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_BUMBLEBEE_LEAD:
  .byte $41,$05,$40,$05,$3F,$05,$3E,$05,$3F,$05,$3E,$05,$3D,$05,$3C,$05
  .byte $3D,$05,$3C,$05,$3B,$05,$3A,$05,$39,$05,$38,$05,$37,$05,$36,$05
  .byte $35,$05,$34,$05,$33,$05,$32,$05,$33,$05,$32,$05,$31,$05,$30,$05
  .byte $31,$05,$30,$05,$2F,$05,$2E,$05,$2D,$05,$2C,$05,$2B,$05,$2A,$05
  .byte $FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$05,$FC,<(S_BUMBLEBEE_LEAD+52),>(S_BUMBLEBEE_LEAD+52),$03,$FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$05,$2B,$05,$2C,$05
  .byte $2D,$05,$FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$05,$FC,<(S_BUMBLEBEE_LEAD+52),>(S_BUMBLEBEE_LEAD+52),$03,$FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$05,$FC,<(S_BUMBLEBEE_LEAD+76)
  .byte >(S_BUMBLEBEE_LEAD+76),$03,$FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$04,$FC,<(S_BUMBLEBEE_LEAD+58),>(S_BUMBLEBEE_LEAD+58),$03,$29,$05,$2A,$05,$FC,<(S_BUMBLEBEE_LEAD+76)
  .byte >(S_BUMBLEBEE_LEAD+76),$03,$2E,$05,$FC,<(S_BUMBLEBEE_LEAD+52),>(S_BUMBLEBEE_LEAD+52),$03,$FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$04,$FC,<(S_BUMBLEBEE_LEAD+58),>(S_BUMBLEBEE_LEAD+58),$03
  .byte $29,$05,$2A,$05,$FC,<(S_BUMBLEBEE_LEAD+76),>(S_BUMBLEBEE_LEAD+76),$03,$2E,$05,$2F,$05,$30,$05,$31,$05
  .byte $FC,<(S_BUMBLEBEE_LEAD+22),>(S_BUMBLEBEE_LEAD+22),$05,$FC,<(S_BUMBLEBEE_LEAD+20),>(S_BUMBLEBEE_LEAD+20),$03,$FC,<(S_BUMBLEBEE_LEAD+22),>(S_BUMBLEBEE_LEAD+22),$05,$37,$05,$38,$05
  .byte $39,$05,$FC,<(S_BUMBLEBEE_LEAD+22),>(S_BUMBLEBEE_LEAD+22),$05,$FC,<(S_BUMBLEBEE_LEAD+20),>(S_BUMBLEBEE_LEAD+20),$03,$FC,<(S_BUMBLEBEE_LEAD+22),>(S_BUMBLEBEE_LEAD+22),$05,$FC,<(S_BUMBLEBEE_LEAD+156)
  .byte >(S_BUMBLEBEE_LEAD+156),$03,$FC,<(S_BUMBLEBEE_LEAD+22),>(S_BUMBLEBEE_LEAD+22),$04,$FC,<(S_BUMBLEBEE_LEAD+26),>(S_BUMBLEBEE_LEAD+26),$04,$36,$05,$FC,<(S_BUMBLEBEE_LEAD+156),>(S_BUMBLEBEE_LEAD+156),$03
  .byte $3A,$05,$FC,<(S_BUMBLEBEE_LEAD+20),>(S_BUMBLEBEE_LEAD+20),$03,$FC,<(S_BUMBLEBEE_LEAD+22),>(S_BUMBLEBEE_LEAD+22),$04,$FC,<(S_BUMBLEBEE_LEAD+26),>(S_BUMBLEBEE_LEAD+26),$04,$36,$05
  .byte $FC,<(S_BUMBLEBEE_LEAD+156),>(S_BUMBLEBEE_LEAD+156),$03,$3A,$05,$3B,$05,$3C,$05,$3D,$05,$FC,<(S_BUMBLEBEE_LEAD+40),>(S_BUMBLEBEE_LEAD+40),$04
  .byte $2F,$05,$FC,<(S_BUMBLEBEE_LEAD+34),>(S_BUMBLEBEE_LEAD+34),$07,$FC,<(S_BUMBLEBEE_LEAD+138),>(S_BUMBLEBEE_LEAD+138),$03,$FC,<(S_BUMBLEBEE_LEAD+38),>(S_BUMBLEBEE_LEAD+38),$05,$2F,$05
  .byte $FC,<(S_BUMBLEBEE_LEAD+34),>(S_BUMBLEBEE_LEAD+34),$07,$FC,<(S_BUMBLEBEE_LEAD+138),>(S_BUMBLEBEE_LEAD+138),$03,$FC,<(S_BUMBLEBEE_LEAD+38),>(S_BUMBLEBEE_LEAD+38),$09,$FC,<(S_BUMBLEBEE_LEAD+138),>(S_BUMBLEBEE_LEAD+138),$03
  .byte $32,$05,$33,$05,$FC,<(S_BUMBLEBEE_LEAD+34),>(S_BUMBLEBEE_LEAD+34),$0B,$FC,<(S_BUMBLEBEE_LEAD+138),>(S_BUMBLEBEE_LEAD+138),$03,$32,$05,$33,$05
  .byte $34,$05,$35,$05,$36,$05,$FC,<(S_BUMBLEBEE_LEAD+8),>(S_BUMBLEBEE_LEAD+8),$04,$3B,$05,$FC,<(S_BUMBLEBEE_LEAD+2),>(S_BUMBLEBEE_LEAD+2),$07
  .byte $FC,<(S_BUMBLEBEE_LEAD+214),>(S_BUMBLEBEE_LEAD+214),$03,$FC,<(S_BUMBLEBEE_LEAD+6),>(S_BUMBLEBEE_LEAD+6),$05,$3B,$05,$FC,<(S_BUMBLEBEE_LEAD+2),>(S_BUMBLEBEE_LEAD+2),$07,$FC,<(S_BUMBLEBEE_LEAD+214)
  .byte >(S_BUMBLEBEE_LEAD+214),$03,$FC,<(S_BUMBLEBEE_LEAD+6),>(S_BUMBLEBEE_LEAD+6),$09,$FC,<(S_BUMBLEBEE_LEAD+214),>(S_BUMBLEBEE_LEAD+214),$03,$3E,$05,$3F,$05,$FC,<(S_BUMBLEBEE_LEAD+2)
  .byte >(S_BUMBLEBEE_LEAD+2),$0B,$FC,<(S_BUMBLEBEE_LEAD+214),>(S_BUMBLEBEE_LEAD+214),$03,$3E,$05,$3F,$05,$40,$05,$41,$05,$42,$05
  .byte $FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$05,$FC,<(S_BUMBLEBEE_LEAD+52),>(S_BUMBLEBEE_LEAD+52),$03,$FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$05,$FC,<(S_BUMBLEBEE_LEAD+76),>(S_BUMBLEBEE_LEAD+76),$03
  .byte $FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$05,$FC,<(S_BUMBLEBEE_LEAD+52),>(S_BUMBLEBEE_LEAD+52),$03,$FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$05,$FC,<(S_BUMBLEBEE_LEAD+76),>(S_BUMBLEBEE_LEAD+76),$03
  .byte $FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$04,$FC,<(S_BUMBLEBEE_LEAD+58),>(S_BUMBLEBEE_LEAD+58),$03,$29,$05,$2A,$05,$FC,<(S_BUMBLEBEE_LEAD+76),>(S_BUMBLEBEE_LEAD+76),$03
  .byte $2E,$05,$FC,<(S_BUMBLEBEE_LEAD+52),>(S_BUMBLEBEE_LEAD+52),$03,$FC,<(S_BUMBLEBEE_LEAD+54),>(S_BUMBLEBEE_LEAD+54),$04,$FC,<(S_BUMBLEBEE_LEAD+58),>(S_BUMBLEBEE_LEAD+58),$03,$29,$05
  .byte $2A,$05,$FC,<(S_BUMBLEBEE_LEAD+76),>(S_BUMBLEBEE_LEAD+76),$03,$FC,<(S_BUMBLEBEE_LEAD+136),>(S_BUMBLEBEE_LEAD+136),$04,$FC,<(S_BUMBLEBEE_LEAD+136),>(S_BUMBLEBEE_LEAD+136),$04,$FC,<(S_BUMBLEBEE_LEAD+268)
  .byte >(S_BUMBLEBEE_LEAD+268),$05,$FC,<(S_BUMBLEBEE_LEAD+156),>(S_BUMBLEBEE_LEAD+156),$03,$3A,$14,$35,$0A,$00,$0A,$2E,$0A,$00,$0A
  .byte $3A,$0A,$00,$1E,$FF
S_BUMBLEBEE_HARM1:
  .byte $00,$A0,$00,$0A,$25,$0A,$00,$0A,$25,$0A,$00,$0A,$21,$0A,$00,$0A
  .byte $21,$0A,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2)
  .byte >(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$00,$0A
  .byte $1E,$0A,$00,$0A,$1E,$0A,$00,$0A,$26,$0A,$00,$0A,$26,$0A,$FC,<(S_BUMBLEBEE_HARM1+46)
  .byte >(S_BUMBLEBEE_HARM1+46),$08,$FC,<(S_BUMBLEBEE_HARM1+46),>(S_BUMBLEBEE_HARM1+46),$08,$FC,<(S_BUMBLEBEE_HARM1+46),>(S_BUMBLEBEE_HARM1+46),$08,$FC,<(S_BUMBLEBEE_HARM1+46),>(S_BUMBLEBEE_HARM1+46),$08,$FC,<(S_BUMBLEBEE_HARM1+46)
  .byte >(S_BUMBLEBEE_HARM1+46),$08,$FC,<(S_BUMBLEBEE_HARM1+46),>(S_BUMBLEBEE_HARM1+46),$08,$FC,<(S_BUMBLEBEE_HARM1+46),>(S_BUMBLEBEE_HARM1+46),$08,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2)
  .byte >(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2),>(S_BUMBLEBEE_HARM1+2),$08,$FC,<(S_BUMBLEBEE_HARM1+2)
  .byte >(S_BUMBLEBEE_HARM1+2),$05,$FC,<(S_BUMBLEBEE_HARM1+4),>(S_BUMBLEBEE_HARM1+4),$03,$FF
S_BUMBLEBEE_BASS:
  .byte $11,$28,$11,$28,$11,$28,$11,$28,$16,$0A,$00,$0A,$11,$0A,$00,$0A
  .byte $11,$0A,$00,$0A,$0C,$0A,$00,$0A,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08
  .byte $FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08
  .byte $FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08,$0F,$0A,$00,$0A,$0A,$0A,$00,$0A,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04
  .byte $FC,<(S_BUMBLEBEE_BASS+52),>(S_BUMBLEBEE_BASS+52),$04,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04,$FC,<(S_BUMBLEBEE_BASS+52),>(S_BUMBLEBEE_BASS+52),$04,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04
  .byte $FC,<(S_BUMBLEBEE_BASS+52),>(S_BUMBLEBEE_BASS+52),$04,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04,$FC,<(S_BUMBLEBEE_BASS+52),>(S_BUMBLEBEE_BASS+52),$04,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04
  .byte $FC,<(S_BUMBLEBEE_BASS+52),>(S_BUMBLEBEE_BASS+52),$04,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04,$FC,<(S_BUMBLEBEE_BASS+52),>(S_BUMBLEBEE_BASS+52),$04,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04
  .byte $FC,<(S_BUMBLEBEE_BASS+52),>(S_BUMBLEBEE_BASS+52),$04,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08
  .byte $FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$08,$FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04
  .byte $FC,<(S_BUMBLEBEE_BASS+8),>(S_BUMBLEBEE_BASS+8),$04,$FF
S_BUMBLEBEE_HARM2:
  .byte $00,$A0,$00,$0A,$29,$0A,$00,$0A,$29,$0A,$00,$0A,$24,$0A,$00,$0A
  .byte $24,$0A,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2)
  .byte >(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$08,$00,$0A
  .byte $22,$0A,$00,$0A,$22,$0A,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$05,$FC,<(S_BUMBLEBEE_HARM2+48),>(S_BUMBLEBEE_HARM2+48),$03,$FC,<(S_BUMBLEBEE_HARM2+2)
  .byte >(S_BUMBLEBEE_HARM2+2),$05,$FC,<(S_BUMBLEBEE_HARM2+48),>(S_BUMBLEBEE_HARM2+48),$03,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$05,$FC,<(S_BUMBLEBEE_HARM2+48),>(S_BUMBLEBEE_HARM2+48),$03,$FC,<(S_BUMBLEBEE_HARM2+2)
  .byte >(S_BUMBLEBEE_HARM2+2),$05,$FC,<(S_BUMBLEBEE_HARM2+48),>(S_BUMBLEBEE_HARM2+48),$03,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$05,$FC,<(S_BUMBLEBEE_HARM2+48),>(S_BUMBLEBEE_HARM2+48),$03,$FC,<(S_BUMBLEBEE_HARM2+2)
  .byte >(S_BUMBLEBEE_HARM2+2),$05,$FC,<(S_BUMBLEBEE_HARM2+48),>(S_BUMBLEBEE_HARM2+48),$03,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$05,$FC,<(S_BUMBLEBEE_HARM2+48),>(S_BUMBLEBEE_HARM2+48),$03,$FC,<(S_BUMBLEBEE_HARM2+2)
  .byte >(S_BUMBLEBEE_HARM2+2),$05,$FC,<(S_BUMBLEBEE_HARM2+4),>(S_BUMBLEBEE_HARM2+4),$07,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2)
  .byte >(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$08,$FC,<(S_BUMBLEBEE_HARM2+2),>(S_BUMBLEBEE_HARM2+2),$05,$FC,<(S_BUMBLEBEE_HARM2+4),>(S_BUMBLEBEE_HARM2+4),$03,$FF
S_BUMBLEBEE_DRUMS:
  .byte $03,$05,$03,$05,$03,$05,$FC,<(S_BUMBLEBEE_DRUMS+0),>(S_BUMBLEBEE_DRUMS+0),$03,$FC,<(S_BUMBLEBEE_DRUMS+0),>(S_BUMBLEBEE_DRUMS+0),$03,$FC,<(S_BUMBLEBEE_DRUMS+0)
  .byte >(S_BUMBLEBEE_DRUMS+0),$03,$FC,<(S_BUMBLEBEE_DRUMS+0),>(S_BUMBLEBEE_DRUMS+0),$03,$FC,<(S_BUMBLEBEE_DRUMS+0),>(S_BUMBLEBEE_DRUMS+0),$03,$FC,<(S_BUMBLEBEE_DRUMS+0),>(S_BUMBLEBEE_DRUMS+0),$03,$FC,<(S_BUMBLEBEE_DRUMS+0)
  .byte >(S_BUMBLEBEE_DRUMS+0),$03,$FC,<(S_BUMBLEBEE_DRUMS+0),>(S_BUMBLEBEE_DRUMS+0),$03,$FC,<(S_BUMBLEBEE_DRUMS+0),>(S_BUMBLEBEE_DRUMS+0),$03,$03,$05,$03,$05,$01,$0A
  .byte $03,$0A,$02,$0A,$03,$0A,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46)
  .byte >(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$04,$FC,<(S_BUMBLEBEE_DRUMS+46),>(S_BUMBLEBEE_DRUMS+46),$03,$02,$0A,$05,$14,$00,$14
  .byte $01,$0A,$00,$1E,$FF

; ---- RONDO ALLA TURCA  (W.A. MOZART 1783) ----
SONG_ALLA_TURCA:
  .word S_ALLA_TURCA_LEAD, S_ALLA_TURCA_HARM1, S_ALLA_TURCA_BASS, S_ALLA_TURCA_HARM2, 0, S_ALLA_TURCA_DRUMS
  .byte 13, 5, 3, 0, 1      ; lead
  .byte 8, 3, 3, 0, 1      ; harm1
  .byte 12, 4, 3, 0, 1      ; bass
  .byte 7, 3, 3, 0, 1      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_ALLA_TURCA_LEAD:
  .byte $30,$06,$2E,$06,$2D,$06,$2E,$06,$31,$0C,$00,$0C,$33,$06,$31,$06
  .byte $30,$06,$31,$06,$35,$0C,$00,$0C,$36,$06,$35,$06,$34,$06,$35,$06
  .byte $3C,$06,$3A,$06,$39,$06,$3A,$06,$FC,<(S_ALLA_TURCA_LEAD+32),>(S_ALLA_TURCA_LEAD+32),$04,$3D,$18,$3A,$0C
  .byte $3C,$0C,$3D,$0C,$3C,$0C,$3A,$0C,$39,$0C,$3A,$0C,$35,$0C,$36,$0C
  .byte $33,$0C,$31,$18,$30,$12,$2E,$06,$2E,$18,$FC,<(S_ALLA_TURCA_LEAD+0),>(S_ALLA_TURCA_LEAD+0),$14,$FC,<(S_ALLA_TURCA_LEAD+32)
  .byte >(S_ALLA_TURCA_LEAD+32),$04,$FC,<(S_ALLA_TURCA_LEAD+44),>(S_ALLA_TURCA_LEAD+44),$0F,$00,$18,$35,$0C,$36,$0C,$38,$0C,$38,$0C
  .byte $3A,$06,$38,$06,$36,$06,$35,$06,$33,$18,$FC,<(S_ALLA_TURCA_LEAD+88),>(S_ALLA_TURCA_LEAD+88),$09,$31,$0C
  .byte $33,$0C,$35,$0C,$35,$0C,$36,$06,$35,$06,$33,$06,$31,$06,$30,$18
  .byte $FC,<(S_ALLA_TURCA_LEAD+110),>(S_ALLA_TURCA_LEAD+110),$08,$FC,<(S_ALLA_TURCA_LEAD+0),>(S_ALLA_TURCA_LEAD+0),$14,$FC,<(S_ALLA_TURCA_LEAD+32),>(S_ALLA_TURCA_LEAD+32),$04,$FC,<(S_ALLA_TURCA_LEAD+44),>(S_ALLA_TURCA_LEAD+44),$0F
  .byte $FC,<(S_ALLA_TURCA_LEAD+0),>(S_ALLA_TURCA_LEAD+0),$14,$FC,<(S_ALLA_TURCA_LEAD+32),>(S_ALLA_TURCA_LEAD+32),$04,$FC,<(S_ALLA_TURCA_LEAD+44),>(S_ALLA_TURCA_LEAD+44),$0F,$FC,<(S_ALLA_TURCA_LEAD+86),>(S_ALLA_TURCA_LEAD+86),$0A
  .byte $FC,<(S_ALLA_TURCA_LEAD+88),>(S_ALLA_TURCA_LEAD+88),$09,$FC,<(S_ALLA_TURCA_LEAD+110),>(S_ALLA_TURCA_LEAD+110),$09,$FC,<(S_ALLA_TURCA_LEAD+110),>(S_ALLA_TURCA_LEAD+110),$08,$FC,<(S_ALLA_TURCA_LEAD+0),>(S_ALLA_TURCA_LEAD+0),$14
  .byte $FC,<(S_ALLA_TURCA_LEAD+32),>(S_ALLA_TURCA_LEAD+32),$04,$FC,<(S_ALLA_TURCA_LEAD+44),>(S_ALLA_TURCA_LEAD+44),$0F,$00,$18,$32,$0C,$35,$0D,$3A,$0D
  .byte $35,$0D,$32,$0E,$35,$0E,$3A,$0E,$35,$0F,$3E,$0F,$3A,$10,$35,$10
  .byte $32,$10,$3A,$22,$00,$23,$FF
S_ALLA_TURCA_HARM1:
  .byte $00,$18,$00,$0C,$25,$0C,$25,$0C,$25,$0C,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$00,$0C
  .byte $21,$0C,$21,$0C,$21,$0C,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$00,$0C
  .byte $1E,$0C,$1E,$0C,$1E,$0C,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2)
  .byte >(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2)
  .byte >(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+30),>(S_ALLA_TURCA_HARM1+30),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$00,$0C
  .byte $1D,$0C,$1D,$0C,$1D,$0C,$00,$0C,$24,$0C,$24,$0C,$24,$0C,$FC,<(S_ALLA_TURCA_HARM1+78)
  .byte >(S_ALLA_TURCA_HARM1+78),$08,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+14)
  .byte >(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2)
  .byte >(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+30),>(S_ALLA_TURCA_HARM1+30),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2)
  .byte >(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2)
  .byte >(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+30),>(S_ALLA_TURCA_HARM1+30),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2)
  .byte >(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+78),>(S_ALLA_TURCA_HARM1+78),$08,$FC,<(S_ALLA_TURCA_HARM1+78),>(S_ALLA_TURCA_HARM1+78),$08,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+14)
  .byte >(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2)
  .byte >(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$FC,<(S_ALLA_TURCA_HARM1+30)
  .byte >(S_ALLA_TURCA_HARM1+30),$04,$FC,<(S_ALLA_TURCA_HARM1+14),>(S_ALLA_TURCA_HARM1+14),$04,$FC,<(S_ALLA_TURCA_HARM1+2),>(S_ALLA_TURCA_HARM1+2),$04,$00,$0C,$26,$0D,$26,$0D
  .byte $26,$0D,$00,$0E,$26,$0E,$26,$0E,$26,$0F,$00,$0F,$26,$10,$26,$10
  .byte $26,$10,$00,$11,$26,$11,$26,$11,$26,$12,$FF
S_ALLA_TURCA_BASS:
  .byte $00,$18,$16,$0C,$00,$0C,$11,$0C,$00,$0C,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$11,$0C
  .byte $00,$0C,$0C,$0C,$00,$0C,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$0F,$0C
  .byte $00,$0C,$0A,$0C,$FC,<(S_ALLA_TURCA_BASS+4),>(S_ALLA_TURCA_BASS+4),$03,$0C,$0C,$00,$0C,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04
  .byte $FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+14),>(S_ALLA_TURCA_BASS+14),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04
  .byte $FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+30),>(S_ALLA_TURCA_BASS+30),$03,$FC,<(S_ALLA_TURCA_BASS+4),>(S_ALLA_TURCA_BASS+4),$03,$0C,$0C,$00,$0C
  .byte $FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$0D,$0C,$00,$0C,$08,$0C,$00,$0C,$14,$0C,$00,$0C
  .byte $0F,$0C,$00,$0C,$FC,<(S_ALLA_TURCA_BASS+84),>(S_ALLA_TURCA_BASS+84),$08,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+14),>(S_ALLA_TURCA_BASS+14),$04
  .byte $FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+14),>(S_ALLA_TURCA_BASS+14),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04
  .byte $FC,<(S_ALLA_TURCA_BASS+14),>(S_ALLA_TURCA_BASS+14),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+30),>(S_ALLA_TURCA_BASS+30),$03
  .byte $FC,<(S_ALLA_TURCA_BASS+4),>(S_ALLA_TURCA_BASS+4),$03,$0C,$0C,$00,$0C,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04
  .byte $FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+14),>(S_ALLA_TURCA_BASS+14),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04
  .byte $FC,<(S_ALLA_TURCA_BASS+30),>(S_ALLA_TURCA_BASS+30),$03,$FC,<(S_ALLA_TURCA_BASS+4),>(S_ALLA_TURCA_BASS+4),$03,$0C,$0C,$00,$0C,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04
  .byte $FC,<(S_ALLA_TURCA_BASS+84),>(S_ALLA_TURCA_BASS+84),$08,$FC,<(S_ALLA_TURCA_BASS+84),>(S_ALLA_TURCA_BASS+84),$08,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+14),>(S_ALLA_TURCA_BASS+14),$04
  .byte $FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+14),>(S_ALLA_TURCA_BASS+14),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04
  .byte $FC,<(S_ALLA_TURCA_BASS+14),>(S_ALLA_TURCA_BASS+14),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$FC,<(S_ALLA_TURCA_BASS+30),>(S_ALLA_TURCA_BASS+30),$03
  .byte $FC,<(S_ALLA_TURCA_BASS+4),>(S_ALLA_TURCA_BASS+4),$03,$0C,$0C,$00,$0C,$FC,<(S_ALLA_TURCA_BASS+2),>(S_ALLA_TURCA_BASS+2),$04,$16,$0C,$00,$0D
  .byte $11,$0D,$00,$0D,$16,$0E,$00,$0E,$11,$0E,$00,$0F,$16,$0F,$00,$10
  .byte $11,$10,$00,$10,$16,$11,$00,$11,$11,$11,$00,$12,$FF
S_ALLA_TURCA_HARM2:
  .byte $00,$18,$00,$0C,$29,$0C,$29,$0C,$29,$0C,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$00,$0C
  .byte $24,$0C,$24,$0C,$24,$0C,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$00,$0C
  .byte $22,$0C,$22,$0C,$22,$0C,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2)
  .byte >(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2)
  .byte >(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+30),>(S_ALLA_TURCA_HARM2+30),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$00,$0C
  .byte $20,$0C,$20,$0C,$20,$0C,$00,$0C,$27,$0C,$27,$0C,$27,$0C,$FC,<(S_ALLA_TURCA_HARM2+78)
  .byte >(S_ALLA_TURCA_HARM2+78),$08,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+14)
  .byte >(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2)
  .byte >(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+30),>(S_ALLA_TURCA_HARM2+30),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2)
  .byte >(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2)
  .byte >(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+30),>(S_ALLA_TURCA_HARM2+30),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2)
  .byte >(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+78),>(S_ALLA_TURCA_HARM2+78),$08,$FC,<(S_ALLA_TURCA_HARM2+78),>(S_ALLA_TURCA_HARM2+78),$08,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+14)
  .byte >(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2)
  .byte >(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$FC,<(S_ALLA_TURCA_HARM2+30)
  .byte >(S_ALLA_TURCA_HARM2+30),$04,$FC,<(S_ALLA_TURCA_HARM2+14),>(S_ALLA_TURCA_HARM2+14),$04,$FC,<(S_ALLA_TURCA_HARM2+2),>(S_ALLA_TURCA_HARM2+2),$04,$00,$0C,$29,$0D,$29,$0D
  .byte $29,$0D,$00,$0E,$29,$0E,$29,$0E,$29,$0F,$00,$0F,$29,$10,$29,$10
  .byte $29,$10,$00,$11,$29,$11,$29,$11,$29,$12,$FF
S_ALLA_TURCA_DRUMS:
  .byte $00,$18,$01,$0C,$03,$0C,$01,$0C,$03,$0C,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2)
  .byte >(S_ALLA_TURCA_DRUMS+2),$04,$FC,<(S_ALLA_TURCA_DRUMS+2),>(S_ALLA_TURCA_DRUMS+2),$04,$01,$0C,$03,$0D,$01,$0D,$03,$0D,$01,$0E
  .byte $03,$0E,$01,$0E,$03,$0F,$01,$0F,$02,$10,$02,$10,$02,$10,$05,$22
  .byte $00,$23,$FF

; ---- CAN-CAN (GALOP INFERNAL) (JACQUES OFFENBACH 1858) ----
SONG_CAN_CAN:
  .word S_CAN_CAN_LEAD, S_CAN_CAN_HARM1, S_CAN_CAN_BASS, S_CAN_CAN_HARM2, S_CAN_CAN_COUNTER, S_CAN_CAN_DRUMS
  .byte 13, 8, 3, 12, 1      ; lead
  .byte 8, 3, 1, 0, 1      ; harm1
  .byte 12, 5, 3, 0, 1      ; bass
  .byte 7, 3, 1, 0, 1      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_CAN_CAN_LEAD:
  .byte $00,$60,$31,$30,$33,$0C,$36,$0C,$35,$0C,$33,$0C,$38,$18,$38,$18
  .byte $38,$0C,$3A,$0C,$35,$0C,$36,$0C,$33,$18,$33,$18,$FC,<(S_CAN_CAN_LEAD+4),>(S_CAN_CAN_LEAD+4),$04
  .byte $31,$0C,$3D,$0C,$3C,$0C,$3A,$0C,$38,$0C,$FC,<(S_CAN_CAN_LEAD+6),>(S_CAN_CAN_LEAD+6),$03,$FC,<(S_CAN_CAN_LEAD+2)
  .byte >(S_CAN_CAN_LEAD+2),$0D,$FC,<(S_CAN_CAN_LEAD+4),>(S_CAN_CAN_LEAD+4),$04,$31,$0C,$2C,$0C,$33,$0C,$35,$0C,$31,$30
  .byte $3D,$30,$3F,$0C,$42,$0B,$41,$0C,$3F,$0C,$44,$17,$44,$18,$44,$0B
  .byte $46,$0C,$41,$0B,$42,$0C,$3F,$17,$3F,$17,$3F,$0B,$42,$0B,$41,$0C
  .byte $3F,$0B,$3D,$0B,$49,$0B,$48,$0C,$46,$0B,$44,$0B,$42,$0B,$41,$0B
  .byte $3F,$0B,$3D,$2C,$3F,$0B,$42,$0A,$41,$0B,$3F,$0B,$44,$15,$44,$16
  .byte $44,$0A,$46,$0B,$41,$0A,$42,$0B,$3F,$15,$3F,$15,$3F,$0A,$42,$0A
  .byte $41,$0B,$3F,$0A,$3D,$0A,$38,$0A,$3F,$0B,$41,$0A,$3D,$28,$FD,$0F
  .byte $3D,$28,$3F,$0A,$42,$09,$41,$0A,$3F,$0A,$44,$13,$44,$14,$44,$09
  .byte $46,$0A,$41,$09,$42,$0A,$3F,$13,$3F,$13,$3F,$09,$42,$09,$41,$0A
  .byte $3F,$09,$3D,$09,$49,$09,$48,$0A,$46,$09,$44,$09,$42,$09,$41,$09
  .byte $3F,$09,$3D,$24,$3F,$09,$42,$08,$41,$09,$3F,$09,$44,$11,$44,$12
  .byte $44,$08,$46,$09,$41,$08,$42,$09,$3F,$11,$3F,$11,$3F,$08,$42,$08
  .byte $41,$09,$3F,$08,$3D,$08,$38,$08,$3F,$09,$41,$08,$3D,$20,$3D,$08
  .byte $00,$09,$38,$0A,$00,$0B,$3D,$0B,$00,$27,$FF
S_CAN_CAN_HARM1:
  .byte $00,$60,$00,$0C,$29,$0C,$00,$0C,$29,$0C,$00,$0C,$30,$0C,$00,$0C
  .byte $30,$0C,$FC,<(S_CAN_CAN_HARM1+2),>(S_CAN_CAN_HARM1+2),$05,$FC,<(S_CAN_CAN_HARM1+4),>(S_CAN_CAN_HARM1+4),$07,$FC,<(S_CAN_CAN_HARM1+10),>(S_CAN_CAN_HARM1+10),$04,$FC,<(S_CAN_CAN_HARM1+2)
  .byte >(S_CAN_CAN_HARM1+2),$08,$FC,<(S_CAN_CAN_HARM1+2),>(S_CAN_CAN_HARM1+2),$08,$FC,<(S_CAN_CAN_HARM1+2),>(S_CAN_CAN_HARM1+2),$05,$FC,<(S_CAN_CAN_HARM1+4),>(S_CAN_CAN_HARM1+4),$07,$FC,<(S_CAN_CAN_HARM1+10)
  .byte >(S_CAN_CAN_HARM1+10),$04,$FC,<(S_CAN_CAN_HARM1+10),>(S_CAN_CAN_HARM1+10),$04,$FC,<(S_CAN_CAN_HARM1+2),>(S_CAN_CAN_HARM1+2),$05,$FC,<(S_CAN_CAN_HARM1+4),>(S_CAN_CAN_HARM1+4),$04,$30,$0B
  .byte $FC,<(S_CAN_CAN_HARM1+10),>(S_CAN_CAN_HARM1+10),$03,$29,$0B,$00,$0C,$29,$0C,$00,$0B,$29,$0C,$00,$0B
  .byte $29,$0C,$00,$0B,$30,$0C,$00,$0B,$30,$0C,$00,$0B,$30,$0B,$00,$0C
  .byte $30,$0B,$00,$0B,$29,$0B,$00,$0C,$29,$0B,$00,$0B,$30,$0B,$00,$0B
  .byte $FC,<(S_CAN_CAN_HARM1+96),>(S_CAN_CAN_HARM1+96),$03,$00,$0B,$29,$0B,$00,$0B,$30,$0A,$FC,<(S_CAN_CAN_HARM1+106),>(S_CAN_CAN_HARM1+106),$03
  .byte $29,$0A,$00,$0B,$29,$0B,$00,$0A,$29,$0B,$00,$0A,$29,$0B,$00,$0A
  .byte $30,$0B,$00,$0A,$30,$0B,$00,$0A,$30,$0A,$00,$0B,$30,$0A,$FC,<(S_CAN_CAN_HARM1+150)
  .byte >(S_CAN_CAN_HARM1+150),$04,$00,$0A,$29,$0A,$00,$0A,$29,$0A,$FC,<(S_CAN_CAN_HARM1+162),>(S_CAN_CAN_HARM1+162),$04,$00,$0A
  .byte $30,$09,$00,$0A,$30,$0A,$00,$0A,$29,$09,$00,$0A,$29,$0A,$00,$09
  .byte $29,$0A,$00,$09,$29,$0A,$00,$09,$30,$0A,$00,$09,$30,$0A,$00,$09
  .byte $30,$09,$00,$0A,$30,$09,$00,$09,$29,$09,$00,$0A,$29,$09,$00,$09
  .byte $30,$09,$00,$09,$FC,<(S_CAN_CAN_HARM1+212),>(S_CAN_CAN_HARM1+212),$03,$00,$09,$29,$09,$00,$09,$30,$08
  .byte $FC,<(S_CAN_CAN_HARM1+222),>(S_CAN_CAN_HARM1+222),$03,$29,$08,$00,$09,$29,$09,$00,$08,$29,$09,$00,$08
  .byte $29,$09,$00,$08,$30,$09,$00,$08,$30,$09,$00,$08,$30,$08,$00,$09
  .byte $30,$08,$FC,<(S_CAN_CAN_HARM1+266),>(S_CAN_CAN_HARM1+266),$04,$00,$08,$29,$08,$00,$08,$29,$08,$00,$08
  .byte $29,$09,$00,$0A,$29,$0B,$00,$0B,$29,$0C,$00,$0D,$29,$0E,$FF
S_CAN_CAN_BASS:
  .byte $0D,$0C,$00,$0C,$08,$0C,$00,$0C,$FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04,$FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04
  .byte $14,$0C,$00,$0C,$0F,$0C,$00,$0C,$FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04,$FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04
  .byte $FC,<(S_CAN_CAN_BASS+16),>(S_CAN_CAN_BASS+16),$04,$FC,<(S_CAN_CAN_BASS+16),>(S_CAN_CAN_BASS+16),$04,$FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04,$FC,<(S_CAN_CAN_BASS+16),>(S_CAN_CAN_BASS+16),$04
  .byte $FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04,$FC,<(S_CAN_CAN_BASS+16),>(S_CAN_CAN_BASS+16),$04,$FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04,$FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04
  .byte $FC,<(S_CAN_CAN_BASS+16),>(S_CAN_CAN_BASS+16),$04,$FC,<(S_CAN_CAN_BASS+16),>(S_CAN_CAN_BASS+16),$04,$FC,<(S_CAN_CAN_BASS+16),>(S_CAN_CAN_BASS+16),$04,$FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04
  .byte $FC,<(S_CAN_CAN_BASS+0),>(S_CAN_CAN_BASS+0),$04,$14,$0C,$00,$0B,$0F,$0C,$00,$0C,$0D,$0C,$00,$0B
  .byte $08,$0C,$00,$0C,$0D,$0B,$00,$0C,$08,$0B,$00,$0C,$14,$0B,$00,$0C
  .byte $0F,$0B,$00,$0C,$14,$0B,$00,$0B,$0F,$0C,$00,$0B,$0D,$0B,$00,$0B
  .byte $08,$0C,$00,$0B,$14,$0B,$00,$0B,$0F,$0B,$FC,<(S_CAN_CAN_BASS+122),>(S_CAN_CAN_BASS+122),$03,$08,$0B
  .byte $00,$0B,$14,$0B,$00,$0A,$0F,$0B,$00,$0B,$0D,$0B,$00,$0A,$08,$0B
  .byte $00,$0B,$0D,$0A,$00,$0B,$08,$0A,$00,$0B,$14,$0A,$00,$0B,$0F,$0A
  .byte $00,$0B,$14,$0A,$00,$0A,$0F,$0B,$00,$0A,$FC,<(S_CAN_CAN_BASS+178),>(S_CAN_CAN_BASS+178),$04,$0D,$0A
  .byte $00,$0A,$08,$0A,$00,$0A,$FC,<(S_CAN_CAN_BASS+190),>(S_CAN_CAN_BASS+190),$04,$14,$0A,$00,$09,$0F,$0A
  .byte $00,$0A,$0D,$0A,$00,$09,$08,$0A,$00,$0A,$0D,$09,$00,$0A,$08,$09
  .byte $00,$0A,$14,$09,$00,$0A,$0F,$09,$00,$0A,$14,$09,$00,$09,$0F,$0A
  .byte $00,$09,$0D,$09,$00,$09,$08,$0A,$00,$09,$14,$09,$00,$09,$0F,$09
  .byte $FC,<(S_CAN_CAN_BASS+240),>(S_CAN_CAN_BASS+240),$03,$08,$09,$00,$09,$14,$09,$00,$08,$0F,$09,$00,$09
  .byte $0D,$09,$00,$08,$08,$09,$00,$09,$0D,$08,$00,$09,$08,$08,$00,$09
  .byte $14,$08,$00,$09,$0F,$08,$00,$09,$14,$08,$00,$08,$0F,$09,$00,$08
  .byte $FC,<(S_CAN_CAN_BASS+296),>(S_CAN_CAN_BASS+296),$04,$0D,$08,$00,$08,$08,$08,$00,$08,$0D,$08,$00,$09
  .byte $08,$0A,$00,$0B,$0D,$0B,$00,$0C,$08,$0D,$00,$0E,$FF
S_CAN_CAN_HARM2:
  .byte $00,$60,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$27,$0C,$00,$0C
  .byte $27,$0C,$FC,<(S_CAN_CAN_HARM2+2),>(S_CAN_CAN_HARM2+2),$05,$FC,<(S_CAN_CAN_HARM2+4),>(S_CAN_CAN_HARM2+4),$07,$FC,<(S_CAN_CAN_HARM2+10),>(S_CAN_CAN_HARM2+10),$04,$FC,<(S_CAN_CAN_HARM2+2)
  .byte >(S_CAN_CAN_HARM2+2),$08,$FC,<(S_CAN_CAN_HARM2+2),>(S_CAN_CAN_HARM2+2),$08,$FC,<(S_CAN_CAN_HARM2+2),>(S_CAN_CAN_HARM2+2),$05,$FC,<(S_CAN_CAN_HARM2+4),>(S_CAN_CAN_HARM2+4),$07,$FC,<(S_CAN_CAN_HARM2+10)
  .byte >(S_CAN_CAN_HARM2+10),$04,$FC,<(S_CAN_CAN_HARM2+10),>(S_CAN_CAN_HARM2+10),$04,$FC,<(S_CAN_CAN_HARM2+2),>(S_CAN_CAN_HARM2+2),$05,$FC,<(S_CAN_CAN_HARM2+4),>(S_CAN_CAN_HARM2+4),$04,$27,$0B
  .byte $FC,<(S_CAN_CAN_HARM2+10),>(S_CAN_CAN_HARM2+10),$03,$20,$0B,$00,$0C,$20,$0C,$00,$0B,$20,$0C,$00,$0B
  .byte $20,$0C,$00,$0B,$27,$0C,$00,$0B,$27,$0C,$00,$0B,$27,$0B,$00,$0C
  .byte $27,$0B,$00,$0B,$20,$0B,$00,$0C,$20,$0B,$00,$0B,$27,$0B,$00,$0B
  .byte $FC,<(S_CAN_CAN_HARM2+96),>(S_CAN_CAN_HARM2+96),$03,$00,$0B,$20,$0B,$00,$0B,$27,$0A,$FC,<(S_CAN_CAN_HARM2+106),>(S_CAN_CAN_HARM2+106),$03
  .byte $20,$0A,$00,$0B,$20,$0B,$00,$0A,$20,$0B,$00,$0A,$20,$0B,$00,$0A
  .byte $27,$0B,$00,$0A,$27,$0B,$00,$0A,$27,$0A,$00,$0B,$27,$0A,$FC,<(S_CAN_CAN_HARM2+150)
  .byte >(S_CAN_CAN_HARM2+150),$04,$00,$0A,$20,$0A,$00,$0A,$20,$0A,$FC,<(S_CAN_CAN_HARM2+162),>(S_CAN_CAN_HARM2+162),$04,$00,$0A
  .byte $27,$09,$00,$0A,$27,$0A,$00,$0A,$20,$09,$00,$0A,$20,$0A,$00,$09
  .byte $20,$0A,$00,$09,$20,$0A,$00,$09,$27,$0A,$00,$09,$27,$0A,$00,$09
  .byte $27,$09,$00,$0A,$27,$09,$00,$09,$20,$09,$00,$0A,$20,$09,$00,$09
  .byte $27,$09,$00,$09,$FC,<(S_CAN_CAN_HARM2+212),>(S_CAN_CAN_HARM2+212),$03,$00,$09,$20,$09,$00,$09,$27,$08
  .byte $FC,<(S_CAN_CAN_HARM2+222),>(S_CAN_CAN_HARM2+222),$03,$20,$08,$00,$09,$20,$09,$00,$08,$20,$09,$00,$08
  .byte $20,$09,$00,$08,$27,$09,$00,$08,$27,$09,$00,$08,$27,$08,$00,$09
  .byte $27,$08,$FC,<(S_CAN_CAN_HARM2+266),>(S_CAN_CAN_HARM2+266),$04,$00,$08,$20,$08,$00,$08,$20,$08,$00,$08
  .byte $20,$09,$00,$0A,$20,$0B,$00,$0B,$20,$0C,$00,$0D,$20,$0E,$FF
S_CAN_CAN_COUNTER:
  .byte $00,$60,$25,$30,$27,$0C,$2A,$0C,$29,$0C,$27,$0C,$2C,$18,$2C,$18
  .byte $2C,$0C,$2E,$0C,$29,$0C,$2A,$0C,$27,$18,$27,$18,$FC,<(S_CAN_CAN_COUNTER+4),>(S_CAN_CAN_COUNTER+4),$04
  .byte $25,$0C,$31,$0C,$30,$0C,$2E,$0C,$2C,$0C,$FC,<(S_CAN_CAN_COUNTER+6),>(S_CAN_CAN_COUNTER+6),$03,$FC,<(S_CAN_CAN_COUNTER+2)
  .byte >(S_CAN_CAN_COUNTER+2),$0D,$FC,<(S_CAN_CAN_COUNTER+4),>(S_CAN_CAN_COUNTER+4),$04,$25,$0C,$20,$0C,$27,$0C,$29,$0C,$25,$30
  .byte $31,$30,$33,$0C,$36,$0B,$35,$0C,$33,$0C,$38,$17,$38,$18,$38,$0B
  .byte $3A,$0C,$35,$0B,$36,$0C,$33,$17,$33,$17,$33,$0B,$36,$0B,$35,$0C
  .byte $33,$0B,$31,$0B,$3D,$0B,$3C,$0C,$3A,$0B,$38,$0B,$36,$0B,$35,$0B
  .byte $33,$0B,$31,$2C,$33,$0B,$36,$0A,$35,$0B,$33,$0B,$38,$15,$38,$16
  .byte $38,$0A,$3A,$0B,$35,$0A,$36,$0B,$33,$15,$33,$15,$33,$0A,$36,$0A
  .byte $35,$0B,$33,$0A,$31,$0A,$2C,$0A,$33,$0B,$35,$0A,$31,$28,$31,$28
  .byte $33,$0A,$36,$09,$35,$0A,$33,$0A,$38,$13,$38,$14,$38,$09,$3A,$0A
  .byte $35,$09,$36,$0A,$33,$13,$33,$13,$33,$09,$36,$09,$35,$0A,$33,$09
  .byte $31,$09,$3D,$09,$3C,$0A,$3A,$09,$38,$09,$36,$09,$35,$09,$33,$09
  .byte $31,$24,$33,$09,$36,$08,$35,$09,$33,$09,$38,$11,$38,$12,$38,$08
  .byte $3A,$09,$35,$08,$36,$09,$33,$11,$33,$11,$33,$08,$36,$08,$35,$09
  .byte $33,$08,$31,$08,$2C,$08,$33,$09,$35,$08,$31,$20,$31,$08,$00,$09
  .byte $2C,$0A,$00,$0B,$31,$0B,$00,$27,$FF
S_CAN_CAN_DRUMS:
  .byte $01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$02,$06,$02,$06
  .byte $02,$06,$02,$06,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06
  .byte $FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06
  .byte $FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$06
  .byte $FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$03,$02,$0B,$FC,<(S_CAN_CAN_DRUMS+0),>(S_CAN_CAN_DRUMS+0),$03,$02,$0B,$01,$0C,$02,$0C
  .byte $01,$0B,$02,$0C,$01,$0B,$FC,<(S_CAN_CAN_DRUMS+78),>(S_CAN_CAN_DRUMS+78),$04,$02,$0C,$01,$0B,$02,$0B
  .byte $01,$0C,$02,$0B,$FC,<(S_CAN_CAN_DRUMS+92),>(S_CAN_CAN_DRUMS+92),$04,$01,$0B,$02,$0B,$01,$0B,$02,$0B
  .byte $FC,<(S_CAN_CAN_DRUMS+104),>(S_CAN_CAN_DRUMS+104),$04,$01,$0B,$02,$0A,$FC,<(S_CAN_CAN_DRUMS+104),>(S_CAN_CAN_DRUMS+104),$03,$02,$0A,$01,$0B
  .byte $02,$0B,$01,$0A,$02,$0B,$01,$0A,$FC,<(S_CAN_CAN_DRUMS+128),>(S_CAN_CAN_DRUMS+128),$04,$02,$0B,$01,$0A
  .byte $02,$0A,$01,$0B,$02,$0A,$FC,<(S_CAN_CAN_DRUMS+142),>(S_CAN_CAN_DRUMS+142),$04,$01,$0A,$02,$0A,$01,$0A
  .byte $02,$0A,$FC,<(S_CAN_CAN_DRUMS+154),>(S_CAN_CAN_DRUMS+154),$04,$01,$0A,$02,$09,$FC,<(S_CAN_CAN_DRUMS+154),>(S_CAN_CAN_DRUMS+154),$03,$02,$09
  .byte $01,$0A,$02,$0A,$01,$09,$02,$0A,$01,$09,$FC,<(S_CAN_CAN_DRUMS+178),>(S_CAN_CAN_DRUMS+178),$04,$02,$0A
  .byte $01,$09,$02,$09,$01,$0A,$02,$09,$FC,<(S_CAN_CAN_DRUMS+192),>(S_CAN_CAN_DRUMS+192),$04,$01,$09,$02,$09
  .byte $01,$09,$02,$09,$FC,<(S_CAN_CAN_DRUMS+204),>(S_CAN_CAN_DRUMS+204),$04,$01,$09,$02,$08,$FC,<(S_CAN_CAN_DRUMS+204),>(S_CAN_CAN_DRUMS+204),$03
  .byte $02,$08,$01,$09,$02,$09,$01,$08,$02,$09,$01,$08,$FC,<(S_CAN_CAN_DRUMS+228),>(S_CAN_CAN_DRUMS+228),$04
  .byte $02,$09,$01,$08,$02,$08,$01,$09,$02,$08,$FC,<(S_CAN_CAN_DRUMS+242),>(S_CAN_CAN_DRUMS+242),$04,$01,$08
  .byte $02,$08,$02,$04,$02,$04,$02,$04,$02,$04,$05,$08,$00,$09,$01,$0A
  .byte $00,$0B,$05,$0B,$00,$27,$FF

; ---- WILLIAM TELL OVERTURE - FINALE (GIOACHINO ROSSINI 1829) ----
SONG_WILLIAM_TELL:
  .word S_WILLIAM_TELL_LEAD, S_WILLIAM_TELL_HARM1, S_WILLIAM_TELL_BASS, S_WILLIAM_TELL_HARM2, 0, S_WILLIAM_TELL_DRUMS
  .byte 14, 9, 3, 12, 1      ; lead
  .byte 8, 3, 1, 0, 1      ; harm1
  .byte 12, 6, 3, 0, 1      ; bass
  .byte 7, 3, 1, 0, 1      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_WILLIAM_TELL_LEAD:
  .byte $29,$0C,$2D,$0C,$30,$0B,$35,$0C,$39,$0B,$00,$0C,$39,$0B,$00,$0B
  .byte $3C,$2B,$00,$29,$30,$05,$30,$05,$30,$0A,$FC,<(S_WILLIAM_TELL_LEAD+20),>(S_WILLIAM_TELL_LEAD+20),$03,$30,$05
  .byte $30,$05,$35,$0A,$37,$0A,$39,$0A,$FC,<(S_WILLIAM_TELL_LEAD+20),>(S_WILLIAM_TELL_LEAD+20),$03,$FC,<(S_WILLIAM_TELL_LEAD+30),>(S_WILLIAM_TELL_LEAD+30),$03
  .byte $39,$05,$39,$05,$37,$0A,$34,$0A,$30,$0A,$FC,<(S_WILLIAM_TELL_LEAD+20),>(S_WILLIAM_TELL_LEAD+20),$03,$FC,<(S_WILLIAM_TELL_LEAD+20)
  .byte >(S_WILLIAM_TELL_LEAD+20),$03,$FC,<(S_WILLIAM_TELL_LEAD+30),>(S_WILLIAM_TELL_LEAD+30),$05,$35,$05,$39,$05,$3C,$0A,$3A,$05,$37,$05
  .byte $34,$0A,$35,$14,$00,$14,$FC,<(S_WILLIAM_TELL_LEAD+20),>(S_WILLIAM_TELL_LEAD+20),$03,$FC,<(S_WILLIAM_TELL_LEAD+20),>(S_WILLIAM_TELL_LEAD+20),$03,$FC,<(S_WILLIAM_TELL_LEAD+30)
  .byte >(S_WILLIAM_TELL_LEAD+30),$05,$FC,<(S_WILLIAM_TELL_LEAD+20),>(S_WILLIAM_TELL_LEAD+20),$03,$FC,<(S_WILLIAM_TELL_LEAD+30),>(S_WILLIAM_TELL_LEAD+30),$03,$FC,<(S_WILLIAM_TELL_LEAD+48),>(S_WILLIAM_TELL_LEAD+48),$05,$FC,<(S_WILLIAM_TELL_LEAD+20)
  .byte >(S_WILLIAM_TELL_LEAD+20),$03,$FC,<(S_WILLIAM_TELL_LEAD+20),>(S_WILLIAM_TELL_LEAD+20),$03,$FC,<(S_WILLIAM_TELL_LEAD+30),>(S_WILLIAM_TELL_LEAD+30),$05,$FC,<(S_WILLIAM_TELL_LEAD+70),>(S_WILLIAM_TELL_LEAD+70),$08,$34,$05
  .byte $34,$05,$34,$0A,$FC,<(S_WILLIAM_TELL_LEAD+126),>(S_WILLIAM_TELL_LEAD+126),$03,$34,$05,$34,$05,$37,$0A,$3A,$0A
  .byte $3C,$0A,$35,$05,$35,$05,$35,$0A,$FC,<(S_WILLIAM_TELL_LEAD+146),>(S_WILLIAM_TELL_LEAD+146),$03,$35,$05,$35,$05
  .byte $39,$0A,$3C,$0A,$41,$0A,$FC,<(S_WILLIAM_TELL_LEAD+126),>(S_WILLIAM_TELL_LEAD+126),$03,$FC,<(S_WILLIAM_TELL_LEAD+126),>(S_WILLIAM_TELL_LEAD+126),$03,$FC,<(S_WILLIAM_TELL_LEAD+136)
  .byte >(S_WILLIAM_TELL_LEAD+136),$08,$FC,<(S_WILLIAM_TELL_LEAD+146),>(S_WILLIAM_TELL_LEAD+146),$03,$FC,<(S_WILLIAM_TELL_LEAD+156),>(S_WILLIAM_TELL_LEAD+156),$05,$3C,$05,$3C,$05,$3C,$0A
  .byte $FC,<(S_WILLIAM_TELL_LEAD+186),>(S_WILLIAM_TELL_LEAD+186),$03,$3C,$05,$3C,$05,$41,$0A,$43,$0A,$45,$0A,$FC,<(S_WILLIAM_TELL_LEAD+186)
  .byte >(S_WILLIAM_TELL_LEAD+186),$03,$FC,<(S_WILLIAM_TELL_LEAD+196),>(S_WILLIAM_TELL_LEAD+196),$03,$45,$05,$45,$05,$43,$0A,$40,$0A,$3C,$0A
  .byte $FC,<(S_WILLIAM_TELL_LEAD+186),>(S_WILLIAM_TELL_LEAD+186),$03,$FC,<(S_WILLIAM_TELL_LEAD+186),>(S_WILLIAM_TELL_LEAD+186),$03,$FC,<(S_WILLIAM_TELL_LEAD+196),>(S_WILLIAM_TELL_LEAD+196),$05,$41,$05,$45,$05
  .byte $48,$0A,$46,$05,$43,$05,$40,$0A,$41,$14,$00,$14,$FC,<(S_WILLIAM_TELL_LEAD+186),>(S_WILLIAM_TELL_LEAD+186),$03
  .byte $FC,<(S_WILLIAM_TELL_LEAD+186),>(S_WILLIAM_TELL_LEAD+186),$03,$FC,<(S_WILLIAM_TELL_LEAD+196),>(S_WILLIAM_TELL_LEAD+196),$05,$FC,<(S_WILLIAM_TELL_LEAD+186),>(S_WILLIAM_TELL_LEAD+186),$03,$FC,<(S_WILLIAM_TELL_LEAD+196),>(S_WILLIAM_TELL_LEAD+196),$03
  .byte $FC,<(S_WILLIAM_TELL_LEAD+214),>(S_WILLIAM_TELL_LEAD+214),$05,$FC,<(S_WILLIAM_TELL_LEAD+186),>(S_WILLIAM_TELL_LEAD+186),$03,$FC,<(S_WILLIAM_TELL_LEAD+186),>(S_WILLIAM_TELL_LEAD+186),$03,$FC,<(S_WILLIAM_TELL_LEAD+196),>(S_WILLIAM_TELL_LEAD+196),$05
  .byte $FC,<(S_WILLIAM_TELL_LEAD+236),>(S_WILLIAM_TELL_LEAD+236),$08,$41,$0A,$00,$0B,$3C,$0B,$00,$0B,$41,$0C,$00,$0C
  .byte $35,$0C,$00,$0D,$41,$37,$00,$3D,$FF
S_WILLIAM_TELL_HARM1:
  .byte $2D,$06,$2D,$06,$00,$0C,$2D,$06,$2D,$05,$FC,<(S_WILLIAM_TELL_HARM1+4),>(S_WILLIAM_TELL_HARM1+4),$03,$00,$0C
  .byte $2D,$05,$2D,$06,$00,$0B,$FC,<(S_WILLIAM_TELL_HARM1+16),>(S_WILLIAM_TELL_HARM1+16),$03,$2D,$05,$2D,$05,$00,$0B
  .byte $34,$05,$34,$05,$FC,<(S_WILLIAM_TELL_HARM1+30),>(S_WILLIAM_TELL_HARM1+30),$03,$00,$0A,$2D,$05,$2D,$05,$FC,<(S_WILLIAM_TELL_HARM1+40)
  .byte >(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40)
  .byte >(S_WILLIAM_TELL_HARM1+40),$03,$00,$0A,$34,$05,$34,$05,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM1+66),>(S_WILLIAM_TELL_HARM1+66),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03,$FC,<(S_WILLIAM_TELL_HARM1+40),>(S_WILLIAM_TELL_HARM1+40),$03
  .byte $00,$0B,$FC,<(S_WILLIAM_TELL_HARM1+16),>(S_WILLIAM_TELL_HARM1+16),$03,$34,$06,$34,$06,$00,$0C,$34,$06,$34,$06
  .byte $00,$0D,$2D,$07,$2D,$06,$00,$0E,$2D,$07,$2D,$07,$00,$0E,$2D,$07
  .byte $2D,$08,$00,$0F,$2D,$07,$2D,$08,$00,$10,$FF
S_WILLIAM_TELL_BASS:
  .byte $11,$0C,$0C,$0C,$11,$0B,$0C,$0C,$11,$0B,$0C,$0C,$11,$0B,$0C,$0B
  .byte $11,$0B,$0C,$0B,$11,$0A,$0C,$0B,$18,$0A,$13,$0B,$18,$0A,$13,$0A
  .byte $11,$0A,$0C,$0A,$11,$0A,$0C,$0A,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04
  .byte $18,$0A,$13,$0A,$FC,<(S_WILLIAM_TELL_BASS+28),>(S_WILLIAM_TELL_BASS+28),$06,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$18,$0A,$13,$0A
  .byte $FC,<(S_WILLIAM_TELL_BASS+28),>(S_WILLIAM_TELL_BASS+28),$06,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04
  .byte $18,$0A,$13,$0A,$FC,<(S_WILLIAM_TELL_BASS+28),>(S_WILLIAM_TELL_BASS+28),$06,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$18,$0A,$13,$0A
  .byte $FC,<(S_WILLIAM_TELL_BASS+28),>(S_WILLIAM_TELL_BASS+28),$06,$18,$0A,$13,$0A,$18,$0A,$13,$0A,$FC,<(S_WILLIAM_TELL_BASS+100),>(S_WILLIAM_TELL_BASS+100),$04
  .byte $FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+100),>(S_WILLIAM_TELL_BASS+100),$04,$FC,<(S_WILLIAM_TELL_BASS+100),>(S_WILLIAM_TELL_BASS+100),$04
  .byte $FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04
  .byte $FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+100),>(S_WILLIAM_TELL_BASS+100),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04
  .byte $FC,<(S_WILLIAM_TELL_BASS+100),>(S_WILLIAM_TELL_BASS+100),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04
  .byte $FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+100),>(S_WILLIAM_TELL_BASS+100),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04
  .byte $FC,<(S_WILLIAM_TELL_BASS+100),>(S_WILLIAM_TELL_BASS+100),$04,$FC,<(S_WILLIAM_TELL_BASS+32),>(S_WILLIAM_TELL_BASS+32),$04,$11,$0A,$FC,<(S_WILLIAM_TELL_BASS+14),>(S_WILLIAM_TELL_BASS+14),$03,$18,$0C
  .byte $13,$0C,$18,$0C,$13,$0D,$11,$0D,$0C,$0E,$11,$0E,$0C,$0E,$11,$0F
  .byte $0C,$0F,$11,$0F,$0C,$10,$FF
S_WILLIAM_TELL_HARM2:
  .byte $24,$06,$24,$06,$00,$0C,$24,$06,$24,$05,$FC,<(S_WILLIAM_TELL_HARM2+4),>(S_WILLIAM_TELL_HARM2+4),$03,$00,$0C
  .byte $24,$05,$24,$06,$00,$0B,$FC,<(S_WILLIAM_TELL_HARM2+16),>(S_WILLIAM_TELL_HARM2+16),$03,$24,$05,$24,$05,$00,$0B
  .byte $2B,$05,$2B,$05,$FC,<(S_WILLIAM_TELL_HARM2+30),>(S_WILLIAM_TELL_HARM2+30),$03,$00,$0A,$24,$05,$24,$05,$FC,<(S_WILLIAM_TELL_HARM2+40)
  .byte >(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40)
  .byte >(S_WILLIAM_TELL_HARM2+40),$03,$00,$0A,$2B,$05,$2B,$05,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03
  .byte $FC,<(S_WILLIAM_TELL_HARM2+66),>(S_WILLIAM_TELL_HARM2+66),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03,$FC,<(S_WILLIAM_TELL_HARM2+40),>(S_WILLIAM_TELL_HARM2+40),$03
  .byte $00,$0B,$FC,<(S_WILLIAM_TELL_HARM2+16),>(S_WILLIAM_TELL_HARM2+16),$03,$2B,$06,$2B,$06,$00,$0C,$2B,$06,$2B,$06
  .byte $00,$0D,$24,$07,$24,$06,$00,$0E,$24,$07,$24,$07,$00,$0E,$24,$07
  .byte $24,$08,$00,$0F,$24,$07,$24,$08,$00,$10,$FF
S_WILLIAM_TELL_DRUMS:
  .byte $05,$2F,$00,$2D,$00,$2B,$02,$05,$02,$05,$02,$06,$02,$05,$02,$05
  .byte $02,$05,$02,$05,$02,$05,$01,$0A,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03
  .byte $FC,<(S_WILLIAM_TELL_DRUMS+18),>(S_WILLIAM_TELL_DRUMS+18),$03,$02,$05,$02,$05,$05,$0A,$00,$0B,$01,$0B,$00,$0B
  .byte $05,$0C,$00,$0C,$01,$0C,$00,$0D,$05,$37,$00,$3D,$FF

; ---- FUR ELISE  (L. VAN BEETHOVEN 1810) ----
SONG_FUR_ELISE:
  .word S_FUR_ELISE_LEAD, 0, S_FUR_ELISE_BASS, 0, 0, 0
  .byte 13, 4, 7, 0, 1      ; lead
  .byte 9, 4, 3, 0, 1      ; harm1
  .byte 10, 3, 7, 0, 1      ; bass
  .byte 8, 4, 3, 0, 1      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_FUR_ELISE_LEAD:
  .byte $35,$08,$34,$08,$35,$08,$34,$08,$35,$08,$30,$08,$33,$08,$31,$08
  .byte $2E,$10,$00,$08,$25,$08,$29,$08,$2E,$08,$30,$10,$00,$08,$29,$08
  .byte $2D,$08,$30,$08,$31,$10,$00,$08,$29,$08,$FC,<(S_FUR_ELISE_LEAD+0),>(S_FUR_ELISE_LEAD+0),$10,$31,$08
  .byte $30,$08,$2E,$20,$FC,<(S_FUR_ELISE_LEAD+0),>(S_FUR_ELISE_LEAD+0),$15,$FC,<(S_FUR_ELISE_LEAD+0),>(S_FUR_ELISE_LEAD+0),$10,$31,$08,$30,$08
  .byte $2E,$10,$00,$08,$30,$08,$31,$08,$33,$08,$35,$18,$2C,$08,$36,$08
  .byte $35,$08,$33,$18,$2A,$08,$35,$08,$33,$08,$31,$18,$29,$08,$33,$08
  .byte $31,$08,$FC,<(S_FUR_ELISE_LEAD+26),>(S_FUR_ELISE_LEAD+26),$03,$35,$08,$00,$08,$00,$08,$35,$08,$41,$08
  .byte $00,$08,$00,$08,$34,$08,$FC,<(S_FUR_ELISE_LEAD+102),>(S_FUR_ELISE_LEAD+102),$03,$FC,<(S_FUR_ELISE_LEAD+2),>(S_FUR_ELISE_LEAD+2),$04,$FC,<(S_FUR_ELISE_LEAD+2)
  .byte >(S_FUR_ELISE_LEAD+2),$04,$FC,<(S_FUR_ELISE_LEAD+2),>(S_FUR_ELISE_LEAD+2),$14,$FC,<(S_FUR_ELISE_LEAD+0),>(S_FUR_ELISE_LEAD+0),$10,$FC,<(S_FUR_ELISE_LEAD+46),>(S_FUR_ELISE_LEAD+46),$03,$FC,<(S_FUR_ELISE_LEAD+0)
  .byte >(S_FUR_ELISE_LEAD+0),$15,$FC,<(S_FUR_ELISE_LEAD+0),>(S_FUR_ELISE_LEAD+0),$10,$FC,<(S_FUR_ELISE_LEAD+60),>(S_FUR_ELISE_LEAD+60),$13,$FC,<(S_FUR_ELISE_LEAD+26),>(S_FUR_ELISE_LEAD+26),$03,$FC,<(S_FUR_ELISE_LEAD+102)
  .byte >(S_FUR_ELISE_LEAD+102),$08,$FC,<(S_FUR_ELISE_LEAD+102),>(S_FUR_ELISE_LEAD+102),$03,$FC,<(S_FUR_ELISE_LEAD+2),>(S_FUR_ELISE_LEAD+2),$04,$FC,<(S_FUR_ELISE_LEAD+2),>(S_FUR_ELISE_LEAD+2),$04,$FC,<(S_FUR_ELISE_LEAD+2)
  .byte >(S_FUR_ELISE_LEAD+2),$14,$FC,<(S_FUR_ELISE_LEAD+0),>(S_FUR_ELISE_LEAD+0),$10,$31,$08,$30,$08,$2E,$3B,$FF
S_FUR_ELISE_BASS:
  .byte $00,$10,$00,$30,$16,$08,$1D,$08,$22,$08,$00,$18,$11,$08,$1D,$08
  .byte $21,$08,$00,$18,$FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$04,$FC,<(S_FUR_ELISE_BASS+2),>(S_FUR_ELISE_BASS+2),$09,$FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$04
  .byte $FC,<(S_FUR_ELISE_BASS+2),>(S_FUR_ELISE_BASS+2),$09,$FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$04,$FC,<(S_FUR_ELISE_BASS+2),>(S_FUR_ELISE_BASS+2),$09,$FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$04
  .byte $19,$08,$20,$08,$25,$08,$00,$18,$14,$08,$20,$08,$24,$08,$00,$18
  .byte $FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$06,$29,$08,$00,$18,$00,$30,$00,$30,$00,$30,$FC,<(S_FUR_ELISE_BASS+2)
  .byte >(S_FUR_ELISE_BASS+2),$09,$FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$04,$FC,<(S_FUR_ELISE_BASS+2),>(S_FUR_ELISE_BASS+2),$09,$FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$04,$FC,<(S_FUR_ELISE_BASS+2)
  .byte >(S_FUR_ELISE_BASS+2),$09,$FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$04,$FC,<(S_FUR_ELISE_BASS+2),>(S_FUR_ELISE_BASS+2),$09,$FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$04,$FC,<(S_FUR_ELISE_BASS+48)
  .byte >(S_FUR_ELISE_BASS+48),$08,$FC,<(S_FUR_ELISE_BASS+4),>(S_FUR_ELISE_BASS+4),$06,$FC,<(S_FUR_ELISE_BASS+68),>(S_FUR_ELISE_BASS+68),$05,$FC,<(S_FUR_ELISE_BASS+2),>(S_FUR_ELISE_BASS+2),$09,$FC,<(S_FUR_ELISE_BASS+4)
  .byte >(S_FUR_ELISE_BASS+4),$04,$FC,<(S_FUR_ELISE_BASS+2),>(S_FUR_ELISE_BASS+2),$09,$16,$08,$1D,$09,$22,$0A,$00,$20,$FF

; ---- MAZE CHASE  (ORIGINAL - MINIVIC SOUND) ----
SONG_MAZE_CHASE:
  .word S_MAZE_CHASE_LEAD, S_MAZE_CHASE_HARM1, S_MAZE_CHASE_BASS, S_MAZE_CHASE_HARM2, 0, S_MAZE_CHASE_DRUMS
  .byte 13, 9, 3, 12, 1      ; lead
  .byte 7, 3, 1, 0, 0      ; harm1
  .byte 12, 6, 1, 0, 1      ; bass
  .byte 6, 5, 15, 0, 0      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_MAZE_CHASE_LEAD:
  .byte $00,$FF,$FE,$41,$31,$0A,$34,$0A,$38,$0A,$3D,$0A,$3C,$0A,$38,$0A
  .byte $34,$14,$2D,$0A,$31,$0A,$34,$0A,$39,$0A,$38,$14,$34,$14,$2F,$0A
  .byte $33,$0A,$36,$0A,$3B,$0A,$3A,$0A,$36,$0A,$33,$14,$38,$0A,$36,$0A
  .byte $34,$0A,$33,$0A,$30,$14,$2C,$14,$FC,<(S_MAZE_CHASE_LEAD+4),>(S_MAZE_CHASE_LEAD+4),$1A,$3D,$05,$3C,$05
  .byte $3D,$05,$3C,$05,$3D,$14,$38,$14,$34,$14,$39,$05,$38,$05,$39,$05
  .byte $38,$05,$39,$14,$34,$14,$31,$14,$3B,$05,$3A,$05,$3B,$05,$3A,$05
  .byte $3B,$14,$36,$14,$33,$14,$38,$0A,$39,$0A,$FC,<(S_MAZE_CHASE_LEAD+44),>(S_MAZE_CHASE_LEAD+44),$04,$31,$0A
  .byte $30,$0A,$FC,<(S_MAZE_CHASE_LEAD+60),>(S_MAZE_CHASE_LEAD+60),$17,$FC,<(S_MAZE_CHASE_LEAD+44),>(S_MAZE_CHASE_LEAD+44),$04,$31,$0A,$30,$0A,$FD,$0E
  .byte $FC,<(S_MAZE_CHASE_LEAD+4),>(S_MAZE_CHASE_LEAD+4),$1A,$FC,<(S_MAZE_CHASE_LEAD+4),>(S_MAZE_CHASE_LEAD+4),$1A,$FC,<(S_MAZE_CHASE_LEAD+60),>(S_MAZE_CHASE_LEAD+60),$17,$FC,<(S_MAZE_CHASE_LEAD+44),>(S_MAZE_CHASE_LEAD+44),$04
  .byte $31,$0A,$30,$0A,$FC,<(S_MAZE_CHASE_LEAD+60),>(S_MAZE_CHASE_LEAD+60),$17,$FC,<(S_MAZE_CHASE_LEAD+44),>(S_MAZE_CHASE_LEAD+44),$04,$31,$0A,$30,$0A
  .byte $31,$0A,$00,$0A,$2C,$0A,$00,$0A,$31,$14,$00,$14,$FF
S_MAZE_CHASE_HARM1:
  .byte $00,$FF,$FE,$41,$25,$05,$28,$05,$2C,$05,$31,$05,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$2D,$05,$31,$05,$34,$05,$39,$05
  .byte $FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$2F,$05,$33,$05
  .byte $36,$05,$3B,$05,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04
  .byte $2C,$05,$30,$05,$33,$05,$38,$05,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+4),>(S_MAZE_CHASE_HARM1+4),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+24),>(S_MAZE_CHASE_HARM1+24),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+44),>(S_MAZE_CHASE_HARM1+44),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04
  .byte $FC,<(S_MAZE_CHASE_HARM1+64),>(S_MAZE_CHASE_HARM1+64),$04,$28,$0A,$00,$0A,$27,$0A,$00,$0A,$25,$14,$00,$14
  .byte $FF
S_MAZE_CHASE_BASS:
  .byte $0D,$0A,$19,$0A,$0D,$0A,$19,$0A,$FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$15,$0A,$21,$0A
  .byte $15,$0A,$21,$0A,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04,$17,$0A,$23,$0A,$17,$0A,$23,$0A
  .byte $FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$14,$0A,$20,$0A,$14,$0A,$20,$0A,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+0),>(S_MAZE_CHASE_BASS+0),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04,$FC,<(S_MAZE_CHASE_BASS+12),>(S_MAZE_CHASE_BASS+12),$04
  .byte $FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+24),>(S_MAZE_CHASE_BASS+24),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04,$FC,<(S_MAZE_CHASE_BASS+36),>(S_MAZE_CHASE_BASS+36),$04
  .byte $0D,$0A,$00,$0A,$08,$0A,$00,$0A,$0D,$14,$00,$14,$FF
S_MAZE_CHASE_HARM2:
  .byte $00,$FF,$FE,$41,$1C,$50,$25,$50,$27,$50,$24,$50,$FC,<(S_MAZE_CHASE_HARM2+4),>(S_MAZE_CHASE_HARM2+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM2+4),>(S_MAZE_CHASE_HARM2+4),$04,$FC,<(S_MAZE_CHASE_HARM2+4),>(S_MAZE_CHASE_HARM2+4),$04,$FC,<(S_MAZE_CHASE_HARM2+4),>(S_MAZE_CHASE_HARM2+4),$04,$FC,<(S_MAZE_CHASE_HARM2+4),>(S_MAZE_CHASE_HARM2+4),$04
  .byte $FC,<(S_MAZE_CHASE_HARM2+4),>(S_MAZE_CHASE_HARM2+4),$04,$FC,<(S_MAZE_CHASE_HARM2+4),>(S_MAZE_CHASE_HARM2+4),$04,$20,$14,$00,$3C,$FF
S_MAZE_CHASE_DRUMS:
  .byte $01,$0A,$03,$0A,$02,$0A,$03,$0A,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $06,$05,$06,$05,$07,$05,$07,$05,$02,$05,$02,$05,$02,$05,$02,$05
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04
  .byte $FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$FC,<(S_MAZE_CHASE_DRUMS+0),>(S_MAZE_CHASE_DRUMS+0),$04,$01,$0A,$02,$0A,$02,$0A,$02,$0A
  .byte $FC,<(S_MAZE_CHASE_DRUMS+40),>(S_MAZE_CHASE_DRUMS+40),$04,$FC,<(S_MAZE_CHASE_DRUMS+40),>(S_MAZE_CHASE_DRUMS+40),$04,$01,$0A,$00,$0A,$01,$0A,$00,$0A
  .byte $05,$28,$FF

; ---- DUNGEON BOSS  (ORIGINAL - MINIVIC SOUND) ----
SONG_DUNGEON_BOSS:
  .word S_DUNGEON_BOSS_LEAD, S_DUNGEON_BOSS_HARM1, S_DUNGEON_BOSS_BASS, S_DUNGEON_BOSS_HARM2, S_DUNGEON_BOSS_COUNTER, S_DUNGEON_BOSS_DRUMS
  .byte 13, 10, 7, 12, 0      ; lead
  .byte 7, 6, 15, 0, 0      ; harm1
  .byte 13, 6, 1, 0, 1      ; bass
  .byte 7, 6, 15, 0, 0      ; harm2
  .byte 10, 8, 7, 0, 0      ; counter
S_DUNGEON_BOSS_LEAD:
  .byte $00,$C0,$35,$24,$36,$0C,$35,$18,$30,$18,$31,$24,$30,$0C,$2F,$30
  .byte $35,$24,$36,$0C,$38,$18,$3B,$18,$3C,$48,$00,$18,$FC,<(S_DUNGEON_BOSS_LEAD+2),>(S_DUNGEON_BOSS_LEAD+2),$0D
  .byte $38,$18,$37,$18,$35,$18,$34,$18,$35,$18,$37,$18,$38,$18,$3A,$18
  .byte $3A,$24,$38,$0C,$FC,<(S_DUNGEON_BOSS_LEAD+34),>(S_DUNGEON_BOSS_LEAD+34),$04,$37,$30,$FC,<(S_DUNGEON_BOSS_LEAD+2),>(S_DUNGEON_BOSS_LEAD+2),$0D,$FC,<(S_DUNGEON_BOSS_LEAD+32)
  .byte >(S_DUNGEON_BOSS_LEAD+32),$0A,$FC,<(S_DUNGEON_BOSS_LEAD+34),>(S_DUNGEON_BOSS_LEAD+34),$04,$37,$30,$FC,<(S_DUNGEON_BOSS_LEAD+2),>(S_DUNGEON_BOSS_LEAD+2),$0D,$35,$18,$00,$18
  .byte $29,$18,$00,$18,$35,$60,$FF
S_DUNGEON_BOSS_HARM1:
  .byte $00,$C0,$24,$60,$29,$60,$24,$60,$2B,$60,$FC,<(S_DUNGEON_BOSS_HARM1+2),>(S_DUNGEON_BOSS_HARM1+2),$04,$24,$60
  .byte $20,$60,$29,$60,$2B,$60,$FC,<(S_DUNGEON_BOSS_HARM1+2),>(S_DUNGEON_BOSS_HARM1+2),$04,$FC,<(S_DUNGEON_BOSS_HARM1+14),>(S_DUNGEON_BOSS_HARM1+14),$04,$FC,<(S_DUNGEON_BOSS_HARM1+2)
  .byte >(S_DUNGEON_BOSS_HARM1+2),$04,$29,$60,$29,$60,$FF
S_DUNGEON_BOSS_BASS:
  .byte $11,$0C,$11,$0C,$1D,$0C,$11,$0C,$14,$0C,$11,$0C,$17,$0C,$18,$0C
  .byte $FC,<(S_DUNGEON_BOSS_BASS+0),>(S_DUNGEON_BOSS_BASS+0),$08,$FC,<(S_DUNGEON_BOSS_BASS+0),>(S_DUNGEON_BOSS_BASS+0),$08,$16,$0C,$16,$0C,$22,$0C,$16,$0C
  .byte $19,$0C,$16,$0C,$1C,$0C,$1D,$0C,$FC,<(S_DUNGEON_BOSS_BASS+0),>(S_DUNGEON_BOSS_BASS+0),$08,$18,$0C,$18,$0C
  .byte $24,$0C,$18,$0C,$1B,$0C,$18,$0C,$1E,$0C,$1F,$0C,$FC,<(S_DUNGEON_BOSS_BASS+0),>(S_DUNGEON_BOSS_BASS+0),$08
  .byte $FC,<(S_DUNGEON_BOSS_BASS+24),>(S_DUNGEON_BOSS_BASS+24),$08,$FC,<(S_DUNGEON_BOSS_BASS+0),>(S_DUNGEON_BOSS_BASS+0),$08,$FC,<(S_DUNGEON_BOSS_BASS+44),>(S_DUNGEON_BOSS_BASS+44),$08,$05,$0C,$05,$0C
  .byte $11,$0C,$05,$0C,$FC,<(S_DUNGEON_BOSS_BASS+76),>(S_DUNGEON_BOSS_BASS+76),$04,$01,$0C,$01,$0C,$0D,$0C,$01,$0C
  .byte $FC,<(S_DUNGEON_BOSS_BASS+88),>(S_DUNGEON_BOSS_BASS+88),$04,$0A,$0C,$0A,$0C,$16,$0C,$0A,$0C,$FC,<(S_DUNGEON_BOSS_BASS+100),>(S_DUNGEON_BOSS_BASS+100),$04
  .byte $0C,$0C,$0C,$0C,$18,$0C,$0C,$0C,$FC,<(S_DUNGEON_BOSS_BASS+112),>(S_DUNGEON_BOSS_BASS+112),$04,$FC,<(S_DUNGEON_BOSS_BASS+0),>(S_DUNGEON_BOSS_BASS+0),$08
  .byte $FC,<(S_DUNGEON_BOSS_BASS+24),>(S_DUNGEON_BOSS_BASS+24),$08,$FC,<(S_DUNGEON_BOSS_BASS+0),>(S_DUNGEON_BOSS_BASS+0),$08,$FC,<(S_DUNGEON_BOSS_BASS+44),>(S_DUNGEON_BOSS_BASS+44),$08,$FC,<(S_DUNGEON_BOSS_BASS+76),>(S_DUNGEON_BOSS_BASS+76),$04
  .byte $FC,<(S_DUNGEON_BOSS_BASS+76),>(S_DUNGEON_BOSS_BASS+76),$04,$FC,<(S_DUNGEON_BOSS_BASS+88),>(S_DUNGEON_BOSS_BASS+88),$04,$FC,<(S_DUNGEON_BOSS_BASS+88),>(S_DUNGEON_BOSS_BASS+88),$04,$FC,<(S_DUNGEON_BOSS_BASS+100),>(S_DUNGEON_BOSS_BASS+100),$04
  .byte $FC,<(S_DUNGEON_BOSS_BASS+100),>(S_DUNGEON_BOSS_BASS+100),$04,$FC,<(S_DUNGEON_BOSS_BASS+112),>(S_DUNGEON_BOSS_BASS+112),$04,$FC,<(S_DUNGEON_BOSS_BASS+112),>(S_DUNGEON_BOSS_BASS+112),$04,$FC,<(S_DUNGEON_BOSS_BASS+0),>(S_DUNGEON_BOSS_BASS+0),$08
  .byte $FC,<(S_DUNGEON_BOSS_BASS+24),>(S_DUNGEON_BOSS_BASS+24),$08,$FC,<(S_DUNGEON_BOSS_BASS+0),>(S_DUNGEON_BOSS_BASS+0),$08,$FC,<(S_DUNGEON_BOSS_BASS+44),>(S_DUNGEON_BOSS_BASS+44),$08,$11,$18,$00,$18
  .byte $05,$18,$00,$18,$05,$60,$FF
S_DUNGEON_BOSS_HARM2:
  .byte $00,$C0,$1D,$60,$22,$60,$1D,$60,$24,$60,$FC,<(S_DUNGEON_BOSS_HARM2+2),>(S_DUNGEON_BOSS_HARM2+2),$04,$1D,$60
  .byte $19,$60,$22,$60,$24,$60,$FC,<(S_DUNGEON_BOSS_HARM2+2),>(S_DUNGEON_BOSS_HARM2+2),$04,$FC,<(S_DUNGEON_BOSS_HARM2+14),>(S_DUNGEON_BOSS_HARM2+14),$04,$FC,<(S_DUNGEON_BOSS_HARM2+2)
  .byte >(S_DUNGEON_BOSS_HARM2+2),$04,$29,$60,$29,$60,$FF
S_DUNGEON_BOSS_COUNTER:
  .byte $00,$C0,$29,$24,$2A,$0C,$29,$18,$24,$18,$25,$24,$24,$0C,$23,$30
  .byte $29,$24,$2A,$0C,$2C,$18,$2F,$18,$30,$48,$00,$18,$FC,<(S_DUNGEON_BOSS_COUNTER+2),>(S_DUNGEON_BOSS_COUNTER+2),$0D
  .byte $2C,$18,$2B,$18,$29,$18,$28,$18,$29,$18,$2B,$18,$2C,$18,$2E,$18
  .byte $2E,$24,$2C,$0C,$FC,<(S_DUNGEON_BOSS_COUNTER+34),>(S_DUNGEON_BOSS_COUNTER+34),$04,$2B,$30,$FC,<(S_DUNGEON_BOSS_COUNTER+2),>(S_DUNGEON_BOSS_COUNTER+2),$0D,$FC,<(S_DUNGEON_BOSS_COUNTER+32)
  .byte >(S_DUNGEON_BOSS_COUNTER+32),$0A,$FC,<(S_DUNGEON_BOSS_COUNTER+34),>(S_DUNGEON_BOSS_COUNTER+34),$04,$2B,$30,$FC,<(S_DUNGEON_BOSS_COUNTER+2),>(S_DUNGEON_BOSS_COUNTER+2),$0D,$29,$18,$00,$18
  .byte $1D,$18,$00,$18,$29,$60,$FF
S_DUNGEON_BOSS_DRUMS:
  .byte $01,$0C,$00,$24,$01,$0C,$00,$24,$01,$0C,$00,$0C,$01,$0C,$00,$0C
  .byte $02,$06,$02,$06,$02,$06,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$02,$06,$02,$06,$01,$0C
  .byte $01,$0C,$02,$0C,$01,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04
  .byte $FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C
  .byte $06,$0C,$06,$0C,$07,$0C,$07,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03
  .byte $FC,<(S_DUNGEON_BOSS_DRUMS+26),>(S_DUNGEON_BOSS_DRUMS+26),$06,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04,$FC,<(S_DUNGEON_BOSS_DRUMS+30)
  .byte >(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+62),>(S_DUNGEON_BOSS_DRUMS+62),$05
  .byte $FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+26),>(S_DUNGEON_BOSS_DRUMS+26),$06,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03
  .byte $03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04
  .byte $FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+62),>(S_DUNGEON_BOSS_DRUMS+62),$05,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03
  .byte $FC,<(S_DUNGEON_BOSS_DRUMS+26),>(S_DUNGEON_BOSS_DRUMS+26),$06,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04,$FC,<(S_DUNGEON_BOSS_DRUMS+30)
  .byte >(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+62),>(S_DUNGEON_BOSS_DRUMS+62),$05
  .byte $FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+26),>(S_DUNGEON_BOSS_DRUMS+26),$06,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03
  .byte $03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04
  .byte $FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+62),>(S_DUNGEON_BOSS_DRUMS+62),$05,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03
  .byte $FC,<(S_DUNGEON_BOSS_DRUMS+26),>(S_DUNGEON_BOSS_DRUMS+26),$06,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04,$FC,<(S_DUNGEON_BOSS_DRUMS+30)
  .byte >(S_DUNGEON_BOSS_DRUMS+30),$03,$03,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$04,$FC,<(S_DUNGEON_BOSS_DRUMS+30),>(S_DUNGEON_BOSS_DRUMS+30),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+62),>(S_DUNGEON_BOSS_DRUMS+62),$05
  .byte $FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$FC,<(S_DUNGEON_BOSS_DRUMS+16),>(S_DUNGEON_BOSS_DRUMS+16),$03,$02,$06,$02,$06,$05,$0C,$FC,<(S_DUNGEON_BOSS_DRUMS+2)
  .byte >(S_DUNGEON_BOSS_DRUMS+2),$03,$05,$60,$FF

; ---- HIGH SCORE  (ORIGINAL - MINIVIC SOUND) ----
SONG_HIGH_SCORE:
  .word S_HIGH_SCORE_LEAD, S_HIGH_SCORE_HARM1, S_HIGH_SCORE_BASS, S_HIGH_SCORE_HARM2, 0, S_HIGH_SCORE_DRUMS
  .byte 13, 8, 3, 14, 1      ; lead
  .byte 8, 3, 1, 0, 1      ; harm1
  .byte 12, 6, 3, 0, 1      ; bass
  .byte 7, 3, 1, 0, 1      ; harm2
  .byte 10, 6, 7, 16, 1      ; counter
S_HIGH_SCORE_LEAD:
  .byte $31,$0C,$36,$0C,$3A,$0D,$3D,$19,$3A,$0C,$3D,$1A,$42,$6C,$3A,$1C
  .byte $38,$0E,$36,$0E,$31,$1C,$36,$1C,$38,$1C,$3A,$0E,$3B,$0E,$3A,$38
  .byte $3B,$1C,$3A,$0E,$38,$0E,$33,$1C,$38,$1C,$FC,<(S_HIGH_SCORE_LEAD+14),>(S_HIGH_SCORE_LEAD+14),$03,$35,$38
  .byte $FC,<(S_HIGH_SCORE_LEAD+14),>(S_HIGH_SCORE_LEAD+14),$03,$3D,$1C,$3A,$1C,$FC,<(S_HIGH_SCORE_LEAD+32),>(S_HIGH_SCORE_LEAD+32),$03,$3F,$38,$3D,$1C
  .byte $3B,$0E,$3A,$0E,$38,$1C,$35,$1C,$36,$54,$00,$1C,$3F,$1C,$3D,$0E
  .byte $3B,$0E,$3A,$1C,$36,$1C,$FC,<(S_HIGH_SCORE_LEAD+62),>(S_HIGH_SCORE_LEAD+62),$03,$38,$38,$FC,<(S_HIGH_SCORE_LEAD+32),>(S_HIGH_SCORE_LEAD+32),$03
  .byte $36,$1C,$33,$1C,$35,$1C,$36,$0E,$38,$0E,$3D,$38,$FC,<(S_HIGH_SCORE_LEAD+14),>(S_HIGH_SCORE_LEAD+14),$0E
  .byte $FC,<(S_HIGH_SCORE_LEAD+14),>(S_HIGH_SCORE_LEAD+14),$03,$35,$38,$FC,<(S_HIGH_SCORE_LEAD+14),>(S_HIGH_SCORE_LEAD+14),$03,$3D,$1C,$3A,$1C,$FC,<(S_HIGH_SCORE_LEAD+32)
  .byte >(S_HIGH_SCORE_LEAD+32),$03,$FC,<(S_HIGH_SCORE_LEAD+60),>(S_HIGH_SCORE_LEAD+60),$08,$36,$0E,$3A,$0F,$3D,$10,$42,$5B,$FF
S_HIGH_SCORE_HARM1:
  .byte $2E,$31,$31,$33,$31,$6C,$00,$0E,$2E,$0E,$00,$0E,$2E,$0E,$FC,<(S_HIGH_SCORE_HARM1+6)
  .byte >(S_HIGH_SCORE_HARM1+6),$04,$00,$0E,$29,$0E,$00,$0E,$29,$0E,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$00,$0E
  .byte $2F,$0E,$00,$0E,$2F,$0E,$FC,<(S_HIGH_SCORE_HARM1+30),>(S_HIGH_SCORE_HARM1+30),$04,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+18)
  .byte >(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+6),>(S_HIGH_SCORE_HARM1+6),$04,$FC,<(S_HIGH_SCORE_HARM1+6),>(S_HIGH_SCORE_HARM1+6),$04,$00,$0E,$33,$0E,$00,$0E
  .byte $33,$0E,$FC,<(S_HIGH_SCORE_HARM1+58),>(S_HIGH_SCORE_HARM1+58),$04,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+6)
  .byte >(S_HIGH_SCORE_HARM1+6),$04,$FC,<(S_HIGH_SCORE_HARM1+6),>(S_HIGH_SCORE_HARM1+6),$04,$FC,<(S_HIGH_SCORE_HARM1+58),>(S_HIGH_SCORE_HARM1+58),$04,$FC,<(S_HIGH_SCORE_HARM1+58),>(S_HIGH_SCORE_HARM1+58),$04,$FC,<(S_HIGH_SCORE_HARM1+18)
  .byte >(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+30),>(S_HIGH_SCORE_HARM1+30),$04,$FC,<(S_HIGH_SCORE_HARM1+30),>(S_HIGH_SCORE_HARM1+30),$04,$FC,<(S_HIGH_SCORE_HARM1+18)
  .byte >(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+6),>(S_HIGH_SCORE_HARM1+6),$04,$FC,<(S_HIGH_SCORE_HARM1+6),>(S_HIGH_SCORE_HARM1+6),$04,$FC,<(S_HIGH_SCORE_HARM1+18)
  .byte >(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+30),>(S_HIGH_SCORE_HARM1+30),$04,$FC,<(S_HIGH_SCORE_HARM1+30),>(S_HIGH_SCORE_HARM1+30),$04,$FC,<(S_HIGH_SCORE_HARM1+18)
  .byte >(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+6),>(S_HIGH_SCORE_HARM1+6),$04,$FC,<(S_HIGH_SCORE_HARM1+6),>(S_HIGH_SCORE_HARM1+6),$04,$FC,<(S_HIGH_SCORE_HARM1+58)
  .byte >(S_HIGH_SCORE_HARM1+58),$04,$FC,<(S_HIGH_SCORE_HARM1+58),>(S_HIGH_SCORE_HARM1+58),$04,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+18),>(S_HIGH_SCORE_HARM1+18),$04,$FC,<(S_HIGH_SCORE_HARM1+6)
  .byte >(S_HIGH_SCORE_HARM1+6),$04,$FC,<(S_HIGH_SCORE_HARM1+6),>(S_HIGH_SCORE_HARM1+6),$04,$31,$88,$FF
S_HIGH_SCORE_BASS:
  .byte $12,$0C,$00,$0C,$19,$0D,$00,$0C,$12,$33,$06,$6C,$12,$1C,$19,$1C
  .byte $1E,$1C,$19,$1C,$0D,$1C,$14,$1C,$19,$1C,$14,$1C,$14,$1C,$1B,$1C
  .byte $20,$1C,$1B,$1C,$FC,<(S_HIGH_SCORE_BASS+20),>(S_HIGH_SCORE_BASS+20),$04,$FC,<(S_HIGH_SCORE_BASS+12),>(S_HIGH_SCORE_BASS+12),$04,$17,$1C,$1E,$1C
  .byte $23,$1C,$1E,$1C,$FC,<(S_HIGH_SCORE_BASS+20),>(S_HIGH_SCORE_BASS+20),$04,$FC,<(S_HIGH_SCORE_BASS+12),>(S_HIGH_SCORE_BASS+12),$04,$FC,<(S_HIGH_SCORE_BASS+44),>(S_HIGH_SCORE_BASS+44),$04
  .byte $FC,<(S_HIGH_SCORE_BASS+20),>(S_HIGH_SCORE_BASS+20),$08,$FC,<(S_HIGH_SCORE_BASS+20),>(S_HIGH_SCORE_BASS+20),$04,$FC,<(S_HIGH_SCORE_BASS+12),>(S_HIGH_SCORE_BASS+12),$0C,$FC,<(S_HIGH_SCORE_BASS+20),>(S_HIGH_SCORE_BASS+20),$04
  .byte $FC,<(S_HIGH_SCORE_BASS+12),>(S_HIGH_SCORE_BASS+12),$04,$FC,<(S_HIGH_SCORE_BASS+44),>(S_HIGH_SCORE_BASS+44),$04,$FC,<(S_HIGH_SCORE_BASS+20),>(S_HIGH_SCORE_BASS+20),$04,$FC,<(S_HIGH_SCORE_BASS+12),>(S_HIGH_SCORE_BASS+12),$04
  .byte $12,$0E,$19,$0F,$1E,$6B,$FF
S_HIGH_SCORE_HARM2:
  .byte $2A,$31,$2A,$33,$2E,$6C,$00,$0E,$25,$0E,$00,$0E,$25,$0E,$FC,<(S_HIGH_SCORE_HARM2+6)
  .byte >(S_HIGH_SCORE_HARM2+6),$04,$00,$0E,$20,$0E,$00,$0E,$20,$0E,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$00,$0E
  .byte $27,$0E,$00,$0E,$27,$0E,$FC,<(S_HIGH_SCORE_HARM2+30),>(S_HIGH_SCORE_HARM2+30),$04,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+18)
  .byte >(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+6),>(S_HIGH_SCORE_HARM2+6),$04,$FC,<(S_HIGH_SCORE_HARM2+6),>(S_HIGH_SCORE_HARM2+6),$04,$00,$0E,$2A,$0E,$00,$0E
  .byte $2A,$0E,$FC,<(S_HIGH_SCORE_HARM2+58),>(S_HIGH_SCORE_HARM2+58),$04,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+6)
  .byte >(S_HIGH_SCORE_HARM2+6),$04,$FC,<(S_HIGH_SCORE_HARM2+6),>(S_HIGH_SCORE_HARM2+6),$04,$FC,<(S_HIGH_SCORE_HARM2+58),>(S_HIGH_SCORE_HARM2+58),$04,$FC,<(S_HIGH_SCORE_HARM2+58),>(S_HIGH_SCORE_HARM2+58),$04,$FC,<(S_HIGH_SCORE_HARM2+18)
  .byte >(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+30),>(S_HIGH_SCORE_HARM2+30),$04,$FC,<(S_HIGH_SCORE_HARM2+30),>(S_HIGH_SCORE_HARM2+30),$04,$FC,<(S_HIGH_SCORE_HARM2+18)
  .byte >(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+6),>(S_HIGH_SCORE_HARM2+6),$04,$FC,<(S_HIGH_SCORE_HARM2+6),>(S_HIGH_SCORE_HARM2+6),$04,$FC,<(S_HIGH_SCORE_HARM2+18)
  .byte >(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+30),>(S_HIGH_SCORE_HARM2+30),$04,$FC,<(S_HIGH_SCORE_HARM2+30),>(S_HIGH_SCORE_HARM2+30),$04,$FC,<(S_HIGH_SCORE_HARM2+18)
  .byte >(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+6),>(S_HIGH_SCORE_HARM2+6),$04,$FC,<(S_HIGH_SCORE_HARM2+6),>(S_HIGH_SCORE_HARM2+6),$04,$FC,<(S_HIGH_SCORE_HARM2+58)
  .byte >(S_HIGH_SCORE_HARM2+58),$04,$FC,<(S_HIGH_SCORE_HARM2+58),>(S_HIGH_SCORE_HARM2+58),$04,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+18),>(S_HIGH_SCORE_HARM2+18),$04,$FC,<(S_HIGH_SCORE_HARM2+6)
  .byte >(S_HIGH_SCORE_HARM2+6),$04,$FC,<(S_HIGH_SCORE_HARM2+6),>(S_HIGH_SCORE_HARM2+6),$04,$2E,$88,$FF
S_HIGH_SCORE_DRUMS:
  .byte $02,$06,$02,$06,$02,$06,$02,$06,$02,$06,$02,$07,$02,$06,$02,$06
  .byte $02,$0D,$02,$0C,$02,$0D,$02,$0D,$05,$6C,$01,$0E,$03,$0E,$02,$0E
  .byte $03,$0E,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26)
  .byte >(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26)
  .byte >(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26)
  .byte >(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26)
  .byte >(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26)
  .byte >(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26)
  .byte >(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26)
  .byte >(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26)
  .byte >(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26)
  .byte >(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$FC,<(S_HIGH_SCORE_DRUMS+26),>(S_HIGH_SCORE_DRUMS+26),$04,$06,$07,$06,$07,$07,$07
  .byte $07,$07,$02,$07,$02,$07,$02,$07,$02,$07,$01,$0E,$02,$0F,$05,$6B
  .byte $FF

NSONGS = 16
RND_MASK = 15
SONG_LO: .byte <SONG_MOUNTAIN_KING,<SONG_KOROBEINIKI,<SONG_ENTERTAINER,<SONG_TOCCATA,<SONG_ARCADE_START,<SONG_STAR_PATROL,<SONG_NEON_DRIVE,<SONG_JINGLES,<SONG_BUMBLEBEE,<SONG_ALLA_TURCA,<SONG_CAN_CAN,<SONG_WILLIAM_TELL,<SONG_FUR_ELISE,<SONG_MAZE_CHASE,<SONG_DUNGEON_BOSS,<SONG_HIGH_SCORE
SONG_HI: .byte >SONG_MOUNTAIN_KING,>SONG_KOROBEINIKI,>SONG_ENTERTAINER,>SONG_TOCCATA,>SONG_ARCADE_START,>SONG_STAR_PATROL,>SONG_NEON_DRIVE,>SONG_JINGLES,>SONG_BUMBLEBEE,>SONG_ALLA_TURCA,>SONG_CAN_CAN,>SONG_WILLIAM_TELL,>SONG_FUR_ELISE,>SONG_MAZE_CHASE,>SONG_DUNGEON_BOSS,>SONG_HIGH_SCORE
T1_LO: .byte <JT1_0,<JT1_1,<JT1_2,<JT1_3,<JT1_4,<JT1_5,<JT1_6,<JT1_7,<JT1_8,<JT1_9,<JT1_10,<JT1_11,<JT1_12,<JT1_13,<JT1_14,<JT1_15
T1_HI: .byte >JT1_0,>JT1_1,>JT1_2,>JT1_3,>JT1_4,>JT1_5,>JT1_6,>JT1_7,>JT1_8,>JT1_9,>JT1_10,>JT1_11,>JT1_12,>JT1_13,>JT1_14,>JT1_15
T2_LO: .byte <JT2_0,<JT2_1,<JT2_2,<JT2_3,<JT2_4,<JT2_5,<JT2_6,<JT2_7,<JT2_8,<JT2_9,<JT2_10,<JT2_11,<JT2_12,<JT2_13,<JT2_14,<JT2_15
T2_HI: .byte >JT2_0,>JT2_1,>JT2_2,>JT2_3,>JT2_4,>JT2_5,>JT2_6,>JT2_7,>JT2_8,>JT2_9,>JT2_10,>JT2_11,>JT2_12,>JT2_13,>JT2_14,>JT2_15
AU_LO: .byte <JAU_0,<JAU_1,<JAU_2,<JAU_3,<JAU_4,<JAU_5,<JAU_6,<JAU_7,<JAU_8,<JAU_9,<JAU_10,<JAU_11,<JAU_12,<JAU_13,<JAU_14,<JAU_15
AU_HI: .byte >JAU_0,>JAU_1,>JAU_2,>JAU_3,>JAU_4,>JAU_5,>JAU_6,>JAU_7,>JAU_8,>JAU_9,>JAU_10,>JAU_11,>JAU_12,>JAU_13,>JAU_14,>JAU_15
ITEM_LO: .byte <JIT_0,<JIT_1,<JIT_2,<JIT_3,<JIT_4,<JIT_5,<JIT_6,<JIT_7,<JIT_8,<JIT_9,<JIT_10,<JIT_11,<JIT_12,<JIT_13,<JIT_14,<JIT_15,<JIT_16,<JIT_17
ITEM_HI: .byte >JIT_0,>JIT_1,>JIT_2,>JIT_3,>JIT_4,>JIT_5,>JIT_6,>JIT_7,>JIT_8,>JIT_9,>JIT_10,>JIT_11,>JIT_12,>JIT_13,>JIT_14,>JIT_15,>JIT_16,>JIT_17
JT1_0: .byte "IN THE HALL OF THE", 0
JT2_0: .byte "MOUNTAIN KING", 0
JAU_0: .byte "EDVARD GRIEG 1875", 0
JT1_1: .byte "KOROBEINIKI", 0
JT2_1: .byte "", 0
JAU_1: .byte "RUSSIAN FOLK SONG", 0
JT1_2: .byte "THE ENTERTAINER", 0
JT2_2: .byte "", 0
JAU_2: .byte "SCOTT JOPLIN 1902", 0
JT1_3: .byte "TOCCATA AND FUGUE", 0
JT2_3: .byte "IN D MINOR", 0
JAU_3: .byte "J.S. BACH 1704", 0
JT1_4: .byte "ARCADE START", 0
JT2_4: .byte "", 0
JAU_4: .byte "ORIGINAL - MINIVIC SOUND", 0
JT1_5: .byte "STAR PATROL", 0
JT2_5: .byte "", 0
JAU_5: .byte "ORIGINAL - MINIVIC SOUND", 0
JT1_6: .byte "NEON DRIVE", 0
JT2_6: .byte "", 0
JAU_6: .byte "ORIGINAL - MINIVIC SOUND", 0
JT1_7: .byte "LEVEL CLEAR", 0
JT2_7: .byte "AND GAME OVER", 0
JAU_7: .byte "ORIGINAL - MINIVIC SOUND", 0
JT1_8: .byte "FLIGHT OF THE", 0
JT2_8: .byte "BUMBLEBEE", 0
JAU_8: .byte "N. RIMSKY-KORSAKOV 1900", 0
JT1_9: .byte "RONDO ALLA TURCA", 0
JT2_9: .byte "", 0
JAU_9: .byte "W.A. MOZART 1783", 0
JT1_10: .byte "CAN-CAN", 0
JT2_10: .byte "(GALOP INFERNAL)", 0
JAU_10: .byte "JACQUES OFFENBACH 1858", 0
JT1_11: .byte "WILLIAM TELL", 0
JT2_11: .byte "OVERTURE - FINALE", 0
JAU_11: .byte "GIOACHINO ROSSINI 1829", 0
JT1_12: .byte "FUR ELISE", 0
JT2_12: .byte "", 0
JAU_12: .byte "L. VAN BEETHOVEN 1810", 0
JT1_13: .byte "MAZE CHASE", 0
JT2_13: .byte "", 0
JAU_13: .byte "ORIGINAL - MINIVIC SOUND", 0
JT1_14: .byte "DUNGEON BOSS", 0
JT2_14: .byte "", 0
JAU_14: .byte "ORIGINAL - MINIVIC SOUND", 0
JT1_15: .byte "HIGH SCORE", 0
JT2_15: .byte "", 0
JAU_15: .byte "ORIGINAL - MINIVIC SOUND", 0
JIT_0: .byte "RANDOM PLAY", 0
JIT_1: .byte " 1  MOUNTAIN KING", 0
JIT_2: .byte " 2  KOROBEINIKI", 0
JIT_3: .byte " 3  THE ENTERTAINER", 0
JIT_4: .byte " 4  TOCCATA IN D MINOR", 0
JIT_5: .byte " 5  ARCADE START", 0
JIT_6: .byte " 6  STAR PATROL", 0
JIT_7: .byte " 7  NEON DRIVE", 0
JIT_8: .byte " 8  JINGLES", 0
JIT_9: .byte " 9  FLIGHT OF THE BUMBLEBEE", 0
JIT_10: .byte "10  RONDO ALLA TURCA", 0
JIT_11: .byte "11  CAN-CAN", 0
JIT_12: .byte "12  WILLIAM TELL OVERTURE", 0
JIT_13: .byte "13  FUR ELISE", 0
JIT_14: .byte "14  MAZE CHASE", 0
JIT_15: .byte "15  DUNGEON BOSS", 0
JIT_16: .byte "16  HIGH SCORE", 0
JIT_17: .byte "EXIT TO THE MENU", 0
TXT_OFN: .byte " OF 16", 0
