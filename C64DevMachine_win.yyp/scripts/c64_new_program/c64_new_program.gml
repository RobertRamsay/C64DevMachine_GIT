function c64_new_program() {
    var prog = {
        //  CORE STATE 
        bytes:         [],                
        labels:        ds_map_create(),  
        fixups:        [],                
        base_address: 0x0801,            
        header_size:  13,                
        pc_override:  -1,
        pc_stack:     [],

        current_pc: function() {
            if (self.pc_override >= 0) return self.pc_override;
            return self.base_address + self.header_size + array_length(self.bytes);
        },

add: function(v) {
	            if (is_array(v)) {
	                for (var i = 0; i < array_length(v); i++) {
	                    var _b = v[i] & 0xFF;
	                    if (self.pc_override >= 0) {
	                        var _off = self.pc_override - self.base_address - self.header_size;
	                        if (_off < 0) {
	                            if (!variable_global_exists("assembler_zero_crash")) global.assembler_zero_crash = false;
	                            if (!global.assembler_zero_crash) {
	                                global.assembler_zero_crash = true;
	                                show_debug_message("ASSEMBLER ABORT: negative offset _off=" + string(_off) + " pc=" + string(self.pc_override) + " — likely $0000 ORG with code attached");
	                            }
	                            self.pc_override++;
	                            continue;
	                        }
	                        var _cur_len = array_length(self.bytes);
	                        if (_off >= _cur_len) {
	                            array_resize(self.bytes, _off + 1);
	                            for (var _pi = _cur_len; _pi < _off; _pi++) self.bytes[_pi] = 0x00;
	                        }
	                        self.bytes[_off] = _b; self.pc_override++;
	                    } else { array_push(self.bytes, _b); }
	                }
	            } else {
	                var _b = v & 0xFF;
	                if (self.pc_override >= 0) {
	                    var _off = self.pc_override - self.base_address - self.header_size;
	                    if (_off < 0) {
	                        if (!variable_global_exists("assembler_zero_crash")) global.assembler_zero_crash = false;
	                        if (!global.assembler_zero_crash) {
	                            global.assembler_zero_crash = true;
	                            show_debug_message("ASSEMBLER ABORT: negative offset _off=" + string(_off) + " pc=" + string(self.pc_override) + " — likely $0000 ORG with code attached");
	                        }
	                        self.pc_override++;
	                        return self;
	                    }
	                    var _cur_len = array_length(self.bytes);
	                    if (_off >= _cur_len) {
	                        array_resize(self.bytes, _off + 1);
	                        for (var _pi = _cur_len; _pi < _off; _pi++) self.bytes[_pi] = 0x00;
	                    }
	                    self.bytes[_off] = _b; self.pc_override++;
	                } else { array_push(self.bytes, _b); }
	            }
	            return self;
	        },

        // ================================================================
        // THE BRIDGE (Switch Case Mapping for 156 Opcodes)
        // ================================================================
assemble_instruction: function(_mnem, _val) {
            var start_count = array_length(self.bytes);
            // Resolve named locations (HW_/UV_ vars) to addresses
			// Only resolve named locations for abs/zp opcodes — NOT for label-fixup opcodes
			// which must remain as strings so the fixup system can patch them post-assembly
			var _is_label_fixup_op = (string_pos("_lab", _mnem) > 0 || _mnem == "bne" || _mnem == "beq"
			    || _mnem == "bcc" || _mnem == "bcs" || _mnem == "bpl" || _mnem == "bmi"
			    || _mnem == "bvc" || _mnem == "bvs" || _mnem == "jsr" || _mnem == "jsr_abs" || _mnem == "jmp"
			    || _mnem == "jmp_abs" || _mnem == "byte_lab_lo" || _mnem == "byte_lab_hi");
			if (!_is_label_fixup_op && is_string(_val) && _val != "" && ds_exists(global.named_loc_map, ds_type_map)) {
			    var _upper = string_upper(_val);
			    if (ds_map_exists(global.named_loc_map, _upper)) {
			        var _resolved = ds_map_find_value(global.named_loc_map, _upper);
			        if (is_real(_resolved)) _val = _resolved;
			    }
			}
            // If still a string, treat as a label fixup for abs/abx/aby instructions
            if (is_string(_val) && _val != "") {
                var _abs_mnems = ",lda_abs,ldx_abs,ldy_abs,sta_abs,stx_abs,sty_abs,"
                               + "lda_abx,lda_absx,lda_aby,ldx_aby,ldy_abx,sta_abx,sta_aby,"
                               + "lda_abs_x,lda_abs_y,sta_abs_x,sta_abs_y,"
                               + "adc_abs,sbc_abs,and_abs,ora_abs,eor_abs,cmp_abs,"
                               + "adc_abx,adc_aby,sbc_abx,sbc_aby,inc_abs,dec_abs,";
                if (string_pos("," + _mnem + ",", _abs_mnems) > 0) {
                    var _fp = (self.pc_override >= 0)
                        ? (self.pc_override + 1) - self.base_address - self.header_size
                        : array_length(self.bytes) + 1;
                    // Emit the correct opcode byte manually then 2 placeholder bytes
                    var _op_map = {
                        lda_abs: 0xAD, ldx_abs: 0xAE, ldy_abs: 0xAC,
                        sta_abs: 0x8D, stx_abs: 0x8E, sty_abs: 0x8C,
                        lda_abx: 0xBD, lda_absx: 0xBD, lda_abs_x: 0xBD,
                        lda_aby: 0xB9, lda_abs_y: 0xB9,
                        ldx_aby: 0xBE, ldy_abx: 0xBC,
                        sta_abx: 0x9D, sta_abs_x: 0x9D,
                        sta_aby: 0x99, sta_abs_y: 0x99,
                        adc_abs: 0x6D, sbc_abs: 0xED,
                        and_abs: 0x2D, ora_abs: 0x0D, eor_abs: 0x4D, cmp_abs: 0xCD,
                        adc_abx: 0x7D, adc_aby: 0x79,
                        sbc_abx: 0xFD, sbc_aby: 0xF9,
                        inc_abs: 0xEE, dec_abs: 0xCE,
                    };
                    var _op = variable_struct_exists(_op_map, _mnem) ? _op_map[$ _mnem] : 0xAD;
                    self.add([_op, 0x00, 0x00]);
                    array_push(self.fixups, {pos: _fp, label: _val, type: "abs"});
                    return array_length(self.bytes) - start_count;
                }
            }
			
            switch(_mnem) {
                //  PAGE 0: DATA MOVEMENT 
                case "brk":      self.add(0x00); break; // Count 1  - $00: Force Break
                case "nop":      self.add(0xEA); break; // Count 2  - $EA: No Operation
                case "lda_imm": if (is_string(_val)) self._add_fix(0xA9, _val, "lo"); else self._lda_imm(_val); break;
                case "ldx_imm": if (is_string(_val)) self._add_fix(0xA2, _val, "lo"); else self._ldx_imm(_val); break;
                case "ldy_imm": if (is_string(_val)) self._add_fix(0xA0, _val, "lo"); else self._ldy_imm(_val); break;
                case "lda_zp":  self._lda_zp(_val);  break; // Count 6  - $A5: Load A Zero Page
                case "ldx_zp":  self._ldx_zp(_val);  break; // Count 7  - $A6: Load X Zero Page
                case "ldy_zp":  self._ldy_zp(_val);  break; // Count 8  - $A4: Load Y Zero Page
                case "lda_zpx": self._lda_zpx(_val); break; // Count 9  - $B5: Load A ZP, X
                case "ldx_zpy": self._ldx_zpy(_val); break; // Count 10 - $B6: Load X ZP, Y
                case "ldy_zpx": self._ldy_zpx(_val); break; // Count 11 - $B4: Load Y ZP, X
                case "lda_abs": self._lda_abs(_val); break; // Count 12 - $AD: Load A Absolute
                case "ldx_abs": self._ldx_abs(_val); break; // Count 13 - $AE: Load X Absolute
                case "ldy_abs": self._ldy_abs(_val); break; // Count 14 - $AC: Load Y Absolute
                
                case "lda_absx": self._lda_abx(_val); break;
                case "lda_abs_x": self._lda_abx(_val); break;
                case "lda_abx":  self._lda_abx(_val); break;
                case "ldx_abs_y":
                case "ldx_aby":  self._ldx_aby(_val); break; // Count 16 - $BE: Load X Absolute, Y
                case "ldy_abs_x":
                case "ldy_abx":  self._ldy_abx(_val); break; // Count 17 - $BC: Load Y Absolute, X
                case "lda_abs_y":
                case "lda_aby":  self._lda_aby(_val); break; // Count 18 - $B9: Load A Absolute, Y
                
                case "lda_izx": self._lda_izx(_val); break; // Count 19 - $A1: Load A (Indirect, X)
                case "lda_iny":  self._lda_izy(_val); break;
                case "lda_izy":  self._lda_izy(_val); break; // Count 20 - $B1: Load A (Indirect), YY
                case "sta_zp":  self._sta_zp(_val);  break; // Count 21 - $85: Store A Zero Page
                case "stx_zp":  self._stx_zp(_val);  break; // Count 22 - $86: Store X Zero Page
                case "sty_zp":  self._sty_zp(_val);  break; // Count 23 - $84: Store Y Zero Page
                case "sta_zpx": self._sta_zpx(_val); break; // Count 24 - $95: Store A ZP, X
                case "stx_zpy": self._stx_zpy(_val); break; // Count 25 - $96: Store X ZP, Y
                case "sty_zpx": self._sty_zpx(_val); break; // Count 26 - $94: Store Y ZP, X
                case "sta_abs": self._sta_abs(_val); break; // Count 27 - $8D: Store A Absolute
                case "stx_abs": self._stx_abs(_val); break; // Count 28 - $8E: Store X Absolute
                case "sty_abs": self._sty_abs(_val); break; // Count 29 - $8C: Store Y Absolute
                
                case "sta_abs_x":
                case "sta_abx":  self._sta_abx(_val); break; // Count 30 - $9D: Store A Absolute, X
                case "sta_abs_y":
                case "sta_aby":  self._sta_aby(_val); break; // Count 31 - $99: Store A Absolute, Y
                
                case "sta_izx": self._sta_izx(_val); break; // Count 32 - $81: Store A (Indirect, X)
                case "sta_iny":
				case "sta_izy": self._sta_izy(_val); break; // Count 33 - $91: Store A (Indirect), Y
                case "tax":      self.add(0xAA); break;      // Count 34 - $AA: Transfer A to X
                case "tay":      self.add(0xA8); break;      // Count 35 - $A8: Transfer A to Y
                case "tsx":      self.add(0xBA); break;      // Count 36 - $BA: Transfer S to X
                case "txa":      self.add(0x8A); break;      // Count 37 - $8A: Transfer X to A
                case "tya":      self.add(0x98); break;      // Count 38 - $98: Transfer Y to A
                case "txs":      self.add(0x9A); break;      // Count 39 - $9A: Transfer X to S
                
                case "ldx_abs_rep": self._ldx_abs(_val); break; // Count 40 - $AE: Load X Absolute (Rep)
                case "ldy_abs_rep": self._ldy_abs(_val); break; // Count 41 - $AC: Load Y Absolute (Rep)
                case "stx_abs_rep": self._stx_abs(_val); break; // Count 42 - $8E: Store X Absolute (Rep)
                case "sty_abs_rep": self._sty_abs(_val); break; // Count 43 - $8C: Store Y Absolute (Rep)
                case "lda_abs_rep": self._lda_abs(_val); break; // Count 44 - $AD: Load A Absolute (Rep)
                case "sta_zp_rep":  self._sta_zp(_val);  break; // Count 45 - $85: Store A ZP (Rep)
                case "ldx_imm_rep": self._ldx_imm(_val); break; // Count 46 - $A2: Load X Imm (Rep)
                case "ldy_imm_rep": self._ldy_imm(_val); break; // Count 47 - $A0: Load Y Imm (Rep)
                case "stx_zp_rep":  self._stx_zp(_val);  break; // Count 48 - $86: Store X ZP (Rep)
                case "sty_zp_rep":  self._sty_zp(_val);  break; // Count 49 - $84: Store Y ZP (Rep)
                case "tax_rep":      self.add(0xAA); break;      // Count 50 - $AA: Transfer A to X (Rep)
                case "tay_rep":      self.add(0xA8); break;      // Count 51 - $A8: Transfer A to Y (Rep)
                case "tsx_rep":      self.add(0xBA); break;      // Count 52 - $BA: Transfer S to X (Rep)

                //  PAGE 1: ALU & MATH 
                case "adc_imm": self._adc_imm(_val); break; // Count 53 - $69: Add with Carry Imm
                case "inx":      self.add(0xE8); break;      // Count 54 - $E8: Increment X
                case "iny":      self.add(0xC8); break;      // Count 55 - $C8: Increment Y
                case "adc_zp":  self._adc_zp(_val);  break; // Count 56 - $65: Add with Carry ZP
                case "dex":      self.add(0xCA); break;      // Count 57 - $CA: Decrement X
                case "dey":      self.add(0x88); break;      // Count 58 - $88: Decrement Y
                case "adc_zpx": self._adc_zpx(_val); break; // Count 59 - $75: Add with Carry ZP, X
                case "inc_zp":  self._inc_zp(_val);  break; // Count 60 - $E6: Increment Memory ZP
                case "dec_zp":  self._dec_zp(_val);  break; // Count 61 - $C6: Decrement Memory ZP
                case "adc_abs": self._adc_abs(_val); break; // Count 62 - $6D: Add with Carry Absolute
                case "inc_abs": self._inc_abs(_val); break; // Count 63 - $EE: Increment Memory Absolute
                case "dec_abs": self._dec_abs(_val); break; // Count 64 - $CE: Decrement Memory Absolute
                
                case "adc_abs_x":
                case "adc_abx":  self._adc_abx(_val); break; // Count 65 - $7D: Add with Carry Abs, X
                case "inc_abs_x":
                case "inc_abx":  self._inc_abx(_val); break; // Count 66 - $FE: Increment Memory Abs, X
                case "dec_abs_x":
                case "dec_abx":  self._dec_abx(_val); break; // Count 67 - $DE: Decrement Memory Abs, X
                case "adc_abs_y":
                case "adc_aby":  self._adc_aby(_val); break; // Count 68 - $79: Add with Carry Abs, Y
                
                case "adc_izx": self._adc_izx(_val); break; // Count 69 - $61: Add with Carry (Ind, X)
                case "adc_izy": self._adc_izy(_val); break; // Count 70 - $71: Add with Carry (Ind), Y
                case "sbc_imm": self._sbc_imm(_val); break; // Count 71 - $E9: Subtract with Carry Imm
                case "sbc_zp":  self._sbc_zp(_val);  break; // Count 72 - $E5: Subtract with Carry ZP
                case "sbc_abs": self._sbc_abs(_val); break; // Count 73 - $ED: Subtract with Carry Abs
                case "and_imm": self._and_imm(_val); break; // Count 74 - $29: Logic AND Imm
                case "cmp_imm": self._cmp_imm(_val); break; // Count 75 - $C9: Compare A Imm
                case "bit_zp":  self._bit_zp(_val);  break; // Count 76 - $24: Bit Test ZP
                case "and_zp":  self._and_zp(_val);  break; // Count 77 - $25: Logic AND ZP
                case "cpx_imm": self._cpx_imm(_val); break; // Count 78 - $E0: Compare X Imm
                case "cpy_imm": self._cpy_imm(_val); break; // Count 79 - $C0: Compare Y Imm
                case "and_abs": self._and_abs(_val); break; // Count 80 - $2D: Logic AND Abs
                case "cpx_zp":  self._cpx_zp(_val);  break; // Count 81 - $E4: Compare X ZP
                case "cpy_zp":  self._cpy_zp(_val);  break; // Count 82 - $C4: Compare Y ZP
                case "ora_imm": self._ora_imm(_val); break; // Count 83 - $09: Logic OR Imm
                case "ora_zp":  self._ora_zp(_val);  break; // Count 84 - $05: Logic OR ZP
                case "ora_abs": self._ora_abs(_val); break; // Count 85 - $0D: Logic OR Abs
                case "eor_imm": self._eor_imm(_val); break; // Count 86 - $49: Logic XOR Imm
                case "eor_zp":  self._eor_zp(_val);  break; // Count 87 - $45: Logic XOR ZP
                case "eor_abs": self._eor_abs(_val); break; // Count 88 - $4D: Logic XOR Abs
                case "sbc_zpx": self._sbc_zpx(_val); break; // Count 89 - $F5: Subtract with Carry ZP, X
                
                case "sbc_abs_x":
                case "sbc_abx":  self._sbc_abx(_val); break; // Count 90 - $FD: Subtract with Carry Abs, X
                case "sbc_abs_y":
                case "sbc_aby":  self._sbc_aby(_val); break; // Count 91 - $F9: Subtract with Carry Abs, Y
                
                case "sbc_izx": self._sbc_izx(_val); break; // Count 92 - $E1: Subtract with Carry (Ind, X)
                case "sbc_izy": self._sbc_izy(_val); break; // Count 93 - $F1: Subtract with Carry (Ind), Y
                case "ora_zpx": self._ora_zpx(_val); break; // Count 94 - $15: Logic OR ZP, X
                
                case "ora_abs_x":
                case "ora_abx":  self._ora_abx(_val); break; // Count 95 - $1D: Logic OR Abs, X
                case "ora_abs_y":
                case "ora_aby":  self._ora_aby(_val); break; // Count 96 - $19: Logic OR Abs, Y
                case "and_zpx": self._and_zpx(_val); break; // Count 97 - $35: Logic AND ZP, X
                
                case "and_abs_x":
                case "and_abx":  self._and_abx(_val); break; // Count 98 - $3D: Logic AND Abs, X
                case "and_abs_y":
                case "and_aby":  self._and_aby(_val); break; // Count 99 - $39: Logic AND Abs, Y
                case "eor_zpx": self._eor_zpx(_val); break; // Count 100- $55: Logic XOR ZP, X
                
                case "eor_abs_x":
                case "eor_abx":  self._eor_abx(_val); break; // Count 101- $5D: Logic XOR Abs, X
                case "eor_abs_y":
                case "eor_aby":  self._eor_aby(_val); break; // Count 102- $59: Logic XOR Abs, Y
                
                case "bit_abs": self._bit_abs(_val); break; // Count 103- $2C: Bit Test Absolute
                case "cpx_abs": self._cpx_abs(_val); break; // Count 104- $EC: Compare X Absolute

                //  PAGE 2: FLOW, SHIFTS & ILLEGALS 
                case "asl_a":   self.add(0x0A); break;      // Count 105- $0A: Arithmetic Shift Left A
                case "rol_a":   self.add(0x2A); break;      // Count 106- $2A: Rotate Left A
                case "ror_a":   self.add(0x6A); break;      // Count 107- $6A: Rotate Right A
                case "asl_zp":  self._asl_zp(_val);  break; // Count 108- $06: Arithmetic Shift Left ZP
                case "rol_zp":  self._rol_zp(_val);  break; // Count 109- $26: Rotate Left ZP
                case "ror_zp":  self._ror_zp(_val);  break; // Count 110- $66: Rotate Right ZP
                case "asl_abs": self._asl_abs(_val); break; // Count 111- $0E: Arithmetic Shift Left Abs
                case "rol_abs": self._rol_abs(_val); break; // Count 112- $2E: Rotate Left Absolute
                case "ror_abs": self._ror_abs(_val); break; // Count 113- $6E: Rotate Right Absolute
                case "lsr_a":   self.add(0x4A); break;      // Count 114- $4A: Logical Shift Right A
                case "lsr_zp":  self._lsr_zp(_val);  break; // Count 115- $46: Logical Shift Right ZP
                case "lsr_abs": self._lsr_abs(_val); break; // Count 116- $4E: Logical Shift Right Abs
                case "asl_zpx": self._asl_zpx(_val); break; // Count 117- $16: Arithmetic Shift Left ZP, X
                
                case "asl_abs_x":
                case "asl_abx":  self._asl_abx(_val); break; // Count 118- $1E: Arithmetic Shift Left Abs, X
                
                case "lsr_zpx": self._lsr_zpx(_val); break; // Count 119- $56: Logical Shift Right ZP, X
                
                case "lsr_abs_x":
                case "lsr_abx":  self._lsr_abx(_val); break; // Count 120- $5E: Logical Shift Right Abs, X
                
                case "rol_zpx": self._rol_zpx(_val); break; // Count 121- $36: Rotate Left ZP, X
                
                case "rol_abs_x":
                case "rol_abx":  self._rol_abx(_val); break; // Count 122- $3E: Rotate Left Abs, X
                
                case "ror_zpx": self._ror_zpx(_val); break; // Count 123- $76: Rotate Right ZP, X
                
                case "ror_abs_x":
                case "ror_abx":  self._ror_abx(_val); break; // Count 124- $7E: Rotate Right Abs, X
                

				case "jmp":
				case "jmp_abs": self._jmp_abs(_val); break;
                case "jsr_abs": self._jsr(_val);     break;
                case "jsr":     self._jsr(_val);     break;
                case "rts":     self._rts();         break; // Count 127- $60: Return from Subroutine
                case "bne":     self._bne(_val);     break; // Count 128- $D0: Branch Not Equal
                case "beq":     self._beq(_val);     break; // Count 129- $F0: Branch Equal
                case "jmp_ind": self._jmp_ind(_val); break; // Count 130- $6C: Jump Indirect
                case "bcc":     self._bcc(_val);     break; // Count 131- $90: Branch Carry Clear
                case "bcs":     self._bcs(_val);     break; // Count 132- $B0: Branch Carry Set
                case "bpl":     self._bpl(_val);     break; // Count 133- $10: Branch Plus
                case "bmi":     self._bmi(_val);     break; // Count 134- $30: Branch Minus
                case "bvc":     self._bvc(_val);     break; // Count 135- $50: Branch Overflow Clear
                case "bvs":     self._bvs(_val);     break; // Count 136- $70: Branch Overflow Set
                case "rti":     self._rti();         break; // Count 137- $40: Return from Interrupt
                case "lax_zp":  self.add([0xA7, _val]); break; // Count 138- $A7: Illegal: LDA+LDX ZP
                case "sax_zp":  self.add([0x87, _val]); break; // Count 139- $87: Illegal: STA&STX ZP
                case "dcp_abs": self.add([0xCF, _val&0xFF, _val>>8]); break; // Count 140- $CF: Illegal: DEC+CMP Abs
                case "isc_abs": self.add([0xEF, _val&0xFF, _val>>8]); break; // Count 141- $EF: Illegal: INC+SBC Abs
                case "rla_abs": self.add([0x2F, _val&0xFF, _val>>8]); break; // Count 142- $2F: Illegal: ROL+AND Abs
                case "slo_abs": self._slo_abs(_val); break; // Count 143- $0F: Illegal: ASL+ORA Abs
                case "sre_abs": self._sre_abs(_val); break; // Count 144- $4F: Illegal: LSR+EOR Abs
                case "clc":      self.add(0x18); break;      // Count 145- $18: Clear Carry
                case "sec":      self.add(0x38); break;      // Count 146- $38: Set Carry
                case "sei":      self.add(0x78); break;      // Count 147- $78: Set Interrupt Mask
                case "cli":      self.add(0x58); break;      // Count 148- $58: Clear Interrupt Mask
                case "pha":      self.add(0x48); break;      // Count 149- $48: Push Accumulator
                case "pla":      self.add(0x68); break;      // Count 150- $68: Pull Accumulator
                case "php":     self._php();    break;      // Count 151- $08: Push Processor Status
                case "plp":     self._plp();    break;      // Count 152- $28: Pull Processor Status
                case "clv":      self.add(0xB8); break;      // Count 153- $B8: Clear Overflow
                case "cld":      self.add(0xD8); break;      // Count 154- $D8: Clear Decimal Mode
                case "sed":      self.add(0xF8); break;      // Count 155- $F8: Set Decimal Mode
                case "cpy_abs": self._cpy_abs(_val); break; // Count 156- $CC: Compare Y Absolute
				case "cmp_abs":  self._cmp_abs(_val);  break; // $CD
				case "cmp_zp":   self._cmp_zp(_val);   break; // $C5
				case "cmp_zpx":  self.add([0xD5, _val]); break; // $D5
				case "cmp_abx":  self.add([0xDD, _val&0xFF, _val>>8]); break; // $DD
				case "cmp_aby":  self.add([0xD9, _val&0xFF, _val>>8]); break; // $D9
				case "cmp_izx":  self.add([0xC1, _val]); break; // $C1
				case "cmp_izy":  self.add([0xD1, _val]); break; // $D1

				case "and_izx":  self.add([0x21, _val]); break; // $21
				case "and_izy":  self.add([0x31, _val]); break; // $31
				case "ora_izx":  self.add([0x01, _val]); break; // $01
				case "ora_izy":  self.add([0x11, _val]); break; // $11
				case "eor_izx":  self.add([0x41, _val]); break; // $41
				case "eor_izy":  self.add([0x51, _val]); break; // $51
				case "inc_zpx":  self.add([0xF6, _val]); break; // $F6
				case "dec_zpx":  self.add([0xD6, _val]); break; // $D6
				case "lax_abs":  self.add([0xAF, _val&0xFF, _val>>8]); break;
				case "lax_aby":  self.add([0xBF, _val&0xFF, _val>>8]); break;
				case "lax_zpy":  self.add([0xB7, _val]); break;
				case "lax_izx":  self.add([0xA3, _val]); break;
				case "lax_izy":  self.add([0xB3, _val]); break;
				case "sax_abs":  self.add([0x8F, _val&0xFF, _val>>8]); break;
				case "sax_zpy":  self.add([0x97, _val]); break;
				case "sax_izx":  self.add([0x83, _val]); break;

				// ── EXTENDED ILLEGAL OPCODES (demoscene set) ──
				// The shelf only exposes the 7 "stable" illegals above as fixed-mode
				// buttons, but the opcode metadata table has always documented byte
				// values for the rest — this just wires those up so anything typed
				// as text in the code editor (or added as a node later) actually
				// assembles instead of silently emitting nothing.
				case "dcp_zp":   self.add([0xC7, _val]); break;
				case "dcp_zpx":  self.add([0xD7, _val]); break;
				case "dcp_abx":  self.add([0xDF, _val&0xFF, _val>>8]); break;
				case "dcp_aby":  self.add([0xDB, _val&0xFF, _val>>8]); break;
				case "dcp_izx":  self.add([0xC3, _val]); break;
				case "dcp_izy":  self.add([0xD3, _val]); break;

				case "isc_zp":   self.add([0xE7, _val]); break;
				case "isc_zpx":  self.add([0xF7, _val]); break;
				case "isc_abx":  self.add([0xFF, _val&0xFF, _val>>8]); break;
				case "isc_aby":  self.add([0xFB, _val&0xFF, _val>>8]); break;
				case "isc_izx":  self.add([0xE3, _val]); break;
				case "isc_izy":  self.add([0xF3, _val]); break;

				case "rla_zp":   self.add([0x27, _val]); break;
				case "rla_zpx":  self.add([0x37, _val]); break;
				case "rla_abx":  self.add([0x3F, _val&0xFF, _val>>8]); break;
				case "rla_aby":  self.add([0x3B, _val&0xFF, _val>>8]); break;
				case "rla_izx":  self.add([0x23, _val]); break;
				case "rla_izy":  self.add([0x33, _val]); break;

				case "rra_zp":   self.add([0x67, _val]); break;
				case "rra_zpx":  self.add([0x77, _val]); break;
				case "rra_abs":  self.add([0x6F, _val&0xFF, _val>>8]); break;
				case "rra_abx":  self.add([0x7F, _val&0xFF, _val>>8]); break;
				case "rra_aby":  self.add([0x7B, _val&0xFF, _val>>8]); break;
				case "rra_izx":  self.add([0x63, _val]); break;
				case "rra_izy":  self.add([0x73, _val]); break;

				case "slo_zp":   self.add([0x07, _val]); break;
				case "slo_zpx":  self.add([0x17, _val]); break;
				case "slo_abx":  self.add([0x1F, _val&0xFF, _val>>8]); break;
				case "slo_aby":  self.add([0x1B, _val&0xFF, _val>>8]); break;
				case "slo_izx":  self.add([0x03, _val]); break;
				case "slo_izy":  self.add([0x13, _val]); break;

				case "sre_zp":   self.add([0x47, _val]); break;
				case "sre_zpx":  self.add([0x57, _val]); break;
				case "sre_abx":  self.add([0x5F, _val&0xFF, _val>>8]); break;
				case "sre_aby":  self.add([0x5B, _val&0xFF, _val>>8]); break;
				case "sre_izx":  self.add([0x43, _val]); break;
				case "sre_izy":  self.add([0x53, _val]); break;

				// Immediate-only illegals
				case "anc_imm":  self.add([0x0B, _val]); break;
				case "anc2_imm": self.add([0x2B, _val]); break; // same effect as anc_imm, different opcode byte
				case "alr_imm":  self.add([0x4B, _val]); break;
				case "arr_imm":  self.add([0x6B, _val]); break;
				case "axs_imm":  self.add([0xCB, _val]); break;

				// Unofficial NOPs — stable cycle-padding, safe on real hardware
				case "nop_imm":  self.add([0x80, _val]); break;
				case "nop_zp":   self.add([0x04, _val]); break;
				case "nop_zpx":  self.add([0x14, _val]); break;
				case "nop_abs":  self.add([0x0C, _val&0xFF, _val>>8]); break;
				case "nop_abx":  self.add([0x1C, _val&0xFF, _val>>8]); break;

				// PALETTE ALIASES - _zp_x / _abs_x / _ind_x style bridging to existing cases
				// PALETTE ALIASES - only truly missing ones
				case "adc_zp_x":  self._adc_zpx(_val); break; // $75
				case "adc_ind_x": self._adc_izx(_val); break; // $61
				case "adc_ind_y": self._adc_izy(_val); break; // $71
				case "sbc_zp_x":  self._sbc_zpx(_val); break; // $F5
				case "sbc_ind_x": self._sbc_izx(_val); break; // $E1
				case "sbc_ind_y": self._sbc_izy(_val); break; // $F1
				case "and_zp_x":  self._and_zpx(_val); break; // $35
				case "ora_zp_x":  self._ora_zpx(_val); break; // $15
				case "eor_zp_x":  self._eor_zpx(_val); break; // $55
				case "asl_zp_x":  self._asl_zpx(_val); break; // $16
				case "lsr_zp_x":  self._lsr_zpx(_val); break; // $56
				case "rol_zp_x":  self._rol_zpx(_val); break; // $36
				case "ror_zp_x":  self._ror_zpx(_val); break; // $76
				
case "lda_lab_lo": {
    var _p = (self.pc_override>=0)
        ? (self.pc_override+1)-self.base_address-self.header_size
        : array_length(self.bytes)+1;
    self.add([0xA9, 0x00]);
    array_push(self.fixups, {pos: _p, label: _val, type: "lo"});
} break;

case "lda_lab_hi": {
    var _p = (self.pc_override>=0)
        ? (self.pc_override+1)-self.base_address-self.header_size
        : array_length(self.bytes)+1;
    self.add([0xA9, 0x00]);
    array_push(self.fixups, {pos: _p, label: _val, type: "hi"});
} break;

case "ldy_lab_lo": {
    var _p = (self.pc_override>=0)
        ? (self.pc_override+1)-self.base_address-self.header_size
        : array_length(self.bytes)+1;
    self.add([0xA0, 0x00]);
    array_push(self.fixups, {pos: _p, label: _val, type: "lo"});
} break;

case "ldy_lab_hi": {
    var _p = (self.pc_override>=0)
        ? (self.pc_override+1)-self.base_address-self.header_size
        : array_length(self.bytes)+1;
    self.add([0xA0, 0x00]);
    array_push(self.fixups, {pos: _p, label: _val, type: "hi"});
} break;

case "ldx_lab_lo": {
    var _p = (self.pc_override>=0)
        ? (self.pc_override+1)-self.base_address-self.header_size
        : array_length(self.bytes)+1;
    self.add([0xA2, 0x00]);
    array_push(self.fixups, {pos: _p, label: _val, type: "lo"});
} break;

case "ldx_lab_hi": {
    var _p = (self.pc_override>=0)
        ? (self.pc_override+1)-self.base_address-self.header_size
        : array_length(self.bytes)+1;
    self.add([0xA2, 0x00]);
    array_push(self.fixups, {pos: _p, label: _val, type: "hi"});
} break;
				
				
case "store_lo": {
    var _lab = _val[0]; var _dst = _val[1];
    var _pos = (self.pc_override >= 0)
        ? (self.pc_override + 1) - self.base_address - self.header_size
        : array_length(self.bytes) + 1;
    self.add([0xA9, 0x00, 0x8D, _dst & 0xFF, (_dst >> 8) & 0xFF]);
    array_push(self.fixups, {pos: _pos, label: _lab, type: "lo"});
} break;
case "store_hi": {
    var _lab = _val[0]; var _dst = _val[1];
    var _pos = (self.pc_override >= 0)
        ? (self.pc_override + 1) - self.base_address - self.header_size
        : array_length(self.bytes) + 1;
    self.add([0xA9, 0x00, 0x8D, _dst & 0xFF, (_dst >> 8) & 0xFF]);
    array_push(self.fixups, {pos: _pos, label: _lab, type: "hi"});
} break;

				case "lda_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0xAD,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "sta_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0x8D,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "stx_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0x8E,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "sty_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0x8C,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "ldx_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0xAE,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "ldy_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0xAC,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "inc_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0xEE,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "dec_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0xCE,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "cmp_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0xCD,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "ora_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0x0D,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
                case "jsr_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0x20,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
			    case "sbc_lab": { var _p = (self.pc_override>=0) ? (self.pc_override+1)-self.base_address-self.header_size : array_length(self.bytes)+1; self.add([0xED,0x00,0x00]); array_push(self.fixups, {pos: _p, label: _val, type: "abs"}); } break;
				// These should exist — add after sbc_lab if missing:
				case "byte_lab_lo": {
				    var _p = (self.pc_override >= 0)
				        ? self.pc_override - self.base_address - self.header_size
				        : array_length(self.bytes);
				    self.add(0x00);
				    array_push(self.fixups, {pos: _p, label: _val, type: "lo"});
				} break;
				case "byte_lab_hi": {
				    var _p = (self.pc_override >= 0)
				        ? self.pc_override - self.base_address - self.header_size
				        : array_length(self.bytes);
				    self.add(0x00);
				    array_push(self.fixups, {pos: _p, label: _val, type: "hi"});
				} break;
				case "byte": self.add(_val & 0xFF); break;
                case "label": self.label(_val); break;
                case "org":   self.org(_val);   break;

				
            }
            return array_length(self.bytes) - start_count;
        },

        // ================================================================
        // INSTRUCTION EMITTERS
        // ================================================================
        _lda_imm: function(v) { return self.add([0xA9, v]); },
        _lda_zp:  function(a) { return self.add([0xA5, a]); },
        _lda_zpx: function(a) { return self.add([0xB5, a]); },
        _lda_abs: function(a) { return self.add([0xAD, a&0xFF, a>>8]); },
        _lda_abx: function(a) { return self.add([0xBD, a&0xFF, a>>8]); },
        _lda_aby: function(a) { return self.add([0xB9, a&0xFF, a>>8]); },
        _lda_izx: function(a) { return self.add([0xA1, a]); },
        _lda_izy: function(a) { return self.add([0xB1, a]); },
        _ldx_imm: function(v) { return self.add([0xA2, v]); },
        _ldx_zp:  function(a) { return self.add([0xA6, a]); },
        _ldx_zpy: function(a) { return self.add([0xB6, a]); },
        _ldx_abs: function(a) { return self.add([0xAE, a&0xFF, a>>8]); },
        _ldx_aby: function(a) { return self.add([0xBE, a&0xFF, a>>8]); },
        _ldy_imm: function(v) { return self.add([0xA0, v]); },
        _ldy_zp:  function(a) { return self.add([0xA4, a]); },
        _ldy_zpx: function(a) { return self.add([0xB4, a]); },
        _ldy_abs: function(a) { return self.add([0xAC, a&0xFF, a>>8]); },
        _ldy_abx: function(a) { return self.add([0xBC, a&0xFF, a>>8]); },
        _sta_zp:  function(a) { return self.add([0x85, a]); },
        _sta_zpx: function(a) { return self.add([0x95, a]); },
        _sta_abs: function(a) { return self.add([0x8D, a&0xFF, a>>8]); },
        _sta_abx: function(a) { return self.add([0x9D, a&0xFF, a>>8]); },
        _sta_aby: function(a) { return self.add([0x99, a&0xFF, a>>8]); },
        _sta_izx: function(a) { return self.add([0x81, a]); },
        _sta_izy: function(a) { return self.add([0x91, a]); },
        _stx_zp:  function(a) { return self.add([0x86, a]); },
        _stx_zpy: function(a) { return self.add([0x96, a]); },
        _stx_abs: function(a) { return self.add([0x8E, a&0xFF, a>>8]); },
        _sty_zp:  function(a) { return self.add([0x84, a]); },
        _sty_zpx: function(a) { return self.add([0x94, a]); },
        _sty_abs: function(a) { return self.add([0x8C, a&0xFF, a>>8]); },
        _adc_imm: function(v) { return self.add([0x69, v]); },
        _adc_zp:  function(a) { return self.add([0x65, a]); },
        _adc_zpx: function(a) { return self.add([0x75, a]); },
        _adc_abs: function(a) { return self.add([0x6D, a&0xFF, a>>8]); },
        _adc_abx: function(a) { return self.add([0x7D, a&0xFF, a>>8]); },
        _adc_aby: function(a) { return self.add([0x79, a&0xFF, a>>8]); },
        _adc_izx: function(a) { return self.add([0x61, a]); },
        _adc_izy: function(a) { return self.add([0x71, a]); },
        _sbc_imm: function(v) { return self.add([0xE9, v]); },
        _sbc_zp:  function(a) { return self.add([0xE5, a]); },
        _sbc_zpx: function(a) { return self.add([0xF5, a]); },
        _sbc_abs: function(a) { return self.add([0xED, a&0xFF, a>>8]); },
        _sbc_abx: function(a) { return self.add([0xFD, a&0xFF, a>>8]); },
        _sbc_aby: function(a) { return self.add([0xF9, a&0xFF, a>>8]); },
        _sbc_izx: function(a) { return self.add([0xE1, a]); },
        _sbc_izy: function(a) { return self.add([0xF1, a]); },
        _inc_zp:  function(a) { return self.add([0xE6, a]); },
        _inc_abs: function(a) { return self.add([0xEE, a&0xFF, a>>8]); },
        _inc_abx: function(a) { return self.add([0xFE, a&0xFF, a>>8]); },
        _dec_zp:  function(a) { return self.add([0xC6, a]); },
        _dec_abs: function(a) { return self.add([0xCE, a&0xFF, a>>8]); },
        _dec_abx: function(a) { return self.add([0xDE, a&0xFF, a>>8]); },
        _and_imm: function(v) { return self.add([0x29, v]); },
        _and_zp:  function(a) { return self.add([0x25, a]); },
        _and_zpx: function(a) { return self.add([0x35, a]); },
        _and_abs: function(a) { return self.add([0x2D, a&0xFF, a>>8]); },
        _and_abx: function(a) { return self.add([0x3D, a&0xFF, a>>8]); },
        _and_aby: function(a) { return self.add([0x39, a&0xFF, a>>8]); },
        _ora_imm: function(v) { return self.add([0x09, v]); },
        _ora_zp:  function(a) { return self.add([0x05, a]); },
        _ora_zpx: function(a) { return self.add([0x15, a]); },
        _ora_abs: function(a) { return self.add([0x0D, a&0xFF, a>>8]); },
        _ora_abx: function(a) { return self.add([0x1D, a&0xFF, a>>8]); },
        _ora_aby: function(a) { return self.add([0x19, a&0xFF, a>>8]); },
        _eor_imm: function(v) { return self.add([0x49, v]); },
        _eor_zp:  function(a) { return self.add([0x45, a]); },
        _eor_zpx: function(a) { return self.add([0x55, a]); },
        _eor_abs: function(a) { return self.add([0x4D, a&0xFF, a>>8]); },
        _eor_abx: function(a) { return self.add([0x5D, a&0xFF, a>>8]); },
        _eor_aby: function(a) { return self.add([0x59, a&0xFF, a>>8]); },
        _bit_zp:  function(a) { return self.add([0x24, a]); },
        _bit_abs: function(a) { return self.add([0x2C, a&0xFF, a>>8]); },
        _cmp_imm: function(v) { return self.add([0xC9, v]); },
        _cmp_zp:  function(a) { return self.add([0xC5, a]); },
        _cmp_abs: function(a) { return self.add([0xCD, a&0xFF, a>>8]); },
        _cpx_imm: function(v) { return self.add([0xE0, v]); },
        _cpx_zp:  function(a) { return self.add([0xE4, a]); },
        _cpx_abs: function(a) { return self.add([0xEC, a&0xFF, a>>8]); },
        _cpy_imm: function(v) { return self.add([0xC0, v]); },
        _cpy_zp:  function(a) { return self.add([0xC4, a]); },
        _cpy_abs: function(a) { return self.add([0xCC, a&0xFF, a>>8]); },
        _asl_zp:  function(a) { return self.add([0x06, a]); },
        _asl_zpx: function(a) { return self.add([0x16, a]); },
        _asl_abs: function(a) { return self.add([0x0E, a&0xFF, a>>8]); },
        _asl_abx: function(a) { return self.add([0x1E, a&0xFF, a>>8]); },
        _lsr_zp:  function(a) { return self.add([0x46, a]); },
        _lsr_zpx: function(a) { return self.add([0x56, a]); },
        _lsr_abs: function(a) { return self.add([0x4E, a&0xFF, a>>8]); },
        _lsr_abx: function(a) { return self.add([0x5E, a&0xFF, a>>8]); },
        _rol_zp:  function(a) { return self.add([0x26, a]); },
        _rol_zpx: function(a) { return self.add([0x36, a]); },
        _rol_abs: function(a) { return self.add([0x2E, a&0xFF, a>>8]); },
        _rol_abx: function(a) { return self.add([0x3E, a&0xFF, a>>8]); },
        _ror_zp:  function(a) { return self.add([0x66, a]); },
        _ror_zpx: function(a) { return self.add([0x76, a]); },
        _ror_abs: function(a) { return self.add([0x6E, a&0xFF, a>>8]); },
        _ror_abx: function(a) { return self.add([0x7E, a&0xFF, a>>8]); },
        
        //  BRANCHING (Relative) 
        _bpl: function(n) { return self._add_fix(0x10, n, "rel"); }, // Count 133
        _bmi: function(n) { return self._add_fix(0x30, n, "rel"); }, // Count 134
        _bvc: function(n) { return self._add_fix(0x50, n, "rel"); }, // Count 135
        _bvs: function(n) { return self._add_fix(0x70, n, "rel"); }, // Count 136
        _bne: function(n) { return self._add_fix(0xD0, n, "rel"); }, // Count 128
        _beq: function(n) { return self._add_fix(0xF0, n, "rel"); }, // Count 129
        _bcc: function(n) { return self._add_fix(0x90, n, "rel"); }, // Count 131
        _bcs: function(n) { return self._add_fix(0xB0, n, "rel"); }, // Count 132

        //  FLOW CONTROL (Absolute/Indirect) 
        _jsr:     function(n) { return self._add_fix(0x20, n, "abs"); }, // Count 126
        _rts:     function()  { return self.add(0x60); },               // Count 127
        _rti:     function()  { return self.add(0x40); },               // Count 137
        _jmp_abs: function(n) { return self._add_fix(0x4C, n, "abs"); }, // Count 125
        _jmp_ind: function(a) { return self.add([0x6C, a & 0xFF, a >> 8]); }, // Count 130

        //  STACK & SYSTEM 
        _php: function() { return self.add(0x08); }, // Count 151
        _plp: function() { return self.add(0x28); }, // Count 152

        //  STABLE ILLEGALS 
        _slo_abs: function(a) { return self.add([0x0F, a & 0xFF, a >> 8]); }, // Count 143
        _sre_abs: function(a) { return self.add([0x4F, a & 0xFF, a >> 8]); }, // Count 144

        //  METADATA 
org: function(_addr) {
			if (_addr == -2) {
                // Save current PC to stack — always save the actual current PC
                array_push(self.pc_stack, self.current_pc());
            } else if (_addr == -3) {
                // Restore saved PC from stack
                if (variable_struct_exists(self, "pc_stack") && array_length(self.pc_stack) > 0) {
                    self.pc_override = array_pop(self.pc_stack);
                }
            } else {
                self.pc_override = _addr;
            }
            return self;
        },

label: function(_name) {
    var _pc = self.current_pc();
    self.labels[? _name] = _pc;
    return self;
},



		
		_add_fix_store: function(lab, dest_addr, part) {
		    // Emit: LDA #00 / STA abs — placeholder, patched by assemble()
		    var pos = (self.pc_override >= 0)
		        ? (self.pc_override + 1) - self.base_address - self.header_size
		        : array_length(self.bytes) + 1;
		    self.add([0xA9, 0x00]);          // LDA #placeholder
		    self.add([0x8D, dest_addr & 0xFF, (dest_addr >> 8) & 0xFF]); // STA abs
		    array_push(self.fixups, {pos: pos, label: lab, type: part, dest: dest_addr});
		    return self;
		},
		
		_add_fix: function(op, lab, type) {
		    var pos;
		    if (self.pc_override >= 0) {
		        pos = (self.pc_override + 1) - self.base_address - self.header_size;
		    } else {
		        pos = array_length(self.bytes) + 1;
		    }
		    self.add(op);
		    if (type == "abs") self.add([0,0]); else self.add(0x00);
    
if (is_real(lab)) {
        if (type == "abs") {
            show_debug_message("_add_fix immediate abs: op=$" + string_upper(decimal_to_hex(op)) + " lab=$" + string_upper(decimal_to_hex(lab)) + " pos=" + string(pos) + " bytes_len=" + string(array_length(self.bytes)));
            self.bytes[pos]   = lab & 0xFF;
            self.bytes[pos+1] = (lab >> 8) & 0xFF;
        } else if (type == "rel") {
            var _pc_next = self.base_address + self.header_size + pos + 1;
            var _off = lab - _pc_next;
            // A 6502 relative branch reaches -128..+127. Storing anything
            // else produces a branch to an arbitrary address that still
            // assembles cleanly, which is about the worst failure mode an
            // assembler has. Say so loudly rather than emitting it quietly.
            if (_off < -128 || _off > 127) {
                show_debug_message("ASM ERROR: branch out of range by "
                    + string(_off) + " bytes at $"
                    + string_upper(decimal_to_hex(_pc_next - 1))
                    + " -> $" + string_upper(decimal_to_hex(lab))
                    + "  (use BNE over a JMP instead)");
                global.asm_branch_error = true;
            }
            self.bytes[pos] = (_off < 0) ? (256 + _off) : (_off & 0xFF);
        } else {
            self.bytes[pos] = lab & 0xFF;
        }
		    } else {
		        array_push(self.fixups, {pos: pos, label: lab, type: type});
		    }
		    return self;
		},

assemble: function() {
		    var _blen = array_length(self.bytes);
		    // TEMP DEBUG — dump every sng-prefixed label in the map
		    var _dbg_k = ds_map_find_first(self.labels);
		    while (!is_undefined(_dbg_k)) {
		        if (string_pos("sng", string(_dbg_k)) == 1) {
		            show_debug_message("LABEL MAP: [" + string(_dbg_k) + "] = $"
		                + string_upper(decimal_to_hex(self.labels[? _dbg_k])));
		        }
		        _dbg_k = ds_map_find_next(self.labels, _dbg_k);
		    }
		    for (var i = 0; i < array_length(self.fixups); i++) {
		        var f = self.fixups[i];
		        if (!ds_map_exists(self.labels, f.label)) {
		            show_debug_message("FIXUP UNRESOLVED: label=[" + string(f.label) + "] pos=" + string(f.pos) + " type=" + f.type);
		            if (f.label == "BMPMODE" || f.label == "TXTMODE" || f.label == "BMPMODE2")
		                show_debug_message("  >>> CRITICAL: IRQ target label missing from label map!");
		            continue;
		        }
		        var target = self.labels[? f.label];
        if (f.label == "BMPMODE" || f.label == "TXTMODE" || f.label == "BMPMODE2")
		            show_debug_message("FIXUP RESOLVED: label=[" + f.label + "] target=$" + string_upper(decimal_to_hex(target)) + " type=" + f.type + " pos=" + string(f.pos));
		        if (f.pos < 0 || f.pos >= _blen) {
		            show_debug_message("FIXUP OOB: label=[" + string(f.label) + "] pos=" + string(f.pos) + " blen=" + string(_blen) + " target=$" + string_upper(decimal_to_hex(target)));
		            continue;
		        }
		        if (f.type == "rel") {
		            var pc_next = self.base_address + self.header_size + f.pos + 1;
		            var off = target - pc_next;
		            // Same range check as the immediate path above. This is
		            // the one that fires for forward branches to a label,
		            // which is exactly where a long branch comes from.
		            if (off < -128 || off > 127) {
		                show_debug_message("ASM ERROR: branch out of range by "
		                    + string(off) + " bytes at $"
		                    + string_upper(decimal_to_hex(pc_next - 1))
		                    + " -> [" + string(f.label) + "] $"
		                    + string_upper(decimal_to_hex(target))
		                    + "  (use BNE over a JMP instead)");
		                global.asm_branch_error = true;
		            }
		            self.bytes[f.pos] = (off < 0) ? (256 + off) : off;
		        } else if (f.type == "lo") {
		            self.bytes[f.pos] = target & 0xFF;
		        } else if (f.type == "hi") {
		            self.bytes[f.pos] = (target >> 8) & 0xFF;
		        } else {
		            if (f.pos + 1 >= _blen) {
		                show_debug_message("FIXUP ABS OOB+1: label=[" + string(f.label) + "] pos=" + string(f.pos) + " blen=" + string(_blen));
		                continue;
		            }
		            self.bytes[f.pos]   = target & 0xFF;
		            self.bytes[f.pos+1] = (target >> 8) & 0xFF;
		        }
		    }
		}
    };
    return prog;
}