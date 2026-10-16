// SHMUP V game code, one string per code block (the vertical twin of
// tools/shmup_h_gen/code.mjs). build.mjs places them in columns between the
// Dev Machine macro nodes. CAPS names are GAME STATE variables or NAME = value settings.
import { CH, LOOP_ROW } from './art.mjs';

// ------------------------------------------------------------ GAME STATE
// One page at $C000. Allocated in this order; $C0FE/$C0FF keep the high
// score through a game over (BootTitle clears $C000-$C0FD).
export const STATE_BASE = 0xC000;
const STATE_LIST = [
  ['PLAYER_XL', 1, 'ship X, low byte (sprite coordinates)'],
  ['PLAYER_XH', 1, 'ship X, ninth bit (0 or 1)'],
  ['PLAYER_Y', 1, 'ship Y'],
  ['SHIP_STEP', 1, 'pixels the ship moves this frame'],
  ['SHIP_TILT', 1, '0 level, 1 banking left, 2 banking right'],
  ['PLAYER_BOOM', 1, 'ship explosion timer, 0 = flying'],
  ['INVULN', 1, 'frames of safety left (respawn / shield)'],
  ['LIVES', 1, 'ships left'],
  ['FIRE_LATCH', 1, '1 while fire is held (tap-fire mode)'],
  ['KEY_LATCH', 1, '1 while the power key is held'],
  ['ANIM', 1, 'counts frames, drives every animation'],
  ['SCROLL_TICK', 1, 'counts frames for the slow scroll'],
  ['SCORE1', 1, 'score: hundreds + thousands (BCD)'],
  ['SCORE2', 1, 'score: 10 thousands + 100 thousands (BCD)'],
  ['EN_BOOM', 3, 'explosion timer per enemy slot (SPN slot 0-2)'],
  ['EN_BXL', 3, 'where that explosion is: X low byte'],
  ['EN_BXH', 3, 'X ninth bit'],
  ['EN_BY', 3, 'Y'],
  ['SHOT_ON', 1, 'main shot / laser flying'],
  ['SHOT_XL', 1, ''], ['SHOT_XH', 1, ''], ['SHOT_Y', 1, ''],
  ['DBL_ON', 1, 'DOUBLE shot flying'],
  ['DBL_XL', 1, ''], ['DBL_XH', 1, ''], ['DBL_Y', 1, ''],
  ['MSL_ON', 1, 'MISSILE flying'],
  ['MSL_XL', 1, ''], ['MSL_XH', 1, ''], ['MSL_Y', 1, ''],
  ['MSL_TGT', 1, 'SPAWNER slot the homing MISSILE chases'],
  ['OPT_XL', 1, 'OPTION position'], ['OPT_XH', 1, ''], ['OPT_Y', 1, ''],
  ['CAP_ON', 1, 'a capsule is out'],
  ['CAP_SLOT', 1, 'enemy slot whose sprite it borrows'],
  ['CAP_XL', 1, ''], ['CAP_XH', 1, ''], ['CAP_Y', 1, ''],
  ['METER', 1, 'lit power meter slot, 0 = none, 1-6'],
  ['POWERS', 6, 'owned powers, one byte per meter slot:'],
  ['TRAIL_POS', 1, 'newest entry of the OPTION trail'],
  ['PROBE_XL', 1, 'ProbeChar input point'], ['PROBE_XH', 1, ''], ['PROBE_Y', 1, ''],
  ['PROBE_COL', 1, 'ProbeChar scratch'], ['PROBE_CHAR', 1, ''],
  ['BOX_XL', 1, 'BoxTest first sprite'], ['BOX_XH', 1, ''], ['BOX_Y', 1, ''],
  ['BOX_W', 1, 'BoxTest hit distance X'], ['BOX_H', 1, 'BoxTest hit distance Y'],
  ['TGT_XL', 1, 'BoxTest second sprite'], ['TGT_XH', 1, ''], ['TGT_Y', 1, ''],
  ['D_XL', 1, 'PutSprite inputs'], ['D_XH', 1, ''], ['D_Y', 1, ''], ['D_PTR', 1, ''], ['D_COL', 1, ''],
  ['SPR_ON', 1, '$D015 being built'], ['SPR_MSB', 1, '$D010 being built'],
  ['T0', 1, 'scratch'], ['T1', 1, ''], ['T2', 1, ''],
];
// Enemy shots (ENEMY FIRE column), page $C1. Not in the range BootTitle
// clears: NEW GAME and ResetActors clear what has to be.
const SHOT_STATE = [
  ['ES_ON', 6, 'enemy shot flying'],
  ['ES_X', 6, 'X in 2-pixel steps from the screen edge (0-159)'], ['ES_XF', 6, 'X fraction'],
  ['ES_Y', 6, 'Y (sprite coordinates)'], ['ES_YF', 6, 'Y fraction'],
  ['ES_VXL', 6, 'X speed, 8.8 signed'], ['ES_VXH', 6, ''],
  ['ES_VYL', 6, 'Y speed, 8.8 signed'], ['ES_VYH', 6, ''],
  ['ES_SHOWN', 6, '1 = drawn on the screen at ES_AL/ES_AH'],
  ['ES_AL', 6, 'screen address of the drawn shot'], ['ES_AH', 6, ''],
  ['ES_UNDER', 6, 'the char it covers, put back by EraseShots'],
  ['ES_TICK', 1, 'frames to the next shot'], ['ES_NEXT', 1, 'enemy slot that shoots next'],
  ['ES_AX', 1, 'aim: |dx|'], ['ES_AY', 1, 'aim: |dy|'], ['ES_SX', 1, 'aim: 1 = dx negative'], ['ES_SY', 1, 'aim: 1 = dy negative'],
  ['ES_K', 1, 'aim: angle from level, 22.5 degree steps'],
  ['SHIP_CX', 1, "the ship's centre in shot units"], ['SHIP_CY', 1, ''],
];
export const STATE = {};
{
  let a = STATE_BASE;
  for (const [n, size] of STATE_LIST) { STATE[n] = a; a += size; }
  if (a > 0xC080) throw new Error('GAME STATE overflows into the trail: $' + a.toString(16));
  STATE.TRAIL_XL = 0xC080; STATE.TRAIL_XH = 0xC0A0; STATE.TRAIL_Y = 0xC0C0;
  STATE.HI1 = 0xC0FE; STATE.HI2 = 0xC0FF;
  let e = 0xC100;
  for (const [n, size] of SHOT_STATE) { STATE[n] = e; e += size; }
}
const POWER_NAMES = ['SPEEDUPS', 'HAS_MISSILE', 'HAS_DOUBLE', 'HAS_LASER', 'HAS_OPTION', 'SHIELD'];
POWER_NAMES.forEach((n, i) => { STATE[n] = STATE.POWERS + i; });

const hex = (v, w = 4) => '$' + v.toString(16).toUpperCase().padStart(w, '0');

export function stateMapCode() {
  const pad = s => s.padEnd(12);
  let out = '; GAME STATE MAP\n; Every variable the game uses, one page at $C000. The other code\n'
    + '; blocks use these names; change an address here and they follow.\n'
    + '; BootTitle clears $C000-$C0FD for every new game.\n\n';
  for (const [n, size, note] of STATE_LIST) {
    out += `${pad(n)}= ${hex(STATE[n])}` + (note ? `   ; ${note}${size > 1 ? ` (${size} bytes)` : ''}` : (size > 1 ? `   ; (${size} bytes)` : '')) + '\n';
    if (n === 'POWERS') POWER_NAMES.forEach((p, i) => { out += `${pad(p)}= ${hex(STATE[p])}   ;   ${['SPEED: speed-ups taken', 'MISSILE owned', 'DOUBLE owned', 'LASER owned', 'OPTION owned', 'SHIELD: hits left'][i]}\n`; });
  }
  out += '\n; OPTION trail: 32 remembered ship positions\n';
  out += `TRAIL_XL    = $C080\nTRAIL_XH    = $C0A0\nTRAIL_Y     = $C0C0\n`;
  out += '\n; Enemy shots (ENEMY FIRE), 6 of each per-shot byte\n';
  for (const [n, size, note] of SHOT_STATE) out += `${pad(n)}= ${hex(STATE[n])}` + (note ? `   ; ${note}${size > 1 ? ` (${size} bytes)` : ''}` : '') + '\n';
  out += '\n; High score - outside the cleared range so it survives a game over\n';
  out += 'HI1         = $C0FE   ; hundreds + thousands (BCD)\nHI2         = $C0FF   ; 10 thousands + 100 thousands (BCD)\n';
  return out;
}

// Which GAME STATE names a block uses, for its header.
export function stateUsed(code) {
  const names = Object.keys(STATE).filter(n => new RegExp(`\\b${n}\\b`).test(code.replace(/;.*$/gm, '')));
  return names;
}

