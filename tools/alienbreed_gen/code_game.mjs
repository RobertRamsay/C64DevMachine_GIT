// ALIEN BREED 64 - game code blocks: title, deck load, the frame loop and
// game states, the marine, bullets, aliens, pickups, doors, reactor cores
// and the self-destruct.

export const TITLE = `
// TITLE: the Koala picture (bank 3) with sprite text in the logo's font.
// Top band: C64 | C64U - LEFT picks the stock C64 (SID music + SFX), RIGHT
// the C64 Ultimate / REU version (streamed audio, only with an REU).
// Bottom band: PRESS FIRE | TO PLAY.
Title:
 SEI
 LDX #$FF
 TXS
 LDA #$00
 STA GSTATE
 STA SH_EN
 STA CUR_EN
 STA $D015
 STA CUR_D020
 STA NEW_D020
 LDA #$01
 STA TITLE_ON
 LDX #$00
TiCopy:
 LDA TITLE_STORE,X
 STA TITLE_VSCR,X
 LDA TITLE_STORE+250,X
 STA TITLE_VSCR+250,X
 LDA TITLE_STORE+500,X
 STA TITLE_VSCR+500,X
 LDA TITLE_STORE+750,X
 STA TITLE_VSCR+750,X
 LDA TITLE_STORE+1000,X
 STA $D800,X
 LDA TITLE_STORE+1250,X
 STA $D8FA,X
 LDA TITLE_STORE+1500,X
 STA $D9F4,X
 LDA TITLE_STORE+1750,X
 STA $DAEE,X
 INX
 CPX #250
 BNE TiCopy
 LDX #$00
TiSpr:
 LDA AB_TITLE_SPR,X
 STA TITLE_VSPR,X
 LDA AB_TITLE_SPR+256,X
 STA TITLE_VSPR+256,X
 LDA AB_TITLE_SPR+512,X
 STA TITLE_VSPR+512,X
 LDA AB_TITLE_SPR+768,X
 STA TITLE_VSPR+768,X
 INX
 BNE TiSpr
 LDA #TITLE_BG
 STA $D021
 LDA #TSPR_MC1
 STA $D025
 LDA #TSPR_MC2
 STA $D026
 LDA #$FF
 STA $D01C
 STA $D017
 LDA #$00
 STA $D01D
 STA $D01B
 LDA #$3B
 STA NEW_D011
 LDA #$18
 STA NEW_D016
 LDA #D018_T
 STA NEW_D018
 LDA #BANK_TITLE
 STA NEW_BANK
 LDA #TSPR_IND
 STA TCOL
 JSR TiSprites
 CLI
 JSR Commit
 JSR MusicStartAny
 LDA #$00
 STA TITLE_T
TiLoop:
 JSR ReadJoy
 INC TITLE_T
 LDA TITLE_T
 LSR A
 LSR A
 LSR A
 AND #$07
 TAX
 LDA FlashCol,X
 STA TCOL
 LDA JOYNEW
 AND #$04
 BEQ TiNoL
 LDA AUDIO_MODE
 BEQ TiNoL
 LDA #$00
 STA AUDIO_MODE
 JSR TiSwitch
TiNoL:
 LDA JOYNEW
 AND #$08
 BEQ TiNoR
 LDA REU_OK
 BEQ TiNoR
 LDA AUDIO_MODE
 BNE TiNoR
 LDA #$01
 STA AUDIO_MODE
 JSR TiSwitch
TiNoR:
 LDA JOYNEW
 AND #$10
 BNE TiStart
 JSR TiSprites
 JSR Commit
 JMP TiLoop
// leave with the screen blanked while the deck loads
TiStart:
 LDA #$00
 STA SH_EN
 LDA #$0B
 STA NEW_D011
 JSR Commit
 LDA #$00
 STA TITLE_ON
 LDA #BANK_GAME
 STA NEW_BANK
 JMP NewGame
TiSwitch:
 JSR MusicStopAll
 JMP MusicStartAny
// the logo's colours, top to bottom, for PRESS FIRE
FlashCol:
 .byte 6,6,14,14,1,1,14,14

// upper band: C64 (sprites 0-1) and C64U (2-3); the version in use is
// shaded, the other one flat dark grey
TiSprites:
 LDX #$03
TsSet:
 LDA TTopX,X
 STA SH_X,X
 LDA #TTOP_Y
 STA SH_Y,X
 DEX
 BPL TsSet
 LDA #TTOP_MSB
 STA SH_MSB
 LDA #$0F
 STA SH_EN
 LDA AUDIO_MODE
 BNE TsU
 LDA #TF_C64
 LDX #TF_C64UD
 JMP TsPut
TsU:
 LDA #TF_C64D
 LDX #TF_C64U
TsPut:
 STA SH_PTR
 CLC
 ADC #$01
 STA SH_PTR+1
 TXA
 STA SH_PTR+2
 CLC
 ADC #$01
 STA SH_PTR+3
 LDA AUDIO_MODE
 BNE TsCu
 LDA #TSPR_IND
 STA SH_COL
 STA SH_COL+1
 LDA #TSPR_DIM
 STA SH_COL+2
 STA SH_COL+3
 RTS
TsCu:
 LDA #TSPR_DIM
 STA SH_COL
 STA SH_COL+1
 LDA #TSPR_IND
 STA SH_COL+2
 STA SH_COL+3
 RTS
TTopX:
 .byte {{TTOP_X}}
`;

