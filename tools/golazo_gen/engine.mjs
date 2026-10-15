// Engine code blocks: boot, raster IRQ chain (HUD split + sprite
// multiplexer), double-buffered 8-way scroller, camera, sprite list
// building, input, maths and sound.
import { CONSTS as C } from './defs.mjs';

export const BOOT = `
// GOLAZO 64 - boot: all RAM + I/O, CIA interrupts off, raster IRQ chain on
// @asset GOLAZO_CHARS
// @asset GOLAZO_SPRITES
Boot:
 LDA #$35
 STA $01
 LDA #$7F
 STA $DC0D
 STA $DD0D
 LDA $DC0D
 LDA $DD0D
 LDA #$00
 STA $D01A
 STA $D015
 LDA #$FF
 STA $D019
 LDX #$10
 LDA #$00
BootZp:
 STA $00,X
 INX
 CPX #$80
 BNE BootZp
 LDY #$00
 STY Z_PTR
 LDA #$C0
 STA Z_PTRH
 LDX #$10
 TYA
BootVar:
 STA (Z_PTR),Y
 INY
 BNE BootVar
 INC Z_PTRH
 DEX
 BNE BootVar
 LDA #<NmiRti
 STA $FFFA
 LDA #>NmiRti
 STA $FFFB
 JSR VicInit
 JSR SoundInit
 LDA #<IrqBottom
 STA $FFFE
 LDA #>IrqBottom
 STA $FFFF
 LDA #$1B
 STA $D011
 LDA #$FC
 STA $D012
 LDA #$01
 STA $D01A
 LDA #$FF
 STA $D019
 LDA #$5A
 STA RNG
 CLI
 JMP Title
`;

// Raster IRQ chain. $FC: apply the frame the main loop committed, HUD
// scroll, first 8 sprites, sound. $3F: HUD/pitch split (fine Y scroll by
// moving the first pitch badline), then the multiplexer re-uses sprites.
// Display-list entry j always goes to hardware sprite j & 7, so each slot
// has its own unrolled handler (IrqM0-7); entry j is set on line DLT =
// (Y of entry j-8) + 22, the first line after that sprite has finished.
const hx = (v, n = 4) => '$' + v.toString(16).toUpperCase().padStart(n, '0');
function setSlot(k, off) {
  const o = off ? '+' + off : '';
  return [
    ` LDA DLY${o},Y`, ` STA ${hx(0xD001 + 2 * k)}`,
    ` LDA DLXL${o},Y`, ` STA ${hx(0xD000 + 2 * k)}`,
    ` LDA DLXH${o},Y`, ' STA $D010',
    ` LDA DLC${o},Y`, ` STA ${hx(0xD027 + k)}`,
    ` LDA DLP${o},Y`, ` STA ${hx(C.SCRA + 0x3F8 + k)}`, ` STA ${hx(C.SCRB + 0x3F8 + k)}`].join('\n');
}
function muxHandlers() {
  const L = [];
  for (let k = 0; k < 8; k++) {
    const n = (k + 1) & 7;
    L.push(`IrqM${k}:`, ' STA Z_SA', ' STX Z_SX', ' STY Z_SY', ' LDY Z_MUX', `MS${k}:`, setSlot(k, 0), ' INY',
      // next entry: due within a line -> wait and set it here, else IRQ on its line
      `MN${k}:`, ' LDA DLY,Y', ' CMP #$FF', ' BEQ MuxDone', ' LDA DLT,Y', ' SEC', ' SBC #$01', ' CMP $D012',
      ` BCC MW${k}`, ` BEQ MW${k}`, ' ADC #$00', ' STA $D012', ' STY Z_MUX',
      ` LDA #<IrqM${n}`, ' STA $FFFE', ` LDA #>IrqM${n}`, ' STA $FFFF', ' JMP IrqRet',
      `MW${k}:`, ' LDA DLT,Y', `MWL${k}:`, ' CMP $D012', ` BEQ MS${n}J`, ` BCS MWL${k}`, `MS${n}J:`, ` JMP MS${n}`);
  }
  return L.join('\n');
}
function bottomSprites() {
  const L = [' LDY FRONT_DL'];
  for (let k = 0; k < 8; k++) {
    const o = k ? '+' + k : '';
    L.push(` LDA DLY${o},Y`, ' CMP #$FF', ` BEQ IbE${k}`, setSlot(k, k));
  }
  L.push(' LDA #$FF', ' STA $D015', ' TYA', ' CLC', ' ADC #$08', ' STA Z_MUX', ' JMP IbSprEnd');
  for (let k = 0; k < 8; k++) {
    L.push(`IbE${k}:`, ` LDA #${hx((1 << k) - 1, 2)}`, ' STA $D015', ' TYA');
    if (k) L.push(' CLC', ` ADC #${hx(k, 2)}`);
    L.push(' STA Z_MUX', ' JMP IbSprEnd');
  }
  return L.join('\n');
}
export const IRQ = `
IrqBottom:
 STA Z_SA
 STX Z_SX
 STY Z_SY
 LDA READY
 BEQ IbKeep
 LDA NEW_DL
 STA FRONT_DL
 LDA NEW_D016
 STA CUR_D016
 LDA NEW_S
 STA CUR_S
 LDA NEW_FLIP
 BEQ IbNoFlip
 LDA CUR_D018
 EOR #$10
 STA CUR_D018
IbNoFlip:
 LDA #$00
 STA READY
IbKeep:
 LDA CUR_D018
 STA $D018
 LDA #$1B
 STA $D011
 LDA HUD_D016
 STA $D016
${bottomSprites()}
IbSprEnd:
 JSR SoundUpdate
 INC FRAMECNT
 LDA #$3F
 STA $D012
 LDA #<IrqSplit
 STA $FFFE
 LDA #>IrqSplit
 STA $FFFF
 JMP IrqRet
IrqSplit:
 STA Z_SA
 STX Z_SX
 STY Z_SY
 LDA CUR_S
 BNE IsWait
 LDA #$18
 STA $D011
 JMP IsGo
IsWait:
 ORA #$18
 TAX
IsLoop:
 LDA $D012
 CMP #$40
 BCC IsLoop
 STX $D011
IsGo:
 LDA CUR_D016
 STA $D016
 LDY Z_MUX
 JMP MN7
${muxHandlers()}
MuxDone:
 LDA #$FC
 STA $D012
 LDA #<IrqBottom
 STA $FFFE
 LDA #>IrqBottom
 STA $FFFF
IrqRet:
 ASL $D019
 LDA Z_SA
 LDX Z_SX
 LDY Z_SY
NmiRti:
 RTI
`;

