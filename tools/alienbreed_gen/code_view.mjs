// ALIEN BREED 64 - view code blocks: camera + double-buffered 8-way
// scroll, sprites, the HUD and messages, text pages (Intex terminal, deck
// complete, game over).

// camera axis: target = player - centre, clamped, eased by CAM_SPEED
function camAxis(ax, p, centre, max, maxLo, maxHi) {
  return `
 SEC
 LDA ${p}
 SBC #${centre}
 STA Z_T0
 LDA ${p}+1
 SBC #$00
 BPL Ca${ax}Pos
 LDA #$00
 STA Z_T0
 JMP Ca${ax}Hi
Ca${ax}Pos:
 CMP #${maxHi}
 BCC Ca${ax}Hi
 BNE Ca${ax}Max
 LDA Z_T0
 CMP #${maxLo}
 BCC Ca${ax}HiA
Ca${ax}Max:
 LDA #${maxLo}
 STA Z_T0
 LDA #${maxHi}
 JMP Ca${ax}Hi
Ca${ax}HiA:
 LDA #${maxHi}
Ca${ax}Hi:
 STA Z_T1
 LDA Z_K
 BNE Ca${ax}Snap
 SEC
 LDA Z_T0
 SBC CAM${ax}
 STA Z_T2
 LDA Z_T1
 SBC CAM${ax}+1
 BMI Ca${ax}Neg
 BNE Ca${ax}Up
 LDA Z_T2
 CMP #CAM_SPEED+1
 BCC Ca${ax}Snap
Ca${ax}Up:
 CLC
 LDA CAM${ax}
 ADC #CAM_SPEED
 STA CAM${ax}
 LDA CAM${ax}+1
 ADC #$00
 STA CAM${ax}+1
 JMP Ca${ax}Done
Ca${ax}Neg:
 CMP #$FF
 BNE Ca${ax}Dn
 LDA Z_T2
 CMP #256-CAM_SPEED
 BCS Ca${ax}Snap
Ca${ax}Dn:
 SEC
 LDA CAM${ax}
 SBC #CAM_SPEED
 STA CAM${ax}
 LDA CAM${ax}+1
 SBC #$00
 STA CAM${ax}+1
 JMP Ca${ax}Done
Ca${ax}Snap:
 LDA Z_T0
 STA CAM${ax}
 LDA Z_T1
 STA CAM${ax}+1
Ca${ax}Done:`;
}
void 0;

// the unrolled copy: 22 rows from the map row pointers, column by column
function redraw(name, base) {
  const body = [];
  for (let r = 0; r < 21; r++) body.push(` LDA (Z_RP${r}),Y\n STA ${base}+${r * 40},Y`);
  return `${name}:
 LDY #39
${name}L:
${body.join('\n')}
 DEY
 BMI ${name}X
 JMP ${name}L
${name}X:
 RTS`;
}

export const SCROLL = `
// CAMERA: follow the marine; when the char cell changes, the back screen
// is redrawn from the map and shown at the next frame (with the new fine
// scroll), so scrolling never tears.
CameraSnap:
 LDA #$01
 STA Z_K
 JMP CamGo
Camera:
 LDA #$00
 STA Z_K
CamGo:
${camAxis('X', 'PX', 152, 'CAMX_MAX', 'CAMX_MAX_LO', 'CAMX_MAX_HI')}
${camAxis('Y', 'PY', 84, 'CAMY_MAX', 'CAMY_MAX_LO', 'CAMY_MAX_HI')}
 LDA CAMX
 STA Z_T0
 LDA CAMX+1
 JSR Pix2C
 STA NCX
 LDA CAMY
 STA Z_T0
 LDA CAMY+1
 JSR Pix2C
 STA NCY
 LDA FORCE_RD
 BNE CmRedraw
 LDA NCX
 CMP DISP_CX
 BNE CmRedraw
 LDA NCY
 CMP DISP_CY
 BEQ CmFine
CmRedraw:
 LDA #$00
 STA FORCE_RD
 LDA NCX
 STA DISP_CX
 LDA NCY
 STA DISP_CY
 JSR RowPtrs
 LDA CUR_SCR
 EOR #$01
 STA CUR_SCR
 BEQ CmA
 JSR RedrawB
 JMP CmFine
CmA:
 JSR RedrawA
CmFine:
 LDA CUR_SCR
 BEQ CmDa
 LDA #D018_B
 JMP CmDs
CmDa:
 LDA #D018_A
CmDs:
 STA NEW_D018
 LDA CAMX
 AND #$07
 EOR #$17
 STA NEW_D016
 LDA CAMY
 AND #$07
 EOR #$17
 STA NEW_D011
 RTS

// Z_RP0-21 = MAP + (DISP_CY + r) * 128 + DISP_CX
RowPtrs:
 LDX DISP_CX
 LDY DISP_CY
 JSR MapPtr
 LDA Z_MP
 LDY Z_MPH
 LDX #$00
RpLoop:
 STA Z_RP,X
 STY Z_RP+1,X
 CLC
 ADC #$80
 BCC RpNc
 INY
RpNc:
 INX
 INX
 CPX #PFROWS*2
 BNE RpLoop
 RTS

${redraw('RedrawA', 'SCRA')}

${redraw('RedrawB', 'SCRB')}
`;

