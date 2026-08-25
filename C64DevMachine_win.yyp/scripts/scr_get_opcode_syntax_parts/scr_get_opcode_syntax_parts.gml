/// @desc scr_get_opcode_syntax_parts(mnemonic)
function scr_get_opcode_syntax_parts(_mn) { // _LDA_imm
    var _m = string_lower(_mn); // _lda_imm
    if (string_pos("_rep", _m)) _m = string_replace(_m, "_rep", ""); 
    
    // Support 3-char mnemonics (LDA) and 4-char Illegals (LAX)
    var _split = string_pos("_", _m);
    var _base = (_split > 0) ? string_copy(_m, 1, _split - 1) : _m;
    _base = string_upper(_base);

    // Label lo/hi byte immediates - must be tested before the generic checks below
    if (string_pos("_lab_lo", _m)) return [_base + " #<", ""];
    if (string_pos("_lab_hi", _m)) return [_base + " #>", ""];

    // Immediate
    if (string_pos("_imm", _m)) return [_base + " #", ""];
    
    // Indirects
    if (string_pos("_izx", _m)) return [_base + " (", ",X)"];
    if (string_pos("_izy", _m)) return [_base + " (", "),Y"];
    if (string_pos("_ind", _m)) return [_base + " (", ")"];
    
    // Accumulator
    if (string_pos("_a", _m) && string_length(_m) <= 5) return [_base + " A", ""];
    
    // Indexed (Absolute/ZP) - Result: "INC $0000,X"
    if (string_pos("_x", _m) || string_pos("_zpx", _m) || string_pos("_abx", _m)) return [_base + " ", ",X"];
    if (string_pos("_y", _m) || string_pos("_zpy", _m) || string_pos("_aby", _m)) return [_base + " ", ",Y"];

    // Default
    return [_base + " ", ""];
}