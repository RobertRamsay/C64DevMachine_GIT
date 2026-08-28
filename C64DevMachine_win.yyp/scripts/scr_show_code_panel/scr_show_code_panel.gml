/// @desc SHOW CODE PANEL
///
/// A floating, draggable, scrollable listing of the whole compiled program,
/// drawn in GUI space to the LEFT of the global shortcuts column.
///
/// Every MACRO_ node folds into a single "MACRO_NAME [+]" row that expands to
/// its real instructions and collapses again. Non-macro output (raw opcode
/// nodes, labels, ORG, inline byte data) always lists inline.
///
/// Two display modes:
///   0 = VICE   .0810  A9 09     LDA #$09
///   1 = ASM    .0810            LDA #$09
///
/// The panel NEVER runs its own compile pass. scr_c64_do_update_addresses()
/// already produces a full sizing-pass compile every time the graph changes,
/// and hands that array straight to scr_show_code_build(). The fold pass
/// (flat list -> visible rows) is the only thing an expand/collapse click
/// re-runs, and the draw event only ever walks the 20 visible rows.
///
/// Functions in this file:
///   scr_show_code_norm(_mnem)          mnemonic -> opCodeManager key
///   scr_show_code_hex(_val, _digits)    zero-padded uppercase hex
///   scr_show_code_is_open(_key)         is this macro group expanded?
///   scr_show_code_toggle(_key)          expand / collapse one macro group
///   scr_show_code_bytes(_ln)            "A9 09" style raw byte column
///   scr_show_code_text(_ln)             "LDA #$09" style disassembly column
///   scr_show_code_build(_compiled)      compiled array -> showcode_flat
///   scr_show_code_fold()                showcode_flat -> showcode_lines
///   scr_show_code_draw()                draw + all panel input

// =====================================================================
// Normalise a compile-chain mnemonic to an obj_opCodeManager key.
// Mirrors the same rewrites scr_c64_do_update_addresses() performs so
// sizes and opcode bytes agree with the assembler.
// =====================================================================
function scr_show_code_norm(_mnem) {
    var _n = string_trim(string_lower(string(_mnem)));

    _n = string_replace_all(_n, "_abs_x",   "_abx");
    _n = string_replace_all(_n, "_abs_y",   "_aby");
    _n = string_replace_all(_n, "_zp_x",    "_zpx");
    _n = string_replace_all(_n, "_zp_y",    "_zpy");
    _n = string_replace_all(_n, "_ind_x",   "_izx");
    _n = string_replace_all(_n, "_ind_y",   "_izy");
    _n = string_replace_all(_n, "_imm_rep", "_imm");

    if (_n == "jmp")     { _n = "jmp_abs"; }
    if (_n == "jsr_abs") { _n = "jsr";     }

    if (_n == "lda_lab_lo") { _n = "lda_imm"; }
    if (_n == "lda_lab_hi") { _n = "lda_imm"; }
    if (_n == "lda_lab")    { _n = "lda_abs"; }
    if (_n == "sta_lab")    { _n = "sta_abs"; }
    if (_n == "inc_lab")    { _n = "inc_abs"; }
    if (_n == "dec_lab")    { _n = "dec_abs"; }
    if (_n == "ora_lab")    { _n = "ora_abs"; }
    if (_n == "and_lab")    { _n = "and_abs"; }
    if (_n == "cmp_lab")    { _n = "cmp_abs"; }

    return _n;
}

// =====================================================================
function scr_show_code_hex(_val, _digits) {
    var _v = _val;
    if (!is_real(_v)) { _v = 0; }
    _v = floor(_v) & $FFFF;

    var _h = string_upper(decimal_to_hex(_v));
    while (string_length(_h) < _digits) {
        _h = "0" + _h;
    }
    return _h;
}

// =====================================================================
// Expanded-macro bookkeeping. showcode_expanded is a plain array of node
// keys initialised in the Create event, so there is no struct to test for
// existence and no lazy allocation anywhere.
// =====================================================================
function scr_show_code_is_open(_key) {
    var _list = obj_workspace_manager.showcode_expanded;
    for (var _i = 0; _i < array_length(_list); _i++) {
        if (_list[_i] == _key) {
            return true;
        }
    }
    return false;
}

function scr_show_code_toggle(_key) {
    with (obj_workspace_manager) {
        var _hit = -1;
        for (var _i = 0; _i < array_length(showcode_expanded); _i++) {
            if (showcode_expanded[_i] == _key) {
                _hit = _i;
                break;
            }
        }
        if (_hit >= 0) {
            array_delete(showcode_expanded, _hit, 1);
        } else {
            array_push(showcode_expanded, _key);
        }
        showcode_dirty = true;
    }
}