export const SPRITES = `
// SPRITES: world positions to the sprite shadow the frame IRQ applies.
// 0 = marine, 1-2 = bullets, 3-7 = aliens.
BuildSprites:
 LDA #$00
 STA SH_EN
 STA SH_MSB
 LDA PX
 STA Z_SX
 LDA PX+1
 STA Z_SXH
 LDA PY
 STA Z_SY
 LDA PY+1
 STA Z_SYH
 LDA P_DEAD
 BEQ BsAlive
 SEC
 LDA #DEATH_FRAMES
 SBC GTIMER
 LSR A
 LSR A
 LSR A
 CMP #$04
 BCS BsP
 CLC
 ADC #SPR_BOOM
 LDY #$08
 JMP BsPlace
BsAlive:
 LDA P_INV
 AND #$04
 BNE BsP
// the 3 frames after a shot: the recoil frame for this direction
 LDA FIRE_CD
 CMP #FIRE_RATE-2
 BCC BsWalk
 LDA P_DIR
 CLC
 ADC #SPR_RECOIL
 JMP BsMar
BsWalk:
 LDA P_DIR
 ASL A
 ORA P_ANIM
 CLC
 ADC #SPR_MARINE
BsMar:
 LDY #MARINE_COL
BsPlace:
 LDX #$00
 JSR PlaceSprite
BsP:
 LDX #$00
BsAct:
 STX Z_J
 LDA AST,X
 BEQ BsSkip
 LDA AXL,X
 STA Z_SX
 LDA AXH,X
 STA Z_SXH
 LDA AYL,X
 STA Z_SY
 LDA AYH,X
 STA Z_SYH
 CPX #NBUL
 BCS BsAlien
 LDY #BULLET_COL
 LDA ATM,X
 CMP #BULLET_LIFE-2
 BCC BsShot
 LDA #SPR_FLASH
 JMP BsPut
BsShot:
 LDA ADIR,X
 CLC
 ADC #SPR_BULLET
 JMP BsPut
BsAlien:
 LDA AST,X
 CMP #AS_SPAWN
 BNE BsNs
 SEC
 LDA #SPAWN_FRAMES
 SBC ATM,X
 LSR A
 LSR A
 LSR A
// climbing out of the vent: the explosion frames backwards
 EOR #$03
 CLC
 ADC #SPR_BOOM
 LDY #GOO_COL
 JMP BsPut
BsNs:
 CMP #AS_DIE
 BNE BsLive
 SEC
 LDA #DIE_FRAMES
 SBC ATM,X
 LSR A
 LSR A
 CLC
 ADC #SPR_BOOM
 LDY #BOOM_COL
 JMP BsPut
BsLive:
 LDA ADIR,X
 ASL A
 STA Z_T0
 LDA FRAMECNT
 LSR A
 LSR A
 LSR A
 AND #$01
 ORA Z_T0
 CLC
 ADC #SPR_ALIEN
 LDY ALIEN_COL
 PHA
 LDA ASTK,X
 BEQ BsNf
 LDY #$01
BsNf:
 PLA
BsPut:
 INX
 JSR PlaceSprite
BsSkip:
 LDX Z_J
 INX
 CPX #NACT
 BNE BsAct
 RTS

// sprite X: frame A, colour Y, world centre Z_SX / Z_SY
PlaceSprite:
 CLC
 ADC #SPR_PTR0
 STA SH_PTR,X
 TYA
 STA SH_COL,X
 SEC
 LDA Z_SX
 SBC CAMX
 STA Z_T0
 LDA Z_SXH
 SBC CAMX+1
 STA Z_T1
 CLC
 LDA Z_T0
 ADC #SPR_DX
 STA Z_T0
 LDA Z_T1
 ADC #$00
 BMI PsOff
 CMP #$02
 BCS PsOff
 CMP #$01
 BNE PsXl
 LDA Z_T0
 CMP #88
 BCS PsOff
 LDA SH_MSB
 ORA SprBit,X
 STA SH_MSB
PsXl:
 LDA Z_T0
 STA SH_X,X
 SEC
 LDA Z_SY
 SBC CAMY
 STA Z_T0
 LDA Z_SYH
 SBC CAMY+1
 STA Z_T1
 CLC
 LDA Z_T0
 ADC #SPR_DY
 STA Z_T0
 LDA Z_T1
 ADC #$00
 BNE PsOffY
 LDA Z_T0
 CMP #SPR_YMAX
 BCS PsOffY
 STA SH_Y,X
 LDA SH_EN
 ORA SprBit,X
 STA SH_EN
 RTS
PsOffY:
 LDA SH_MSB
 AND SprMask,X
 STA SH_MSB
PsOff:
 RTS
SprBit:
 .byte $01,$02,$04,$08,$10,$20,$40,$80
SprMask:
 .byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F
`;

