// Match code blocks: players, CPU AI, keepers, ball, kicks, rules, HUD,
// title screen.
let uq = 0;
const U = p => p + (++uq);

// dst(16) += sign(var) * src(16); sign var holds -1/0/1 as a byte
function accSigned(dst, dstH, src, srcH, signVar, negate) {
  const skip = U('As'), neg = U('Asn');
  const add = `
 CLC
 LDA ${dst}
 ADC ${src}
 STA ${dst}
 LDA ${dstH}
 ADC ${srcH}
 STA ${dstH}`;
  const sub = `
 SEC
 LDA ${dst}
 SBC ${src}
 STA ${dst}
 LDA ${dstH}
 SBC ${srcH}
 STA ${dstH}`;
  return `
 LDA ${signVar}
 BEQ ${skip}
 BMI ${neg}
${negate ? sub : add}
 JMP ${skip}
${neg}:
${negate ? add : sub}
${skip}:`;
}
// negate a 16-bit zp/abs pair
const neg16 = (l, h) => `
 LDA #$00
 SEC
 SBC ${l}
 STA ${l}
 LDA #$00
 SBC ${h}
 STA ${h}`;

export const GAMELOOP = `
// ----------------------------------------------------------------- match
StartMatch:
 JSR MatchInit
GameLoop:
 JSR FrameSync
 JSR GameFrame
 LDA MODE
 BNE GameLoop
 JMP Title
GameFrame:
 JSR ReadInput
 JSR CameraUpdate
 JSR MatchUpdate
 LDA SNAP_REQ
 BEQ GfNoSnap
 JSR CamSnap
GfNoSnap:
 JSR BuildSprites
 JSR Commit
 JMP IdleWork
// A = humans (bit 0 port 2 plays C64, bit 1 port 1 plays VIC; 0 = demo)
MatchInit:
 STA HUMANS
 LDA #D018_A
 STA CUR_D018
 LDA #$00
 STA TITLE_MODE
 STA SCORE0
 STA SCORE1
 STA CLK_SUB
 STA CLK_SEC
 STA CLK_MIN
 STA ATT0
 STA KO_TEAM
 STA MSG_T
 STA PRE_ON
 STA BK_OK
 STA FLIP_REQ
 STA BZH
 STA BZL
 LDA #$01
 STA HALF
 STA MODE
 LDA #$10
 STA HUD_D016
 JSR InitSort
 JSR ColourGame
 JSR HudInit
 LDA #$01
 STA FLOCK1
 STA FLOCK2
 JSR SetupKickoff
 LDA HUMANS
 BNE MiR
 LDA #MSG_DEMO
 JMP ShowMsgLong
MiR:
 RTS
MatchUpdate:
 JSR Rand
 LDA HUMANS
 BNE MuNoDemo
 LDA FPRESS1
 ORA FPRESS2
 BEQ MuNoDemo
 LDA #$00
 STA MODE
 RTS
MuNoDemo:
 LDA #$00
 STA KICKED
 LDA GSTATE
 BNE MuNotPlay
 JSR HumanAll
 JSR AIUpdate
 JSR UpdPlayers
 JSR BallUpdate
 JSR ClockTick
 JSR CrowdLevel
 JMP HudTick
MuNotPlay:
 CMP #GS_RESTART
 BNE MuNotRs
 JSR HumanAll
 JSR AIUpdate
 JSR RestartTick
 JSR UpdPlayers
 JSR AttachIfOwned
 LDA RS_TYPE
 CMP #RS_KICKOFF
 BEQ MuRsNoClk
 JSR ClockTick
MuRsNoClk:
 JSR CrowdLevel
 JMP HudTick
MuNotRs:
 CMP #GS_GOAL
 BNE MuNotGoal
 JSR AIUpdate
 JSR UpdPlayers
 JSR BallLoose
 JSR NetClamp
 DEC GTIMER
 BNE MuGoalH
 JSR SetupKickoff
MuGoalH:
 JMP HudTick
MuNotGoal:
 CMP #GS_BREAK
 BNE MuFull
 JSR AIUpdate
 JSR UpdPlayers
 JSR BallLoose
 DEC GTIMER
 BNE MuBrH
 LDA HUMANS
 BNE MuHalf2
 LDA #$00
 STA MODE
 RTS
MuHalf2:
 LDA #$02
 STA HALF
 LDA ATT0
 EOR #$01
 STA ATT0
 LDA #$01
 STA KO_TEAM
 JSR HudHalf
 JSR SetupKickoff
 LDA #MSG_2ND
 JSR ShowMsg
MuBrH:
 JMP HudTick
MuFull:
 JSR AIUpdate
 JSR UpdPlayers
 JSR BallLoose
 LDA GTIMER
 BEQ MuFwait
 DEC GTIMER
 JMP HudTick
MuFwait:
 LDA HUMANS
 BEQ MuFend
 LDA FPRESS1
 ORA FPRESS2
 BEQ MuFh
MuFend:
 LDA #$00
 STA MODE
MuFh:
 JMP HudTick
// ---- kick-off: everyone to their own half, ball on the spot
SetupKickoff:
 LDX #$00
SkL:
 LDY ROLE,X
 LDA TEAMOF,X
 JSR AttDir
 BNE SkLeft
 CLC
 LDA #<P_LEFT
 ADC KODISTL,Y
 STA PXL,X
 LDA #>P_LEFT
 ADC KODISTH,Y
 STA PXH,X
 LDA #$00
 STA PDIR,X
 JMP SkY
SkLeft:
 SEC
 LDA #<P_RIGHT
 SBC KODISTL,Y
 STA PXL,X
 LDA #>P_RIGHT
 SBC KODISTH,Y
 STA PXH,X
 LDA #$04
 STA PDIR,X
SkY:
 LDA FYL,Y
 STA PYL,X
 LDA FYH,Y
 STA PYH,X
 LDA #$00
 STA PXF,X
 STA PYF,X
 STA PSTATE,X
 STA PCOOL,X
 STA PANIM,X
 LDA #$FF
 STA PMOVE,X
 JSR ZeroVel
 JSR PickFrame
 INX
 CPX #NPL
 BNE SkL
// the kick-off partner stands beside the centre spot
 LDX KO_TEAM
 LDA TEAMBASE,X
 CLC
 ADC #10
 TAY
 LDA KO_TEAM
 JSR AttDir
 BNE SkPl
 LDA #<(P_MIDX-26)
 STA PXL,Y
 LDA #>(P_MIDX-26)
 STA PXH,Y
 JMP SkPy
SkPl:
 LDA #<(P_MIDX+26)
 STA PXL,Y
 LDA #>(P_MIDX+26)
 STA PXH,Y
SkPy:
 LDA #232
 STA PYL,Y
 LDA #$00
 STA PYH,Y
 LDA KO_TEAM
 STA RS_TEAM
 LDA #<P_MIDX
 STA RS_X
 LDA #>P_MIDX
 STA RS_X+1
 LDA #P_MIDY
 STA RS_Y
 LDA #$00
 STA RS_Y+1
 LDA #$09
 STA CTRL1
 LDA #20
 STA CTRL2
 LDA #$40
 STA CROWD_T
 LDA #$FF
 STA OWNER
 LDA #RS_KICKOFF
 JMP RestartSetup
// A = team -> A = 0 if it attacks right, 1 if left
AttDir:
 EOR ATT0
 RTS
// X = side (0 left goal, 1 right) -> A = team defending it
DefTeam:
 TXA
 EOR ATT0
 RTS
`;