// =====================================================================
// Raw byte column, VICE monitor style. Operands that are still labels at
// sizing-pass time print as ?? because the two-pass fixup has not run yet.
// =====================================================================
function scr_show_code_bytes(_ln) {
    if (_ln.kind == "byte") {
        return scr_show_code_hex(_ln.val, 2);
    }

    var _op = scr_opcode_hex(_ln.mnem);

    if (_ln.sz <= 1) {
        return _op;
    }

    if (_ln.lbl != "") {
        if (_ln.sz == 2) {
            return _op + " ??";
        }
        return _op + " ?? ??";
    }

    var _v = _ln.val;
    if (!is_real(_v)) { _v = 0; }
    _v = floor(_v) & $FFFF;

    if (_ln.sz == 2) {
        return _op + " " + scr_show_code_hex(_v & $FF, 2);
    }
    return _op + " " + scr_show_code_hex(_v & $FF, 2)
               + " " + scr_show_code_hex((_v >> 8) & $FF, 2);
}

// =====================================================================
// Disassembly column.
// =====================================================================
function scr_show_code_text(_ln) {
    if (_ln.kind == "org") {
        return "* = $" + scr_show_code_hex(_ln.pc, 4);
    }

    if (_ln.kind == "label") {
        var _lt = _ln.lbl;
        if (_lt == "") {
            _lt = "(anon)";
        }
        return string_upper(_lt) + ":";
    }

    if (_ln.kind == "byte") {
        return ".BYTE $" + scr_show_code_hex(_ln.val, 2);
    }

    var _raw = _ln.raw;
    var _op3 = string_upper(string_copy(_raw, 1, 3));

    if (_ln.lbl != "") {
        if (string_pos("_lab_lo", _raw) > 0) {
            return _op3 + " #<" + string_upper(_ln.lbl);
        }
        if (string_pos("_lab_hi", _raw) > 0) {
            return _op3 + " #>" + string_upper(_ln.lbl);
        }
        return _op3 + " " + string_upper(_ln.lbl);
    }

    return scr_format_asm(_raw, _ln.val);
}

// =====================================================================
// BUILD — turn one compile-chain result into the flat line list.
// Called from scr_c64_do_update_addresses() with the sizing-pass array it
// already has in hand, so this costs a walk and nothing more.
// =====================================================================
function scr_show_code_build(_compiled) {
    if (!instance_exists(obj_workspace_manager)) { exit; }

    with (obj_workspace_manager) {
        var _flat = [];
        var _pc   = global.start_pc;

        for (var _i = 0; _i < array_length(_compiled); _i++) {
            var _e = _compiled[_i];
            if (array_length(_e) < 1) { continue; }

            var _m = string_lower(string(_e[0]));
            if (_m == "_node_ref_" || _m == "const" || _m == "_line_map_" || _m == "comment" || _m == "") {
                continue;
            }

            // ORG relocates the program counter mid-stream — follow it so
            // every address below stays honest.
            if (_m == "org") {
                var _o = _e[1];
                if (is_string(_o)) {
                    _o = real(_o);
                }
                _pc = _o;
                array_push(_flat, { kind:"org", key:"", name:"", pc:_pc, raw:_m, mnem:_m, val:0, lbl:"", sz:0 });
                continue;
            }

            // [1] is the operand. A non-numeric operand is an unresolved label.
            var _v = 0;
            if (array_length(_e) > 1) {
                _v = _e[1];
            }
            var _lbl = "";
            if (is_string(_v) && _v != "" && _v != "0") {
                _lbl = _v;
                _v   = 0;
            }

            // [2] is the owning node instance (or a string sentinel).
            var _key  = "";
            var _name = "";
            if (array_length(_e) > 2) {
                var _tag = _e[2];
                if (!is_string(_tag) && _tag != noone) {
                    if (instance_exists(_tag)) {
                        if (string_pos("MACRO_", string(_tag.node_type)) == 1) {
                            _key  = string(_tag);
                            _name = string(_tag.node_type);
                        }
                    }
                }
            }

            if (_m == "label") {
                array_push(_flat, { kind:"label", key:_key, name:_name, pc:_pc, raw:_m, mnem:_m, val:0, lbl:_lbl, sz:0 });
                continue;
            }

            if (_m == "byte" || _m == "byt" || _m == "byte_lab_lo" || _m == "byte_lab_hi") {
                array_push(_flat, { kind:"byte", key:_key, name:_name, pc:_pc, raw:_m, mnem:"byte", val:_v, lbl:_lbl, sz:1 });
                _pc += 1;
                continue;
            }

            var _norm = scr_show_code_norm(_m);
            var _sz   = obj_opCodeManager.get_size(_norm);
            if (_sz <= 0) { continue; }

            array_push(_flat, { kind:"op", key:_key, name:_name, pc:_pc, raw:_m, mnem:_norm, val:_v, lbl:_lbl, sz:_sz });
            _pc += _sz;
        }

        showcode_flat  = _flat;
        showcode_gen   = global.named_loc_repack_gen;
        showcode_dirty = true;
    }
}