export const STATES = `
// NEW GAME / START DECK
NewGame:
 JSR MusicStopAll
 LDA #$03
 STA LIVES
 LDA #$00
 STA LEVEL
 STA KEYS
 STA SCORE
 STA SCORE+1
 STA SCORE+2
 STA CREDITS
 STA CREDITS+1
 STA CREDITS+2
 LDA #START_AMMO_L
 STA AMMOL
 LDA #START_AMMO_H
 STA AMMOH
StartDeck:
 SEI
 LDX #$FF
 TXS
// the game's sprite set-up (the title changes it)
 LDA #$00
 STA $D025
 STA $D017
 LDA #$0F
 STA $D026
 LDA #$F9
 STA $D01C
 LDA #$00
 STA SH_EN
 STA CUR_EN
 STA $D015
 CLI
 LDA #$00
 JSR SetAllRowCol
 JSR LoadDeck
 JSR GameSoundOn
 LDA #ENERGY_MAX
 STA ENERGY
 LDA #$00
 STA SD_ON
 STA NEW_D020
 STA TERM_LOCK
 STA MSG_T
 STA P_DEAD
 LDA #$01
 STA SPAWN_T
 JSR Respawn
 JSR HudInit
 JSR DefaultMsg
 LDA LEVEL
 BNE SdMsg2
 LDA #<TX_MSG_D1
 LDX #>TX_MSG_D1
 JMP SdMsg
SdMsg2:
 LDA #<TX_MSG_D2
 LDX #>TX_MSG_D2
SdMsg:
 JSR SetMsg
 LDA GAME_COL
 JSR SetAllRowCol
 LDA #GS_PLAY
 STA GSTATE

// THE FRAME LOOP: one pass per frame, committed at the end
GameLoop:
 JSR ReadJoy
 LDA GSTATE
 CMP #GS_PLAY
 BNE GlNp
 JSR PlayFrame
 JMP GlChk
GlNp:
 CMP #GS_DEAD
 BNE GlNd
 JSR DeadFrame
GlChk:
 LDA GSTATE
 CMP #GS_INTEX
 BCS GlCommit
 JMP GlView
GlNd:
 CMP #GS_INTEX
 BNE GlNi
 JSR IntexFrame
 JMP GlCommit
GlNi:
 JSR PageFrame
 JMP GlCommit
GlView:
 JSR Camera
 JSR BuildSprites
 JSR HudUpdate
GlCommit:
 JSR Commit
 JMP GameLoop

PlayFrame:
 JSR MovePlayer
 LDA GSTATE
 CMP #GS_PLAY
 BEQ PfGo
 RTS
PfGo:
 JSR FireControl
 JSR MoveBullets
 JSR Spawner
 JSR MoveAliens
 JSR SelfDestruct
 LDA P_INV
 BEQ PfInv
 DEC P_INV
PfInv:
 LDA FIRE_CD
 BEQ PfCd
 DEC FIRE_CD
PfCd:
 RTS

// player dead: explosion, then a life or GAME OVER
DeadFrame:
 JSR MoveAliens
 JSR SelfDestruct
 DEC GTIMER
 BNE DfOut
 LDA LIVES
 BEQ DfOver
 DEC LIVES
 LDA HUD_DIRTY
 ORA #HD_LIVES
 STA HUD_DIRTY
 LDA LIVES
 BEQ DfOver
 LDA #ENERGY_MAX
 STA ENERGY
 LDA #$00
 STA P_DEAD
 JSR Respawn
 LDA #GS_PLAY
 STA GSTATE
 LDA HUD_DIRTY
 ORA #HD_ENERGY
 STA HUD_DIRTY
DfOut:
 RTS
DfOver:
 LDA #$00
 STA DEAD_CAUSE
 JMP GameOver

KillPlayer:
 LDA GSTATE
 CMP #GS_PLAY
 BNE KpOut
 LDA #GS_DEAD
 STA GSTATE
 LDA #DEATH_FRAMES
 STA GTIMER
 LDA #$01
 STA P_DEAD
 LDA #S_EXPLODE
 JSR PlaySfx
 LDA #<TX_MSG_DEAD
 LDX #>TX_MSG_DEAD
 JSR SetMsg
KpOut:
 RTS

// back to the deck start: aliens and bullets gone, safe for a while
Respawn:
 LDA START_X
 STA PX
 LDA START_XH
 STA PX+1
 LDA START_Y
 STA PY
 LDA START_YH
 STA PY+1
 LDA #$04
 STA P_DIR
 LDA #RESPAWN_SAFE
 STA P_INV
 LDX #NACT-1
RsClr:
 LDA #AS_FREE
 STA AST,X
 DEX
 BPL RsClr
 LDA #$01
 STA FORCE_RD
 JMP CameraSnap

// LOAD DECK: the deck's map of stamp ids (AB_DECKS) into the 128 x 96 char
// map at $A000 - void everywhere, then the cropped map at its place, one
// 2 x 2 char stamp per id; read the deck table (start, vents, cores,
// colours, alien settings)
LoadDeck:
 LDX LEVEL
 LDA DeckMapL,X
 STA Z_PTR
 LDA DeckMapH,X
 STA Z_PTRH
 LDA DeckTabL,X
 STA Z_PTR2
 LDA DeckTabH,X
 STA Z_PTR2H
 LDA #$00
 STA Z_MP
 LDA #$A0
 STA Z_MPH
 LDY #$00
 LDA #CH_VOID
LdFill:
 STA (Z_MP),Y
 INY
 BNE LdFill
 INC Z_MPH
 LDX Z_MPH
 CPX #$D0
 BNE LdFill
 LDY #DT_MY
 LDA (Z_PTR2),Y
 CLC
 ADC #$A0
 STA Z_MPH
 LDY #DT_MH
 LDA (Z_PTR2),Y
 STA Z_J
LdRow:
 LDY #DT_MX
 LDA (Z_PTR2),Y
 ASL A
 STA Z_MP
 LDY #DT_MW
 LDA (Z_PTR2),Y
 STA Z_I
LdCell:
 LDY #$00
 LDA (Z_PTR),Y
 JSR LdInc
 ASL A
 ASL A
 TAX
 LDA META_TL,X
 STA (Z_MP),Y
 INY
 LDA META_TR,X
 STA (Z_MP),Y
 LDY #$80
 LDA META_BL,X
 STA (Z_MP),Y
 INY
 LDA META_BR,X
 STA (Z_MP),Y
 INC Z_MP
 INC Z_MP
 DEC Z_I
 BNE LdCell
 INC Z_MPH
 DEC Z_J
 BNE LdRow
 JMP LdDone
LdInc:
 INC Z_PTR
 BNE LdIo
 INC Z_PTRH
LdIo:
 LDY #$00
 RTS
LdDone:
 LDY #DT_PX
 LDA (Z_PTR2),Y
 STA START_X
 INY
 LDA (Z_PTR2),Y
 STA START_XH
 INY
 LDA (Z_PTR2),Y
 STA START_Y
 INY
 LDA (Z_PTR2),Y
 STA START_YH
 INY
 LDA (Z_PTR2),Y
 STA NVENTS
 INY
 LDA (Z_PTR2),Y
 STA NCORES
 STA CORES
 INY
 LDA (Z_PTR2),Y
 ORA #$08
 STA GAME_COL
 INY
 LDA (Z_PTR2),Y
 STA ALIEN_COL
 INY
 LDA (Z_PTR2),Y
 STA ALIEN_HP
 INY
 LDA (Z_PTR2),Y
 STA SPAWN_RATE
 INY
 LDA (Z_PTR2),Y
 STA ALIEN_SPD
 LDX #$00
 LDY #DT_VX
LdVent:
 LDA (Z_PTR2),Y
 STA VENT_X,X
 INY
 INX
 CPX #32
 BNE LdVent
 LDX #$00
LdVent2:
 LDA (Z_PTR2),Y
 STA VENT_Y,X
 INY
 INX
 CPX #32
 BNE LdVent2
 LDX #$00
LdCore:
 LDA (Z_PTR2),Y
 STA CORE_X,X
 INY
 INX
 CPX #$04
 BNE LdCore
 LDX #$00
LdCore2:
 LDA (Z_PTR2),Y
 STA CORE_Y,X
 LDA #CORE_HITS
 STA CORE_HP,X
 INY
 INX
 CPX #$04
 BNE LdCore2
 LDA #$00
 STA VENT_I
 LDA #$0B
 STA $D022
 LDA #$0F
 STA $D023
 LDA #$00
 STA $D021
 RTS
DeckMapL:
 .byte <DECK_MAP0,<DECK_MAP1
DeckMapH:
 .byte >DECK_MAP0,>DECK_MAP1
DeckTabL:
 .byte <DECK_TAB0,<DECK_TAB1
DeckTabH:
 .byte >DECK_TAB0,>DECK_TAB1

// SELF DESTRUCT: after the last core, a minute and a half to the lift
SelfDestruct:
 LDA SD_ON
 BEQ SdOut
 INC SD_SUB
 LDA SD_SUB
 CMP #10
 BNE SdNf
 LDA #$00
 STA NEW_D020
SdNf:
 LDA SD_SUB
 CMP #50
 BNE SdOut
 LDA #$00
 STA SD_SUB
 LDA #$02
 STA NEW_D020
 LDA HUD_DIRTY
 ORA #HD_TIMER
 STA HUD_DIRTY
 SED
 SEC
 LDA SD_SEC
 SBC #$01
 STA SD_SEC
 BCS SdNb
 LDA #$59
 STA SD_SEC
 SEC
 LDA SD_MIN
 SBC #$01
 STA SD_MIN
SdNb:
 CLD
 LDA SD_SEC
 AND #$03
 BNE SdNa
 LDA #S_ALARM
 JSR PlaySfx
SdNa:
 LDA SD_SEC
 ORA SD_MIN
 BNE SdOut
 LDA #$01
 STA DEAD_CAUSE
 JMP GameOver
SdOut:
 RTS
`;

