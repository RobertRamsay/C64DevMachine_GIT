function scr_format_asm(_mnem, _val) {
    var _m = string_lower(_mnem);
    var _h = "";
    
// Format the operand value as hex
    if (is_real(_val)) {
        _h = string_upper(decimal_to_hex(_val));
        while (string_length(_h) < 2) _h = "0" + _h;
    }

    // 1-byte ops (implied/accumulator) - no operand
    var _implied = ["brk","nop","tax","tay","tsx","txa","tya","txs",
                    "inx","iny","dex","dey","clc","sec","sei","cli",
                    "clv","cld","sed","pha","pla","php","plp","rts",
                    "rti","asl_a","rol_a","ror_a","lsr_a"];
    for (var i = 0; i < array_length(_implied); i++) {
        if (_m == _implied[i]) return string_upper(string_copy(_m, 1, 3));
    }

    var _op = string_upper(string_copy(_m, 1, 3));

// Immediate
    if (string_pos("_imm", _m) > 0) {
        if (!is_real(_val) && string(_val) != "" && string(_val) != "0") return _op + " #" + string(_val);
        while (string_length(_h) < 2) _h = "0" + _h;
        return _op + " #$" + _h;
    }
    // Zero page
    if (string_pos("_zp", _m) > 0 && string_pos("_zpx", _m) == 0 && string_pos("_zpy", _m) == 0) {
        return _op + " $" + _h;
    }
    // Zero page X
    if (string_pos("_zpx", _m) > 0 || string_pos("_zp_x", _m) > 0) {
        return _op + " $" + _h + ",X";
    }
    // Zero page Y
    if (string_pos("_zpy", _m) > 0 || string_pos("_zp_y", _m) > 0) {
        return _op + " $" + _h + ",Y";
    }
    // Absolute
    if (string_pos("_abs", _m) > 0 && string_pos("_abx", _m) == 0 && 
        string_pos("_aby", _m) == 0 && string_pos("_abs_x", _m) == 0 && 
        string_pos("_abs_y", _m) == 0) {
        while (string_length(_h) < 4) _h = "0" + _h;
        return _op + " $" + _h;
    }
    // Absolute X
    if (string_pos("_abx", _m) > 0 || string_pos("_abs_x", _m) > 0) {
        while (string_length(_h) < 4) _h = "0" + _h;
        return _op + " $" + _h + ",X";
    }
    // Absolute Y
    if (string_pos("_aby", _m) > 0 || string_pos("_abs_y", _m) > 0) {
        while (string_length(_h) < 4) _h = "0" + _h;
        return _op + " $" + _h + ",Y";
    }
    // Indirect X (izx)
    if (string_pos("_izx", _m) > 0 || string_pos("_ind_x", _m) > 0) {
        return _op + " ($" + _h + ",X)";
    }
    // Indirect Y (izy)
    if (string_pos("_izy", _m) > 0 || string_pos("_ind_y", _m) > 0) {
        return _op + " ($" + _h + "),Y";
    }
    // Indirect (jmp only)
    if (string_pos("_ind", _m) > 0) {
        while (string_length(_h) < 4) _h = "0" + _h;
        return _op + " ($" + _h + ")";
    }
    // Branches and jumps - show label or address
    if (_m == "bne" || _m == "beq" || _m == "bcc" || _m == "bcs" ||
        _m == "bpl" || _m == "bmi" || _m == "bvc" || _m == "bvs") {
        if (is_real(_val)) {
            while (string_length(_h) < 4) _h = "0" + _h;
            return _op + " $" + _h;
        }
        return _op + " " + string(_val);
    }
    if (_m == "jmp" || _m == "jmp_abs" || _m == "jsr") {
        if (is_real(_val)) {
            while (string_length(_h) < 4) _h = "0" + _h;
            return _op + " $" + _h;
        }
        return _op + " " + string(_val);
    }

    // Fallback
    return _op + " $" + _h;
}