export const VIC = `
VicInit:
 LDA $DD02
 ORA #$03
 STA $DD02
 LDA $DD00
 AND #$FC
 ORA #$02
 STA $DD00
 LDA #$00
 STA $D020
 STA $D021
 STA $D017
 STA $D01D
 STA $D01B
 STA $D026
 LDA #$05
 STA $D022
 LDA #$0D
 STA $D023
 LDA #$0A
 STA $D025
 LDA #$FF
 STA $D01C
 LDA #D018_A
 STA CUR_D018
 LDA #$18
 STA HUD_D016
 STA CUR_D016
 LDA #$03
 STA CUR_S
 LDA #$FF
 STA DLY
 STA DLY+32
 LDA #$00
 STA FRONT_DL
 STA READY
 LDA #$FF
 STA $DC02
 STA $DC00
 LDA #$00
 STA $DC03
 RTS
// wait for the next frame (the $FC IRQ applies a committed frame first)
// wait until the IRQ has shown the committed frame
FrameSync:
 LDA #$00
 STA WAITCNT
 LDA CMT_FC
FsWait:
 INC WAITCNT
 CMP FRAMECNT
 BEQ FsWait
 LDA WAITCNT
 CMP WAITMIN
 BCS FsRts
 STA WAITMIN
FsRts:
 LDA FRAMECNT
 STA ITER_FC
 RTS
// hand the prepared frame to the IRQ (scroll from CAM1)
Commit:
 LDA FRAMECNT
 CMP ITER_FC
 BEQ CmInTime
 INC OVRCNT
 BNE CmInTime
 INC OVRCNT+1
CmInTime:
 INC ITERCNT
 BNE CmIt
 INC ITERCNT+1
CmIt:
 LDA BACK_DL
 STA NEW_DL
 LDA TITLE_MODE
 BNE CmTitle
 LDA CAM1X
 AND #$07
 EOR #$07
 ORA #$10
 STA NEW_D016
 LDA CAM1Y
 AND #$07
 EOR #$07
 STA NEW_S
 JMP CmFlip
CmTitle:
 LDA #$18
 STA NEW_D016
 LDA #$03
 STA NEW_S
CmFlip:
 LDA FLIP_REQ
 STA NEW_FLIP
 LDA #$00
 STA FLIP_REQ
 SEI
 LDA FRAMECNT
 STA CMT_FC
 LDA #$01
 STA READY
 CLI
 RTS
`;

// Unrolled redraw routines live in their own ORG column so the patch code
// can address their operands directly. 39 columns x 23 rows, split in two
// halves (12 + 11 rows) so a coarse scroll costs two frames of half work.
export const PARTS = [[0, 4], [4, 4], [8, 4], [12, 4], [16, 4], [20, 3]];    // [first row, rows]
C.NSL = PARTS.length;
// RdP<slice><buffer>: A = map lo of the slice's first row, X = map hi of its
// even rows, Y = map hi of its odd rows (rows are 128 apart). The routine
// patches its own LDA operands, then copies 39 columns.
export function redrawBlock(org) {
  const L = [];
  let a = org;
  const hx = v => '$' + v.toString(16).toUpperCase().padStart(4, '0');
  for (const [buf, scr] of [['A', C.SCRA], ['B', C.SCRB]]) {
    PARTS.forEach(([r0, n], p) => {
      const name = 'RdP' + p + buf;
      const patch = n * 3 + (n - 1) * 2 + n * 3 + 2 * Math.floor(n / 2);
      const loop = a + patch + 2;
      const op = k => loop + k * 6 + 1;
      L.push(name + ':');
      for (let k = 0; k < n; k++) {
        L.push(' STA ' + hx(op(k)));
        if (k < n - 1) L.push(' EOR #$80');
      }
      for (let k = 0; k < n; k++) {
        L.push((k & 1 ? ' STY ' : ' STX ') + hx(op(k) + 1));
        if (k & 1) L.push(' INX', ' INY');
      }
      L.push(' LDX #$26', name + 'L:');
      for (let k = 0; k < n; k++) {
        L.push(' LDA $8000,X');
        L.push(' STA ' + hx(scr + (2 + r0 + k) * 40) + ',X');
      }
      L.push(' DEX', ' BPL ' + name + 'L', ' RTS');
      a = loop + n * 6 + 4;    // DEX, BPL, RTS
    });
  }
  return { text: '// unrolled screen redraw in ' + PARTS.length + ' slices (self-patching map operands)\n' + L.join('\n') + '\n', consts: {}, end: a };
}
function drawDispatch() {
  const L = [];
  for (const buf of ['B', 'A']) {
    L.push('Dp' + buf + ':', ' LDA Z_K');
    PARTS.forEach((_, p) => { if (p < PARTS.length - 1) L.push(p ? ' CMP #$0' + p : '', ' BEQ Dp' + buf + p); });
    L.push(' LDA Z_T0', ' JMP RdP' + (PARTS.length - 1) + buf);
    PARTS.forEach((_, p) => { if (p < PARTS.length - 1) L.push('Dp' + buf + p + ':', ' LDA Z_T0', ' JMP RdP' + p + buf); });
  }
  return L.filter(Boolean).join('\n');
}

