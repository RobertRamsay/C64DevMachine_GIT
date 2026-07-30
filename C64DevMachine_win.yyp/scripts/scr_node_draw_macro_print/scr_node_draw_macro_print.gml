function scr_node_draw_macro_print(_draw_x, _y) {
    var _header_h = 24;
    var _line_h   = 12;
    var _sx       = is_real(instructions[0][1]) ? real(instructions[0][1]) : 0;
    var _sy       = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
    var _col      = is_real(instructions[0][3]) ? clamp(real(instructions[0][3]), 0, 15) : 1;
    var _clr      = is_real(instructions[0][4]) ? real(instructions[0][4]) : 0;
    var _txt      = (array_length(instructions[0]) > 5) ? string(instructions[0][5]) : "";
    var _loc      = (array_length(instructions[0]) > 6) ? real(instructions[0][6]) : 0x2000;
    var _align_h  = (array_length(instructions[0]) > 7) ? real(instructions[0][7]) : 0;
    var _align_v  = (array_length(instructions[0]) > 8) ? real(instructions[0][8]) : 0;

    // New fields for asset mode
    var _src_mode  = (array_length(instructions[0]) > 9  && is_real(instructions[0][9]))  ? real(instructions[0][9])  : 0;
    var _asset_nm  = (array_length(instructions[0]) > 10) ? string(instructions[0][10]) : "";
    var _start_off = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
    var _end_off   = (array_length(instructions[0]) > 12 && is_real(instructions[0][12])) ? real(instructions[0][12]) : 0;
    var _scr_base  = (array_length(instructions[0]) > 13 && is_real(instructions[0][13])) ? real(instructions[0][13]) : 0x0400;

    // Resolve effective text length for byte/range display
    var _eff_len  = string_length(_txt);
    var _eff_addr = _loc;
    if (_src_mode == 1 && _asset_nm != "") {
        if (instance_exists(obj_asset_manager)) {
            var _am_d = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am_d.asset_list); _ai++) {
                var _ad = ds_list_find_value(_am_d.asset_list, _ai);
                if (_ad.type == "TEXT_DATA" && _ad.name == _asset_nm) {
                    var _asz = 0;
                    if (buffer_exists(_ad.buffer)) {
                        _asz = buffer_get_size(_ad.buffer);
                        if (_asz > 0 && buffer_peek(_ad.buffer, _asz - 1, buffer_u8) == 0) _asz--;
                    }
                    var _s = clamp(_start_off, 0, _asz);
                    var _e = (_end_off == 0 || _end_off > _asz) ? _asz : _end_off;
                    if (_e < _s) _e = _s;
                    _eff_len  = _e - _s;
                    _eff_addr = _ad.address + _s;
                    break;
                }
            }
        }
    }

    var _loc_end  = _eff_addr + _eff_len;
    var _loch     = string_upper(decimal_to_hex(_eff_addr));
    var _loch_end = string_upper(decimal_to_hex(_loc_end));
    while (string_length(_loch)     < 4) _loch     = "0" + _loch;
    while (string_length(_loch_end) < 4) _loch_end = "0" + _loch_end;

    var _align_h_labels = ["DEF", "LEFT", "CENT", "RGHT"];
    var _align_v_labels = ["DEF", "TOP", "MID", "BOT"];
    var _col_x_determined = (_align_h != 0);
    var _col_y_determined = (_align_v != 0);

    var _c_edit = make_color_rgb(120, 220, 120);
    var _c_dim  = make_color_rgb(120, 120, 120);
    var _c_warn = make_color_rgb(200, 60, 60);

    draw_set_font(fnt_c64_tiny);
    var _ply = _y + _header_h + 4;

    // Row 1: X / Y / LOC
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "X:");
    draw_set_color(_col_x_determined ? make_color_rgb(220, 40, 220) : c_aqua);
    draw_text(_draw_x + 28, _ply, string(_sx));
    draw_set_color(_c_edit);
    draw_text(_draw_x + 65, _ply, "Y:");
    draw_set_color(_col_y_determined ? make_color_rgb(220, 40, 220) : c_aqua);
    draw_text(_draw_x + 85, _ply, string(_sy));

    // LOC field is dim in asset mode (driven by asset addr + start offset)
    if (_src_mode == 1) {
        draw_set_color(_c_dim);
        draw_text(_draw_x + 115, _ply, "LOC:");
        draw_set_color(make_color_rgb(100, 120, 100));
        draw_text(_draw_x + 148, _ply, "$" + _loch);
    } else {
        draw_set_color(_c_edit);
        draw_text(_draw_x + 115, _ply, "LOC:");
        draw_set_color(c_aqua);
        draw_text(_draw_x + 148, _ply, "$" + _loch);
    }
    _ply += _line_h;

    // Row 2: COL + resolved screen address
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "COL:");
    draw_set_color(scr_c64_pepto_colour(_col));
    draw_rectangle(_draw_x + 50, _ply + 5, _draw_x + 70, _ply + _line_h, false);
    draw_set_color(c_yellow);
    draw_text(_draw_x + 76, _ply, string(_col));

    var _cell_off = (_sy * 40) + _sx;
    var _scr_addr = _scr_base + _cell_off;
    var _col_addr = 0xD800 + _cell_off;
    var _scr_hex = string_upper(decimal_to_hex(_scr_addr));
    var _col_hex = string_upper(decimal_to_hex(_col_addr));
    while (string_length(_scr_hex) < 4) _scr_hex = "0" + _scr_hex;
    while (string_length(_col_hex) < 4) _col_hex = "0" + _col_hex;

    draw_set_font(fnt_c64_nano);
    draw_set_color(_c_dim);
    draw_text(_draw_x + 100, _ply + 3, "ADDR:");
    draw_set_color(c_orange);
    draw_text(_draw_x + 130, _ply + 3, "$" + _scr_hex + " $" + _col_hex);
    _ply += _line_h;

    // Row 2b: SCR BASE (VIC screen-matrix base for the copy loop)
    var _base_hex = string_upper(decimal_to_hex(_scr_base));
    while (string_length(_base_hex) < 4) _base_hex = "0" + _base_hex;
    var _base_editing = (obj_workspace_manager.is_entering_text &&
                         obj_workspace_manager.input_target_node  == id &&
                         obj_workspace_manager.input_target_index == 13);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "SCR BASE:");
    if (_base_editing) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 80, _ply, "$" + obj_workspace_manager.current_input_string);
    } else {
        draw_set_color(c_aqua);
        draw_text(_draw_x + 80, _ply, "$" + _base_hex);
    }
    _ply += _line_h;

    draw_set_font(fnt_c64_tiny);
    // Row 3: CLR toggle
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "PRE-CLEAR?: ");
    draw_text(_draw_x + 8 + string_width("PRE-CLEAR?: "), _ply, _clr ? "YES" : "NO");
    _ply += _line_h;

    // Row 4: H-ALIGN buttons
    draw_set_color(c_ltgray);
    draw_text(_draw_x + 8, _ply, "H:");
    var _btn_w = 34;
    for (var _i = 0; _i < 4; _i++) {
        var _bx  = _draw_x + 28 + (_i * (_btn_w + 2));
        var _sel = (_align_h == _i);
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, _ply, _bx + _btn_w, _ply + 14);
        draw_set_color(_sel ? make_color_rgb(220, 40, 220) : (_hov ? make_color_rgb(80, 60, 80) : make_color_rgb(40, 30, 40)));
        draw_rectangle(_bx, _ply + 3, _bx + _btn_w, _ply + 14, false);
        draw_set_color(_sel ? c_white : c_gray);
        draw_set_halign(fa_center);
        draw_text(_bx + _btn_w * 0.5, _ply, _align_h_labels[_i]);
        draw_set_halign(fa_left);
    }
    _ply += _line_h;

    // Row 5: V-ALIGN buttons
    draw_set_color(c_ltgray);
    draw_text(_draw_x + 8, _ply, "V:");
    for (var _i = 0; _i < 4; _i++) {
        var _bx  = _draw_x + 28 + (_i * (_btn_w + 2));
        var _sel = (_align_v == _i);
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, _ply, _bx + _btn_w, _ply + 14);
        draw_set_color(_sel ? make_color_rgb(220, 40, 220) : (_hov ? make_color_rgb(80, 60, 80) : make_color_rgb(40, 30, 40)));
        draw_rectangle(_bx, _ply + 3, _bx + _btn_w, _ply + 14, false);
        draw_set_color(_sel ? c_white : c_gray);
        draw_set_halign(fa_center);
        draw_text(_bx + _btn_w * 0.5, _ply, _align_v_labels[_i]);
        draw_set_halign(fa_left);
    }
    _ply += _line_h;
    _ply += _line_h / 2;

    // Row 6: SOURCE toggle
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "SOURCE:");
    draw_set_color(_src_mode == 0 ? c_aqua : c_lime);
    draw_text(_draw_x + 60, _ply, _src_mode == 0 ? "INLINE" : "ASSET");
    _ply += _line_h;

    // Row 7: content row — inline text field OR asset picker
    if (_src_mode == 0) {
        // INLINE — original text field
        var _editing  = (obj_workspace_manager.is_entering_text &&
                         obj_workspace_manager.input_target_node  == id &&
                         obj_workspace_manager.input_target_index == 5);
        var _txt_hover = point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ply+3, _draw_x + width - 8, _ply + 17);
        draw_set_color(_editing   ? make_color_rgb(40, 80, 70)  :
                      (_txt_hover ? make_color_rgb(33, 70, 60)  : make_color_rgb(15, 25, 15)));
        draw_rectangle(_draw_x + 4, _ply+3, _draw_x + width - 8, _ply + 17, false);
        if (_editing) {
            var _live    = obj_workspace_manager.current_input_string;
            var _cur_pos = obj_workspace_manager.cursor_pos;
            var _before  = string_copy(_live, 1, _cur_pos);
            var _cur_x   = _draw_x + 8 + string_width(_before);
            draw_set_color(c_lime);
            draw_text(_draw_x + 8, _ply, _live);
            if ((current_time mod 600) < 300) {
                draw_set_color(c_white);
                draw_line(_cur_x, _ply, _cur_x, _ply + 14);
            }
        } else {
            var _max_w   = width - 24;
            var _display = _txt;
            while (string_length(_display) > 0 && string_width(_display) > _max_w) {
                _display = string_copy(_display, 1, string_length(_display) - 1);
            }
            draw_set_color(_txt == "" ? _c_edit : c_lime);
            draw_text(_draw_x + 8, _ply+2, _txt == "" ? "CLICK TO ENTER TEXT" : _display);
        }
        _ply += _line_h + 8;
    } else {
        // ASSET — name display + start/end rows
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "ASSET:");
        draw_set_color(_asset_nm == "" ? c_orange : c_lime);
        draw_text(_draw_x + 60, _ply, _asset_nm == "" ? "< NONE >" : _asset_nm);
        _ply += _line_h;

        var _s_vmode = (array_length(instructions[0]) > 14 && is_real(instructions[0][14])) ? real(instructions[0][14]) : 0;
        var _s_vname = (array_length(instructions[0]) > 15) ? string(instructions[0][15]) : "";
        var _e_vmode = (array_length(instructions[0]) > 16 && is_real(instructions[0][16])) ? real(instructions[0][16]) : 0;
        var _e_vname = (array_length(instructions[0]) > 17) ? string(instructions[0][17]) : "";

        // START
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "START:");
        if (_s_vmode == 1) {
            draw_set_color(c_yellow);
            draw_text(_draw_x + 60, _ply, (_s_vname != "") ? scr_nloc_display_name(_s_vname) : "<PICK>");
        } else {
            draw_set_color(c_aqua);
            draw_text(_draw_x + 60, _ply, string(_start_off));
        }
        var _svb_x = _draw_x + width - 40;
        draw_set_color((_s_vmode == 1) ? make_color_rgb(180, 140, 30) : make_color_rgb(50, 50, 60));
        draw_rectangle(_svb_x, _ply + 1, _svb_x + 28, _ply + 12, false);
        draw_set_color((_s_vmode == 1) ? c_yellow : make_color_rgb(140, 140, 160));
        draw_set_halign(fa_center);
        draw_text(_svb_x + 14, _ply, "VAR");
        draw_set_halign(fa_left);
        _ply += _line_h;

        // END (0 = auto / to end)
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "END:");
        if (_e_vmode == 1) {
            draw_set_color(c_yellow);
            draw_text(_draw_x + 60, _ply, (_e_vname != "") ? scr_nloc_display_name(_e_vname) : "<PICK>");
        } else {
            draw_set_color(_end_off == 0 ? _c_dim : c_aqua);
            draw_text(_draw_x + 60, _ply, _end_off == 0 ? "AUTO" : string(_end_off));
        }
        var _evb_x = _draw_x + width - 40;
        draw_set_color((_e_vmode == 1) ? make_color_rgb(180, 140, 30) : make_color_rgb(50, 50, 60));
        draw_rectangle(_evb_x, _ply + 1, _evb_x + 28, _ply + 12, false);
        draw_set_color((_e_vmode == 1) ? c_yellow : make_color_rgb(140, 140, 160));
        draw_set_halign(fa_center);
        draw_text(_evb_x + 14, _ply, "VAR");
        draw_set_halign(fa_left);
        _ply += _line_h;
        _ply += 8;
    }

    // Row 8: byte count / range
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(80, 120, 180));
    draw_text(_draw_x + 8, _ply, string(_eff_len) + " BYTES   $" + _loch + " -> $" + _loch_end);
    draw_text(_draw_x + 7, _ply + 12, "IF MC MODE USE UPPER 8 COLS");
    if (_src_mode == 1) {
        draw_set_color(make_color_rgb(230, 160, 30));
        draw_text(_draw_x + 7, _ply + 24, "USE WORD TYPES FOR START / END");
    }
}