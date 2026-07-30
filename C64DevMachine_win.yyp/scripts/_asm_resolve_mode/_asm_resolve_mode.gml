/// @function _asm_resolve_mode(_mnem, _op)
function _asm_resolve_mode(_mnem, _op) {
    // Strip comments and all whitespace
    var _semicolon = string_pos(";", _op);
    if (_semicolon > 0) _op = string_copy(_op, 1, _semicolon - 1);
    _op = string_replace_all(_op, " ", ""); 
    
    var _ml = string_lower(_mnem);
    var _up_op = string_upper(_op);

    // ─── Implied / Accumulator ───
    if (_up_op == "" || _up_op == "A") {
        if (_ml == "asl" || _ml == "lsr" || _ml == "rol" || _ml == "ror") {
            return [_ml + "_a", 0];
        }
        return [_ml, 0];
    }

    // ─── Immediate: #$xx / #xx / #%xxxx / #<label / #>label / #LABEL ───
    if (string_char_at(_op, 1) == "#") {
        var _v = string_delete(_op, 1, 1);
        // #<label — lo byte
        if (string_char_at(_v, 1) == "<") {
            var _lname = string_delete(_v, 1, 1);
            _lname = string_replace_all(_lname, "[", "");
            _lname = string_replace_all(_lname, "]", "");
            // Only resolve if it is a named constant — never an assembly label
            if (ds_map_exists(global.named_loc_map, string_upper(_lname))
            &&  !variable_struct_exists(global.code_block_labels, string_upper(_lname))
            &&  !variable_struct_exists(global.code_block_labels, _lname)) {
                var _resolved = ds_map_find_value(global.named_loc_map, string_upper(_lname));
                return [_ml + "_imm", _resolved & 0xFF];
            }
            var _suffix = "lda_lab_lo";
            if (_ml == "ldx") _suffix = "ldx_lab_lo";
            else if (_ml == "ldy") _suffix = "ldy_lab_lo";
            return [_suffix, _lname, _lname];
        }
        // #>label — hi byte
        if (string_char_at(_v, 1) == ">") {
            var _lname = string_delete(_v, 1, 1);
            _lname = string_replace_all(_lname, "[", "");
            _lname = string_replace_all(_lname, "]", "");
            // Only resolve if it is a named constant — never an assembly label
            if (ds_map_exists(global.named_loc_map, string_upper(_lname))
            &&  !variable_struct_exists(global.code_block_labels, string_upper(_lname))
            &&  !variable_struct_exists(global.code_block_labels, _lname)) {
                var _resolved = ds_map_find_value(global.named_loc_map, string_upper(_lname));
                return [_ml + "_imm", (_resolved >> 8) & 0xFF];
            }
            var _suffix = "lda_lab_hi";
            if (_ml == "ldx") _suffix = "ldx_lab_hi";
            else if (_ml == "ldy") _suffix = "ldy_lab_hi";
            return [_suffix, _lname, _lname];
        }
        // If it's not a number, treat it as an immediate label
        if (!_asm_is_dec(_v) && string_char_at(_v, 1) != "$" && string_char_at(_v, 1) != "%") {
            return [_ml + "_imm", _v, _v];
        }
        return [_ml + "_imm", _asm_val(_v) & 0xFF];
    }
    if (string_length(_op) >= 2 && string_copy(_op, 1, 2) == "$#") {
        return [_ml + "_imm", _asm_val("$" + string_delete(_op, 1, 2)) & 0xFF];
    }
    if (string_char_at(_op, 1) == "%") {
        var _raw = string_delete(_op, 1, 1);
        if (string_char_at(_raw, 1) == "#") _raw = string_delete(_raw, 1, 1);
        return [_ml + "_imm", _asm_val("%" + _raw) & 0xFF];
    }

    // ─── Guard: reject any invalid indirect (16-bit addr in parens, or bad syntax) ───
    if (string_char_at(_up_op, 1) == "(") {
        var _valid_izy = (string_pos("),Y", _up_op) > 0);
        var _valid_izx = (string_pos(",X)", _up_op) > 0);
        var _valid_jmp = (_ml == "jmp" && string_char_at(_up_op, string_length(_up_op)) == ")");
        if (!_valid_izy && !_valid_izx && !_valid_jmp) return undefined;
        if (_valid_izy || _valid_izx) {
            var _inner_end = string_pos(_valid_izy ? ")" : ",", _up_op);
            if (_inner_end > 2) {
                var _inner_check = string_copy(_op, 2, _inner_end - 2);
                if (string_char_at(_inner_check, 1) == "$" && string_length(_inner_check) > 3) return undefined;
            } else {
                return undefined;
            }
        }
    }

    // ─── Indirect Indexed Y: ($xx),Y ───
    if (string_char_at(_up_op, 1) == "(" && string_pos("),Y", _up_op) > 0) {
        var _inner = string_copy(_op, 2, string_pos(")", _up_op) - 2);
        if (!_asm_is_dec(_inner) && string_char_at(_inner, 1) != "$" && string_char_at(_inner, 1) != "%") {
            return [_ml + "_izy", _inner, _inner];
        }
        return [_ml + "_izy", _asm_val(_inner) & 0xFF];
    }

    // ─── Indexed Indirect X: ($xx,X) ───
    if (string_char_at(_up_op, 1) == "(" && string_pos(",X)", _up_op) > 0) {
        var _inner = string_copy(_op, 2, string_pos(",", _up_op) - 2);
        if (!_asm_is_dec(_inner) && string_char_at(_inner, 1) != "$" && string_char_at(_inner, 1) != "%") {
            return [_ml + "_izx", _inner, _inner];
        }
        return [_ml + "_izx", _asm_val(_inner) & 0xFF];
    }

    // ─── Indexed: addr,X or addr,Y ───
    var _comma = string_pos(",", _up_op);
    if (_comma > 0 && string_char_at(_up_op, 1) != "(") {
        var _addr_part = string_copy(_op, 1, _comma - 1);
        var _idx_part  = string_copy(_up_op, _comma + 1, string_length(_up_op) - _comma);
        var _is_label  = (!_asm_is_dec(_addr_part) && string_char_at(_addr_part, 1) != "$" && string_char_at(_addr_part, 1) != "%");
        if (_idx_part == "X") {
            if (_is_label) return [_ml + "_abs_x", _addr_part, _addr_part];
            var _v = _asm_val(_addr_part);
            var _is_zp = (_v <= 0xFF);
            return [_ml + (_is_zp ? "_zpx" : "_abs_x"), _v];
        }
        if (_idx_part == "Y") {
            if (_is_label) return [_ml + "_abs_y", _addr_part, _addr_part];
            var _v = _asm_val(_addr_part);
            var _is_zp = (_v <= 0xFF && (_ml == "ldx" || _ml == "stx"));
            return [_ml + (_is_zp ? "_zpy" : "_abs_y"), _v];
        }
    }

    // ─── Branches ───
    var _branches = ["bne","beq","bmi","bpl","bcc","bcs","bvc","bvs"];
    for (var _bi = 0; _bi < 8; _bi++) {
        if (_ml == _branches[_bi]) {
            if (string_char_at(_op, 1) == "$" || _asm_is_dec(_op) || string_char_at(_op, 1) == "%") {
                return [_ml, _asm_val(_op)];
            }
            var _op_nodot = (string_char_at(_op, 1) == ".") ? string_delete(_op, 1, 1) : _op;
            return [_ml, _op_nodot, _op_nodot];
        }
    }

    // ─── JMP / JSR ───
    if (_ml == "jmp" || _ml == "jsr") {
        if (_ml == "jmp" && string_char_at(_op, 1) == "(" && string_char_at(_op, string_length(_op)) == ")") {
            var _inner = string_copy(_op, 2, string_length(_op) - 2);
            if (!_asm_is_dec(_inner) && string_char_at(_inner, 1) != "$" && string_char_at(_inner, 1) != "%") {
                return ["jmp_ind", _inner, _inner];
            }
            return ["jmp_ind", _asm_val(_inner)];
        }
        if (string_char_at(_op, 1) == "$" || _asm_is_dec(_op) || string_char_at(_op, 1) == "%") {
            return [(_ml == "jmp" ? "jmp_abs" : _ml), _asm_val(_op)];
        }
        var _op_nodot = (string_char_at(_op, 1) == ".") ? string_delete(_op, 1, 1) : _op;
        return [(_ml == "jmp" ? "jmp_abs" : _ml), _op_nodot, _op_nodot];
    }

    // ─── Standard Labels (Absolute) ───
    if (!_asm_is_dec(_op) && string_char_at(_op, 1) != "$" && string_char_at(_op, 1) != "%") {
        return [_ml + "_abs", _op, _op];
    }

    // ─── Zero page vs Absolute Fallback ───
    var _v = _asm_val(_op);
    var _hex_len = string_length(string_replace_all(_op, "$", ""));
    if (_v <= 0xFF && _hex_len <= 2) return [_ml + "_zp", _v];
    return [_ml + "_abs", _v];
}