// Screen row addresses for ProbeChar
const rowTable = (hi) => Array.from({ length: 25 }, (_, r) => hex(hi ? (0x0400 + r * 40) >> 8 : (0x0400 + r * 40) & 0xFF, 2)).join(',');

// ------------------------------------------------------------ the blocks
export const C = {};

// ---------------- 01 STARTUP
C.startup = `; Bank BASIC out, clear the high score (power-on RAM is random),
; then straight to the title screen.
LDA #$36
STA $01
LDA #$00
STA HI1
STA HI2
JMP BootTitle

; InstallHudSplit - called once per game from GAME SETUP.
; Stops the CIA timer IRQs, points NMI at a bare RTI and banks
; out the KERNAL ($01 = $35). The HUD RASTER HANDLER macro below
; finishes the job by installing the four raster IRQs.
InstallHudSplit:
SEI
LDA #$7F
STA $DC0D
STA $DD0D
LDA $DC0D
LDA $DD0D
LDA #<HudNmi
STA $FFFA
LDA #>HudNmi
STA $FFFB
LDA #$1B
STA $D011
LDA #$08
STA $D016
LDA #$35
STA $01
`;

// ---------------- 02 BOOT / TITLE
C.bootTitle = `; BootTitle - also where a game over comes back to.
BootTitle:
SEI
CLD
LDX #$FF         ; fresh stack: a game over jumps here mid-call
TXS
LDA #$36
.byte $8D,$01,$00 ; STA $0001 (absolute, as SHMUP V)
LDA #$00
STA $D01A        ; no raster IRQs on the title
STA $D015        ; no sprites
LDA #$FF
STA $D019
; Clear GAME STATE ($C000-$C0FD). $C0FE/$C0FF keep the high score.
LDA #$00
LDX #$00
ClearState:
STA $C000,X
INX
CPX #$FE
BNE ClearState
; Port 2 as input, keyboard rows released.
LDA #$00
STA $DC02
LDA #$FF
STA $DC00
`;

C.titleLoop = `; Wait for fire to be pressed, then released, then start.
TitleLoop:
JSR TitleFrame
LDA $DC00
AND #$10
BNE TitleLoop
TitleRelease:
JSR TitleFrame
LDA $DC00
AND #$10
BEQ TitleRelease
JMP SetupGame

; One title frame: wait for the border, play the tune.
TitleFrame:
`;

// ---------------- 03 GAME SETUP
C.newGame = `; A fresh game: ships and score, then into the loop.
START_LIVES = 3

; Every sprite hires, in front of the scenery, not expanded.
LDA #$00
STA $D01B
STA $D01C
STA $D017
STA $D01D
LDA #START_LIVES
STA LIVES
LDA #$00
STA SCORE1
STA SCORE2
; the screen is fresh: no enemy shot is drawn on it
LDX #$05
ClearShown:
STA ES_SHOWN,X
DEX
BPL ClearShown
; The climb starts at the bottom of the WORLD map ($61 = the camera's
; map row): LOOP_ROW, whose rows repeat the top of the map.
LDA #${hex(LOOP_ROW, 2)}
STA $61
JSR ResetActors
JSR DrawActors
JSR InstallHudSplit
JMP GameLoop
`;

// ---------------- 04 FRAME LOOP
C.gameLoop = `; One pass = one frame. All the game logic runs here, while the
; screen is still being drawn; drawing and scrolling wait for the
; bottom border (FRAME SYNC below).
GameLoop:
JSR SfxTick
JSR Effects
JSR Input
JSR PowerKey
JSR Enemy
JSR EnemyFire
JSR Weapons
JSR OptionMove
JSR Hits
JSR Capsule
JSR Status
`;

C.scroll = `; In the border: place the sprites, then scroll the world.
; Scroll speed - on the SCROLL panel.
SCROLL_SPEED = 1   ; 0 slow (1 pixel every 2 frames), 1 normal, 2 fast

JSR DrawActors
; enemy shots are chars: off the screen while it scrolls, then back on
JSR EraseShots
.IF SCROLL_SPEED == 0
INC SCROLL_TICK
LDA SCROLL_TICK
AND #$01
BEQ ScrollDone
JSR ScrollStep
.ENDIF
.IF SCROLL_SPEED >= 1
JSR ScrollStep
.ENDIF
.IF SCROLL_SPEED >= 2
JSR ScrollStep
.ENDIF
ScrollDone:
JSR DrawShots
JMP GameLoop

; ScrollStep - the world moves one pixel down.
; MSC_U moves the WORLD SCROLLER camera up, MSC_Update finishes a
; coarse (whole char) step. $61 is the camera's map row; the climb
; starts at LOOP_ROW (NEW GAME). The WORLD map's bottom rows repeat
; its top rows, so when the camera reaches row 0 it can jump back to
; LOOP_ROW without the screen changing.
LOOP_ROW = ${hex(LOOP_ROW, 2)}
ScrollStep:
LDA $61
BNE ScrollGo
LDA #LOOP_ROW
STA $61
ScrollGo:
JSR MSC_U
JSR MSC_Update
; A capsule sits in the world, so it drifts down with it; so do
; the SPAWNER's TANK (WALKER) and TURRET entities (SPN_Scroll).
JSR SPN_Scroll
INC CAP_Y
RTS
`;

// ---------------- 05 RESPAWN
C.respawn = `; ResetActors - a new ship at the bottom of the screen.
; On the SHIP panel:
KEEP_POWERS = 0     ; 0 = a lost ship loses its power-ups (Nemesis rules)
RESPAWN_SAFE = 100  ; frames the new ship cannot be hit

ResetActors:
LDA #$A0
STA PLAYER_XL
LDA #$00
STA PLAYER_XH
LDA #$D0
STA PLAYER_Y
LDA #$00
STA PLAYER_BOOM
STA SHIP_TILT
STA SHOT_ON
STA DBL_ON
STA MSL_ON
STA CAP_ON
.IF KEEP_POWERS == 0
STA METER
LDX #$05
ClearPowers:
STA POWERS,X
DEX
BPL ClearPowers
.ENDIF
LDX #$02
ClearBooms:
STA EN_BOOM,X
DEX
BPL ClearBooms
LDX #$05
ClearShots:
STA ES_ON,X
DEX
BPL ClearShots
; The SPAWNER clears its slots and relaunches what is on screen.
JSR SPN_Reset
LDA #$40
STA ES_TICK
LDA #RESPAWN_SAFE
STA INVULN
; Fill the OPTION trail with the new position.
LDX #$1F
FillTrail:
LDA PLAYER_XL
STA TRAIL_XL,X
LDA PLAYER_XH
STA TRAIL_XH,X
LDA PLAYER_Y
STA TRAIL_Y,X
DEX
BPL FillTrail
RTS
`;

// ---------------- 06 JOYSTICK / FIRE
C.input = `; Input - the JOYSTICK macro below reads port 2 into $F8 and calls
; one of the Joy... labels for the direction held.
; Ship speed in pixels per frame - on the SHIP panel.
SHIP_SPEED = 2

Input:
LDA PLAYER_BOOM
BEQ InputAlive
RTS
InputAlive:
; This frame's step = SHIP_SPEED + SPEED power-ups taken.
LDA #SHIP_SPEED
CLC
ADC SPEEDUPS
STA SHIP_STEP
LDA #$00
STA SHIP_TILT
`;

C.fire = `; Fire. Hold fire for auto-fire, or tap mode: one press, one shot.
AUTO_FIRE = 1     ; on the SHIP panel

LDA $F8           ; joystick bits from the JOYSTICK macro, 0 = pressed
AND #$10
BNE FireReleased
.IF AUTO_FIRE == 0
LDA FIRE_LATCH
BNE InputDone
LDA #$01
STA FIRE_LATCH
.ENDIF
JMP FireWeapons   ; launches whatever is free (WEAPONS column)
FireReleased:
LDA #$00
STA FIRE_LATCH
InputDone:
RTS
`;

C.joyLeft = `; Left, as far as X_MIN. X is 9 bits: PLAYER_XL + PLAYER_XH.
; Banks the ship.
X_MIN = $18

LDA #$01
STA SHIP_TILT
LDA PLAYER_XL
SEC
SBC SHIP_STEP
STA PLAYER_XL
LDA PLAYER_XH
SBC #$00
STA PLAYER_XH
BMI JoyLeftClamp
BNE JoyLeftDone
LDA PLAYER_XL
CMP #X_MIN
BCS JoyLeftDone
JoyLeftClamp:
LDA #X_MIN
STA PLAYER_XL
LDA #$00
STA PLAYER_XH
JoyLeftDone:
RTS
`;

