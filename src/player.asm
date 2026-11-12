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