// =====================================================================
// FOLD — flat list -> visible rows, honouring the expand/collapse state.
// Runs on a rebuild and on every expand/collapse click. Never on a plain
// scroll and never per frame.
// =====================================================================
function scr_show_code_fold() {
    if (!instance_exists(obj_workspace_manager)) { exit; }

    with (obj_workspace_manager) {
        var _out  = [];
        var _n    = array_length(showcode_flat);
        var _i    = 0;

        while (_i < _n) {
            var _ln = showcode_flat[_i];

            if (_ln.key == "") {
                array_push(_out, { kind:"line", idx:_i, key:"", name:"", pc:_ln.pc, sz:_ln.sz, count:1, open:false });
                _i += 1;
                continue;
            }

            // Fold this run of consecutive lines owned by the same macro node.
            var _k     = _ln.key;
            var _j     = _i;
            var _bytes = 0;
            var _cnt   = 0;
            while (_j < _n && showcode_flat[_j].key == _k) {
                _bytes += showcode_flat[_j].sz;
                _cnt   += 1;
                _j     += 1;
            }

            var _open = scr_show_code_is_open(_k);
            array_push(_out, { kind:"group", idx:_i, key:_k, name:_ln.name, pc:_ln.pc, sz:_bytes, count:_cnt, open:_open });

            if (_open) {
                for (var _g = _i; _g < _j; _g++) {
                    array_push(_out, { kind:"child", idx:_g, key:_k, name:"", pc:showcode_flat[_g].pc, sz:showcode_flat[_g].sz, count:1, open:true });
                }
            }

            _i = _j;
        }

        showcode_lines  = _out;
        showcode_dirty  = false;

        var _maxs = max(0, array_length(showcode_lines) - showcode_rows);
        showcode_scroll = clamp(showcode_scroll, 0, _maxs);
    }
}