export const RULES = `
// ----------------------------------------------------------------- rules
CheckGoalOut:
 LDA GSTATE
 BNE CgRts
 LDA PXH+BALL
 BNE CgR
 LDA PXL+BALL
 CMP #P_LEFT
 BCS CgSide
 LDX #$00
 JMP CgLine
CgR:
 CMP #$03
 BCC CgSide
 LDA PXL+BALL
 CMP #<(P_RIGHT+1)
 BCC CgSide
 LDX #$01
 JMP CgLine
CgSide:
 LDA PYH+BALL
 BNE CgBot
 LDA PYL+BALL
 CMP #P_TOP
 BCS CgRts
 LDA #$00
 JMP ThrowIn
CgBot:
 LDA PYL+BALL
 CMP #<(P_BOT+1)
 BCC CgRts
 LDA #$01
 JMP ThrowIn
CgRts:
 RTS
CgLine:
 STX Z_K
 LDA PYH+BALL
 BNE CgOut
 LDA PYL+BALL
 CMP #P_POST_T
 BCC CgOut
 CMP #P_POST_B+1
 BCS CgOut
 LDA BZH
 CMP #P_BAR
 BCS CgOut
 JMP Goal
CgOut:
 JMP OutEnd
Goal:
 LDX Z_K
 STX GOALSIDE
 JSR DefTeam
 EOR #$01
 STA Z_T2
 TAX
 LDA SCORE,X
 CMP #$09
 BCS GoCap
 INC SCORE,X
GoCap:
 LDA Z_T2
 EOR #$01
 STA KO_TEAM
 LDX LASTTOUCH
 LDA TEAMOF,X
 CMP Z_T2
 BEQ GoSc
 LDX Z_T2
 LDA TEAMBASE,X
 CLC
 ADC #$09
 TAX
GoSc:
 STX SCORER
 LDA #ST_CELEB
 STA PSTATE,X
 LDA #$FF
 STA OWNER
 STA PASS_TO
 STA SHOT_GOAL
 LDA #GS_GOAL
 STA GSTATE
 LDA #230
 STA GTIMER
 LDA #$F0
 STA CROWD_T
 JSR HudScore
 LDA #MSG_GOAL
 JSR ShowMsgLong
 LDA #FX_WHISTLE
 JMP SfxPlay
// ball crossed a goal line outside the goal: corner or goal kick
OutEnd:
 LDX Z_K
 JSR DefTeam
 STA Z_T2
 LDX LASTTOUCH
 LDA TEAMOF,X
 CMP Z_T2
 BEQ OeCorner
 LDA Z_T2
 STA RS_TEAM
 LDA #P_MIDY
 STA RS_Y
 LDA #$00
 STA RS_Y+1
 LDA Z_K
 BNE OeGkR
 LDA #<(P_LEFT+24)
 STA RS_X
 LDA #>(P_LEFT+24)
 STA RS_X+1
 JMP OeGk
OeGkR:
 LDA #<(P_RIGHT-24)
 STA RS_X
 LDA #>(P_RIGHT-24)
 STA RS_X+1
OeGk:
 LDA #RS_GOALKICK
 JMP RestartSetup
OeCorner:
 LDA Z_T2
 EOR #$01
 STA RS_TEAM
 LDA Z_K
 BNE OeCr
 LDA #<(P_LEFT+4)
 STA RS_X
 LDA #>(P_LEFT+4)
 STA RS_X+1
 JMP OeCy
OeCr:
 LDA #<(P_RIGHT-4)
 STA RS_X
 LDA #>(P_RIGHT-4)
 STA RS_X+1
OeCy:
 LDA #$00
 STA RS_Y+1
 LDA PYL+BALL
 CMP #P_MIDY
 BCS OeCb
 LDA #P_TOP+4
 STA RS_Y
 JMP OeCgo
OeCb:
 LDA #<(P_BOT-4)
 STA RS_Y
 LDA #>(P_BOT-4)
 STA RS_Y+1
OeCgo:
 LDA #RS_CORNER
 JMP RestartSetup
// A = 0 top / 1 bottom touchline
ThrowIn:
 STA Z_K
 LDX LASTTOUCH
 LDA TEAMOF,X
 EOR #$01
 STA RS_TEAM
 LDA PXL+BALL
 STA RS_X
 LDA PXH+BALL
 STA RS_X+1
 BNE TiHi
 LDA RS_X
 CMP #<(P_LEFT+12)
 BCS TiY
 LDA #<(P_LEFT+12)
 STA RS_X
 JMP TiY
TiHi:
 CMP #$03
 BCC TiY
 LDA RS_X
 CMP #<(P_RIGHT-12)
 BCC TiY
 LDA #<(P_RIGHT-12)
 STA RS_X
TiY:
 LDA #$00
 STA RS_Y+1
 LDA Z_K
 BNE TiB
 LDA #P_TOP+2
 STA RS_Y
 JMP TiGo
TiB:
 LDA #<(P_BOT-2)
 STA RS_Y
 LDA #>(P_BOT-2)
 STA RS_Y+1
TiGo:
 LDA #RS_THROW
// A = restart type; RS_TEAM, RS_X, RS_Y set
RestartSetup:
 STA RS_TYPE
 LDA RS_X
 STA PXL+BALL
 LDA RS_X+1
 STA PXH+BALL
 LDA RS_Y
 STA PYL+BALL
 LDA RS_Y+1
 STA PYH+BALL
 LDX #BALL
 JSR ZeroVel
 LDA #$00
 STA PXF+BALL
 STA PYF+BALL
 STA BZL
 STA BZH
 STA BVZL
 STA BVZH
 LDX RS_TEAM
 LDA RS_TYPE
 CMP #RS_GOALKICK
 BNE RsNotGk
 LDA TEAMBASE,X
 TAX
 JMP RsGot
RsNotGk:
 CMP #RS_KICKOFF
 BNE RsNear
 LDA TEAMBASE,X
 CLC
 ADC #$09
 TAX
 JMP RsGot
RsNear:
 LDA RS_TEAM
 JSR NearestToBall
RsGot:
 STX Z_I
 JSR RsFacing
 STA PDIR,X
 TAY
// stand so the dribble offset puts the ball on the spot
 LDA DRIBX,Y
 STA Z_T0
 LDA #$00
 LDY Z_T0
 BPL RsXp
 LDA #$FF
RsXp:
 STA Z_T1
 SEC
 LDA PXL+BALL
 SBC Z_T0
 STA PXL,X
 LDA PXH+BALL
 SBC Z_T1
 STA PXH,X
 LDY PDIR,X
 LDA DRIBY,Y
 STA Z_T0
 LDA #$00
 LDY Z_T0
 BPL RsYp
 LDA #$FF
RsYp:
 STA Z_T1
 SEC
 LDA PYL+BALL
 SBC Z_T0
 STA PYL,X
 LDA PYH+BALL
 SBC Z_T1
 STA PYH,X
 LDA #ST_WAIT
 STA PSTATE,X
 LDA #50
 STA PTIMER,X
 LDA #$00
 STA PCOOL,X
 JSR ZeroVel
 STX OWNER
 STX LASTTOUCH
 LDA #$FF
 STA PASS_TO
 STA SHOT_GOAL
 LDA #GS_RESTART
 STA GSTATE
 LDA #250
 STA RS_AUTO
 LDY RS_TEAM
 LDA HUMANS
 AND BITTAB,Y
 BEQ RsCpu
 TXA
 STA CTRL,Y
RsCpu:
 JSR PickFrame
 LDA #$01
 STA SNAP_REQ
 LDY RS_TYPE
 LDA RSMSG,Y
 JSR ShowMsg
 LDA #FX_WHISTLE
 JMP SfxPlay
// X = taker -> A = facing into the pitch
RsFacing:
 LDA RS_TYPE
 CMP #RS_THROW
 BNE RfNotThrow
 LDA RS_Y+1
 BNE RfUp
 LDA RS_Y
 CMP #P_MIDY
 BCS RfUp
 LDA #$02
 RTS
RfUp:
 LDA #$06
 RTS
RfNotThrow:
 CMP #RS_CORNER
 BEQ RfCorner
 LDA RS_TEAM
 JSR AttDir
 BEQ RfR
 LDA #$04
RfR:
 RTS
RfCorner:
 LDA RS_X+1
 BNE RfCr
 LDA RS_Y+1
 BNE RfCl2
 LDA #$01
 RTS
RfCl2:
 LDA #$07
 RTS
RfCr:
 LDA RS_Y+1
 BNE RfCr2
 LDA #$03
 RTS
RfCr2:
 LDA #$05
 RTS
// the taking team's CPU taker waits PTIMER frames, a human presses fire
RestartTick:
 LDX OWNER
 BMI RtRts
 LDA TEAMOF,X
 TAY
 LDA HUMANS
 AND BITTAB,Y
 BEQ RtCpu
 TXA
 CMP CTRL,Y
 BNE RtCpu
 DEC RS_AUTO
 BNE RtRts
 JMP RestartGoCpu
RtCpu:
 DEC PTIMER,X
 BNE RtRts
 JMP RestartGoCpu
RtRts:
 RTS
RestartGoCpu:
 LDX OWNER
 LDA #GS_PLAY
 STA GSTATE
 LDA #ST_NORMAL
 STA PSTATE,X
 LDA RS_TYPE
 CMP #RS_CORNER
 BEQ RgCross
 CMP #RS_GOALKICK
 BEQ RgLong
 CMP #RS_KICKOFF
 BEQ RgKo
 JMP DoPassCpu
RgCross:
 JMP DoCross
RgLong:
 JMP DoLongKick
RgKo:
 LDA TEAMOF,X
 TAY
 LDA TEAMBASE,Y
 CLC
 ADC #10
 TAY
 JMP PassTo
// A = team -> X = its outfield player nearest the ball
NearestToBall:
 TAX
 LDA TEAMBASE,X
 CLC
 ADC #$01
 TAX
 LDA #$FF
 STA Z_T5
 STX Z_T6
 LDA #10
 STA Z_T7
NtL:
 LDA PSTATE,X
 CMP #ST_FALLEN
 BEQ NtN
 JSR DistToBall
 CMP Z_T5
 BCS NtN
 STA Z_T5
 STX Z_T6
NtN:
 INX
 DEC Z_T7
 BNE NtL
 LDX Z_T6
 RTS
// X = human (0/1, also its team) -> control the player nearest the ball
SwitchNearest:
 STX Z_HUM
 TXA
 JSR NearestToBall
 TXA
 LDX Z_HUM
 STA CTRL,X
 RTS
// ---- clock: 1 game second every 3 frames, 45 minutes a half
ClockTick:
 INC CLK_SUB
 LDA CLK_SUB
 CMP #$03
 BCC CtRts
 LDA #$00
 STA CLK_SUB
 INC CLK_SEC
 LDA CLK_SEC
 CMP #60
 BCC CtHud
 LDA #$00
 STA CLK_SEC
 INC CLK_MIN
 LDA CLK_MIN
 CMP #45
 BEQ CtHalf
 CMP #90
 BEQ CtFull
CtHud:
 JMP HudClock
CtRts:
 RTS
CtHalf:
 LDA HALF
 CMP #$01
 BNE CtHud
 JSR HudClock
 JSR StopPlay
 LDA #GS_BREAK
 STA GSTATE
 LDA #200
 STA GTIMER
 LDA #MSG_HALF
 JSR ShowMsgLong
 LDA #FX_WHISTLE_L
 JMP SfxPlay
CtFull:
 JSR HudClock
 JSR StopPlay
 LDA #GS_FULL
 STA GSTATE
 LDA #200
 STA GTIMER
 LDA #MSG_FULL
 JSR ShowMsgLong
 LDA #FX_WHISTLE3
 JMP SfxPlay
StopPlay:
 LDA #$FF
 STA OWNER
 STA PASS_TO
 STA SHOT_GOAL
 LDX #$00
SpL:
 LDA #ST_NORMAL
 STA PSTATE,X
 INX
 CPX #NPL
 BNE SpL
 RTS
CrowdLevel:
 LDA PXH+BALL
 CMP #$02
 BCS ClRight
 SEC
 LDA PXL+BALL
 SBC #<P_LEFT
 STA Z_T0
 LDA PXH+BALL
 SBC #>P_LEFT
 JMP ClD
ClRight:
 SEC
 LDA #<P_RIGHT
 SBC PXL+BALL
 STA Z_T0
 LDA #>P_RIGHT
 SBC PXH+BALL
ClD:
 BMI ClNear
 LSR
 ROR Z_T0
 LSR
 ROR Z_T0
 BNE ClFar
 LDA Z_T0
 CMP #$80
 BCC ClSet
ClFar:
 LDA #$80
ClSet:
 STA Z_T0
 LDA #$C8
 SEC
 SBC Z_T0
 STA CROWD_T
 RTS
ClNear:
 LDA #$C8
 STA CROWD_T
 RTS
`;

export const HUD = `
// ----------------------------------------------------------------- HUD
ColourGame:
 LDX #39
CgcL:
 LDA HUDCOL,X
 STA $D800,X
 LDA #$05
 STA $D828,X
 DEX
 BPL CgcL
 LDA #$09
 LDX #$00
CgcF:
 STA $D850,X
 STA $D950,X
 STA $DA50,X
 STA $DAE8,X
 INX
 BNE CgcF
 RTS
HudInit:
 LDX #39
HiL:
 LDA HUDROW,X
 STA SCRA,X
 STA SCRB,X
 LDA #CH_BAR
 STA SCRA+40,X
 STA SCRB+40,X
 DEX
 BPL HiL
 JSR HudScore
 JSR HudClock
 JMP HudHalf
HudPut:
 STA SCRA,X
 STA SCRB,X
 RTS
HudScore:
 LDA SCORE0
 ORA #$30
 LDX #$05
 JSR HudPut
 LDA SCORE1
 ORA #$30
 LDX #$07
 JMP HudPut
HudClock:
 LDA CLK_MIN
 JSR Div10
 PHA
 TXA
 ORA #$30
 LDX #33
 JSR HudPut
 PLA
 ORA #$30
 LDX #34
 JSR HudPut
 LDA CLK_SEC
 JSR Div10
 PHA
 TXA
 ORA #$30
 LDX #36
 JSR HudPut
 PLA
 ORA #$30
 LDX #37
 JMP HudPut
HudHalf:
 LDY #$00
 LDA HALF
 CMP #$02
 BNE HhL0
 LDY #$03
HhL0:
 LDX #29
HhL:
 LDA HALFTXT,Y
 JSR HudPut
 INY
 INX
 CPX #32
 BNE HhL
 RTS
Div10:
 LDX #$00
D10L:
 CMP #10
 BCC D10R
 SBC #10
 INX
 JMP D10L
D10R:
 RTS
ShowMsgLong:
 LDY #250
 JMP SmGo
ShowMsg:
 LDY #120
SmGo:
 STY MSG_T
 STA MSG_ID
 TAX
 LDA MSGOFS,X
 TAX
 LDY #$00
SmL:
 LDA MSGTXT,X
 STA SCRA+15,Y
 STA SCRB+15,Y
 INX
 INY
 CPY #12
 BNE SmL
 RTS
HudTick:
 LDA MSG_T
 BEQ HtIdle
 DEC MSG_T
 BNE HtFlash
 LDA HUMANS
 BNE HtClear
 LDA MSG_ID
 CMP #MSG_DEMO
 BEQ HtFire
 LDA #MSG_DEMO
 JMP ShowMsg
HtFire:
 LDA #MSG_FIRE
 JMP ShowMsg
HtClear:
 LDA #MSG_NONE
 JSR ShowMsg
 LDA #$00
 STA MSG_T
 RTS
HtFlash:
 LDA FRAMECNT
 AND #$08
 BEQ HtC1
 LDA #$07
 JMP HtC2
HtC1:
 LDA #$01
HtC2:
 LDX #11
HtCl:
 STA $D800+15,X
 DEX
 BPL HtCl
HtIdle:
 RTS
`;

