// ALIEN BREED 64 - core code blocks: boot, raster IRQs, REU audio stream,
// sound dispatch and the small helpers everything else calls.
//
// Syntax is the Dev Machine CODE BLOCK dialect: constants are folded by
// resolve() (golazo_gen/asm.mjs), labels stay labels, .byte is constants
// only, no label arithmetic, #</#> only on LDA/LDX/LDY.

// SNG / SFX labels come from the editor's own macro nodes (SID SONG and SFX
// columns); the generator stubs them for its stand-alone test PRG.
export const SONG_UID = 710001;
export const SNG_PLAY = `sng${SONG_UID}_play`;

export const BOOT = `
// @asset AB_CHARS
// @asset AB_SPRITES
// @asset AB_TITLE_BMP
// @asset AB_TITLE_SPR
// BOOT: RAM + I/O only, VIC bank 1, our IRQ/NMI vectors, then the title
Boot:
 SEI
 CLD
 LDX #$FF
 TXS
 LDA #$35
 STA $01
 LDA #$7F
 STA $DC0D
 STA $DD0D
 LDA $DC0D
 LDA $DD0D
 LDA #$00
 STA $D015
 STA $D020
 STA $D021
 STA $DC02
 STA $D01A
 LDA $DD02
 ORA #$03
 STA $DD02
 LDA $DD00
 AND #$FC
 ORA #$02
 STA $DD00
 JSR ClearVars
 JSR SidClear
// the title picture's screen + colour (AB_TITLE_BMP, emitted at $C400 /
// $C7E8 in the level area) go to TITLE_STORE before a deck overwrites them
 LDX #$00
BtSave:
${[0, 250, 500, 750, 1000, 1250, 1500, 1750].map(o => ` LDA TITLE_VSCR+${o},X\n STA TITLE_STORE+${o},X`).join('\n')}
 INX
 CPX #250
 BNE BtSave
 LDA #BANK_GAME
 STA NEW_BANK
// the stock C64's Intex voice: 4 KB from DIGI_SRC (in the level area) into
// the RAM under the I/O at DIGI_RAM, with the I/O banked out for the copy
 LDA #<DIGI_SRC
 STA Z_PTR
 LDA #>DIGI_SRC
 STA Z_PTRH
 LDA #<DIGI_RAM
 STA Z_PTR2
 LDA #>DIGI_RAM
 STA Z_PTR2H
 LDA #$34
 STA $01
 LDX #$10
 LDY #$00
BtDigi:
 LDA (Z_PTR),Y
 STA (Z_PTR2),Y
 INY
 BNE BtDigi
 INC Z_PTRH
 INC Z_PTR2H
 DEX
 BNE BtDigi
 LDA #$35
 STA $01
 LDA #<IrqVbl
 STA $FFFE
 LDA #>IrqVbl
 STA $FFFF
 LDA #<Nmi
 STA $FFFA
 STA $0318
 LDA #>Nmi
 STA $FFFB
 STA $0319
 LDA #<IrqVbl
 STA $0314
 LDA #>IrqVbl
 STA $0315
 LDA #LINE_VBL
 STA $D012
 LDA #$10
 STA $D011
 STA CUR_D011
 LDA #$10
 STA CUR_D016
 LDA #$01
 STA $D01A
 STA $D019
 LDA #$00
 STA $D025
 LDA #$0F
 STA $D026
 LDA #$F9
 STA $D01C
 LDA #$00
 STA $D01B
 STA $D017
 STA $D01D
 LDA #$5A
 STA RNG
 JSR ReuDetect
 CLI
 JMP Title

ClearVars:
 LDA #$00
 LDX #$00
CvLoop:
 STA $0200,X
 STA $0400,X
 STA $0500,X
 STA $0600,X
 STA $0700,X
 INX
 BNE CvLoop
 LDX #$BF
CvLoop2:
 STA $0340,X
 DEX
 CPX #$FF
 BNE CvLoop2
 RTS
`;

