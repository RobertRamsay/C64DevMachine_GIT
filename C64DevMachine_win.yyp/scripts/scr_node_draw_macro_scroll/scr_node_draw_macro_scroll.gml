function scr_node_draw_macro_scroll(_draw_x, _y, _cam_x, _cam_y, _cam_zoom) {

// instructions[0] canonical index layout:
    //   [0]="MACRO_SCROLL" [1]=start_row [2]=row_count [3]=colour_mode
    //   [4]=use_sid_irq    [5]=speed     [6]=scroll_text (string, inline)
    //   [7]=direction      [8]=text_src (0=inline,1=asset) [9]=asset_name (string)

    // Ensure scroll_alias is set for older nodes that predate the alias system
    if (!variable_instance_exists(id, "scroll_alias") || scroll_alias == "") {
        scroll_alias = "scr" + string(instance_number(obj_c64_node));
    }

    var _start_row = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 4;
    var _row_count = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 16;
    var _col_mode  = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 1;
    var _use_sid   = (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) ? real(instructions[0][4]) : 0;
    var _speed     = (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) ? real(instructions[0][5]) : 2;
    var _dir       = (array_length(instructions[0]) > 7 && is_real(instructions[0][7])) ? real(instructions[0][7]) : 0;

    // Register secondary memory regions for overlap detection
    if (!variable_instance_exists(id, "extra_regions")) extra_regions = [];
    // scr2 is scr1 + $0800 — derive from MACRO_VIC if present
    var _scr1_draw = 0x0400;
    with (obj_c64_node) {
        if (node_type == "MACRO_VIC" && is_connected) {
            var _vm = string(instructions[0][1]);
            if (_vm == "BITMAP" || _vm == "BMP" || _vm == "MCB") {
                _scr1_draw = (is_real(instructions[0][4]) ? real(instructions[0][4]) : 0x4000) + 0x2000;
            } else {
                _scr1_draw = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0x0400;
            }
            break;
        }
    }
    extra_regions = [{ addr: _scr1_draw + 0x0800, size: 0x0400 }]; // screen buffer 2
	
// Check for MACRO_SID in scene and connected (needed for USE SID IRQ row warning)
    var _sid_present = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected) { _sid_present = true; break; }
    }

    var _col_labels  = ["NONE", "DEFERRED", "INLINE"];
    var _col_str     = _col_labels[clamp(_col_mode, 0, 2)];
    var _inline_warn = (_col_mode == 2 && _row_count > 8);

    var _px = _draw_x + 8;
    var _ly = _y + 24 + 4;
    var _lh = 18;
    draw_set_font(fnt_c64_code);

    // ROW 0 — START ROW
    draw_set_color(c_gray);
    draw_text(_px,       _ly, "START ROW:");
    draw_set_color(c_aqua);
    draw_text(_px + 100, _ly, string(_start_row));
    _ly += _lh;