C.joyRight = `; Right, as far as $100 + X_MAX_LO (the right edge of the 40-column
; screen is X = $140 for a sprite's left side). Banks the ship.
X_MAX_LO = $40

LDA #$02
STA SHIP_TILT
LDA PLAYER_XL
CLC
ADC SHIP_STEP
STA PLAYER_XL
LDA PLAYER_XH
ADC #$00
STA PLAYER_XH
BEQ JoyRightDone
LDA PLAYER_XL
CMP #X_MAX_LO
BCC JoyRightDone
LDA #X_MAX_LO
STA PLAYER_XL
JoyRightDone:
RTS
`;

C.joyUp = `; Up, no higher than Y_MIN (a good way below the HUD, so enemies
; coming down can be seen in time).
Y_MIN = $60

LDA PLAYER_Y
SEC
SBC SHIP_STEP
CMP #Y_MIN
BCS JoyUpStore
LDA #Y_MIN
JoyUpStore:
STA PLAYER_Y
RTS
`;

C.joyDown = `; Down, no lower than Y_MAX (the bottom of the screen).
Y_MAX = $E0

LDA PLAYER_Y
CLC
ADC SHIP_STEP
CMP #Y_MAX
BCC JoyDownStore
LDA #Y_MAX
JoyDownStore:
STA PLAYER_Y
RTS
`;

// ---------------- 07 POWER METER
C.powerKey = `; PowerKey - the key that cashes in the lit meter slot.
POWER_KEY = 0      ; on the POWER METER panel: 0 SPACE, 1 RETURN, 2 C=

.IF POWER_KEY == 0
KEY_ROW = $7F
KEY_BIT = $10
.ENDIF
.IF POWER_KEY == 1
KEY_ROW = $FE
KEY_BIT = $02
.ENDIF
.IF POWER_KEY == 2
KEY_ROW = $7F
KEY_BIT = $20
.ENDIF

PowerKey:
LDA #$FF
STA $DC02        ; port A drives the keyboard rows for a moment
LDA #KEY_ROW
STA $DC00
LDA $DC01        ; the row's keys, 0 = pressed
LDX #$FF
STX $DC00
LDX #$00
STX $DC02        ; port A back to input for the joystick
AND #KEY_BIT
BNE KeyUp
LDA KEY_LATCH    ; one power per press
BNE KeyDone
LDA #$01
STA KEY_LATCH
JMP ApplyPower
KeyUp:
LDA #$00
STA KEY_LATCH
KeyDone:
RTS
`;

C.applyPower = `; ApplyPower - turn the lit slot into its power-up.
; Slots: 1 SPEED  2 MISSILE  3 DOUBLE  4 LASER  5 OPTION  6 SHIELD
; A power you already own is refused and the slot stays lit.
; On the POWER METER panel:
MAX_SPEEDUPS = 3   ; SPEED can be taken this many times
SHIELD_HITS = 3    ; hits a SHIELD soaks up

ApplyPower:
LDA METER
BNE PowerPick
RTS
PowerPick:
CMP #$01
BEQ PowSpeed
CMP #$02
BEQ PowMissile
CMP #$03
BEQ PowDouble
CMP #$04
BEQ PowLaser
CMP #$05
BEQ PowOption
; 6 = SHIELD, always refills
LDA #SHIELD_HITS
STA SHIELD
JMP PowerTaken

PowSpeed:
LDA SPEEDUPS
CMP #MAX_SPEEDUPS
BCS PowerRefused
INC SPEEDUPS
JMP PowerTaken

PowMissile:
LDA HAS_MISSILE
BNE PowerRefused
INC HAS_MISSILE
JMP PowerTaken

; DOUBLE and LASER replace each other.
PowDouble:
LDA HAS_DOUBLE
BNE PowerRefused
LDA #$01
STA HAS_DOUBLE
LDA #$00
STA HAS_LASER
JMP PowerTaken

PowLaser:
LDA HAS_LASER
BNE PowerRefused
LDA #$01
STA HAS_LASER
LDA #$00
STA HAS_DOUBLE
JMP PowerTaken

PowOption:
LDA HAS_OPTION
BNE PowerRefused
INC HAS_OPTION

PowerTaken:
LDA #$00
STA METER
JMP PowerSound
PowerRefused:
RTS
`;

C.capsule = `; Capsule - dropped by an entity whose type has a DROP (the RED FAN in
; the WORLD map's spawn layer). It borrows that enemy slot's sprite,
; drifts down with the world (ScrollStep) and lights the next meter
; slot when you fly into it.
Capsule:
LDA CAP_ON
BNE CapsuleLive
RTS
CapsuleLive:
; gone off the bottom?
LDA CAP_Y
CMP #$F0
BCC CapsuleShown
LDA #$00
STA CAP_ON
RTS
; hidden while its slot shows an explosion or a new enemy
CapsuleShown:
LDY CAP_SLOT
LDA EN_BOOM,Y
ORA SPN_ON,Y
ORA PLAYER_BOOM
BNE CapsuleDone
LDA CAP_XL
STA BOX_XL
LDA CAP_XH
STA BOX_XH
LDA CAP_Y
STA BOX_Y
LDA #$10
STA BOX_W
STA BOX_H
JSR BoxVsShip
BCS CapsuleDone
; collected: light the next slot, 6 wraps round to 1
LDA #$00
STA CAP_ON
INC METER
LDA METER
CMP #$07
BCC CapsuleGot
LDA #$01
STA METER
CapsuleGot:
JMP CapsuleSound
CapsuleDone:
RTS
`;

// ---------------- 08 ATTACK WAVES
C.enemy = `; Enemy - the SPAWNER node (GAME SETUP column) launches the entities
; placed on the WORLD map's SPAWN layer as they scroll in, and flies
; them by their type's movement. Tell it where the ship is - CHASE and
; DIVE home in on SPN_TGT.
Enemy:
INC ANIM
LDA PLAYER_XL
STA SPN_TGT_XL
LDA PLAYER_XH
STA SPN_TGT_XH
LDA PLAYER_Y
STA SPN_TGT_Y
JMP SPN_Update
`;

// ---------------- 09 WEAPONS
C.fireWeapons = `; FireWeapons - fire pressed: launch every weapon that is free.
FireWeapons:
LDA SHOT_ON
BNE FireDouble
LDA #$01
STA SHOT_ON
LDA PLAYER_XL      ; from the ship's nose
STA SHOT_XL
LDA PLAYER_XH
STA SHOT_XH
LDA PLAYER_Y
SEC
SBC #$0C
STA SHOT_Y
JSR FireSound

FireDouble:
LDA HAS_DOUBLE
BEQ FireMissile
LDA DBL_ON
BNE FireMissile
LDA #$01
STA DBL_ON
LDA PLAYER_XL      ; from the left wing
SEC
SBC #$04
STA DBL_XL
LDA PLAYER_XH
SBC #$00
STA DBL_XH
LDA PLAYER_Y
SEC
SBC #$06
STA DBL_Y

FireMissile:
LDA HAS_MISSILE
BEQ FireDone
LDA MSL_ON
BNE FireDone
LDA #$01
STA MSL_ON
LDA PLAYER_XL
STA MSL_XL
LDA PLAYER_XH
STA MSL_XH
LDA PLAYER_Y
SEC
SBC #$08
STA MSL_Y
FireDone:
RTS
`;

C.weapons = `; Weapons - move everything the ship has fired.
; Speeds in pixels per frame - on the WEAPONS panel.
SHOT_SPEED = 6
LASER_SPEED = 9
DOUBLE_SPEED = 4
SHOT_TOP = $40     ; above this the shot has gone under the HUD

Weapons:
JSR MoveShot
JSR MoveDouble
JMP MoveMissile

; The shot (or laser) flies up until the top of the screen.
MoveShot:
LDA SHOT_ON
BNE ShotLive
RTS
ShotLive:
LDA #SHOT_SPEED
LDY HAS_LASER
BEQ ShotStep
LDA #LASER_SPEED
ShotStep:
STA T0
LDA SHOT_Y
SEC
SBC T0
BCC ShotGone
STA SHOT_Y
CMP #SHOT_TOP
BCS ShotTerrain
ShotGone:
LDA #$00
STA SHOT_ON
RTS
; Whatever is under the tip of the shot: a bunker is blown up.
ShotTerrain:
LDA SHOT_XL
CLC
ADC #$0B
STA PROBE_XL
LDA SHOT_XH
ADC #$00
STA PROBE_XH
LDA SHOT_Y
CLC
ADC #$03
STA PROBE_Y
JSR ProbeChar
JSR TerrainHit
BCS ShotGone
RTS

; DOUBLE flies up and left at 45 degrees.
MoveDouble:
LDA DBL_ON
BNE DoubleLive
RTS
DoubleLive:
LDA DBL_XL
SEC
SBC #DOUBLE_SPEED
STA DBL_XL
LDA DBL_XH
SBC #$00
STA DBL_XH
BMI DoubleGone
BNE DoubleUp
LDA DBL_XL
CMP #$08
BCC DoubleGone
DoubleUp:
LDA DBL_Y
SEC
SBC #DOUBLE_SPEED
BCC DoubleGone
STA DBL_Y
CMP #SHOT_TOP
BCC DoubleGone
LDA DBL_XL
CLC
ADC #$07
STA PROBE_XL
LDA DBL_XH
ADC #$00
STA PROBE_XH
LDA DBL_Y
CLC
ADC #$06
STA PROBE_Y
JSR ProbeChar
JSR TerrainHit
BCS DoubleGone
RTS
DoubleGone:
LDA #$00
STA DBL_ON
RTS
`;