export const PLAYER = `
// THE MARINE: 8-way, SPEED_FRAC sub-pixel speed, walls stop him per axis.
// Doors open with a key, terminals open the Intex network.
MovePlayer:
 LDA #$00
 STA TOUCH_TERM
 STA P_MOVED
 LDA JOY
 AND #$0F
 TAX
 LDA JoyDir,X
 BMI MpStill
 STA P_DIR
 CLC
 LDA P_ACC
 ADC #SPEED_FRAC
 STA P_ACC
 LDA #SPEED_INT
 ADC #$00
 STA Z_K
MpStep:
 LDA JOY
 AND #$04
 BEQ MpNl
 LDA #$FF
 JSR MpTryX
MpNl:
 LDA JOY
 AND #$08
 BEQ MpNr
 LDA #$01
 JSR MpTryX
MpNr:
 LDA JOY
 AND #$01
 BEQ MpNu
 LDA #$FF
 JSR MpTryY
MpNu:
 LDA JOY
 AND #$02
 BEQ MpNd
 LDA #$01
 JSR MpTryY
MpNd:
 DEC Z_K
 BNE MpStep
 LDA FRAMECNT
 AND #$07
 BNE MpStill
 LDA P_ANIM
 EOR #$01
 STA P_ANIM
MpStill:
 LDA TOUCH_TERM
 BNE MpT
 LDA #$00
 STA TERM_LOCK
MpT:
 JMP Pickups

// try one pixel along X (A = +1 / -1)
MpTryX:
 STA Z_T6
 LDA PY
 STA Z_BY
 LDA PY+1
 STA Z_BYH
 CLC
 LDA PX
 ADC Z_T6
 STA Z_BX
 LDA Z_T6
 BMI MxNeg
 LDA #$00
 JMP MxAdd
MxNeg:
 LDA #$FF
MxAdd:
 ADC PX+1
 STA Z_BXH
 LDA #PBOX
 STA Z_BH
 JSR BoxSolid
 BCS MpBlocked
 LDA Z_BX
 STA PX
 LDA Z_BXH
 STA PX+1
 LDA #$01
 STA P_MOVED
 RTS
MpTryY:
 STA Z_T6
 LDA PX
 STA Z_BX
 LDA PX+1
 STA Z_BXH
 CLC
 LDA PY
 ADC Z_T6
 STA Z_BY
 LDA Z_T6
 BMI MyNeg
 LDA #$00
 JMP MyAdd
MyNeg:
 LDA #$FF
MyAdd:
 ADC PY+1
 STA Z_BYH
 LDA #PBOX
 STA Z_BH
 JSR BoxSolid
 BCS MpBlocked
 LDA Z_BY
 STA PY
 LDA Z_BYH
 STA PY+1
 LDA #$01
 STA P_MOVED
 RTS
// walked into something solid: doors and terminals react
MpBlocked:
 LDA Z_HT
 CMP #T_DOOR
 BEQ MbDoor
 CMP #T_TERM
 BEQ MbTerm
 RTS
MbTerm:
 LDA #$01
 STA TOUCH_TERM
 LDA TERM_LOCK
 BNE MbOut
 LDA #$01
 STA TERM_LOCK
 JMP EnterIntex
MbDoor:
 LDA KEYS
 BEQ MbLocked
 DEC KEYS
 LDA HUD_DIRTY
 ORA #HD_KEYS
 STA HUD_DIRTY
 JSR OpenDoor
 LDA #S_DOOR
 JSR PlaySfx
 LDA #<TX_MSG_OPEN
 LDX #>TX_MSG_OPEN
 JMP SetMsg
MbLocked:
 LDA MSG_T
 BNE MbOut
 LDA #<TX_MSG_LOCKED
 LDX #>TX_MSG_LOCKED
 JMP SetMsg
MbOut:
 RTS

// the door tile at Z_HX, Z_HY and the door tiles in line with it
OpenDoor:
 LDA Z_HX
 AND #$FE
 STA Z_HX
 STA Z_DX
 LDA Z_HY
 AND #$FE
 STA Z_HY
 STA Z_DY
 JSR ClearTile
 LDX #$03
OdDir:
 STX Z_J
 LDA Z_DX
 STA Z_HX
 LDA Z_DY
 STA Z_HY
 LDA #$04
 STA Z_I
OdStep:
 LDX Z_J
 CLC
 LDA Z_HX
 ADC OdX,X
 STA Z_HX
 CLC
 LDA Z_HY
 ADC OdY,X
 STA Z_HY
 LDX Z_HX
 LDY Z_HY
 JSR CharAt
 TAX
 LDA CHAR_TYPES,X
 CMP #T_DOOR
 BNE OdNext
 JSR ClearTile
 DEC Z_I
 BNE OdStep
OdNext:
 LDX Z_J
 DEX
 BPL OdDir
 RTS
OdX:
 .byte $02,$FE,$00,$00
OdY:
 .byte $00,$00,$02,$FE

// what the marine stands on
Pickups:
 LDA PX
 STA Z_BX
 LDA PX+1
 STA Z_BXH
 LDA PY
 STA Z_BY
 LDA PY+1
 STA Z_BYH
 LDA #PBOX
 STA Z_BH
 JSR BoxPickup
 BNE PkGot
 RTS
PkGot:
 CMP #T_EXIT
 BEQ PkExit
 PHA
 JSR ClearTile
 PLA
 CMP #T_KEY
 BNE PkNk
 LDA KEYS
 CMP #$09
 BCS PkK9
 INC KEYS
PkK9:
 LDA HUD_DIRTY
 ORA #HD_KEYS
 STA HUD_DIRTY
 LDA #S_KEY
 JSR PlaySfx
 LDA #<TX_MSG_KEY
 LDX #>TX_MSG_KEY
 JMP SetMsg
PkNk:
 CMP #T_AMMO
 BNE PkNa
 JSR AddAmmo
 LDA #S_CLIP
 JSR PlaySfx
 LDA #<TX_MSG_AMMO
 LDX #>TX_MSG_AMMO
 JMP SetMsg
PkNa:
 CMP #T_MEDKIT
 BNE PkNm
 JSR AddEnergy
 LDA #S_PICKUP
 JSR PlaySfx
 LDA #<TX_MSG_MED
 LDX #>TX_MSG_MED
 JMP SetMsg
PkNm:
 LDA #CREDIT_PICKUP
 JSR AddCredits
 LDA #$01
 JSR AddScore
 LDA #S_PICKUP
 JSR PlaySfx
 LDA #<TX_MSG_CRED
 LDX #>TX_MSG_CRED
 JMP SetMsg
PkExit:
 LDA CORES
 BEQ PkGo
 LDA MSG_T
 BNE PkOut
 LDA #<TX_MSG_LIFTLOCK
 LDX #>TX_MSG_LIFTLOCK
 JMP SetMsg
PkGo:
 JMP DeckDone
PkOut:
 RTS

AddAmmo:
 SED
 CLC
 LDA AMMOL
 ADC #CLIP_ROUNDS
 STA AMMOL
 LDA AMMOH
 ADC #$00
 STA AMMOH
 CLD
 CMP #$10
 BCC AaOk
 LDA #$09
 STA AMMOH
 LDA #$99
 STA AMMOL
AaOk:
 LDA HUD_DIRTY
 ORA #HD_AMMO
 STA HUD_DIRTY
 RTS
AddEnergy:
 CLC
 LDA ENERGY
 ADC #MEDKIT_ENERGY
 CMP #ENERGY_MAX
 BCC AeOk
 LDA #ENERGY_MAX
AeOk:
 STA ENERGY
 LDA HUD_DIRTY
 ORA #HD_ENERGY
 STA HUD_DIRTY
 RTS

// up 1 down 2 left 4 right 8 -> direction 0-7 (0 up, clockwise), $FF none
JoyDir:
 .byte $FF,$00,$04,$FF,$06,$07,$05,$06,$02,$01,$03,$02,$FF,$00,$04,$FF
`;

