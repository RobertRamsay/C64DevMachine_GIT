function scr_parse_asm_byte_count(_text) {
    var _instrs = scr_parse_asm_text(_text);
    var _bytes = 0, _cycles = 0;
    for (var _i = 0; _i < array_length(_instrs); _i++) {
        var _m = string_lower(_instrs[_i][0]);

        // Skip directives and inline data (these live at their own .pc
        // addresses and are excluded from node sizing in the compile chain)
        if (_m == "byte" || _m == "pc" || _m == "org" ||
            _m == "label" || _m == "const" || _m == "comment" || _m == "") continue;
			
			// Handle Repeat Macro
        if (_m == "repeat") {
            var _count = real(_instrs[_i][1]); // Get the number after repeat
            var _inner_text = _instrs[_i][2]; // Assuming your parser puts the {block} here
            
            var _inner_stats = scr_parse_asm_byte_count(_inner_text);
            _bytes  += (_inner_stats[0] * _count);
            _cycles += (_inner_stats[1] * _count);
            continue; 
        }

        // Mirror the mnemonic remapping from scr_c64_do_update_addresses
        _m = string_replace_all(_m, "_abs_x",   "_abx");
        _m = string_replace_all(_m, "_abs_y",   "_aby");
        _m = string_replace_all(_m, "_zp_x",    "_zpx");
        _m = string_replace_all(_m, "_zp_y",    "_zpy");
        _m = string_replace_all(_m, "_imm_rep", "_imm");
        if (_m == "jmp")                               _m = "jmp_abs";
        if (_m == "lda_lab_lo" || _m == "lda_lab_hi") _m = "lda_imm";
        if (_m == "lda_lab")  _m = "lda_abs";
        if (_m == "sta_lab")  _m = "sta_abs";
        if (_m == "inc_lab")  _m = "inc_abs";
        if (_m == "dec_lab")  _m = "dec_abs";
        if (_m == "ora_lab")  _m = "ora_abs";
        if (_m == "and_lab")  _m = "and_abs";
        if (_m == "cmp_lab")  _m = "cmp_abs";
        if (_m == "beq")      _m = "bne";
        if (_m == "bcc")      _m = "bcs";
        if (_m == "bpl")      _m = "bmi";
        if (_m == "bvc")      _m = "bvs";

        var _sz = obj_opCodeManager.get_size(_m);
       // if (_sz == 0) show_debug_message("PARSE_ASM_BYTE_COUNT ZERO: " + _m);
        _bytes  += _sz;
        _cycles += obj_opCodeManager.get_cycles(_m);
    }
    return [_bytes, _cycles];
}