C.missile = `; MISSILE - homes in on an enemy: it picks the first SPAWNER slot
; that is flying and steers towards it, MISSILE_SPEED pixels a frame
; on each axis. With nothing to chase (or homing off) it flies
; straight up. On the WEAPONS panel:
MISSILE_SPEED = 3
MISSILE_HOMING = 1   ; 0 = straight up, like a second shot

MoveMissile:
LDA MSL_ON
BNE MissileLive
RTS
MissileLive:
.IF MISSILE_HOMING == 1
; Still chasing a live enemy? Otherwise look for another.
LDX MSL_TGT
LDA SPN_ON,X
BNE MissileSteer
LDX #$02
MissileFind:
LDA SPN_ON,X
BNE MissileFound
DEX
BPL MissileFind
JMP MissileStraight
MissileFound:
STX MSL_TGT
; Across: compare the 9-bit X positions, then step that way.
MissileSteer:
LDA MSL_XL
CMP SPN_XL,X
LDA MSL_XH
SBC SPN_XH,X
BCS MissileLeft
LDA MSL_XL
CLC
ADC #MISSILE_SPEED
STA MSL_XL
LDA MSL_XH
ADC #$00
STA MSL_XH
JMP MissileVertical
MissileLeft:
LDA MSL_XL
SEC
SBC #MISSILE_SPEED
STA MSL_XL
LDA MSL_XH
SBC #$00
STA MSL_XH
; Up or down, towards the enemy.
MissileVertical:
LDA MSL_Y
CMP SPN_Y,X
BCC MissileDown
SEC
SBC #MISSILE_SPEED
STA MSL_Y
JMP MissileCheck
MissileDown:
CLC
ADC #MISSILE_SPEED
STA MSL_Y
JMP MissileCheck
.ENDIF
MissileStraight:
LDA MSL_Y
SEC
SBC #MISSILE_SPEED
BCC MissileGone
STA MSL_Y

; Off the screen, or into a bunker?
MissileCheck:
LDA MSL_Y
CMP #$40          ; under the HUD at the top
BCC MissileGone
CMP #$F8
BCS MissileGone
LDA MSL_XH
BMI MissileGone
BEQ MissileProbe
LDA MSL_XL
CMP #$48
BCS MissileGone
MissileProbe:
LDA MSL_XL
CLC
ADC #$0B
STA PROBE_XL
LDA MSL_XH
ADC #$00
STA PROBE_XH
LDA MSL_Y
CLC
ADC #$06
STA PROBE_Y
JSR ProbeChar
JSR TerrainHit
BCS MissileGone
RTS
MissileGone:
LDA #$00
STA MSL_ON
RTS
`;

C.option = `; OPTION - an orb that follows the ship's path OPTION_GAP moves
; behind. It destroys any enemy it touches (Hits). A C64 has eight
; sprites and every one is in use, so this OPTION rams instead of
; firing - free a sprite to give it a shot of its own.
OPTION_GAP = 12    ; on the WEAPONS panel, 4-30

; The trail is 32 positions; a new one is stored only when the
; ship moves, so a still ship keeps its OPTION where it is.
OptionMove:
LDY TRAIL_POS
LDA PLAYER_XL
CMP TRAIL_XL,Y
BNE TrailPush
LDA PLAYER_Y
CMP TRAIL_Y,Y
BEQ TrailRead
TrailPush:
INY
TYA
AND #$1F
STA TRAIL_POS
TAY
LDA PLAYER_XL
STA TRAIL_XL,Y
LDA PLAYER_XH
STA TRAIL_XH,Y
LDA PLAYER_Y
STA TRAIL_Y,Y
TrailRead:
LDA TRAIL_POS
SEC
SBC #OPTION_GAP
AND #$1F
TAY
LDA TRAIL_XL,Y
STA OPT_XL
LDA TRAIL_XH,Y
STA OPT_XH
LDA TRAIL_Y,Y
STA OPT_Y
RTS
`;

// ---------------- 10 COLLISIONS / LIVES
C.hits = `; Hits - the ship against walls and enemies, and every weapon
; against every enemy. On the RULES panel:
WALLS_KILL = 1     ; 1 = flying into the canyon walls costs a ship
DROPS = 1          ; 1 = types with a DROP leave a capsule behind

Hits:
LDA PLAYER_BOOM
BEQ HitsAlive
RTS
HitsAlive:
LDA INVULN
BEQ HitsWalls
DEC INVULN
JMP HitsEnemies
HitsWalls:
.IF WALLS_KILL == 1
JSR ShipVsTerrain
BCC HitsEnemies
JSR ShipHit
.ENDIF

HitsEnemies:
LDX #$02
HitLoop:
LDA SPN_ON,X
BNE HitShip
JMP HitNext

; the ship (skipped while invulnerable)
HitShip:
LDA INVULN
ORA PLAYER_BOOM
BNE HitShot
LDA PLAYER_XL
STA BOX_XL
LDA PLAYER_XH
STA BOX_XH
LDA PLAYER_Y
STA BOX_Y
LDA #$0C
STA BOX_W
LDA #$0E
STA BOX_H
JSR BoxVsEnemy
BCS HitShot
LDA #$FF          ; ramming destroys it outright
JSR HitEnemy
JSR ShipHit
JMP HitNext

; the shot - a LASER keeps going through
HitShot:
LDA SHOT_ON
BEQ HitDouble
LDA SHOT_XL
STA BOX_XL
LDA SHOT_XH
STA BOX_XH
LDA SHOT_Y
STA BOX_Y
LDA #$09
STA BOX_W
LDA #$0E
STA BOX_H
JSR BoxVsEnemy
BCS HitDouble
LDA HAS_LASER
BNE HitShotKill
LDA #$00
STA SHOT_ON
HitShotKill:
LDA #$01
JSR HitEnemy
JMP HitNext

HitDouble:
LDA DBL_ON
BEQ HitMissile
LDA DBL_XL
STA BOX_XL
LDA DBL_XH
STA BOX_XH
LDA DBL_Y
STA BOX_Y
LDA #$0C
STA BOX_W
STA BOX_H
JSR BoxVsEnemy
BCS HitMissile
LDA #$00
STA DBL_ON
LDA #$01
JSR HitEnemy
JMP HitNext

HitMissile:
LDA MSL_ON
BEQ HitOption
LDA MSL_XL
STA BOX_XL
LDA MSL_XH
STA BOX_XH
LDA MSL_Y
STA BOX_Y
LDA #$0C
STA BOX_W
STA BOX_H
JSR BoxVsEnemy
BCS HitOption
LDA #$00
STA MSL_ON
LDA #$02          ; a missile hits twice as hard
JSR HitEnemy
JMP HitNext

HitOption:
LDA HAS_OPTION
BEQ HitNext
LDA OPT_XL
STA BOX_XL
LDA OPT_XH
STA BOX_XH
LDA OPT_Y
STA BOX_Y
LDA #$0E
STA BOX_W
LDA #$0C
STA BOX_H
JSR BoxVsEnemy
BCS HitNext
LDA #$01
JSR HitEnemy

HitNext:
DEX
BMI HitsDone
JMP HitLoop
HitsDone:
RTS

; HitEnemy - X = slot, A = damage. SPN_Hit takes it off the entity's HP
; (its type's HP in the spawn layer); carry set = destroyed: explosion,
; its type's POINTS, and a capsule if its type has a DROP.
HitEnemy:
JSR SPN_Hit
BCS EnemyDown
RTS
EnemyDown:
LDA SPN_XL,X
STA EN_BXL,X
LDA SPN_XH,X
STA EN_BXH,X
LDA SPN_Y,X
STA EN_BY,X
LDA #$18
STA EN_BOOM,X
LDY SPN_TYPE,X
LDA SPN_T_PTS,Y
JSR AddHundreds
JSR ExplosionSound
.IF DROPS == 1
LDY SPN_TYPE,X
LDA SPN_T_DROP,Y
BEQ KillDone
LDA CAP_ON
BNE KillDone
LDA #$01
STA CAP_ON
STX CAP_SLOT
LDA SPN_XL,X
STA CAP_XL
LDA SPN_XH,X
STA CAP_XH
LDA SPN_Y,X
STA CAP_Y
.ENDIF
KillDone:
RTS

; AddHundreds - A = how many hundreds to add (0-99).
AddHundreds:
STA T0
AddHundredsLoop:
LDA T0
BEQ AddHundredsDone
LDA #$01
JSR AddScore
DEC T0
JMP AddHundredsLoop
AddHundredsDone:
RTS

; ShipHit - a SHIELD soaks the hit, otherwise the ship bursts.
ShipHit:
LDA SHIELD
BEQ ShipBurst
DEC SHIELD
LDA #$30
STA INVULN
JMP ExplosionSound
ShipBurst:
LDA #$20
STA PLAYER_BOOM
LDA #$00
STA SHOT_ON
STA DBL_ON
STA MSL_ON
DEC LIVES
JMP ExplosionSound

; AddScore - A = points in hundreds (BCD).
AddScore:
SED
CLC
ADC SCORE1
STA SCORE1
LDA SCORE2
ADC #$00
STA SCORE2
CLD
RTS
`;