// ------------------------------------------------------------------ IRQ
// Two raster IRQs a frame:
//   LINE_VBL ($FA): apply the committed frame (scroll, screen, sprites),
//                   tick music / SFX / REU stream, count the frame.
//   LINE_HUD ($DD): on line $DF set YSCROLL 0 so line $E0 starts row 22
//                   (the HUD) whatever the playfield scroll was; HUD hires,
//                   no X scroll, sprites off below the playfield.
export const IRQ = `
IrqVbl:
 PHA
 TXA
 PHA
 TYA
 PHA
 CLD
 LDA #$FF
 STA $D019
 LDA READY
 BEQ IvNoNew
 LDA NEW_D011
 STA CUR_D011
 LDA NEW_D016
 STA CUR_D016
 LDA NEW_D018
 STA $D018
 LDA NEW_D020
 STA CUR_D020
 LDA $DD00
 AND #$FC
 ORA NEW_BANK
 STA $DD00
 JSR SprApply
 LDA #$00
 STA READY
 JMP IvApply
// the title's split IRQ moved the sprites: put the upper band back
IvNoNew:
 LDA TITLE_ON
 BEQ IvApply
 JSR SprApply
IvApply:
 LDA CUR_D011
 STA $D011
 LDA CUR_D016
 STA $D016
 LDA CUR_EN
 STA $D015
 LDA CUR_D020
 STA $D020
 INC FRAMECNT
 LDA MUSIC_ON
 BEQ IvNoMus
 JSR ${SNG_PLAY}
 LDA #$35
 STA $01
IvNoMus:
 LDA SFX_ON
 BEQ IvNoSfx
 JSR SfxTick
 LDA #$35
 STA $01
IvNoSfx:
 LDA A_ON
 BEQ IvNoStr
 JSR AudioTick
IvNoStr:
 LDA TITLE_ON
 BNE IvTitle
 LDA #LINE_HUD
 STA $D012
 LDA #<IrqHud
 STA $FFFE
 STA $0314
 LDA #>IrqHud
 STA $FFFF
 STA $0315
 JMP IvOut
IvTitle:
 LDA #LINE_TSPLIT
 STA $D012
 LDA #<IrqTSplit
 STA $FFFE
 STA $0314
 LDA #>IrqTSplit
 STA $FFFF
 STA $0315
IvOut:
 PLA
 TAY
 PLA
 TAX
 PLA
 RTI

// FLD: from line $D7 (row 20 has started whatever the scroll) each line
// gets a YSCROLL that keeps the next line from being a badline, so row 21
// (the HUD) always starts at line $E0. The gap shows idle (black) lines.
IrqHud:
 PHA
 TXA
 PHA
 LDA #$FF
 STA $D019
// any sample NMI (REU stream or stock C64 sample) landing between the
// FLD's line writes throws them off: hold it for the split (the tick that
// comes due meanwhile fires once it is allowed again)
 LDA #$01
 STA $DD0D
 LDA #LINE_HUD_GO
IhWait:
 CMP $D012
 BNE IhWait
// past cycle 14 of line $D7: with YSCROLL 7 it is row 20's badline,
// which a YSCROLL change before it starts would cancel
 LDX #$04
IhDelay:
 DEX
 BNE IhDelay
// from here to the HUD the screen is black (ECM + multicolour is the VIC's
// "illegal" mode), so the playfield ends on the same line whatever the
// scroll, and the sprites stop there too
 LDA #$00
 STA $D015
IhFld:
 LDA $D012
 TAX
 CLC
 ADC #$02
 AND #$07
 ORA #$50
 STA $D011
// at or past the last FLD line: an NMI (sample) can make the loop skip a
// line, and waiting for the exact line would then hang here for a frame
 CPX #LINE_HUD_END
 BCS IhFldX
IhLine:
 CPX $D012
 BEQ IhLine
 JMP IhFld
IhFldX:
 LDA #$10
 STA $D011
 STA $D016
 LDA A_ON
 BEQ IhNoDg2
 LDA #$81
 STA $DD0D
IhNoDg2:
 LDA #LINE_VBL
 STA $D012
 LDA #<IrqVbl
 STA $FFFE
 STA $0314
 LDA #>IrqVbl
 STA $FFFF
 STA $0315
 PLA
 TAX
 PLA
 RTI

// the sprite shadow into the VIC; pointers into both game screens, and the
// title screen's while the title is up
SprApply:
 LDA SH_EN
 STA CUR_EN
 LDA SH_MSB
 STA $D010
${[0, 1, 2, 3, 4, 5, 6, 7].map(i => ` LDA SH_X+${i}
 STA $D0${(i * 2).toString(16).padStart(2, '0').toUpperCase()}
 LDA SH_Y+${i}
 STA $D0${(i * 2 + 1).toString(16).padStart(2, '0').toUpperCase()}
 LDA SH_COL+${i}
 STA $D0${(0x27 + i).toString(16).toUpperCase()}
 LDA SH_PTR+${i}
 STA SPTRA+${i}
 STA SPTRB+${i}`).join('\n')}
 LDA TITLE_ON
 BEQ SaOut
 LDX #$07
SaPtr:
 LDA SH_PTR,X
 STA TITLE_PTRS,X
 DEX
 BPL SaPtr
SaOut:
 RTS

// TITLE: line $A0, the upper text band is done - the sprites move down to
// the lower band (PRESS FIRE | TO PLAY), flashing in TCOL
IrqTSplit:
 PHA
 TXA
 PHA
 LDA #$FF
 STA $D019
 LDX #TLO_N-1
TsLoop:
 LDA TLoPtr,X
 STA TITLE_PTRS,X
 LDA TCOL
 STA $D027,X
 DEX
 BPL TsLoop
 TYA
 PHA
 LDX #$07
 LDY #$0E
TsPos:
 LDA TLoX,X
 STA $D000,Y
 LDA #TLO_Y
 STA $D001,Y
 DEY
 DEY
 DEX
 BPL TsPos
 PLA
 TAY
 LDA #TLO_MSB
 STA $D010
 LDA #TLO_EN
 STA $D015
 LDA #LINE_VBL
 STA $D012
 LDA #<IrqVbl
 STA $FFFE
 STA $0314
 LDA #>IrqVbl
 STA $FFFF
 STA $0315
 PLA
 TAX
 PLA
 RTI
TLoX:
 .byte {{TLO_X}}
TLoPtr:
 .byte {{TLO_PTR}}

// NMI: one REU byte straight into $D418 (the stream is set up by
// AudioPlay: C64 address fixed at $D418, length 1). CIA 2 timer A clocks it.
// The REU's address counter carries through 19 bits only: at each 512 KB
// boundary ($x80000, low 19 bits back to 0) the bank bits above it are
// stepped here, or a long clip (the title) would wrap to its block's start.
Nmi:
 PHA
 LDA #$91
 STA $DF01
 LDA $DF05
 BEQ NmPage
NmOut:
 LDA $DD0D
 PLA
 RTI
NmPage:
 LDA $DF04
 BNE NmOut
 LDA $DF06
 AND #$07
 BNE NmOut
 LDA A_BANK
 CLC
 ADC #$08
 STA A_BANK
 STA $DF06
 JMP NmOut

// Commit the frame: the next LINE_VBL IRQ applies it. Waits until it has.
Commit:
 LDA #$01
 STA READY
CmWait:
 LDA READY
 BNE CmWait
 LDA COL_REQ
 BEQ CmOut
 DEC COL_REQ
 BNE CmOut
 JMP FillColRows
CmOut:
 RTS

// colour RAM rows 0-21 from ROWCOL[]
FillColRows:
 LDA #$00
 STA Z_SP
 LDA #$D8
 STA Z_SPH
 LDX #$00
FcRow:
 LDA ROWCOL,X
 LDY #39
FcCol:
 STA (Z_SP),Y
 DEY
 BPL FcCol
 CLC
 LDA Z_SP
 ADC #40
 STA Z_SP
 BCC FcNc
 INC Z_SPH
FcNc:
 INX
 CPX #PFROWS
 BNE FcRow
 RTS

// every playfield row the same colour (A), applied now
SetAllRowCol:
 LDX #PFROWS-1
SrLoop:
 STA ROWCOL,X
 DEX
 BPL SrLoop
 JMP FillColRows
`;