export const WEAPONS = `
// FIRE: hold fire for a stream of shots (FIRE_RATE frames apart), two on
// screen at once, each costs one round.
FireControl:
 LDA JOY
 AND #$10
 BEQ FcOut
 LDA FIRE_CD
 BNE FcOut
 LDA AMMOL
 ORA AMMOH
 BNE FcAmmo
 LDA JOYNEW
 AND #$10
 BEQ FcOut
 LDA #<TX_MSG_NOAMMO
 LDX #>TX_MSG_NOAMMO
 JMP SetMsg
FcAmmo:
 LDX #$00
 LDA AST,X
 BEQ FcSlot
 INX
 LDA AST,X
 BEQ FcSlot
FcOut:
 RTS
FcSlot:
 LDA #AS_LIVE
 STA AST,X
 LDA #BULLET_LIFE
 STA ATM,X
 LDY P_DIR
 TYA
 STA ADIR,X
 LDA PX
 STA AXL,X
 LDA PX+1
 STA AXH,X
 LDA PY
 STA AYL,X
 LDA PY+1
 STA AYH,X
 LDA #FIRE_RATE
 STA FIRE_CD
 SED
 SEC
 LDA AMMOL
 SBC #$01
 STA AMMOL
 LDA AMMOH
 SBC #$00
 STA AMMOH
 CLD
 LDA HUD_DIRTY
 ORA #HD_AMMO
 STA HUD_DIRTY
 JSR BulletStep
 JSR BulletStep
 LDA #S_GUN
 JMP PlaySfx

MoveBullets:
 LDX #$00
 JSR MbOne
 LDX #$01
MbOne:
 LDA AST,X
 BEQ MbNone
 DEC ATM,X
 BEQ MbKill
// a new shot holds at the muzzle for two frames (the muzzle flash)
 LDA ATM,X
 CMP #BULLET_LIFE-2
 BCS MbNone
 JSR BulletStep
 JSR BulletStep
MbNone:
 RTS
MbKill:
 LDA #AS_FREE
 STA AST,X
 RTS

// one half-step (BULLET_STEP pixels); walls stop it, cores take damage,
// aliens die
BulletStep:
 LDA AST,X
 BEQ BsDone
 LDY ADIR,X
 CLC
 LDA AXL,X
 ADC BulDX,Y
 STA AXL,X
 LDA BulDX,Y
 BMI BsXn
 LDA #$00
 JMP BsXa
BsXn:
 LDA #$FF
BsXa:
 ADC AXH,X
 STA AXH,X
 CLC
 LDA AYL,X
 ADC BulDY,Y
 STA AYL,X
 LDA BulDY,Y
 BMI BsYn
 LDA #$00
 JMP BsYa
BsYn:
 LDA #$FF
BsYa:
 ADC AYH,X
 STA AYH,X
 STX Z_IX
 LDA AXL,X
 STA Z_T0
 LDA AXH,X
 JSR Pix2C
 STA Z_HX
 LDX Z_IX
 LDA AYL,X
 STA Z_T0
 LDA AYH,X
 JSR Pix2C
 STA Z_HY
 TAY
 LDX Z_HX
 JSR CharAt
 TAX
 LDA CHAR_TYPES,X
 LDX Z_IX
 CMP #$80
 BCC BsAir
 CMP #T_CORE
 BNE BsWall
 JSR CoreHit
 LDX Z_IX
BsWall:
 LDA #AS_FREE
 STA AST,X
BsDone:
 RTS
BsAir:
 JMP BulletVsAliens
BulDX:
 .byte $00,$03,$04,$03,$00,$FD,$FC,$FD
BulDY:
 .byte $FC,$FD,$00,$03,$04,$03,$00,$FD

// bullet X against every live alien
BulletVsAliens:
 LDY #NBUL
BaLoop:
 LDA AST,Y
 CMP #AS_LIVE
 BNE BaNext
 SEC
 LDA AXL,X
 SBC AXL,Y
 STA Z_T0
 LDA AXH,X
 SBC AXH,Y
 JSR Near10
 BCC BaNext
 SEC
 LDA AYL,X
 SBC AYL,Y
 STA Z_T0
 LDA AYH,X
 SBC AYH,Y
 JSR Near10
 BCC BaNext
 LDA #AS_FREE
 STA AST,X
 LDA AHP,Y
 SEC
 SBC #$01
 STA AHP,Y
 BNE BaHurt
 JMP AlienDie
BaHurt:
 LDA #$06
 STA ASTK,Y
 RTS
BaNext:
 INY
 CPY #NACT
 BNE BaLoop
 RTS

// C set if the 16-bit difference Z_T0 (lo) / A (hi) is within +-HIT_RANGE
Near10:
 CMP #$00
 BEQ NpPos
 CMP #$FF
 BNE NpNo
 LDA Z_T0
 CMP #256-HIT_RANGE
 RTS
NpPos:
 LDA Z_T0
 CMP #HIT_RANGE
 BCS NpNo
 SEC
 RTS
NpNo:
 CLC
 RTS

// a bullet hit the core tile at Z_HX, Z_HY
CoreHit:
 LDA Z_HX
 AND #$FE
 STA Z_HX
 LDA Z_HY
 AND #$FE
 STA Z_HY
 LDX #$03
ChFind:
 LDA CORE_X,X
 CMP Z_HX
 BNE ChNext
 LDA CORE_Y,X
 CMP Z_HY
 BEQ ChGot
ChNext:
 DEX
 BPL ChFind
 RTS
ChGot:
 LDA CORE_HP,X
 BEQ ChOut
 DEC CORE_HP,X
 BEQ ChDead
 LDA #S_CORE_HIT
 JMP PlaySfx
ChDead:
 LDX Z_HX
 LDY Z_HY
 LDA #CH_DEAD
 JSR PutTile
 LDA #$50
 JSR AddScore
 LDA #S_EXPLODE
 JSR PlaySfx
 DEC CORES
 BNE ChLeft
 LDA #$01
 STA SD_ON
 LDA #SD_START_MIN
 STA SD_MIN
 LDA #SD_START_SEC
 STA SD_SEC
 LDA #$00
 STA SD_SUB
 LDA #S_ALARM
 JSR PlaySfx
 LDA #<TX_MSG_SD
 LDX #>TX_MSG_SD
 JMP SetMsg
ChLeft:
 LDA #<TX_MSG_CORE
 LDX #>TX_MSG_CORE
 JMP SetMsg
ChOut:
 RTS
`;