export const HUD = `
// HUD rows 22-24 (both screens): template from HUD_TPL / HUD_TCOL, then
// only the values that changed (HUD_DIRTY bits) are written.
HudInit:
 LDX #119
HiLoop:
 LDA HUD_TPL,X
 STA HUDA,X
 STA HUDB,X
 LDA HUD_TCOL,X
 STA HUDC,X
 DEX
 BPL HiLoop
 LDA #$FF
 STA HUD_DIRTY
 RTS

HudUpdate:
 LDA MSG_T
 BEQ HuNoT
 DEC MSG_T
 BNE HuNoT
 JSR DefaultMsg
HuNoT:
 LDA HUD_DIRTY
 AND #HD_TIMER
 BEQ HuNoTm
 LDA MSG_T
 BNE HuNoTm
 JSR TimerMsg
HuNoTm:
 LDA HUD_DIRTY
 BNE HuGo
 RTS
HuGo:
 LSR HUD_DIRTY
 BCC HuNe
 JSR HudEnergy
HuNe:
 LSR HUD_DIRTY
 BCC HuNl
 LDY #HUD_O_LIVES
 LDA LIVES
 JSR HudDigit
HuNl:
 LSR HUD_DIRTY
 BCC HuNa
 LDY #HUD_O_AMMO
 LDA AMMOH
 JSR HudDigit
 LDA AMMOL
 JSR HudBcd
HuNa:
 LSR HUD_DIRTY
 BCC HuNk
 LDY #HUD_O_KEYS
 LDA KEYS
 JSR HudDigit
HuNk:
 LSR HUD_DIRTY
 BCC HuNc
 LDY #HUD_O_CREDITS
 LDA CREDITS+2
 JSR HudBcd
 LDA CREDITS+1
 JSR HudBcd
 LDA CREDITS
 JSR HudBcd
HuNc:
 LSR HUD_DIRTY
 BCC HuNs
 LDY #HUD_O_SCORE
 LDA SCORE+2
 JSR HudBcd
 LDA SCORE+1
 JSR HudBcd
 LDA SCORE
 JSR HudBcd
HuNs:
 LSR HUD_DIRTY
 BCC HuNm
 LDX #$00
 LDY #HUD_O_MSG
HuMsg:
 LDA MSG_BUF,X
 STA HUDA,Y
 STA HUDB,Y
 INY
 INX
 CPX #MSG_LEN
 BNE HuMsg
HuNm:
 LDA #$00
 STA HUD_DIRTY
 RTS

// A = 0-9 at offset Y (Y moves on)
HudDigit:
 AND #$0F
 ORA #$30
 STA HUDA,Y
 STA HUDB,Y
 INY
 RTS
// A = two BCD digits at offset Y
HudBcd:
 PHA
 LSR A
 LSR A
 LSR A
 LSR A
 JSR HudDigit
 PLA
 JMP HudDigit

// 8 bar chars, 8 energy each; green / yellow / red
HudEnergy:
 LDA ENERGY
 STA Z_T0
 LDY #HUD_O_ENERGY
 LDX #$08
HeLoop:
 LDA Z_T0
 CMP #$08
 BCC HePart
 SEC
 SBC #$08
 STA Z_T0
 LDA #$08
 JMP HePut
HePart:
 PHA
 LDA #$00
 STA Z_T0
 PLA
HePut:
 CLC
 ADC #$01
 STA HUDA,Y
 STA HUDB,Y
 INY
 DEX
 BNE HeLoop
 LDA ENERGY
 LDX #$05
 CMP #32
 BCS HeCol
 LDX #$07
 CMP #16
 BCS HeCol
 LDX #$02
HeCol:
 TXA
 LDY #HUD_O_ENERGY+7
HeC:
 STA HUDC,Y
 DEY
 CPY #HUD_O_ENERGY-1
 BNE HeC
 RTS

// a message for MSG_TIME frames: A = lo, X = hi of MSG_LEN chars
SetMsg:
 STA Z_PTR
 STX Z_PTRH
 LDY #MSG_LEN-1
SmLoop:
 LDA (Z_PTR),Y
 STA MSG_BUF,Y
 DEY
 BPL SmLoop
 LDA #MSG_TIME
 STA MSG_T
 LDA HUD_DIRTY
 ORA #HD_MSG
 STA HUD_DIRTY
 RTS
// the standing message: the deck goal, or the self-destruct clock
DefaultMsg:
 LDA SD_ON
 BNE TimerMsg
 LDA LEVEL
 BNE DmD2
 LDA #<TX_GOAL1
 LDX #>TX_GOAL1
 JMP DmSet
DmD2:
 LDA CORES
 BNE DmD2c
 LDA #<TX_GOAL3
 LDX #>TX_GOAL3
 JMP DmSet
DmD2c:
 LDA #<TX_GOAL2
 LDX #>TX_GOAL2
DmSet:
 JSR SetMsg
 LDA #$00
 STA MSG_T
 RTS
TimerMsg:
 LDA SD_ON
 BEQ TmOut
 LDA #<TX_MSG_TIMER
 LDX #>TX_MSG_TIMER
 JSR DmSet
 LDA SD_MIN
 AND #$0F
 ORA #$30
 STA MSG_BUF+TIMER_O
 LDA SD_SEC
 LSR A
 LSR A
 LSR A
 LSR A
 ORA #$30
 STA MSG_BUF+TIMER_O+2
 LDA SD_SEC
 AND #$0F
 ORA #$30
 STA MSG_BUF+TIMER_O+3
TmOut:
 RTS
`;