// ------------------------------------------------------------------ audio
// AUDIO_MODE 0 = SID (Music Maker title tune, SFX Maker effects on voice 3)
// AUDIO_MODE 1 = REU stream (C64 Ultimate / any REU): 4-bit samples DMA'd
//                byte by byte into $D418 from an NMI, voice 3 as DC boost.
// REU directory (REU $000100, fetched to REU_HDR): "ABREU1", count, 0,
// then 8 bytes per clip: start (3), frames (2), CIA latch (2), loop flag.
export const AUDIO = `
ReuDetect:
 LDA #$00
 STA REU_OK
 LDA #$55
 STA $DF02
 LDA #$AA
 STA $DF03
 LDA $DF02
 CMP #$55
 BNE RdNo
 LDA $DF03
 CMP #$AA
 BNE RdNo
 LDA #$A5
 STA $DF02
 LDA $DF02
 CMP #$A5
 BNE RdNo
 LDA #<REU_HDR
 STA $DF02
 LDA #>REU_HDR
 STA $DF03
 LDA #$00
 STA $DF04
 STA $DF06
 STA $DF08
 STA $DF0A
 LDA #$01
 STA $DF05
 LDA #128
 STA $DF07
 LDA #$91
 STA $DF01
 LDX #$05
RdSig:
 LDA REU_HDR,X
 CMP ReuSig,X
 BNE RdNo
 DEX
 BPL RdSig
 LDA #$01
 STA REU_OK
 STA AUDIO_MODE
RdNo:
 RTS
ReuSig:
 .byte $41,$42,$52,$45,$55,$31

// A = clip, X = priority. Starts the stream unless a higher one plays.
AudioPlay:
 PHP
 SEI
 STA Z_SND
 LDA A_ON
 BEQ ApGo
 CPX A_PRI
 BCS ApGo
 PLP
 RTS
ApGo:
 STX A_PRI
 LDA #$00
 STA $DD0E
 LDA Z_SND
 STA A_CLIP
 JSR ApLoad
 LDA #$11
 STA $DD0E
 LDA #$81
 STA $DD0D
 PLP
 RTS
// REU registers, latch and frame count for clip A_CLIP
ApLoad:
 LDA A_CLIP
 ASL A
 ASL A
 ASL A
 TAX
 LDA #$18
 STA $DF02
 LDA #$D4
 STA $DF03
 LDA REU_HDR+8,X
 STA $DF04
 LDA REU_HDR+9,X
 STA $DF05
 LDA REU_HDR+10,X
 STA $DF06
 AND #$F8
 STA A_BANK
 LDA #$01
 STA $DF07
 LDA #$00
 STA $DF08
 LDA #$80
 STA $DF0A
 LDA REU_HDR+11,X
 STA A_REM0
 LDA REU_HDR+12,X
 STA A_REM1
 LDA REU_HDR+13,X
 STA $DD04
 LDA REU_HDR+14,X
 STA $DD05
 LDA REU_HDR+15,X
 STA A_LOOP
 LDA #$01
 STA A_ON
 RTS

// once a frame (IRQ): count the clip down; loop or stop it at the end
AudioTick:
 LDA A_REM0
 BNE AtDec
 LDA A_REM1
 BEQ AtEnd
 DEC A_REM1
AtDec:
 DEC A_REM0
 RTS
AtEnd:
 LDA A_LOOP
 BEQ AudioStop
 JMP ApLoad
AudioStop:
 LDA #$00
 STA $DD0E
 STA A_ON
 STA A_PRI
 LDA #$08
 STA $D418
// a stock-C64 sample ended: NMI back to the REU player, SID effects back on
 LDA RAM_DIGI
 BEQ AuOut
 LDA #$00
 STA RAM_DIGI
 LDA #<Nmi
 STA $FFFA
 STA $0318
 LDA #>Nmi
 STA $FFFB
 STA $0319
 LDA SFX_WAS
 BEQ AuOut
 JSR SfxInit
 LDA #$35
 STA $01
 LDA #$01
 STA SFX_ON
AuOut:
 RTS

// STOCK C64 SAMPLES: A = sample (0 Intex voice, 1 ammo clip), played from
// RAM - 4-bit, two to a byte - by NmiRam, timed by CIA 2 like the REU
// stream. The SID effects pause meanwhile ($D418 is the sample).
RamPlay:
 PHP
 SEI
 TAX
 LDA RAM_DIGI
 BEQ RpFree
 CPX #$01
 BNE RpKeep
 PLP
 RTS
RpFree:
 LDA SFX_ON
 STA SFX_WAS
 LDA #$00
 STA SFX_ON
RpKeep:
 LDA #$00
 STA $DD0E
 STA Z_DGP
 STA A_REM1
 STA A_LOOP
 LDA DgAddrL,X
 STA Z_DG
 LDA DgAddrH,X
 STA Z_DGH
 LDA DgFrames,X
 STA A_REM0
 LDA #$01
 STA A_ON
 STA RAM_DIGI
 JSR DigiBoost
 LDA #<NmiRam
 STA $FFFA
 STA $0318
 LDA #>NmiRam
 STA $FFFB
 STA $0319
 LDA #<DIGI_LATCH
 STA $DD04
 LDA #>DIGI_LATCH
 STA $DD05
 LDA #$81
 STA $DD0D
 LDA #$11
 STA $DD0E
 PLP
 RTS
DgAddrL:
 .byte <DIGI_RAM,<DIGI_CLIP
DgAddrH:
 .byte >DIGI_RAM,>DIGI_CLIP
DgFrames:
 .byte DIGI_V_FRAMES,DIGI_C_FRAMES

// one 4-bit sample from RAM (the voice lives under the I/O: bank it out
// for the read, back in for $D418)
NmiRam:
 PHA
 TYA
 PHA
 LDA #$34
 STA $01
 LDY #$00
 LDA (Z_DG),Y
 LDY #$35
 STY $01
 LDY Z_DGP
 BNE NrHi
 AND #$0F
 INC Z_DGP
 JMP NrOut
NrHi:
 LSR A
 LSR A
 LSR A
 LSR A
 LDY #$00
 STY Z_DGP
 INC Z_DG
 BNE NrOut
 INC Z_DGH
NrOut:
 STA $D418
 LDA $DD0D
 PLA
 TAY
 PLA
 RTI

// voice 3 as a steady DC level so $D418 samples are loud on the 8580 too
DigiBoost:
 LDA #$00
 STA $D40E
 STA $D40F
 STA $D413
 LDA #$F0
 STA $D414
 LDA #$08
 STA $D411
 LDA #$49
 STA $D412
 LDA #$08
 STA $D418
 RTS

SidClear:
 LDA #$00
 LDX #$18
ScLoop:
 STA $D400,X
 DEX
 BPL ScLoop
 RTS

// title music: SID tune or the REU stream
MusicStartAny:
 LDA AUDIO_MODE
 BEQ MsSid
 JSR SidClear
 JSR DigiBoost
 LDA #CLIP_MUSIC
 LDX #$00
 JMP AudioPlay
MsSid:
 JSR SidClear
 JSR MusicInit
 LDA #$01
 STA MUSIC_ON
 RTS

MusicStopAll:
 LDA #$00
 STA MUSIC_ON
 STA SFX_ON
 JSR AudioStop
 JMP SidClear

// start the in-game sound for the current mode
GameSoundOn:
 JSR MusicStopAll
 LDA AUDIO_MODE
 BEQ GsSid
 JMP DigiBoost
GsSid:
 JSR SfxInit
 LDA #$01
 STA SFX_ON
 RTS

// A = sound id (S_*). REU: clip id+1; SID: the SFX Maker effect.
PlaySfx:
 LDX AUDIO_MODE
 BEQ PsSid
 TAX
 LDA SfxPri,X
 PHA
 INX
 TXA
 TAY
 PLA
 TAX
 TYA
 JMP AudioPlay
PsSid:
 CMP #NSFX
 BCC PsSfx
 SEC
 SBC #NSFX
 JMP RamPlay
PsSfx:
 LDX SFX_ON
 BNE PsGo
 RTS
PsGo:
${['Gun', 'AlienDie', 'Hurt', 'Pickup', 'Door', 'Key', 'Terminal', 'Alarm', 'CoreHit', 'Explode'].map((n, i) =>
  ` CMP #${i}\n BNE Ps${i}\n JSR Sfx${n}\n JMP PsOut\nPs${i}:`).join('\n')}
