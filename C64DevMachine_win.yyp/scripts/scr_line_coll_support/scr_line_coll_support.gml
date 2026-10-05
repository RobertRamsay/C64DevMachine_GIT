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

/// Undo/redo snapshot: a deep copy of the lines plus the WIDE X flag (the
/// WIDE toggle rescales every line, so it has to come back with them).
function scr_line_coll_snapshot(_m) {
    var _copy = [];
    for (var _i = 0; _i < array_length(_m.lines); _i++) {
        var _ln = _m.lines[_i];
        array_push(_copy, { x1: _ln.x1, y1: _ln.y1, x2: _ln.x2, y2: _ln.y2, type: _ln.type });
    }
    return { lines: _copy, wide: _m.wide_x };
}

/// Call BEFORE changing the lines. A new change clears the redo stack.
function scr_line_coll_push_undo(_m) {
    array_push(_m.undo, scr_line_coll_snapshot(_m));
    if (array_length(_m.undo) > 50) { array_delete(_m.undo, 0, 1); }
    _m.redo = [];
}

/// _redo false = undo, true = redo.
function scr_line_coll_history_step(_asset, _redo) {
    var _m    = _asset.meta;
    var _from = _m.undo;
    var _to   = _m.redo;
    if (_redo) {
        _from = _m.redo;
        _to   = _m.undo;
    }
    if (array_length(_from) == 0) return;
    array_push(_to, scr_line_coll_snapshot(_m));
    var _s = array_pop(_from);
    _m.lines     = _s.lines;
    _m.wide_x    = _s.wide;
    _m.drag_line = -1;
    _m.draw_x1   = -1;
    _m.draw_y1   = -1;
    scr_line_coll_commit(_asset);
}

