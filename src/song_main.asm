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