export const PLAYERS = `
// ----------------------------------------------------------------- players
UpdPlayers:
 LDX #NPL-1
UpL:
 LDA PCOOL,X
 BEQ UpC0
 DEC PCOOL,X
UpC0:
 LDA PSTATE,X
 BEQ UpNormal
 CMP #ST_CELEB
 BEQ UpNormal
 JMP UpSpecial
UpNormal:
 LDA PMOVE,X
 BMI UpStop
 STA PDIR,X
 LDA OBY,X
 CMP #$FF
 BNE UpOn
// off screen: move every 4th frame at 4x speed
 TXA
 EOR FRAMECNT
 AND #$03
 BEQ UpOff2
 JMP UpNext
UpOff2:
 LDA PSPD,X
 ASL
 ASL
 ASL
 ORA PMOVE,X
 STA PVI,X
 CLC
 ADC #40
 JMP UpIdx
UpOn:
 LDA PSPD,X
 ASL
 ASL
 ASL
 ORA PMOVE,X
 STA PVI,X
UpIdx:
 TAY
 LDA SPVXL,Y
 CLC
 ADC PXF,X
 STA PXF,X
 LDA SPVXH,Y
 ADC PXL,X
 STA PXL,X
 LDA SPVXS,Y
 ADC PXH,X
 STA PXH,X
 LDA SPVYL,Y
 CLC
 ADC PYF,X
 STA PYF,X
 LDA SPVYH,Y
 ADC PYL,X
 STA PYL,X
 LDA SPVYS,Y
 ADC PYH,X
 STA PYH,X
 INC PANIM,X
// only the edges need the full clamp
 LDA PXH,X
 BEQ UpCl
 CMP #$03
 BCS UpCl
 LDA PYH,X
 BNE UpYh
 LDA PYL,X
 CMP #64
 BCC UpCl
 JMP UpNext
UpYh:
 CMP #$01
 BNE UpCl
 LDA PYL,X
 CMP #$6C
 BCC UpNext
UpCl:
 JSR ClampPos
 JMP UpNext
UpStop:
 LDA #$FF
 STA PVI,X
UpNext:
 DEX
 BPL UpL
 RTS
// slides, dives, stumbles, holding: timers, then the generic move
UpSpecial:
 CMP #ST_SLIDE
 BEQ UpTimed
 CMP #ST_DIVE
 BEQ UpTimed
 CMP #ST_KICK
 BEQ UpStill
 CMP #ST_FALLEN
 BEQ UpStill
 JSR ZeroVel
 JMP UpInteg
UpTimed:
 DEC PTIMER,X
 BEQ UpNorm
 LDA PTIMER,X
 CMP #12
 BCS UpInteg
 JSR ZeroVel
 JMP UpInteg
UpStill:
 JSR ZeroVel
 DEC PTIMER,X
 BNE UpInteg
UpNorm:
 LDA #ST_NORMAL
 STA PSTATE,X
 LDA #$FF
 STA PVI,X
 JSR ZeroVel
UpInteg:
 JSR Integrate
 JSR ClampPos
 JMP UpNext
// X = player: VX/VY from the velocity table for running players
SyncVel:
 LDA PSTATE,X
 BEQ SvRun
 CMP #ST_CELEB
 BNE SvRts
SvRun:
 LDY PVI,X
 CPY #$FF
 BEQ SvZero
 LDA SPVXL,Y
 STA VXL,X
 LDA SPVXH,Y
 STA VXH,X
 LDA SPVYL,Y
 STA VYL,X
 LDA SPVYH,Y
 STA VYH,X
SvRts:
 RTS
SvZero:
 JMP ZeroVel
// keep players on the grass: x 24..1000, y 64..364
ClampPos:
 LDA PXH,X
 BMI CpX0
 BNE CpXhi
 LDA PXL,X
 CMP #24
 BCS CpY
CpX0:
 LDA #24
 STA PXL,X
 LDA #$00
 STA PXH,X
 JMP CpY
CpXhi:
 CMP #$03
 BCC CpY
 BNE CpX1
 LDA PXL,X
 CMP #$E8
 BCC CpY
CpX1:
 LDA #$E8
 STA PXL,X
 LDA #$03
 STA PXH,X
CpY:
 LDA PYH,X
 BMI CpY0
 BNE CpYhi
 LDA PYL,X
 CMP #64
 BCS CpRts
CpY0:
 LDA #64
 STA PYL,X
 LDA #$00
 STA PYH,X
 RTS
CpYhi:
 CMP #$01
 BNE CpY1
 LDA PYL,X
 CMP #$6C
 BCC CpRts
CpY1:
 LDA #$6C
 STA PYL,X
 LDA #$01
 STA PYH,X
CpRts:
 RTS
PickFrame:
 LDA PSTATE,X
 BNE PfSpecial
 LDY PDIR,X
 LDA PMOVE,X
 BMI PfStd
 LDA PANIM,X
 LSR
 LSR
 AND #$03
 SEC
 ADC DIRBASE,Y
 STA PFRAME,X
 RTS
PfStd:
 LDA DIRBASE,Y
 STA PFRAME,X
 RTS
PfSpecial:
 CMP #ST_CELEB
 BEQ PfCeleb
 CMP #ST_SLIDE
 BEQ PfSlide
 CMP #ST_KICK
 BEQ PfKick
 CMP #ST_FALLEN
 BEQ PfFall
 CMP #ST_DIVE
 BEQ PfDive
 LDA #F_HOLD
 STA PFRAME,X
 RTS
PfCeleb:
 LDA FRAMECNT
 AND #$08
 BEQ PfRun
 LDA #F_CELEB
 STA PFRAME,X
 RTS
PfRun:
 LDY PDIR,X
 LDA DIRBASE,Y
 STA Z_T0
 LDA PMOVE,X
 BMI PfStand
 LDA PANIM,X
 LSR
 LSR
 AND #$03
 SEC
 ADC Z_T0
 STA PFRAME,X
 RTS
PfStand:
 LDA Z_T0
 STA PFRAME,X
 RTS
PfSlide:
 LDY PDIR,X
 LDA ISLEFT,Y
 CLC
 ADC #F_R_SLIDE
 STA PFRAME,X
 RTS
PfKick:
 LDY PDIR,X
 LDA ISLEFT,Y
 CLC
 ADC #F_R_KICK
 STA PFRAME,X
 RTS
PfFall:
 LDY PDIR,X
 LDA ISLEFT,Y
 CLC
 ADC #F_R_FALL
 STA PFRAME,X
 RTS
PfDive:
 LDA VYH,X
 BMI PfDu
 LDA #F_DIVE_D
 STA PFRAME,X
 RTS
PfDu:
 LDA #F_DIVE_U
 STA PFRAME,X
 RTS
StartSlide:
 LDA #ST_SLIDE
 STA PSTATE,X
 LDA #28
 STA PTIMER,X
 LDA PDIR,X
 ORA #$18
 TAY
 LDA SPVXL,Y
 STA VXL,X
 LDA SPVXH,Y
 STA VXH,X
 LDA SPVYL,Y
 STA VYL,X
 LDA SPVYH,Y
 STA VYH,X
 LDA #FX_TACKLE
 JMP SfxPlay
// ---- human players (X = 0: port 2 / team 0, 1: port 1 / team 1)
HumanAll:
 LDA HUMANS
 AND #$01
 BEQ Ha2
 LDX #$00
 JSR Human
Ha2:
 LDA HUMANS
 AND #$02
 BEQ HaE
 LDX #$01
 JMP Human
HaE:
 RTS
Human:
 STX Z_HUM
 LDA CTRL,X
 STA Z_I
 LDA JOY,X
 AND #$0F
 TAY
 LDA JOYDIR,Y
 STA Z_T0
 LDY Z_I
 LDA PSTATE,Y
 BEQ HuNormal
 CMP #ST_HOLD
 BNE HuNotHold
 JMP HuHold
HuNotHold:
 CMP #ST_WAIT
 BNE HuBusy
 JMP HuHold
HuBusy:
 LDX Z_HUM
 LDA FPRESS,X
 BEQ HuRts
 JMP SwitchNearest
HuNormal:
 LDA Z_T0
 STA PMOVE,Y
 LDA #$02
 STA PSPD,Y
 LDA OWNER
 CMP Z_I
 BNE HuNoBall
 LDA #$01
 STA PSPD,Y
 LDX Z_HUM
 LDA FREL,X
 BEQ HuRts
 CMP #10
 BCS HuLong
 LDX Z_I
 JMP DoPass
HuLong:
 SEC
 SBC #10
 LSR
 CMP #16
 BCC HuPw
 LDA #15
HuPw:
 LDX Z_I
 JMP DoShootOrLong
HuNoBall:
 LDX Z_HUM
 LDA FPRESS,X
 BEQ HuAuto
 LDX Z_I
 JSR DistToBall
 CMP #30
 BCS HuSwitch
 LDX Z_I
 JMP StartSlide
HuSwitch:
 LDX Z_HUM
 JMP SwitchNearest
HuAuto:
 LDA FRAMECNT
 AND #$07
 BNE HuRts
 LDY OWNER
 BMI HuAuChk
 LDA TEAMOF,Y
 CMP Z_HUM
 BEQ HuRts
HuAuChk:
 LDX Z_I
 JSR DistToBall
 CMP #90
 BCC HuRts
 LDX Z_HUM
 JMP SwitchNearest
HuRts:
 RTS
// keeper holding the ball, or a restart taker: aim, then fire
HuHold:
 LDA Z_T0
 BMI HhNoDir
 STA PDIR,Y
HhNoDir:
 LDA PSTATE,Y
 CMP #ST_HOLD
 BNE HhFire
 LDA PTIMER,Y
 SEC
 SBC #$01
 STA PTIMER,Y
 BNE HhFire
 LDX Z_I
 LDA #ST_NORMAL
 STA PSTATE,X
 JMP DoLongKick
HhFire:
 LDX Z_HUM
 LDA FREL,X
 BEQ HuRts
 STA Z_T1
 LDX Z_I
 LDA PSTATE,X
 STA Z_T2
 CMP #ST_WAIT
 BNE HhGo
 LDA #GS_PLAY
 STA GSTATE
HhGo:
 LDA #ST_NORMAL
 STA PSTATE,X
 LDA Z_T1
 CMP #10
 BCS HhLong
 JMP DoPass
HhLong:
 LDA Z_T2
 CMP #ST_WAIT
 BNE HhPow
 LDA RS_TYPE
 CMP #RS_CORNER
 BNE HhPow
 JMP DoCross
HhPow:
 LDA Z_T1
 SEC
 SBC #10
 LSR
 CMP #16
 BCC HhP
 LDA #15
HhP:
 JMP DoShootOrLong
`;