PsOut:
 LDA #$35
 STA $01
 RTS
// priority per sound: the SFX, then the samples (Intex voice, ammo clip)
SfxPri:
 .byte 1,2,3,2,2,3,2,4,2,4,4,2

// MusicInit: the Music Maker init sets $01 to $36 (KERNAL in), so it runs
// with IRQs off from here (below $E000) and $01 goes back to $35.
MusicInit:
 SEI
 JSR MusicStart
 LDA #$35
 STA $01
 CLI
 RTS
`;

// ------------------------------------------------------------------ helpers
export const UTIL = `
// Z_MP = MAP + Y * 128 + X  (X 0-127, Y 0-95)
MapPtr:
 TYA
 LSR A
 STA Z_MPH
 LDA #$00
 ROR A
 STA Z_MP
 TXA
 ORA Z_MP
 STA Z_MP
 LDA Z_MPH
 CLC
 ADC #$A0
 STA Z_MPH
 RTS
// A = char at X, Y (Y is lost)
CharAt:
 JSR MapPtr
 LDY #$00
 LDA (Z_MP),Y
 RTS
// A = pixel / 8 for the 16-bit pixel Z_T0 (lo) / A (hi)
Pix2C:
 ASL A
 ASL A
 ASL A
 ASL A
 ASL A
 STA Z_T1
 LDA Z_T0
 LSR A
 LSR A
 LSR A
 ORA Z_T1
 RTS