// ROW 1 — ROW COUNT
    draw_set_color(c_gray);
    draw_text(_px,       _ly, "ROW COUNT:");
    draw_set_color(c_aqua);
    draw_text(_px + 100, _ly, string(_row_count));
    draw_set_color(make_color_rgb(70, 130, 140));
    draw_text(_px + 130, _ly, string(_start_row) + " to " + string(_start_row + _row_count - 1));
    _ly += _lh;

    // ROW 2 — COLOUR MODE (click to cycle 0→1→2→0)
    var _cm_col;
    if      (_col_mode == 0)    { _cm_col = c_gray; }
    else if (_col_mode == 1)    { _cm_col = c_yellow; }
    else if (_inline_warn)      { _cm_col = c_orange; }
    else                        { _cm_col = c_lime; }
    draw_set_color(c_gray);
    draw_text(_px, _ly, "COLOUR:");
    draw_set_color(_cm_col);
    draw_text(_px + 76, _ly, _col_str);
    if (_inline_warn) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_orange);
        draw_text(_px + 76 + string_width(_col_str) + 6, _ly + 2, "! >8 ROWS");
        draw_set_font(fnt_c64_code);
    }
    _ly += _lh;

    // ROW 3 — SPEED (click to cycle 1-8)
    draw_set_color(c_gray);
    draw_text(_px, _ly, "SPEED = 1px per JSR");
    _ly += _lh;

    // ROW 4 — JSR entry points (read-only)
    draw_set_color(c_gray);
    draw_text(_px, _ly, "JSR LEFT :");
    draw_set_color(c_yellow);
    draw_text(_px + 90, _ly, "Scroller_L");
    _ly += _lh;

    draw_set_color(c_gray);
    draw_text(_px, _ly, "JSR RIGHT:");
    draw_set_color(c_yellow);
    draw_text(_px + 90, _ly, "Scroller_R");
    _ly += _lh;

    // ROW — SOURCE (click to toggle MAP_DATA <-> META_TILESET), index [6]
    var _mm_src_mode = (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) ? real(instructions[0][6]) : 0;
    draw_set_color(c_gray);
    draw_text(_px, _ly, "SOURCE:");
    draw_set_color(c_aqua);
    if (_mm_src_mode == 0) {
        draw_text(_px + 76, _ly, "MAP_DATA");
    } else {
        draw_text(_px + 76, _ly, "META_TILESET");
    }
    _ly += _lh;

    if (_mm_src_mode == 1) {
        var _mm_tileset_name = (array_length(instructions[0]) > 7 && is_string(instructions[0][7])) ? string(instructions[0][7]) : "";
        var _mm_map_index    = (array_length(instructions[0]) > 8 && is_real(instructions[0][8])) ? real(instructions[0][8]) : 0;

        draw_set_color(c_gray);
        draw_text(_px, _ly, "TILESET:");
        draw_set_color(c_yellow);
        if (_mm_tileset_name == "") {
            draw_text(_px + 76, _ly, "(NONE)");
        } else {
            draw_text(_px + 76, _ly, _mm_tileset_name);
        }
        _ly += _lh;

        draw_set_color(c_gray);
        draw_text(_px, _ly, "MAP IDX:");
        draw_set_color(c_aqua);
        draw_text(_px + 76, _ly, string(_mm_map_index));
        _ly += _lh;

        var _mm_base_addr = (array_length(instructions[0]) > 9 && is_real(instructions[0][9])) ? real(instructions[0][9]) : 0xA000;
        draw_set_color(c_gray);
        draw_text(_px, _ly, "BASE ADDR:");
        draw_set_color(c_aqua);
        draw_text(_px + 76, _ly, "$" + string_upper(decimal_to_hex(_mm_base_addr)));
        _ly += _lh;

        // Resolve the tileset to check for ignored colour overrides
        var _mm_has_override = false;
        if (_mm_tileset_name != "" && instance_exists(obj_asset_manager)) {
            var _mm_am = obj_asset_manager;
            for (var _mm_ai = 0; _mm_ai < ds_list_size(_mm_am.asset_list); _mm_ai++) {
                var _mm_a = ds_list_find_value(_mm_am.asset_list, _mm_ai);
                if (_mm_a.type == "META_TILESET" && _mm_a.name == _mm_tileset_name) {
                    if (variable_struct_exists(_mm_a.meta, "stamp_override")) {
                        for (var _mm_oi = 0; _mm_oi < array_length(_mm_a.meta.stamp_override); _mm_oi++) {
                            if (_mm_a.meta.stamp_override[_mm_oi] != 0x80) {
                                _mm_has_override = true;
                                break;
                            }
                        }
                    }
                    break;
                }
            }
        }
        if (_mm_has_override) {
            draw_set_font(fnt_c64_tiny);
            draw_set_color(c_orange);
            draw_text(_px, _ly, "! STAMP COLOUR OVERRIDES IGNORED");
            draw_set_font(fnt_c64_code);
            _ly += _lh;
        }
    }

/*
    // ROW 5 — USE SID IRQ (checkbox)
    var _chk_x      = _px;
    var _chk_y      = _ly + 2;
    var _chk_active = (_use_sid == 1) && _sid_present;
    var _chk_col;
    if      (_chk_active)                { _chk_col = c_lime; }
    else if (_use_sid == 1 && !_sid_present) { _chk_col = c_orange; }
    else                                 { _chk_col = make_color_rgb(50, 50, 50); }
    draw_set_color(_chk_col);
    draw_rectangle(_chk_x, _chk_y, _chk_x + 14, _chk_y + 14, false);
    if (_use_sid == 1) {
        draw_set_color(_sid_present ? c_black : c_orange);
        draw_line(_chk_x + 2,  _chk_y + 7,  _chk_x + 6,  _chk_y + 12);
        draw_line(_chk_x + 6,  _chk_y + 12, _chk_x + 12, _chk_y + 2);
    }
    draw_set_font(fnt_c64_tiny);
    var _lbl_col;
    if      (!_sid_present) { _lbl_col = c_orange; }
    else if (_chk_active)   { _lbl_col = c_lime; }
    else                    { _lbl_col = c_gray; }
    draw_set_color(_lbl_col);
    draw_text(_chk_x + 18, _chk_y + 1,
              _sid_present ? "USE SID IRQ" : "USE SID IRQ (NO SID NODE)");
    draw_set_font(fnt_c64_code);
    _ly += _lh;
	*/

// ROW 6 —     // (no text rows — use MACRO_TEXT_SCROLL for scrolling text)


    // ROW 8 — IRQ raster line (read-only, derived from start_row)



    // ROW 7 — screen buffer 2 notice
    var _scr2_end = 0x0C00 + 0x0400 - 1;
    var _scr2_flash = last_overlap_check;
    var _scr2_col;
    if (_scr2_flash) {
        var _scr2_pulse = (sin(current_time * 0.012) + 1) * 0.5;
        _scr2_col = make_color_rgb(
            lerp(0,   255, _scr2_pulse),
            lerp(0,   255, _scr2_pulse),
            lerp(0,   255, _scr2_pulse)
        );
    } else {
        _scr2_col = make_color_rgb(180, 140, 40);
    }
draw_set_font(fnt_c64_tiny);
    draw_set_color(_scr2_col);
    var _scr2_display = _scr1_draw + 0x0800;
    draw_text(_px, _ly, "USES $" + string_upper(decimal_to_hex(_scr2_display)) + "-$" + string_upper(decimal_to_hex(_scr2_display + 0x03FF)) + " (SCR BUF 2)");

    draw_set_font(fnt_c64_code);
}