C.boxTest = `; BoxTest - do two sprites overlap?
;  In: BOX_XL/BOX_XH/BOX_Y  one sprite's position
;      TGT_XL/TGT_XH/TGT_Y  the other's (BoxVsShip / BoxVsEnemy set it)
;      BOX_W / BOX_H        how close counts as touching, in pixels
; Out: carry clear = touching. X and Y are kept.
; Every ACTORS frame is drawn centred, so comparing the sprites'
; corners compares their middles.
BoxVsShip:
LDA PLAYER_XL
STA TGT_XL
LDA PLAYER_XH
STA TGT_XH
LDA PLAYER_Y
STA TGT_Y
JMP BoxTest

BoxVsEnemy:
LDA SPN_XL,X
STA TGT_XL
LDA SPN_XH,X
STA TGT_XH
LDA SPN_Y,X
STA TGT_Y

BoxTest:
LDA BOX_XL
SEC
SBC TGT_XL
STA T0
LDA BOX_XH
SBC TGT_XH
STA T1           ; T1:T0 = distance in X, signed
LDA T0
CLC
ADC BOX_W
STA T0
LDA T1
ADC #$00
BNE BoxMiss      ; more than 255 apart, either way
LDA BOX_W
ASL
STA T1
LDA T0
CMP T1
BCS BoxMiss
LDA BOX_Y
SEC
SBC TGT_Y
CLC
ADC BOX_H
STA T0
LDA BOX_H
ASL
STA T1
LDA T0
CMP T1
BCS BoxMiss
CLC
RTS
BoxMiss:
SEC
RTS
`;

C.terrain = `; The scenery. Chars are tagged in the TILES charset (char editor:
; right-click a char to set its tag). The WORLD SCROLLER emits
; the tags as WORLD_TILE_TYPES. You look down on the canyon, so
; shots fly over the rock and blow up the bunkers they cross.
; On the RULES panel:
WALL_TAG = 1           ; canyon rock: wrecks the ship
TARGET_TAG = 2         ; bunkers: any shot blows them up
TARGET_POINTS = 3      ; score for a bunker, in hundreds (BCD)
ROCK_STOPS_SHOTS = 0   ; 1 = shots hit the rock instead of flying over

; TILES chars a bunker is made of, and its wreckage.
CH_HATCH_L = ${CH.HATCH_L}
CH_HATCH_R = ${CH.HATCH_R}
CH_RUBBLE = ${CH.RUBBLE}

; TerrainHit - A = tag from ProbeChar.
; Out: carry set = the weapon is stopped (a bunker is blown up too).
TerrainHit:
.IF ROCK_STOPS_SHOTS == 1
CMP #WALL_TAG
BEQ TerrainStop
.ENDIF
CMP #TARGET_TAG
BEQ TerrainTarget
CLC
RTS
TerrainTarget:
JSR BlastTarget
TerrainStop:
SEC
RTS

; BlastTarget - ($FB) is a bunker char: both halves become rubble.
BlastTarget:
LDY #$00
LDA ($FB),Y
CMP #CH_HATCH_R
BNE BlastPair
LDA $FB          ; right half hit: step back to the left half
BNE BlastDecLo
DEC $FC
BlastDecLo:
DEC $FB
BlastPair:
LDA #CH_RUBBLE
STA ($FB),Y
INY
STA ($FB),Y
LDA #TARGET_POINTS
JSR AddScore
JMP ExplosionSound

; ShipVsTerrain - carry set when the nose or a wing tip is in rock.
ShipVsTerrain:
LDA #$0B
LDY #$01
JSR ShipProbe
BCS ShipTerrainDone
LDA #$02
LDY #$0E
JSR ShipProbe
BCS ShipTerrainDone
LDA #$15
LDY #$0E
JSR ShipProbe
ShipTerrainDone:
RTS

; ShipProbe - A / Y = x / y offset into the ship sprite.
ShipProbe:
CLC
ADC PLAYER_XL
STA PROBE_XL
LDA PLAYER_XH
ADC #$00
STA PROBE_XH
TYA
CLC
ADC PLAYER_Y
STA PROBE_Y
JSR ProbeChar
CMP #WALL_TAG
BEQ ShipSolid
CMP #TARGET_TAG
BEQ ShipSolid
CLC
RTS
ShipSolid:
SEC
RTS
`;

C.probe = `; ProbeChar - which char is under a point, and what is its tag?
;  In: PROBE_XL/PROBE_XH/PROBE_Y, a point in sprite coordinates.
; Out: A = the char's tag (0 = untagged, off screen or in the HUD),
;      $FB/$FC + Y=0 = the char on the screen.
; $63 is the WORLD SCROLLER's fine Y. V never scrolls sideways:
; 40 columns, no fine X.
ProbeNone:
LDA #$00
RTS

ProbeChar:
; column = (X - 24) / 8
LDA PROBE_XL
SEC
SBC #$18
STA T0
LDA PROBE_XH
SBC #$00
BMI ProbeNone
LSR
ROR T0
LSR
ROR T0
LSR
ROR T0
LDA T0
CMP #$28
BCS ProbeNone
STA PROBE_COL
; row = (Y - 56 - fine Y) / 8: row 3 starts on line 80 + fine Y (see
; FIXED HUD / RASTER). Rows 0-2 are the HUD.
LDA PROBE_Y
SEC
SBC #$38
BCC ProbeNone
SEC
SBC $63
BCC ProbeNone
LSR
LSR
LSR
CMP #$03
BCC ProbeNone
CMP #$19
BCS ProbeNone
; $FB/$FC = $0400 + row * 40 + column
TAY
LDA ProbeRowLo,Y
CLC
ADC PROBE_COL
STA $FB
LDA ProbeRowHi,Y
ADC #$00
STA $FC
LDY #$00
LDA ($FB),Y
STA PROBE_CHAR
; Look it up in WORLD_TILE_TYPES: [char, tag] pairs, $FF ends.
ProbeScan:
LDA WORLD_TILE_TYPES,Y
CMP #$FF
BEQ ProbeNone
CMP PROBE_CHAR
BEQ ProbeTag
INY
INY
BNE ProbeScan
JMP ProbeNone
ProbeTag:
INY
LDA WORLD_TILE_TYPES,Y
RTS

ProbeRowLo:
.byte ${rowTable(false)}
ProbeRowHi:
.byte ${rowTable(true)}
`;

