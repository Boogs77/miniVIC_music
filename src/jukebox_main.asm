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
