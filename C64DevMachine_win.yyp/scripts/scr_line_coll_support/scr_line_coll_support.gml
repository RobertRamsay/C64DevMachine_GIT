/// LINE_COLL support — normalizes user-authored line segments (x1,y1,x2,y2,type)
/// into the byte-packed runtime LUT record format used by MACRO_LINE.
///
/// RECORD FORMAT (6 bytes per line):
///   byte 0: axis_flag   (0 = X-major, 1 = Y-major)
///   byte 1: major_start (X0 if X-major, Y0 if Y-major)
///   byte 2: minor_start (Y0 if X-major, X0 if Y-major)
///   byte 3: major_end   (X1 if X-major, Y1 if Y-major)
///   byte 4: slope_byte  (bit 6 = direction, bits 1-5 = gradient magnitude 0-31)
///   byte 5: type        (0-7)
///
/// Runtime walks the major axis from major_start to major_end; at each step
/// the minor axis moves by slope_byte's gradient/16, direction per bit 6.
/// This is X-major or Y-major depending on which axis has the larger span,
/// so any line direction (including vertical) is representable exactly.
///
/// Block terminator: three bytes of $FF ($FF,$FF,$FF). A normal record's
/// byte 0 is always 0 or 1, so a single $FF check on byte 0 is sufficient
/// to detect the sentinel at runtime — the extra two $FF bytes exist only
/// to keep the terminator visually/structurally distinct in raw memory.

/// @desc scr_line_coll_normalize(x1, y1, x2, y2, type)
/// Converts one raw authored line into its 6-byte packed record.
/// Returns an array of 6 bytes.
function scr_line_coll_normalize(_x1, _y1, _x2, _y2, _type) {
    var _dx = _x2 - _x1;
    var _dy = _y2 - _y1;
    var _adx = abs(_dx);
    var _ady = abs(_dy);

    var _axis_flag = 0;
    var _major_start = 0;
    var _minor_start = 0;
    var _major_end = 0;
    var _span = 0;
    var _delta = 0;

    if (_ady > _adx) {
        // Y-major: walk Y, derive X per step.
        _axis_flag = 1;
        if (_y1 <= _y2) {
            _major_start = _y1; _minor_start = _x1; _major_end = _y2; _delta = _dx;
        } else {
            _major_start = _y2; _minor_start = _x2; _major_end = _y1; _delta = -_dx;
        }
        _span = _major_end - _major_start;
    } else {
        // X-major: walk X, derive Y per step. Ties (|dx|==|dy|) default X-major.
        _axis_flag = 0;
        if (_x1 <= _x2) {
            _major_start = _x1; _minor_start = _y1; _major_end = _x2; _delta = _dy;
        } else {
            _major_start = _x2; _minor_start = _y2; _major_end = _x1; _delta = -_dy;
        }
        _span = _major_end - _major_start;
    }

    // Gradient magnitude scaled to a 5-bit field (0-31), representing
    // minor-axis movement per major-axis step in 1/16ths of a pixel.
    var _direction_bit = (_delta < 0) ? 0x40 : 0x00;
    var _gradient = (_span == 0) ? 0 : round((abs(_delta) * 16) / _span);
    _gradient = clamp(_gradient, 0, 31);
    var _slope_byte = _direction_bit | (_gradient & 0x1F);

    return [
        _axis_flag & 0xFF,
        _major_start & 0xFF,
        _minor_start & 0xFF,
        _major_end & 0xFF,
        _slope_byte & 0xFF,
        _type & 0x07
    ];
}

/// @desc scr_line_coll_compile(_lines)
/// _lines is an array of structs: {x1, y1, x2, y2, type}
/// Returns a byte array: all normalized records concatenated, followed by
/// the 3-byte $FF,$FF,$FF sentinel.
function scr_line_coll_compile(_lines) {
    var _out = [];
    var _n = array_length(_lines);
    for (var _i = 0; _i < _n; _i++) {
        var _ln = _lines[_i];
        var _rec = scr_line_coll_normalize(_ln.x1, _ln.y1, _ln.x2, _ln.y2, _ln.type);
        for (var _b = 0; _b < 6; _b++) array_push(_out, _rec[_b]);
    }
    array_push(_out, 0xFF);
    array_push(_out, 0xFF);
    array_push(_out, 0xFF);
    return _out;
}

