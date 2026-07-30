/// @desc scr_define_opcodes()
/// Returns a struct mapping every supported 6502 mnemonic to [byte_size, cycle_count].
/// Commented with [Hex Value], [Count 1-156+], and Description.
/// Extended with aliases, demoscene illegals, and C64 common patterns.

function scr_define_opcodes() {
    return {
        // ================================================================
        // 1. SYSTEM & CONTROL
        // ================================================================
        "brk":         [1, 7], // $00 | Count 1   | Force Break
        "nop":         [1, 2], // $EA | Count 2   | No Operation

        // ================================================================
        // 2. LOAD GROUP (A-X-Y)
        // ================================================================
        "lda_imm":     [2, 2], // $A9 | Count 3   | Load A Immediate
        "ldx_imm":     [2, 2], // $A2 | Count 4   | Load X Immediate
        "ldy_imm":     [2, 2], // $A0 | Count 5   | Load Y Immediate
        "lda_zp":      [2, 3], // $A5 | Count 6   | Load A Zero Page
        "ldx_zp":      [2, 3], // $A6 | Count 7   | Load X Zero Page
        "ldy_zp":      [2, 3], // $A4 | Count 8   | Load Y Zero Page
        "lda_zpx":     [2, 4], // $B5 | Count 9   | Load A ZP, X
        "ldx_zpy":     [2, 4], // $B6 | Count 10  | Load X ZP, Y
        "ldy_zpx":     [2, 4], // $B4 | Count 11  | Load Y ZP, X
        "lda_abs":     [3, 4], // $AD | Count 12  | Load A Absolute
        "ldx_abs":     [3, 4], // $AE | Count 13  | Load X Absolute
        "ldy_abs":     [3, 4], // $AC | Count 14  | Load Y Absolute
        "lda_abx":     [3, 4], // $BD | Count 15  | Load A Abs, X
        "ldx_aby":     [3, 4], // $BE | Count 16  | Load X Abs, Y
        "ldy_abx":     [3, 4], // $BC | Count 17  | Load Y Abs, X
        "lda_aby":     [3, 4], // $B9 | Count 18  | Load A Abs, Y
        "lda_izx":     [2, 6], // $A1 | Count 19  | Load A (Ind, X)
        "lda_izy":     [2, 5], // $B1 | Count 20  | Load A (Ind), Y

        // ================================================================
        // 3. STORE GROUP (A-X-Y)
        // ================================================================
        "sta_zp":      [2, 3], // $85 | Count 21  | Store A Zero Page
        "stx_zp":      [2, 3], // $86 | Count 22  | Store X Zero Page
        "sty_zp":      [2, 3], // $84 | Count 23  | Store Y Zero Page
        "sta_zpx":     [2, 4], // $95 | Count 24  | Store A ZP, X
        "stx_zpy":     [2, 4], // $96 | Count 25  | Store X ZP, Y
        "sty_zpx":     [2, 4], // $94 | Count 26  | Store Y ZP, X
        "sta_abs":     [3, 4], // $8D | Count 27  | Store A Absolute
        "stx_abs":     [3, 4], // $8E | Count 28  | Store X Absolute
        "sty_abs":     [3, 4], // $8C | Count 29  | Store Y Absolute
        "sta_abx":     [3, 5], // $9D | Count 30  | Store A Abs, X
        "sta_aby":     [3, 5], // $99 | Count 31  | Store A Abs, Y
        "sta_izx":     [2, 6], // $81 | Count 32  | Store A (Ind, X)
        "sta_izy":     [2, 6], // $91 | Count 33  | Store A (Ind), Y

        // ================================================================
        // 4. TRANSFERS
        // ================================================================
        "tax":         [1, 2], // $AA | Count 34  | Transfer A to X
        "tay":         [1, 2], // $A8 | Count 35  | Transfer A to Y
        "tsx":         [1, 2], // $BA | Count 36  | Transfer S to X
        "txa":         [1, 2], // $8A | Count 37  | Transfer X to A
        "tya":         [1, 2], // $98 | Count 38  | Transfer Y to A
        "txs":         [1, 2], // $9A | Count 39  | Transfer X to S

        // ================================================================
        // 5. REPEATS / ALIASES (Consistency Fill)
        // ================================================================
        "ldx_abs_rep": [3, 4], // $AE | Count 40  | Load X Abs (Rep)
        "ldy_abs_rep": [3, 4], // $AC | Count 41  | Load Y Abs (Rep)
        "stx_abs_rep": [3, 4], // $8E | Count 42  | Store X Abs (Rep)
        "sty_abs_rep": [3, 4], // $8C | Count 43  | Store Y Abs (Rep)
        "lda_abs_rep": [3, 4], // $AD | Count 44  | Load A Abs (Rep)
        "sta_zp_rep":  [2, 3], // $85 | Count 45  | Store A ZP (Rep)
        "ldx_imm_rep": [2, 2], // $A2 | Count 46  | Load X Imm (Rep)
        "ldy_imm_rep": [2, 2], // $A0 | Count 47  | Load Y Imm (Rep)
        "stx_zp_rep":  [2, 3], // $86 | Count 48  | Store X ZP (Rep)
        "sty_zp_rep":  [2, 3], // $84 | Count 49  | Store Y ZP (Rep)
        "tax_rep":     [1, 2], // $AA | Count 50  | Tax (Rep)
        "tay_rep":     [1, 2], // $A8 | Count 51  | Tay (Rep)
        "tsx_rep":     [1, 2], // $BA | Count 52  | Tsx (Rep)

        // ================================================================
        // 6. ARITHMETIC
        // ================================================================
        "adc_imm":     [2, 2], // $69 | Count 53  | Add with Carry Imm
        "inx":         [1, 2], // $E8 | Count 54  | Increment X
        "iny":         [1, 2], // $C8 | Count 55  | Increment Y
        "adc_zp":      [2, 3], // $65 | Count 56  | Add with Carry ZP
        "dex":         [1, 2], // $CA | Count 57  | Decrement X
        "dey":         [1, 2], // $88 | Count 58  | Decrement Y
        "adc_zpx":     [2, 4], // $75 | Count 59  | Add with Carry ZP, X
        "inc_zp":      [2, 5], // $E6 | Count 60  | Increment Mem ZP
        "dec_zp":      [2, 5], // $C6 | Count 61  | Decrement Mem ZP
        "adc_abs":     [3, 4], // $6D | Count 62  | Add with Carry Abs
        "inc_abs":     [3, 6], // $EE | Count 63  | Increment Mem Abs
        "dec_abs":     [3, 6], // $CE | Count 64  | Decrement Mem Abs
        "adc_abx":     [3, 4], // $7D | Count 65  | Add with Carry Abs, X
        "inc_abx":     [3, 7], // $FE | Count 66  | Increment Mem Abs, X
        "dec_abx":     [3, 7], // $DE | Count 67  | Decrement Mem Abs, X
        "adc_aby":     [3, 4], // $79 | Count 68  | Add with Carry Abs, Y
        "adc_izx":     [2, 6], // $61 | Count 69  | Add with Carry (Ind, X)
        "adc_izy":     [2, 5], // $71 | Count 70  | Add with Carry (Ind), Y
        "sbc_imm":     [2, 2], // $E9 | Count 71  | Subtract w/ Carry Imm
        "sbc_zp":      [2, 3], // $E5 | Count 72  | Subtract w/ Carry ZP
        "sbc_abs":     [3, 4], // $ED | Count 73  | Subtract w/ Carry Abs
        "sbc_zpx":     [2, 4], // $F5 | Count 89  | Subtract ZP, X
        "sbc_abx":     [3, 4], // $FD | Count 90  | Subtract Abs, X
        "sbc_aby":     [3, 4], // $F9 | Count 91  | Subtract Abs, Y
        "sbc_izx":     [2, 6], // $E1 | Count 92  | Subtract (Ind, X)
        "sbc_izy":     [2, 5], // $F1 | Count 93  | Subtract (Ind), Y

        // ================================================================
        // 7. LOGIC & COMPARISON
        // ================================================================
        "and_imm":     [2, 2], // $29 | Count 74  | Logic AND Imm
        "cmp_imm":     [2, 2], // $C9 | Count 75  | Compare A Imm
        "bit_zp":      [2, 3], // $24 | Count 76  | Bit Test ZP
        "and_zp":      [2, 3], // $25 | Count 77  | Logic AND ZP
        "cpx_imm":     [2, 2], // $E0 | Count 78  | Compare X Imm
        "cpy_imm":     [2, 2], // $C0 | Count 79  | Compare Y Imm
        "and_abs":     [3, 4], // $2D | Count 80  | Logic AND Abs
        "cpx_zp":      [2, 3], // $E4 | Count 81  | Compare X ZP
        "cpy_zp":      [2, 3], // $C4 | Count 82  | Compare Y ZP
        "ora_imm":     [2, 2], // $09 | Count 83  | Logic OR Imm
        "ora_zp":      [2, 3], // $05 | Count 84  | Logic OR ZP
        "ora_abs":     [3, 4], // $0D | Count 85  | Logic OR Abs
        "eor_imm":     [2, 2], // $49 | Count 86  | Logic XOR Imm
        "eor_zp":      [2, 3], // $45 | Count 87  | Logic XOR ZP
        "eor_abs":     [3, 4], // $4D | Count 88  | Logic XOR Abs
        "ora_zpx":     [2, 4], // $15 | Count 94  | Logic OR ZP, X
        "ora_abx":     [3, 4], // $1D | Count 95  | Logic OR Abs, X
        "ora_aby":     [3, 4], // $19 | Count 96  | Logic OR Abs, Y
        "and_zpx":     [2, 4], // $35 | Count 97  | Logic AND ZP, X
        "and_abx":     [3, 4], // $3D | Count 98  | Logic AND Abs, X
        "and_aby":     [3, 4], // $39 | Count 99  | Logic AND Abs, Y
        "eor_zpx":     [2, 4], // $55 | Count 100 | Logic XOR ZP, X
        "eor_abx":     [3, 4], // $5D | Count 101 | Logic XOR Abs, X
        "eor_aby":     [3, 4], // $59 | Count 102 | Logic XOR Abs, Y
        "bit_abs":     [3, 4], // $2C | Count 103 | Bit Test Abs
        "cpx_abs":     [3, 4], // $EC | Count 104 | Compare X Abs
        "cmp_zp":      [2, 3], // $C5 |           | Compare A ZP
        "cmp_abs":     [3, 4], // $CD |           | Compare A Abs
        "cmp_zpx":     [2, 4], // $D5 |           | Compare A ZP, X
        "cmp_abx":     [3, 4], // $DD |           | Compare A Abs, X
        "cmp_aby":     [3, 4], // $D9 |           | Compare A Abs, Y
"cmp_izx":     [2, 6], // $C1 |           | Compare A (Ind, X)
        "cmp_izy":     [2, 5], // $D1 |           | Compare A (Ind), Y
"and_izx":     [2, 6], // $21 |           | AND (Ind, X)
"and_izy":     [2, 5], // $31 |           | AND (Ind), Y
"ora_izx":     [2, 6], // $01 |           | ORA (Ind, X)
"ora_izy":     [2, 5], // $11 |           | ORA (Ind), Y
"eor_izx":     [2, 6], // $41 |           | EOR (Ind, X)
"eor_izy":     [2, 5], // $51 |           | EOR (Ind), Y
"inc_zpx":     [2, 6], // $F6 |           | INC ZP, X
"dec_zpx":     [2, 6], // $D6 |           | DEC ZP, X
        "cpy_abs":     [3, 4], // $CC | Count 156 | Compare Y Abs

        // ================================================================
        // 8. SHIFTS & ROTATES
        // ================================================================
        "asl_a":       [1, 2], // $0A | Count 105 | Shift Left A
        "rol_a":       [1, 2], // $2A | Count 106 | Rotate Left A
        "ror_a":       [1, 2], // $6A | Count 107 | Rotate Right A
        "asl_zp":      [2, 5], // $06 | Count 108 | Shift Left ZP
        "rol_zp":      [2, 5], // $26 | Count 109 | Rotate Left ZP
        "ror_zp":      [2, 5], // $66 | Count 110 | Rotate Right ZP
        "asl_abs":     [3, 6], // $0E | Count 111 | Shift Left Abs
        "rol_abs":     [3, 6], // $2E | Count 112 | Rotate Left Abs
        "ror_abs":     [3, 6], // $6E | Count 113 | Rotate Right Abs
        "lsr_a":       [1, 2], // $4A | Count 114 | Shift Right A
        "lsr_zp":      [2, 5], // $46 | Count 115 | Shift Right ZP
        "lsr_abs":     [3, 6], // $4E | Count 116 | Shift Right Abs
        "asl_zpx":     [2, 6], // $16 | Count 117 | Shift Left ZP, X
        "asl_abx":     [3, 7], // $1E | Count 118 | Shift Left Abs, X
        "lsr_zpx":     [2, 6], // $56 | Count 119 | Shift Right ZP, X
        "lsr_abx":     [3, 7], // $5E | Count 120 | Shift Right Abs, X
        "rol_zpx":     [2, 6], // $36 | Count 121 | Rotate Left ZP, X
        "rol_abx":     [3, 7], // $3E | Count 122 | Rotate Left Abs, X
        "ror_zpx":     [2, 6], // $76 | Count 123 | Rotate Right ZP, X
        "ror_abx":     [3, 7], // $7E | Count 124 | Rotate Right Abs, X

        // ================================================================
        // 9. FLOW CONTROL
        // ================================================================
        "jmp":         [3, 3], // $4C |           | Jump Absolute (alias)
        "jmp_abs":     [3, 3], // $4C | Count 125 | Jump Absolute
        "jsr":         [3, 6], // $20 | Count 126 | Jump Subroutine
        "rts":         [1, 6], // $60 | Count 127 | Return Subroutine
        "bne":         [2, 2], // $D0 | Count 128 | Branch Not Equal
        "beq":         [2, 2], // $F0 | Count 129 | Branch Equal
        "jmp_ind":     [3, 5], // $6C | Count 130 | Jump Indirect
        "bcc":         [2, 2], // $90 | Count 131 | Branch Carry Clear
        "bcs":         [2, 2], // $B0 | Count 132 | Branch Carry Set
        "bpl":         [2, 2], // $10 | Count 133 | Branch Plus
        "bmi":         [2, 2], // $30 | Count 134 | Branch Minus
        "bvc":         [2, 2], // $50 | Count 135 | Branch Ovf Clear
        "bvs":         [2, 2], // $70 | Count 136 | Branch Ovf Set
        "rti":         [1, 6], // $40 | Count 137 | Return Interrupt

        // ================================================================
        // 10. STABLE ILLEGALS (Original 7)
        // ================================================================
        "lax_zp":      [2, 3], // $A7 | Count 138 | LDA+LDX ZP
        "sax_zp":      [2, 3], // $87 | Count 139 | STA&STX ZP
        "dcp_abs":     [3, 6], // $CF | Count 140 | DEC+CMP Abs
        "isc_abs":     [3, 6], // $EF | Count 141 | INC+SBC Abs
        "rla_abs":     [3, 6], // $2F | Count 142 | ROL+AND Abs
        "slo_abs":     [3, 6], // $0F | Count 143 | ASL+ORA Abs
        "sre_abs":     [3, 6], // $4F | Count 144 | LSR+EOR Abs

        // ================================================================
        // 11. FLAGS & STACK
        // ================================================================
        "clc":         [1, 2], // $18 | Count 145 | Clear Carry
        "sec":         [1, 2], // $38 | Count 146 | Set Carry
        "sei":         [1, 2], // $78 | Count 147 | Set Interrupt
        "cli":         [1, 2], // $58 | Count 148 | Clear Interrupt
        "pha":         [1, 3], // $48 | Count 149 | Push Accumulator
        "pla":         [1, 4], // $68 | Count 150 | Pull Accumulator
        "php":         [1, 3], // $08 | Count 151 | Push Status
        "plp":         [1, 4], // $28 | Count 152 | Pull Status
        "clv":         [1, 2], // $B8 | Count 153 | Clear Overflow
        "cld":         [1, 2], // $D8 | Count 154 | Clear Decimal
        "sed":         [1, 2], // $F8 | Count 155 | Set Decimal

        // ================================================================
        // 12. EXTENDED ILLEGALS (Demoscene / C64 tricks)
        // ================================================================

        // LAX - Load A and X simultaneously (very useful for C64 demos)
        "lax_abs":     [3, 4], // $AF | LAX Absolute
        "lax_aby":     [3, 4], // $BF | LAX Absolute, Y
        "lax_zpy":     [2, 4], // $B7 | LAX ZP, Y
        "lax_izx":     [2, 6], // $A3 | LAX (Ind, X)
        "lax_izy":     [2, 5], // $B3 | LAX (Ind), Y

        // SAX - Store A AND X (used for fast ZP writes)
        "sax_abs":     [3, 4], // $8F | SAX Absolute
        "sax_zpy":     [2, 4], // $97 | SAX ZP, Y
        "sax_izx":     [2, 6], // $83 | SAX (Ind, X)

        // DCP - DEC then CMP (saves cycles vs separate DEC+CMP)
        "dcp_zp":      [2, 5], // $C7 | DCP Zero Page
        "dcp_zpx":     [2, 6], // $D7 | DCP ZP, X
        "dcp_abx":     [3, 7], // $DF | DCP Abs, X
        "dcp_aby":     [3, 7], // $DB | DCP Abs, Y
        "dcp_izx":     [2, 8], // $C3 | DCP (Ind, X)
        "dcp_izy":     [2, 8], // $D3 | DCP (Ind), Y

        // ISC/ISB - INC then SBC
        "isc_zp":      [2, 5], // $E7 | ISC Zero Page
        "isc_zpx":     [2, 6], // $F7 | ISC ZP, X
        "isc_abx":     [3, 7], // $FF | ISC Abs, X
        "isc_aby":     [3, 7], // $FB | ISC Abs, Y
        "isc_izx":     [2, 8], // $E3 | ISC (Ind, X)
        "isc_izy":     [2, 8], // $F3 | ISC (Ind), Y

        // RLA - ROL then AND (compact bit manipulation)
        "rla_zp":      [2, 5], // $27 | RLA Zero Page
        "rla_zpx":     [2, 6], // $37 | RLA ZP, X
        "rla_abx":     [3, 7], // $3F | RLA Abs, X
        "rla_aby":     [3, 7], // $3B | RLA Abs, Y
        "rla_izx":     [2, 8], // $23 | RLA (Ind, X)
        "rla_izy":     [2, 8], // $33 | RLA (Ind), Y

        // RRA - ROR then ADC
        "rra_zp":      [2, 5], // $67 | RRA Zero Page
        "rra_zpx":     [2, 6], // $77 | RRA ZP, X
        "rra_abs":     [3, 6], // $6F | RRA Absolute
        "rra_abx":     [3, 7], // $7F | RRA Abs, X
        "rra_aby":     [3, 7], // $7B | RRA Abs, Y
        "rra_izx":     [2, 8], // $63 | RRA (Ind, X)
        "rra_izy":     [2, 8], // $73 | RRA (Ind), Y

        // SLO - ASL then ORA (fast multiply-and-OR patterns)
        "slo_zp":      [2, 5], // $07 | SLO Zero Page
        "slo_zpx":     [2, 6], // $17 | SLO ZP, X
        "slo_abx":     [3, 7], // $1F | SLO Abs, X
        "slo_aby":     [3, 7], // $1B | SLO Abs, Y
        "slo_izx":     [2, 8], // $03 | SLO (Ind, X)
        "slo_izy":     [2, 8], // $13 | SLO (Ind), Y

        // SRE - LSR then EOR
        "sre_zp":      [2, 5], // $47 | SRE Zero Page
        "sre_zpx":     [2, 6], // $57 | SRE ZP, X
        "sre_abx":     [3, 7], // $5F | SRE Abs, X
        "sre_aby":     [3, 7], // $5B | SRE Abs, Y
        "sre_izx":     [2, 8], // $43 | SRE (Ind, X)
        "sre_izy":     [2, 8], // $53 | SRE (Ind), Y

        // ANC - AND then set carry from bit 7 (used in fast multiply routines)
        "anc_imm":     [2, 2], // $0B | ANC Immediate
        "anc2_imm":    [2, 2], // $2B | ANC2 Immediate (same effect, different opcode)

        // ALR/ASR - AND then LSR (compact bit extraction)
        "alr_imm":     [2, 2], // $4B | ALR Immediate

        // ARR - AND then ROR (used in BCD tricks)
        "arr_imm":     [2, 2], // $6B | ARR Immediate

        // AXS/SBX - A AND X minus immediate into X (very cycle efficient)
        "axs_imm":     [2, 2], // $CB | AXS Immediate

        // NOP variants (unstable but predictable on C64 - used for cycle padding in demos)
        "nop_imm":     [2, 2], // $80 | NOP Immediate (cycle pad 2)
        "nop_zp":      [2, 3], // $04 | NOP Zero Page (cycle pad 3)
        "nop_zpx":     [2, 4], // $14 | NOP ZP, X (cycle pad 4)
        "nop_abs":     [3, 4], // $0C | NOP Absolute (cycle pad 4)
        "nop_abx":     [3, 4], // $1C | NOP Abs, X (cycle pad 4-5, used for raster timing)

        // ================================================================
        // 13. META
        // ================================================================
        "label":       [0, 0], // Meta - Label marker
        "comment":     [0, 0], // Meta - Comment (no output)
        "org":         [0, 0], // Meta - Origin directive
		"store_lo":    [5, 0], // Meta - Store lo byte of label to abs addr
        "store_hi":    [5, 0], // Meta - Store hi byte of label to abs addr
        "byte":        [1, 0], // Raw byte emit
        "word":        [2, 0], // Raw word emit
        "sta_abs_x":   [3, 5], // Alias for sta_abx
        "sta_abs_y":   [3, 5], // Alias for sta_aby
        "lda_abs_x":   [3, 4], // Alias for lda_abx
        "lda_abs_y":   [3, 4], // Alias for lda_aby
        "sta_abx_rep": [3, 5], // Repeat alias
        "sta_abs_rep": [3, 4], // Repeat alias
		// ================================================================
        // 14. PALETTE ALIASES (_zp_x / _abs_x / _ind_x style)
        // ================================================================
        "adc_zp_x":    [2, 4], // $75 | Alias for adc_zpx | Add with Carry ZP, X
        "adc_abs_x":   [3, 4], // $7D | Alias for adc_abx | Add with Carry Abs, X
        "adc_abs_y":   [3, 4], // $79 | Alias for adc_aby | Add with Carry Abs, Y
        "adc_ind_x":   [2, 6], // $61 | Alias for adc_izx | Add with Carry (Ind, X)
        "adc_ind_y":   [2, 5], // $71 | Alias for adc_izy | Add with Carry (Ind), Y
        "sbc_zp_x":    [2, 4], // $F5 | Alias for sbc_zpx | Subtract ZP, X
        "sbc_abs_x":   [3, 4], // $FD | Alias for sbc_abx | Subtract Abs, X
        "sbc_abs_y":   [3, 4], // $F9 | Alias for sbc_aby | Subtract Abs, Y
        "sbc_ind_x":   [2, 6], // $E1 | Alias for sbc_izx | Subtract (Ind, X)
        "sbc_ind_y":   [2, 5], // $F1 | Alias for sbc_izy | Subtract (Ind), Y
        "and_zp_x":    [2, 4], // $35 | Alias for and_zpx | Logic AND ZP, X
        "and_abs_x":   [3, 4], // $3D | Alias for and_abx | Logic AND Abs, X
        "and_abs_y":   [3, 4], // $39 | Alias for and_aby | Logic AND Abs, Y
        "ora_zp_x":    [2, 4], // $15 | Alias for ora_zpx | Logic OR ZP, X
        "ora_abs_x":   [3, 4], // $1D | Alias for ora_abx | Logic OR Abs, X
        "ora_abs_y":   [3, 4], // $19 | Alias for ora_aby | Logic OR Abs, Y
        "eor_zp_x":    [2, 4], // $55 | Alias for eor_zpx | Logic XOR ZP, X
        "eor_abs_x":   [3, 4], // $5D | Alias for eor_abx | Logic XOR Abs, X
        "eor_abs_y":   [3, 4], // $59 | Alias for eor_aby | Logic XOR Abs, Y
        "inc_abs_x":   [3, 7], // $FE | Alias for inc_abx | Increment Mem Abs, X
        "dec_abs_x":   [3, 7], // $DE | Alias for dec_abx | Decrement Mem Abs, X
        "asl_zp_x":    [2, 6], // $16 | Alias for asl_zpx | Shift Left ZP, X
        "asl_abs_x":   [3, 7], // $1E | Alias for asl_abx | Shift Left Abs, X
        "lsr_zp_x":    [2, 6], // $56 | Alias for lsr_zpx | Shift Right ZP, X
        "lsr_abs_x":   [3, 7], // $5E | Alias for lsr_abx | Shift Right Abs, X
        "rol_zp_x":    [2, 6], // $36 | Alias for rol_zpx | Rotate Left ZP, X
        "rol_abs_x":   [3, 7], // $3E | Alias for rol_abx | Rotate Left Abs, X
        "ror_zp_x":    [2, 6], // $76 | Alias for ror_zpx | Rotate Right ZP, X
        "ror_abs_x":   [3, 7], // $7E | Alias for ror_abx | Rotate Right Abs, X
		"byte_lab_lo": [1, 0], "byte_lab_hi": [1, 0],
		"lda_lab": [3, 0], "sta_lab": [3, 0], "stx_lab": [3, 0], "sty_lab": [3, 0],
		"ldx_lab": [3, 0], "ldy_lab": [3, 0], "inc_lab": [3, 0], "dec_lab": [3, 0],
		"cmp_lab": [3, 0], "ora_lab": [3, 0], "sbc_lab": [3, 0],
		"lda_iny": [2, 5], "jsr_lab": [3, 6],
		"lda_lab_lo": [2, 2], "lda_lab_hi": [2, 2],
		"ldy_lab_lo": [2, 2], "ldy_lab_hi": [2, 2],
		"ldx_lab_lo": [2, 2], "ldx_lab_hi": [2, 2],
		"sta_iny":  [2, 6],
    };
}
