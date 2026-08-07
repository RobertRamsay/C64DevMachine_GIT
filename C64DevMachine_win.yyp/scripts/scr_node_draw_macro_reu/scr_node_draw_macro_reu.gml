/// @desc Draw body content for MACRO_REU node. Slots 0-8 are the original
/// DIRECT layout; 9=mode, 10=LOAD_REU name, 11=linked asset name,
/// 12=INDEXED index var name, 13=INDEXED size mode (0 CUSTOM, 1 HRBITMAP, 2 MCBITMAP),
/// 14=INDEXED ZP scratch base (2 bytes, only used when the index var is WORD-encoded).
function scr_node_draw_macro_reu(_draw_x, _y) {
    var _hh = 24, _lh = 16, _inst = instructions[0];
    while (array_length(_inst) < 15) {
        var _ni = array_length(_inst);
        if (_ni == 13) { array_push(_inst, 2); }
        else if (_ni == 14) { array_push(_inst, 0x03); }
        else if (_ni >= 10) { array_push(_inst, ""); }
        else { array_push(_inst, 0); }
    }
    var _mode = is_real(_inst[9]) ? real(_inst[9]) : 0;
    var _lx = _draw_x + 8, _rx = _draw_x + width - 6, _cy = _y + _hh + 4;
    var _button = function(_label, _x1, _x2, _yy, _col) {
        var _hov = point_in_rectangle(mouse_x, mouse_y, _x1, _yy + 4, _x2, _yy + 10);
        draw_set_color(_hov ? merge_color(_col, c_white, 0.25) : _col);
        draw_rectangle(_x1, _yy + 1, _x2, _yy + 11, false);
        draw_set_color(c_white); draw_set_halign(fa_center); draw_text((_x1 + _x2) * 0.5, _yy, _label); draw_set_halign(fa_left);
    };
    var _hex = function(_v, _digits) {
        var _s = string_upper(decimal_to_hex(real(_v)));
        while (string_length(_s) < _digits) _s = "0" + _s;
        return "$" + _s;
    };

    draw_set_font(fnt_C64_Angled_tiny);
    draw_set_color(c_gray); draw_text(_lx, _cy, "MODE:");
    var _mode_label = "DIRECT";
    var _mode_col   = make_color_rgb(40,30,70);
    if (_mode == 1) { _mode_label = "ASSET";   _mode_col = make_color_rgb(30,90,75); }
    if (_mode == 2) { _mode_label = "INDEXED"; _mode_col = make_color_rgb(80,60,20); }
    _button(_mode_label, _lx + 44, _rx, _cy, _mode_col);
    _cy += _lh;

    if (_mode == 2) {
        draw_set_color(c_gray); draw_text(_lx, _cy, "REU:");
        _button(string(_inst[10]) != "" ? string(_inst[10]) : "<SELECT LOAD_REU>", _lx + 44, _rx, _cy, make_color_rgb(25,65,60));
        _cy += _lh;
        draw_set_color(c_gray); draw_text(_lx, _cy, "INDEX:");
        _button(string(_inst[12]) != "" ? string(_inst[12]) : "<SELECT VAR>", _lx + 44, _rx, _cy, make_color_rgb(25,65,60));
        _cy += _lh;
        var _size_mode = is_real(_inst[13]) ? real(_inst[13]) : 2;
        var _size_labels = ["CUSTOM", "HRBITMAP", "MCBITMAP"];
        var _size_cols   = [make_color_rgb(70,40,40), make_color_rgb(40,70,40), make_color_rgb(40,50,80)];
        draw_set_color(c_gray); draw_text(_lx, _cy, "SIZE:");
        _button(_size_labels[clamp(_size_mode,0,2)], _lx + 44, _rx, _cy, _size_cols[clamp(_size_mode,0,2)]);
        _cy += _lh;
        if (_size_mode == 0) {
            draw_set_color(c_gray); draw_text(_lx, _cy, "LEN:");
            _button(_hex(_inst[5],4), _lx+44,_rx,_cy,make_color_rgb(34,44,64));
            _cy += _lh;
        }
        var _idx_meta    = scr_nloc_find_meta(string(_inst[12]));
        var _idx_is_word = (!is_undefined(_idx_meta) && variable_struct_exists(_idx_meta, "encoding") && _idx_meta.encoding == "word");
        var _idx_cap     = _idx_is_word ? 65536 : 256;
        if (_idx_is_word) {
            draw_set_color(c_gray); draw_text(_lx, _cy, "ZP:");
            _button(_hex(_inst[14],2), _lx+44,_rx,_cy,make_color_rgb(34,44,64));
            _cy += _lh;
        }
        var _idx_manifest = scr_reu_find_asset(string(_inst[10]));
        var _idx_count = 0;
        if (!is_undefined(_idx_manifest) && variable_struct_exists(_idx_manifest, "linked_assets")) {
            var _idx_links = _idx_manifest.linked_assets;
            for (var _ii = 0; _ii < array_length(_idx_links); _ii++) {
                var _idx_asset = scr_reu_find_asset(_idx_links[_ii].asset_name);
                if (!is_undefined(_idx_asset) && (_idx_asset.type == "BITMAP" || _idx_asset.type == "BITMAP_KLA")) _idx_count++;
            }
        }
        draw_set_color(c_gray); draw_text(_lx, _cy, "SLOTS:");
        draw_set_color((_idx_count > 0 && _idx_count <= _idx_cap) ? c_lime : c_red);
        draw_text(_lx + 60, _cy, string(_idx_count) + "/" + string(_idx_cap) + (_idx_is_word ? " (WORD)" : " (BYTE)"));
        _cy += _lh;
    } else if (_mode == 1) {
        draw_set_color(c_gray); draw_text(_lx, _cy, "REU:");
        _button(string(_inst[10]) != "" ? string(_inst[10]) : "<SELECT LOAD_REU>", _lx + 44, _rx, _cy, make_color_rgb(25,65,60));
        _cy += _lh;
        draw_set_color(c_gray); draw_text(_lx, _cy, "ASSET:");
        _button(string(_inst[11]) != "" ? string(_inst[11]) : "<SELECT ASSET>", _lx + 44, _rx, _cy, make_color_rgb(25,65,60));
        _cy += _lh;
        var _resolved = scr_reu_resolve(string(_inst[10]), string(_inst[11]));
        draw_set_color(c_gray); draw_text(_lx, _cy, "C64:");
        draw_set_color(_resolved.found ? c_yellow : c_red); draw_text(_lx + 44, _cy, _resolved.found ? _hex(_resolved.c64_address, 4) : "UNRESOLVED");
        _cy += _lh;
        draw_set_color(c_gray); draw_text(_lx, _cy, "REU:");
        draw_set_color(_resolved.found ? c_aqua : c_red); draw_text(_lx + 44, _cy, _resolved.found ? _hex(_resolved.reu_address, 6) : "UNRESOLVED");
        _cy += _lh;
        draw_set_color(c_gray); draw_text(_lx, _cy, "LEN:");
        draw_set_color(_resolved.found ? c_lime : c_red); draw_text(_lx + 44, _cy, _resolved.found ? _hex(_resolved.size, 4) : "UNRESOLVED");
        _cy += _lh;
    } else {
        var _ops = ["STASH (C64->REU)", "FETCH (REU->C64)", "SWAP", "COMPARE"];
        draw_set_color(c_gray); draw_text(_lx, _cy, "OP:");
        _button(_ops[clamp(real(_inst[1]),0,3)], _lx + 30, _rx, _cy, make_color_rgb(40,30,70)); _cy += _lh;
        draw_set_color(c_gray); draw_text(_lx, _cy, "C64:"); _button(_hex(_inst[2],4), _lx+44,_rx,_cy,make_color_rgb(34,44,64)); _cy += _lh;
        draw_set_color(c_gray); draw_text(_lx, _cy, "REU:"); _button(_hex(_inst[3],4), _lx+44,_rx,_cy,make_color_rgb(34,44,64)); _cy += _lh;
        draw_set_color(c_gray); draw_text(_lx, _cy, "BANK:"); _button(string(real(_inst[4])), _lx+44,_rx,_cy,make_color_rgb(34,44,64)); _cy += _lh;
        draw_set_color(c_gray); draw_text(_lx, _cy, "LEN:"); _button(_hex(_inst[5],4), _lx+44,_rx,_cy,make_color_rgb(34,44,64)); _cy += _lh;
    }

    _button((real(_inst[6]) == 1) ? "AUTOLOAD: ON" : "AUTOLOAD: OFF", _lx,_rx,_cy,make_color_rgb(45,45,30)); _cy += _lh;
    _button((real(_inst[7]) == 1) ? "FIX C64 ADDR: ON" : "FIX C64 ADDR: OFF", _lx,_rx,_cy,make_color_rgb(45,45,30)); _cy += _lh;
    _button((real(_inst[8]) == 1) ? "FIX REU ADDR: ON" : "FIX REU ADDR: OFF", _lx,_rx,_cy,make_color_rgb(45,45,30));
}