// ---------------- ENEMY FIRE
C.enemyFire = `; EnemyFire - the enemies shoot at the ship. All 8 sprites are taken,
; so a shot is a character: a dot drawn into the screen, rubbed out and
; drawn again every frame (SHOT DRAW). Up to 6 fly at once.
; On the ENEMY FIRE panel:
ENEMY_SHOTS = 1       ; 0 = the enemies never shoot
FIRE_RATE = 50        ; frames between shots
ENEMY_SHOT_SPEED = 2  ; pixels per frame
SHOT_CHAR = $78       ; the first of the 16 shot chars in TILES (120-135)

EnemyFire:
.IF ENEMY_SHOTS == 1
; The ship's centre in shot units: X in 2-pixel steps from the left
; edge of the screen, Y as sprites have it.
LDA PLAYER_XL
SEC
SBC #$0C          ; +12 to the middle of the ship, -24 to the edge
STA T0
LDA PLAYER_XH
SBC #$00
LSR
LDA T0
ROR
STA SHIP_CX
LDA PLAYER_Y
CLC
ADC #$0A
STA SHIP_CY
JSR MoveShots
LDA PLAYER_BOOM
BNE EFDone
; TURRET entities fire when the SPAWNER cues them (SPN_FIRE)
LDX #$02
EFCue:
LDA SPN_ON,X
BEQ EFCueNext
LDA SPN_FIRE,X
BEQ EFCueNext
JSR LaunchShot
EFCueNext:
DEX
BPL EFCue
; Every FIRE_RATE frames the next enemy in turn shoots - one that is
; above the ship and far enough away to dodge.
DEC ES_TICK
BNE EFDone
LDA #FIRE_RATE
STA ES_TICK
LDY #$03
EFPick:
LDX ES_NEXT
INX
CPX #$03
BCC EFPickSlot
LDX #$00
EFPickSlot:
STX ES_NEXT
LDA SPN_ON,X
BEQ EFPickNext
LDA SPN_Y,X
CLC
ADC #$20
BCS EFPickNext
CMP PLAYER_Y
BCS EFPickNext
JMP LaunchShot    ; its RTS ends EnemyFire
EFPickNext:
DEY
BNE EFPick
EFDone:
.ENDIF
RTS

; LaunchShot - SPAWNER slot X fires. The four-spoke spinner (the
; FAN types: ACTORS frame 10) sprays four shots along its spokes, any
; other enemy fires one shot at the ship. Keeps X.
SPIN_PTR = $AA        ; the spinner's first frame: $A0 + 10
LaunchShot:
LDY SPN_TYPE,X
LDA SPN_T_PTR,Y
CMP #SPIN_PTR
BNE LaunchAimed
JMP SprayShots
LaunchNone:
RTS
LaunchAimed:
JSR ShotStart
BCS LaunchNone
; aim: |dx| and |dy| to the ship, and their signs
LDA #$00
STA ES_SX
STA ES_SY
LDA SHIP_CX
SEC
SBC ES_X,Y
BCS AimX
EOR #$FF
ADC #$01
INC ES_SX
AimX:
STA ES_AX
LDA SHIP_CY
SEC
SBC ES_Y,Y
BCS AimY
EOR #$FF
ADC #$01
INC ES_SY
AimY:
STA ES_AY
; halve both until they are under 32, so the sums below fit a byte
AimShrink:
LDA ES_AX
CMP #$20
BCS AimHalve
LDA ES_AY
CMP #$20
BCC AimAngle
AimHalve:
LSR ES_AX
LSR ES_AY
JMP AimShrink
; ES_K = the angle from level in 22.5 degree steps, 0-4:
; tan 11.25 is about 1/5, tan 33.75 about 2/3.
AimAngle:
LDA ES_AX
CMP ES_AY
BCC AimSteep
LDA #$00          ; mostly sideways
STA ES_K
LDA ES_AY
ASL
ASL
ADC ES_AY
CMP ES_AX
BCC ShotGo         ; dy * 5 < dx: level
INC ES_K
LDA ES_AY
ASL
ADC ES_AY
STA T0
LDA ES_AX
ASL
CMP T0
BCS ShotGo         ; dy * 3 <= dx * 2: 22.5
INC ES_K
JMP ShotGo         ; 45
AimSteep:
LDA #$04          ; mostly up or down
STA ES_K
LDA ES_AX
ASL
ASL
ADC ES_AX
CMP ES_AY
BCC ShotGo         ; dx * 5 < dy: straight
DEC ES_K
LDA ES_AX
ASL
ADC ES_AX
STA T0
LDA ES_AY
ASL
CMP T0
BCS ShotGo         ; 67.5
DEC ES_K          ; 45
; ShotGo - shot Y flies at angle ES_K (0 level - 4 straight up or
; down, 22.5 degrees a step), X negative if ES_SX, Y negative if ES_SY.
ShotGo:
STX T1
LDX ES_K
LDA AimVX,X
STA ES_VXL,Y
LDA #$00
STA ES_VXH,Y
LDA AimVYL,X
STA ES_VYL,Y
LDA AimVYH,X
STA ES_VYH,Y
LDX T1
LDA ES_SX
BEQ AimXSign
LDA #$00
SEC
SBC ES_VXL,Y
STA ES_VXL,Y
LDA #$00
SBC ES_VXH,Y
STA ES_VXH,Y
AimXSign:
LDA ES_SY
BEQ AimYSign
LDA #$00
SEC
SBC ES_VYL,Y
STA ES_VYL,Y
LDA #$00
SBC ES_VYH,Y
STA ES_VYH,Y
AimYSign:
LDA #$01
STA ES_ON,Y
RTS

; ShotStart - a free shot (Y) at the middle of SPAWNER slot X.
; Carry set: no shot (all flying, or the enemy is off the playfield).
ShotStart:
LDY #$05
SSFind:
LDA ES_ON,Y
BEQ SSFree
DEY
BPL SSFind
SSNone:
SEC
RTS
SSFree:
LDA SPN_Y,X
CLC
ADC #$0A
CMP #$5A
BCC SSNone
CMP #$F0
BCS SSNone
STA ES_Y,Y
LDA SPN_XL,X
SEC
SBC #$0C
STA T0
LDA SPN_XH,X
SBC #$00
BMI SSNone
LSR
LDA T0
ROR
CMP #$A0
BCS SSNone
STA ES_X,Y
LDA #$80
STA ES_XF,Y
STA ES_YF,Y
CLC
RTS

; SprayShots - spinner slot X fires along its four spokes. It is drawn
; as an X (frame +0) or a + (frame +1), swapped every 8 frames: the X
; shoots the diagonals, the + straight across and up and down.
SprayShots:
LDA ANIM
LSR
AND #$04          ; frame +1: spokes 4-7
STA T2
LDA #$04
STA ES_AX         ; spokes to go
SprayLoop:
JSR ShotStart
BCS SprayDone
STX ES_AY
LDX T2
LDA SprayK,X
STA ES_K
LDA SpraySX,X
STA ES_SX
LDA SpraySY,X
STA ES_SY
LDX ES_AY
JSR ShotGo
INC T2
DEC ES_AX
BNE SprayLoop
SprayDone:
RTS
; spokes 0-3: the X, 4-7: the +
SprayK:
.byte $02,$02,$02,$02,$00,$00,$04,$04
SpraySX:
.byte $00,$01,$00,$01,$00,$01,$00,$00
SpraySY:
.byte $00,$00,$01,$01,$00,$00,$00,$01

; 1 pixel per frame at each angle, 8.8: X in shot units (2 pixels),
; so cos / 2; Y in pixels, sin.
AimVX:
.byte $80,$76,$5B,$31,$00
AimVYL:
.byte $00,$62,$B5,$ED,$00
AimVYH:
.byte $00,$00,$00,$00,$01

; MoveShots - ENEMY_SHOT_SPEED steps a frame; off the playfield they go,
; into the ship they cost a life (or a SHIELD hit).
MoveShots:
LDX #$05
ESMove:
LDA ES_ON,X
BNE ESLive
JMP ESNext
ESLive:
LDY #ENEMY_SHOT_SPEED
ESStep:
LDA ES_XF,X
CLC
ADC ES_VXL,X
STA ES_XF,X
LDA ES_X,X
ADC ES_VXH,X
STA ES_X,X
LDA ES_YF,X
CLC
ADC ES_VYL,X
STA ES_YF,X
LDA ES_Y,X
ADC ES_VYH,X
STA ES_Y,X
DEY
BNE ESStep
LDA ES_X,X
CMP #$A0          ; past either side (left wraps round to $FF)
BCS ESOff
LDA ES_Y,X
CMP #$5A          ; up into the band under the HUD
BCC ESOff
CMP #$F4          ; the bottom border
BCS ESOff
JMP ESInside
ESOff:
LDA #$00
STA ES_ON,X
JMP ESNext
ESInside:
; our shot, DOUBLE or MISSILE meets it: both are gone (a LASER keeps
; going)
LDA SHOT_ON
BEQ ESCDouble
LDA SHOT_XL
STA T0
LDA SHOT_XH
STA T1
LDA SHOT_Y
STA T2
JSR ShotVsWeapon
BCS ESCDouble
LDA HAS_LASER
BNE ESCancel
LDA #$00
STA SHOT_ON
JMP ESCancel
ESCDouble:
LDA DBL_ON
BEQ ESCMissile
LDA DBL_XL
STA T0
LDA DBL_XH
STA T1
LDA DBL_Y
STA T2
JSR ShotVsWeapon
BCS ESCMissile
LDA #$00
STA DBL_ON
JMP ESCancel
ESCMissile:
LDA MSL_ON
BEQ ESShip
LDA MSL_XL
STA T0
LDA MSL_XH
STA T1
LDA MSL_Y
STA T2
JSR ShotVsWeapon
BCS ESShip
LDA #$00
STA MSL_ON
ESCancel:
LDA #$00
STA ES_ON,X
JMP ESNext
ESShip:
LDA PLAYER_BOOM
ORA INVULN
BNE ESNext
LDA ES_X,X        ; within 8 pixels across...
SEC
SBC SHIP_CX
CLC
ADC #$03
CMP #$07
BCS ESNext
LDA ES_Y,X        ; ...and 7 down
SEC
SBC SHIP_CY
CLC
ADC #$07
CMP #$0E
BCS ESNext
LDA #$00
STA ES_ON,X
JSR ShipHit
JMP ESNext
ESNext:
DEX
BMI ESDone
JMP ESMove
ESDone:
RTS

; ShotVsWeapon - does enemy shot X touch our weapon sprite at
; T0/T1 (X, 9 bits) / T2 (Y)? Carry clear: yes. Within 10 pixels each
; way of the sprite's middle (+12, +9); the shot's middle is +2, +2.
ShotVsWeapon:
LDA T0
SEC
SBC #$0E          ; +12 to the middle, -24 to the edge, -2 for the shot
STA T0
LDA T1
SBC #$00
BMI SVWMiss
LSR
LDA T0
ROR               ; in shot units (2 pixels)
SEC
SBC ES_X,X
CLC
ADC #$05
CMP #$0B
BCS SVWMiss
LDA T2
CLC
ADC #$07          ; +9 to the middle, -2 for the shot
SEC
SBC ES_Y,X
CLC
ADC #$0A
CMP #$15
BCS SVWMiss
CLC
RTS
SVWMiss:
SEC
RTS
`;

