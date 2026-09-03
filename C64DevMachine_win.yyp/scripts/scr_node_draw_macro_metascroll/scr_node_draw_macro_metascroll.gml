/// @desc Draw MACRO_METASCROLL node
function scr_node_draw_macro_metascroll(_draw_x, _draw_y, _cam_x, _cam_y, _cam_zoom) {

    // instructions[0] layout:
    //   [0]="MACRO_METASCROLL" [1]=tileset_name [2]=map_index
    //   [3]=base_addr [4]=zp_base [5]=clamp [6]=colour_mode [7]=fixed_nibble

    var _ts_name   = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
    var _map_index = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 0;
    var _base_addr = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 0x4000;
    var _zp        = (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) ? real(instructions[0][4]) : 0x60;
    var _clamp     = (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) ? real(instructions[0][5]) : 1;
    var _col_mode  = (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) ? real(instructions[0][6]) : 0;
    var _fixed_col = (array_length(instructions[0]) > 7 && is_real(instructions[0][7])) ? real(instructions[0][7]) : -1;

    // Resolve the tileset so the node can show the real map size
    var _map_count = 0;
    var _mapw      = 0;
    var _maph      = 0;
    if (_ts_name != "" && instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "META_TILESET" && _a.name == _ts_name) {
                var _tm = _a.meta;
                _map_count = _tm.map_count;
                if (_map_index >= 0 && _map_index < _tm.map_count) {
                    var _lit_w_ch = 40;
                    if (_map_index < array_length(_tm.map_w)) _lit_w_ch = _tm.map_w[_map_index];
                    var _cg = floor(_lit_w_ch / _tm.stamp_w);
                    if (_cg < 1) _cg = 1;
                    var _rg = floor(array_length(_tm.maps[_map_index]) / _cg);
                    _mapw = _cg * _tm.stamp_w;
                    _maph = _rg * _tm.stamp_h;
                }
                break;
            }
        }
    }

    var _plane_sz = _mapw * _maph;
    var _pages    = ceil(_plane_sz / 256);
    var _co_base  = _base_addr + _pages * 256;
    var _bytes    = _plane_sz;
    if (_col_mode == 1) {
        _bytes = _plane_sz * 2;
    }

    // ── Layout ───────────────────────────────────────────
    // Everything is measured off the node's own width, so nothing spills
    // past the right edge when the node is narrow.
    var _lx  = _draw_x + 8;                                  // label column
    var _rx  = _draw_x + width - 8;                          // hard right edge
    var _vx  = _draw_x + 8 + max(56, floor(width * 0.34));   // value column
    if (_vx > _rx - 40) {
        _vx = _rx - 40;
    }
    var _mid = _vx + floor((_rx - _vx) * 0.5);               // second value column
    var _ly  = _draw_y + 24 + 4;
    var _lh  = 18;

    msc_entry_rects = [];

    draw_set_font(fnt_c64_code);
    draw_set_halign(fa_left);

    // ROW 0 — TILESET
    draw_set_color(c_gray);
    draw_text(_lx, _ly, "TILESET:");
    var _ts_col = c_aqua;
    var _ts_txt = _ts_name;
    if (_ts_name == "") {
        _ts_col = c_red;
        _ts_txt = "<PICK>";
    }
    draw_set_color(_ts_col);
    draw_text_ext(_vx, _ly, _ts_txt, _lh, _rx - _vx);
    _ly += _lh;

    // ROW 1 — MAP index, with the resolved size on the right
    draw_set_color(c_gray);
    draw_text(_lx, _ly, "MAP:");
    draw_set_color(c_aqua);
    draw_text(_vx, _ly, string(_map_index) + " / " + string(max(0, _map_count - 1)));
    draw_set_color(make_color_rgb(70, 130, 140));
    draw_set_halign(fa_right);
    draw_text(_rx, _ly, string(_mapw) + "x" + string(_maph) + " CH");
    draw_set_halign(fa_left);
    _ly += _lh;

    // ROW 2 — plane base, plus the colour plane only when there is one
    draw_set_color(c_gray);
    draw_text(_lx, _ly, "PLANES:");
    draw_set_color(c_yellow);
    var _pl_txt = "$" + string_upper(decimal_to_hex(_base_addr));
    if (_col_mode == 1) {
        _pl_txt = _pl_txt + " / $" + string_upper(decimal_to_hex(_co_base));
    }
    draw_text(_vx, _ly, _pl_txt);
    _ly += _lh;

    // ROW 3 — memory cost
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(180, 100, 30));
    var _sz_txt = string(_bytes) + " BYTES, CHAR PLANE";
    if (_col_mode == 1) {
        _sz_txt = string(_bytes) + " BYTES, CHAR + COLOUR";
    }
    draw_text(_lx, _ly, _sz_txt);
    draw_set_font(fnt_c64_code);
    _ly += _lh;

    // ROW 4 — ZP base
    draw_set_color(c_gray);
    draw_text(_lx, _ly, "ZP BASE:");
    draw_set_color(c_aqua);
    draw_text(_vx, _ly, "$" + string_upper(decimal_to_hex(_zp)));
    draw_set_color(make_color_rgb(70, 130, 140));
    draw_set_halign(fa_right);
    draw_text(_rx, _ly, "10 BYTES");
    draw_set_halign(fa_left);
    _ly += _lh;

    // ROW 5 — colour mode, with the fixed nibble beside it
    draw_set_color(c_gray);
    draw_text(_lx, _ly, "COLOUR:");
    var _cm_col = c_lime;
    var _cm_txt = "FIXED";
    if (_col_mode == 1) {
        _cm_col = c_orange;
        _cm_txt = "SHIFT";
    }
    draw_set_color(_cm_col);
    draw_text(_vx, _ly, _cm_txt);
    draw_set_color(make_color_rgb(70, 130, 140));
    draw_set_halign(fa_right);
    if (_col_mode == 1) {
        draw_text(_rx, _ly, "2-FRAME");
    } else {
        var _fc_txt = "AUTO";
        if (_fixed_col >= 0) {
            _fc_txt = "$" + string_upper(decimal_to_hex(_fixed_col & 0x0F));
        }
        draw_text(_rx, _ly, "NIB " + _fc_txt);
    }
    draw_set_halign(fa_left);
    _ly += _lh;

    // ROW 6 — clamp
    draw_set_color(c_gray);
    draw_text(_lx, _ly, "CLAMP:");
    var _cl_col = c_gray;
    var _cl_txt = "OFF";
    if (_clamp == 1) {
        _cl_col = c_lime;
        _cl_txt = "ON";
    }
    draw_set_color(_cl_col);
    draw_text(_vx, _ly, _cl_txt);
    _ly += _lh;

    // ROWS 7-9 — the JSR entry points. Each name is clickable and drops a
    // ready-made JSR node, so its rect is recorded for the step event.
    draw_set_color(c_gray);
    draw_text(_lx, _ly, "JSR L/R:");
    scr_msc_entry(_vx,  _ly, "MSC_L");
    scr_msc_entry(_mid, _ly, "MSC_R");
    _ly += _lh;

    draw_set_color(c_gray);
    draw_text(_lx, _ly, "JSR U/D:");
    scr_msc_entry(_vx,  _ly, "MSC_U");
    scr_msc_entry(_mid, _ly, "MSC_D");
    _ly += _lh;

    draw_set_color(c_gray);
    draw_text(_lx, _ly, "EVERY FR:");
    scr_msc_entry(_vx, _ly, "MSC_Update");
    _ly += _lh;

    // ROWS 10-11 — register ownership, split over two lines so it fits
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(100, 100, 160));
    draw_text(_lx, _ly, "OWNS $D016 + $D011 BITS 0-2");
    _ly += 10;
    draw_text(_lx, _ly, "38 COL / 24 ROW MODE");
    draw_set_font(fnt_c64_code);
    draw_set_halign(fa_left);
}

/// @desc Draw one clickable METASCROLL entry name and record its hit rect.
function scr_msc_entry(_ex, _ey, _name) {
    var _w  = string_width(_name);
    var _h  = string_height(_name);
    var _x2 = _ex + _w;
    var _y2 = _ey + _h;
    var _is_hov = point_in_rectangle(mouse_x, mouse_y, _ex - 2, _ey - 2, _x2 + 2, _y2);

    if (_is_hov) {
        draw_set_color(make_color_rgb(60, 50, 20));
        draw_rectangle(_ex - 2, _ey - 2, _x2 + 2, _y2, false);
        draw_set_color(c_white);
    } else {
        draw_set_color(c_yellow);
    }
    draw_text(_ex, _ey, _name);

    array_push(msc_entry_rects, [_ex - 2, _ey - 2, _x2 + 2, _y2, _name]);
    return _is_hov;
}