export const SCROLL = `
// A = map row, X = map column -> Z_PTR = MAP + row*128 + col
RdBase:
 LSR
 STA Z_T0
 LDA #$00
 ROR
 STA Z_PTR
 TXA
 CLC
 ADC Z_PTR
 STA Z_PTR
 LDA Z_T0
 ADC #>MAP
 STA Z_PTRH
 RTS
// draw slice Z_K (0-5) of map cell (PRE_C, PRE_R) into the back screen
DrawPart:
 LDA #$00
 STA BK_OK
 LDA Z_K
 ASL
 ASL
 CLC
 ADC PRE_R
 LDX PRE_C
 JSR RdBase
 LDX Z_PTRH
 LDY Z_PTRH
 LDA Z_PTR
 BPL DpEven
 INY
DpEven:
 STA Z_T0
 LDA CUR_D018
 AND #$10
 BEQ DpB
 JMP DpA
${drawDispatch()}
// After the frame is committed: the slice the camera needs now, the
// deferred AI, then more slices of the prepared cell while there is time.
IdleWork:
 JSR IwUrgent
 JSR IdleAI
 JMP IwMore
IwUrgent:
 LDA RD_BUSY
 STA Z_T6
IwU:
 LDA Z_T6
 BEQ IwRts
 JSR IwCan
 BCC IwRts
 JSR IwSlice
 DEC Z_T6
 JMP IwU
IwMore:
 JSR IwCan
 BCC IwRts
IwLoop:
 LDA #IDLE_LIM
 JSR IdleChk
 BCC IwRts
 JSR IwSlice
 LDA PRE_ST
 CMP #NSL
 BCC IwLoop
IwRts:
 RTS
// C=1 if the prepared cell still needs slices (and no flip is pending)
IwCan:
 LDA PRE_ON
 BEQ IwNo
 LDA READY
 BEQ IwCan2
 LDA NEW_FLIP
 BNE IwNo
IwCan2:
 LDA PRE_ST
 CMP #NSL
 BCS IwNo
 SEC
 RTS
IwNo:
 CLC
 RTS
IwSlice:
 LDA PRE_ST
 STA Z_K
 JSR DrawPart
 INC PRE_ST
 RTS
// A = last raster line to start some work: C=1 if it may start now
// (same frame, raster before that line or still in the top border)
IdleChk:
 STA Z_T7
 LDA FRAMECNT
 CMP ITER_FC
 BNE IoNo
 LDA $D011
 BMI IoYes
 LDA $D012
 CMP #$FC
 BCS IoYes
 CMP Z_T7
 BCC IoYes
IoNo:
 CLC
 RTS
IoYes:
 SEC
 RTS
`;