C.shotDraw = `; EraseShots - before the WORLD SCROLLER moves the screen: put back the
; char under every drawn shot, so the scroll never carries a shot along.
EraseShots:
LDX #$05
ESErase:
LDA ES_SHOWN,X
BEQ ESEraseNext
LDA ES_AL,X
STA $FB
LDA ES_AH,X
STA $FC
LDA ES_UNDER,X
LDY #$00
STA ($FB),Y
TYA
STA ES_SHOWN,X
ESEraseNext:
DEX
BPL ESErase
RTS

; DrawShots - after the scroll: each flying shot into the screen. A shot
; that meets a tagged char (rock, a bunker) is gone; one that meets
; another shot waits a frame.
DrawShots:
LDX #$05
ESDraw:
LDA ES_ON,X
BEQ ESDrawNext
LDA ES_X,X        ; sprite X = 24 + 2 * X
ASL
STA T0
LDA #$00
ROL
STA T1
LDA T0
CLC
ADC #$18
STA PROBE_XL
LDA T1
ADC #$00
STA PROBE_XH
LDA ES_Y,X
STA PROBE_Y
JSR ProbeChar
BEQ ESFree
LDA #$00
STA ES_ON,X
JMP ESDrawNext
ESFree:
LDA PROBE_CHAR
SEC
SBC #SHOT_CHAR
CMP #$10
BCC ESDrawNext
LDA $FB
STA ES_AL,X
LDA $FC
STA ES_AH,X
LDA PROBE_CHAR
STA ES_UNDER,X
LDA #$01
STA ES_SHOWN,X
; which shot char: 2-pixel steps down and across the cell
LDA ES_Y,X
SEC
SBC #$38
SEC
SBC $63
AND #$06
ASL
STA T0
LDA ES_X,X
AND #$03
ORA T0
CLC
ADC #SHOT_CHAR
LDY #$00
STA ($FB),Y
ESDrawNext:
DEX
BPL ESDraw
RTS
`;

// ---------------- 11 SPRITE DRAW
C.draw = `; DrawActors - copy the game state into the VIC sprite registers.
; Sprites: 0 ship, 1 shot/laser, 2 DOUBLE, 3 MISSILE, 4 OPTION,
; 5-7 the three SPAWNER slots (or the capsule, in a free slot).
; Colours - on the COLOURS panel (enemy colours are their spawn types).
SHIP_COL = 1
SHIELD_COL = 14
SHOT_COL = 7
LASER_COL = 3
MISSILE_COL = 10
OPTION_COL = 8
CAPSULE_COL = 2
BOOM_COL = 7

; ACTORS frames as sprite pointers ($2800 / 64 = $A0 is frame 0).
FR_BASE = $A0
FR_SHIP = $A0
FR_SHIP_FLAME = $A1   ; +1 bank left, +2 bank right
FR_SHOT = $A4
FR_LASER = $A5
FR_DOUBLE = $A6
FR_MISSILE = $A7
FR_OPTION = $A8
FR_CAPSULE = $B2
FR_BOOM = $B4

DrawActors:
LDA #$00
STA SPR_ON
STA SPR_MSB

; --- sprite 0: the ship ---
LDA PLAYER_XL
STA D_XL
LDA PLAYER_XH
STA D_XH
LDA PLAYER_Y
STA D_Y
LDA PLAYER_BOOM
BEQ ShipFlying
JSR BoomFrame
JMP ShipPut
ShipFlying:
LDA INVULN          ; blink while it cannot be hit
AND #$04
BNE DrawShot
LDA SHIP_TILT
BEQ ShipLevel
CLC
ADC #FR_SHIP_FLAME
STA D_PTR
JMP ShipColour
ShipLevel:
LDA ANIM            ; exhaust flicker
AND #$02
LSR
CLC
ADC #FR_SHIP
STA D_PTR
ShipColour:
LDA #SHIP_COL
LDY SHIELD
BEQ ShipColourSet
LDA #SHIELD_COL
ShipColourSet:
STA D_COL
ShipPut:
LDX #$00
JSR PutSprite

; --- sprite 1: shot or laser ---
DrawShot:
LDA SHOT_ON
BEQ DrawDouble
LDA SHOT_XL
STA D_XL
LDA SHOT_XH
STA D_XH
LDA SHOT_Y
STA D_Y
LDA #FR_SHOT
LDY #SHOT_COL
LDX HAS_LASER
BEQ ShotLook
LDA #FR_LASER
LDY #LASER_COL
ShotLook:
STA D_PTR
STY D_COL
LDX #$01
JSR PutSprite

; --- sprite 2: DOUBLE ---
DrawDouble:
LDA DBL_ON
BEQ DrawMissile
LDA DBL_XL
STA D_XL
LDA DBL_XH
STA D_XH
LDA DBL_Y
STA D_Y
LDA #FR_DOUBLE
STA D_PTR
LDA #SHOT_COL
STA D_COL
LDX #$02
JSR PutSprite

; --- sprite 3: MISSILE ---
DrawMissile:
LDA MSL_ON
BEQ DrawOption
LDA MSL_XL
STA D_XL
LDA MSL_XH
STA D_XH
LDA MSL_Y
STA D_Y
LDA #FR_MISSILE
STA D_PTR
LDA #MISSILE_COL
STA D_COL
LDX #$03
JSR PutSprite

; --- sprite 4: OPTION ---
DrawOption:
LDA HAS_OPTION
BEQ DrawEnemies
LDA PLAYER_BOOM
BNE DrawEnemies
LDA OPT_XL
STA D_XL
LDA OPT_XH
STA D_XH
LDA OPT_Y
STA D_Y
LDA ANIM
LSR
LSR
LSR
AND #$01
CLC
ADC #FR_OPTION
STA D_PTR
LDA #OPTION_COL
STA D_COL
LDX #$04
JSR PutSprite
`;

C.drawEnemies = `; --- sprites 5-7: SPAWNER slots 0-2 ---
; A live entity shows its type's frame pair (SPN_T_PTR + 0 / 1) and
; colour; otherwise the slot's explosion; otherwise the capsule, if it
; is borrowing this slot.
DrawEnemies:
LDA #$02
STA T2
DrawEnemyLoop:
LDY T2
LDA SPN_ON,Y
BEQ DrawEnemyBoom
LDA SPN_XL,Y
STA D_XL
LDA SPN_XH,Y
STA D_XH
LDA SPN_Y,Y
STA D_Y
LDA SPN_TYPE,Y
TAX
LDA ANIM            ; two frames, swapped every 8 frames
LSR
LSR
LSR
AND #$01
CLC
ADC SPN_T_PTR,X
STA D_PTR
LDA SPN_T_COL,X
STA D_COL
JMP DrawEnemyPut
DrawEnemyBoom:
LDA EN_BOOM,Y
BEQ DrawCapsule
LDA EN_BXL,Y
STA D_XL
LDA EN_BXH,Y
STA D_XH
LDA EN_BY,Y
STA D_Y
LDA EN_BOOM,Y
JSR BoomFrame
DrawEnemyPut:
LDA T2
CLC
ADC #$05
TAX
JSR PutSprite
JMP DrawEnemyNext

; A free slot may be lending its sprite to the capsule.
DrawCapsule:
LDA CAP_ON
BEQ DrawEnemyNext
CPY CAP_SLOT
BNE DrawEnemyNext
LDA CAP_XL
STA D_XL
LDA CAP_XH
STA D_XH
LDA CAP_Y
STA D_Y
LDA ANIM
LSR
LSR
AND #$01
CLC
ADC #FR_CAPSULE
STA D_PTR
LDA #CAPSULE_COL
STA D_COL
LDA ANIM            ; flash white
AND #$08
BEQ DrawEnemyPut
LDA #$01
STA D_COL
JMP DrawEnemyPut

DrawEnemyNext:
DEC T2
BMI DrawEnemiesDone
JMP DrawEnemyLoop
DrawEnemiesDone:

; All sprites placed: switch on exactly the ones in use.
LDA SPR_ON
STA $D015
LDA SPR_MSB
STA $D010
RTS
`;