// box corners for the box of half size Z_BH round Z_BX, Z_BY:
// Z_CX / Z_T2 = left / right char, Z_CY / Z_T3 = top / bottom char
BoxCorners:
 SEC
 LDA Z_BX
 SBC Z_BH
 STA Z_T0
 LDA Z_BXH
 SBC #$00
 JSR Pix2C
 STA Z_CX
 CLC
 LDA Z_BX
 ADC Z_BH
 STA Z_T0
 LDA Z_BXH
 ADC #$00
 STA Z_T4
 LDA Z_T0
 BNE BcR
 DEC Z_T4
BcR:
 DEC Z_T0
 LDA Z_T4
 JSR Pix2C
 STA Z_T2
 SEC
 LDA Z_BY
 SBC Z_BH
 STA Z_T0
 LDA Z_BYH
 SBC #$00
 JSR Pix2C
 STA Z_CY
 CLC
 LDA Z_BY
 ADC Z_BH
 STA Z_T0
 LDA Z_BYH
 ADC #$00
 STA Z_T4
 LDA Z_T0
 BNE BcB
 DEC Z_T4
BcB:
 DEC Z_T0
 LDA Z_T4
 JSR Pix2C
 STA Z_T3
 RTS

// C set if the box touches a solid char; Z_HT / Z_HX / Z_HY = what it hit
BoxSolid:
 JSR BoxCorners
 LDX Z_CX
 LDY Z_CY
 JSR BsTest
 BCS BsOut
 LDX Z_T2
 LDY Z_CY
 JSR BsTest
 BCS BsOut
 LDX Z_CX
 LDY Z_T3
 JSR BsTest
 BCS BsOut
 LDX Z_T2
 LDY Z_T3