export const CAMERA = `
// Camera target from the ball: X 0..712, Y 0..200
CamTarget:
 LDA PXL+BALL
 SEC
 SBC #152
 STA CAMTX
 LDA PXH+BALL
 SBC #$00
 STA CAMTX+1
 BPL CtXpos
 LDA #$00
 STA CAMTX
 STA CAMTX+1
 JMP CtY
CtXpos:
 CMP #$02
 BCC CtY
 BNE CtXmax
 LDA CAMTX
 CMP #$C8
 BCC CtY
CtXmax:
 LDA #$C8
 STA CAMTX
 LDA #$02
 STA CAMTX+1
CtY:
 LDA PYL+BALL
 SEC
 SBC BZH
 STA Z_T0
 LDA PYH+BALL
 SBC #$00
 STA Z_T1
 LDA Z_T0
 SEC
 SBC #96
 STA Z_T0
 LDA Z_T1
 SBC #$00
 BMI CtYmin
 BNE CtYmax
 LDA Z_T0
 CMP #200
 BCC CtYok
CtYmax:
 LDA #200
 STA CAMTY
 RTS
CtYmin:
 LDA #$00
 STA CAMTY
 RTS
CtYok:
 STA CAMTY
 RTS
// Z_DX = signed distance, Z_T0 = max step, Z_T2 = dead zone -> A = signed step
CamStepCalc:
 LDA Z_DXH
 BMI CscNeg
 BNE CscMaxP
 LDA Z_DX
 SEC
 SBC Z_T2
 BCC CscZero
 BEQ CscZero
 LSR
 LSR
 BNE CscPos
 LDA #$01
CscPos:
 CMP Z_T0
 BCC CscRts
CscMaxP:
 LDA Z_T0
CscRts:
 RTS
CscZero:
 LDA #$00
 RTS
CscNeg:
 LDA #$00
 SEC
 SBC Z_DX
 STA Z_DX
 LDA #$00
 SBC Z_DXH
 STA Z_DXH
 JSR CamStepCalc
 EOR #$FF
 CLC
 ADC #$01
 RTS
// The screen buffer on show covers char cell (FRONTC, FRONTR). While the
// camera heads for a neighbouring cell, the back buffer is prepared for it
// one slice per frame (3 slices). Crossing into the cell flips the buffers
// if it is ready; otherwise the camera waits at the cell edge.
CameraUpdate:
 LDA #$00
 STA RD_BUSY
 LDA SNAP_REQ
 BEQ CuNorm
 JMP CamSnap
CuNorm:
 JSR CamTarget
 SEC
 LDA CAMTX
 SBC CAM1X
 STA Z_DX
 LDA CAMTX+1
 SBC CAM1X+1
 STA Z_DXH
// 2 px a frame is what the redraw keeps up with; 3 when the next
// screen is already prepared
 LDX #$02
 LDA PRE_ST
 CMP #NSL
 BCC CuMx
 INX
CuMx:
 STX Z_T0
 LDA #36
 STA Z_T2
 JSR CamStepCalc
 STA CSX
 LDX #$00
 CMP #$80
 BCC CuXp
 LDX #$FF
CuXp:
 CLC
 ADC CAM1X
 STA CAMNX
 TXA
 ADC CAM1X+1
 STA CAMNX+1
 LDA CAMTY
 SEC
 SBC CAM1Y
 STA Z_DX
 LDA #$00
 SBC #$00
 STA Z_DXH
 LDA #$02
 STA Z_T0
 LDA #20
 STA Z_T2
 JSR CamStepCalc
 STA CSY
 CLC
 ADC CAM1Y
 STA CAMNY
 JSR CoarseN
 LDA Z_T4
 CMP FRONTC
 BNE CuCross
 LDA Z_T5
 CMP FRONTR
 BNE CuCross
 JSR AcceptN
 JMP Predict
CuCross:
 LDA PRE_ON
 BEQ CuHold
 LDA PRE_ST
 CMP #NSL
 BNE CuHold
 LDA PRE_C
 CMP Z_T4
 BNE CuHold
 LDA PRE_R
 CMP Z_T5
 BNE CuHold
// the prepared buffer is for this cell: show it (the old one stays
// complete in the back screen)
 LDA FRONTC
 STA BK_C
 LDA FRONTR
 STA BK_R
 LDA #$01
 STA BK_OK
 STA FLIP_REQ
 LDA #$00
 STA PRE_ON
 LDA Z_T4
 STA FRONTC
 LDA Z_T5
 STA FRONTR
 JMP AcceptN
// waiting at the cell edge: two slices a frame until the buffer is ready
CuHold:
 LDA Z_T4
 LDX Z_T5
 JSR SetPre
 JSR ClampN
 JSR AcceptN
 LDA PRE_ST
 CMP #NSL
 BCS CuR
 LDA #$02
 STA RD_BUSY
CuR:
 RTS
// A = column, X = row: prepare that cell unless already doing so
SetPre:
 LDY PRE_ON
 BEQ SpNew
 CMP PRE_C
 BNE SpNew
 CPX PRE_R
 BNE SpNew
 RTS
SpNew:
 STA PRE_C
 STX PRE_R
 LDY #$01
 STY PRE_ON
 DEY
// the back screen may still hold that cell (camera turned back)
 LDA BK_OK
 BEQ SpSt
 LDA PRE_C
 CMP BK_C
 BNE SpSt
 CPX BK_R
 BNE SpSt
 LDY #NSL
SpSt:
 STY PRE_ST
 RTS
// How many frames until the camera leaves its cell at the current speed,
// and which cell it enters. Within 8 frames that cell is prepared, and
// RD_BUSY = slices that must be drawn this frame to have it ready in time
// (drawn after the commit; spare time draws more).
Predict:
 LDA #$00
 STA Z_U3
 LDA CSX
 STA Z_U0
 LDA CSY
 STA Z_U1
 ORA Z_U0
 BNE PdReal
// camera at rest: guess its next move from where the ball is, and get
// that cell ready in spare time (never urgent)
 INC Z_U3
 SEC
 LDA CAMTX
 SBC CAMNX
 STA Z_T0
 LDA CAMTX+1
 SBC CAMNX+1
 BMI PvXn
 BNE PvXp
 LDA Z_T0
 CMP #12
 BCC PvY
PvXp:
 LDA #$01
 STA Z_U0
 JMP PvY
PvXn:
 CMP #$FF
 BNE PvXm
 LDA Z_T0
 CMP #$F4
 BCS PvY
PvXm:
 LDA #$FF
 STA Z_U0
PvY:
 SEC
 LDA CAMTY
 SBC CAMNY
 BCC PvYn
 CMP #10
 BCC PdReal
 LDA #$01
 STA Z_U1
 JMP PdReal
PvYn:
 CMP #$F6
 BCS PdReal
 LDA #$FF
 STA Z_U1
PdReal:
 LDA FRONTC
 STA Z_A0
 LDA FRONTR
 STA Z_A1
 LDA #$FF
 STA Z_A2
 LDA Z_U0
 BEQ PdY
 BMI PdXl
 LDA FRONTC
 CMP #89
 BCS PdY
 LDA CAMNX
 AND #$07
 EOR #$07
 CLC
 ADC #$01
 LDX Z_U0
 JSR PdFrames
 STA Z_A2
 INC Z_A0
 JMP PdY
PdXl:
 LDA FRONTC
 BEQ PdY
 LDA CAMNX
 AND #$07
 CLC
 ADC #$01
 TAY
 LDA #$00
 SEC
 SBC Z_U0
 TAX
 TYA
 JSR PdFrames
 STA Z_A2
 DEC Z_A0
PdY:
 LDA Z_U1
 BEQ PdGo
 BMI PdYu
 LDA FRONTR
 CMP #25
 BCS PdGo
 LDA CAMNY
 AND #$07
 EOR #$07
 CLC
 ADC #$01
 LDX Z_U1
 JSR PdFrames
 LDX #$01
 JMP PdYc
PdYu:
 LDA FRONTR
 BEQ PdGo
 LDA CAMNY
 AND #$07
 CLC
 ADC #$01
 TAY
 LDA #$00
 SEC
 SBC Z_U1
 TAX
 TYA
 JSR PdFrames
 LDX #$FF
PdYc:
 CMP Z_A2
 BEQ PdBoth
 BCS PdGo
 STA Z_A2
 LDA FRONTC
 STA Z_A0
PdBoth:
 TXA
 CLC
 ADC FRONTR
 STA Z_A1
PdGo:
 LDA Z_A2
 CMP #$09
 BCS PdRts
 LDA Z_A0
 LDX Z_A1
 JSR SetPre
 LDA Z_U3
 BNE PdRts
 LDA #NSL
 SEC
 SBC PRE_ST
 BEQ PdRts
 STA Z_A3
// not urgent while the frames left exceed the slices left
 SEC
 SBC Z_A2
 BCC PdRts
 LDX #$00
 TXA
PdU:
 INX
 CPX #$02
 BCS PdUx
 CLC
 ADC Z_A2
 CMP Z_A3
 BCC PdU
// at most two a frame (else the camera waits at the edge for a moment)
PdUx:
 STX RD_BUSY
PdRts:
 RTS
// A = distance in pixels, X = speed (1-3) -> A = frames to cover it
PdFrames:
 STX Z_T6
 LDX #$00
PfL:
 INX
 SEC
 SBC Z_T6
 BEQ PfD
 BCS PfL
PfD:
 TXA
 RTS
// keep CAMN inside the front cell (waiting for the buffer)
ClampN:
 LDA FRONTC
 STA Z_T0
 LDA #$00
 ASL Z_T0
 ROL
 ASL Z_T0
 ROL
 ASL Z_T0
 ROL
 STA Z_T1
 LDA Z_T4
 CMP FRONTC
 BEQ CnY
 BCC CnXl
 LDA Z_T0
 ORA #$07
 STA CAMNX
 LDA Z_T1
 STA CAMNX+1
 JMP CnY
CnXl:
 LDA Z_T0
 STA CAMNX
 LDA Z_T1
 STA CAMNX+1
CnY:
 LDA Z_T5
 CMP FRONTR
 BEQ CnR
 LDA FRONTR
 ASL
 ASL
 ASL
 STA CAMNY
 LDA Z_T5
 CMP FRONTR
 BCC CnR
 LDA CAMNY
 ORA #$07
 STA CAMNY
CnR:
 RTS
AcceptN:
 LDA CAMNX
 STA CAM1X
 LDA CAMNX+1
 STA CAM1X+1
 LDA CAMNY
 STA CAM1Y
 RTS
// Z_T4 / Z_T5 = cell of CAMN
CoarseN:
 LDA CAMNX+1
 STA Z_T4
 LDA CAMNX
 LSR Z_T4
 ROR
 LSR Z_T4
 ROR
 LSR Z_T4
 ROR
 STA Z_T4
 LDA CAMNY
 LSR
 LSR
 LSR
 STA Z_T5
 RTS
// jump straight to the ball (restarts, kick-off): full redraw, flip
CamSnap:
 LDA #$00
 STA SNAP_REQ
 STA PRE_ON
 JSR CamTarget
 LDA CAMTX
 STA CAMNX
 LDA CAMTX+1
 STA CAMNX+1
 LDA CAMTY
 STA CAMNY
 JSR AcceptN
 JSR CoarseN
 LDA Z_T4
 STA FRONTC
 STA PRE_C
 LDA Z_T5
 STA FRONTR
 STA PRE_R
 LDA #$00
 STA Z_K
CsDraw:
 JSR DrawPart
 INC Z_K
 LDA Z_K
 CMP #NSL
 BNE CsDraw
 LDA #$01
 STA FLIP_REQ
 RTS
`;

