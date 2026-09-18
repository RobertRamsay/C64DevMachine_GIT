	/// @function scr_mbb_emit_mask_cells(_list, _id, _pfx, _src_scr, _src_col_loc, _dst_scr)
	/// @desc Emits the ASSET-mode MASK00 bitmap blit for MACRO_MOVE_BMP_BLOCK.
	///       Called from the copy-body subroutine, in place of the flat OPAQUE run.
	///
	/// WHY THIS IS NOT A FLAT RUN
	/// OPAQUE copies w*8 consecutive bytes per char row — cells interleaved, no
	/// per-cell state, about ten cycles a byte. MASK00 cannot do that.
	///
	/// A masked merge combines two cells that have DIFFERENT palettes, and the
	/// merged cell can only carry ONE. The source's wins. That leaves the
	/// destination pixels surviving under the source's %00 holes pointing at bit
	/// pairs whose colours no longer exist, so each surviving pair must be
	/// REMAPPED onto whichever source slot holds a colour of the same luma group.
	///
	///   dest %01 -> first source slot whose MBBTONE group matches
	///   dest %10 -> likewise
	///   dest %11 -> likewise
	///
	/// Scan order is %01 -> %10 -> %11, so ties go to the LOWEST source slot. No
	/// group match at all falls through to identity, which means the source's
	/// colour in that same slot wins — consistent with "source palette wins".
	///
	/// So the work is per-cell: read both palettes, build a three-entry
	/// substitution table, then merge that cell's eight bytes pair by pair.
	/// Roughly 320 cycles a cell. MASK00 is a level-build operation, never a
	/// per-frame one, so the cost does not matter.
	///
	/// INPUTS (set up by the caller, unchanged from the OPAQUE path)
	///   $F4 sc   $F5 sr   $F6 dc   $F7 dr   $F8 w   $F9 h
	///   $FB/$FC  src bitmap pointer, top-left cell of the record
	///   $FD/$FE  dst bitmap pointer, top-left cell of the record
	///
	/// CLOBBERS  A, X, Y, $FB-$FE. All other state is absolute scratch emitted
	///           inline below, so zero-page pressure is unchanged.
	///
	/// REQUIRES  MBBTONE (16-byte colour -> group LUT) and MBBR40_LO/HI, both
	///           emitted once per build by the caller.
	function scr_mbb_emit_mask_cells(_list, _id, _pfx, _src_scr, _src_col_loc, _dst_scr) {

	    // ── Absolute scratch. Emitted inline and jumped over. ──
	    var _lbl_skip = _pfx + "mvskip";
	    array_push(_list, ["jmp_abs", _lbl_skip, _id]);

	    var _v_s1   = _pfx + "S1";     // source cell's %01 colour
	    var _v_s2   = _pfx + "S2";     // source cell's %10 colour
	    var _v_s3   = _pfx + "S3";     // source cell's %11 colour
	    // SUB table. SUB0 is a dead padding byte that exists purely so the table
	    // can be indexed by the dest pair value (1, 2 or 3) with no decrement:
	    // lda SUB0,x reaches SUB1/SUB2/SUB3 for x = 1/2/3. Labels do not support
	    // arithmetic in this assembler, so "SUB1 - 1" is not expressible.
	    var _v_sub0 = _pfx + "SUB0";
	    var _v_sub1 = _pfx + "SUB1";   // dest %01 -> source pair (1, 2 or 3)
	    var _v_sub2 = _pfx + "SUB2";   // dest %10 -> source pair
	    var _v_sub3 = _pfx + "SUB3";   // dest %11 -> source pair
	    var _v_cell = _pfx + "CELL";   // cells left in this char row
	    var _v_row  = _pfx + "ROW";    // char rows left
	    var _v_tmp  = _pfx + "TMP";    // merged-byte accumulator
	    var _v_srcb = _pfx + "SRCB";   // source byte in hand
	    var _v_dstb = _pfx + "DSTB";   // dest byte in hand
	    var _v_grp  = _pfx + "GRP";    // group of the dest slot being resolved
	    var _v_byi  = _pfx + "BYI";    // pixel row within the cell, 0..7
	    // Slot-insertion state. USED is a bitmask of which source bit-pairs the
	    // cell's 8 bitmap bytes actually paint: bit 1 = %01, bit 2 = %10,
	    // bit 3 = %11. A clear bit means that slot's colour is never displayed, so
	    // the slot is free to be overwritten with a destination colour — that is
	    // the only way a colour absent from the source palette can survive the
	    // merge. NEWS1/2/3 start as the source's colours and are overwritten as
	    // slots get claimed; the palette write-back at the end of the cell uses
	    // them rather than re-reading the source bytes.
	    var _v_used = _pfx + "USED";
	    var _v_ns1  = _pfx + "NEWS1";
	    var _v_ns2  = _pfx + "NEWS2";
	    var _v_ns3  = _pfx + "NEWS3";
	    var _v_dcol = _pfx + "DCOL";   // dest colour being placed, this slot
	    // (TRN removed — a slot painting colour $00 is a real pixel, not a hole.
	    //  Only bitmap pair %00 is a hole, handled directly in the merge loop.)
	    // Per-slot painted-pixel counts for this cell, 0..32. A cell is allowed two
	    // non-background colours; when all three slots are painted, the sparsest is
	    // dropped into TRN and its pixels become holes, freeing a palette slot for
	    // a destination colour to claim. Fewest pixels is the cheapest proxy for
	    // least visual damage, and ties go to the lowest slot so the result is
	    // deterministic across builds.
	    var _v_cn1  = _pfx + "CN1";
	    var _v_cn2  = _pfx + "CN2";
	    var _v_cn3  = _pfx + "CN3";

	    var _v_spl  = _pfx + "SPL";    // source screen  ptr, current cell
	    var _v_sph  = _pfx + "SPH";
	    var _v_scl  = _pfx + "SCL";    // source colour  ptr, current cell
	    var _v_sch  = _pfx + "SCH";
	    var _v_dpl  = _pfx + "DPL";    // dest screen    ptr, current cell
	    var _v_dph  = _pfx + "DPH";
	    var _v_dcl  = _pfx + "DCL";    // dest colour    ptr, current cell
	    var _v_dch  = _pfx + "DCH";

	    var _v_sbl  = _pfx + "SBL";    // source bitmap  ptr, current cell
	    var _v_sbh  = _pfx + "SBH";
	    var _v_dbl  = _pfx + "DBL";    // dest bitmap    ptr, current cell
	    var _v_dbh  = _pfx + "DBH";

	    var _v_rspl = _pfx + "RSPL";   // row-start copies, restored each new row
	    var _v_rsph = _pfx + "RSPH";
	    var _v_rscl = _pfx + "RSCL";
	    var _v_rsch = _pfx + "RSCH";
	    var _v_rdpl = _pfx + "RDPL";
	    var _v_rdph = _pfx + "RDPH";
	    var _v_rdcl = _pfx + "RDCL";
	    var _v_rdch = _pfx + "RDCH";
	    var _v_rsbl = _pfx + "RSBL";
	    var _v_rsbh = _pfx + "RSBH";
	    var _v_rdbl = _pfx + "RDBL";
	    var _v_rdbh = _pfx + "RDBH";

	    // SUB0..SUB3 must stay contiguous and in this order — the merge indexes
	    // them as a table.
	    var _scratch = [
	        _v_s1, _v_s2, _v_s3, _v_sub0, _v_sub1, _v_sub2, _v_sub3,
	        _v_cell, _v_row, _v_tmp, _v_srcb, _v_dstb, _v_grp, _v_byi,
	        _v_used, _v_ns1, _v_ns2, _v_ns3, _v_dcol,
	        _v_cn1, _v_cn2, _v_cn3,
	        _v_spl, _v_sph, _v_scl, _v_sch, _v_dpl, _v_dph, _v_dcl, _v_dch,
	        _v_sbl, _v_sbh, _v_dbl, _v_dbh,
	        _v_rspl, _v_rsph, _v_rscl, _v_rsch,
	        _v_rdpl, _v_rdph, _v_rdcl, _v_rdch,
	        _v_rsbl, _v_rsbh, _v_rdbl, _v_rdbh
	    ];
	    for (var _si = 0; _si < array_length(_scratch); _si++) {
	        array_push(_list, ["label", _scratch[_si]]);
	        array_push(_list, ["byte",  0, _id]);
	    }
	    array_push(_list, ["label", _lbl_skip]);

	    // ── Park the record's bitmap pointers ──
	    // They arrive in $FB-$FE, but the cell walk rebuilds those for every cell
	    // and every plane, so the row bases must live in absolute scratch.
	    array_push(_list, ["lda_zp",  0xFB,    _id]);
	    array_push(_list, ["sta_abs", _v_rsbl, _id]);
	    array_push(_list, ["lda_zp",  0xFC,    _id]);
	    array_push(_list, ["sta_abs", _v_rsbh, _id]);
	    array_push(_list, ["lda_zp",  0xFD,    _id]);
	    array_push(_list, ["sta_abs", _v_rdbl, _id]);
	    array_push(_list, ["lda_zp",  0xFE,    _id]);
	    array_push(_list, ["sta_abs", _v_rdbh, _id]);

	    // ── Palette pointers for the record's top-left cell ──
	    //
	    // Each of the four is built independently from its OWN base address, never
	    // derived from another by a compile-time delta. For a bank-2 source the
	    // colour block sits at bmp+8000 while the screen matrix is at
	    // bankbase+$3C00 — that delta is NEGATIVE, so deriving colour from screen
	    // lands nowhere near the data. scr_bmp_regions owns both addresses; each is
	    // used directly.
	    //
	    //   ptr = base + MBBR40[row] + col
	    //
	    // The carry is chained one addend at a time. Two ADCs off a single CLC eats
	    // the intermediate carry and drops 256 bytes.
	    var _emit_ptr = function(_list, _id, _base, _zp_row, _zp_col, _out_lo, _out_hi) {
	        array_push(_list, ["ldx_zp",  _zp_row,       _id]);
	        array_push(_list, ["clc",     0,             _id]);
	        array_push(_list, ["lda_abx", "MBBR40_LO",   _id]);
	        array_push(_list, ["adc_imm", _base & 0xFF,        _id]);
	        array_push(_list, ["sta_abs", _out_lo,       _id]);
	        array_push(_list, ["lda_abx", "MBBR40_HI",   _id]);
	        array_push(_list, ["adc_imm", (_base >> 8) & 0xFF, _id]);
	        array_push(_list, ["sta_abs", _out_hi,       _id]);
	        array_push(_list, ["clc",     0,             _id]);
	        array_push(_list, ["lda_abs", _out_lo,       _id]);
	        array_push(_list, ["adc_zp",  _zp_col,       _id]);
	        array_push(_list, ["sta_abs", _out_lo,       _id]);
	        array_push(_list, ["lda_abs", _out_hi,       _id]);
	        array_push(_list, ["adc_imm", 0,             _id]);
	        array_push(_list, ["sta_abs", _out_hi,       _id]);
	    };
	    _emit_ptr(_list, _id, _src_scr,     0xF5, 0xF4, _v_rspl, _v_rsph);
	    _emit_ptr(_list, _id, _src_col_loc, 0xF5, 0xF4, _v_rscl, _v_rsch);
	    _emit_ptr(_list, _id, _dst_scr,     0xF7, 0xF6, _v_rdpl, _v_rdph);
	    _emit_ptr(_list, _id, 0xD800,       0xF7, 0xF6, _v_rdcl, _v_rdch);

	    // Small helper: copy a 16-bit absolute pair.
	    var _emit_mov16 = function(_list, _id, _from_lo, _from_hi, _to_lo, _to_hi) {
	        array_push(_list, ["lda_abs", _from_lo, _id]);
	        array_push(_list, ["sta_abs", _to_lo,   _id]);
	        array_push(_list, ["lda_abs", _from_hi, _id]);
	        array_push(_list, ["sta_abs", _to_hi,   _id]);
	    };
	    // Small helper: add an 8-bit constant to a 16-bit absolute pair.
	    var _emit_add16 = function(_list, _id, _lo, _hi, _amt) {
	        array_push(_list, ["clc",     0,              _id]);
	        array_push(_list, ["lda_abs", _lo,            _id]);
	        array_push(_list, ["adc_imm", _amt & 0xFF,    _id]);
	        array_push(_list, ["sta_abs", _lo,            _id]);
	        array_push(_list, ["lda_abs", _hi,            _id]);
	        array_push(_list, ["adc_imm", (_amt >> 8) & 0xFF, _id]);
	        array_push(_list, ["sta_abs", _hi,            _id]);
	    };
	    // Small helper: load an absolute 16-bit pair into $FB/$FC for (zp),y use.
	    var _emit_toptr = function(_list, _id, _lo, _hi) {
	        array_push(_list, ["lda_abs", _lo,  _id]);
	        array_push(_list, ["sta_zp",  0xFB, _id]);
	        array_push(_list, ["lda_abs", _hi,  _id]);
	        array_push(_list, ["sta_zp",  0xFC, _id]);
	    };
	    // Long back-branch. All three loop bodies here run well past the 6502's
	    // +-127 relative branch range (the byte loop alone is ~242 bytes), so a
	    // plain BNE back to the top will not assemble. Invert the condition, branch
	    // forward over a JMP, and let the JMP do the work.
	    //
	    //     bne target        becomes     beq skip
	    //                                   jmp target
	    //                                 skip:
	    var _emit_long_bne = function(_list, _id, _target, _skip) {
	        array_push(_list, ["beq",     _skip,   _id]);
	        array_push(_list, ["jmp_abs", _target, _id]);
	        array_push(_list, ["label",   _skip         ]);
	    };

	    array_push(_list, ["lda_zp",  0xF9,   _id]);   // h
	    array_push(_list, ["sta_abs", _v_row, _id]);

	    // ═══════════════════════ ROW LOOP ═══════════════════════
	    var _lbl_row = _pfx + "mrow";
	    array_push(_list, ["label", _lbl_row]);

	    array_push(_list, ["lda_zp",  0xF8,    _id]);  // w
	    array_push(_list, ["sta_abs", _v_cell, _id]);
	    _emit_mov16(_list, _id, _v_rsbl, _v_rsbh, _v_sbl, _v_sbh);
	    _emit_mov16(_list, _id, _v_rdbl, _v_rdbh, _v_dbl, _v_dbh);
	    _emit_mov16(_list, _id, _v_rspl, _v_rsph, _v_spl, _v_sph);
	    _emit_mov16(_list, _id, _v_rscl, _v_rsch, _v_scl, _v_sch);
	    _emit_mov16(_list, _id, _v_rdpl, _v_rdph, _v_dpl, _v_dph);
	    _emit_mov16(_list, _id, _v_rdcl, _v_rdch, _v_dcl, _v_dch);

	    // ═══════════════════════ CELL LOOP ═══════════════════════
	    var _lbl_cell = _pfx + "mcell";
	    array_push(_list, ["label", _lbl_cell]);

	    // ── Source cell palette ──
	    // Screen RAM: high nibble = C1 (%01), low nibble = C2 (%10).
	    // Colour RAM low nibble = C3 (%11).
	    array_push(_list, ["ldy_imm", 0, _id]);
	    _emit_toptr(_list, _id, _v_spl, _v_sph);
	    array_push(_list, ["lda_izy", 0xFB,  _id]);
	    array_push(_list, ["pha",     0,     _id]);
	    array_push(_list, ["and_imm", 0x0F,  _id]);
	    array_push(_list, ["sta_abs", _v_s2, _id]);
	    array_push(_list, ["pla",     0,     _id]);
	    array_push(_list, ["lsr_a",   0,     _id]);
	    array_push(_list, ["lsr_a",   0,     _id]);
	    array_push(_list, ["lsr_a",   0,     _id]);
	    array_push(_list, ["lsr_a",   0,     _id]);
	    array_push(_list, ["sta_abs", _v_s1, _id]);
	    _emit_toptr(_list, _id, _v_scl, _v_sch);
	    array_push(_list, ["lda_izy", 0xFB,  _id]);
	    array_push(_list, ["and_imm", 0x0F,  _id]);
	    array_push(_list, ["sta_abs", _v_s3, _id]);

	    // ── Seed the outgoing palette with the source's ──
	    array_push(_list, ["lda_abs", _v_s1, _id]);
	    array_push(_list, ["sta_abs", _v_ns1, _id]);
	    array_push(_list, ["lda_abs", _v_s2, _id]);
	    array_push(_list, ["sta_abs", _v_ns2, _id]);
	    array_push(_list, ["lda_abs", _v_s3, _id]);
	    array_push(_list, ["sta_abs", _v_ns3, _id]);

	    // ── Count painted pixels per slot ──
	    // One pass over the cell's eight bytes, four pairs each. A pair's value is
	    // its slot number, so the count lands in CN1/CN2/CN3 directly. Black slots
	    // are skipped here rather than counted and discarded later, so a cell that
	    // paints black plus two colours still reads as a two-colour cell.
	    var _lbl_uby = _pfx + "uby";
	    array_push(_list, ["lda_imm", 0,      _id]);
	    array_push(_list, ["sta_abs", _v_cn1, _id]);
	    array_push(_list, ["sta_abs", _v_cn2, _id]);
	    array_push(_list, ["sta_abs", _v_cn3, _id]);
	    array_push(_list, ["ldy_imm", 0,      _id]);
	    _emit_toptr(_list, _id, _v_sbl, _v_sbh);
	    array_push(_list, ["label",   _lbl_uby     ]);
	    array_push(_list, ["lda_izy", 0xFB,    _id]);
	    array_push(_list, ["sta_abs", _v_srcb, _id]);
	    for (var _up = 0; _up < 4; _up++) {
	        var _l_uz = _pfx + "uz" + string(_up);
	        var _l_u2 = _pfx + "uc2" + string(_up);
	        var _l_u3 = _pfx + "uc3" + string(_up);
	        array_push(_list, ["lda_abs", _v_srcb, _id]);
	        for (var _uk = 0; _uk < _up * 2; _uk++) {
	            array_push(_list, ["lsr_a", 0, _id]);
	        }
	        array_push(_list, ["and_imm", 0x03,  _id]);
	        array_push(_list, ["beq",     _l_uz, _id]);
	        array_push(_list, ["tax",     0,     _id]);
	        // X holds the pair value (1/2/3) — bump that slot's counter.
	        array_push(_list, ["cpx_imm", 1,      _id]);
	        array_push(_list, ["bne",     _l_u2,  _id]);
	        array_push(_list, ["inc_abs", _v_cn1, _id]);
	        array_push(_list, ["jmp_abs", _l_uz,  _id]);
	        array_push(_list, ["label",   _l_u2        ]);
	        array_push(_list, ["cpx_imm", 2,      _id]);
	        array_push(_list, ["bne",     _l_u3,  _id]);
	        array_push(_list, ["inc_abs", _v_cn2, _id]);
	        array_push(_list, ["jmp_abs", _l_uz,  _id]);
	        array_push(_list, ["label",   _l_u3        ]);
	        array_push(_list, ["inc_abs", _v_cn3, _id]);
	        array_push(_list, ["label",   _l_uz        ]);
	    }
	    // The four unrolled pair blocks push this loop body past 200 bytes, so the
	    // back-branch to the top is outside the 6502's -128 reach. Invert and
	    // trampoline, same pattern as _emit_long_bne elsewhere in this file.
	    array_push(_list, ["iny",     0,        _id]);
	    array_push(_list, ["cpy_imm", 8,        _id]);
	    array_push(_list, ["beq",     _pfx + "ubyx", _id]);
	    array_push(_list, ["jmp_abs", _lbl_uby,      _id]);
	    array_push(_list, ["label",   _pfx + "ubyx"      ]);

	    // ── Drop the sparsest slot when all three are painted ──
	    // Only fires when every slot has a non-zero count; a cell already using two
	    // or fewer colours has a free slot and needs no sacrifice. The winner is
	    // the smallest count, ties going to the lowest slot, which falls out of
	    // testing 1 against 2 with BCC and then the survivor against 3 the same way.
	    var _l_dnone = _pfx + "dnone";
	    var _l_d23   = _pfx + "d23";
	    var _l_dc3   = _pfx + "dc3";
	    var _l_dset  = _pfx + "dset";
	    var _l_dst2  = _pfx + "dst2";
	    var _l_dst3  = _pfx + "dst3";

	    array_push(_list, ["lda_abs", _v_cn1,   _id]);
	    array_push(_list, ["beq",     _l_dnone, _id]);
	    array_push(_list, ["lda_abs", _v_cn2,   _id]);
	    array_push(_list, ["beq",     _l_dnone, _id]);
	    array_push(_list, ["lda_abs", _v_cn3,   _id]);
	    array_push(_list, ["beq",     _l_dnone, _id]);

	    // X = slot currently winning, A = its count. Start with slot 1.
	    array_push(_list, ["ldx_imm", 1,      _id]);
	    array_push(_list, ["lda_abs", _v_cn1, _id]);
	    array_push(_list, ["cmp_abs", _v_cn2, _id]);
	    array_push(_list, ["bcc",     _l_d23, _id]);   // cn1 < cn2, slot 1 holds
	    array_push(_list, ["beq",     _l_d23, _id]);   // equal, lowest slot wins
	    array_push(_list, ["ldx_imm", 2,      _id]);
	    array_push(_list, ["lda_abs", _v_cn2, _id]);
	    array_push(_list, ["label",   _l_d23       ]);
	    array_push(_list, ["cmp_abs", _v_cn3, _id]);
	    array_push(_list, ["bcc",     _l_dset, _id]);
	    array_push(_list, ["beq",     _l_dset, _id]);
	    array_push(_list, ["ldx_imm", 3,      _id]);
	    array_push(_list, ["label",   _l_dset      ]);

	    // Zero the loser's count so USED (built from the counts below) excludes
	    // it, freeing its palette slot for a dest colour to claim. The pixels
	    // themselves are untouched — the merge loop still paints them from the
	    // source byte; only the palette-slot bookkeeping treats the slot as free.
	    array_push(_list, ["cpx_imm", 1,      _id]);
	    array_push(_list, ["bne",     _l_dst2, _id]);
	    array_push(_list, ["lda_imm", 0,      _id]);
	    array_push(_list, ["sta_abs", _v_cn1, _id]);
	    array_push(_list, ["jmp_abs", _l_dnone, _id]);
	    array_push(_list, ["label",   _l_dst2      ]);
	    array_push(_list, ["cpx_imm", 2,      _id]);
	    array_push(_list, ["bne",     _l_dst3, _id]);
	    array_push(_list, ["lda_imm", 0,      _id]);
	    array_push(_list, ["sta_abs", _v_cn2, _id]);
	    array_push(_list, ["jmp_abs", _l_dnone, _id]);
	    array_push(_list, ["label",   _l_dst3      ]);
	    array_push(_list, ["lda_imm", 0,      _id]);
	    array_push(_list, ["sta_abs", _v_cn3, _id]);

	    array_push(_list, ["label",   _l_dnone     ]);

	    // ── USED from the surviving counts ──
	    // A slot is used when it still paints pixels. Derived from the counters
	    // rather than re-walking the bitmap, so the dropped slot is excluded for
	    // free and its palette entry is available to be claimed.
	    var _l_us2 = _pfx + "us2";
	    var _l_us3 = _pfx + "us3";
	    array_push(_list, ["lda_imm", 0,      _id]);
	    array_push(_list, ["sta_abs", _v_used, _id]);
	    array_push(_list, ["lda_abs", _v_cn1, _id]);
	    array_push(_list, ["beq",     _l_us2, _id]);
	    array_push(_list, ["lda_abs", _v_used, _id]);
	    array_push(_list, ["ora_imm", 0x02,   _id]);
	    array_push(_list, ["sta_abs", _v_used, _id]);
	    array_push(_list, ["label",   _l_us2       ]);
	    array_push(_list, ["lda_abs", _v_cn2, _id]);
	    array_push(_list, ["beq",     _l_us3, _id]);
	    array_push(_list, ["lda_abs", _v_used, _id]);
	    array_push(_list, ["ora_imm", 0x04,   _id]);
	    array_push(_list, ["sta_abs", _v_used, _id]);
	    array_push(_list, ["label",   _l_us3       ]);
	    array_push(_list, ["lda_abs", _v_cn3, _id]);
	    array_push(_list, ["beq",     _pfx + "usdn", _id]);
	    array_push(_list, ["lda_abs", _v_used, _id]);
	    array_push(_list, ["ora_imm", 0x08,   _id]);
	    array_push(_list, ["sta_abs", _v_used, _id]);
	    array_push(_list, ["label",   _pfx + "usdn"  ]);

	    // ── Substitution table ──
	    // For each dest slot: group its colour, then scan the source slots in
	    // order 1, 2, 3 and take the first whose group matches. Falls through to
	    // identity when nothing matches.
	    var _emit_sub = function(_list, _id, _pfx, _slot,
	                             _v_dpl, _v_dph, _v_dcl, _v_dch,
	                             _v_s1, _v_s2, _v_s3, _v_grp, _v_out,
	                             _v_used, _v_ns1, _v_ns2, _v_ns3, _v_dcol) {
	        var _l_t2 = _pfx + "sb" + string(_slot) + "t2";
	        var _l_t3 = _pfx + "sb" + string(_slot) + "t3";
	        var _l_dn = _pfx + "sb" + string(_slot) + "dn";

	        array_push(_list, ["ldy_imm", 0, _id]);
	        if (_slot == 3) {
	            // Dest %11 comes from colour RAM.
	            array_push(_list, ["lda_abs", _v_dcl, _id]);
	            array_push(_list, ["sta_zp",  0xFB,   _id]);
	            array_push(_list, ["lda_abs", _v_dch, _id]);
	            array_push(_list, ["sta_zp",  0xFC,   _id]);
	            array_push(_list, ["lda_izy", 0xFB,   _id]);
	            array_push(_list, ["and_imm", 0x0F,   _id]);
	        } else {
	            // Dest %01 and %10 come from the screen byte's two nibbles.
	            array_push(_list, ["lda_abs", _v_dpl, _id]);
	            array_push(_list, ["sta_zp",  0xFB,   _id]);
	            array_push(_list, ["lda_abs", _v_dph, _id]);
	            array_push(_list, ["sta_zp",  0xFC,   _id]);
	            array_push(_list, ["lda_izy", 0xFB,   _id]);
	            if (_slot == 1) {
	                array_push(_list, ["lsr_a", 0, _id]);
	                array_push(_list, ["lsr_a", 0, _id]);
	                array_push(_list, ["lsr_a", 0, _id]);
	                array_push(_list, ["lsr_a", 0, _id]);
	            } else {
	                array_push(_list, ["and_imm", 0x0F, _id]);
	            }
	        }
	        array_push(_list, ["sta_abs", _v_dcol,   _id]);   // keep the raw colour
	        array_push(_list, ["tax",     0,         _id]);
	        array_push(_list, ["lda_abx", "MBBTONE", _id]);
	        array_push(_list, ["sta_abs", _v_grp,    _id]);

	        // ── Try to claim a free source slot first ──
	        // A slot the source never paints can be overwritten with this dest
	        // colour outright, so the colour survives instead of being approximated
	        // by tone. Slots are tried 1, 2, 3 and marked used on claim so two dest
	        // colours cannot land in the same one. Only when all three are occupied
	        // does the tone match below run.
	        var _l_c2 = _pfx + "cl" + string(_slot) + "c2";
	        var _l_c3 = _pfx + "cl" + string(_slot) + "c3";
	        var _l_ct = _pfx + "cl" + string(_slot) + "ct";   // no free slot -> tone

	        array_push(_list, ["lda_abs", _v_used, _id]);
	        array_push(_list, ["and_imm", 0x02,    _id]);
	        array_push(_list, ["bne",     _l_c2,   _id]);
	        array_push(_list, ["lda_abs", _v_used, _id]);
	        array_push(_list, ["ora_imm", 0x02,    _id]);
	        array_push(_list, ["sta_abs", _v_used, _id]);
	        array_push(_list, ["lda_abs", _v_dcol, _id]);
	        array_push(_list, ["sta_abs", _v_ns1,  _id]);
	        array_push(_list, ["lda_imm", 1,       _id]);
	        array_push(_list, ["jmp_abs", _l_dn,   _id]);

	        array_push(_list, ["label",   _l_c2         ]);
	        array_push(_list, ["lda_abs", _v_used, _id]);
	        array_push(_list, ["and_imm", 0x04,    _id]);
	        array_push(_list, ["bne",     _l_c3,   _id]);
	        array_push(_list, ["lda_abs", _v_used, _id]);
	        array_push(_list, ["ora_imm", 0x04,    _id]);
	        array_push(_list, ["sta_abs", _v_used, _id]);
	        array_push(_list, ["lda_abs", _v_dcol, _id]);
	        array_push(_list, ["sta_abs", _v_ns2,  _id]);
	        array_push(_list, ["lda_imm", 2,       _id]);
	        array_push(_list, ["jmp_abs", _l_dn,   _id]);

	        array_push(_list, ["label",   _l_c3         ]);
	        array_push(_list, ["lda_abs", _v_used, _id]);
	        array_push(_list, ["and_imm", 0x08,    _id]);
	        array_push(_list, ["bne",     _l_ct,   _id]);
	        array_push(_list, ["lda_abs", _v_used, _id]);
	        array_push(_list, ["ora_imm", 0x08,    _id]);
	        array_push(_list, ["sta_abs", _v_used, _id]);
	        array_push(_list, ["lda_abs", _v_dcol, _id]);
	        array_push(_list, ["sta_abs", _v_ns3,  _id]);
	        array_push(_list, ["lda_imm", 3,       _id]);
	        array_push(_list, ["jmp_abs", _l_dn,   _id]);

	        array_push(_list, ["label",   _l_ct         ]);
	        array_push(_list, ["lda_abs", _v_s1,     _id]);
	        array_push(_list, ["tax",     0,         _id]);
	        array_push(_list, ["lda_abx", "MBBTONE", _id]);
	        array_push(_list, ["cmp_abs", _v_grp,    _id]);
	        array_push(_list, ["bne",     _l_t2,     _id]);
	        array_push(_list, ["lda_imm", 1,         _id]);
	        array_push(_list, ["jmp_abs", _l_dn,     _id]);

	        array_push(_list, ["label",   _l_t2           ]);
	        array_push(_list, ["lda_abs", _v_s2,     _id]);
	        array_push(_list, ["tax",     0,         _id]);
	        array_push(_list, ["lda_abx", "MBBTONE", _id]);
	        array_push(_list, ["cmp_abs", _v_grp,    _id]);
	        array_push(_list, ["bne",     _l_t3,     _id]);
	        array_push(_list, ["lda_imm", 2,         _id]);
	        array_push(_list, ["jmp_abs", _l_dn,     _id]);

	        // Slot 3, then identity. Both land on _l_dn with the right value in A:
	        // a match loads 3, a miss falls through with the slot's own index.
	        array_push(_list, ["label",   _l_t3           ]);
	        array_push(_list, ["lda_abs", _v_s3,     _id]);
	        array_push(_list, ["tax",     0,         _id]);
	        array_push(_list, ["lda_abx", "MBBTONE", _id]);
	        array_push(_list, ["cmp_abs", _v_grp,    _id]);
	        array_push(_list, ["beq",     _pfx + "sb" + string(_slot) + "h3", _id]);
	        array_push(_list, ["lda_imm", _slot,     _id]);   // identity
	        array_push(_list, ["jmp_abs", _l_dn,     _id]);
	        array_push(_list, ["label",   _pfx + "sb" + string(_slot) + "h3"  ]);
	        array_push(_list, ["lda_imm", 3,         _id]);

	        array_push(_list, ["label",   _l_dn           ]);
	        array_push(_list, ["sta_abs", _v_out,    _id]);
	    };
	    _emit_sub(_list, _id, _pfx, 1, _v_dpl, _v_dph, _v_dcl, _v_dch, _v_s1, _v_s2, _v_s3, _v_grp, _v_sub1, _v_used, _v_ns1, _v_ns2, _v_ns3, _v_dcol);
	    _emit_sub(_list, _id, _pfx, 2, _v_dpl, _v_dph, _v_dcl, _v_dch, _v_s1, _v_s2, _v_s3, _v_grp, _v_sub2, _v_used, _v_ns1, _v_ns2, _v_ns3, _v_dcol);
	    _emit_sub(_list, _id, _pfx, 3, _v_dpl, _v_dph, _v_dcl, _v_dch, _v_s1, _v_s2, _v_s3, _v_grp, _v_sub3, _v_used, _v_ns1, _v_ns2, _v_ns3, _v_dcol);

	    // ── Merge this cell's eight bytes ──
	    // Per pixel row: read the source and dest bytes, then walk the four pairs
	    // from the low end up. Source pair non-zero passes straight through; source
	    // pair %00 is a hole, so the dest's pair is substituted and dropped in.
	    //
	    // The accumulator is built low pair first, shifting right as it goes, then
	    // corrected at the end — cheaper than shifting each pair into position.
	    // ── All-background source cell: touch nothing ──
	    // Every pair is a hole, so the merge would read each dest pair and write it
	    // straight back — identity in principle, but any error in the substitution
	    // table corrupts a cell the source had no business modifying. The source
	    // contributes no pixels and no palette here, so the correct behaviour is to
	    // leave the dest's bitmap, screen and colour bytes exactly as they are and
	    // advance to the next cell.
	    var _lbl_skipcell = _pfx + "mskcell";
	    array_push(_list, ["lda_abs", _v_used,       _id]);
	    array_push(_list, ["bne",     _pfx + "mgo",  _id]);
	    array_push(_list, ["jmp_abs", _lbl_skipcell, _id]);
	    array_push(_list, ["label",   _pfx + "mgo"       ]);

	    var _lbl_byte = _pfx + "mbyte";
	    var _lbl_pair = _pfx + "mpair";
	    array_push(_list, ["lda_imm", 0,      _id]);
	    array_push(_list, ["sta_abs", _v_byi, _id]);
	    array_push(_list, ["label",   _lbl_byte    ]);

	    array_push(_list, ["lda_abs", _v_byi, _id]);
	    array_push(_list, ["tay",     0,      _id]);
	    _emit_toptr(_list, _id, _v_sbl, _v_sbh);
	    array_push(_list, ["lda_izy", 0xFB,   _id]);
	    array_push(_list, ["sta_abs", _v_srcb, _id]);
	    _emit_toptr(_list, _id, _v_dbl, _v_dbh);
	    array_push(_list, ["lda_izy", 0xFB,   _id]);
	    array_push(_list, ["sta_abs", _v_dstb, _id]);

	    array_push(_list, ["lda_imm", 0,      _id]);
	    array_push(_list, ["sta_abs", _v_tmp, _id]);

	    // Four pairs, unrolled. Pair 0 is bits 0-1 of the byte and ends up as bits
	    // 0-1 of the result, so the accumulator is assembled by ORing each pair in
	    // at its own shift.
	    for (var _p = 0; _p < 4; _p++) {
	        var _sh   = _p * 2;
	        var _l_hl = _pfx + "ph" + string(_p);   // source pair is a hole
	        var _l_nx = _pfx + "pn" + string(_p);   // pair resolved, move on

	        // Extract the source pair.
	        array_push(_list, ["lda_abs", _v_srcb, _id]);
	        for (var _k = 0; _k < _sh; _k++) {
	            array_push(_list, ["lsr_a", 0, _id]);
	        }
	        array_push(_list, ["and_imm", 0x03,  _id]);
	        array_push(_list, ["beq",     _l_hl, _id]);   // %00 -> hole (only case)

	        // Opaque: the source pair itself is the answer.
	        for (var _k2 = 0; _k2 < _sh; _k2++) {
	            array_push(_list, ["asl_a", 0, _id]);
	        }
	        array_push(_list, ["jmp_abs", _l_nx, _id]);

	        // Hole: take the dest pair, substitute it, shift into place.
	        array_push(_list, ["label",   _l_hl           ]);
	        array_push(_list, ["lda_abs", _v_dstb, _id]);
	        for (var _k3 = 0; _k3 < _sh; _k3++) {
	            array_push(_list, ["lsr_a", 0, _id]);
	        }
	        array_push(_list, ["and_imm", 0x03,  _id]);
	        // A is now 0..3. Zero means the dest was background too, so the merged
	        // pair is background — no substitution, nothing to OR in.
	        var _l_bg = _pfx + "pb" + string(_p);
	        array_push(_list, ["beq", _l_bg, _id]);
	        // Substitute: 1 -> SUB1, 2 -> SUB2, 3 -> SUB3. The table is three
	        // consecutive bytes, so index it with (pair - 1).
	        array_push(_list, ["tax",     0,        _id]);
	        array_push(_list, ["lda_abx", _v_sub0,  _id]);   // SUB0,x -> SUB1..SUB3
	        for (var _k4 = 0; _k4 < _sh; _k4++) {
	            array_push(_list, ["asl_a", 0, _id]);
	        }
	        array_push(_list, ["jmp_abs", _l_nx, _id]);
	        array_push(_list, ["label",   _l_bg      ]);
	        array_push(_list, ["lda_imm", 0, _id]);

	        // OR the resolved pair into the accumulator.
	        array_push(_list, ["label",   _l_nx           ]);
	        array_push(_list, ["ora_abs", _v_tmp,  _id]);
	        array_push(_list, ["sta_abs", _v_tmp,  _id]);
	    }

	    // Store the merged byte.
	    array_push(_list, ["lda_abs", _v_byi, _id]);
	    array_push(_list, ["tay",     0,      _id]);
	    _emit_toptr(_list, _id, _v_dbl, _v_dbh);
	    array_push(_list, ["lda_abs", _v_tmp, _id]);
	    array_push(_list, ["sta_izy", 0xFB,   _id]);

	    array_push(_list, ["inc_abs", _v_byi, _id]);
	    array_push(_list, ["lda_abs", _v_byi, _id]);
	    array_push(_list, ["cmp_imm", 8,      _id]);
	    _emit_long_bne(_list, _id, _lbl_byte, _pfx + "mbyx");

	    // ── Write the source cell's palette to the dest cell ──
	    // The source's palette wins outright; the dest survivors have already been
	    // remapped to fit it.
	    // ── All-background source cell: leave the dest's palette alone ──
	    // USED == 0 means the source paints no pixels in this cell at all. Every
	    // pair took the hole path, so the merged bitmap bytes are already exactly
	    // the dest's. The source has no palette worth propagating, and writing one
	    // over the dest's screen and colour nibbles repoints the dest's surviving
	    // pixels at colours that were never theirs — which is what turned the
	    // uncovered corner cells black. Skip the write-back entirely.
	    var _lbl_nopal = _pfx + "mnopal";
	    array_push(_list, ["lda_abs", _v_used,  _id]);
	    array_push(_list, ["beq",     _lbl_nopal, _id]);

	    // Screen byte: high nibble = slot 1, low nibble = slot 2. Built from
	    // NEWS1/NEWS2 rather than copied from the source, because a claimed slot
	    // now carries a destination colour.
	    array_push(_list, ["ldy_imm", 0, _id]);
	    array_push(_list, ["lda_abs", _v_ns1,  _id]);
	    array_push(_list, ["asl_a",   0,       _id]);
	    array_push(_list, ["asl_a",   0,       _id]);
	    array_push(_list, ["asl_a",   0,       _id]);
	    array_push(_list, ["asl_a",   0,       _id]);
	    array_push(_list, ["ora_abs", _v_ns2,  _id]);
	    array_push(_list, ["pha",     0,       _id]);
	    _emit_toptr(_list, _id, _v_dpl, _v_dph);
	    array_push(_list, ["pla",     0,    _id]);
	    array_push(_list, ["sta_izy", 0xFB, _id]);

	    // Colour RAM: slot 3 only, low nibble.
	    array_push(_list, ["lda_abs", _v_ns3, _id]);
	    array_push(_list, ["and_imm", 0x0F,   _id]);
	    array_push(_list, ["pha",     0,      _id]);
	    _emit_toptr(_list, _id, _v_dcl, _v_dch);
	    array_push(_list, ["pla",     0,    _id]);
	    array_push(_list, ["sta_izy", 0xFB, _id]);

	    array_push(_list, ["label", _lbl_nopal]);

	    array_push(_list, ["label", _lbl_skipcell]);

	    // ── Next cell: bitmap ptrs += 8, palette ptrs += 1 ──
	    _emit_add16(_list, _id, _v_sbl, _v_sbh, 8);
	    _emit_add16(_list, _id, _v_dbl, _v_dbh, 8);
	    _emit_add16(_list, _id, _v_spl, _v_sph, 1);
	    _emit_add16(_list, _id, _v_scl, _v_sch, 1);
	    _emit_add16(_list, _id, _v_dpl, _v_dph, 1);
	    _emit_add16(_list, _id, _v_dcl, _v_dch, 1);

	    array_push(_list, ["dec_abs", _v_cell,   _id]);
	    array_push(_list, ["lda_abs", _v_cell,   _id]);
	    _emit_long_bne(_list, _id, _lbl_cell, _pfx + "mcelx");

	    // ── Next char row: bitmap ptrs += 320, palette ptrs += 40 ──
	    _emit_add16(_list, _id, _v_rsbl, _v_rsbh, 320);
	    _emit_add16(_list, _id, _v_rdbl, _v_rdbh, 320);
	    _emit_add16(_list, _id, _v_rspl, _v_rsph, 40);
	    _emit_add16(_list, _id, _v_rscl, _v_rsch, 40);
	    _emit_add16(_list, _id, _v_rdpl, _v_rdph, 40);
	    _emit_add16(_list, _id, _v_rdcl, _v_rdch, 40);

	    array_push(_list, ["dec_abs", _v_row,   _id]);
	    array_push(_list, ["lda_abs", _v_row,   _id]);
	    _emit_long_bne(_list, _id, _lbl_row, _pfx + "mrowx");
	}