export const ALIENS = `
// SPAWNER: every SPAWN_RATE frames a free alien slot is filled from the
// next vent that is near the marine (but not right on top of him).
Spawner:
 DEC SPAWN_T
 BNE SpOut
 LDA SPAWN_RATE
 STA SPAWN_T
 LDX #NBUL
SpFree:
 LDA AST,X
 BEQ SpSlot
 INX
 CPX #NACT
 BNE SpFree
SpOut:
 RTS
SpSlot:
 STX Z_IX
 LDA PX
 STA Z_T0
 LDA PX+1
 JSR Pix2C
 STA Z_CX
 LDA PY
 STA Z_T0
 LDA PY+1
 JSR Pix2C
 STA Z_CY
 LDA #$06
 STA Z_I
SpTry:
 LDY VENT_I
 INY
 CPY NVENTS
 BCC SpVi
 LDY #$00
SpVi:
 STY VENT_I
 LDA VENT_X,Y
 SEC
 SBC Z_CX
 JSR Abs8
 CMP #SPAWN_FAR_X
 BCS SpNo
 STA Z_T2
 LDA VENT_Y,Y
 SEC
 SBC Z_CY
 JSR Abs8
 CMP #SPAWN_FAR_Y
 BCS SpNo
 CMP #SPAWN_NEAR
 BCS SpOk
 LDA Z_T2
 CMP #SPAWN_NEAR
 BCS SpOk
SpNo:
 DEC Z_I
 BNE SpTry
 RTS
SpOk:
 LDX Z_IX
 LDA VENT_X,Y
 ASL A
 ASL A
 ASL A
 STA AXL,X
 LDA VENT_X,Y
 LSR A
 LSR A
 LSR A
 LSR A
 LSR A
 STA AXH,X
 CLC
 LDA AXL,X
 ADC #$08
 STA AXL,X
 BCC SpXc
 INC AXH,X
SpXc:
 LDA VENT_Y,Y
 ASL A
 ASL A
 ASL A
 STA AYL,X
 LDA VENT_Y,Y
 LSR A
 LSR A
 LSR A
 LSR A
 LSR A
 STA AYH,X
 CLC
 LDA AYL,X
 ADC #$08
 STA AYL,X
 BCC SpYc
 INC AYH,X
SpYc:
 LDA #AS_SPAWN
 STA AST,X
 LDA #SPAWN_FRAMES
 STA ATM,X
 LDA ALIEN_HP
 STA AHP,X
 LDA #$04
 STA ADIR,X
 LDA #$00
 STA ASTK,X
 STA AACC,X
 RTS
Abs8:
 BPL AbOk
 EOR #$FF
 CLC
 ADC #$01
AbOk:
 RTS

// ALIENS: climb out of the vent, chase the marine (one axis at a time,
// sliding along walls), bite on contact, explode when shot.
MoveAliens:
 LDX #NBUL
MaLoop:
 STX Z_IX
 LDA AST,X
 BEQ MaNext
 CMP #AS_LIVE
 BEQ MaLive
 DEC ATM,X
 BNE MaNext
 LDA AST,X
 CMP #AS_SPAWN
 BNE MaFree
 LDA #AS_LIVE
 STA AST,X
 JMP MaNext
MaFree:
 LDA #AS_FREE
 STA AST,X
 JMP MaNext
MaLive:
 JSR AlienStep
MaNext:
 LDX Z_IX
 INX
 CPX #NACT
 BNE MaLoop
 RTS

AlienStep:
 SEC
 LDA AXL,X
 SBC PX
 LDA AXH,X
 SBC PX+1
 JSR Far8
 BCS AsGone
 SEC
 LDA AYL,X
 SBC PY
 LDA AYH,X
 SBC PY+1
 JSR Far8
 BCC AsNear
AsGone:
 LDA #AS_FREE
 STA AST,X
 RTS
// C set if the high byte A of a difference is past +-255 pixels
Far8:
 CMP #$00
 BEQ FaNo
 CMP #$FF
 BEQ FaNo
 SEC
 RTS
FaNo:
 CLC
 RTS
AsNear:
 LDA ASTK,X
 BEQ AsNoFlash
 DEC ASTK,X
AsNoFlash:
 CLC
 LDA AACC,X
 ADC ALIEN_SPD
 STA AACC,X
 BCC AsBite
 LDA #$00
 STA Z_DX
 STA Z_DY
 SEC
 LDA PX
 SBC AXL,X
 STA Z_T0
 LDA PX+1
 SBC AXH,X
 BMI AsXl
 ORA Z_T0
 BEQ AsXd
 LDA #$01
 JMP AsXs
AsXl:
 LDA #$FF
AsXs:
 STA Z_DX
 JSR AlienTryX
AsXd:
 LDX Z_IX
 SEC
 LDA PY
 SBC AYL,X
 STA Z_T0
 LDA PY+1
 SBC AYH,X
 BMI AsYu
 ORA Z_T0
 BEQ AsYd
 LDA #$01
 JMP AsYs
AsYu:
 LDA #$FF
AsYs:
 STA Z_DY
 JSR AlienTryY
AsYd:
 LDX Z_IX
 LDA Z_DY
 CLC
 ADC #$01
 STA Z_T0
 ASL A
 ADC Z_T0
 STA Z_T0
 LDA Z_DX
 CLC
 ADC #$01
 CLC
 ADC Z_T0
 TAY
 LDA AlDir,Y
 BMI AsBite
 STA ADIR,X
AsBite:
 LDX Z_IX
 SEC
 LDA AXL,X
 SBC PX
 STA Z_T0
 LDA AXH,X
 SBC PX+1
 JSR Near10
 BCC AsOut
 SEC
 LDA AYL,X
 SBC PY
 STA Z_T0
 LDA AYH,X
 SBC PY+1
 JSR Near10
 BCC AsOut
 LDA P_INV
 BNE AsOut
 LDA #BITE_SAFE
 STA P_INV
 LDA HUD_DIRTY
 ORA #HD_ENERGY
 STA HUD_DIRTY
 SEC
 LDA ENERGY
 SBC #BITE_DAMAGE
 BCS AsHurt
 LDA #$00
AsHurt:
 STA ENERGY
 BEQ AsKill
 LDA #S_HURT
 JMP PlaySfx
AsKill:
 JMP KillPlayer
AsOut:
 RTS
// direction from (dy+1)*3 + (dx+1)
AlDir:
 .byte $07,$00,$01,$06,$FF,$02,$05,$04,$03

AlienTryX:
 LDX Z_IX
 CLC
 LDA AXL,X
 ADC Z_DX
 STA Z_BX
 LDA Z_DX
 BMI AxN
 LDA #$00
 JMP AxA
AxN:
 LDA #$FF
AxA:
 ADC AXH,X
 STA Z_BXH
 LDA AYL,X
 STA Z_BY
 LDA AYH,X
 STA Z_BYH
 LDA #ABOX
 STA Z_BH
 JSR BoxSolid
 LDX Z_IX
 BCS AxBlk
 LDA Z_BX
 STA AXL,X
 LDA Z_BXH
 STA AXH,X
 RTS
AxBlk:
 LDA #$00
 STA Z_DX
 RTS
AlienTryY:
 LDX Z_IX
 CLC
 LDA AYL,X
 ADC Z_DY
 STA Z_BY
 LDA Z_DY
 BMI AyN
 LDA #$00
 JMP AyA
AyN:
 LDA #$FF
AyA:
 ADC AYH,X
 STA Z_BYH
 LDA AXL,X
 STA Z_BX
 LDA AXH,X
 STA Z_BXH
 LDA #ABOX
 STA Z_BH
 JSR BoxSolid
 LDX Z_IX
 BCS AyBlk
 LDA Z_BY
 STA AYL,X
 LDA Z_BYH
 STA AYH,X
 RTS
AyBlk:
 LDA #$00
 STA Z_DY
 RTS

// alien Y shot dead (X = the bullet, kept)
AlienDie:
 LDA #AS_DIE
 STA AST,Y
 LDA #DIE_FRAMES
 STA ATM,Y
 STX Z_T5
 LDA #$01
 JSR AddScore
 LDA #S_ALIEN_DIE
 JSR PlaySfx
 LDX Z_T5
 RTS
`;