export const SPRITES = `
// Sprite objects: 0-21 players, 22 ball, 23 shadow, 24/25 control markers
BuildSprites:
 LDA FRONT_DL
 EOR #$20
 STA BACK_DL
 JSR ProjectAll
 JSR SortObjs
 JMP BuildDL
ProjectAll:
// camera offsets: sprite X = PX - (CAM1X - 19), Y = PY - (CAM1Y - $34)
 SEC
 LDA CAM1X
 SBC #19
 STA Z_U0
 LDA CAM1X+1
 SBC #$00
 STA Z_U1
 SEC
 LDA CAM1Y
 SBC #$34
 STA Z_U2
 LDA #$00
 SBC #$00
 STA Z_U3
 LDX #NPL-1
PaLoop:
 SEC
 LDA PXL,X
 SBC Z_U0
 STA Z_T0
 LDA PXH,X
 SBC Z_U1
 BEQ PaX0
 CMP #$01
 BNE PaHide
 LDA Z_T0
 CMP #$58
 BCS PaHide
 LDA #$01
PaX0:
 STA Z_T1
 SEC
 LDA PYL,X
 SBC Z_U2
 TAY
 LDA PYH,X
 SBC Z_U3
 BNE PaHide
 CPY #$30
 BCC PaHide
 CPY #$F5
 BCS PaHide
 TYA
 STA OBY,X
 LDA Z_T0
 STA OBXL,X
 LDA Z_T1
 STA OBXH,X
 LDA PSTATE,X
 BNE PaSpec
 LDY PDIR,X
 LDA PMOVE,X
 BMI PaStd
 LDA PANIM,X
 LSR
 LSR
 AND #$03
 SEC
 ADC DIRBASE,Y
 JMP PaFr
PaStd:
 LDA DIRBASE,Y
 JMP PaFr
PaSpec:
 JSR PickFrame
PaFr:
 CLC
 ADC #SPR_PTR0
 STA OBP,X
 DEX
 BPL PaLoop
 JMP PaBall
PaHide:
 LDA #$FF
 STA OBY,X
 DEX
 BPL PaLoop
PaBall:
// ball + shadow
 LDA #$FF
 STA OBY+BALL
 STA OBY+OBJ_SHADOW
 LDA PXL+BALL
 SEC
 SBC CAM1X
 STA Z_T0
 LDA PXH+BALL
 SBC CAM1X+1
 STA Z_T1
 LDA Z_T0
 CLC
 ADC #19
 STA Z_T0
 STA OBXL+BALL
 STA OBXL+OBJ_SHADOW
 LDA Z_T1
 ADC #$00
 STA OBXH+BALL
 STA OBXH+OBJ_SHADOW
 BMI PbDone
 BEQ PbXok
 CMP #$01
 BNE PbDone
 LDA Z_T0
 CMP #$58
 BCS PbDone
PbXok:
 LDA PYL+BALL
 SEC
 SBC CAM1Y
 STA Z_T2
 LDA PYH+BALL
 SBC #$00
 STA Z_T3
 LDA Z_T2
 CLC
 ADC #$33
 STA Z_T2
 LDA Z_T3
 ADC #$00
 BNE PbDone
 LDA Z_T2
 CMP #$30
 BCC PbDone
 CMP #$F5
 BCS PbDone
// the shadow only shows (as a sprite) while the ball is off the ground
 LDY BZH
 BEQ PbGnd
 STA OBY+OBJ_SHADOW
PbGnd:
 SEC
 SBC BZH
 BCC PbDone
 CMP #$30
 BCC PbDone
 STA OBY+BALL
PbDone:
 LDA BFRAME
 CLC
 ADC #SPR_PTR0
 STA OBP+BALL
 LDA #$01
 STA OBC+BALL
 LDA #SPR_PTR0+F_SHADOW
 STA OBP+OBJ_SHADOW
 LDA #$00
 STA OBC+OBJ_SHADOW
// control markers above the human players
 LDX #$00
PmLoop:
 LDA #$FF
 STA OBY+OBJ_MARK1,X
 LDA HUMANS
 AND BITTAB,X
 BEQ PmNext
 LDY CTRL,X
 LDA OBY,Y
 CMP #$FF
 BEQ PmNext
 SEC
 SBC #$07
 CMP #$30
 BCC PmNext
 STA OBY+OBJ_MARK1,X
 LDA OBXL,Y
 STA OBXL+OBJ_MARK1,X
 LDA OBXH,Y
 STA OBXH+OBJ_MARK1,X
 LDA #SPR_PTR0+F_MARKER
 STA OBP+OBJ_MARK1,X
 LDA MARKCOL,X
 STA OBC+OBJ_MARK1,X
PmNext:
 INX
 CPX #$02
 BNE PmLoop
 RTS
// insertion sort of SORT[] by OBY (nearly sorted frame to frame)
SortObjs:
 LDY #$01
SoOuter:
 LDX SORT,Y
 LDA OBY,X
 LDX SORT-1,Y
 CMP OBY,X
 BCS SoNext
// out of order: insert element Y further down
 STA Z_T1
 LDA SORT,Y
 STA Z_T0
 STY Z_T3
SoInner:
 LDA SORT-1,Y
 STA SORT,Y
 DEY
 BEQ SoPlace
 LDX SORT-1,Y
 LDA OBY,X
 CMP Z_T1
 BEQ SoPlace
 BCS SoInner
SoPlace:
 LDA Z_T0
 STA SORT,Y
 LDY Z_T3
SoNext:
 INY
 CPY #NOBJ
 BNE SoOuter
 RTS
// Pick the sprites that fit (no 9th sprite within 24 lines) and write
// the back display list in Y order. Even frames accept bottom-up from the
// top, odd frames top-up from the bottom, so overloaded bands flicker
// fairly instead of always losing the same sprite.
BuildDL:
 LDA #$00
 STA Z_D010
 STA Z_T4
 LDA BACK_DL
 STA Z_T6
 LDA FRAMECNT
 AND #$01
 BEQ BdAsc
 JMP BdDesc
BdAsc:
 LDY #$00
BdA:
 LDX SORT,Y
 LDA OBY,X
 CMP #$FF
 BEQ BdAEnd
 STA Z_T1
 LDA Z_T4
 CMP #$08
 BCC BdAacc
 AND #$07
 TAX
 LDA RING,X
 CLC
 ADC #24
 BCS BdArej
 CMP Z_T1
 BEQ BdAacc
 BCS BdArej
BdAacc:
 LDA Z_T4
 AND #$07
 TAX
 LDA Z_T1
 STA RING,X
 INC Z_T4
 LDX SORT,Y
 STY Z_T7
 LDY Z_T6
 LDA OBY,X
 STA DLY,Y
 LDA OBXL,X
 STA DLXL,Y
 LDA OBP,X
 STA DLP,Y
 LDA OBC,X
 STA DLC,Y
 LDA OBXH,X
 BEQ BdAhc
 LDA BITJ,Y
 ORA Z_D010
 JMP BdAhs
BdAhc:
 LDA BITJ,Y
 EOR #$FF
 AND Z_D010
BdAhs:
 STA Z_D010
 STA DLXH,Y
 LDA DLY-8,Y
 CLC
 ADC #22
 STA DLT,Y
 INC Z_T6
 LDY Z_T7
BdArej:
 INY
 CPY #NOBJ
 BNE BdA
BdAEnd:
 LDY Z_T6
 LDA #$FF
 STA DLY,Y
 RTS
BdDesc:
 LDY #NOBJ-1
BdD:
 LDX SORT,Y
 LDA OBY,X
 CMP #$FF
 BEQ BdDnext
 STA Z_T1
 LDA Z_T4
 CMP #$08
 BCC BdDacc
 AND #$07
 TAX
 LDA Z_T1
 CLC
 ADC #24
 BCS BdDnext
 CMP RING,X
 BEQ BdDacc
 BCS BdDnext
BdDacc:
 LDA Z_T4
 AND #$07
 TAX
 LDA Z_T1
 STA RING,X
 LDX Z_T4
 LDA SORT,Y
 STA ALIST,X
 INC Z_T4
BdDnext:
 DEY
 BPL BdD
// emit the accepted list backwards (= ascending Y)
 LDY Z_T4
 BEQ BdAEnd
BdDe:
 DEY
 STY Z_T7
 LDX ALIST,Y
 JSR BdEmit
 LDY Z_T7
 BNE BdDe
 JMP BdAEnd
// X = object -> DL entry Z_T6 (+ T for the multiplexer; harmless below 8)
BdEmit:
 LDY Z_T6
 LDA OBY,X
 STA DLY,Y
 LDA OBXL,X
 STA DLXL,Y
 LDA OBP,X
 STA DLP,Y
 LDA OBC,X
 STA DLC,Y
 LDA OBXH,X
 BEQ BdEhc
 LDA BITJ,Y
 ORA Z_D010
 JMP BdEhs
BdEhc:
 LDA BITJ,Y
 EOR #$FF
 AND Z_D010
BdEhs:
 STA Z_D010
 STA DLXH,Y
 LDA DLY-8,Y
 CLC
 ADC #22
 STA DLT,Y
 INC Z_T6
 RTS
InitSort:
 LDX #$00
IsrL:
 TXA
 STA SORT,X
 INX
 CPX #NOBJ
 BNE IsrL
 LDX #NPL-1
IsrC:
 LDA PCOL,X
 STA OBC,X
 DEX
 BPL IsrC
 RTS
`;