export const AI = `
// ----------------------------------------------------------------- CPU AI
AIUpdate:
 JSR AiPrep
 LDA GSTATE
 BNE AiKeep
// the ball owner (passes, shots, dribbling)
 LDX OWNER
 JSR AiCanAct
 BCC AiKeep
 JSR CpuOwnerAI
// one keeper per frame
AiKeep:
 LDX #$00
 LDA FRAMECNT
 AND #$01
 BEQ AiK
 LDX #11
AiK:
 CPX HCTRL0
 BEQ AiRts
 CPX HCTRL1
 BEQ AiRts
 JMP KeeperAI
// After the commit, when there is time (and at least every third frame):
// chaser choice, chasers + pass receiver (every other frame), formation.
// Short of time: the chasers still get their turn from the third frame
// on; the formation waits up to six frames.
IdleAI:
 LDA #AI_LIM
 JSR IdleChk
 BCS IaRun
 INC AI_SKIP
 LDA AI_SKIP
 CMP #$06
 BCS IaRun
 CMP #$03
 BCS AIChase
 RTS
IaRun:
 LDA #$00
 STA AI_SKIP
AIDefer:
 JSR AIChase
 JMP AdForm
AIChase:
 JSR ChooseChasers
 LDA GSTATE
 BNE AcRts
 LDA FRAMECNT
 AND #$01
 BNE AcRts
 LDX CHASE0
 JSR AiChaseIf
 LDX CHASE1
 JSR AiChaseIf
 LDX PASS_TO
 JMP AiChaseIf
AcRts:
 RTS
AdForm:
// formation: every 8th outfield player per frame (every 4th in a goal)
 LDA #$08
 STA AI_STEP
 LDA FRAMECNT
 AND #$07
 LDY GSTATE
 CPY #GS_GOAL
 BNE AiF0
 LDA #$04
 STA AI_STEP
 LDA FRAMECNT
 AND #$03
AiF0:
 TAX
AiFl:
 STX AI_X
 CPX HCTRL0
 BEQ AiFn
 CPX HCTRL1
 BEQ AiFn
 LDA ROLE,X
 BEQ AiFn
 LDA PSTATE,X
 BEQ AiFok
 CMP #ST_CELEB
 BNE AiFn
AiFok:
 LDA GSTATE
 BNE AiFnp
 CPX OWNER
 BEQ AiFn
 CPX CHASE0
 BEQ AiFn
 CPX CHASE1
 BEQ AiFn
 CPX PASS_TO
 BEQ AiFn
 JSR FormationAI
 JMP AiFn
AiFnp:
 CMP #GS_GOAL
 BNE AiFform
 JSR GoalCelebAI
 JMP AiFn
// waiting for a kick-off: everybody stays where the line-up put him
AiFform:
 CMP #GS_RESTART
 BNE AiFf2
 LDA RS_TYPE
 CMP #RS_KICKOFF
 BEQ AiFn
AiFf2:
 JSR FormationAI
AiFn:
 LDA AI_X
 CLC
 ADC AI_STEP
 TAX
 CPX #NPL
 BCC AiFl
AiRts:
 RTS
// X = player: C=1 if the CPU may steer him (exists, not human, outfield, free)
AiCanAct:
 CPX #NPL
 BCS AcNo
 CPX HCTRL0
 BEQ AcNo
 CPX HCTRL1
 BEQ AcNo
 LDA ROLE,X
 BEQ AcNo
 LDA PSTATE,X
 BNE AcNo
 SEC
 RTS
AcNo:
 CLC
 RTS
AiChaseIf:
 JSR AiCanAct
 BCC AciR
 CPX OWNER
 BEQ AciR
 JMP ChaseBall
AciR:
 RTS
// per-frame team values for FormationAI: attack direction, how far the
// block is pushed up the pitch, and the sideways shift with the ball
AiPrep:
 LDA #$FE
 STA HCTRL0
 STA HCTRL1
 LDA HUMANS
 LSR
 BCC ApH2
 LDY CTRL1
 STY HCTRL0
ApH2:
 LSR
 BCC ApH3
 LDY CTRL2
 STY HCTRL1
ApH3:
 LDA FRAMECNT
 AND #$03
 CMP #$01
 BEQ ApTeam
 RTS
ApTeam:
 LDA OWNER
 TAY
 LDA #$FF
 CPY #NPL
 BCS ApOwn
 LDA TEAMOF,Y
ApOwn:
 STA Z_T2
 LDX #$01
ApT:
 TXA
 JSR AttDir
 STA TATT,X
 BNE ApL
 SEC
 LDA PXL+BALL
 SBC #<P_LEFT
 STA Z_T0
 LDA PXH+BALL
 SBC #>P_LEFT
 JMP ApBp
ApL:
 SEC
 LDA #<P_RIGHT
 SBC PXL+BALL
 STA Z_T0
 LDA #>P_RIGHT
 SBC PXH+BALL
ApBp:
 BPL ApBpOk
 LDA #$00
 STA Z_T0
ApBpOk:
 LSR
 ROR Z_T0
 STA Z_T1
 SEC
 LDA Z_T0
 SBC #100
 STA Z_T0
 LDA Z_T1
 SBC #$00
 STA Z_T1
 CPX Z_T2
 BNE ApNoPos
 CLC
 LDA Z_T0
 ADC #40
 STA Z_T0
 LDA Z_T1
 ADC #$00
 STA Z_T1
ApNoPos:
 LDA Z_T0
 STA TSHL,X
 LDA Z_T1
 STA TSHH,X
 DEX
 BPL ApT
 SEC
 LDA PYL+BALL
 SBC #<P_MIDY
 STA Z_T0
 LDA PYH+BALL
 SBC #>P_MIDY
 CMP #$80
 ROR
 STA YOFFH
 ROR Z_T0
 LDA Z_T0
 STA YOFFL
 RTS
ChooseChasers:
 LDA GSTATE
 BEQ CcPlay
 LDA #$FF
 STA CHASE0
 STA CHASE1
 RTS
// every 4 frames (whenever the deferred AI gets to run), the two teams
// in turn - not tied to the frame number, so neither team loses out
CcPlay:
 SEC
 LDA FRAMECNT
 SBC CC_LAST
 CMP #$04
 BCC CcRts
 LDA FRAMECNT
 STA CC_LAST
 LDA CC_TURN
 EOR #$01
 STA CC_TURN
 TAX
 LDA #$FF
 STA CHASE,X
 TXA
 JMP CcTeam
CcRts:
 RTS
CcTeam:
 STA Z_K
 LDY OWNER
 BMI CcFree
 LDA TEAMOF,Y
 CMP Z_K
 BEQ CcRts
CcFree:
 LDX Z_K
 LDA TEAMBASE,X
 CLC
 ADC #$01
 TAX
 LDA #$FF
 STA Z_T5
 STA Z_T6
 LDA #10
 STA Z_T7
CcL:
 LDY Z_K
 LDA HUMANS
 AND BITTAB,Y
 BEQ CcNh
 TXA
 CMP CTRL,Y
 BEQ CcN
CcNh:
 LDA PSTATE,X
 BNE CcN
 JSR DistToBall
 CMP Z_T5
 BCS CcN
 STA Z_T5
 STX Z_T6
CcN:
 INX
 DEC Z_T7
 BNE CcL
 LDY Z_K
 LDA HUMANS
 AND BITTAB,Y
 BEQ CcSet
 LDA Z_T5
 CMP #40
 BCC CcSet
 LDA #$FF
 STA Z_T6
CcSet:
 LDY Z_K
 LDA Z_T6
 STA CHASE,Y
 RTS
// steer X towards (Z_TX, Z_TY); A = speed index or $FF = jog/run by distance
Steer:
 STA Z_U3
 LDA Z_TX
 SEC
 SBC PXL,X
 STA Z_DX
 LDA Z_TXH
 SBC PXH,X
 STA Z_DXH
 LDA Z_TY
 SEC
 SBC PYL,X
 STA Z_DY
 LDA Z_TYH
 SBC PYH,X
 STA Z_DYH
 LDA #$02
 STA Z_U0
 LDA Z_DXH
 BPL StXp
 LDA #$00
 STA Z_U0
${neg16('Z_DX', 'Z_DXH')}
StXp:
 LDA Z_DXH
 BEQ StY
 LDA #$FF
 STA Z_DX
StY:
 LDA #$02
 STA Z_U1
 LDA Z_DYH
 BPL StYp
 LDA #$00
 STA Z_U1
${neg16('Z_DY', 'Z_DYH')}
StYp:
 LDA Z_DYH
 BNE StYsat
 LDA Z_DY
 BPL StY2
StYsat:
 LDA #$7F
StY2:
 ASL
 STA Z_DY
 LDA Z_DX
 CMP #$04
 BCS StGo
 LDA Z_DY
 CMP #$04
 BCS StGo
 LDA #$FF
 STA PMOVE,X
 RTS
StGo:
 LDA Z_DY
 ASL
 BCS StChkV
 CMP Z_DX
 BCS StChkV
 LDA #$01
 STA Z_U1
 JMP StDir
StChkV:
 LDA Z_DX
 ASL
 BCS StDir
 CMP Z_DY
 BCS StDir
 LDA #$01
 STA Z_U0
StDir:
 LDA Z_U1
 ASL
 ADC Z_U1
 ADC Z_U0
 TAY
 LDA DIRHV,Y
 STA PMOVE,X
 LDA Z_U3
 CMP #$FF
 BNE StSp
 LDA #$00
 LDY Z_DX
 CPY #48
 BCS StRun
 LDY Z_DY
 CPY #48
 BCC StSp
StRun:
 LDA #$02
StSp:
 STA PSPD,X
 RTS
// run at the ball, aiming 8 frames ahead of it
ChaseBall:
// aim 8 frames ahead of the ball (lead rounded the same both ways)
 CLC
 LDA VXL+BALL
 ADC #$10
 STA Z_T0
 LDA VXH+BALL
 ADC #$00
 ASL
 ASL
 ASL
 STA Z_T1
 LDA Z_T0
 LSR
 LSR
 LSR
 LSR
 LSR
 ORA Z_T1
 STA Z_T0
 LDY #$00
 CMP #$80
 BCC CbXp
 DEY
CbXp:
 CLC
 LDA PXL+BALL
 ADC Z_T0
 STA Z_TX
 TYA
 ADC PXH+BALL
 STA Z_TXH
 CLC
 LDA VYL+BALL
 ADC #$10
 STA Z_T0
 LDA VYH+BALL
 ADC #$00
 ASL
 ASL
 ASL
 STA Z_T1
 LDA Z_T0
 LSR
 LSR
 LSR
 LSR
 LSR
 ORA Z_T1
 STA Z_T0
 LDY #$00
 CMP #$80
 BCC CbYp
 DEY
CbYp:
 CLC
 LDA PYL+BALL
 ADC Z_T0
 STA Z_TY
 TYA
 ADC PYH+BALL
 STA Z_TYH
 LDA #$02
 JMP Steer
// formation place: role base distance from own goal, pushed up and down
// the pitch with the ball, spread across with it
FormationAI:
 LDY TEAMOF,X
 LDA TSHL,Y
 STA Z_T0
 LDA TSHH,Y
 STA Z_T1
 LDA TATT,Y
 STA Z_U2
 LDY ROLE,X
 STY Z_J
 LDY Z_J
 CLC
 LDA FDISTL,Y
 ADC Z_T0
 STA Z_T0
 LDA FDISTH,Y
 ADC Z_T1
 STA Z_T1
 BMI FaMin
 LDA Z_T0
 CMP FMINL,Y
 LDA Z_T1
 SBC FMINH,Y
 BCS FaMaxChk
FaMin:
 LDA FMINL,Y
 STA Z_T0
 LDA FMINH,Y
 STA Z_T1
 JMP FaX
FaMaxChk:
 LDA FMAXL,Y
 CMP Z_T0
 LDA FMAXH,Y
 SBC Z_T1
 BCS FaX
 LDA FMAXL,Y
 STA Z_T0
 LDA FMAXH,Y
 STA Z_T1
FaX:
 LDA Z_U2
 BNE FaXl
 CLC
 LDA #<P_LEFT
 ADC Z_T0
 STA Z_TX
 LDA #>P_LEFT
 ADC Z_T1
 STA Z_TXH
 JMP FaY
FaXl:
 SEC
 LDA #<P_RIGHT
 SBC Z_T0
 STA Z_TX
 LDA #>P_RIGHT
 SBC Z_T1
 STA Z_TXH
FaY:
 CLC
 LDA FYL,Y
 ADC YOFFL
 STA Z_TY
 LDA FYH,Y
 ADC YOFFH
 STA Z_TYH
 BMI FaYmin
 BNE FaYhi
 LDA Z_TY
 CMP #84
 BCS FaGo
FaYmin:
 LDA #84
 STA Z_TY
 LDA #$00
 STA Z_TYH
 JMP FaGo
FaYhi:
 LDA Z_TY
 CMP #$55
 BCC FaGo
 LDA #$54
 STA Z_TY
// at a restart the other team keeps its distance from the ball
FaGo:
 LDA GSTATE
 CMP #GS_RESTART
 BNE FaSteer
 LDA TEAMOF,X
 CMP RS_TEAM
 BEQ FaSteer
 SEC
 LDA Z_TX
 SBC PXL+BALL
 STA Z_T0
 LDA Z_TXH
 SBC PXH+BALL
 BEQ FaDxP
 CMP #$FF
 BNE FaSteer
 LDA Z_T0
 CMP #$C8
 BCC FaSteer
 BCS FaDy
FaDxP:
 LDA Z_T0
 CMP #56
 BCS FaSteer
FaDy:
 SEC
 LDA Z_TY
 SBC PYL+BALL
 STA Z_T0
 LDA Z_TYH
 SBC PYH+BALL
 BEQ FaDyP
 CMP #$FF
 BNE FaSteer
 LDA Z_T0
 CMP #$C8
 BCC FaSteer
 BCS FaPush
FaDyP:
 LDA Z_T0
 CMP #56
 BCS FaSteer
// too close: drop back 64 towards his own goal
FaPush:
 LDA Z_U2
 BNE FaPushR
 LDA #$C0
 JSR AddTX
 JMP FaSteer
FaPushR:
 LDA #$40
 JSR AddTX
FaSteer:
 LDA #$FF
 JMP Steer
// after a goal the scorer runs off, team-mates pile on
GoalCelebAI:
 LDA KO_TEAM
 EOR #$01
 STA Z_T2
 LDA TEAMOF,X
 CMP Z_T2
 BEQ GcMine
 JMP FormationAI
GcMine:
 CPX SCORER
 BNE GcHug
 LDA PXL,X
 STA Z_TX
 LDA PXH,X
 STA Z_TXH
 LDA #<330
 STA Z_TY
 LDA #>330
 STA Z_TYH
 LDA #$02
 JMP Steer
GcHug:
 LDY SCORER
 LDA PXL,Y
 STA Z_TX
 LDA PXH,Y
 STA Z_TXH
 LDA PYL,Y
 STA Z_TY
 LDA PYH,Y
 STA Z_TYH
 LDA #$02
 JMP Steer
// CPU player on the ball: dribble at goal, shoot in range, pass under pressure
CpuOwnerAI:
 LDA TEAMOF,X
 STA Z_K
 JSR AttDir
 STA Z_U2
 BNE CoL
 LDA #<(P_RIGHT+8)
 STA Z_TX
 LDA #>(P_RIGHT+8)
 STA Z_TXH
 JMP CoGd
CoL:
 LDA #<(P_LEFT-8)
 STA Z_TX
 LDA #>(P_LEFT-8)
 STA Z_TXH
// Z_S0 = distance to the goal line / 4 (max 255), Z_S1 = |y - middle|
CoGd:
 SEC
 LDA Z_TX
 SBC PXL,X
 STA Z_T0
 LDA Z_TXH
 SBC PXH,X
 STA Z_T1
 BPL CoGd1
${neg16('Z_T0', 'Z_T1')}
CoGd1:
 LSR Z_T1
 ROR Z_T0
 LSR Z_T1
 ROR Z_T0
 LDA Z_T0
 LDY Z_T1
 BEQ CoGd2
 LDA #$FF
CoGd2:
 STA Z_S0
 SEC
 LDA PYL,X
 SBC #<P_MIDY
 STA Z_T0
 LDA PYH,X
 SBC #>P_MIDY
 BPL CoAy
 LDA #$00
 SEC
 SBC Z_T0
 STA Z_T0
CoAy:
 LDA Z_T0
 STA Z_S1
// run along his lane; near the goal cut inside; plus a drift
 LDA PYL,X
 STA Z_TY
 LDA PYH,X
 STA Z_TYH
 LDA Z_S0
 CMP #75
 BCS CoLane
 SEC
 LDA #<P_MIDY
 SBC PYL,X
 STA Z_T0
 LDA #>P_MIDY
 SBC PYH,X
 CMP #$80
 ROR
 ROR Z_T0
 CMP #$80
 ROR
 ROR Z_T0
 STA Z_T1
 CLC
 LDA Z_TY
 ADC Z_T0
 STA Z_TY
 LDA Z_TYH
 ADC Z_T1
 STA Z_TYH
CoLane:
 LDY Z_K
 LDA DRIFT,Y
 JSR AddTY
// stay off the touchlines
 LDA Z_TYH
 BNE CoYhi
 LDA Z_TY
 CMP #P_TOP+14
 BCS CoDec
 LDA #P_TOP+14
 STA Z_TY
 JMP CoDec
CoYhi:
 LDA Z_TY
 CMP #<(P_BOT-14)
 BCC CoDec
 LDA #<(P_BOT-14)
 STA Z_TY
// decisions every 8 frames (not while two redraw slices are due)
CoDec:
 LDA RD_BUSY
 CMP #$02
 BCS CoMove
 LDA FRAMECNT
 AND #$07
 CMP #$02
 BNE CoMove
// in shooting range and not too wide: shoot (or lay it off)
 LDA Z_S0
 CMP #46
 BCS CoNoShot
 LDA Z_S1
 CMP #80
 BCS CoNoShot
 JSR Rand
 CMP #185
 BCS CoPass
 JSR Rand
 AND #$07
 CLC
 ADC #$05
 JMP Shoot
// wide near the box: cross it
CoNoShot:
 LDA Z_S0
 CMP #62
 BCS CoMid
 LDA Z_S1
 CMP #64
 BCC CoMid
 JSR Rand
 CMP #120
 BCS CoMid
 JMP DoCross
// pressed: in his own half clear it, otherwise pass
CoMid:
 JSR Pressure
 BCC CoFree
 LDA Z_S0
 CMP #140
 BCC CoPress
 JSR Rand
 CMP #140
 BCS CoPress
 JMP DoClear
CoPress:
 JSR Rand
 CMP #80
 BCS CoSwerve
CoPass:
 JMP DoPassCpu
CoFree:
 JSR Rand
 CMP #8
 BCC CoPass
 CMP #60
 BCS CoMove
CoSwerve:
 LDA #$1F
 JSR RandSym
 LDY Z_K
 STA DRIFT,Y
CoMove:
 LDA #$01
 JMP Steer
// A = signed offset added to Z_TY / Z_TX
AddTY:
 LDY #$00
 CMP #$80
 BCC AtyP
 DEY
AtyP:
 CLC
 ADC Z_TY
 STA Z_TY
 TYA
 ADC Z_TYH
 STA Z_TYH
 RTS
AddTX:
 LDY #$00
 CMP #$80
 BCC AtxP
 DEY
AtxP:
 CLC
 ADC Z_TX
 STA Z_TX
 TYA
 ADC Z_TXH
 STA Z_TXH
 RTS
// C=1 if an opponent of X is within 28
Pressure:
 LDA TEAMOF,X
 EOR #$01
 TAY
 LDA TEAMBASE,Y
 TAY
 LDA #11
 STA Z_S3
// opponent inside a 55 x 55 box around him?
PrL:
 LDA PXL,Y
 SEC
 SBC PXL,X
 STA Z_T0
 LDA PXH,Y
 SBC PXH,X
 BEQ PrXp
 CMP #$FF
 BNE PrNext
 LDA Z_T0
 CMP #$E5
 BCC PrNext
 BCS PrY
PrXp:
 LDA Z_T0
 CMP #28
 BCS PrNext
PrY:
 LDA PYL,Y
 SEC
 SBC PYL,X
 STA Z_T0
 LDA PYH,Y
 SBC PYH,X
 BEQ PrYp
 CMP #$FF
 BNE PrNext
 LDA Z_T0
 CMP #$E5
 BCS PrYes
 BCC PrNext
PrYp:
 LDA Z_T0
 CMP #28
 BCC PrYes
PrNext:
 INY
 DEC Z_S3
 BNE PrL
 CLC
 RTS
PrYes:
 SEC
 RTS
// ---- goalkeepers
KeeperAI:
 LDA PSTATE,X
 CMP #ST_HOLD
 BEQ KaHold
 CMP #ST_NORMAL
 BEQ KaNorm
 RTS
KaHold:
 CPX OWNER
 BNE KaRts
 DEC PTIMER,X
 BNE KaRts
 LDA #ST_NORMAL
 STA PSTATE,X
 JSR Rand
 CMP #120
 BCS KaPunt
 JMP DoPassCpu
KaPunt:
 JMP DoLongKick
KaRts:
 RTS
KaNorm:
 CPX OWNER
 BNE KaNo
 LDA #ST_HOLD
 STA PSTATE,X
 LDA #60
 STA PTIMER,X
 JMP ZeroVel
KaNo:
 LDA GSTATE
 BNE KaStd
 LDA SHOT_GOAL
 BPL KaNear
 JSR DistToBall
 CMP #$FF
 BNE KaNear
 LDA FRAMECNT
 AND #$06
 BEQ KaNear
 RTS
KaNear:
 LDA TEAMOF,X
 STA Z_K
 CMP ATT0
 BEQ KaLeft
 LDA #$01
 JMP KaS
KaLeft:
 LDA #$00
KaS:
 STA Z_U2
 LDA SHOT_GOAL
 CMP Z_U2
 BNE KaPos
 LDA SHOT_REACT
 BEQ KaPos
 DEC SHOT_REACT
 BNE KaPos
 SEC
 LDA PRED_Y
 SBC PYL,X
 STA Z_T0
 LDA PRED_Y+1
 SBC PYH,X
 STA Z_T1
 BMI KaDn
 BNE KaDiveDown
 LDA Z_T0
 CMP #11
 BCC KaPos
KaDiveDown:
 LDA #$02
 JMP KaDive
KaDn:
 LDA Z_T1
 CMP #$FF
 BNE KaDiveUp
 LDA Z_T0
 CMP #$F6
 BCS KaPos
KaDiveUp:
 LDA #$FE
KaDive:
 STA VYH,X
 LDA #$00
 STA VYL,X
 STA VXL,X
 STA VXH,X
 LDA #ST_DIVE
 STA PSTATE,X
 LDA #22
 STA PTIMER,X
 RTS
KaPos:
 JSR DistToBall
 CMP #64
 BCS KaStd
 LDA Z_U2
 BNE KaBoxR
 LDA PXH+BALL
 BNE KaStd
 LDA PXL+BALL
 CMP #<(P_LEFT+132)
 BCS KaStd
 JMP KaRush
KaBoxR:
 LDA PXH+BALL
 CMP #$03
 BCC KaStd
 LDA PXL+BALL
 CMP #<(P_RIGHT-132)
 BCC KaStd
KaRush:
 LDY OWNER
 BMI KaRu2
 LDA TEAMOF,Y
 CMP Z_K
 BEQ KaStd
KaRu2:
 JMP ChaseBall
KaStd:
 LDA TEAMOF,X
 CMP ATT0
 BNE KaTr
 LDA #<(P_LEFT+14)
 STA Z_TX
 LDA #>(P_LEFT+14)
 STA Z_TXH
 JMP KaTy
KaTr:
 LDA #<(P_RIGHT-14)
 STA Z_TX
 LDA #>(P_RIGHT-14)
 STA Z_TXH
KaTy:
 SEC
 LDA PYL+BALL
 SBC #<P_MIDY
 STA Z_T0
 LDA PYH+BALL
 SBC #>P_MIDY
 STA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 BMI KaTyN
 LDA Z_T0
 CMP #18
 BCC KaTyOk
 LDA #18
 JMP KaTyOk
KaTyN:
 LDA Z_T0
 CMP #$EE
 BCS KaTyOk
 LDA #$EE
KaTyOk:
 CLC
 ADC #P_MIDY
 STA Z_TY
 LDA #$00
 STA Z_TYH
 LDA #$FF
 JMP Steer
`;