export const PAGES = `
// TEXT: a string is row, col, colour, chars..., 0
// PrintDirect: string Z_PTR onto the screen whose high byte is Z_T7, colour RAM too
PrintDirect:
 LDY #$00
 LDA (Z_PTR),Y
 TAX
 INY
 LDA (Z_PTR),Y
 CLC
 ADC Row40L,X
 STA Z_SP
 STA Z_PTR2
 LDA Row40H,X
 ADC #$00
 STA Z_T6
 ADC Z_T7
 STA Z_SPH
 LDA Z_T6
 ADC #$D8
 STA Z_PTR2H
 INY
 LDA (Z_PTR),Y
 STA Z_T5
 CPX #PFROWS
 BCS PdNoRow
 STA ROWCOL,X
PdNoRow:
 CLC
 LDA Z_PTR
 ADC #$03
 STA Z_PTR
 BCC PdNc
 INC Z_PTRH
PdNc:
 LDY #$00
PdLoop:
 LDA (Z_PTR),Y
 BEQ PdOut
 STA (Z_SP),Y
 LDA Z_T5
 STA (Z_PTR2),Y
 INY
 BNE PdLoop
PdOut:
 RTS

// ShowPage: page table A/X (string lo, hi pairs, 0 0) onto the back screen,
// screen goes black, flips at the next frame, then the row colours
ShowPage:
 STA Z_DX
 STX Z_DXH
 LDA #$00
 STA SH_EN
 JSR SetAllRowCol
 LDA CUR_SCR
 EOR #$01
 STA CUR_SCR
 BEQ SpA
 LDA #$44
 JMP SpB
SpA:
 LDA #$40
SpB:
 STA Z_T7
 STA Z_SPH
 LDA #$00
 STA Z_SP
 LDA #$20
 LDX #$03
 LDY #$00
SpClr:
 STA (Z_SP),Y
 INY
 BNE SpClr
 INC Z_SPH
 DEX
 BNE SpClr
 LDY #840-769
SpCl3:
 STA (Z_SP),Y
 DEY
 BPL SpCl3
 LDY #$00
SpStr:
 STY Z_J
 LDA (Z_DX),Y
 STA Z_PTR
 INY
 LDA (Z_DX),Y
 STA Z_PTRH
 ORA Z_PTR
 BEQ SpDone
 LDA Z_T7
 PHA
 JSR PrintNoCol
 PLA
 STA Z_T7
 LDY Z_J
 INY
 INY
 JMP SpStr
SpDone:
 LDA CUR_SCR
 BEQ SpDa
 LDA #D018_B
 JMP SpDs
SpDa:
 LDA #D018_A
SpDs:
 STA NEW_D018
 LDA #$17
 STA NEW_D011
 STA NEW_D016
 LDA #$01
 STA COL_REQ
 RTS
// like PrintDirect, but the colour only goes to ROWCOL (applied later)
PrintNoCol:
 LDY #$00
 LDA (Z_PTR),Y
 TAX
 INY
 LDA (Z_PTR),Y
 CLC
 ADC Row40L,X
 STA Z_SP
 LDA Row40H,X
 ADC Z_T7
 STA Z_SPH
 INY
 LDA (Z_PTR),Y
 STA ROWCOL,X
 CLC
 LDA Z_PTR
 ADC #$03
 STA Z_PTR
 BCC PnNc
 INC Z_PTRH
PnNc:
 LDY #$00
PnLoop:
 LDA (Z_PTR),Y
 BEQ PnOut
 STA (Z_SP),Y
 INY
 BNE PnLoop
PnOut:
 RTS

// the shown screen's high byte in Z_T7
ShownHi:
 LDA CUR_SCR
 BEQ ShA
 LDA #$44
 STA Z_T7
 RTS
ShA:
 LDA #$40
 STA Z_T7
 RTS

// DECK COMPLETE / VICTORY / GAME OVER
DeckDone:
 LDA #$00
 STA SD_ON
 STA NEW_D020
 LDA #$20
 JSR AddScore
 LDA LEVEL
 CMP #DECKS-1
 BEQ DdWin
 LDA #GS_DONE
 STA GSTATE
 LDA #<PG_DONE
 LDX #>PG_DONE
 JMP DdShow
DdWin:
 LDA #GS_WIN
 STA GSTATE
 LDA #<PG_WIN
 LDX #>PG_WIN
DdShow:
 JSR ShowPage
 LDA #PAGE_WAIT
 STA GTIMER
 LDA #S_KEY
 JMP PlaySfx
GameOver:
 LDA #$00
 STA SD_ON
 STA NEW_D020
 LDA #GS_OVER
 STA GSTATE
 LDA DEAD_CAUSE
 BNE GoBoom
 LDA #<PG_OVER0
 LDX #>PG_OVER0
 JMP GoShow
GoBoom:
 LDA #<PG_OVER1
 LDX #>PG_OVER1
GoShow:
 JSR ShowPage
 LDA #PAGE_WAIT
 STA GTIMER
 LDA #S_EXPLODE
 JMP PlaySfx

// waiting on a page: the score is drawn live, fire moves on
PageFrame:
 JSR ShownHi
 LDA #<PAGE_SCORE_AT
 STA Z_SP
 CLC
 LDA #>PAGE_SCORE_AT
 ADC Z_T7
 STA Z_SPH
 LDY #$00
 LDX #$02
PfDig:
 LDA SCORE,X
 LSR A
 LSR A
 LSR A
 LSR A
 ORA #$30
 STA (Z_SP),Y
 INY
 LDA SCORE,X
 AND #$0F
 ORA #$30
 STA (Z_SP),Y
 INY
 DEX
 BPL PfDig
 LDA GTIMER
 BEQ PfFire
 DEC GTIMER
 RTS
PfFire:
 LDA JOYNEW
 AND #$10
 BNE PgGo
 RTS
PgGo:
 LDA GSTATE
 CMP #GS_DONE
 BNE PfTitle
 INC LEVEL
 JMP StartDeck
PfTitle:
 JMP Title
`;