/// @function scr_line_coll_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my)
/// Dedicated visual editor for LINE_COLL assets. Click-drag on the canvas
/// places a line (mousedown = start, mouseup = end); the active TYPE
/// selector (0-7) is baked into each new line. An optional BITMAP reference
/// can be shown underneath at a configurable X/Y offset to trace over.
/// meta.lines[] is the single source of truth — every change re-flushes
/// through scr_line_coll_flush so the compiled buffer stays in sync.
function scr_line_coll_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _m = _asset.meta;

    // ── Ensure editor state exists ──
    if (!variable_struct_exists(_m, "lines"))          _m.lines = [];
    if (!variable_struct_exists(_m, "active_type"))    _m.active_type = 1;
    if (!variable_struct_exists(_m, "draw_x1"))        _m.draw_x1 = -1;
    if (!variable_struct_exists(_m, "draw_y1"))        _m.draw_y1 = -1;
    if (!variable_struct_exists(_m, "ref_enabled"))    _m.ref_enabled = false;
    if (!variable_struct_exists(_m, "ref_asset_name")) _m.ref_asset_name = "";
    if (!variable_struct_exists(_m, "ref_offset_x"))   _m.ref_offset_x = 0;
    if (!variable_struct_exists(_m, "ref_offset_y"))   _m.ref_offset_y = 0;
    if (!variable_struct_exists(_m, "line_scroll"))    _m.line_scroll = 0;
    if (!variable_struct_exists(_m, "ref_picker_open")) _m.ref_picker_open = false;

    // ── CANVAS BOX — 256x256 byte-limited coordinate space ──
    var _box_x = _vx1 + 20;
    var _box_y = _cy + 40;
    var _box_w = 256 * 2; // 512 on-screen px
    var _box_h = 256 * 2;

    // ── OPTIONAL BITMAP REFERENCE ──
    var _ref_toggle_x1 = _vx1 + 10;
    var _ref_toggle_x2 = _ref_toggle_x1 + 140;
    var _ref_toggle_y1 = _cy;
    var _ref_toggle_y2 = _cy + 20;
    var _ref_toggle_hov = point_in_rectangle(_mx, _my, _ref_toggle_x1, _ref_toggle_y1, _ref_toggle_x2, _ref_toggle_y2);
    draw_set_color(_m.ref_enabled ? make_color_rgb(60, 160, 90) : (_ref_toggle_hov ? make_color_rgb(80, 80, 80) : make_color_rgb(40, 40, 40)));
    draw_rectangle(_ref_toggle_x1, _ref_toggle_y1, _ref_toggle_x2, _ref_toggle_y2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_ref_toggle_x1 + 70, _ref_toggle_y1 + 4, "REFERENCE: " + (_m.ref_enabled ? "ON" : "OFF"));
    draw_set_halign(fa_left);
    if (_ref_toggle_hov && mouse_check_button_pressed(mb_left)) {
        _m.ref_enabled = !_m.ref_enabled;
    }

    var _ref_asset = undefined;
    var _ref_dropdown_bottom = _cy + 20; // grows if the picker dropdown is open
    if (_m.ref_enabled) {
        // Reference asset name picker (BITMAP only)
        var _rpbx1 = _ref_toggle_x2 + 10;
        var _rpbx2 = _rpbx1 + 160;
        var _rpby1 = _cy;
        var _rpby2 = _cy + 20;
        var _rpbhov = point_in_rectangle(_mx, _my, _rpbx1, _rpby1, _rpbx2, _rpby2);
        draw_set_color(_rpbhov ? make_color_rgb(40, 80, 60) : make_color_rgb(20, 35, 25));
        draw_rectangle(_rpbx1, _rpby1, _rpbx2, _rpby2, false);
        draw_set_color(_m.ref_asset_name != "" ? c_lime : make_color_rgb(150, 150, 150));
        draw_text(_rpbx1 + 6, _rpby1 + 4, _m.ref_asset_name != "" ? _m.ref_asset_name : "-- PICK BITMAP --");
        if (_rpbhov && mouse_check_button_pressed(mb_left)) {
            _m.ref_picker_open = !_m.ref_picker_open;
        }

        if (_m.ref_picker_open) {
            var _rp_list = [];
            for (var _rpi = 0; _rpi < ds_list_size(asset_list); _rpi++) {
                var _rp_a = ds_list_find_value(asset_list, _rpi);
                if (_rp_a.type == "BITMAP") array_push(_rp_list, _rp_a.name);
            }
            var _rp_y = _rpby2 + 2;
            var _rp_h = (array_length(_rp_list) * 18) + 4;
            draw_set_color(make_color_rgb(15, 15, 15));
            draw_rectangle(_rpbx1, _rp_y, _rpbx2, _rp_y + _rp_h, false);
            for (var _rpj = 0; _rpj < array_length(_rp_list); _rpj++) {
                var _rp_row_y1 = _rp_y + 2 + (_rpj * 18);
                var _rp_row_y2 = _rp_row_y1 + 18;
                var _rp_row_hov = point_in_rectangle(_mx, _my, _rpbx1, _rp_row_y1, _rpbx2, _rp_row_y2);
                draw_set_color(_rp_row_hov ? make_color_rgb(50, 90, 70) : make_color_rgb(15, 15, 15));
                draw_rectangle(_rpbx1, _rp_row_y1, _rpbx2, _rp_row_y2, false);
                draw_set_color(c_white);
                draw_text(_rpbx1 + 6, _rp_row_y1 + 3, _rp_list[_rpj]);
                if (_rp_row_hov && mouse_check_button_pressed(mb_left)) {
                    _m.ref_asset_name  = _rp_list[_rpj];
                    _m.ref_picker_open = false;
                }
            }
            // Push the dropdown's bottom edge past everything below it so the
            // offset steppers (and canvas) never sit underneath the open list.
            _ref_dropdown_bottom = _rp_y + _rp_h;
        }

        // X/Y offset steppers — placed below the toggle/picker row, and below
        // the picker dropdown too when it's open, so nothing overlaps.
        var _off_y = _ref_dropdown_bottom + 10;
        var _off_labels = [
            { label: "REF X: " + string(_m.ref_offset_x), field: "ref_offset_x" },
            { label: "REF Y: " + string(_m.ref_offset_y), field: "ref_offset_y" }
        ];
        for (var _oi = 0; _oi < 2; _oi++) {
            var _obx1 = _ref_toggle_x1 + (_oi * 160);
            var _obx2 = _obx1 + 70;
            var _obm1 = _obx2 + 4;
            var _obm2 = _obm1 + 20;
            var _obp1 = _obm2 + 4;
            var _obp2 = _obp1 + 20;
            draw_set_color(make_color_rgb(30, 30, 30));
            draw_rectangle(_obx1, _off_y, _obx2, _off_y + 18, false);
            draw_set_color(c_white);
            draw_text(_obx1 + 4, _off_y + 3, _off_labels[_oi].label);
            var _minus_hov = point_in_rectangle(_mx, _my, _obm1, _off_y, _obm2, _off_y + 18);
            draw_set_color(_minus_hov ? make_color_rgb(90, 40, 40) : make_color_rgb(50, 20, 20));
            draw_rectangle(_obm1, _off_y, _obm2, _off_y + 18, false);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_text(_obm1 + 10, _off_y + 3, "-");
            var _plus_hov = point_in_rectangle(_mx, _my, _obp1, _off_y, _obp2, _off_y + 18);
            draw_set_color(_plus_hov ? make_color_rgb(40, 90, 40) : make_color_rgb(20, 50, 20));
            draw_rectangle(_obp1, _off_y, _obp2, _off_y + 18, false);
            draw_set_color(c_white);
            draw_text(_obp1 + 10, _off_y + 3, "+");
            draw_set_halign(fa_left);
            if (_minus_hov && mouse_check_button_pressed(mb_left)) {
                _m[$ _off_labels[_oi].field] = clamp(_m[$ _off_labels[_oi].field] - 1, -255, 255);
            }
            if (_plus_hov && mouse_check_button_pressed(mb_left)) {
                _m[$ _off_labels[_oi].field] = clamp(_m[$ _off_labels[_oi].field] + 1, -255, 255);
            }
        }
        _box_y = _off_y + 26;

        // Resolve the reference asset each frame (names can change elsewhere)
        if (_m.ref_asset_name != "") {
            for (var _rai = 0; _rai < ds_list_size(asset_list); _rai++) {
                var _ra2 = ds_list_find_value(asset_list, _rai);
                if (_ra2.type == "BITMAP" && _ra2.name == _m.ref_asset_name) { _ref_asset = _ra2; break; }
            }
        }
    }

    // ── DRAW CANVAS BACKGROUND ──
    draw_set_color(make_color_rgb(20, 20, 30));
    draw_rectangle(_box_x, _box_y, _box_x + _box_w, _box_y + _box_h, false);

    // Scissor everything drawn inside the canvas box (reference bitmap, lines,
    // drag preview) so nothing bleeds into the list column beside it.
    // gpu_set_scissor works in window px, not GUI px — scale by the same
    // ratio scr_asset_inline_editor_draw uses for its text-area scissor.
    var _sx_sc = window_get_width()  / global.gui_w;
    var _sy_sc = window_get_height() / display_get_gui_height();
    gpu_set_scissor(
        floor(_box_x * _sx_sc),
        floor(_box_y * _sy_sc),
        ceil(_box_w * _sx_sc),
        ceil(_box_h * _sy_sc)
    );

    // ── DRAW REFERENCE BITMAP (if enabled and resolved) ──
    if (_m.ref_enabled && _ref_asset != undefined
        && variable_struct_exists(_ref_asset.meta, "preview_surf")
        && surface_exists(_ref_asset.meta.preview_surf)) {
        // Reference bitmap is 320x200 C64 space; LINE_COLL canvas is 256x256.
        // Drawn at its offset, scaled 1:1 with the canvas's 2x zoom; the
        // scissor above (not draw_surface_ext itself) keeps it inside the box.
        var _draw_ox = _box_x + (_m.ref_offset_x * 2);
        var _draw_oy = _box_y + (_m.ref_offset_y * 2);
        var _prev_filter2 = gpu_get_texfilter();
        gpu_set_texfilter(false);
        draw_surface_ext(_ref_asset.meta.preview_surf, _draw_ox, _draw_oy, 2, 2, 0, c_white, 0.7);
        gpu_set_texfilter(_prev_filter2);
    }

    var _in_canvas = point_in_rectangle(_mx, _my, _box_x, _box_y, _box_x + _box_w, _box_y + _box_h);
    var _raw_px = clamp(floor((_mx - _box_x) / 2), 0, 255);
    var _raw_py = clamp(floor((_my - _box_y) / 2), 0, 255);

    // ── TYPE COLOUR TABLE (type N shown in the actual C64 pen colour N) ──
    // Direct 1:1: type 0 swatch is pepto colour 0 (black), type 1 is pepto
    // colour 1 (white), etc. — the swatch itself is the debug readout, since
    // this is meant to match colour values the person will see/compare
    // elsewhere (e.g. a border colour set to the result byte).
    var _type_colours = [
        scr_c64_pepto_colour(0), // black
        scr_c64_pepto_colour(1), // white
        scr_c64_pepto_colour(2), // red
        scr_c64_pepto_colour(3), // cyan
        scr_c64_pepto_colour(4), // purple
        scr_c64_pepto_colour(5), // green
        scr_c64_pepto_colour(6), // blue
        scr_c64_pepto_colour(7)  // yellow
    ];

    // ── DRAW EXISTING LINES ──
    for (var _li = 0; _li < array_length(_m.lines); _li++) {
        var _ln = _m.lines[_li];
        var _lx1 = _box_x + (_ln.x1 * 2);
        var _ly1 = _box_y + (_ln.y1 * 2);
        var _lx2 = _box_x + (_ln.x2 * 2);
        var _ly2 = _box_y + (_ln.y2 * 2);
        draw_set_color(_type_colours[clamp(_ln.type, 0, 7)]);
        draw_line_width(_lx1, _ly1, _lx2, _ly2, 2);
    }

    // Release scissor — everything below (border, type selector, list) sits
    // outside or spans past the canvas box and must not be clipped.
    gpu_set_scissor(0, 0, window_get_width(), window_get_height());

    draw_set_color(make_color_rgb(90, 90, 110));
    draw_rectangle(_box_x, _box_y, _box_x + _box_w, _box_y + _box_h, true);

    // ── TYPE SELECTOR (0-7) ──
    var _type_y = _box_y + _box_h + 10;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(_box_x, _type_y, "TYPE:");
    for (var _ti = 0; _ti < 8; _ti++) {
        var _tbx1 = _box_x + 40 + (_ti * 26);
        var _tbx2 = _tbx1 + 22;
        var _tby1 = _type_y - 2;
        var _tby2 = _tby1 + 18;
        var _tb_hov = point_in_rectangle(_mx, _my, _tbx1, _tby1, _tbx2, _tby2);
        var _tb_sel = (_m.active_type == _ti);
        // Filled swatch is the colour readout itself (type N = pepto colour N).
        // Always draw a filled swatch, with a brighter outline when selected/
        // hovered — outline-only (as before) would make the black (type 0)
        // and near-black swatches invisible against the dark panel.
        draw_set_color(_type_colours[_ti]);
        draw_rectangle(_tbx1, _tby1, _tbx2, _tby2, false);
        draw_set_color(_tb_sel ? c_white : (_tb_hov ? make_color_rgb(200, 200, 200) : make_color_rgb(60, 60, 60)));
        draw_rectangle(_tbx1, _tby1, _tbx2, _tby2, true);
        if (_tb_hov && mouse_check_button_pressed(mb_left)) {
            _m.active_type = _ti;
        }
        // Small index number under the swatch — position alone (1st, 2nd...)
        // should be enough once memorised, but this avoids any ambiguity.
        draw_set_halign(fa_center);
        draw_set_color(make_color_rgb(140, 140, 140));
        draw_text(_tbx1 + 11, _tby2 + 2, string(_ti));
        draw_set_halign(fa_left);
    }

    // ── CLICK-DRAG LINE PLACEMENT ──
    if (_in_canvas) {
        if (mouse_check_button_pressed(mb_left)) {
            _m.draw_x1 = _raw_px;
            _m.draw_y1 = _raw_py;
        }
    }
    if (_m.draw_x1 >= 0 && mouse_check_button_released(mb_left)) {
        var _end_px = _in_canvas ? _raw_px : clamp(floor((_mx - _box_x) / 2), 0, 255);
        var _end_py = _in_canvas ? _raw_py : clamp(floor((_my - _box_y) / 2), 0, 255);
        array_push(_m.lines, { x1: _m.draw_x1, y1: _m.draw_y1, x2: _end_px, y2: _end_py, type: _m.active_type });
        _m.draw_x1 = -1;
        _m.draw_y1 = -1;
        scr_line_coll_commit(_asset);
    }
    // In-progress drag preview — re-apply the canvas scissor just for this,
    // so a drag toward the list column doesn't paint over the list text.
    if (_m.draw_x1 >= 0 && mouse_check_button(mb_left)) {
        gpu_set_scissor(
            floor(_box_x * _sx_sc),
            floor(_box_y * _sy_sc),
            ceil(_box_w * _sx_sc),
            ceil(_box_h * _sy_sc)
        );
        var _px1 = _box_x + (_m.draw_x1 * 2);
        var _py1 = _box_y + (_m.draw_y1 * 2);
        draw_set_color(_type_colours[clamp(_m.active_type, 0, 7)]);
        draw_line_width(_px1, _py1, _mx, _my, 2);
        gpu_set_scissor(0, 0, window_get_width(), window_get_height());
    }

    // ── LINE LIST (with delete) ──
    var _list_x1 = _box_x + _box_w + 20;
    var _list_x2 = min(_vx2 - 10, _list_x1 + 220);
    var _list_y1 = _box_y;
    var _row_h   = 20;
    var _rows_vis = max(1, floor((_box_h - 20) / _row_h));
    draw_set_color(c_ltgray);
    draw_text(_list_x1, _list_y1 - 20, "LINES (" + string(array_length(_m.lines)) + "):");

    // CLEAR button — wipes every line in this LINE_COLL asset.
    var _clr_w = 50;
    var _clr_x2 = _list_x2;
    var _clr_x1 = _clr_x2 - _clr_w;
    var _clr_y1 = _list_y1 - 21;
    var _clr_y2 = _clr_y1 + 16;
    var _has_lines = array_length(_m.lines) > 0;
    var _clr_hov = _has_lines && point_in_rectangle(_mx, _my, _clr_x1, _clr_y1, _clr_x2, _clr_y2);
    draw_set_color(_has_lines ? (_clr_hov ? make_color_rgb(200, 60, 60) : make_color_rgb(110, 30, 30)) : make_color_rgb(40, 40, 40));
    draw_rectangle(_clr_x1, _clr_y1, _clr_x2, _clr_y2, false);
    draw_set_color(_has_lines ? c_white : make_color_rgb(90, 90, 90));
    draw_set_halign(fa_center);
    draw_text(_clr_x1 + (_clr_w / 2), _clr_y1 + 3, "CLEAR");
    draw_set_halign(fa_left);
    if (_has_lines && _clr_hov && mouse_check_button_pressed(mb_left)) {
        _m.lines = [];
        _m.line_scroll = 0;
        scr_line_coll_commit(_asset);
    }

    var _total_lines = array_length(_m.lines);
    _m.line_scroll = clamp(_m.line_scroll, 0, max(0, _total_lines - _rows_vis));

    // "N more above" indicator — replaces the top row slot when scrolled down.
    var _more_above = _m.line_scroll;
    var _row_start  = 0;
    if (_more_above > 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(140, 140, 140));
        draw_text(_list_x1 + 10, _list_y1 + 3, "^ " + string(_more_above) + " more above");
        _row_start = 1;
    }

    var _delete_idx = -1;
    for (var _vi = _row_start; _vi < _rows_vis; _vi++) {
        var _idx = _vi + _m.line_scroll;
        if (_idx >= _total_lines) break;
        // Reserve the last visible slot for a "more below" indicator if there
        // are additional rows past what fits — unless this is the final one.
        var _remaining_after = _total_lines - _idx - 1;
        var _is_last_slot     = (_vi == _rows_vis - 1);
        if (_is_last_slot && _remaining_after > 0) {
            var _fy1 = _list_y1 + (_vi * _row_h);
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(140, 140, 140));
            draw_text(_list_x1 + 10, _fy1 + 3, "v " + string(_remaining_after + 1) + " more below");
            break;
        }
        var _row_ln = _m.lines[_idx];
        var _ry1 = _list_y1 + (_vi * _row_h);
        var _ry2 = _ry1 + _row_h - 2;
        draw_set_color(make_color_rgb(25, 25, 25));
        draw_rectangle(_list_x1, _ry1, _list_x2, _ry2, false);
        draw_set_color(_type_colours[clamp(_row_ln.type, 0, 7)]);
        draw_rectangle(_list_x1, _ry1, _list_x1 + 6, _ry2, false);
        draw_set_color(c_white);
        draw_set_font(fnt_c64_tiny);
        draw_text(_list_x1 + 10, _ry1 + 3,
            string(_row_ln.x1) + "," + string(_row_ln.y1) + " -> " + string(_row_ln.x2) + "," + string(_row_ln.y2) + " T" + string(_row_ln.type));
        var _delx1 = _list_x2 - 20;
        var _del_hov = point_in_rectangle(_mx, _my, _delx1, _ry1, _list_x2, _ry2);
        draw_set_color(_del_hov ? c_red : make_color_rgb(120, 60, 60));
        draw_text(_delx1 + 2, _ry1 + 3, "X");
        if (_del_hov && mouse_check_button_pressed(mb_left)) {
            _delete_idx = _idx;
        }
    }
    if (_delete_idx >= 0) {
        array_delete(_m.lines, _delete_idx, 1);
        scr_line_coll_commit(_asset);
    }
    if (point_in_rectangle(_mx, _my, _list_x1, _list_y1, _list_x2, _list_y1 + (_rows_vis * _row_h))) {
        if (mouse_wheel_up())   _m.line_scroll = max(0, _m.line_scroll - 1);
        if (mouse_wheel_down()) _m.line_scroll = min(max(0, _total_lines - _rows_vis), _m.line_scroll + 1);
    }
}