BsTest:
 STX Z_HX
 STY Z_HY
 JSR CharAt
 TAX
 LDA CHAR_TYPES,X
 STA Z_HT
 ASL A
BsOut:
 RTS

// the type of the first pickup / lift char under the box (A, 0 = none),
// at Z_HX, Z_HY
BoxPickup:
 JSR BoxCorners
 LDX Z_CX
 LDY Z_CY
 JSR BpTest
 BNE BpOut
 LDX Z_T2
 LDY Z_CY
 JSR BpTest
 BNE BpOut
 LDX Z_CX
 LDY Z_T3
 JSR BpTest
 BNE BpOut
 LDX Z_T2
 LDY Z_T3
BpTest:
 STX Z_HX
 STY Z_HY
 JSR CharAt
 TAX
 LDA CHAR_TYPES,X
 BMI BpNone
 CMP #T_VENT
 BCS BpNone
 CMP #$00
 RTS
BpNone:
 LDA #$00
BpOut:
 RTS

// write char A at X, Y to the map and, if on show, to the shown screen
PutChar:
 STA Z_T5
 STX Z_T6
 STY Z_T7
 JSR MapPtr
 LDY #$00
 LDA Z_T5
 STA (Z_MP),Y
 SEC
 LDA Z_T7
 SBC DISP_CY
 BCC PcOut
 CMP #PFROWS
 BCS PcOut
 TAY
 SEC
 LDA Z_T6
 SBC DISP_CX
 BCC PcOut
 CMP #40
 BCS PcOut
 CLC
 ADC Row40L,Y
 STA Z_SP
 LDA Row40H,Y
 ADC #$40
 LDX CUR_SCR
 BEQ PcA
 ADC #$04