// =====================================================================
// DRAW — panel chrome, listing, drag, scroll, collapse, mode toggle.
// Call this once from obj_workspace_manager's Draw GUI event.
// =====================================================================
function scr_show_code_draw() {
    if (!instance_exists(obj_workspace_manager)) { exit; }

    with (obj_workspace_manager) {

        global.showcode_mouse_over = false;

        // A dropdown menu owns the screen while it is open — stand down so the
        // two panels never fight, and come straight back once it closes.
        if (gui_menu_open != -1) {
            showcode_dragging = false;
            exit;
        }

        if (showcode_dirty) {
            scr_show_code_fold();
        }

        var _gw = global.gui_w;
        var _gh = display_get_gui_height();
        var _mx = global.gui_mouse_x;
        var _my = global.gui_mouse_y;

        // ---- geometry -------------------------------------------------
        var _pw    = showcode_w;
        var _hdr_h = 24;
        var _row_h = 15;
        var _pad_t = 6;
        var _pad_b = 12;

        var _body_h = showcode_rows * _row_h;
        var _ph     = _hdr_h + _pad_t + _body_h + _pad_b;
        if (!showcode_open) {
            _ph = _hdr_h + 12;
        }

        // First run of a fresh .ini: park immediately left of the shortcuts column.
        if (showcode_x < 0) {
            showcode_x = global.sc_x_start - _pw - 14;
            showcode_y = 50;
        }

        showcode_x = clamp(showcode_x, 0, max(0, _gw - _pw));
        showcode_y = clamp(showcode_y, 0, max(0, _gh - _hdr_h - 8));

        var _px = floor(showcode_x);
        var _py = floor(showcode_y);

        // ---- drag ------------------------------------------------------
        var _hdr_hover = (_mx >= _px && _mx < _px + _pw && _my >= _py && _my < _py + _hdr_h);
        var _btn_w     = 30;
        var _btn_min_x = _px + _pw - 10 - _btn_w;
        var _btn_mod_x = _btn_min_x - 6 - 52;

        var _on_min = (_mx >= _btn_min_x && _mx < _btn_min_x + _btn_w && _my >= _py + 4 && _my < _py + _hdr_h - 4);
        var _on_mod = (_mx >= _btn_mod_x && _mx < _btn_mod_x + 52   && _my >= _py + 4 && _my < _py + _hdr_h - 4);

        if (mouse_check_button_pressed(mb_left)) {
            if (_on_min) {
                showcode_open = !showcode_open;
                scr_show_code_save_ini();
            } else if (_on_mod && showcode_open) {
                showcode_mode = (showcode_mode + 1) mod 2;
                scr_show_code_save_ini();
            } else if (_hdr_hover) {
                showcode_dragging = true;
                showcode_drag_dx  = _mx - showcode_x;
                showcode_drag_dy  = _my - showcode_y;
            }
        }

        if (showcode_dragging) {
            if (mouse_check_button(mb_left)) {
                showcode_x = _mx - showcode_drag_dx;
                showcode_y = _my - showcode_drag_dy;
                showcode_x = clamp(showcode_x, 0, max(0, _gw - _pw));
                showcode_y = clamp(showcode_y, 0, max(0, _gh - _hdr_h - 8));
                _px = floor(showcode_x);
                _py = floor(showcode_y);
            } else {
                showcode_dragging = false;
                scr_show_code_save_ini();
            }
        }

        // Everything below the workspace needs to know the mouse is ours.
        var _over = (_mx >= _px && _mx < _px + _pw && _my >= _py && _my < _py + _ph);
        global.showcode_mouse_over = (_over || showcode_dragging);

        // ---- panel background: the same glass 9-slice the menus use ----
        draw_sprite_stretched(spr_glassSlice, niceSliceFrm, _px, _py, _pw, _ph);

        var _font_before  = draw_get_font();
        var _halign_before = draw_get_halign();
        var _valign_before = draw_get_valign();
        draw_set_valign(fa_top);

        // ---- header ----------------------------------------------------
        draw_set_font(fnt_C64_Angled);
        draw_set_halign(fa_left);
        draw_set_color(c_white);
        draw_text_transformed(_px + 12, _py + 6, "SHOW CODE", 1.0, 1.0, 0);

        if (showcode_open) {
            var _mode_lbl = "VICE";
            if (showcode_mode == 1) {
                _mode_lbl = "ASM";
            }

            var _mod_col = make_color_rgb(120, 120, 130);
            if (_on_mod) {
                _mod_col = c_white;
            }
            draw_set_color(_mod_col);
            draw_rectangle(_btn_mod_x, _py + 4, _btn_mod_x + 52, _py + _hdr_h - 4, true);
            draw_set_halign(fa_center);
            draw_text_transformed(_btn_mod_x + 26, _py + 6, _mode_lbl, 1.0, 1.0, 0);
        }

        var _min_lbl = "-";
        if (!showcode_open) {
            _min_lbl = "+";
        }
        var _min_col = make_color_rgb(120, 120, 130);
        if (_on_min) {
            _min_col = c_white;
        }
        draw_set_color(_min_col);
        draw_rectangle(_btn_min_x, _py + 4, _btn_min_x + _btn_w, _py + _hdr_h - 4, true);
        draw_set_halign(fa_center);
        draw_text_transformed(_btn_min_x + (_btn_w / 2), _py + 5, _min_lbl, 1.0, 1.0, 0);

        if (!showcode_open) {
            draw_set_font(_font_before);
            draw_set_halign(_halign_before);
            draw_set_valign(_valign_before);
            exit;
        }

        // ---- body ------------------------------------------------------
        var _total = array_length(showcode_lines);
        var _maxs  = max(0, _total - showcode_rows);
        showcode_scroll = clamp(showcode_scroll, 0, _maxs);

        var _body_y = _py + _hdr_h + _pad_t;

        // Wheel scrolls the listing whenever the pointer is over the panel.
        if (_over) {
            if (mouse_wheel_up())   { showcode_scroll = max(0,     showcode_scroll - 3); }
            if (mouse_wheel_down()) { showcode_scroll = min(_maxs, showcode_scroll + 3); }
        }

        // Column origins. ASM mode drops the raw byte column and pulls the
        // disassembly left into the space it frees.
        var _col_addr = _px + 12;
        var _col_byte = _px + 66;
        var _col_text = _px + 150;
        if (showcode_mode == 1) {
            _col_text = _px + 66;
        }

        draw_set_font(fnt_c64_opCode);
        draw_set_halign(fa_left);

        if (_total == 0) {
            draw_set_color(make_color_rgb(120, 120, 130));
            draw_text_transformed(_col_addr, _body_y, "NO CODE — ADD SOME NODES", 1.0, 1.0, 0);
        }

        var _clicked_key = "";

        for (var _r = 0; _r < showcode_rows; _r++) {
            var _li = showcode_scroll + _r;
            if (_li >= _total) { break; }

            var _row  = showcode_lines[_li];
            var _ry   = _body_y + (_r * _row_h);
            var _rhov = (_mx >= _px + 6 && _mx < _px + _pw - 14 && _my >= _ry && _my < _ry + _row_h);

            if (_row.kind == "group") {

                if (_rhov) {
                    draw_set_alpha(0.22);
                    draw_set_color(c_white);
                    draw_rectangle(_px + 6, _ry, _px + _pw - 14, _ry + _row_h - 1, false);
                    draw_set_alpha(1.0);

                    if (mouse_check_button_pressed(mb_left)) {
                        _clicked_key = _row.key;
                    }
                }

                var _sign = "[+]";
                if (_row.open) {
                    _sign = "[-]";
                }

                draw_set_color(make_color_rgb(150, 150, 160));
                draw_text_transformed(_col_addr, _ry, "." + scr_show_code_hex(_row.pc, 4), 1.0, 1.0, 0);

                draw_set_color(make_color_rgb(255, 210, 80));
                draw_text_transformed(_col_byte, _ry, _sign + " " + _row.name, 1.0, 1.0, 0);

                draw_set_halign(fa_right);
                draw_set_color(make_color_rgb(110, 130, 150));
                draw_text_transformed(_px + _pw - 20, _ry, string(_row.sz) + "B", 1.0, 1.0, 0);
                draw_set_halign(fa_left);

                continue;
            }

            var _ln = showcode_flat[_row.idx];

            var _indent = 0;
            var _tint   = make_color_rgb(210, 220, 230);
            if (_row.kind == "child") {
                _indent = 10;
                _tint   = make_color_rgb(160, 200, 220);
            }
            if (_ln.kind == "label") {
                _tint = make_color_rgb(120, 230, 140);
            }
            if (_ln.kind == "org") {
                _tint = make_color_rgb(255, 140, 140);
            }
            if (_ln.kind == "byte") {
                _tint = make_color_rgb(180, 170, 210);
            }

            draw_set_color(make_color_rgb(150, 150, 160));
            draw_text_transformed(_col_addr + _indent, _ry, "." + scr_show_code_hex(_ln.pc, 4), 1.0, 1.0, 0);

            if (showcode_mode == 0 && _ln.kind != "label" && _ln.kind != "org") {
                draw_set_color(make_color_rgb(190, 190, 120));
                draw_text_transformed(_col_byte + _indent, _ry, scr_show_code_bytes(_ln), 1.0, 1.0, 0);
            }

            draw_set_color(_tint);
            draw_text_transformed(_col_text + _indent, _ry, scr_show_code_text(_ln), 1.0, 1.0, 0);
        }

        if (_clicked_key != "") {
            scr_show_code_toggle(_clicked_key);
        }

        // ---- scrollbar --------------------------------------------------
        if (_total > showcode_rows) {
            var _tr_x = _px + _pw - 12;
            var _tr_y1 = _body_y;
            var _tr_y2 = _body_y + _body_h;

            draw_set_alpha(0.30);
            draw_set_color(c_black);
            draw_rectangle(_tr_x, _tr_y1, _tr_x + 5, _tr_y2, false);
            draw_set_alpha(1.0);

            var _frac  = showcode_rows / _total;
            var _thh   = max(16, (_tr_y2 - _tr_y1) * _frac);
            var _thy   = _tr_y1 + ((_tr_y2 - _tr_y1 - _thh) * (showcode_scroll / max(1, _maxs)));

            draw_set_color(make_color_rgb(160, 170, 190));
            draw_rectangle(_tr_x, _thy, _tr_x + 5, _thy + _thh, false);
        }

        draw_set_font(_font_before);
        draw_set_halign(_halign_before);
        draw_set_valign(_valign_before);
        draw_set_color(c_white);
    }
}

// =====================================================================
// Persist position / open state / mode. Written on every state change so
// the panel comes back exactly where it was left.
// =====================================================================
function scr_show_code_save_ini() {
    with (obj_workspace_manager) {
        var _open_flag = 0;
        if (showcode_open) {
            _open_flag = 1;
        }

        ini_open("c64devmachine.ini");
        ini_write_real("showcode", "x",    floor(showcode_x));
        ini_write_real("showcode", "y",    floor(showcode_y));
        ini_write_real("showcode", "open", _open_flag);
        ini_write_real("showcode", "mode", showcode_mode);
        ini_close();
    }
}
