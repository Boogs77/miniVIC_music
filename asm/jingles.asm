;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   MiniVIC Sound - LEVEL CLEAR AND GAME OVER                  ;
;   ORIGINAL - MINIVIC SOUND                                   ;
;   loaded and started at $1000 (song entry of the SD menu)    ;
;   fire = back to the menu; the song plays again and again    ;
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
;  one song: title, volume bars, the song again and again;
;  fire (joystick 1 or 2) = back to the menu of the BIOS
;  the build adds SONG_HDR, TXT_T1, TXT_T2, TXT_AU
; ===============================================================
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
  JSR BARS_RESET
  JSR VDP_INIT
  JSR DRAW_HEADER
  LDA #2                        ; title in yellow, author in white
  STA TXT_MODE
  LDA #<TXT_T1
  STA TXT_PTR
  LDA #>TXT_T1
  STA TXT_PTR+1
  LDA #5
  JSR PRINT_C
  LDA #<TXT_T2
  STA TXT_PTR
  LDA #>TXT_T2
  STA TXT_PTR+1
  LDA #6
  JSR PRINT_C
  STZ TXT_MODE
  LDA #<TXT_AU
  STA TXT_PTR
  LDA #>TXT_AU
  STA TXT_PTR+1
  LDA #8
  JSR PRINT_C
  JSR DRAW_BAR_LABELS
  LDA #<TXT_FIRE
  STA TXT_PTR
  LDA #>TXT_FIRE
  STA TXT_PTR+1
  LDA #21
  JSR PRINT_C
  LDA #23
  LDY #$6B
  JSR FILL_ROW
  JSR READ_JOY                  ; a button still held does not count
  STZ JNEW
SONG_AGAIN:
  LDX #<SONG_HDR
  LDY #>SONG_HDR
  JSR MUS_START
.loop:
  JSR WAIT_VBL
  JSR MUS_TICK
  JSR AY_FLUSH
  JSR DRAW_BARS
  JSR READ_JOY
  LDA JNEW
  AND #J_FIRE
  BNE SONG_EXIT
  LDA MUS_ON
  BNE .loop
  LDA #90                       ; 1.5 s of silence, then again
  STA WAITC
.pause:
  JSR WAIT_VBL
  JSR DRAW_BARS
  JSR READ_JOY
  LDA JNEW
  AND #J_FIRE
  BNE SONG_EXIT
  DEC WAITC
  BNE .pause
  JMP SONG_AGAIN

SONG_EXIT:
  JSR SND_RESET
  JMP JT_SHOW_MENU

TXT_FIRE: .byte "FIRE = BACK TO THE MENU", 0

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

SONG_HDR = SONG_JINGLES
TXT_T1: .byte "LEVEL CLEAR", 0
TXT_T2: .byte "AND GAME OVER", 0
TXT_AU: .byte "ORIGINAL - MINIVIC SOUND", 0
