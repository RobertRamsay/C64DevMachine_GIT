function scr_node_draw_set_var() {

    var _name  = (array_length(instructions) > 0) ? string(instructions[0][1]) : "";
    var _value = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 0;
    var _mode  = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 0;
    var _sign  = (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) ? real(instructions[0][4]) : 0;
    var _src_mode = (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) ? real(instructions[0][5]) : 0;
    var _src_v1   = (array_length(instructions[0]) > 6) ? string(instructions[0][6]) : "";
    var _ptr_byte_mode = (array_length(instructions[0]) > 7 && is_real(instructions[0][7])) ? real(instructions[0][7]) : 0;
    var _offx = (array_length(instructions[0]) > 8 && is_real(instructions[0][8])) ? real(instructions[0][8]) : 0;

    // ---- Cached lookups (named_loc_map, meta, hex) ----
    // Rebuild only when the dependent values change. Signature is cheap; the
    // map/meta/hex work it guards is not. Static nodes skip all of it.
    var _sv_sig = _name + "|" + string(_value) + "|" + string(global.use_hex_display);
    if (setvar_cache_sig != _sv_sig) {
        setvar_cache_sig = _sv_sig;

        setvar_cache_addr = ds_map_exists(global.named_loc_map, _name)
                          ? ds_map_find_value(global.named_loc_map, _name) : -1;
        var _meta_c = scr_nloc_find_meta(_name);
        if (_meta_c != undefined) {
            setvar_cache_size  = _meta_c.size;
            setvar_cache_enc   = _meta_c.encoding;
            setvar_cache_isbcd = (string_pos("bcd", _meta_c.encoding) > 0);
        } else {
            setvar_cache_size  = 1;
            setvar_cache_enc   = "byte";
            setvar_cache_isbcd = false;
        }

        if (setvar_cache_addr >= 0) {
            var _hx = decimal_to_hex(setvar_cache_addr);
            while (string_length(_hx) < 4) _hx = "0" + _hx;
            setvar_cache_hex = string_upper(_hx);
        } else {
            setvar_cache_hex = "";
        }
    }

    var _addr   = setvar_cache_addr;
    var _size   = setvar_cache_size;
    var _enc    = setvar_cache_enc;
    var _is_bcd = setvar_cache_isbcd;
    var _lh     = 12;
    var _ly     = y + 28;

    // Row 1 — variable name (click name to open DEST picker; handled in Step)
    var _name_disp = scr_nloc_display_name(_name);
    draw_set_font(fnt_c64_tiny);
    var _name_hov = point_in_rectangle(mouse_x, mouse_y, x + 10, _ly - 2, x + width - 44, _ly + 10);
    draw_set_color(_name_hov ? c_lime : c_yellow);
    draw_text(x + 10, _ly - 2, _name_disp != "" ? _name_disp : "< SELECT >");

    draw_set_color(make_color_rgb(80, 140, 120));
    draw_text(x + 150, _ly - 4, "[" + string_upper(_enc) + "]");

    // ▶ Offset ,X toggle — far right of name row (LOOKUP removed; name click opens picker)
    // Shown only for offset-capable sources: A = src_mode 3, VAR = 1, byte-LIT-ABS = 0 & mode 0 & size 1
    var _vlby1   = _ly + 16;
    var _vlby2   = _ly + 28;
    var _offx_ok = (_src_mode == 3)
                || (_src_mode == 1)
                || (_src_mode == 0 && _mode == 0 && _size < 2);
    if (_offx_ok) {
        var _oxx1 = x + width - 38;
        var _oxx2 = x + width - 4;
        var _oxhov = point_in_rectangle(mouse_x, mouse_y, _oxx1, _vlby1, _oxx2, _vlby2);
        if (_offx == 1) {
            draw_set_color(_oxhov ? make_color_rgb(120, 160, 220) : make_color_rgb(60, 95, 165));
        } else {
            draw_set_color(_oxhov ? make_color_rgb(70, 80, 100) : make_color_rgb(35, 45, 60));
        }
        draw_rectangle(_oxx1, _vlby1, _oxx2, _vlby2, false);
        draw_set_color((_offx == 1) ? c_white : make_color_rgb(120, 130, 150));
        draw_set_halign(fa_center);
        draw_text((_oxx1 + _oxx2) * 0.5, _vlby1 - 3, _offx == 1 ? ",X" : "+X");
        draw_set_halign(fa_left);
    }

    _ly += _lh;

    // Row 2 — address
    if (_addr >= 0) {
        var _hex = decimal_to_hex(_addr);
        while (string_length(_hex) < 4) _hex = "0" + _hex;
        draw_set_color(c_aqua);
        var _addr_disp = global.use_hex_display
            ? ("@ $" + string_upper(_hex))
            : ("@ " + string(_addr));
        draw_text(x + 10, _ly, _addr_disp);
    } else {
        draw_set_color(c_red);
        draw_text(x + 10, _ly, "UNKNOWN NAME");
    }

    // Row 3 — stores (PTR mode reframes this as a pointer)
    _ly += _lh + 6;
    draw_set_font(fnt_c64_tiny);

    // ----- SRC mode toggle (LIT -> VAR -> PTR -> A -> X -> Y) — left side of value row -----
    var _src_btn_x1 = x + 10;
    var _src_btn_x2 = x + 46;
    var _src_hov = point_in_rectangle(mouse_x, mouse_y, _src_btn_x1, _ly, _src_btn_x2, _ly + 14);
    var _src_lbl = "LIT";
    if (_src_mode == 1) { _src_lbl = "VAR"; }
    else if (_src_mode == 2) { _src_lbl = "PTR"; }
    else if (_src_mode == 3) { _src_lbl = "A"; }
    else if (_src_mode == 4) { _src_lbl = "X"; }
    else if (_src_mode == 5) { _src_lbl = "Y"; }

    var _src_base_col = make_color_rgb(40, 60, 100);
    if (_src_mode == 1) { _src_base_col = make_color_rgb(100, 60, 40); }
    else if (_src_mode == 2) { _src_base_col = make_color_rgb(100, 40, 100); }
    else if (_src_mode == 3) { _src_base_col = make_color_rgb(40, 100, 60); }
    else if (_src_mode == 4) { _src_base_col = make_color_rgb(40, 100, 60); }
    else if (_src_mode == 5) { _src_base_col = make_color_rgb(40, 100, 60); }

    var _src_hot_col = make_color_rgb(80, 100, 160);
    if (_src_mode == 1) { _src_hot_col = make_color_rgb(160, 100, 80); }
    else if (_src_mode == 2) { _src_hot_col = make_color_rgb(160, 80, 160); }
    else if (_src_mode == 3) { _src_hot_col = make_color_rgb(80, 160, 110); }
    else if (_src_mode == 4) { _src_hot_col = make_color_rgb(80, 160, 110); }
    else if (_src_mode == 5) { _src_hot_col = make_color_rgb(80, 160, 110); }

    draw_set_color(_src_hov ? _src_hot_col : _src_base_col);
    draw_rectangle(_src_btn_x1, _ly, _src_btn_x2, _ly + 14, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_src_btn_x1 + _src_btn_x2) * 0.5, _ly, _src_lbl);
    draw_set_halign(fa_left);

    if (_src_mode == 0) {
        // ============ LITERAL MODE ============
        draw_set_color(make_color_rgb(120, 120, 180));
        draw_text(x + 52, _ly, _mode == 0 ? "VALUE:" : (_sign == 0 ? "OFFSET+:" : "OFFSET-:"));

        draw_set_color(c_yellow);
        draw_set_halign(fa_right);
        if (_is_bcd) {
            draw_text(x + width - 52, _ly, string(_value));
        } else if (global.use_hex_display) {
            var _pad = (_size >= 2) ? 4 : 2;
            var _val_hex = decimal_to_hex(_value);
            while (string_length(_val_hex) < _pad) _val_hex = "0" + _val_hex;
            draw_text(x + width - 52, _ly, "$" + string_upper(_val_hex));
        } else {
            draw_text(x + width - 52, _ly, string(_value));
        }
        draw_set_halign(fa_left);

        var _btn_x   = x + width - 46;
        var _btn_hov = point_in_rectangle(mouse_x, mouse_y, _btn_x, _ly, _btn_x + 38, _ly + 14);
        draw_set_color(_mode == 0
            ? (_btn_hov ? make_color_rgb(80, 160, 80)  : make_color_rgb(40, 100, 40))
            : (_btn_hov ? make_color_rgb(200, 120, 40) : make_color_rgb(120, 70, 20)));
        draw_rectangle(_btn_x, _ly, _btn_x + 38, _ly + 14, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_btn_x + 19, _ly, _mode == 0 ? "ABS" : "REL");
        draw_set_halign(fa_left);

        if (_mode == 1) {
            var _sbtn_y  = _ly + 16;
            var _sbtn_hov = point_in_rectangle(mouse_x, mouse_y, _btn_x, _sbtn_y, _btn_x + 38, _sbtn_y + 14);
            draw_set_color(_sign == 0
                ? (_sbtn_hov ? make_color_rgb(80, 160, 80)  : make_color_rgb(40, 100, 40))
                : (_sbtn_hov ? make_color_rgb(200, 60, 60)  : make_color_rgb(120, 20, 20)));
            draw_rectangle(_btn_x, _sbtn_y, _btn_x + 38, _sbtn_y + 14, false);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_text(_btn_x + 19, _sbtn_y, _sign == 0 ? "POS" : "NEG");
            draw_set_halign(fa_left);
        }

    } else if (_src_mode >= 3) {
        // ============ REGISTER MODE (A / X / Y -> dest) ============
        var _reg_name = "A";
        if (_src_mode == 4) { _reg_name = "X"; }
        else if (_src_mode == 5) { _reg_name = "Y"; }

        var _reg_lbl = "REG " + _reg_name + " -> DEST";
        if (_src_mode == 3 && _offx == 1) { _reg_lbl = "REG A -> DEST,X"; }
        draw_set_color(make_color_rgb(120, 180, 140));
        draw_text(x + 52, _ly, _reg_lbl);

    } else if (_src_mode == 1) {
        // ============ VAR MODE (byte = byte copy) ============
        // Click the name itself to open the SRC picker (SRC SET button removed).
        var _srcname_hov = point_in_rectangle(mouse_x, mouse_y, x + 52, _ly, x + width - 4, _ly + 12);
        draw_set_color(_srcname_hov ? c_lime : c_yellow);
        draw_text(x + 52, _ly, _src_v1 != "" ? ("$" + _src_v1) : "< SRC >");

    } else {
        // ============ PTR MODE (store byte at *resolved address* of dest word) ============
        draw_set_color(make_color_rgb(120, 120, 180));
        draw_text(x + 52, _ly, "STORE @PTR");

        var _bt_x   = x + width - 46;
        var _bt_hov = point_in_rectangle(mouse_x, mouse_y, _bt_x, _ly, _bt_x + 38, _ly + 14);
        draw_set_color(_ptr_byte_mode == 0
            ? (_bt_hov ? make_color_rgb(80, 100, 160) : make_color_rgb(40, 60, 100))
            : (_bt_hov ? make_color_rgb(160, 100, 80) : make_color_rgb(100, 60, 40)));
        draw_rectangle(_bt_x, _ly, _bt_x + 38, _ly + 14, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_bt_x + 19, _ly, _ptr_byte_mode == 0 ? "LIT" : "VAR");
        draw_set_halign(fa_left);

        // Next row — the byte source itself
        _ly += _lh + 4;
        if (_ptr_byte_mode == 0) {
            // literal byte value (click to type), shares slot 2
            draw_set_color(make_color_rgb(120, 120, 180));
            draw_text(x + 10, _ly, "BYTE:");
            draw_set_color(c_yellow);
            draw_set_halign(fa_right);
            if (global.use_hex_display) {
                var _bh = decimal_to_hex(_value & 0xFF);
                while (string_length(_bh) < 2) _bh = "0" + _bh;
                draw_text(x + width - 10, _ly, "$" + string_upper(_bh));
            } else {
                draw_text(x + width - 10, _ly, string(_value & 0xFF));
            }
            draw_set_halign(fa_left);
        } else {
            // byte var (picker) — click the name to open the picker (SRC SET button removed)
            var _bsrc_hov = point_in_rectangle(mouse_x, mouse_y, x + 10, _ly, x + width - 4, _ly + 12);
            draw_set_color(_bsrc_hov ? c_lime : c_yellow);
            draw_text(x + 10, _ly, _src_v1 != "" ? ("$" + _src_v1) : "< BYTE SRC >");
        }
    }
}