/// @function scr_parse_asm_text(_text)
function scr_parse_asm_text(_text) {
    var _result = [];
    if (_text == "" || _text == undefined) return _result;

    // ── Pre-pass A: desugar scope { } blocks (BEFORE repeat expansion) ──
    _text = scr_desugar_scopes(_text);

    // ── Pre-pass: expand repeat N { ... } blocks ──────────────────
    var _expanded = "";
    var _src = _text;
    var _rpos = string_pos("repeat", _src);
    while (_rpos > 0) {
        _expanded += string_copy(_src, 1, _rpos - 1);
        _src = string_delete(_src, 1, _rpos - 1 + 6);
        var _after_rep = string_trim(_src);
        var _ob = string_pos("{", _after_rep);
        var _count_str = string_trim(string_copy(_after_rep, 1, _ob - 1));
        var _count = 1;
        if (_count_str != "") {
            try {
                _count = clamp(real(string_digits(_count_str)), 1, 512);
            } catch(_e) {
                _count = 1;
            }
        }
        _after_rep = string_delete(_after_rep, 1, _ob);
        var _depth = 1;
        var _bi = 1;
        while (_bi <= string_length(_after_rep) && _depth > 0) {
            var _ch = string_char_at(_after_rep, _bi);
            if (_ch == "{") _depth++;
            if (_ch == "}") _depth--;
            _bi++;
        }
        var _body = (_bi > 1) ? string_copy(_after_rep, 1, _bi - 2) : "";
        _src = string_delete(_after_rep, 1, _bi - 1);
        for (var _ri = 0; _ri < _count; _ri++) {
            _expanded += _body + "\n";
        }
        _rpos = string_pos("repeat", _src);
    }
    _expanded += _src;

    // ── Pre-pass B: desugar multi-labels (AFTER repeat expansion) ──
    _expanded = scr_desugar_multi_labels(_expanded);

    // ── Helper: evaluate a constant expression ─────────────────────
    var _eval_expr = function(_expr) {
        _expr = string_replace_all(_expr, " ", "");
        if (_expr == "") return 0;
        _expr = string_replace_all(_expr, "0x", "$");
        _expr = string_replace_all(_expr, "0b", "%");

        var _total = 0;
        var _sign  = 1;
        var _tok   = "";
        for (var _ei = 1; _ei <= string_length(_expr); _ei++) {
            var _ch = string_char_at(_expr, _ei);
            if ((_ch == "+" || _ch == "-") && _ei > 1) {
                _tok = string_trim(_tok);
                if (ds_map_exists(global.named_loc_map, string_upper(_tok))) {
                    _total += _sign * ds_map_find_value(global.named_loc_map, string_upper(_tok));
                } else if (variable_struct_exists(global.code_block_labels, _tok)
                       && !ds_map_exists(global.named_loc_map, string_upper(_tok))) {
                    _total += _sign * global.code_block_labels[$ _tok];
                } else {
                    _total += _sign * _asm_val(_tok);
                }
                _tok  = "";
                _sign = (_ch == "+") ? 1 : -1;
            } else {
                _tok += _ch;
            }
        }
        _tok = string_trim(_tok);
        if (_tok != "") {
            if (ds_map_exists(global.named_loc_map, string_upper(_tok))) {
                _total += _sign * ds_map_find_value(global.named_loc_map, string_upper(_tok));
            } else if (variable_struct_exists(global.code_block_labels, _tok)
                   && !ds_map_exists(global.named_loc_map, string_upper(_tok))) {
                _total += _sign * global.code_block_labels[$ _tok];
            } else {
                _total += _sign * _asm_val(_tok);
            }
        }
        return _total;
    };

    // ── Main parse loop ────────────────────────────────────────────
    var _lines = string_split(_expanded, "\n");
    for (var _li = 0; _li < array_length(_lines); _li++) {
        var _line = string_trim(_lines[_li]);
        if (_line == "") continue;
        if (string_char_at(_line, 1) == ";") continue;
        if (string_length(_line) >= 2 && string_copy(_line, 1, 2) == "//") continue;
        var _semi = string_pos(";", _line);
        if (_semi > 0) _line = string_trim(string_copy(_line, 1, _semi - 1));
        var _dslash = string_pos("//", _line);
        if (_dslash > 0) _line = string_trim(string_copy(_line, 1, _dslash - 1));
        if (_line == "") continue;

        var _space       = 0;
        var _mnem_raw    = "";
        var _operand_str = "";

        // --- Label ---
        var _colon = string_pos(":", _line);
        if (_colon > 1) {
            var _before = string_trim(string_copy(_line, 1, _colon - 1));
            if (string_pos(" ", _before) == 0) {
                if (string_char_at(_before, 1) == ".") _before = string_delete(_before, 1, 1);
                if (_before != "") {
                    array_push(_result, ["_line_map_", _li + 1]);
                    array_push(_result, ["label", _before]);
                    var _after = string_trim(string_delete(_line, 1, _colon));
                    if (_after == "") continue;
                    _line = _after;
                }
            }
        }

        // --- Constant assignment: name = $addr / name EQU $addr [size] ---
        var _eq_pos  = string_pos("=", _line);
        var _equ_pos = string_pos(" EQU ", string_upper(_line));
        if (_eq_pos > 1 || _equ_pos > 1) {
            var _asgn_name    = "";
            var _asgn_val_str = "";
            if (_equ_pos > 1) {
                _asgn_name    = string_trim(string_copy(_line, 1, _equ_pos - 1));
                _asgn_val_str = string_trim(string_delete(_line, 1, _equ_pos + 4));
            } else {
                _asgn_name    = string_trim(string_copy(_line, 1, _eq_pos - 1));
                _asgn_val_str = string_trim(string_delete(_line, 1, _eq_pos));
            }
            if (_asgn_name != "" && string_pos(" ", _asgn_name) == 0
            &&  string_char_at(_asgn_name, 1) != "."
            &&  string_char_at(_asgn_name, 1) != "*"
            &&  _asgn_val_str != "") {

                // --- Strip type suffix from name: .w / .b / .bcd / .bcd2 / .bcd3 ---
                var _enc      = "byte";
                var _name_up  = string_upper(_asgn_name);
                var _suf_list = [".BCD3", ".BCD2", ".BCD", ".W", ".B"];
                for (var _sfi = 0; _sfi < array_length(_suf_list); _sfi++) {
                    var _suf     = _suf_list[_sfi];
                    var _suf_len = string_length(_suf);
                    var _tstart  = string_length(_name_up) - _suf_len + 1;
                    if (_tstart > 1 && string_copy(_name_up, _tstart, _suf_len) == _suf) {
                        var _tag = string_delete(_suf, 1, 1); // drop leading "."
                        if (_tag == "W")      _enc = "word";
                        else if (_tag == "B") _enc = "byte";
                        else                  _enc = string_lower(_tag);
                        _asgn_name = string_copy(_asgn_name, 1, _tstart - 1);
                        break;
                    }
                }
                var _size_map = { byte: 1, word: 2, bcd: 3, bcd2: 2, bcd3: 3 };
                var _sz = _size_map[$ _enc];

                var _asgn_num = _eval_expr(_asgn_val_str);
                ds_map_set(global.named_loc_map, string_upper(_asgn_name), _asgn_num);

                // --- Register/refresh size+encoding meta so node macros see it too ---
                var _meta_found = false;
                for (var _mi = 0; _mi < array_length(global.named_loc_meta); _mi++) {
                    if (global.named_loc_meta[_mi].name == _asgn_name) {
                        global.named_loc_meta[_mi].size     = _sz;
                        global.named_loc_meta[_mi].encoding  = _enc;
                        global.named_loc_meta[_mi].addr      = _asgn_num;
                        _meta_found = true;
                        break;
                    }
                }
                if (!_meta_found) {
                    array_push(global.named_loc_meta, { name: _asgn_name, addr: _asgn_num, size: _sz, encoding: _enc, type: "UV", chip: "RAM" });
                }
                global.named_loc_meta_dirty = true;

                array_push(_result, ["_line_map_", _li + 1]);
                array_push(_result, ["const", _asgn_name, _asgn_num]);
                continue;
            }
        }

        // Split mnemonic + operand
        _space = string_pos(" ", _line);
        if (_space > 0) {
            _mnem_raw    = string_upper(string_trim(string_copy(_line, 1, _space - 1)));
            _operand_str = string_trim(string_delete(_line, 1, _space));
        } else {
            _mnem_raw    = string_upper(string_trim(_line));
            _operand_str = "";
        }

        // ── Directives ────────────────────────────────────────────

        // .string "text"
        if (_mnem_raw == ".STRING") {
            var _str_entry = ["byte"];
            var _qs = string_pos("\"", _operand_str);
            var _qe = string_pos_ext("\"", _operand_str, _qs + 1);
            var _raw_str = (_qs > 0 && _qe > _qs)
                         ? string_copy(_operand_str, _qs + 1, _qe - _qs - 1)
                         : _operand_str;
            for (var _si = 1; _si <= string_length(_raw_str); _si++) {
                var _b = string_ord_at(_raw_str, _si);
                if      (_b >= 65  && _b <= 90)  _b -= 64;
                else if (_b >= 97  && _b <= 122) _b -= 96;
                else if (_b == 163 || _b == 100) _b = 28;
                array_push(_str_entry, _b & 0xFF);
            }
            array_push(_str_entry, 0x00);
            if (array_length(_str_entry) > 1) {
                array_push(_result, ["_line_map_", _li + 1]);
                array_push(_result, _str_entry);
            }
            continue;
        }

        // .byte
        if (_mnem_raw == ".BYTE") {
            var _byte_parts = string_split(_operand_str, ",");
            var _byte_entry = ["byte"];
            for (var _bpi = 0; _bpi < array_length(_byte_parts); _bpi++) {
                var _bp = string_trim(_byte_parts[_bpi]);
                if (_bp != "") array_push(_byte_entry, _eval_expr(_bp) & 0xFF);
            }
            if (array_length(_byte_entry) > 1) {
                array_push(_result, ["_line_map_", _li + 1]);
                array_push(_result, _byte_entry);
            }
            continue;
        }

        // name = $addr (second pass, after directives)
        var _eq_pos2  = string_pos("=", _line);
        var _equ_pos2 = string_pos(" EQU ", string_upper(_line));
        if (_eq_pos2 > 1 || _equ_pos2 > 1) {
            var _asgn_name2    = "";
            var _asgn_val_str2 = "";
            if (_equ_pos2 > 1) {
                _asgn_name2    = string_trim(string_copy(_line, 1, _equ_pos2 - 1));
                _asgn_val_str2 = string_trim(string_delete(_line, 1, _equ_pos2 + 4));
            } else if (_eq_pos2 > 1) {
                _asgn_name2    = string_trim(string_copy(_line, 1, _eq_pos2 - 1));
                _asgn_val_str2 = string_trim(string_delete(_line, 1, _eq_pos2));
            }
            if (_asgn_name2 != "" && string_pos(" ", _asgn_name2) == 0
            &&  string_char_at(_asgn_name2, 1) != "."
            &&  string_char_at(_asgn_name2, 1) != "*"
            &&  _asgn_val_str2 != "") {
                var _asgn_num2 = _eval_expr(_asgn_val_str2);
                ds_map_set(global.named_loc_map, string_upper(_asgn_name2), _asgn_num2);
                continue;
            }
        }

        // .pcsave / .pcrestore — bracket a relocated run so the program counter
        // comes BACK afterwards.
        //
        // .pc on its own is a ONE-WAY relocation: c64_new_program's org() sets
        // pc_override and never restores it, so everything emitted after a .pc
        // — including every node further down the spine — assembles at the
        // relocated address. These two map onto the same save/restore markers
        // the compile chain already uses internally (org -2 / org -3), so a
        // block can park a data table somewhere and carry on where it left off.
        //
        // Must be tested BEFORE the ".PC" prefix check below, or ".PCSAVE"
        // parses as a .pc directive with the address "SAVE".
        if (_mnem_raw == ".PCSAVE") {
            array_push(_result, ["_line_map_", _li + 1]);
            array_push(_result, ["pc", -2]);
            continue;
        }
        if (_mnem_raw == ".PCRESTORE") {
            array_push(_result, ["_line_map_", _li + 1]);
            array_push(_result, ["pc", -3]);
            continue;
        }

        // .pc / *. / .* / * = directives
        var _is_pc_dir   = false;
        var _pc_addr_str = "";
        if (string_copy(_mnem_raw, 1, 3) == ".PC") {
            _is_pc_dir = true;
            var _pc_rest = string_delete(_mnem_raw, 1, 3) + _operand_str;
            _pc_rest = string_replace_all(_pc_rest, " ", "");
            if (string_length(_pc_rest) > 0 && string_char_at(_pc_rest, 1) == "=") _pc_rest = string_delete(_pc_rest, 1, 1);
            _pc_addr_str = _pc_rest;
        } else if (string_copy(_mnem_raw, 1, 2) == "*." || string_copy(_mnem_raw, 1, 2) == ".*") {
            _is_pc_dir = true;
            var _pc_rest = string_delete(_mnem_raw, 1, 2) + _operand_str;
            _pc_rest = string_replace_all(_pc_rest, " ", "");
            if (string_length(_pc_rest) > 0 && string_char_at(_pc_rest, 1) == "=") _pc_rest = string_delete(_pc_rest, 1, 1);
            _pc_addr_str = _pc_rest;
        } else if (_mnem_raw == "*" && string_char_at(string_trim(_operand_str), 1) == "=") {
            _is_pc_dir = true;
            var _pc_rest = string_trim(_operand_str);
            _pc_rest = string_delete(_pc_rest, 1, 1); // strip the '='
            _pc_rest = string_replace_all(_pc_rest, " ", "");
            _pc_addr_str = _pc_rest;
        }
		
        if (_is_pc_dir) {
            array_push(_result, ["_line_map_", _li + 1]);
            array_push(_result, ["pc", _eval_expr(_pc_addr_str)]);
            continue;
        }

        // ── Resolve expressions in operand ────────────────────────
        if (_operand_str != "") {
            var _imm_prefix = "";
            var _op_work    = _operand_str;

            if (string_char_at(_op_work, 1) == "#") {
                _imm_prefix = "#";
                _op_work    = string_delete(_op_work, 1, 1);

                // Handle #<expr (lo byte)
                if (string_char_at(_op_work, 1) == "<") {
                    var _lo_expr  = string_delete(_op_work, 1, 1);
                    var _lo_clean = string_replace_all(_lo_expr, "[", "");
                    _lo_clean     = string_replace_all(_lo_clean, "]", "");
                    // Extract base name (before first + or -)
                    var _lo_base  = _lo_clean;
                    var _lo_plus  = string_pos("+", _lo_clean);
                    var _lo_minus = string_pos("-", _lo_clean);
                    var _lo_split = 0;
                    if (_lo_plus  > 1 && (_lo_minus <= 1 || _lo_plus  < _lo_minus)) _lo_split = _lo_plus;
                    if (_lo_minus > 1 && (_lo_plus  <= 1 || _lo_minus < _lo_plus))  _lo_split = _lo_minus;
                    if (_lo_split > 1) _lo_base = string_trim(string_copy(_lo_clean, 1, _lo_split - 1));
                    // Assembly label check — exists in code_block_labels but NOT as a named constant
                    var _lo_is_asm   = (variable_struct_exists(global.code_block_labels, _lo_base)
                                     || variable_struct_exists(global.code_block_labels, string_upper(_lo_base)))
                                    && !ds_map_exists(global.named_loc_map, string_upper(_lo_base));
                    var _lo_is_const   = ds_map_exists(global.named_loc_map, string_upper(_lo_base));
                    // Raw literal check — #<$D800, #<%00010, #<12345 (no label/const lookup needed)
                    var _lo_is_literal = (string_char_at(_lo_base, 1) == "$"
                                       || string_char_at(_lo_base, 1) == "%"
                                       || _asm_is_dec(_lo_base));
                    if (!_lo_is_asm && (_lo_is_const || _lo_split > 1 || _lo_is_literal)) {
                        var _lo_val = _eval_expr(_lo_clean) & 0xFF;
                        array_push(_result, ["_line_map_", _li + 1]);
                        array_push(_result, [_mnem_raw == "LDX" ? "ldx_imm" : (_mnem_raw == "LDY" ? "ldy_imm" : "lda_imm"), _lo_val]);
                    } else {
                        array_push(_result, ["_line_map_", _li + 1]);
                        array_push(_result, [_mnem_raw == "LDX" ? "ldx_lab_lo" : (_mnem_raw == "LDY" ? "ldy_lab_lo" : "lda_lab_lo"), _lo_clean]);
                    }
                    continue;
                }

                // Handle #>expr (hi byte)
                if (string_char_at(_op_work, 1) == ">") {
                    var _hi_expr  = string_delete(_op_work, 1, 1);
                    var _hi_clean = string_replace_all(_hi_expr, "[", "");
                    _hi_clean     = string_replace_all(_hi_clean, "]", "");
                    var _hi_base  = _hi_clean;
                    var _hi_plus  = string_pos("+", _hi_clean);
                    var _hi_minus = string_pos("-", _hi_clean);
                    var _hi_split = 0;
                    if (_hi_plus  > 1 && (_hi_minus <= 1 || _hi_plus  < _hi_minus)) _hi_split = _hi_plus;
                    if (_hi_minus > 1 && (_hi_plus  <= 1 || _hi_minus < _hi_plus))  _hi_split = _hi_minus;
                    if (_hi_split > 1) _hi_base = string_trim(string_copy(_hi_clean, 1, _hi_split - 1));
                    var _hi_is_asm   = (variable_struct_exists(global.code_block_labels, _hi_base)
                                     || variable_struct_exists(global.code_block_labels, string_upper(_hi_base)))
                                    && !ds_map_exists(global.named_loc_map, string_upper(_hi_base));
                    var _hi_is_const   = ds_map_exists(global.named_loc_map, string_upper(_hi_base));
                    // Raw literal check — #>$D800, #>%00010, #>12345 (no label/const lookup needed)
                    var _hi_is_literal = (string_char_at(_hi_base, 1) == "$"
                                       || string_char_at(_hi_base, 1) == "%"
                                       || _asm_is_dec(_hi_base));
                    if (!_hi_is_asm && (_hi_is_const || _hi_split > 1 || _hi_is_literal)) {
                        var _hi_val = (_eval_expr(_hi_clean) >> 8) & 0xFF;
                        array_push(_result, ["_line_map_", _li + 1]);
                        array_push(_result, [_mnem_raw == "LDX" ? "ldx_imm" : (_mnem_raw == "LDY" ? "ldy_imm" : "lda_imm"), _hi_val]);
                    } else {
                        array_push(_result, ["_line_map_", _li + 1]);
                        array_push(_result, [_mnem_raw == "LDX" ? "ldx_lab_hi" : (_mnem_raw == "LDY" ? "ldy_lab_hi" : "lda_lab_hi"), _hi_clean]);
                    }
                    continue;
                }
            }

            // Separate index suffix (,X or ,Y) before evaluating
            var _idx_suffix = "";
            var _up_work    = string_upper(_op_work);
            if (string_char_at(_up_work, string_length(_up_work)) == "X"
            &&  string_char_at(_up_work, string_length(_up_work)-1) == ",") {
                _idx_suffix = string_copy(_op_work, string_length(_op_work)-1, 2);
                _op_work    = string_copy(_op_work, 1, string_length(_op_work)-2);
            } else if (string_char_at(_up_work, string_length(_up_work)) == "Y"
            &&         string_char_at(_up_work, string_length(_up_work)-1) == ",") {
                _idx_suffix = string_copy(_op_work, string_length(_op_work)-1, 2);
                _op_work    = string_copy(_op_work, 1, string_length(_op_work)-2);
            }

            var _first_char     = string_char_at(_op_work, 1);
            var _is_literal     = (string_pos("$", _op_work) == 1 || string_pos("%", _op_work) == 1 || (ord(_first_char) >= 48 && ord(_first_char) <= 57));
            var _has_math       = (string_pos("+", _op_work) > 0 || string_pos("-", _op_work) > 1);
            var _is_known_const = ds_map_exists(global.named_loc_map, string_upper(_op_work));
            var _needs_eval     = _is_literal || _has_math || _is_known_const;

            if (_needs_eval) {
                var _val = _eval_expr(_op_work);
                _operand_str = _imm_prefix + "$" + string_upper(decimal_to_hex(_val)) + _idx_suffix;
            } else {
                _operand_str = _imm_prefix + _op_work + _idx_suffix;
            }
        }

        var _parsed = _asm_resolve_mode(_mnem_raw, _operand_str);
        if (_parsed != undefined) {
            array_push(_result, ["_line_map_", _li + 1]);
            array_push(_result, _parsed);
        }
    }
    return _result;
}