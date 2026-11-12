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