export const BALL = `
// ----------------------------------------------------------------- ball
BallUpdate:
 LDA OWNER
 BMI BuFree
 JSR AttachBall
 JSR TackleChecks
 JMP CheckGoalOut
BuFree:
 JSR BallLoose
 JSR KeeperCatch
 LDA OWNER
 BPL BuChk
 JSR Pickups
BuChk:
 JMP CheckGoalOut
AttachIfOwned:
 LDA OWNER
 BMI AioR
 JMP AttachBall
AioR:
 RTS
BallLoose:
 LDX #BALL
 JSR Integrate
 CLC
 LDA BZL
 ADC BVZL
 STA BZL
 LDA BZH
 ADC BVZH
 STA BZH
 SEC
 LDA BVZL
 SBC #GRAV
 STA BVZL
 LDA BVZH
 SBC #$00
 STA BVZH
 LDA BZH
 BPL BlAir
 LDA #$00
 STA BZL
 STA BZH
 SEC
 LDA #$00
 SBC BVZL
 STA Z_T0
 LDA #$00
 SBC BVZH
 STA Z_T1
 BNE BlBounce
 LDA Z_T0
 CMP #$A0
 BCS BlBounce
 LDA #$00
 STA BVZL
 STA BVZH
 JMP BlGround
BlBounce:
 LSR Z_T1
 ROR Z_T0
 LDA Z_T0
 STA BVZL
 LDA Z_T1
 STA BVZH
 LDA #FX_BOUNCE
 JSR SfxPlay
 JMP BlGround
BlAir:
 ORA BZL
 BNE BlSpin
BlGround:
 LDX #BALL
 JSR Friction
BlSpin:
 LDA VXH+BALL
 ORA VYH+BALL
 BNE BlSp1
 LDA VXL+BALL
 ORA VYL+BALL
 CMP #$30
 BCC BlSpDone
BlSp1:
 INC BANIM
BlSpDone:
 LDA BANIM
 LSR
 LSR
 AND #$03
 TAY
 LDA BALLFR,Y
 STA BFRAME
// keep the ball on the map
 LDA PXH+BALL
 BMI BbX0
 BNE BbXh
 LDA PXL+BALL
 CMP #16
 BCS BbY
BbX0:
 LDA #16
 STA PXL+BALL
 LDA #$00
 STA PXH+BALL
 STA VXL+BALL
 STA VXH+BALL
 JMP BbY
BbXh:
 CMP #$03
 BCC BbY
 BNE BbX1
 LDA PXL+BALL
 CMP #$F0
 BCC BbY
BbX1:
 LDA #$F0
 STA PXL+BALL
 LDA #$03
 STA PXH+BALL
 LDA #$00
 STA VXL+BALL
 STA VXH+BALL
BbY:
 LDA PYH+BALL
 BMI BbY0
 BNE BbYh
 LDA PYL+BALL
 CMP #44
 BCS BbRts
BbY0:
 LDA #44
 STA PYL+BALL
 LDA #$00
 STA PYH+BALL
 STA VYL+BALL
 STA VYH+BALL
 RTS
BbYh:
 CMP #$01
 BNE BbY1
 LDA PYL+BALL
 CMP #$74
 BCC BbRts
BbY1:
 LDA #$74
 STA PYL+BALL
 LDA #$01
 STA PYH+BALL
 LDA #$00
 STA VYL+BALL
 STA VYH+BALL
BbRts:
 RTS
// V -= V/64 on both axes; tiny speeds stop
// Z_T1:Z_T0 >>= 6
FrSh:
 LDY #$06
FrShL:
 LSR Z_T1
 ROR Z_T0
 DEY
 BNE FrShL
 RTS
Friction:
// X: |v| -= |v| / 64 (same both ways)
 LDA VXH,X
 BMI FrXn
 STA Z_T1
 LDA VXL,X
 STA Z_T0
 JSR FrSh
 SEC
 LDA VXL,X
 SBC Z_T0
 STA VXL,X
 LDA VXH,X
 SBC Z_T1
 STA VXH,X
 JMP FrXd
FrXn:
 LDA #$00
 SEC
 SBC VXL,X
 STA Z_T0
 LDA #$00
 SBC VXH,X
 STA Z_T1
 JSR FrSh
 CLC
 LDA VXL,X
 ADC Z_T0
 STA VXL,X
 LDA VXH,X
 ADC Z_T1
 STA VXH,X
FrXd:
// Y: |v| -= |v| / 64 (same both ways)
 LDA VYH,X
 BMI FrYn
 STA Z_T1
 LDA VYL,X
 STA Z_T0
 JSR FrSh
 SEC
 LDA VYL,X
 SBC Z_T0
 STA VYL,X
 LDA VYH,X
 SBC Z_T1
 STA VYH,X
 JMP FrYd
FrYn:
 LDA #$00
 SEC
 SBC VYL,X
 STA Z_T0
 LDA #$00
 SBC VYH,X
 STA Z_T1
 JSR FrSh
 CLC
 LDA VYL,X
 ADC Z_T0
 STA VYL,X
 LDA VYH,X
 ADC Z_T1
 STA VYH,X
FrYd:
 LDA VXH,X
 BEQ FrXp
 CMP #$FF
 BNE FrYk
 LDA VXL,X
 CMP #$E8
 BCC FrYk
 BCS FrXz
FrXp:
 LDA VXL,X
 CMP #$18
 BCS FrYk
FrXz:
 LDA #$00
 STA VXL,X
 STA VXH,X
FrYk:
 LDA VYH,X
 BEQ FrYp
 CMP #$FF
 BNE FrRts
 LDA VYL,X
 CMP #$E8
 BCC FrRts
 BCS FrYz
FrYp:
 LDA VYL,X
 CMP #$18
 BCS FrRts
FrYz:
 LDA #$00
 STA VYL,X
 STA VYH,X
FrRts:
 RTS
// in the net after a goal: stop at the back of the net
NetClamp:
 LDA GOALSIDE
 BNE NcR
 LDA PXH+BALL
 BNE NcY
 LDA PXL+BALL
 CMP #<(P_LEFT-14)
 BCS NcY
 LDA #<(P_LEFT-14)
 STA PXL+BALL
 JMP NcStop
NcR:
 LDA PXH+BALL
 CMP #$03
 BCC NcY
 LDA PXL+BALL
 CMP #<(P_RIGHT+14)
 BCC NcY
 LDA #<(P_RIGHT+14)
 STA PXL+BALL
NcStop:
 LDA #$00
 STA VXL+BALL
 STA VXH+BALL
 STA VYL+BALL
 STA VYH+BALL
NcY:
 RTS
// ball at the owner's feet (in the hands when holding / throwing)
AttachBall:
 LDX OWNER
 LDY PDIR,X
 LDA PSTATE,X
 CMP #ST_HOLD
 BEQ AbHand
 CMP #ST_WAIT
 BNE AbFeet
 LDA RS_TYPE
 CMP #RS_THROW
 BNE AbFeet
 LDA #17
 STA BZH
 JMP AbHand2
AbHand:
 LDA #$08
 STA BZH
AbHand2:
 LDA PXL,X
 STA PXL+BALL
 LDA PXH,X
 STA PXH+BALL
 CLC
 LDA PYL,X
 ADC #$01
 STA PYL+BALL
 LDA PYH,X
 ADC #$00
 STA PYH+BALL
 JMP AbVel
AbFeet:
 LDA #$00
 STA BZH
 LDA DRIBX,Y
 STA Z_T0
 LDA #$00
 LDY Z_T0
 BPL AbXp
 LDA #$FF
AbXp:
 STA Z_T1
 CLC
 LDA PXL,X
 ADC Z_T0
 STA PXL+BALL
 LDA PXH,X
 ADC Z_T1
 STA PXH+BALL
 LDY PDIR,X
 LDA DRIBY,Y
 STA Z_T0
 LDA #$00
 LDY Z_T0
 BPL AbYp
 LDA #$FF
AbYp:
 STA Z_T1
 CLC
 LDA PYL,X
 ADC Z_T0
 STA PYL+BALL
 LDA PYH,X
 ADC Z_T1
 STA PYH+BALL
AbVel:
 JSR SyncVel
 LDA VXL,X
 STA VXL+BALL
 LDA VXH,X
 STA VXH+BALL
 LDA VYL,X
 STA VYL+BALL
 LDA VYH,X
 STA VYH+BALL
 LDA #$00
 STA PXF+BALL
 STA PYF+BALL
 STA BVZL
 STA BVZH
 STA BZL
 LDA VXL,X
 ORA VXH,X
 ORA VYL,X
 ORA VYH,X
 BEQ AbR
 INC BANIM
 LDA BANIM
 LSR
 LSR
 AND #$03
 TAY
 LDA BALLFR,Y
 STA BFRAME
AbR:
 RTS
// opponents next to the ball win it (sliders always do)
TackleChecks:
 LDA GSTATE
 BNE TcRts
 LDX OWNER
 LDA PSTATE,X
 CMP #ST_HOLD
 BEQ TcRts
 CMP #ST_WAIT
 BEQ TcRts
 LDA TEAMOF,X
 STA Z_K
 TAY
 LDA #12
 STA Z_U3
 LDA HUMANS
 AND BITTAB,Y
 BEQ TcOpp
 TXA
 CMP CTRL,Y
 BNE TcOpp
 LDA #$06
 STA Z_U3
TcOpp:
 LDA Z_K
 EOR #$01
 STA Z_U2
 TAY
 LDA TEAMBASE,Y
 CLC
 ADC #$01
 TAX
 LDA #10
 STA Z_T7
TcL:
 LDA PXL,X
 SEC
 SBC PXL+BALL
 CLC
 ADC #16
 CMP #32
 BCS TcN
 LDA PCOOL,X
 BNE TcN
 LDA PSTATE,X
 BEQ TcNorm
 CMP #ST_SLIDE
 BNE TcN
 LDA #14
 STA Z_S0
 LDA #$08
 STA Z_S1
 JSR NearBall
 BCC TcN
 JMP SlidePoke
TcNorm:
 LDA #10
 STA Z_S0
 LDA #$06
 STA Z_S1
 JSR NearBall
 BCC TcN
 LDA Z_U3
 STA Z_T6
 LDY Z_U2
 LDA HUMANS
 AND BITTAB,Y
 BEQ TcRoll
 TXA
 CMP CTRL,Y
 BNE TcRoll
 LDA #24
 STA Z_T6
TcRoll:
 JSR Rand
 CMP Z_T6
 BCS TcN
 JMP Steal
TcN:
 INX
 DEC Z_T7
 BNE TcL
TcRts:
 RTS
Steal:
 LDY OWNER
 LDA #30
 STA PCOOL,Y
 LDA #ST_KICK
 STA PSTATE,Y
 LDA #10
 STA PTIMER,Y
 LDA #$00
 STA VXL,Y
 STA VXH,Y
 STA VYL,Y
 STA VYH,Y
 STX OWNER
 STX LASTTOUCH
 LDA #$FF
 STA PASS_TO
 JSR GainBall
 LDA #FX_TACKLE
 JMP SfxPlay
// X = slider: the ball squirts away, its owner goes down
SlidePoke:
 LDY OWNER
 BMI SpFree
 LDA #ST_FALLEN
 STA PSTATE,Y
 LDA #40
 STA PTIMER,Y
 STA PCOOL,Y
 LDA #$00
 STA VXL,Y
 STA VXH,Y
 STA VYL,Y
 STA VYH,Y
SpFree:
 LDA #$FF
 STA OWNER
 STA PASS_TO
 STX LASTTOUCH
 LDA VXH,X
 CMP #$80
 LDA VXH,X
 ROR
 STA Z_T1
 LDA VXL,X
 ROR
 CLC
 ADC VXL,X
 STA VXL+BALL
 LDA Z_T1
 ADC VXH,X
 STA VXH+BALL
 LDA VYH,X
 CMP #$80
 LDA VYH,X
 ROR
 STA Z_T1
 LDA VYL,X
 ROR
 CLC
 ADC VYL,X
 STA VYL+BALL
 LDA Z_T1
 ADC VYH,X
 STA VYH+BALL
 LDA #$80
 STA BVZL
 LDA #$00
 STA BVZH
 LDA #16
 STA PCOOL,X
 LDA #$00
 STA GK_TRIED
 LDA #FX_TACKLE
 JMP SfxPlay
// a loose ball near a player's feet becomes his
Pickups:
 LDA BZH
 CMP #14
 BCS PkRts
 LDA FRAMECNT
 LSR
 BCC PkUp
 LDX #NPL-1
PkDn:
 JSR PkOne
 BCS PkRts
 DEX
 BPL PkDn
 RTS
PkUp:
 LDX #$00
PkUl:
 JSR PkOne
 BCS PkRts
 INX
 CPX #NPL
 BNE PkUl
PkRts:
 RTS
// X = player: C=1 if he took (or poked) the ball
PkOne:
 LDA PXL,X
 SEC
 SBC PXL+BALL
 CLC
 ADC #16
 CMP #32
 BCS PkN
 LDA PYL,X
 SEC
 SBC PYL+BALL
 CLC
 ADC #12
 CMP #24
 BCS PkN
 LDA PCOOL,X
 BNE PkN
 LDA PSTATE,X
 BEQ PkNorm
 CMP #ST_SLIDE
 BNE PkN
 LDA #14
 STA Z_S0
 LDA #$08
 STA Z_S1
 JSR NearBall
 BCC PkN
 JSR SlidePoke
 SEC
 RTS
PkNorm:
 LDA #$08
 STA Z_S0
 LDA #$05
 STA Z_S1
 JSR NearBall
 BCC PkN
 STX OWNER
 STX LASTTOUCH
 LDA #$FF
 STA PASS_TO
 STA SHOT_GOAL
 LDA #$00
 STA GK_TRIED
 JSR GainBall
 LDA #FX_BOUNCE
 JSR SfxPlay
 SEC
 RTS
PkN:
 CLC
 RTS
// X = new owner: human control follows the ball; keepers hold it
GainBall:
 LDA TEAMOF,X
 TAY
 LDA HUMANS
 AND BITTAB,Y
 BEQ GbK
 TXA
 STA CTRL,Y
GbK:
 LDA ROLE,X
 BNE GbR
 LDA #ST_HOLD
 STA PSTATE,X
 LDA #60
 STA PTIMER,X
 JSR ZeroVel
 LDA TEAMOF,X
 TAY
 LDA HUMANS
 AND BITTAB,Y
 BEQ GbR
 LDA #200
 STA PTIMER,X
GbR:
 RTS
// keepers try once per shot: catch, or parry it back out
KeeperCatch:
 LDA GK_TRIED
 BNE KcRts
 LDA BZH
 CMP #26
 BCS KcRts
 LDX #$00
 JSR KcOne
 LDA OWNER
 BPL KcRts
 LDA GK_TRIED
 BNE KcRts
 LDX #11
 JSR KcOne
KcRts:
 RTS
KcOne:
 LDA PCOOL,X
 BNE KcRts
 LDA #11
 STA Z_S0
 STA Z_S1
 LDA PSTATE,X
 BEQ KcN
 CMP #ST_DIVE
 BNE KcRts
 LDA #13
 STA Z_S0
 LDA #19
 STA Z_S1
KcN:
 JSR NearBall
 BCC KcRts
 LDA #$01
 STA GK_TRIED
 LDA #215
 LDY PSTATE,X
 BEQ KcC1
 LDA #160
KcC1:
 STA Z_T6
 LDA VXH+BALL
 BPL KcAbs
 EOR #$FF
KcAbs:
 CMP #$04
 BCC KcRoll
 LDA Z_T6
 SEC
 SBC #70
 STA Z_T6
KcRoll:
 JSR Rand
 CMP Z_T6
 BCS KcParry
 STX OWNER
 STX LASTTOUCH
 LDA #$FF
 STA SHOT_GOAL
 STA PASS_TO
 JSR GainBall
 LDA #MSG_SAVED
 JSR ShowMsg
 LDA #FX_CATCH
 JMP SfxPlay
// parry: half the time tipped round the post (corner), else pushed out
KcParry:
 JSR Rand
 BMI KcTip
${neg16('VXL+BALL', 'VXH+BALL')}
KcTip:
 LDA VXH+BALL
 CMP #$80
 ROR VXH+BALL
 ROR VXL+BALL
 LDA VXH+BALL
 CMP #$80
 ROR VXH+BALL
 ROR VXL+BALL
 LDA #$C0
 STA VYL+BALL
 LDA #$01
 STA VYH+BALL
 JSR Rand
 BPL KcPy
 LDA #$40
 STA VYL+BALL
 LDA #$FE
 STA VYH+BALL
KcPy:
 LDA #$80
 STA BVZL
 LDA #$01
 STA BVZH
 LDA #20
 STA PCOOL,X
 STX LASTTOUCH
 LDA #$FF
 STA SHOT_GOAL
 LDA #MSG_SAVED
 JSR ShowMsg
 LDA #FX_BOUNCE
 JMP SfxPlay
`;