/// @function scr_line_coll_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my)
/// Full-width LINE_COLL editor.
///   LEFT   reference bitmap, coordinate mode, line type, tools
///   CENTRE the canvas, scaled to fit and centred
///   RIGHT  the line list
/// Click-drag on the canvas places a line with the active TYPE. EDIT POINTS
/// (or ALT held) shows the end points so they can be dragged. meta.lines[] is
/// the single source of truth; every change goes through scr_line_coll_commit.
function scr_line_coll_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _m = _asset.meta;
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);

    var _press   = mouse_check_button_pressed(mb_left);
    var _alt_hot = keyboard_check(vk_alt);

    // ── LAYOUT ──
    var _top    = _cy + 4;
    var _bottom = _vy2 - 112;            // the INJECTED footer sits below this
    var _lw     = 260;
    var _lx     = _vx1 + 20;
    var _rw     = 280;
    var _rx     = _vx2 - 20 - _rw;
    var _ax1    = _lx + _lw + 30;
    var _ax2    = _rx - 30;
    var _aw     = _ax2 - _ax1;
    var _ah     = _bottom - (_top + 26);

    // Canvas: the 200 rows of the bitmap. X is 256 units, or 160 two-pixel
    // units (320 px) in WIDE mode. _ys = screen px per bitmap pixel - as big
    // as the space allows, not just whole steps; the reference bitmap is
    // always drawn at that scale so lines and picture line up.
    var _span_px = 256;
    var _x_max   = 255;
    if (_m.wide_x) {
        _span_px = 320;
        _x_max   = 159;
    }
    var _rows = 200;
    var _ys = max(1, min(_aw / _span_px, _ah / _rows));
    var _xs = _ys;
    if (_m.wide_x) {
        _xs = _ys * 2;
    }
    var _box_w = floor(_span_px * _ys);
    var _box_h = floor(_rows * _ys);
    var _box_x = floor(_ax1 + (_aw - _box_w) * 0.5);
    var _box_y = floor(_top + 26 + (_ah - _box_h) * 0.5);

    var _type_colours = [];
    for (var _tc = 0; _tc < 8; _tc++) {
        array_push(_type_colours, scr_c64_pepto_colour(_tc));
    }

    // While the reference dropdown is open, nothing underneath takes clicks.
    var _ui_my = _my;
    if (_m.ref_picker_open) {
        _ui_my = -10000;
    }

    var _btn = function(_x1, _y1, _w, _h, _label, _fill, _hov_fill, _mx2, _my2) {
        var _hov = point_in_rectangle(_mx2, _my2, _x1, _y1, _x1 + _w, _y1 + _h);
        draw_set_color(_fill);
        if (_hov) { draw_set_color(_hov_fill); }
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, false);
        draw_set_color(make_color_rgb(72, 83, 103));
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, true);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text_l(_x1 + _w * 0.5, _y1 + floor(_h * 0.5) - 6, _label);
        draw_set_halign(fa_left);
        return (_hov && mouse_check_button_pressed(mb_left));
    };
    var _c_off  = make_color_rgb(31, 38, 54);
    var _c_hov  = make_color_rgb(53, 61, 82);
    var _c_on   = make_color_rgb(38, 94, 111);
    var _c_head = make_color_rgb(154, 175, 198);

    // ════════════════════════════════════════════════════════════════
    // LEFT PANEL
    // ════════════════════════════════════════════════════════════════
    draw_set_color(make_color_rgb(23, 29, 42));
    draw_rectangle(_lx - 10, _top - 6, _lx + _lw + 10, _bottom, false);
    var _sy = _top + 4;

    // ── 1 REFERENCE ──
    draw_set_color(_c_head);
    draw_text_l(_lx, _sy, "REFERENCE BITMAP"); _sy += 20;
    var _ref_lbl = "SHOW REFERENCE: OFF";
    var _ref_col = _c_off;
    if (_m.ref_enabled) {
        _ref_lbl = "SHOW REFERENCE: ON";
        _ref_col = _c_on;
    }
    if (_btn(_lx, _sy, _lw, 24, _ref_lbl, _ref_col, _c_hov, _mx, _ui_my)) {
        _m.ref_enabled = !_m.ref_enabled;
    }
    _sy += 30;
    var _pick_y = _sy;
    var _pick_lbl = "-- PICK BITMAP --";
    if (_m.ref_asset_name != "") {
        _pick_lbl = scr_bbuild_fit_name(_m.ref_asset_name, _lw - 20);
    }
    if (_btn(_lx, _sy, _lw, 24, _pick_lbl, _c_off, _c_hov, _mx, _my)) {
        _m.ref_picker_open = !_m.ref_picker_open;
        _press = false;
    }
    _sy += 30;
    // Offset steppers
    var _offs = [["REF X", "ref_offset_x"], ["REF Y", "ref_offset_y"]];
    for (var _oi = 0; _oi < 2; _oi++) {
        var _fld = _offs[_oi][1];
        draw_set_color(make_color_rgb(16, 19, 29));
        draw_rectangle(_lx, _sy, _lx + _lw - 64, _sy + 22, false);
        draw_set_color(c_white);
        draw_text_l(_lx + 8, _sy + 5, _offs[_oi][0] + ": " + string(_m[$ _fld]));
        if (_btn(_lx + _lw - 58, _sy, 26, 22, "-", make_color_rgb(60, 25, 25), make_color_rgb(110, 45, 45), _mx, _ui_my)) {
            _m[$ _fld] = clamp(_m[$ _fld] - 1, -255, 255);
        }
        if (_btn(_lx + _lw - 26, _sy, 26, 22, "+", make_color_rgb(25, 60, 25), make_color_rgb(45, 110, 45), _mx, _ui_my)) {
            _m[$ _fld] = clamp(_m[$ _fld] + 1, -255, 255);
        }
        _sy += 28;
    }
    _sy += 10;

    // ── 2 COORDINATES ──
    draw_set_color(_c_head);
    draw_text_l(_lx, _sy, "X COORDINATES"); _sy += 20;
    var _wx_lbl = "X: 0-255 (1 = 1 PIXEL)";
    var _wx_col = _c_off;
    if (_m.wide_x) {
        _wx_lbl = "X: 320 WIDE (1 = 2 PIXELS)";
        _wx_col = _c_on;
    }
    if (_btn(_lx, _sy, _lw, 24, _wx_lbl, _wx_col, _c_hov, _mx, _ui_my)) {
        // Rescale existing lines so they stay where they are.
        scr_line_coll_push_undo(_m);
        _m.wide_x = !_m.wide_x;
        for (var _wl = 0; _wl < array_length(_m.lines); _wl++) {
            var _wln = _m.lines[_wl];
            if (_m.wide_x) {
                _wln.x1 = round(_wln.x1 / 2);
                _wln.x2 = round(_wln.x2 / 2);
            } else {
                _wln.x1 = min(255, _wln.x1 * 2);
                _wln.x2 = min(255, _wln.x2 * 2);
            }
        }
        scr_line_coll_commit(_asset);
        exit;
    }
    _sy += 40;

    // ── 3 LINE TYPE ──
    draw_set_color(_c_head);
    draw_text_l(_lx, _sy, "LINE TYPE  (RESULT VALUE)"); _sy += 20;
    var _sw = floor((_lw - 3 * 8) / 4);
    for (var _ti = 0; _ti < 8; _ti++) {
        var _tbx1 = _lx + (_ti mod 4) * (_sw + 8);
        var _tby1 = _sy + (_ti div 4) * 34;
        var _tbx2 = _tbx1 + _sw;
        var _tby2 = _tby1 + 26;
        var _tb_hov = point_in_rectangle(_mx, _ui_my, _tbx1, _tby1, _tbx2, _tby2);
        draw_set_color(_type_colours[_ti]);
        draw_rectangle(_tbx1, _tby1, _tbx2, _tby2, false);
        draw_set_color(make_color_rgb(60, 60, 60));
        if (_tb_hov) { draw_set_color(make_color_rgb(200, 200, 200)); }
        if (_m.active_type == _ti) { draw_set_color(c_white); }
        draw_rectangle(_tbx1, _tby1, _tbx2, _tby2, true);
        if (_m.active_type == _ti) {
            draw_rectangle(_tbx1 + 1, _tby1 + 1, _tbx2 - 1, _tby2 - 1, true);
        }
        // Number in a contrasting box so it reads on every swatch colour
        draw_set_color(c_black);
        draw_rectangle(_tbx1 + 2, _tby1 + 2, _tbx1 + 14, _tby1 + 14, false);
        draw_set_color(c_white);
        draw_text_l(_tbx1 + 5, _tby1 + 2, string(_ti));
        if (_tb_hov && _press) {
            _m.active_type = _ti;
        }
    }
    _sy += 76;

    // ── 4 TOOLS ──
    draw_set_color(_c_head);
    draw_text_l(_lx, _sy, "TOOLS"); _sy += 20;
    // EDIT POINTS: on only by clicking. ALT lights it (hot edit) without
    // switching it on.
    var _ed_col = _c_off;
    if (_alt_hot) { _ed_col = make_color_rgb(120, 100, 30); }
    if (_m.edit_mode) { _ed_col = make_color_rgb(200, 160, 40); }
    var _ed_lbl = "EDIT POINTS: OFF  (HOLD ALT)";
    if (_m.edit_mode) { _ed_lbl = "EDIT POINTS: ON"; }
    if (_btn(_lx, _sy, _lw, 24, _ed_lbl, _ed_col, _c_hov, _mx, _ui_my)) {
        _m.edit_mode = !_m.edit_mode;
        _m.draw_x1   = -1;
        _m.draw_y1   = -1;
    }
    _sy += 30;
    var _hw = floor((_lw - 8) / 2);
    var _hist_lbl = ["UNDO", "REDO"];
    for (var _hb = 0; _hb < 2; _hb++) {
        var _hb_has = array_length(_m.undo) > 0;
        if (_hb == 1) { _hb_has = array_length(_m.redo) > 0; }
        var _hb_x = _lx + _hb * (_hw + 8);
        if (_hb_has) {
            if (_btn(_hb_x, _sy, _hw, 24, _hist_lbl[_hb], make_color_rgb(40, 60, 90), make_color_rgb(70, 100, 150), _mx, _ui_my)) {
                scr_line_coll_history_step(_asset, _hb == 1);
                exit;
            }
        } else {
            draw_set_color(make_color_rgb(24, 26, 34));
            draw_rectangle(_hb_x, _sy, _hb_x + _hw, _sy + 24, false);
            draw_set_color(make_color_rgb(90, 90, 90));
            draw_set_halign(fa_center);
            draw_text_l(_hb_x + _hw * 0.5, _sy + 6, _hist_lbl[_hb]);
            draw_set_halign(fa_left);
        }
    }
    _sy += 40;

    // ── HELP ──
    draw_set_color(make_color_rgb(125, 146, 163));
    var _help = [
        "CLICK-DRAG: NEW LINE",
        "ALT / EDIT POINTS: DRAG ENDS",
        "CTRL+Z UNDO   CTRL+Y REDO",
        "TYPE = VALUE IN THE RESULT VAR",
        "0 = NO HIT, SO USE 1-7"
    ];
    for (var _hl = 0; _hl < array_length(_help); _hl++) {
        draw_text_l(_lx, _sy, _help[_hl]);
        _sy += 16;
    }

    // ════════════════════════════════════════════════════════════════
    // CENTRE — CANVAS
    // ════════════════════════════════════════════════════════════════
    var _in_canvas = point_in_rectangle(_mx, _ui_my, _box_x, _box_y, _box_x + _box_w - 1, _box_y + _box_h - 1);
    var _raw_px = clamp(floor((_mx - _box_x) / _xs), 0, _x_max);
    var _raw_py = clamp(floor((_my - _box_y) / _ys), 0, _rows - 1);

    // Status line above the canvas
    draw_set_color(c_ltgray);
    var _status = "MOUSE: OFF CANVAS";
    if (_in_canvas) {
        _status = "MOUSE: " + string(_raw_px) + ", " + string(_raw_py);
    }
    _status += "     MODE: ";
    if (_m.edit_mode || _alt_hot) {
        _status += "EDIT POINTS";
    } else {
        _status += "DRAW TYPE " + string(_m.active_type);
    }
    if (_m.wide_x) {
        _status += "     X UNITS ARE 2 PIXELS";
    }
    draw_text_l(_box_x, _box_y - 22, _status);

    draw_set_color(make_color_rgb(20, 20, 30));
    draw_rectangle(_box_x, _box_y, _box_x + _box_w, _box_y + _box_h, false);

    // Scissor (window px) keeps the reference, lines and drag preview inside.
    var _sx_sc = window_get_width()  / global.gui_w;
    var _sy_sc = window_get_height() / display_get_gui_height();
    gpu_set_scissor(floor(_box_x * _sx_sc), floor(_box_y * _sy_sc),
                    ceil(_box_w * _sx_sc), ceil(_box_h * _sy_sc));

    // Reference bitmap
    var _ref_asset = undefined;
    if (_m.ref_asset_name != "") {
        for (var _rai = 0; _rai < ds_list_size(asset_list); _rai++) {
            var _ra2 = ds_list_find_value(asset_list, _rai);
            if (_ra2.type == "BITMAP" && _ra2.name == _m.ref_asset_name) { _ref_asset = _ra2; break; }
        }
    }
    if (_m.ref_enabled && !is_undefined(_ref_asset)
        && variable_struct_exists(_ref_asset.meta, "preview_surf")
        && surface_exists(_ref_asset.meta.preview_surf)) {
        var _prev_filter = gpu_get_texfilter();
        gpu_set_texfilter(false);
        draw_surface_ext(_ref_asset.meta.preview_surf,
            _box_x + _m.ref_offset_x * _ys, _box_y + _m.ref_offset_y * _ys,
            _ys, _ys, 0, c_white, 0.7);
        gpu_set_texfilter(_prev_filter);
    }

    // Lines
    var _lt = max(2, _ys);
    for (var _li = 0; _li < array_length(_m.lines); _li++) {
        var _ln = _m.lines[_li];
        draw_set_color(_type_colours[clamp(_ln.type, 0, 7)]);
        draw_line_width(_box_x + _ln.x1 * _xs + _xs * 0.5, _box_y + _ln.y1 * _ys + _ys * 0.5,
                        _box_x + _ln.x2 * _xs + _xs * 0.5, _box_y + _ln.y2 * _ys + _ys * 0.5, _lt);
    }

    // End point handles (EDIT on, ALT held, or a drag in progress)
    var _editing  = _m.edit_mode || _alt_hot || _m.drag_line >= 0;
    var _hit_line = -1;
    var _hit_end  = 0;
    var _hit_best = 10 * 10;
    if (_editing) {
        for (var _hi = 0; _hi < array_length(_m.lines); _hi++) {
            var _hl2 = _m.lines[_hi];
            for (var _he = 0; _he < 2; _he++) {
                var _hx = _box_x + _hl2.x1 * _xs + _xs * 0.5;
                var _hy = _box_y + _hl2.y1 * _ys + _ys * 0.5;
                if (_he == 1) {
                    _hx = _box_x + _hl2.x2 * _xs + _xs * 0.5;
                    _hy = _box_y + _hl2.y2 * _ys + _ys * 0.5;
                }
                var _hd = sqr(_mx - _hx) + sqr(_ui_my - _hy);
                if (_hd <= _hit_best) {
                    _hit_best = _hd;
                    _hit_line = _hi;
                    _hit_end  = _he;
                }
                draw_set_color(c_black);
                draw_rectangle(_hx - 5, _hy - 5, _hx + 5, _hy + 5, false);
                draw_set_color(c_white);
                draw_rectangle(_hx - 4, _hy - 4, _hx + 4, _hy + 4, true);
            }
        }
        var _sel_line = _hit_line;
        var _sel_end  = _hit_end;
        if (_m.drag_line >= 0) {
            _sel_line = _m.drag_line;
            _sel_end  = _m.drag_end;
        }
        if (_sel_line >= 0 && _sel_line < array_length(_m.lines)) {
            var _sl = _m.lines[_sel_line];
            var _shx = _box_x + _sl.x1 * _xs + _xs * 0.5;
            var _shy = _box_y + _sl.y1 * _ys + _ys * 0.5;
            if (_sel_end == 1) {
                _shx = _box_x + _sl.x2 * _xs + _xs * 0.5;
                _shy = _box_y + _sl.y2 * _ys + _ys * 0.5;
            }
            draw_set_color(c_yellow);
            draw_rectangle(_shx - 6, _shy - 6, _shx + 6, _shy + 6, false);
        }
    }

    // Drag preview for a new line
    if (_m.draw_x1 >= 0 && mouse_check_button(mb_left)) {
        draw_set_color(_type_colours[clamp(_m.active_type, 0, 7)]);
        draw_line_width(_box_x + _m.draw_x1 * _xs + _xs * 0.5, _box_y + _m.draw_y1 * _ys + _ys * 0.5,
                        _box_x + _raw_px * _xs + _xs * 0.5, _box_y + _raw_py * _ys + _ys * 0.5, _lt);
    }
    gpu_set_scissor(0, 0, window_get_width(), window_get_height());
    draw_set_color(make_color_rgb(90, 90, 110));
    draw_rectangle(_box_x, _box_y, _box_x + _box_w, _box_y + _box_h, true);

    // ── Canvas input ──
    if (_editing && _in_canvas && _hit_line >= 0 && _m.drag_line < 0 && _press) {
        scr_line_coll_push_undo(_m);
        _m.drag_line = _hit_line;
        _m.drag_end  = _hit_end;
    }
    if (_m.drag_line >= 0) {
        if (_m.drag_line < array_length(_m.lines)) {
            var _dln = _m.lines[_m.drag_line];
            if (_m.drag_end == 0) {
                _dln.x1 = _raw_px;
                _dln.y1 = _raw_py;
            } else {
                _dln.x2 = _raw_px;
                _dln.y2 = _raw_py;
            }
        }
        if (!mouse_check_button(mb_left)) {
            _m.drag_line = -1;
            scr_line_coll_commit(_asset);
        }
    }
    if (_in_canvas && !_editing && _press) {
        _m.draw_x1 = _raw_px;
        _m.draw_y1 = _raw_py;
    }
    if (_m.draw_x1 >= 0 && mouse_check_button_released(mb_left)) {
        scr_line_coll_push_undo(_m);
        array_push(_m.lines, { x1: _m.draw_x1, y1: _m.draw_y1, x2: _raw_px, y2: _raw_py, type: _m.active_type });
        _m.draw_x1 = -1;
        _m.draw_y1 = -1;
        scr_line_coll_commit(_asset);
    }

    // ════════════════════════════════════════════════════════════════
    // RIGHT PANEL — LINE LIST
    // ════════════════════════════════════════════════════════════════
    draw_set_color(make_color_rgb(23, 29, 42));
    draw_rectangle(_rx - 10, _top - 6, _rx + _rw + 10, _bottom, false);
    draw_set_color(_c_head);
    draw_text_l(_rx, _top + 4, "LINES (" + string(array_length(_m.lines)) + ")");
    var _has_lines = array_length(_m.lines) > 0;
    if (_has_lines) {
        if (_btn(_rx + _rw - 60, _top, 60, 20, "CLEAR", make_color_rgb(110, 30, 30), make_color_rgb(200, 60, 60), _mx, _ui_my)) {
            scr_line_coll_push_undo(_m);
            _m.lines = [];
            _m.line_scroll = 0;
            scr_line_coll_commit(_asset);
        }
    }
    var _list_y1  = _top + 30;
    var _row_h    = 22;
    var _rows_vis = max(1, floor((_bottom - 10 - _list_y1) / _row_h));
    var _total    = array_length(_m.lines);
    _m.line_scroll = clamp(_m.line_scroll, 0, max(0, _total - _rows_vis));
    if (point_in_rectangle(_mx, _ui_my, _rx, _list_y1, _rx + _rw, _list_y1 + _rows_vis * _row_h)) {
        if (mouse_wheel_up())   { _m.line_scroll = max(0, _m.line_scroll - 1); }
        if (mouse_wheel_down()) { _m.line_scroll = min(max(0, _total - _rows_vis), _m.line_scroll + 1); }
    }
    var _delete_idx = -1;
    for (var _vi = 0; _vi < _rows_vis; _vi++) {
        var _idx = _vi + _m.line_scroll;
        if (_idx >= _total) break;
        var _row_ln = _m.lines[_idx];
        var _ry1 = _list_y1 + _vi * _row_h;
        var _ry2 = _ry1 + _row_h - 3;
        var _row_hov = point_in_rectangle(_mx, _ui_my, _rx, _ry1, _rx + _rw, _ry2);
        draw_set_color(make_color_rgb(16, 19, 29));
        if (_row_hov) { draw_set_color(make_color_rgb(35, 42, 58)); }
        if (_m.drag_line == _idx) { draw_set_color(make_color_rgb(70, 60, 20)); }
        draw_rectangle(_rx, _ry1, _rx + _rw, _ry2, false);
        draw_set_color(_type_colours[clamp(_row_ln.type, 0, 7)]);
        draw_rectangle(_rx, _ry1, _rx + 6, _ry2, false);
        draw_set_color(c_white);
        draw_text_l(_rx + 12, _ry1 + 4, string(_idx + 1) + ":  " + string(_row_ln.x1) + "," + string(_row_ln.y1)
            + " -> " + string(_row_ln.x2) + "," + string(_row_ln.y2) + "   T" + string(_row_ln.type));
        var _dx1 = _rx + _rw - 22;
        var _del_hov = point_in_rectangle(_mx, _ui_my, _dx1, _ry1, _rx + _rw, _ry2);
        draw_set_color(make_color_rgb(120, 60, 60));
        if (_del_hov) { draw_set_color(c_red); }
        draw_text_l(_dx1 + 6, _ry1 + 4, "X");
        if (_del_hov && _press) {
            _delete_idx = _idx;
        }
    }
    if (_total > _rows_vis) {
        draw_set_color(make_color_rgb(125, 146, 163));
        draw_text_l(_rx, _list_y1 + _rows_vis * _row_h + 2,
            "SHOWING " + string(_m.line_scroll + 1) + "-" + string(min(_total, _m.line_scroll + _rows_vis))
            + " OF " + string(_total) + "  (WHEEL)");
    }
    if (_delete_idx >= 0) {
        scr_line_coll_push_undo(_m);
        array_delete(_m.lines, _delete_idx, 1);
        scr_line_coll_commit(_asset);
    }

    // ── Keys ──
    if (!global.is_any_text_active && scr_ctrl_held()) {
        if (keyboard_check_pressed(ord("Z"))) {
            scr_line_coll_history_step(_asset, keyboard_check(vk_shift));
            exit;
        }
        if (keyboard_check_pressed(ord("Y"))) {
            scr_line_coll_history_step(_asset, true);
            exit;
        }
    }

    // ── Reference dropdown (drawn last so it sits on top) ──
    if (_m.ref_picker_open) {
        var _rp_list = [];
        for (var _rpi = 0; _rpi < ds_list_size(asset_list); _rpi++) {
            var _rp_a = ds_list_find_value(asset_list, _rpi);
            if (_rp_a.type == "BITMAP") { array_push(_rp_list, _rp_a.name); }
        }
        var _rp_y = _pick_y + 26;
        draw_set_color(make_color_rgb(12, 14, 20));
        draw_rectangle(_lx, _rp_y, _lx + _lw, _rp_y + max(1, array_length(_rp_list)) * 22 + 4, false);
        draw_set_color(make_color_rgb(72, 83, 103));
        draw_rectangle(_lx, _rp_y, _lx + _lw, _rp_y + max(1, array_length(_rp_list)) * 22 + 4, true);
        if (array_length(_rp_list) == 0) {
            draw_set_color(c_gray);
            draw_text_l(_lx + 8, _rp_y + 6, "NO BITMAP ASSETS");
        }
        for (var _rpj = 0; _rpj < array_length(_rp_list); _rpj++) {
            var _r1 = _rp_y + 2 + _rpj * 22;
            var _rh = point_in_rectangle(_mx, _my, _lx, _r1, _lx + _lw, _r1 + 20);
            if (_rh) {
                draw_set_color(make_color_rgb(45, 70, 90));
                draw_rectangle(_lx + 2, _r1, _lx + _lw - 2, _r1 + 20, false);
            }
            draw_set_color(c_white);
            if (_rp_list[_rpj] == _m.ref_asset_name) { draw_set_color(c_lime); }
            draw_text_l(_lx + 8, _r1 + 4, scr_bbuild_fit_name(_rp_list[_rpj], _lw - 16));
            if (_rh && _press) {
                _m.ref_asset_name  = _rp_list[_rpj];
                _m.ref_enabled     = true;
                _m.ref_picker_open = false;
            }
        }
        // A click anywhere else closes it.
        var _rp_h2 = max(1, array_length(_rp_list)) * 22 + 4;
        if (_press && !point_in_rectangle(_mx, _my, _lx, _rp_y, _lx + _lw, _rp_y + _rp_h2)) {
            _m.ref_picker_open = false;
        }
    }
}

/// @desc scr_line_coll_save(_asset)
/// Commits the shared inline text editor's working text (meta.inline_edit_text,
/// one "x1,y1,x2,y2,type" row per line) into meta.lines[] and the compiled
/// buffer. Called when the LINE_COLL editor panel is closed/saved — mirrors
/// scr_asset_byte_data_save's role for BYTE_DATA.
function scr_line_coll_save(_asset) {
    scr_line_coll_push_undo(_asset.meta);   // a TEXT EDIT save can be undone too
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
    var _x_max      = 255;
    if (_asset.meta.wide_x) {
        _x_max = 159;
    }
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

        var _x1 = clamp(_vals[0], 0, _x_max);
        var _y1 = clamp(_vals[1], 0, 255);
        var _x2 = clamp(_vals[2], 0, _x_max);
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