C.putSprite = `; PutSprite - sprite X (0-7) at D_XL/D_XH/D_Y, pointer D_PTR,
; colour D_COL; marks it in SPR_ON and the ninth-bit mask SPR_MSB.
; A sprite whose top is above PLAY_TOP would show over the HUD, so it
; stays switched off until it is all the way into the playfield.
PLAY_TOP = $4B
PutSprite:
LDA D_Y
CMP #PLAY_TOP
BCS PutShow
RTS
PutShow:
LDA D_PTR
STA $07F8,X
LDA D_COL
STA $D027,X
LDA SprBit,X
ORA SPR_ON
STA SPR_ON
LDA D_XH
BEQ PutLowX
LDA SprBit,X
ORA SPR_MSB
STA SPR_MSB
PutLowX:
TXA
ASL
TAY
LDA D_XL
STA $D000,Y
LDA D_Y
STA $D001,Y
RTS
SprBit:
.byte $01,$02,$04,$08,$10,$20,$40,$80

; BoomFrame - A = explosion timer -> one of the four BOOM frames.
BoomFrame:
LSR
LSR
LSR
CMP #$04
BCC BoomStep
LDA #$03
BoomStep:
EOR #$03          ; counts down, so big timer = first frame
CLC
ADC #FR_BOOM
STA D_PTR
LDA #BOOM_COL
STA D_COL
RTS
`;

// ---------------- 12 HUD VALUES
C.status = `; Status - numbers and meter colours into the fixed HUD (rows 0-2,
; drawn by the TOP STATUS macro from the STATUS asset).
; Meter colours - on the HUD panel.
METER_COL = 14       ; a slot you can buy
METER_LIT_COL = 7    ; the lit slot (flashes white)
METER_OWNED_COL = 11 ; a power you already own

Status:
LDY #$07          ; score at row 0, column 7 (the HUD adds "00")
LDA SCORE2
JSR PutBcd
LDA SCORE1
JSR PutBcd
LDY #$14          ; high score at column 20
LDA HI2
JSR PutBcd
LDA HI1
JSR PutBcd
LDA LIVES         ; ships at column 37
CLC
ADC #$30
STA $0425

; Meter word n is 5 cells of colour RAM at row 1, column 2 + 6n.
LDX #$00
LDY #$00
MeterLoop:
JSR MeterColour
STA $D82A,Y
STA $D82B,Y
STA $D82C,Y
STA $D82D,Y
STA $D82E,Y
TYA
CLC
ADC #$06
TAY
INX
CPX #$06
BNE MeterLoop
RTS

; MeterColour - A = colour for meter slot X (0-5).
MeterColour:
TXA
CLC
ADC #$01
CMP METER
BNE MeterNotLit
LDA ANIM
AND #$08
BEQ MeterLit
LDA #$01
RTS
MeterLit:
LDA #METER_LIT_COL
RTS
MeterNotLit:
CPX #$00          ; SPEED can be bought again
BEQ MeterNormal
LDA POWERS,X
BEQ MeterNormal
LDA #METER_OWNED_COL
RTS
MeterNormal:
LDA #METER_COL
RTS

; PutBcd - BCD byte A as two digits at $0400 + Y; Y moves on by 2.
PutBcd:
PHA
LSR
LSR
LSR
LSR
CLC
ADC #$30
STA $0400,Y
INY
PLA
AND #$0F
CLC
ADC #$30
STA $0400,Y
INY
RTS
`;

// ---------------- 13 FIXED HUD / RASTER
C.raster = `; The raster IRQ callbacks (STARTUP column). The HUD rows are hires
; and never scroll; the playfield below is multicolour, 40 columns (it
; only scrolls up and down), with the WORLD SCROLLER's fine Y ($63).
;
; The VIC starts a char row on any line whose low 3 bits equal fine Y,
; so the playfield's first row can only start on line 80 + fine Y. Fine
; Y has to reach the VIC late enough that no earlier line matches it,
; or the world jumps a char every 8 pixels:
;   line 72  park fine Y on 1 - no line from 74 to 79 matches it
;   line 78  the real fine Y (line 80 for fine Y 7), in ECM + multicolour:
;            an invalid mode, so the rows still starting show black
;   line 86  switch ECM off at the end of line 88
; Lines 75-88 are a black band under the HUD that hides the row edge;
; the playfield shows from line 89.
HudFixed:
LDA #$1B          ; fine Y 3: HUD row 0 starts on the first visible line
STA $D011
LDA #$08
STA $D016
RTS

HudPlayfield:
LDA $D012
CMP #$4A          ; wait for line 74 (HUD row 2's last line)
BCC HudPlayfield
LDA #$11          ; fine Y 1, before line 75 can start a row
STA $D011
RTS

HudScroll:
LDA $63
AND #$07
TAX
ORA #$50          ; ECM + screen on + fine Y
TAY
LDA #$4F          ; line 79
CPX #$07
BNE HudScrollWait
LDA #$50          ; fine Y 7 would match line 79 itself: line 80
HudScrollWait:
CMP $D012
BCC HudScrollSet  ; past the line
BNE HudScrollWait ; not there yet
HudScrollSet:
STY $D011
LDA #$18          ; multicolour, 40 columns
STA $D016
RTS

; Line 88 starts a char row when fine Y is 0, and the VIC then holds the
; CPU until the right border - so the switch lands there for every fine
; Y: the other seven wait the same time in a delay loop. Line 88 stays
; black, the playfield shows from line 89.
HudReveal:
LDA $63
AND #$07
TAX
ORA #$10          ; ECM off: the playfield shows
TAY
HudRevealWait:
LDA $D012
CMP #$58          ; line 88
BCC HudRevealWait
CPX #$00
BEQ HudRevealSet  ; fine Y 0: the char row fetch is the delay
LDX #$08
HudRevealDelay:
DEX
BNE HudRevealDelay
HudRevealSet:
STY $D011
RTS

HudNmi:
RTI
`;

// ---------------- 14 EXPLOSIONS / SFX
C.silence = `; SilenceGame - quiet the title tune's three voices, then set up the
; SFX player.
SilenceGame:
LDA #$00
STA $D404
STA $D40B
STA $D412
`;
C.sfxExplosionEntry = `RTS

; ExplosionSound keeps X (it is called from the enemy loops).
ExplosionSound:
TXA
PHA
`;
C.sfxCapsuleEntry = `PLA
TAX
RTS

CapsuleSound:
`;
C.sfxPowerEntry = `RTS

PowerSound:
`;
C.sfxTickEntry = `RTS

; SfxTick - once per frame from GameLoop.
SfxTick:
`;
C.effects = `RTS

; Effects - run the explosion timers. When the ship's burst ends:
; another ship, or GAME OVER back to the title.
Effects:
LDX #$02
EffectEnemy:
LDA EN_BOOM,X
BEQ EffectNext
DEC EN_BOOM,X
EffectNext:
DEX
BPL EffectEnemy
LDA PLAYER_BOOM
BEQ EffectsDone
DEC PLAYER_BOOM
BNE EffectsDone
LDA LIVES
BEQ GameOver
JMP ResetActors
EffectsDone:
RTS

; GameOver - keep the best score, then back to the title.
GameOver:
LDA SCORE2
CMP HI2
BCC GameOverTitle
BNE GameOverHi
LDA SCORE1
CMP HI1
BCC GameOverTitle
GameOverHi:
LDA SCORE2
STA HI2
LDA SCORE1
STA HI1
GameOverTitle:
SEI
LDA #$00
STA $D01A          ; raster IRQs off before the KERNAL comes back
STA $D015
LDA #$FF
STA $D019
JSR SilenceGame
JMP BootTitle
`;
