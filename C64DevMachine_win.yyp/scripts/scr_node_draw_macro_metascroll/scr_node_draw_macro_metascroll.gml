/// @desc Draw MACRO_METASCROLL node
function scr_node_draw_macro_metascroll(_draw_x, _draw_y, _cam_x, _cam_y, _cam_zoom) {

    // instructions[0] layout:
    //   [0]="MACRO_METASCROLL" [1]=tileset_name [2]=map_index
    //   [3]=base_addr [4]=zp_base [5]=clamp

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
    var _planes   = 1;
    if (_col_mode == 1) {
        _planes = 2;
    }

    var _px = _draw_x + 8;
    var _ly = _draw_y + 24 + 4;
    var _lh = 18;
    draw_set_font(fnt_c64_code);

    // ROW 0 - TILESET
    draw_set_color(c_gray);
    draw_text(_px, _ly, "TILESET:");
    var _ts_col = c_aqua;
    var _ts_txt = _ts_name;
    if (_ts_name == "") {
        _ts_col = c_red;
        _ts_txt = "<PICK>";
    }
    draw_set_color(_ts_col);
    draw_text(_px + 64, _ly, _ts_txt);
    _ly += _lh;

    // ROW 1 - MAP INDEX
    draw_set_color(c_gray);
    draw_text(_px, _ly, "MAP:");
    draw_set_color(c_aqua);
    draw_text(_px + 42, _ly, string(_map_index));
    draw_set_color(make_color_rgb(70, 130, 140));
    draw_text(_px + 80, _ly, "/ " + string(max(0, _map_count - 1)));
    draw_set_color(c_gray);
    draw_text(_draw_x + width - 130, _ly, string(_mapw) + "x" + string(_maph) + " CH");
    _ly += _lh;

    // ROW 2 - PLANE ADDRESSES
    draw_set_color(c_gray);
    draw_text(_px, _ly, "PLANES:");
    draw_set_color(c_yellow);
    var _pl_txt = "$" + string_upper(decimal_to_hex(_base_addr));
    if (_col_mode == 1) {
        _pl_txt = _pl_txt + " / $" + string_upper(decimal_to_hex(_co_base));
    }
    draw_text(_px + 64, _ly, _pl_txt);
    _ly += _lh;

    // ROW 3 - SIZE
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(180, 100, 30));
    var _sz_txt = "USES " + string(_plane_sz) + " BYTES (CHAR PLANE)";
    if (_col_mode == 1) {
        _sz_txt = "USES " + string(_plane_sz * 2) + " BYTES (CHAR + COLOUR PLANES)";
    }
    draw_text(_px, _ly, _sz_txt);
    draw_set_font(fnt_c64_code);
    _ly += _lh;

    // ROW 4 - ZP
    draw_set_color(c_gray);
    draw_text(_px, _ly, "ZP BASE:");
    draw_set_color(c_aqua);
    draw_text(_px + 140, _ly, "$" + string_upper(decimal_to_hex(_zp)));
    draw_set_color(make_color_rgb(70, 130, 140));
    draw_text(_px + 180, _ly, "(10 BYTES)");
    _ly += _lh;

    // ROW 5 - COLOUR MODE
    draw_set_color(c_gray);
    draw_text(_px, _ly, "COLOUR:");
    var _cm_col = c_lime;
    var _cm_txt = "FIXED";
    if (_col_mode == 1) {
        _cm_col = c_orange;
        _cm_txt = "SHIFT";
    }
    draw_set_color(_cm_col);
    draw_text(_px + 140, _ly, _cm_txt);
    draw_set_color(make_color_rgb(70, 130, 140));
    if (_col_mode == 1) {
        draw_text(_px + 200, _ly, "2-FRAME COARSE");
    } else {
        var _fc_txt = "AUTO";
        if (_fixed_col >= 0) {
            _fc_txt = "$" + string_upper(decimal_to_hex(_fixed_col & 0x0F));
        }
        draw_text(_px + 200, _ly, "NIBBLE " + _fc_txt);
    }
    _ly += _lh;

    // ROW 6 - CLAMP
    draw_set_color(c_gray);
    draw_text(_px, _ly, "CLAMP EDGES:");
    var _cl_col = c_gray;
    var _cl_txt = "OFF";
    if (_clamp == 1) {
        _cl_col = c_lime;
        _cl_txt = "ON";
    }
    draw_set_color(_cl_col);
    draw_text(_px + 140, _ly, _cl_txt);
    _ly += _lh;

    // ROW 7..9 - entry points
    draw_set_color(c_gray);
    draw_text(_px, _ly, "JSR L/R :");
    draw_set_color(c_yellow);
    draw_text(_px + 90, _ly, "Metascroll_L  Metascroll_R");
    _ly += _lh;

    draw_set_color(c_gray);
    draw_text(_px, _ly, "JSR U/D :");
    draw_set_color(c_yellow);
    draw_text(_px + 90, _ly, "Metascroll_U  Metascroll_D");
    _ly += _lh;

    draw_set_color(c_gray);
    draw_text(_px, _ly, "EVERY FR:");
    draw_set_color(c_yellow);
    draw_text(_px + 90, _ly, "Metascroll_Update");
    _ly += _lh;

    // ROW 10 - register ownership
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(100, 100, 160));
    draw_text(_px, _ly, "OWNS $D016 BITS 0-2 AND $D011 BITS 0-2 (38 COL / 24 ROW)");
    draw_set_font(fnt_c64_code);
}