/// @desc scr_line_coll_save(_asset)
/// Commits the shared inline text editor's working text (meta.inline_edit_text,
/// one "x1,y1,x2,y2,type" row per line) into meta.lines[] and the compiled
/// buffer. Called when the LINE_COLL editor panel is closed/saved — mirrors
/// scr_asset_byte_data_save's role for BYTE_DATA.
function scr_line_coll_save(_asset) {
    _asset.meta.line_string = _asset.meta.inline_edit_text;
    scr_line_coll_flush(_asset);
}

/// @desc scr_line_coll_commit(_asset)
/// Rebuilds meta.line_string and the compiled buffer FROM meta.lines[] —
/// the reverse direction of scr_line_coll_flush. Use this after the visual
/// canvas editor mutates meta.lines[] directly (push/delete): flushing from
/// text there would re-parse the stale line_string and silently discard the
/// just-drawn line. Text-edit paths still use scr_line_coll_flush, since
/// there the text IS the source of truth.
function scr_line_coll_commit(_asset) {
    var _lines = variable_struct_exists(_asset.meta, "lines") ? _asset.meta.lines : [];
    var _out_lines = [];
    for (var _i = 0; _i < array_length(_lines); _i++) {
        var _ln = _lines[_i];
        array_push(_out_lines, string(_ln.x1) + "," + string(_ln.y1) + "," + string(_ln.x2) + "," + string(_ln.y2) + "," + string(_ln.type));
    }
    var _serialised = string_join_ext("\n", _out_lines);
    _asset.meta.line_string      = _serialised;
    _asset.meta.inline_edit_text = _serialised;

    var _bytes = scr_line_coll_compile(_lines);
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    _asset.buffer = buffer_create(max(1, array_length(_bytes)), buffer_fixed, 1);
    for (var _bi = 0; _bi < array_length(_bytes); _bi++) {
        buffer_write(_asset.buffer, buffer_u8, _bytes[_bi]);
    }
    _asset.size = array_length(_bytes);
}

