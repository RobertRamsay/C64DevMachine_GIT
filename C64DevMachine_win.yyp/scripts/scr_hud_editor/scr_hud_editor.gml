/// @function scr_hud_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my)
/// @desc Inline editor for HUD assets — the whole 40x25 text screen drawn with
///       the game's own charset, with the HUD's rectangle live and everything
///       outside it dimmed, so a status panel can be laid out where it will
///       actually appear instead of being poked in blind.
///
/// MOUSE
///   left            paint the active char + colour, and move the type cursor
///   left drag       keep painting
///   right           erase to space (colour is left alone)
///   alt + left      pick the char and colour under the cursor
///   shift + left    move the selected FIELD here
///
/// KEYBOARD (canvas)
///   typing          writes at the cursor and advances — this is how the text
///                   of a panel gets in; click where it starts and type it
///   backspace       step back and clear
///   arrows          move the cursor
///   ctrl+Z / ctrl+Y undo / redo
///
/// FIELDS are the cells the game rewrites at runtime. They are listed on the
/// right, drawn as outlined runs on the canvas, and each one becomes an entry
/// point on the MACRO_HUD node — see scr_hud_create for what the kinds mean.
function scr_hud_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {

    var _m = _asset.meta;

    // ── Everything below assumes a full meta. An asset from an older save is
    //    seeded by the loader, so the only gap that can reach here is a field
    //    added after this build shipped.
    if (!variable_struct_exists(_m, "hud_w"))    { scr_hud_create(_asset); _m = _asset.meta; }
    if (!variable_struct_exists(_m, "cur_x"))    { _m.cur_x = 0; _m.cur_y = 0; }
    if (!variable_struct_exists(_m, "atlas_hr")) { _m.atlas_hr = -1; _m.atlas_mcs = -1; _m.atlas_mcf = -1; _m.atlas_key = ""; }

    var _ctrl  = scr_ctrl_held();
    var _shift = keyboard_check(vk_shift);
    var _alt   = keyboard_check(vk_alt);

    // ── LINKED CHARSET ──
    var _chr = noone;
    if (_m.chr_asset != "" && instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "CHAR_SET" && _a.name == _m.chr_asset) {
                _chr = _a;
                break;
            }
        }
    }

    var _chr_mc = false;
    if (_chr != noone) {
        if (variable_struct_exists(_chr.meta, "mc_mode")) {
            if (_chr.meta.mc_mode == 1) {
                _chr_mc = true;
            }
        }
    }

    var _bg_col = _m.hud_mc_bg;
    if (_bg_col < 0) {
        _bg_col = 0;
        if (_chr != noone && variable_struct_exists(_chr.meta, "mc_bg")) {
            _bg_col = _chr.meta.mc_bg;
        }
    }

    var _have_atlas = scr_hud_atlas(_asset, _chr);

    // ── UNDO ──
    var _push_undo = function(_mm) {
        array_push(_mm.undo_stack, {
            char_grid   : array_copy_shallow(_mm.char_grid),
            colour_grid : array_copy_shallow(_mm.colour_grid)
        });
        if (array_length(_mm.undo_stack) > 60) {
            array_delete(_mm.undo_stack, 0, 1);
        }
        _mm.redo_stack = [];
    };

    draw_set_font(fnt_c64_tiny);

    // ===============================================================
    // HEADER — rect, charset, view toggles
    // ===============================================================
    var _hy  = _cy;
    var _hx  = _vx1 + 10;

    var _rect_fields = ["X", "Y", "W", "H"];
    var _rect_vals   = [_m.hud_x, _m.hud_y, _m.hud_w, _m.hud_h];
    var _rect_max    = [39, 24, 40, 25];
    var _rect_min    = [0, 0, 1, 1];

    draw_set_color(c_ltgray);
    draw_text(_hx, _hy + 3, "RECT:");

    var _fx = _hx + 46;
    for (var _ri = 0; _ri < 4; _ri++) {
        draw_set_color(make_color_rgb(120, 120, 140));
        draw_text(_fx, _hy + 3, _rect_fields[_ri]);

        var _mbx1 = _fx + 14;
        var _mbx2 = _mbx1 + 14;
        var _pbx1 = _mbx2 + 30;
        var _pbx2 = _pbx1 + 14;

        var _mhov = point_in_rectangle(_mx, _my, _mbx1, _hy, _mbx2, _hy + 16);
        var _phov = point_in_rectangle(_mx, _my, _pbx1, _hy, _pbx2, _hy + 16);

        draw_set_color(make_color_rgb(40, 40, 60));
        if (_mhov) { draw_set_color(make_color_rgb(70, 70, 100)); }
        draw_rectangle(_mbx1, _hy, _mbx2, _hy + 16, false);
        draw_set_color(make_color_rgb(40, 40, 60));
        if (_phov) { draw_set_color(make_color_rgb(70, 70, 100)); }
        draw_rectangle(_pbx1, _hy, _pbx2, _hy + 16, false);

        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_mbx1 + 7, _hy + 3, "-");
        draw_text(_pbx1 + 7, _hy + 3, "+");
        draw_set_color(c_aqua);
        draw_text(_mbx2 + 15, _hy + 3, string(_rect_vals[_ri]));
        draw_set_halign(fa_left);

        var _delta = 0;
        if (_mhov && mouse_check_button_pressed(mb_left)) { _delta = -1; }
        if (_phov && mouse_check_button_pressed(mb_left)) { _delta =  1; }
        if (_delta != 0) {
            var _nv = clamp(_rect_vals[_ri] + _delta, _rect_min[_ri], _rect_max[_ri]);
            if (_ri == 0) { _m.hud_x = min(_nv, 40 - _m.hud_w); }
            if (_ri == 1) { _m.hud_y = min(_nv, 25 - _m.hud_h); }
            if (_ri == 2) {
                // Grow/shrink keeps the cells that survive: rebuild row by row
                // rather than letting the flat array slide sideways a cell per
                // row, which would shear the whole panel.
                var _ow = _m.hud_w;
                var _nw = min(_nv, 40 - _m.hud_x);
                if (_nw != _ow) {
                    _push_undo(_m);
                    var _nc = array_create(_nw * _m.hud_h, 32);
                    var _nk = array_create(_nw * _m.hud_h, _m.active_colour);
                    for (var _r = 0; _r < _m.hud_h; _r++) {
                        for (var _c = 0; _c < min(_ow, _nw); _c++) {
                            _nc[_r * _nw + _c] = _m.char_grid[_r * _ow + _c];
                            _nk[_r * _nw + _c] = _m.colour_grid[_r * _ow + _c];
                        }
                    }
                    _m.char_grid   = _nc;
                    _m.colour_grid = _nk;
                    _m.hud_w       = _nw;
                }
            }
            if (_ri == 3) {
                var _nh = min(_nv, 25 - _m.hud_y);
                if (_nh != _m.hud_h) {
                    _push_undo(_m);
                    _m.hud_h = _nh;
                }
            }
            _m.cur_x = clamp(_m.cur_x, 0, _m.hud_w - 1);
            _m.cur_y = clamp(_m.cur_y, 0, _m.hud_h - 1);
            scr_hud_flush(_asset);
            global.addresses_dirty = true;
        }
        _fx = _pbx2 + 40;
    }

    // ── CHARSET PICKER — click cycles, right-click clears ──
    var _cbx1 = _fx + 10;
    var _cbx2 = _cbx1 + 190;
    var _chov = point_in_rectangle(_mx, _my, _cbx1, _hy, _cbx2, _hy + 16);
    draw_set_color(make_color_rgb(20, 35, 25));
    if (_chov) { draw_set_color(make_color_rgb(40, 80, 60)); }
    draw_rectangle(_cbx1, _hy, _cbx2, _hy + 16, false);
    draw_set_color(make_color_rgb(150, 150, 150));
    if (_m.chr_asset != "") { draw_set_color(c_lime); }
    var _cb_label = "CHARSET: -- PICK --";
    if (_m.chr_asset != "") { _cb_label = "CHARSET: " + _m.chr_asset; }
    draw_text(_cbx1 + 6, _hy + 3, _cb_label);

    if (_chov && (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right))) {
        var _sets = [];
        if (instance_exists(obj_asset_manager)) {
            var _am2 = obj_asset_manager;
            for (var _si = 0; _si < ds_list_size(_am2.asset_list); _si++) {
                var _sa = ds_list_find_value(_am2.asset_list, _si);
                if (_sa.type == "CHAR_SET") {
                    array_push(_sets, _sa.name);
                }
            }
        }
        if (mouse_check_button_pressed(mb_right) || array_length(_sets) == 0) {
            _m.chr_asset = "";
        } else {
            var _cur = -1;
            for (var _si = 0; _si < array_length(_sets); _si++) {
                if (_sets[_si] == _m.chr_asset) {
                    _cur = _si;
                    break;
                }
            }
            _m.chr_asset = _sets[(_cur + 1) mod array_length(_sets)];
        }
        _m.atlas_key = "";
    }

    // ── PAINT MC toggle (multicolour charsets only) ──
    var _mcx1 = _cbx2 + 10;
    var _mcx2 = _mcx1 + 80;
    if (_chr_mc) {
        var _mc_on = 0;
        if ((_m.active_colour & 8) != 0) { _mc_on = 1; }
        var _mhov2 = point_in_rectangle(_mx, _my, _mcx1, _hy, _mcx2, _hy + 16);
        var _mc_cols  = [make_color_rgb(30, 30, 45), make_color_rgb(160, 80, 20)];
        var _mc_tcols = [make_color_rgb(80, 80, 100), make_color_rgb(255, 160, 60)];
        draw_set_color(_mc_cols[_mc_on]);
        draw_rectangle(_mcx1, _hy, _mcx2, _hy + 16, false);
        draw_set_color(_mc_tcols[_mc_on]);
        draw_set_halign(fa_center);
        var _mc_lbl = "CELL HR";
        if (_mc_on == 1) { _mc_lbl = "CELL MC"; }
        draw_text((_mcx1 + _mcx2) * 0.5, _hy + 3, _mc_lbl);
        draw_set_halign(fa_left);
        if (_mhov2 && mouse_check_button_pressed(mb_left)) {
            _m.active_colour = _m.active_colour ^ 8;
        }
    }

    // ── GRID toggle ──
    var _gbx1 = _mcx2 + 10;
    var _gbx2 = _gbx1 + 70;
    var _ghov = point_in_rectangle(_mx, _my, _gbx1, _hy, _gbx2, _hy + 16);
    draw_set_color(make_color_rgb(30, 30, 45));
    if (_ghov) { draw_set_color(make_color_rgb(60, 60, 80)); }
    draw_rectangle(_gbx1, _hy, _gbx2, _hy + 16, false);
    draw_set_color(make_color_rgb(150, 150, 170));
    draw_set_halign(fa_center);
    var _g_lbl = "GRID OFF";
    if (_m.show_grid == 1) { _g_lbl = "GRID ON"; }
    draw_text((_gbx1 + _gbx2) * 0.5, _hy + 3, _g_lbl);
    draw_set_halign(fa_left);
    if (_ghov && mouse_check_button_pressed(mb_left)) {
        _m.show_grid = 1 - _m.show_grid;
    }

    _cy = _hy + 24;

    // ===============================================================
    // CANVAS — the whole 40x25 screen
    // ===============================================================
    var _cs  = 8 * _m.zoom * 1.5;      // zoom 2 -> 24px cells
    _cs = floor(_cs);
    var _cvx = _vx1 + 10;
    var _cvy = _cy;
    var _cvw = 40 * _cs;
    var _cvh = 25 * _cs;

    // Border frame around the screen, the way a C64 shows it.
    draw_set_color(scr_c64_pepto_colour(_bg_col));
    draw_rectangle(_cvx - 8, _cvy - 8, _cvx + _cvw + 8, _cvy + _cvh + 8, false);
    draw_set_color(make_color_rgb(70, 70, 90));
    draw_rectangle(_cvx - 8, _cvy - 8, _cvx + _cvw + 8, _cvy + _cvh + 8, true);

    var _atl_cell = 16;   // scr_hud_atlas cell size

    for (var _sr = 0; _sr < 25; _sr++) {
        for (var _sc = 0; _sc < 40; _sc++) {

            var _px = _cvx + _sc * _cs;
            var _py = _cvy + _sr * _cs;

            var _in_rect = (_sc >= _m.hud_x && _sc < _m.hud_x + _m.hud_w
                         && _sr >= _m.hud_y && _sr < _m.hud_y + _m.hud_h);

            if (!_in_rect) {
                // Outside the panel: just the background, dimmed, so the HUD
                // reads as sitting on a screen rather than floating.
                draw_set_color(scr_c64_pepto_colour(_bg_col));
                draw_rectangle(_px, _py, _px + _cs - 1, _py + _cs - 1, false);
                draw_set_color(c_black);
                draw_set_alpha(0.45);
                draw_rectangle(_px, _py, _px + _cs - 1, _py + _cs - 1, false);
                draw_set_alpha(1.0);
                continue;
            }

            var _idx  = (_sr - _m.hud_y) * _m.hud_w + (_sc - _m.hud_x);
            var _char = _m.char_grid[_idx]   & 0xFF;
            var _colv = _m.colour_grid[_idx] & 0x0F;

            draw_set_color(scr_c64_pepto_colour(_bg_col));
            draw_rectangle(_px, _py, _px + _cs - 1, _py + _cs - 1, false);

            if (_have_atlas) {
                var _ax = (_char mod 16) * _atl_cell;
                var _ay = (_char div 16) * _atl_cell;
                var _sx = _cs / _atl_cell;

                var _cell_mc = false;
                if (_chr_mc && (_colv & 8) != 0) {
                    _cell_mc = true;
                }
                if (_cell_mc) {
                    draw_surface_part_ext(_m.atlas_mcs, _ax, _ay, _atl_cell, _atl_cell,
                                          _px, _py, _sx, _sx, c_white, 1);
                    draw_surface_part_ext(_m.atlas_mcf, _ax, _ay, _atl_cell, _atl_cell,
                                          _px, _py, _sx, _sx, scr_c64_pepto_colour(_colv & 7), 1);
                } else {
                    draw_surface_part_ext(_m.atlas_hr, _ax, _ay, _atl_cell, _atl_cell,
                                          _px, _py, _sx, _sx, scr_c64_pepto_colour(_colv), 1);
                }
            } else {
                // No charset linked yet — show the code, so a panel imported
                // from a real game is still readable as data.
                if (_char != 32 && _cs >= 14) {
                    draw_set_color(scr_c64_pepto_colour(_colv));
                    draw_set_halign(fa_center);
                    draw_text(_px + _cs * 0.5, _py + _cs * 0.5 - 4, string(_char));
                    draw_set_halign(fa_left);
                }
            }

            if (_m.show_grid == 1) {
                draw_set_color(make_color_rgb(45, 45, 60));
                draw_set_alpha(0.5);
                draw_rectangle(_px, _py, _px + _cs - 1, _py + _cs - 1, true);
                draw_set_alpha(1.0);
            }
        }
    }

    // Panel outline
    draw_set_color(make_color_rgb(90, 200, 255));
    draw_rectangle(_cvx + _m.hud_x * _cs, _cvy + _m.hud_y * _cs,
                   _cvx + (_m.hud_x + _m.hud_w) * _cs - 1,
                   _cvy + (_m.hud_y + _m.hud_h) * _cs - 1, true);

    // ── FIELD OVERLAYS ──
    for (var _fi = 0; _fi < array_length(_m.fields); _fi++) {
        var _f  = _m.fields[_fi];
        var _fx1 = _cvx + (_m.hud_x + _f.fx) * _cs;
        var _fy1 = _cvy + (_m.hud_y + _f.fy) * _cs;
        var _fx2 = _fx1 + _f.flen * _cs - 1;
        var _fy2 = _fy1 + _cs - 1;

        var _fcol = make_color_rgb(255, 200, 60);
        if (_fi == _m.sel_field) {
            _fcol = make_color_rgb(255, 80, 160);
        }
        draw_set_color(_fcol);
        draw_set_alpha(0.18);
        draw_rectangle(_fx1, _fy1, _fx2, _fy2, false);
        draw_set_alpha(1.0);
        draw_rectangle(_fx1, _fy1, _fx2, _fy2, true);
        draw_set_font(fnt_c64_tiny);
        draw_text(_fx1 + 1, _fy1 - 11, _f.name);
    }

    // ── TYPE CURSOR ──
    if ((current_time mod 700) < 420) {
        draw_set_color(c_white);
        var _tcx = _cvx + (_m.hud_x + _m.cur_x) * _cs;
        var _tcy = _cvy + (_m.hud_y + _m.cur_y) * _cs;
        draw_rectangle(_tcx, _tcy + _cs - 3, _tcx + _cs - 1, _tcy + _cs - 1, false);
    }

    // ── CANVAS INPUT ──
    var _hov_cell = point_in_rectangle(_mx, _my, _cvx, _cvy, _cvx + _cvw - 1, _cvy + _cvh - 1);
    var _hcol = -1;
    var _hrow = -1;
    if (_hov_cell) {
        _hcol = (_mx - _cvx) div _cs;
        _hrow = (_my - _cvy) div _cs;
    }

    var _in_panel = (_hcol >= _m.hud_x && _hcol < _m.hud_x + _m.hud_w
                  && _hrow >= _m.hud_y && _hrow < _m.hud_y + _m.hud_h);

    if (_hov_cell && _in_panel && !_m.name_edit_active) {

        var _rx  = _hcol - _m.hud_x;
        var _ry  = _hrow - _m.hud_y;
        var _idx = _ry * _m.hud_w + _rx;

        // Hover highlight
        draw_set_color(c_white);
        draw_set_alpha(0.22);
        draw_rectangle(_cvx + _hcol * _cs, _cvy + _hrow * _cs,
                       _cvx + _hcol * _cs + _cs - 1, _cvy + _hrow * _cs + _cs - 1, false);
        draw_set_alpha(1.0);

        if (_alt) {
            // PICK — same gesture as the map editor's tile picker.
            if (mouse_check_button_pressed(mb_left)) {
                _m.active_char   = _m.char_grid[_idx];
                _m.active_colour = _m.colour_grid[_idx];
            }
        } else if (_shift) {
            // MOVE THE SELECTED FIELD
            if (mouse_check_button_pressed(mb_left) && _m.sel_field >= 0
            &&  _m.sel_field < array_length(_m.fields)) {
                var _sf = _m.fields[_m.sel_field];
                _sf.fx = min(_rx, _m.hud_w - _sf.flen);
                _sf.fy = _ry;
                if (_sf.fx < 0) { _sf.fx = 0; }
            }
        } else {
            if (mouse_check_button_pressed(mb_left)) {
                _push_undo(_m);
                _m.cur_x = _rx;
                _m.cur_y = _ry;
            }
            if (mouse_check_button(mb_left)) {
                _m.char_grid[_idx]   = _m.active_char;
                _m.colour_grid[_idx] = _m.active_colour;
                scr_hud_flush(_asset);
            }
            if (mouse_check_button_pressed(mb_right)) {
                _push_undo(_m);
            }
            if (mouse_check_button(mb_right)) {
                _m.char_grid[_idx] = 32;
                scr_hud_flush(_asset);
            }
        }
    }

    // ── KEYBOARD: TYPE INTO THE PANEL ──
    if (!_m.name_edit_active) {

        if (keyboard_check_pressed(vk_left))  { _m.cur_x = max(0, _m.cur_x - 1); }
        if (keyboard_check_pressed(vk_right)) { _m.cur_x = min(_m.hud_w - 1, _m.cur_x + 1); }
        if (keyboard_check_pressed(vk_up))    { _m.cur_y = max(0, _m.cur_y - 1); }
        if (keyboard_check_pressed(vk_down))  { _m.cur_y = min(_m.hud_h - 1, _m.cur_y + 1); }

        if (keyboard_check_pressed(vk_backspace)) {
            _push_undo(_m);
            _m.cur_x = max(0, _m.cur_x - 1);
            _m.char_grid[_m.cur_y * _m.hud_w + _m.cur_x] = 32;
            scr_hud_flush(_asset);
        }

        if (_ctrl && keyboard_check_pressed(ord("Z")) && array_length(_m.undo_stack) > 0) {
            var _snap = array_pop(_m.undo_stack);
            array_push(_m.redo_stack, {
                char_grid   : array_copy_shallow(_m.char_grid),
                colour_grid : array_copy_shallow(_m.colour_grid)
            });
            _m.char_grid   = _snap.char_grid;
            _m.colour_grid = _snap.colour_grid;
            scr_hud_flush(_asset);
        }
        if (_ctrl && keyboard_check_pressed(ord("Y")) && array_length(_m.redo_stack) > 0) {
            var _snap2 = array_pop(_m.redo_stack);
            array_push(_m.undo_stack, {
                char_grid   : array_copy_shallow(_m.char_grid),
                colour_grid : array_copy_shallow(_m.colour_grid)
            });
            _m.char_grid   = _snap2.char_grid;
            _m.colour_grid = _snap2.colour_grid;
            scr_hud_flush(_asset);
        }

        if (!_ctrl && keyboard_string != "") {
            var _typed = scr_strip_key_ghosts(keyboard_string);
            if (_typed != "") {
                _push_undo(_m);
                for (var _ti = 1; _ti <= string_length(_typed); _ti++) {
                    var _sc_code = scr_hud_screen_code(ord(string_char_at(_typed, _ti)));
                    _m.char_grid[_m.cur_y * _m.hud_w + _m.cur_x]   = _sc_code;
                    _m.colour_grid[_m.cur_y * _m.hud_w + _m.cur_x] = _m.active_colour;
                    _m.cur_x += 1;
                    if (_m.cur_x >= _m.hud_w) {
                        _m.cur_x = 0;
                        _m.cur_y = min(_m.hud_h - 1, _m.cur_y + 1);
                    }
                }
                scr_hud_flush(_asset);
            }
            keyboard_string = "";
        }
    }

    // ===============================================================
    // CHAR STRIP + COLOUR STRIP (under the canvas)
    // ===============================================================
    var _sy = _cvy + _cvh + 18;

    draw_set_color(c_ltgray);
    draw_text(_cvx, _sy + 3, "PAINT:");

    // Active char swatch
    var _swx = _cvx + 56;
    var _swz = 28;
    draw_set_color(scr_c64_pepto_colour(_bg_col));
    draw_rectangle(_swx, _sy, _swx + _swz, _sy + _swz, false);
    if (_have_atlas) {
        var _sax = (_m.active_char mod 16) * _atl_cell;
        var _say = (_m.active_char div 16) * _atl_cell;
        var _scale_sw = _swz / _atl_cell;
        if (_chr_mc && (_m.active_colour & 8) != 0) {
            draw_surface_part_ext(_m.atlas_mcs, _sax, _say, _atl_cell, _atl_cell,
                                  _swx, _sy, _scale_sw, _scale_sw, c_white, 1);
            draw_surface_part_ext(_m.atlas_mcf, _sax, _say, _atl_cell, _atl_cell,
                                  _swx, _sy, _scale_sw, _scale_sw, scr_c64_pepto_colour(_m.active_colour & 7), 1);
        } else {
            draw_surface_part_ext(_m.atlas_hr, _sax, _say, _atl_cell, _atl_cell,
                                  _swx, _sy, _scale_sw, _scale_sw, scr_c64_pepto_colour(_m.active_colour & 0x0F), 1);
        }
    }
    draw_set_color(c_white);
    draw_rectangle(_swx, _sy, _swx + _swz, _sy + _swz, true);
    draw_text(_swx + _swz + 6, _sy + 3, "CHR " + string(_m.active_char));
    draw_text(_swx + _swz + 6, _sy + 15, "COL " + string(_m.active_colour));

    // Colour swatches
    var _colx = _swx + _swz + 80;
    for (var _ci = 0; _ci < 16; _ci++) {
        var _cx1 = _colx + _ci * 20;
        var _chov2 = point_in_rectangle(_mx, _my, _cx1, _sy, _cx1 + 18, _sy + 18);
        draw_set_color(scr_c64_pepto_colour(_ci));
        draw_rectangle(_cx1, _sy, _cx1 + 18, _sy + 18, false);
        draw_set_color(make_color_rgb(60, 60, 80));
        if ((_m.active_colour & 0x0F) == _ci) { draw_set_color(c_white); }
        if (_chov2) { draw_set_color(c_yellow); }
        draw_rectangle(_cx1, _sy, _cx1 + 18, _sy + 18, true);
        if (_chov2 && mouse_check_button_pressed(mb_left)) {
            _m.active_colour = _ci;
        }
        if (_chov2 && mouse_check_button_pressed(mb_right)) {
            _m.hud_mc_bg = _ci;
            _m.atlas_key = "";
        }
    }
    draw_set_color(make_color_rgb(110, 110, 130));
    draw_text(_colx, _sy + 22, "LEFT = PAINT COLOUR   RIGHT = SCREEN BACKGROUND ($D021 = " + string(_bg_col) + ")");

    // Char strip — every code 0-255, 32 per row
    var _csy = _sy + 40;
    var _cssz = 18;
    draw_set_color(c_ltgray);
    draw_text(_cvx, _csy - 12, "CHARSET  (CLICK A CHAR, OR ALT+CLICK THE PANEL TO PICK ONE)");
    for (var _ki = 0; _ki < 256; _ki++) {
        var _kx = _cvx + (_ki mod 32) * _cssz;
        var _ky = _csy + (_ki div 32) * _cssz;
        draw_set_color(scr_c64_pepto_colour(_bg_col));
        draw_rectangle(_kx, _ky, _kx + _cssz - 1, _ky + _cssz - 1, false);
        if (_have_atlas) {
            var _kax = (_ki mod 16) * _atl_cell;
            var _kay = (_ki div 16) * _atl_cell;
            var _ksc = _cssz / _atl_cell;
            draw_surface_part_ext(_m.atlas_hr, _kax, _kay, _atl_cell, _atl_cell,
                                  _kx, _ky, _ksc, _ksc, scr_c64_pepto_colour(_m.active_colour & 0x0F), 1);
        }
        var _khov = point_in_rectangle(_mx, _my, _kx, _ky, _kx + _cssz - 1, _ky + _cssz - 1);
        if (_ki == _m.active_char) {
            draw_set_color(c_white);
            draw_rectangle(_kx, _ky, _kx + _cssz - 1, _ky + _cssz - 1, true);
        } else if (_khov) {
            draw_set_color(c_yellow);
            draw_rectangle(_kx, _ky, _kx + _cssz - 1, _ky + _cssz - 1, true);
        }
        if (_khov && mouse_check_button_pressed(mb_left)) {
            _m.active_char = _ki;
        }
    }

    // ===============================================================
    // FIELDS PANEL (right of the canvas)
    // ===============================================================
    var _fpx = _cvx + _cvw + 26;
    var _fpw = 360;
    if (_fpx + _fpw > _vx2 - 10) {
        _fpw = (_vx2 - 10) - _fpx;
    }
    var _fpy = _cvy;

    if (_fpw > 120) {

        draw_set_color(make_color_rgb(26, 26, 40));
        draw_rectangle(_fpx, _fpy, _fpx + _fpw, _fpy + 420, false);
        draw_set_color(make_color_rgb(60, 60, 85));
        draw_rectangle(_fpx, _fpy, _fpx + _fpw, _fpy + 420, true);

        draw_set_color(make_color_rgb(255, 200, 60));
        draw_text(_fpx + 8, _fpy + 6, "FIELDS  —  CELLS THE GAME WRITES");
        draw_set_color(make_color_rgb(110, 110, 130));
        draw_text(_fpx + 8, _fpy + 20, "EACH ONE BECOMES AN ENTRY POINT ON THE HUD NODE");

        // ADD / DEL
        var _abx1 = _fpx + 8;
        var _abx2 = _abx1 + 90;
        var _aby  = _fpy + 36;
        var _ahov = point_in_rectangle(_mx, _my, _abx1, _aby, _abx2, _aby + 18);
        draw_set_color(make_color_rgb(30, 80, 40));
        if (_ahov) { draw_set_color(make_color_rgb(60, 160, 80)); }
        draw_rectangle(_abx1, _aby, _abx2, _aby + 18, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text((_abx1 + _abx2) * 0.5, _aby + 4, "+ FIELD");
        draw_set_halign(fa_left);
        if (_ahov && mouse_check_button_pressed(mb_left)) {
            array_push(_m.fields, {
                name  : "FIELD" + string(array_length(_m.fields)),
                fx    : _m.cur_x,
                fy    : _m.cur_y,
                flen  : 2,
                kind  : 1,          // DIGITS — the common case
                base  : 48,         // screen code of '0' in a stock charset
                pad   : 0,
                full  : 81,
                empty : 32
            });
            _m.sel_field = array_length(_m.fields) - 1;
            global.addresses_dirty = true;
        }

        var _dbx1 = _abx2 + 10;
        var _dbx2 = _dbx1 + 70;
        var _dhov = point_in_rectangle(_mx, _my, _dbx1, _aby, _dbx2, _aby + 18);
        draw_set_color(make_color_rgb(80, 30, 30));
        if (_dhov) { draw_set_color(make_color_rgb(170, 60, 60)); }
        draw_rectangle(_dbx1, _aby, _dbx2, _aby + 18, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text((_dbx1 + _dbx2) * 0.5, _aby + 4, "DELETE");
        draw_set_halign(fa_left);
        if (_dhov && mouse_check_button_pressed(mb_left) && _m.sel_field >= 0
        &&  _m.sel_field < array_length(_m.fields)) {
            array_delete(_m.fields, _m.sel_field, 1);
            _m.sel_field = -1;
            _m.name_edit_active = false;
            global.addresses_dirty = true;
        }

        // LIST
        var _ly = _aby + 26;
        for (var _fi = 0; _fi < array_length(_m.fields); _fi++) {
            if (_fi >= 12) {
                break;
            }
            var _f    = _m.fields[_fi];
            var _ry1  = _ly + _fi * 16;
            var _rhov = point_in_rectangle(_mx, _my, _fpx + 8, _ry1, _fpx + _fpw - 8, _ry1 + 14);

            if (_fi == _m.sel_field) {
                draw_set_color(make_color_rgb(60, 30, 60));
                draw_rectangle(_fpx + 8, _ry1, _fpx + _fpw - 8, _ry1 + 14, false);
            } else if (_rhov) {
                draw_set_color(make_color_rgb(40, 40, 60));
                draw_rectangle(_fpx + 8, _ry1, _fpx + _fpw - 8, _ry1 + 14, false);
            }

            var _kind_names = ["TEXT", "DIGITS", "BAR"];
            draw_set_color(c_white);
            draw_text(_fpx + 12, _ry1 + 2, _f.name);
            draw_set_color(make_color_rgb(140, 140, 170));
            draw_text(_fpx + 150, _ry1 + 2, _kind_names[_f.kind]);
            draw_text(_fpx + 220, _ry1 + 2, string(_f.fx) + "," + string(_f.fy));
            draw_text(_fpx + 285, _ry1 + 2, "LEN " + string(_f.flen));

            if (_rhov && mouse_check_button_pressed(mb_left)) {
                _m.sel_field        = _fi;
                _m.name_edit_active = false;
            }
        }

        // SELECTED FIELD PROPERTIES
        if (_m.sel_field >= 0 && _m.sel_field < array_length(_m.fields)) {

            var _f2  = _m.fields[_m.sel_field];
            var _py2 = _ly + 12 * 16 + 14;

            draw_set_color(make_color_rgb(255, 80, 160));
            draw_text(_fpx + 8, _py2, "SELECTED FIELD");
            _py2 += 16;

            // NAME (click to edit)
            draw_set_color(c_ltgray);
            draw_text(_fpx + 8, _py2 + 3, "NAME:");
            var _nbx1 = _fpx + 60;
            var _nbx2 = _fpx + _fpw - 10;
            var _nhov = point_in_rectangle(_mx, _my, _nbx1, _py2, _nbx2, _py2 + 16);
            draw_set_color(make_color_rgb(20, 35, 25));
            if (_m.name_edit_active) { draw_set_color(make_color_rgb(20, 60, 30)); }
            draw_rectangle(_nbx1, _py2, _nbx2, _py2 + 16, false);
            draw_set_color(c_lime);
            if (_m.name_edit_active) {
                var _blink = " ";
                if ((current_time mod 600) < 300) { _blink = "_"; }
                draw_text(_nbx1 + 5, _py2 + 3, _m.name_edit_buf + _blink);
            } else {
                draw_text(_nbx1 + 5, _py2 + 3, _f2.name);
            }
            if (_nhov && mouse_check_button_pressed(mb_left) && !_m.name_edit_active) {
                _m.name_edit_active = true;
                _m.name_edit_buf    = _f2.name;
                keyboard_string     = "";
            }
            _py2 += 22;

            if (_m.name_edit_active) {
                if (keyboard_check_pressed(vk_backspace) && string_length(_m.name_edit_buf) > 0) {
                    _m.name_edit_buf = string_delete(_m.name_edit_buf, string_length(_m.name_edit_buf), 1);
                }
                if (keyboard_string != "") {
                    var _nt = scr_strip_key_ghosts(keyboard_string);
                    for (var _ni = 1; _ni <= string_length(_nt); _ni++) {
                        var _nch = string_upper(string_char_at(_nt, _ni));
                        var _ok  = false;
                        if (_nch >= "A" && _nch <= "Z") { _ok = true; }
                        if (_nch >= "0" && _nch <= "9" && string_length(_m.name_edit_buf) > 0) { _ok = true; }
                        if (_nch == "_") { _ok = true; }
                        if (_ok && string_length(_m.name_edit_buf) < 16) {
                            _m.name_edit_buf += _nch;
                        }
                    }
                    keyboard_string = "";
                }
                if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_escape)) {
                    if (keyboard_check_pressed(vk_enter) && _m.name_edit_buf != "") {
                        _f2.name = _m.name_edit_buf;
                        global.addresses_dirty = true;
                    }
                    _m.name_edit_active = false;
                    keyboard_string     = "";
                }
            }

            // KIND
            var _kbx1 = _fpx + 60;
            var _kbx2 = _kbx1 + 110;
            var _khov2 = point_in_rectangle(_mx, _my, _kbx1, _py2, _kbx2, _py2 + 16);
            draw_set_color(c_ltgray);
            draw_text(_fpx + 8, _py2 + 3, "KIND:");
            draw_set_color(make_color_rgb(40, 40, 70));
            if (_khov2) { draw_set_color(make_color_rgb(70, 70, 110)); }
            draw_rectangle(_kbx1, _py2, _kbx2, _py2 + 16, false);
            draw_set_color(c_aqua);
            var _kind_names2 = ["TEXT", "DIGITS", "BAR"];
            draw_set_halign(fa_center);
            draw_text((_kbx1 + _kbx2) * 0.5, _py2 + 3, _kind_names2[_f2.kind]);
            draw_set_halign(fa_left);
            if (_khov2 && mouse_check_button_pressed(mb_left)) {
                _f2.kind = (_f2.kind + 1) mod 3;
                global.addresses_dirty = true;
            }
            _py2 += 22;

            // LENGTH
            draw_set_color(c_ltgray);
            draw_text(_fpx + 8, _py2 + 3, "LEN:");
            var _lmx1 = _fpx + 60;
            var _lpx1 = _fpx + 110;
            var _lmhov = point_in_rectangle(_mx, _my, _lmx1, _py2, _lmx1 + 16, _py2 + 16);
            var _lphov = point_in_rectangle(_mx, _my, _lpx1, _py2, _lpx1 + 16, _py2 + 16);
            draw_set_color(make_color_rgb(40, 40, 60));
            if (_lmhov) { draw_set_color(make_color_rgb(70, 70, 100)); }
            draw_rectangle(_lmx1, _py2, _lmx1 + 16, _py2 + 16, false);
            draw_set_color(make_color_rgb(40, 40, 60));
            if (_lphov) { draw_set_color(make_color_rgb(70, 70, 100)); }
            draw_rectangle(_lpx1, _py2, _lpx1 + 16, _py2 + 16, false);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_text(_lmx1 + 8, _py2 + 3, "-");
            draw_text(_lpx1 + 8, _py2 + 3, "+");
            draw_set_color(c_aqua);
            draw_text(_lmx1 + 33, _py2 + 3, string(_f2.flen));
            draw_set_halign(fa_left);
            if (_lmhov && mouse_check_button_pressed(mb_left)) {
                _f2.flen = max(1, _f2.flen - 1);
                global.addresses_dirty = true;
            }
            if (_lphov && mouse_check_button_pressed(mb_left)) {
                _f2.flen = min(_m.hud_w - _f2.fx, _f2.flen + 1);
                global.addresses_dirty = true;
            }
            _py2 += 22;

            if (_f2.kind == 1) {
                // DIGITS: which glyph is '0', and what the leading cells show
                draw_set_color(c_ltgray);
                draw_text(_fpx + 8, _py2 + 3, "ZERO CHR:");
                var _zbx1 = _fpx + 90;
                var _zbx2 = _zbx1 + 130;
                var _zhov = point_in_rectangle(_mx, _my, _zbx1, _py2, _zbx2, _py2 + 16);
                draw_set_color(make_color_rgb(40, 40, 70));
                if (_zhov) { draw_set_color(make_color_rgb(70, 70, 110)); }
                draw_rectangle(_zbx1, _py2, _zbx2, _py2 + 16, false);
                draw_set_color(c_aqua);
                draw_set_halign(fa_center);
                draw_text((_zbx1 + _zbx2) * 0.5, _py2 + 3, string(_f2.base) + "  < TAKE ACTIVE");
                draw_set_halign(fa_left);
                if (_zhov && mouse_check_button_pressed(mb_left)) {
                    _f2.base = _m.active_char;
                }
                _py2 += 22;

                draw_set_color(c_ltgray);
                draw_text(_fpx + 8, _py2 + 3, "LEAD:");
                var _pbx1b = _fpx + 90;
                var _pbx2b = _pbx1b + 130;
                var _phov2 = point_in_rectangle(_mx, _my, _pbx1b, _py2, _pbx2b, _py2 + 16);
                draw_set_color(make_color_rgb(40, 40, 70));
                if (_phov2) { draw_set_color(make_color_rgb(70, 70, 110)); }
                draw_rectangle(_pbx1b, _py2, _pbx2b, _py2 + 16, false);
                draw_set_color(c_aqua);
                draw_set_halign(fa_center);
                var _pad_lbl = "ZEROS";
                if (_f2.pad == 1) { _pad_lbl = "BLANK"; }
                draw_text((_pbx1b + _pbx2b) * 0.5, _py2 + 3, _pad_lbl);
                draw_set_halign(fa_left);
                if (_phov2 && mouse_check_button_pressed(mb_left)) {
                    _f2.pad = 1 - _f2.pad;
                    global.addresses_dirty = true;
                }
                _py2 += 22;

                draw_set_color(make_color_rgb(110, 110, 130));
                draw_text(_fpx + 8, _py2, "A = VALUE 0-255, WRITTEN RIGHT-ALIGNED");
            }

            if (_f2.kind == 2) {
                // BAR: full and empty glyphs
                draw_set_color(c_ltgray);
                draw_text(_fpx + 8, _py2 + 3, "FULL CHR:");
                var _fbx1 = _fpx + 90;
                var _fbx2 = _fbx1 + 130;
                var _fhov2 = point_in_rectangle(_mx, _my, _fbx1, _py2, _fbx2, _py2 + 16);
                draw_set_color(make_color_rgb(40, 40, 70));
                if (_fhov2) { draw_set_color(make_color_rgb(70, 70, 110)); }
                draw_rectangle(_fbx1, _py2, _fbx2, _py2 + 16, false);
                draw_set_color(c_aqua);
                draw_set_halign(fa_center);
                draw_text((_fbx1 + _fbx2) * 0.5, _py2 + 3, string(_f2.full) + "  < TAKE ACTIVE");
                draw_set_halign(fa_left);
                if (_fhov2 && mouse_check_button_pressed(mb_left)) {
                    _f2.full = _m.active_char;
                }
                _py2 += 22;

                draw_set_color(c_ltgray);
                draw_text(_fpx + 8, _py2 + 3, "EMPTY CHR:");
                var _ebx1 = _fpx + 90;
                var _ebx2 = _ebx1 + 130;
                var _ehov = point_in_rectangle(_mx, _my, _ebx1, _py2, _ebx2, _py2 + 16);
                draw_set_color(make_color_rgb(40, 40, 70));
                if (_ehov) { draw_set_color(make_color_rgb(70, 70, 110)); }
                draw_rectangle(_ebx1, _py2, _ebx2, _py2 + 16, false);
                draw_set_color(c_aqua);
                draw_set_halign(fa_center);
                draw_text((_ebx1 + _ebx2) * 0.5, _py2 + 3, string(_f2.empty) + "  < TAKE ACTIVE");
                draw_set_halign(fa_left);
                if (_ehov && mouse_check_button_pressed(mb_left)) {
                    _f2.empty = _m.active_char;
                }
                _py2 += 22;

                draw_set_color(make_color_rgb(110, 110, 130));
                draw_text(_fpx + 8, _py2, "A = HOW MANY CELLS TO FILL");
            }

            if (_f2.kind == 0) {
                draw_set_color(make_color_rgb(110, 110, 130));
                draw_text(_fpx + 8, _py2, "POSITION ONLY — NO CODE EMITTED.");
                draw_text(_fpx + 8, _py2 + 12, "THE NODE SHOWS ITS SCREEN ADDRESS.");
            }

            draw_set_color(make_color_rgb(90, 90, 110));
            draw_text(_fpx + 8, _fpy + 398, "SHIFT+CLICK THE PANEL TO MOVE THIS FIELD");
        }
    }

    // ── HELP LINE ──
    draw_set_color(make_color_rgb(90, 90, 110));
    draw_text(_cvx, _csy + 8 * 18 + 6,
        "CLICK = PAINT + SET CURSOR   TYPE = TEXT   RIGHT = ERASE   ALT+CLICK = PICK   CTRL+Z/Y = UNDO/REDO");
}