export const KICKS = `
// ----------------------------------------------------------------- kicks
// X = kicker; aim the ball at (Z_TX, Z_TY) at speed Z_SPD (8.8) with
// lift Z_VZ (8.8). Vertical pitch distances count double (foreshortening).
Kick:
 LDA #$01
 STA KICKED
 STX Z_J
 SEC
 LDA Z_TX
 SBC PXL+BALL
 STA Z_DX
 LDA Z_TXH
 SBC PXH+BALL
 STA Z_DXH
 SEC
 LDA Z_TY
 SBC PYL+BALL
 STA Z_DY
 LDA Z_TYH
 SBC PYH+BALL
 STA Z_DYH
 LDA Z_DXH
 STA Z_S2
 BPL KkAx
${neg16('Z_DX', 'Z_DXH')}
KkAx:
 LDA Z_DYH
 STA Z_S3
 BPL KkAy
${neg16('Z_DY', 'Z_DYH')}
KkAy:
 ASL Z_DY
 ROL Z_DYH
KkScale:
 LDA Z_DXH
 ORA Z_DYH
 BNE KkShr
 LDA Z_DX
 ORA Z_DY
 BPL KkScaled
KkShr:
 LSR Z_DXH
 ROR Z_DX
 LSR Z_DYH
 ROR Z_DY
 JMP KkScale
KkScaled:
 LDA Z_DX
 ORA Z_DY
 BNE KkNz
 LDA #$01
 STA Z_DX
KkNz:
 LDA Z_DX
 CMP Z_DY
 BCS KkMx
 LDA Z_DX
 STA Z_T0
 LDA Z_DY
 STA Z_T1
 JMP KkL
KkMx:
 LDA Z_DY
 STA Z_T0
 LDA Z_DX
 STA Z_T1
KkL:
 LDA Z_T0
 LSR
 STA Z_T2
 LSR
 LSR
 STA Z_T3
 LDA Z_T2
 SEC
 SBC Z_T3
 CLC
 ADC Z_T1
 STA Z_T4
 LDA Z_SPD
 STA Z_A0
 LDA Z_SPDH
 STA Z_A1
 LDA Z_DX
 STA Z_A2
 LDA Z_T4
 STA Z_A3
 JSR MulDiv
 LDA Z_S2
 BPL KkVxP
${neg16('Z_R0', 'Z_R1')}
KkVxP:
 LDA Z_R0
 STA VXL+BALL
 LDA Z_R1
 STA VXH+BALL
 LDA Z_SPD
 STA Z_A0
 LDA Z_SPDH
 STA Z_A1
 LDA Z_DY
 STA Z_A2
 LDA Z_T4
 STA Z_A3
 JSR MulDiv
 LSR Z_R1
 ROR Z_R0
 LDA Z_S3
 BPL KkVyP
${neg16('Z_R0', 'Z_R1')}
KkVyP:
 LDA Z_R0
 STA VYL+BALL
 LDA Z_R1
 STA VYH+BALL
 LDA Z_VZ
 STA BVZL
 LDA Z_VZH
 STA BVZH
 LDA #$00
 STA BZL
 STA BZH
 STA GK_TRIED
 LDX Z_J
 LDA #$FF
 STA OWNER
 STA SHOT_GOAL
 STX LASTTOUCH
 LDA #14
 STA PCOOL,X
 LDA #ST_KICK
 STA PSTATE,X
 LDA #$08
 STA PTIMER,X
 JSR ZeroVel
 JSR PickFrame
 LDA #FX_KICK
 JSR SfxPlay
 LDX Z_J
 RTS
// X = passer, Y = receiver: lead the receiver, pace by distance
PassTo:
 STY Z_U0
 STX Z_U1
 TYA
 TAX
 JSR SyncVel
 LDX Z_U1
 LDY Z_U0
 LDA VXL,Y
 STA Z_T0
 LDA VXH,Y
 STA Z_T1
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 CLC
 LDA PXL,Y
 ADC Z_T0
 STA Z_TX
 LDA PXH,Y
 ADC Z_T1
 STA Z_TXH
 LDA VYL,Y
 STA Z_T0
 LDA VYH,Y
 STA Z_T1
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 CLC
 LDA PYL,Y
 ADC Z_T0
 STA Z_TY
 LDA PYH,Y
 ADC Z_T1
 STA Z_TYH
 JSR DistXY
 STA Z_T0
 ASL
 STA Z_SPD
 LDA #$02
 ADC #$00
 STA Z_SPDH
 LDA #$00
 STA Z_VZ
 STA Z_VZH
 LDA Z_T0
 CMP #170
 BCC PtGround
 LDA #$C0
 STA Z_VZ
PtGround:
 LDX Z_U1
 CPX HCTRL0
 BEQ PtKick
 CPX HCTRL1
 BEQ PtKick
 LDA #$07
 JSR RandSym
 JSR AddTX
 LDA #$07
 JSR RandSym
 JSR AddTY
 LDX Z_U1
PtKick:
 JSR Kick
 LDY Z_U0
 STY PASS_TO
 LDA TEAMOF,Y
 TAX
 LDA HUMANS
 AND BITTAB,X
 BEQ PtR
 TYA
 STA CTRL,X
PtR:
 RTS
// X = passer
DoPass:
 LDA TEAMOF,X
 TAY
 LDA HUMANS
 AND BITTAB,Y
 BEQ DoPassCpu
 TXA
 CMP CTRL,Y
 BNE DoPassCpu
 JMP DoPassHuman
DoPassCpu:
 JSR CpuPassTarget
 BMI DpFwd
 JMP PassTo
DpFwd:
 JMP KickForward
// best forward option, with a little randomness: Y = receiver or $FF
CpuPassTarget:
 STX Z_U1
 LDA TEAMOF,X
 STA Z_K
 JSR AttDir
 STA Z_U2
 LDX Z_K
 LDA TEAMBASE,X
 CLC
 ADC #$01
 TAY
 LDA #10
 STA Z_U3
 LDA #$FF
 STA Z_T6
 LDA #$00
 STA Z_T7
CpL:
 CPY Z_U1
 BEQ CpN
 STY Z_T5
 LDX Z_U1
 JSR DistXY
 CMP #36
 BCC CpN2
 CMP #230
 BCS CpN2
 LDY Z_T5
 LDX Z_U1
 SEC
 LDA PXL,Y
 SBC PXL,X
 STA Z_T0
 LDA PXH,Y
 SBC PXH,X
 STA Z_T1
 LDA Z_U2
 BEQ CpF
${neg16('Z_T0', 'Z_T1')}
CpF:
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 CMP #$80
 ROR Z_T1
 ROR Z_T0
 LDA Z_T1
 BMI CpNg
 BNE CpMax
 LDA Z_T0
 CMP #$80
 BCS CpMax
 ORA #$80
 JMP CpSc
CpMax:
 LDA #$FF
 JMP CpSc
CpNg:
 CMP #$FF
 BNE CpN2
 LDA Z_T0
 CMP #$F4
 BCC CpN2
 EOR #$80
// + width: |dy| / 4 (switching play), + a little luck
CpSc:
 STA Z_T2
 LDY Z_T5
 LDX Z_U1
 SEC
 LDA PYL,Y
 SBC PYL,X
 BCS CpDy
 EOR #$FF
 ADC #$01
CpDy:
 LSR
 LSR
 CLC
 ADC Z_T2
 BCC CpDy2
 LDA #$FF
CpDy2:
 STA Z_T2
 JSR Rand
 AND #$1F
 CLC
 ADC Z_T2
 BCC CpS2
 LDA #$FF
CpS2:
 CMP Z_T7
 BCC CpN2
 STA Z_T7
 LDA Z_T5
 STA Z_T6
CpN2:
 LDY Z_T5
CpN:
 INY
 DEC Z_U3
 BNE CpL
 LDX Z_U1
 LDY Z_T6
 RTS
// human pass: the team-mate closest to the facing direction
DoPassHuman:
 STX Z_U1
 LDY PDIR,X
 LDA DIRCX,Y
 STA Z_U2
 LDA DIRCY,Y
 STA Z_U3
 LDA #$FF
 STA Z_T6
 STA Z_T7
 STA Z_A0
 STA Z_A1
 LDA TEAMOF,X
 TAY
 LDA TEAMBASE,Y
 STA Z_T5
 LDA #11
 STA Z_K
DhL:
 LDY Z_T5
 CPY Z_U1
 BNE DhGo
 JMP DhN
// remember the nearest team-mate too (fallback when nobody is in the cone)
DhGo:
 LDX Z_U1
 JSR DistXY
 CMP Z_A0
 BCS DhFar
 STA Z_A0
 LDA Z_T5
 STA Z_A1
DhFar:
 LDY Z_T5
 LDX Z_U1
 SEC
 LDA PXL,Y
 SBC PXL,X
 STA Z_DX
 LDA PXH,Y
 SBC PXH,X
 STA Z_DXH
 SEC
 LDA PYL,Y
 SBC PYL,X
 STA Z_DY
 LDA PYH,Y
 SBC PYH,X
 STA Z_DYH
 ASL Z_DY
 ROL Z_DYH
 LDA #$00
 STA Z_S0
 STA Z_S1
 STA Z_S2
 STA Z_S3
${accSigned('Z_S0', 'Z_S1', 'Z_DX', 'Z_DXH', 'Z_U2', false)}
${accSigned('Z_S0', 'Z_S1', 'Z_DY', 'Z_DYH', 'Z_U3', false)}
${accSigned('Z_S2', 'Z_S3', 'Z_DX', 'Z_DXH', 'Z_U3', false)}
${accSigned('Z_S2', 'Z_S3', 'Z_DY', 'Z_DYH', 'Z_U2', true)}
 LDA Z_S1
 BMI DhN2
 BNE DhPok
 LDA Z_S0
 CMP #16
 BCC DhN2
DhPok:
 LDA Z_S3
 BPL DhPp
${neg16('Z_S2', 'Z_S3')}
DhPp:
 LDA Z_S2
 CMP Z_S0
 LDA Z_S3
 SBC Z_S1
 BCS DhN2
 LSR Z_S1
 ROR Z_S0
 LSR Z_S1
 ROR Z_S0
 CLC
 LDA Z_S2
 ADC Z_S0
 STA Z_S2
 LDA Z_S3
 ADC Z_S1
 BNE DhN2
 LDA Z_S2
 CMP Z_T7
 BCS DhN2
 STA Z_T7
 LDA Z_T5
 STA Z_T6
DhN2:
DhN:
 INC Z_T5
 DEC Z_K
 BEQ DhDone
 JMP DhL
DhDone:
 LDX Z_U1
 LDY Z_T6
 BPL DhTo
 LDY Z_A1
 BMI DhFwd
DhTo:
 JMP PassTo
DhFwd:
 JMP KickForward
// X = kicker, A = power 0-15: shoot in range, else a long ball
DoShootOrLong:
 STA SHOT_P
 LDA TEAMOF,X
 JSR AttDir
 BNE DslL
 SEC
 LDA #<P_RIGHT
 SBC PXL,X
 STA Z_T0
 LDA #>P_RIGHT
 SBC PXH,X
 JMP DslC
DslL:
 SEC
 LDA PXL,X
 SBC #<P_LEFT
 STA Z_T0
 LDA PXH,X
 SBC #>P_LEFT
DslC:
 BMI DslShoot
 BEQ DslShoot
 CMP #$01
 BNE DslLong
 LDA Z_T0
 CMP #$4A
 BCS DslLong
DslShoot:
 LDA SHOT_P
 JMP Shoot
DslLong:
 JMP LongBall
// X = shooter, A = power 0-15
Shoot:
 STA SHOT_P
 LDA TEAMOF,X
 STA Z_K
 JSR AttDir
 BNE ShL
 LDA #<(P_RIGHT+10)
 STA Z_TX
 LDA #>(P_RIGHT+10)
 STA Z_TXH
 LDA #$01
 STA SHOT_SIDE
 JMP ShY
ShL:
 LDA #<(P_LEFT-10)
 STA Z_TX
 LDA #>(P_LEFT-10)
 STA Z_TXH
 LDA #$00
 STA SHOT_SIDE
ShY:
 LDY Z_K
 LDA HUMANS
 AND BITTAB,Y
 BEQ ShCpu
 TXA
 CMP CTRL,Y
 BNE ShCpu
 LDA JOY,Y
 AND #$03
 BEQ ShCpu
 CMP #$01
 BNE ShDown
 LDA #$EE
 JMP ShAim
ShDown:
 LDA #18
 JMP ShAim
ShCpu:
 LDA #$1F
 JSR RandSym
ShAim:
 CLC
 ADC #P_MIDY
 STA Z_TY
 LDA #$00
 STA Z_TYH
// speed 4.0 + p/5, lift 0.25 + p*0.11 + a little luck
 LDA SHOT_P
 ASL
 ASL
 ASL
 ASL
 ASL
 STA Z_SPD
 LDA SHOT_P
 LSR
 LSR
 LSR
 CLC
 ADC #$04
 STA Z_SPDH
 LDA SHOT_P
 ASL
 ASL
 ASL
 ASL
 STA Z_VZ
 LDA SHOT_P
 LSR
 LSR
 LSR
 LSR
 STA Z_VZH
 LDA SHOT_P
 ASL
 ASL
 ADC SHOT_P
 ADC Z_VZ
 STA Z_VZ
 LDA Z_VZH
 ADC #$00
 STA Z_VZH
 JSR Rand
 AND #$3F
 ADC #$40
 ADC Z_VZ
 STA Z_VZ
 LDA Z_VZH
 ADC #$00
 STA Z_VZH
 JSR Kick
 LDA SHOT_SIDE
 STA SHOT_GOAL
 JSR PredictShot
 JSR Rand
 AND #$07
 CLC
 ADC #$03
 STA SHOT_REACT
 RTS
// where will the shot cross the goal line? (no friction, good enough)
PredictShot:
 LDA PXF+BALL
 STA Z_U0
 LDA PXL+BALL
 STA Z_U1
 LDA PXH+BALL
 STA Z_U2
 LDA PYF+BALL
 STA Z_S0
 LDA PYL+BALL
 STA Z_S1
 LDA PYH+BALL
 STA Z_S2
 LDX #120
PsL:
 LDY #$00
 LDA VXH+BALL
 BPL PsX
 DEY
PsX:
 CLC
 LDA Z_U0
 ADC VXL+BALL
 STA Z_U0
 LDA Z_U1
 ADC VXH+BALL
 STA Z_U1
 TYA
 ADC Z_U2
 STA Z_U2
 LDY #$00
 LDA VYH+BALL
 BPL PsY
 DEY
PsY:
 CLC
 LDA Z_S0
 ADC VYL+BALL
 STA Z_S0
 LDA Z_S1
 ADC VYH+BALL
 STA Z_S1
 TYA
 ADC Z_S2
 STA Z_S2
 LDA SHOT_SIDE
 BNE PsR
 LDA Z_U2
 BMI PsDone
 BNE PsN
 LDA Z_U1
 CMP #P_LEFT
 BCC PsDone
 JMP PsN
PsR:
 LDA Z_U2
 CMP #$03
 BCC PsN
 LDA Z_U1
 CMP #<(P_RIGHT+1)
 BCS PsDone
PsN:
 DEX
 BNE PsL
PsDone:
 LDA Z_S1
 STA PRED_Y
 LDA Z_S2
 STA PRED_Y+1
 RTS
// target in the facing direction: Z_T0 = x distance, Z_T1 = y distance
DirTarget:
 LDY PDIR,X
 LDA PXL,X
 STA Z_TX
 LDA PXH,X
 STA Z_TXH
 LDA PYL,X
 STA Z_TY
 LDA PYH,X
 STA Z_TYH
 LDA DIRCX,Y
 BEQ DtY
 BMI DtXn
 CLC
 LDA Z_TX
 ADC Z_T0
 STA Z_TX
 LDA Z_TXH
 ADC #$00
 STA Z_TXH
 JMP DtY
DtXn:
 SEC
 LDA Z_TX
 SBC Z_T0
 STA Z_TX
 LDA Z_TXH
 SBC #$00
 STA Z_TXH
DtY:
 LDA DIRCY,Y
 BEQ DtR
 BMI DtYn
 CLC
 LDA Z_TY
 ADC Z_T1
 STA Z_TY
 LDA Z_TYH
 ADC #$00
 STA Z_TYH
 RTS
DtYn:
 SEC
 LDA Z_TY
 SBC Z_T1
 STA Z_TY
 LDA Z_TYH
 SBC #$00
 STA Z_TYH
DtR:
 RTS
KickForward:
 LDA #80
 STA Z_T0
 LDA #40
 STA Z_T1
 JSR DirTarget
 LDA #$00
 STA Z_SPD
 STA Z_VZ
 STA Z_VZH
 LDA #$03
 STA Z_SPDH
 JMP Kick
LongBall:
 LDA #190
 STA Z_T0
 LDA #95
 STA Z_T1
 JSR DirTarget
 LDA SHOT_P
 ASL
 ASL
 ASL
 ASL
 STA Z_SPD
 LDA #$03
 STA Z_SPDH
 LDA #$C0
 STA Z_VZ
 LDA #$01
 STA Z_VZH
 JMP Kick
// corner: a lofted ball into the box
DoCross:
 LDA TEAMOF,X
 JSR AttDir
 BNE DcL
 JSR Rand
 AND #$1F
 CLC
 ADC #<(P_RIGHT-100)
 STA Z_TX
 LDA #>(P_RIGHT-100)
 ADC #$00
 STA Z_TXH
 JMP DcY
DcL:
 JSR Rand
 AND #$1F
 CLC
 ADC #<(P_LEFT+68)
 STA Z_TX
 LDA #>(P_LEFT+68)
 ADC #$00
 STA Z_TXH
DcY:
 JSR Rand
 AND #$3F
 CLC
 ADC #<(P_MIDY-32)
 STA Z_TY
 LDA #$00
 STA Z_TYH
 LDA #$40
 STA Z_SPD
 LDA #$03
 STA Z_SPDH
 LDA #$40
 STA Z_VZ
 LDA #$02
 STA Z_VZH
 JMP Kick
// clearance under pressure: long, high, to anywhere across the pitch
DoClear:
 LDA TEAMOF,X
 JSR AttDir
 BNE DclL
 CLC
 LDA PXL,X
 ADC #<300
 STA Z_TX
 LDA PXH,X
 ADC #>300
 STA Z_TXH
 JMP DclY
DclL:
 SEC
 LDA PXL,X
 SBC #<300
 STA Z_TX
 LDA PXH,X
 SBC #>300
 STA Z_TXH
// ...towards a wing (often into touch)
DclY:
 JSR Rand
 AND #$3F
 STA Z_T0
 JSR Rand
 BMI DclBot
 LDA #P_TOP-24
 CLC
 ADC Z_T0
 STA Z_TY
 LDA #$00
 STA Z_TYH
 JMP DclK
DclBot:
 LDA #<(P_BOT-40)
 CLC
 ADC Z_T0
 STA Z_TY
 LDA #>(P_BOT-40)
 ADC #$00
 STA Z_TYH
DclK:
 LDA #$80
 STA Z_SPD
 LDA #$03
 STA Z_SPDH
 LDA #$40
 STA Z_VZ
 LDA #$02
 STA Z_VZH
 JMP Kick
// goal kick / keeper punt: long and high up the middle
DoLongKick:
 LDA TEAMOF,X
 JSR AttDir
 BNE DlL
 CLC
 LDA PXL,X
 ADC #<400
 STA Z_TX
 LDA PXH,X
 ADC #>400
 STA Z_TXH
 JMP DlY
DlL:
 SEC
 LDA PXL,X
 SBC #<400
 STA Z_TX
 LDA PXH,X
 SBC #>400
 STA Z_TXH
DlY:
 JSR Rand
 AND #$7F
 CLC
 ADC #<(P_MIDY-64)
 STA Z_TY
 LDA #$00
 ADC #$00
 STA Z_TYH
 LDA #$00
 STA Z_SPD
 LDA #$04
 STA Z_SPDH
 LDA #$80
 STA Z_VZ
 LDA #$02
 STA Z_VZH
 JMP Kick
`;