PcA:
 STA Z_SPH
 LDY #$00
 LDA Z_T5
 STA (Z_SP),Y
PcOut:
 RTS

// a 2 x 2 tile at the even char X, Y: chars from A (TL), A+1, A+2, A+3
PutTile:
 STA Z_K
 STX Z_TX
 STY Z_TY
 JSR PutChar
 LDX Z_TX
 INX
 LDY Z_TY
 LDA Z_K
 CLC
 ADC #$01
 JSR PutChar
 LDX Z_TX
 LDY Z_TY
 INY
 LDA Z_K
 CLC
 ADC #$02
 JSR PutChar
 LDX Z_TX
 INX
 LDY Z_TY
 INY
 LDA Z_K
 CLC
 ADC #$03
 JMP PutChar

// floor where a pickup / door was: tile at Z_HX, Z_HY (rounded down to even)
ClearTile:
 LDA Z_HX
 AND #$FE
 TAX
 LDA Z_HY
 AND #$FE
 TAY
 LDA #CH_FLOOR_A
 JMP PutTile

Row40L:
${rowTable(r => (r * 40) & 255)}
Row40H:
${rowTable(r => (r * 40) >> 8)}

// 8-bit Galois LFSR
Rnd:
 LDA RNG
 ASL A
 BCC RnOk
 EOR #$1D
RnOk:
 STA RNG
 RTS

// BCD: A x 100 onto SCORE / CREDITS
AddScore:
 SED
 CLC
 ADC SCORE+1
 STA SCORE+1
 LDA SCORE+2
 ADC #$00
 STA SCORE+2
 CLD
 LDA HUD_DIRTY
 ORA #HD_SCORE
 STA HUD_DIRTY
 RTS
AddCredits:
 SED
 CLC
 ADC CREDITS+1
 STA CREDITS+1
 LDA CREDITS+2
 ADC #$00
 STA CREDITS+2
 CLD
 LDA HUD_DIRTY
 ORA #HD_CREDITS
 STA HUD_DIRTY
 RTS

// joystick port 2, active high in JOY; JOYNEW = newly pressed
ReadJoy:
 LDA $DC00
 EOR #$FF
 AND #$1F
 STA JOY
 EOR JOYOLD
 AND JOY
 STA JOYNEW
 LDA JOY
 STA JOYOLD
 RTS
`;

function rowTable(f) {
  const v = Array.from({ length: 25 }, (_, r) => '$' + f(r).toString(16).toUpperCase().padStart(2, '0'));
  return ' .byte ' + v.slice(0, 13).join(',') + '\n .byte ' + v.slice(13).join(',');
}