export const INPUT = `
// JOY / FHOLD / FPRESS / FREL: index 0 = port 2 (player 1), 1 = port 1
ReadInput:
 LDA $DC00
 EOR #$FF
 AND #$1F
 STA JOY1
 LDA $DC01
 EOR #$FF
 AND #$1F
 STA JOY2
 LDX #$00
 JSR FireTrack
 LDX #$01
FireTrack:
 LDA #$00
 STA FPRESS,X
 STA FREL,X
 LDA FLOCK,X
 BEQ FtFree
// locked until released (the press that started the match)
 LDA JOY,X
 AND #$10
 BNE FtRts
 STA FLOCK,X
 STA FHOLD,X
 RTS
FtFree:
 LDA JOY,X
 AND #$10
 BEQ FtUp
 LDA FHOLD,X
 BNE FtHeld
 LDA #$01
 STA FPRESS,X
FtHeld:
 LDA FHOLD,X
 CMP #$FF
 BEQ FtRts
 INC FHOLD,X
FtRts:
 RTS
FtUp:
 LDA FHOLD,X
 BEQ FtRts
 STA FREL,X
 LDA #$00
 STA FHOLD,X
 RTS
`;

export const MATH = `
// 8-bit Galois LFSR
// 16-bit xorshift (7, 9, 8): A = next random byte
Rand:
 LDA RNGH
 LSR
 LDA RNG
 ROR
 EOR RNGH
 STA RNGH
 ROR
 EOR RNG
 STA RNG
 EOR RNGH
 STA RNGH
 RTS
// A = mask (2^n - 1) -> A = random -mask..+mask, as likely either way
RandSym:
 STA Z_R2
 JSR Rand
 TAY
 AND Z_R2
 CPY #$80
 BCC RsP
 EOR #$FF
 ADC #$00
RsP:
 RTS
// Z_R0/1 = (Z_A0/1 * Z_A2) / Z_A3  (16 x 8 / 8, 24-bit intermediate)
MulDiv:
 LDA #$00
 STA Z_R0
 STA Z_R1
 STA Z_R2
 LDX #$08
MdM:
 ASL Z_R0
 ROL Z_R1
 ROL Z_R2
 ASL Z_A2
 BCC MdMn
 CLC
 LDA Z_R0
 ADC Z_A0
 STA Z_R0
 LDA Z_R1
 ADC Z_A1
 STA Z_R1
 LDA Z_R2
 ADC #$00
 STA Z_R2
MdMn:
 DEX
 BNE MdM
// leading zero bytes of the product need no division steps
 LDX #24
MdSk:
 LDA Z_R2
 BNE MdDgo
 CPX #$09
 BCC MdDgo
 LDA Z_R1
 STA Z_R2
 LDA Z_R0
 STA Z_R1
 LDA #$00
 STA Z_R0
 TXA
 SEC
 SBC #$08
 TAX
 JMP MdSk
MdDgo:
 LDA #$00
MdD:
 ASL Z_R0
 ROL Z_R1
 ROL Z_R2
 ROL
 BCS MdDsub
 CMP Z_A3
 BCC MdDn
MdDsub:
 SBC Z_A3
 INC Z_R0
MdDn:
 DEX
 BNE MdD
 RTS
// Z_DX / Z_DY signed 16-bit -> A = min(255, |dx| + 2|dy|)
DistDXDY:
 LDA Z_DXH
 BPL DdX
 LDA #$00
 SEC
 SBC Z_DX
 STA Z_DX
 LDA #$00
 SBC Z_DXH
DdX:
 BNE DdSat
 LDA Z_DYH
 BPL DdY
 LDA #$00
 SEC
 SBC Z_DY
 STA Z_DY
 LDA #$00
 SBC Z_DYH
DdY:
 BNE DdSat
 LDA Z_DY
 ASL
 BCS DdSat
 ADC Z_DX
 BCS DdSat
 RTS
DdSat:
 LDA #$FF
 RTS
// X = player: Z_DX/Z_DY = player - ball, A = distance
DistToBall:
 LDA PXL,X
 SEC
 SBC PXL+BALL
 STA Z_DX
 LDA PXH,X
 SBC PXH+BALL
 STA Z_DXH
 LDA PYL,X
 SEC
 SBC PYL+BALL
 STA Z_DY
 LDA PYH,X
 SBC PYH+BALL
 STA Z_DYH
 JMP DistDXDY
// X = player, Y = other player: A = distance
DistXY:
 LDA PXL,X
 SEC
 SBC PXL,Y
 STA Z_DX
 LDA PXH,X
 SBC PXH,Y
 STA Z_DXH
 LDA PYL,X
 SEC
 SBC PYL,Y
 STA Z_DY
 LDA PYH,X
 SBC PYH,Y
 STA Z_DYH
 JMP DistDXDY
// X = player: C=1 if |dx| < Z_S0 and |dy| < Z_S1 to the ball
NearBall:
 LDA PXL,X
 SEC
 SBC PXL+BALL
 STA Z_T0
 LDA PXH,X
 SBC PXH+BALL
 BEQ NbX
 CMP #$FF
 BNE NbNo
 LDA Z_T0
 EOR #$FF
 CLC
 ADC #$01
 BEQ NbNo
 STA Z_T0
NbX:
 LDA Z_T0
 CMP Z_S0
 BCS NbNo
 LDA PYL,X
 SEC
 SBC PYL+BALL
 STA Z_T0
 LDA PYH,X
 SBC PYH+BALL
 BEQ NbY
 CMP #$FF
 BNE NbNo
 LDA Z_T0
 EOR #$FF
 CLC
 ADC #$01
 BEQ NbNo
 STA Z_T0
NbY:
 LDA Z_T0
 CMP Z_S1
 BCS NbNo
 SEC
 RTS
NbNo:
 CLC
 RTS
// add signed velocity to position for entity X (8.8 + 16-bit int)
Integrate:
 LDY #$00
 LDA VXH,X
 BPL InX
 DEY
InX:
 CLC
 LDA PXF,X
 ADC VXL,X
 STA PXF,X
 LDA PXL,X
 ADC VXH,X
 STA PXL,X
 TYA
 ADC PXH,X
 STA PXH,X
 LDY #$00
 LDA VYH,X
 BPL InY
 DEY
InY:
 CLC
 LDA PYF,X
 ADC VYL,X
 STA PYF,X
 LDA PYL,X
 ADC VYH,X
 STA PYL,X
 TYA
 ADC PYH,X
 STA PYH,X
 RTS
ZeroVel:
 LDA #$00
 STA VXL,X
 STA VXH,X
 STA VYL,X
 STA VYH,X
 RTS
`;