export const INTEX = `
// INTEX NETWORK TERMINAL: spend credits on ammo, first aid, keys and lives.
// The game stops while the terminal is open, as on the Amiga.
EnterIntex:
 LDA #GS_INTEX
 STA GSTATE
 LDA #$00
 STA MENU_I
 LDA #S_INTEX_VOICE
 JSR PlaySfx
 JSR HumOn
 LDA #<PG_INTEX
 LDX #>PG_INTEX
 JMP ShowPage

IntexFrame:
 JSR HumTick
 LDA JOYNEW
 AND #$01
 BEQ IfNu
 JSR IntexBleep
 DEC MENU_I
 BPL IfNu
 LDA #INTEX_ITEMS-1
 STA MENU_I
IfNu:
 LDA JOYNEW
 AND #$02
 BEQ IfNd
 JSR IntexBleep
 INC MENU_I
 LDA MENU_I
 CMP #INTEX_ITEMS
 BCC IfNd
 LDA #$00
 STA MENU_I
IfNd:
 JSR ShownHi
 LDX #$00
IfRow:
 STX Z_J
 LDA IntexRow,X
 TAY
 LDA Row40L,Y
 STA Z_SP
 STA Z_PTR2
 LDA Row40H,Y
 PHA
 CLC
 ADC Z_T7
 STA Z_SPH
 PLA
 CLC
 ADC #$D8
 STA Z_PTR2H
 LDA #$20
 CPX MENU_I
 BNE IfNoCur
 LDA #$3E
IfNoCur:
 LDY #INTEX_CURSOR_COL
 STA (Z_SP),Y
 LDA #INTEX_COL
 CPX MENU_I
 BNE IfCol
 LDA #INTEX_SEL_COL
IfCol:
 LDY #37
IfColL:
 STA (Z_PTR2),Y
 DEY
 BPL IfColL
 LDX Z_J
 INX
 CPX #INTEX_ITEMS
 BNE IfRow
 LDA #<INTEX_CRED_AT
 STA Z_SP
 CLC
 LDA #>INTEX_CRED_AT
 ADC Z_T7
 STA Z_SPH
 LDY #$00
 LDX #$02
IfCr:
 LDA CREDITS,X
 LSR A
 LSR A
 LSR A
 LSR A
 ORA #$30
 STA (Z_SP),Y
 INY
 LDA CREDITS,X
 AND #$0F
 ORA #$30
 STA (Z_SP),Y
 INY
 DEX
 BPL IfCr
 JSR HudUpdate
 LDA JOYNEW
 AND #$10
 BNE IfFire
 RTS
IfFire:
 LDX MENU_I
 CPX #INTEX_ITEMS-1
 BNE IfBuy
 JMP ExitIntex
IfBuy:
 LDA CREDITS+2
 CMP PriceH,X
 BCC IfPoor
 BNE IfRich
 LDA CREDITS+1
 CMP PriceM,X
 BCC IfPoor
IfRich:
 SED
 SEC
 LDA CREDITS+1
 SBC PriceM,X
 STA CREDITS+1
 LDA CREDITS+2
 SBC PriceH,X
 STA CREDITS+2
 CLD
 LDA HUD_DIRTY
 ORA #HD_CREDITS
 STA HUD_DIRTY
 TXA
 BNE IfB1
 JSR AddAmmo
 LDA #S_CLIP
 JSR PlaySfx
 JMP IfSoldMsg
IfB1:
 CMP #$01
 BNE IfB2
 JSR AddEnergy
 JMP IfSold
IfB2:
 CMP #$02
 BNE IfB3
 LDA KEYS
 CMP #$09
 BCS IfSold
 INC KEYS
 LDA HUD_DIRTY
 ORA #HD_KEYS
 STA HUD_DIRTY
 JMP IfSold
IfB3:
 LDA LIVES
 CMP #$09
 BCS IfSold
 INC LIVES
 LDA HUD_DIRTY
 ORA #HD_LIVES
 STA HUD_DIRTY
IfSold:
 LDA #S_TERMINAL
 JSR PlaySfx
IfSoldMsg:
 LDA #<TX_INT_OK
 LDX #>TX_INT_OK
 JMP IfStatus
IfPoor:
 LDA #S_HURT
 JSR PlaySfx
 LDA #<TX_INT_POOR
 LDX #>TX_INT_POOR
IfStatus:
 STA Z_PTR
 STX Z_PTRH
 JMP PrintDirect

ExitIntex:
 JSR HumOff
 LDA #GS_PLAY
 STA GSTATE
 LDA #$00
 JSR SetAllRowCol
 LDA GAME_COL
 LDX #PFROWS-1
ExCol:
 STA ROWCOL,X
 DEX
 BPL ExCol
 LDA #$02
 STA COL_REQ
 LDA #$01
 STA FORCE_RD
 LDA #RESPAWN_SAFE
 STA P_INV
 JMP Camera

// THE MAINFRAME: SID voice 1 whirs while the terminal is open - a low
// pulse whose pitch wobbles and whose width sweeps, like a fan - and voice
// 2 bleeps when the selection moves (the effects keep voice 3). A sample
// (the Intex voice, the ammo clip) drives $D418, so the hum rests while
// one plays and the volume is put back after it.
HumOn:
 LDA #$00
 STA HUM_LFO
 STA HUM_BLP
 STA $D402
 LDA #$80
 STA $D405
 LDA #$58
 STA $D406
 LDA #$00
 STA $D40C
 LDA #$A0
 STA $D40D
 LDA #$01
 STA HUM_WAS
 RTS
// once a frame while the terminal is open
HumTick:
 INC HUM_LFO
 LDA HUM_LFO
 AND #$3F
 CMP #$20
 BCC HtUp
 EOR #$3F
HtUp:
 ASL A
 ASL A
 STA $D400
 LDA #$07
 STA $D401
 LDA HUM_LFO
 LSR A
 LSR A
 LSR A
 AND #$07
 ORA #$04
 STA $D403
 LDA A_ON
 BEQ HtOn
 LDA #$40
 STA $D404
 LDA #$01
 STA HUM_WAS
 JMP HtBlp
HtOn:
 LDA HUM_WAS
 BEQ HtGate
 LDA #$00
 STA HUM_WAS
 LDA #$0F
 STA $D418
HtGate:
 LDA #$41
 STA $D404
HtBlp:
 LDA HUM_BLP
 BEQ HtOut
 DEC HUM_BLP
 BNE HtOut
 LDA #$10
 STA $D40B
HtOut:
 RTS
// the selection moved: a short high blip on voice 2
IntexBleep:
 LDA #$D0
 STA $D407
 LDA #$84
 STA $D408
 LDA #$10
 STA $D40B
 LDA #$11
 STA $D40B
 LDA #$03
 STA HUM_BLP
 RTS
HumOff:
 LDA #$40
 STA $D404
 LDA #$10
 STA $D40B
 RTS

IntexRow:
 .byte ${'{{INTEX_ROWS}}'}
// prices in credits / 100 (BCD): ammo 1000, first aid 1500, key 2500, life 10000
PriceM:
 .byte $10,$15,$25,$00
PriceH:
 .byte $00,$00,$00,$01
`;