/// @desc scr_line_coll_flush(_asset)
/// Parses the LINE_COLL asset's inline text (meta.line_string) into
/// meta.lines[] structs and recompiles the buffer. Same "tolerant text
/// editor" pattern as scr_asset_byte_data_flush — one line record per
/// text row: "x1,y1,x2,y2,type". Invalid rows are skipped and logged.
function scr_line_coll_flush(_asset) {
    var _str = "";
    if (variable_struct_exists(_asset, "meta") && variable_struct_exists(_asset.meta, "line_string")) {
        _str = string(_asset.meta.line_string);
    }

    _str = string_replace_all(_str, "\r\n", "\n");
    _str = string_replace_all(_str, "\r",   "\n");

    var _text_lines = string_split(_str, "\n");
    var _out_lines  = [];
    var _lines      = [];
    var _skipped    = 0;

    for (var _li = 0; _li < array_length(_text_lines); _li++) {
        var _row = string_trim(_text_lines[_li]);
        if (_row == "") continue;

        var _parts = string_split(_row, ",");
        if (array_length(_parts) != 5) {
            _skipped += 1;
            show_debug_message("scr_line_coll_flush: skipped row (need 5 values) \"" + _row + "\"");
            continue;
        }

        var _vals  = [0, 0, 0, 0, 0];
        var _valid = true;
        for (var _pi = 0; _pi < 5; _pi++) {
            var _tok = string_trim(_parts[_pi]);
            if (_tok == "" || !scr_str_is_decimal(_tok)) { _valid = false; break; }
            _vals[_pi] = floor(real(_tok));
        }
        if (!_valid) {
            _skipped += 1;
            show_debug_message("scr_line_coll_flush: skipped row (invalid number) \"" + _row + "\"");
            continue;
        }

        var _x1 = clamp(_vals[0], 0, 255);
        var _y1 = clamp(_vals[1], 0, 255);
        var _x2 = clamp(_vals[2], 0, 255);
        var _y2 = clamp(_vals[3], 0, 255);
        var _tp = clamp(_vals[4], 0, 7);

        array_push(_lines, { x1: _x1, y1: _y1, x2: _x2, y2: _y2, type: _tp });
        array_push(_out_lines, string(_x1) + "," + string(_y1) + "," + string(_x2) + "," + string(_y2) + "," + string(_tp));
    }

    var _serialised = string_join_ext("\n", _out_lines);
    if (variable_struct_exists(_asset, "meta")) {
        _asset.meta.line_string      = _serialised;
        _asset.meta.inline_edit_text = _serialised;
        _asset.meta.lines            = _lines;
    }

    var _bytes = scr_line_coll_compile(_lines);
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    _asset.buffer = buffer_create(max(1, array_length(_bytes)), buffer_fixed, 1);
    for (var _bi = 0; _bi < array_length(_bytes); _bi++) {
        buffer_write(_asset.buffer, buffer_u8, _bytes[_bi]);
    }
    _asset.size = array_length(_bytes);

    if (_skipped > 0) {
        show_debug_message("scr_line_coll_flush: " + string(_skipped) + " invalid row(s) skipped.");
    }
}

/// @desc scr_line_coll_find_asset(_name)
/// Looks up a LINE_COLL asset by name in the asset manager.
function scr_line_coll_find_asset(_name) {
    if (!instance_exists(obj_asset_manager)) return undefined;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "LINE_COLL" && _a.name == _name) return _a;
    }
    return undefined;
}