export const SOUND = `
// Voice 1: kicks / bounces, voice 2: referee whistle, voice 3: crowd
// (noise through the low-pass filter; cutoff follows the excitement)
SoundInit:
 LDX #$18
 LDA #$00
SiClr:
 STA $D400,X
 DEX
 BPL SiClr
 LDA #$08
 STA $D403
 STA $D40A
 LDA #$00
 STA $D413
 LDA #$A0
 STA $D414
 LDA #$00
 STA $D40E
 LDA #$30
 STA $D40F
 LDA #$81
 STA $D412
 LDA #$24
 STA CROWD_C
 STA CROWD_T
 STA $D416
 LDA #$44
 STA $D417
 LDA #$1F
 STA $D418
 RTS
// A = effect id
SfxPlay:
 CMP #FX_WHISTLE
 BCS SpV2
 STA SFX_REQ1
 RTS
SpV2:
 STA SFX_REQ2
 RTS
SoundUpdate:
 LDA SFX_REQ1
 BEQ Su1Run
 TAX
 LDA #$00
 STA SFX_REQ1
 STA $D404
 LDY SFXOFS-1,X
 LDA SFXDATA,Y
 STA $D405
 INY
 LDA SFXDATA,Y
 STA $D406
 INY
 STY SFX_P1
 LDA #$01
 STA SFX_ON1
 STA SFX_C1
 JMP Su2
Su1Run:
 LDA SFX_ON1
 BEQ Su2
 DEC SFX_C1
 BNE Su2
 LDY SFX_P1
 LDA SFXDATA,Y
 BEQ Su1End
 LDA SFXDATA+1,Y
 STA $D401
 LDA SFXDATA+2,Y
 STA SFX_C1
 LDA SFXDATA,Y
 STA $D404
 INY
 INY
 INY
 STY SFX_P1
 JMP Su2
Su1End:
 STA SFX_ON1
 STA $D404
Su2:
 LDA SFX_REQ2
 BEQ Su2Run
 TAX
 LDA #$00
 STA SFX_REQ2
 STA $D40B
 LDY SFXOFS-1,X
 LDA SFXDATA,Y
 STA $D40C
 INY
 LDA SFXDATA,Y
 STA $D40D
 INY
 STY SFX_P2
 LDA #$01
 STA SFX_ON2
 STA SFX_C2
 JMP SuCrowd
Su2Run:
 LDA SFX_ON2
 BEQ SuCrowd
 DEC SFX_C2
 BNE Su2Trill
 LDY SFX_P2
 LDA SFXDATA,Y
 BEQ Su2End
 LDA SFXDATA+1,Y
 STA SFX_F2
 LDA SFXDATA+2,Y
 STA SFX_C2
 LDA SFXDATA,Y
 STA $D40B
 INY
 INY
 INY
 STY SFX_P2
Su2Trill:
 LDA FRAMECNT
 AND #$01
 BEQ Su2T0
 LDA #$08
Su2T0:
 EOR #$FF
 SEC
 ADC SFX_F2
 STA $D408
 JMP SuCrowd
Su2End:
 STA SFX_ON2
 STA $D40B
SuCrowd:
 LDA CROWD_C
 CMP CROWD_T
 BEQ SuDone
 BCC SuUp
 DEC CROWD_C
 JMP SuSet
SuUp:
 INC CROWD_C
SuSet:
 LDA CROWD_C
 STA $D416
SuDone:
 RTS
`;