export const TITLE = `
// ----------------------------------------------------------------- title
Title:
 LDA #$00
 STA MODE
 STA HUMANS
 STA FLIP_REQ
 STA IDLE_T
 STA TT_X
 STA TT_XH
 LDA #$01
 STA TITLE_MODE
 LDA #$10
 STA CROWD_T
 JSR InitSort
 JSR TitleDraw
// drop any frame the match left pending (it may carry a screen flip)
 SEI
 LDA #$00
 STA READY
 LDA #$08
 STA HUD_D016
 LDA #TITLE_D018
 STA CUR_D018
 CLI
TitleLoop:
 JSR FrameSync
 JSR ReadInput
 LDA FPRESS1
 BEQ TlNo1
 LDA #$01
 JMP StartMatch
TlNo1:
 LDA FPRESS2
 BEQ TlNo2
 LDA #$03
 JMP StartMatch
TlNo2:
 LDA FRAMECNT
 AND #$03
 BNE TlAnim
 INC IDLE_T
 LDA IDLE_T
 CMP #200
 BNE TlAnim
 LDA #$00
 JMP StartMatch
TlAnim:
 JSR TitleSprites
 LDA FRONT_DL
 EOR #$20
 STA BACK_DL
 JSR SortObjs
 JSR BuildDL
 JSR Commit
 JMP TitleLoop
// screen A: the PETSCII title picture (TITLE_SCR / TITLE_COL, 1000 bytes each)
TitleDraw:
 LDX #$00
TdCopy:
 LDA TITLE_SCR,X
 STA SCRA,X
 LDA TITLE_SCR+$100,X
 STA SCRA+$100,X
 LDA TITLE_SCR+$200,X
 STA SCRA+$200,X
 LDA TITLE_SCR+$2E8,X
 STA SCRA+$2E8,X
 LDA TITLE_COL,X
 STA $D800,X
 LDA TITLE_COL+$100,X
 STA $D900,X
 LDA TITLE_COL+$200,X
 STA $DA00,X
 LDA TITLE_COL+$2E8,X
 STA $DAE8,X
 INX
 BNE TdCopy
 RTS
// one blue player dribbling right, two white ones chasing
TitleSprites:
 INC TT_X
 BNE TsNw
 INC TT_XH
TsNw:
 LDA TT_XH
 BEQ TsOk
 LDA TT_X
 CMP #$80
 BCC TsOk
 LDA #$00
 STA TT_X
 STA TT_XH
TsOk:
 LDX #NOBJ-1
 LDA #$FF
TsHide:
 STA OBY,X
 DEX
 BPL TsHide
 LDA FRAMECNT
 LSR
 LSR
 AND #$03
 CLC
 ADC #F_R_RUN0+SPR_PTR0
 STA OBP
 STA OBP+1
 STA OBP+2
 LDA #14
 STA OBC
 LDA #$01
 STA OBC+1
 STA OBC+2
 STA OBC+3
 LDA #$D9
 STA OBY
 LDA #$DE
 STA OBY+1
 LDA #$D4
 STA OBY+2
 LDA #$D9
 STA OBY+3
 LDA BANIM
 CLC
 ADC #$01
 STA BANIM
 LSR
 LSR
 AND #$03
 TAY
 LDA BALLFR,Y
 CLC
 ADC #SPR_PTR0
 STA OBP+3
// x positions: blue at TT_X, ball +14, chasers -34 / -56
 LDA TT_X
 STA OBXL
 LDA TT_XH
 STA OBXH
 CLC
 LDA TT_X
 ADC #14
 STA OBXL+3
 LDA TT_XH
 ADC #$00
 STA OBXH+3
 SEC
 LDA TT_X
 SBC #34
 STA OBXL+1
 LDA TT_XH
 SBC #$00
 STA OBXH+1
 SEC
 LDA TT_X
 SBC #56
 STA OBXL+2
 LDA TT_XH
 SBC #$00
 STA OBXH+2
// hide anything off the left edge (negative x)
 LDX #$03
TsClip:
 LDA OBXH,X
 BPL TsCn
 LDA #$FF
 STA OBY,X
TsCn:
 DEX
 BPL TsClip
 RTS
`;
