/// @function scr_hud_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my)
/// @desc Inline editor for HUD assets.
///
/// LAYOUT
///   toolbar      RECT x/y/w/h · CHARSET · SCREEN HR/MC · ZOOM
///   left         the whole 40x25 screen, panel live, outside dimmed;
///                under it the 256-char strip
///   right        TILE  — the charset's own 8x8 tile editor on the active char
///                PAINT — active char/colour, 16 swatches, CELL HR/MC
///                FIELDS — list + properties of the selected field
///
/// SCREEN HR / MC is the VIC's own text mode ($D016 bit 4). In MC the cells
/// whose colour RAM has bit 3 set render multicolour with three shared
/// colours plus colour RAM 0-7; in HR every cell is hi-res in colour 0-15.
/// The canvas, the char strip, the paint swatch and the tile editor all
/// follow it, so what is on screen is what the machine will show.
///
/// MOUSE (canvas)     left paint + set cursor · drag paints · right erase ·
///                    alt+left pick char+colour · shift+left move field
/// KEYBOARD (canvas)  type text · backspace · arrows · ctrl+Z / ctrl+Y
///                    (ctrl+Z/Y go to the TILE editor while the mouse is over it)
function scr_hud_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {

    var _m = _asset.meta;

    if (!variable_struct_exists(_m, "hud_w"))       { scr_hud_create(_asset); _m = _asset.meta; }
    if (!variable_struct_exists(_m, "hud_mc_mode")) { _m.hud_mc_mode = 0; }
    if (!variable_struct_exists(_m, "cur_x"))       { _m.cur_x = 0; _m.cur_y = 0; }
    if (!variable_struct_exists(_m, "atlas_hr"))    { _m.atlas_hr = -1; _m.atlas_mcs = -1; _m.atlas_mcf = -1; _m.atlas_key = ""; }

    var _ctrl  = scr_ctrl_held();
    var _shift = keyboard_check(vk_shift);
    var _alt   = keyboard_check(vk_alt);

    var _c_lbl   = make_color_rgb(140, 150, 180);
    var _c_dim   = make_color_rgb(95, 95, 115);
    var _c_head  = make_color_rgb(90, 220, 190);
    var _c_box   = make_color_rgb(24, 24, 36);
    var _c_edge  = make_color_rgb(56, 56, 78);
    var _c_btn   = make_color_rgb(38, 38, 58);
    var _c_btnh  = make_color_rgb(66, 66, 98);
    var _c_on    = make_color_rgb(160, 80, 20);
    var _c_ontx  = make_color_rgb(255, 160, 60);

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

    var _scr_mc = (_m.hud_mc_mode == 1);

    var _bg_col = _m.hud_mc_bg;
    if (_bg_col < 0) {
        _bg_col = 0;
        if (_chr != noone && variable_struct_exists(_chr.meta, "mc_bg")) { _bg_col = _chr.meta.mc_bg; }
    }
    var _col1 = _m.hud_mc_col1;
    if (_col1 < 0) {
        _col1 = 1;
        if (_chr != noone && variable_struct_exists(_chr.meta, "mc_col1")) { _col1 = _chr.meta.mc_col1; }
    }
    var _col2 = _m.hud_mc_col2;
    if (_col2 < 0) {
        _col2 = 2;
        if (_chr != noone && variable_struct_exists(_chr.meta, "mc_col2")) { _col2 = _chr.meta.mc_col2; }
    }

    var _have_atlas = scr_hud_atlas(_asset, _chr);

    // Draws one glyph cell at (_px,_py) of size _sz the way the current screen
    // mode would show it. Shared by the canvas, the strip and the swatch.
    var _draw_glyph = function(_mm, _px, _py, _sz, _char, _colv, _mc_screen) {
        var _ax = (_char mod 16) * 16;
        var _ay = (_char div 16) * 16;
        var _sc = _sz / 16;
        if (_mc_screen && (_colv & 8) != 0) {
            draw_surface_part_ext(_mm.atlas_mcs, _ax, _ay, 16, 16, _px, _py, _sc, _sc, c_white, 1);
            draw_surface_part_ext(_mm.atlas_mcf, _ax, _ay, 16, 16, _px, _py, _sc, _sc, scr_c64_pepto_colour(_colv & 7), 1);
        } else {
            draw_surface_part_ext(_mm.atlas_hr, _ax, _ay, 16, 16, _px, _py, _sc, _sc, scr_c64_pepto_colour(_colv & 15), 1);
        }
    };

    var _push_undo = function(_mm) {
        array_push(_mm.undo_stack, {
            char_grid   : array_copy_shallow(_mm.char_grid),
            colour_grid : array_copy_shallow(_mm.colour_grid)
        });
        if (array_length(_mm.undo_stack) > 60) { array_delete(_mm.undo_stack, 0, 1); }
        _mm.redo_stack = [];
    };

    // A small button: returns true on click. Label centred.
    var _button = function(_x1, _y1, _w, _h, _label, _on, _mx2, _my2, _cb, _cbh, _con, _ctx) {
        var _hov = point_in_rectangle(_mx2, _my2, _x1, _y1, _x1 + _w, _y1 + _h);
        var _bg = _cb;
        var _tx = c_white;
        if (_on) { _bg = _con; _tx = _ctx; }
        if (_hov && !_on) { _bg = _cbh; }
        draw_set_color(_bg);
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, false);
        draw_set_color(_tx);
        draw_set_halign(fa_center);
        draw_text(_x1 + _w * 0.5, _y1 + 3, _label);
        draw_set_halign(fa_left);
        return (_hov && mouse_check_button_pressed(mb_left));
    };

    draw_set_font(fnt_c64_tiny);

    // ===============================================================
    // GEOMETRY — the canvas cell size is the largest zoom that leaves room
    // for the char strip underneath, so nothing ever runs off the panel.
    // ===============================================================
    var _tool_y  = _cy;
    var _cvx     = _vx1 + 14;
    var _cvy     = _tool_y + 30;
    var _strip_h = 8 * 18;
    var _fit     = (_vy2 - 12) - _cvy - 30 - _strip_h - 16;      // room for 25 rows
    var _zoom_sizes = [16, 20, 24];
    var _cs_want = _zoom_sizes[clamp(_m.zoom, 1, 3) - 1];
    var _cs      = min(_cs_want, _fit div 25);
    if (_cs < 12) { _cs = 12; }
    var _cvw = 40 * _cs;
    var _cvh = 25 * _cs;
    var _rcx = _cvx + _cvw + 28;                    // right column
    var _rcw = (_vx2 - 12) - _rcx;

    // ===============================================================
    // TOOLBAR
    // ===============================================================
    var _tx = _cvx;
    draw_set_color(_c_lbl);
    draw_text(_tx, _tool_y + 3, "RECT");
    _tx += 34;

    var _rf_lbl = ["X", "Y", "W", "H"];
    var _rf_val = [_m.hud_x, _m.hud_y, _m.hud_w, _m.hud_h];
    for (var _ri = 0; _ri < 4; _ri++) {
        draw_set_color(_c_dim);
        draw_text(_tx, _tool_y + 3, _rf_lbl[_ri]);
        var _d = 0;
        if (_button(_tx + 12, _tool_y, 14, 16, "-", false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) { _d = -1; }
        draw_set_color(c_aqua);
        draw_set_halign(fa_center);
        draw_text(_tx + 38, _tool_y + 3, string(_rf_val[_ri]));
        draw_set_halign(fa_left);
        if (_button(_tx + 50, _tool_y, 14, 16, "+", false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) { _d = 1; }
        if (_d != 0) {
            if (_ri == 0) { _m.hud_x = clamp(_m.hud_x + _d, 0, 40 - _m.hud_w); }
            if (_ri == 1) { _m.hud_y = clamp(_m.hud_y + _d, 0, 25 - _m.hud_h); }
            if (_ri == 2) {
                var _ow = _m.hud_w;
                var _nw = clamp(_ow + _d, 1, 40 - _m.hud_x);
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
                    _m.char_grid = _nc;
                    _m.colour_grid = _nk;
                    _m.hud_w = _nw;
                }
            }
            if (_ri == 3) {
                var _nh = clamp(_m.hud_h + _d, 1, 25 - _m.hud_y);
                if (_nh != _m.hud_h) { _push_undo(_m); _m.hud_h = _nh; }
            }
            _m.cur_x = clamp(_m.cur_x, 0, _m.hud_w - 1);
            _m.cur_y = clamp(_m.cur_y, 0, _m.hud_h - 1);
            scr_hud_flush(_asset);
            global.addresses_dirty = true;
        }
        _tx += 76;
    }

    // CHARSET — click cycles, right-click clears
    _tx += 6;
    var _cb_w = 200;
    var _chov = point_in_rectangle(_mx, _my, _tx, _tool_y, _tx + _cb_w, _tool_y + 16);
    draw_set_color(make_color_rgb(20, 35, 25));
    if (_chov) { draw_set_color(make_color_rgb(40, 80, 60)); }
    draw_rectangle(_tx, _tool_y, _tx + _cb_w, _tool_y + 16, false);
    draw_set_color(make_color_rgb(150, 150, 150));
    var _cb_label = "CHARSET  -- PICK --";
    if (_m.chr_asset != "") { draw_set_color(c_lime); _cb_label = "CHARSET  " + _m.chr_asset; }
    draw_text(_tx + 6, _tool_y + 3, _cb_label);
    if (_chov && (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right))) {
        var _sets = [];
        if (instance_exists(obj_asset_manager)) {
            var _am2 = obj_asset_manager;
            for (var _si = 0; _si < ds_list_size(_am2.asset_list); _si++) {
                var _sa = ds_list_find_value(_am2.asset_list, _si);
                if (_sa.type == "CHAR_SET") { array_push(_sets, _sa.name); }
            }
        }
        if (mouse_check_button_pressed(mb_right) || array_length(_sets) == 0) {
            _m.chr_asset = "";
        } else {
            var _cur = -1;
            for (var _si = 0; _si < array_length(_sets); _si++) {
                if (_sets[_si] == _m.chr_asset) { _cur = _si; break; }
            }
            _m.chr_asset = _sets[(_cur + 1) mod array_length(_sets)];
        }
        _m.atlas_key = "";
    }
    _tx += _cb_w + 10;

    // SCREEN HR / MC
    var _sm_lbl = "SCREEN HR";
    if (_scr_mc) { _sm_lbl = "SCREEN MC"; }
    if (_button(_tx, _tool_y, 90, 16, _sm_lbl, _scr_mc, _mx, _my, _c_btn, _c_btnh, make_color_rgb(20, 60, 80), make_color_rgb(80, 200, 255))) {
        _m.hud_mc_mode = 1 - _m.hud_mc_mode;
    }
    _tx += 100;

    // ZOOM
    draw_set_color(_c_lbl);
    draw_text(_tx, _tool_y + 3, "ZOOM");
    if (_button(_tx + 36, _tool_y, 14, 16, "-", false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) { _m.zoom = max(1, _m.zoom - 1); }
    draw_set_color(c_aqua);
    draw_text(_tx + 55, _tool_y + 3, string(_m.zoom));
    if (_button(_tx + 66, _tool_y, 14, 16, "+", false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) { _m.zoom = min(3, _m.zoom + 1); }

    // ===============================================================
    // CANVAS — the whole 40x25 screen
    // ===============================================================
    draw_set_color(scr_c64_pepto_colour(_bg_col));
    draw_rectangle(_cvx - 8, _cvy - 8, _cvx + _cvw + 8, _cvy + _cvh + 8, false);
    draw_set_color(_c_edge);
    draw_rectangle(_cvx - 8, _cvy - 8, _cvx + _cvw + 8, _cvy + _cvh + 8, true);

    for (var _sr = 0; _sr < 25; _sr++) {
        for (var _sc = 0; _sc < 40; _sc++) {
            var _px = _cvx + _sc * _cs;
            var _py = _cvy + _sr * _cs;
            var _in_rect = (_sc >= _m.hud_x && _sc < _m.hud_x + _m.hud_w
                         && _sr >= _m.hud_y && _sr < _m.hud_y + _m.hud_h);

            draw_set_color(scr_c64_pepto_colour(_bg_col));
            draw_rectangle(_px, _py, _px + _cs - 1, _py + _cs - 1, false);

            if (!_in_rect) {
                draw_set_color(c_black);
                draw_set_alpha(0.5);
                draw_rectangle(_px, _py, _px + _cs - 1, _py + _cs - 1, false);
                draw_set_alpha(1.0);
                continue;
            }

            var _idx  = (_sr - _m.hud_y) * _m.hud_w + (_sc - _m.hud_x);
            var _char = _m.char_grid[_idx] & 0xFF;
            var _colv = _m.colour_grid[_idx] & 0x0F;

            if (_have_atlas) {
                _draw_glyph(_m, _px, _py, _cs, _char, _colv, _scr_mc);
            } else if (_char != 32 && _cs >= 14) {
                draw_set_color(scr_c64_pepto_colour(_colv));
                draw_set_halign(fa_center);
                draw_text(_px + _cs * 0.5, _py + _cs * 0.5 - 4, string(_char));
                draw_set_halign(fa_left);
            }
        }
    }

    // Panel outline
    draw_set_color(make_color_rgb(90, 200, 255));
    draw_rectangle(_cvx + _m.hud_x * _cs, _cvy + _m.hud_y * _cs,
                   _cvx + (_m.hud_x + _m.hud_w) * _cs - 1, _cvy + (_m.hud_y + _m.hud_h) * _cs - 1, true);

    // Field overlays
    for (var _fi = 0; _fi < array_length(_m.fields); _fi++) {
        var _f  = _m.fields[_fi];
        var _fx1 = _cvx + (_m.hud_x + _f.fx) * _cs;
        var _fy1 = _cvy + (_m.hud_y + _f.fy) * _cs;
        var _fx2 = _fx1 + _f.flen * _cs - 1;
        var _fy2 = _fy1 + _cs - 1;
        var _fcol = make_color_rgb(255, 200, 60);
        if (_fi == _m.sel_field) { _fcol = make_color_rgb(255, 80, 160); }
        draw_set_color(_fcol);
        draw_set_alpha(0.16);
        draw_rectangle(_fx1, _fy1, _fx2, _fy2, false);
        draw_set_alpha(1.0);
        draw_rectangle(_fx1, _fy1, _fx2, _fy2, true);
        draw_text(_fx1 + 1, _fy1 - 11, _f.name);
    }

    // Type cursor
    if ((current_time mod 700) < 420) {
        draw_set_color(c_white);
        var _tcx = _cvx + (_m.hud_x + _m.cur_x) * _cs;
        var _tcy = _cvy + (_m.hud_y + _m.cur_y) * _cs;
        draw_rectangle(_tcx, _tcy + _cs - 3, _tcx + _cs - 1, _tcy + _cs - 1, false);
    }

    // ── CANVAS INPUT ──
    var _over_canvas = point_in_rectangle(_mx, _my, _cvx, _cvy, _cvx + _cvw - 1, _cvy + _cvh - 1);
    var _hcol = -1;
    var _hrow = -1;
    if (_over_canvas) {
        _hcol = (_mx - _cvx) div _cs;
        _hrow = (_my - _cvy) div _cs;
    }
    var _in_panel = (_hcol >= _m.hud_x && _hcol < _m.hud_x + _m.hud_w
                  && _hrow >= _m.hud_y && _hrow < _m.hud_y + _m.hud_h);

    if (_over_canvas && _in_panel && !_m.name_edit_active) {
        var _rx  = _hcol - _m.hud_x;
        var _ry  = _hrow - _m.hud_y;
        var _idx = _ry * _m.hud_w + _rx;

        draw_set_color(c_white);
        draw_set_alpha(0.22);
        draw_rectangle(_cvx + _hcol * _cs, _cvy + _hrow * _cs, _cvx + _hcol * _cs + _cs - 1, _cvy + _hrow * _cs + _cs - 1, false);
        draw_set_alpha(1.0);

        if (_alt) {
            if (mouse_check_button_pressed(mb_left)) {
                _m.active_char   = _m.char_grid[_idx];
                _m.active_colour = _m.colour_grid[_idx];
            }
        } else if (_shift) {
            if (mouse_check_button_pressed(mb_left) && _m.sel_field >= 0 && _m.sel_field < array_length(_m.fields)) {
                var _sf = _m.fields[_m.sel_field];
                _sf.fx = max(0, min(_rx, _m.hud_w - _sf.flen));
                _sf.fy = _ry;
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
            if (mouse_check_button_pressed(mb_right)) { _push_undo(_m); }
            if (mouse_check_button(mb_right)) {
                _m.char_grid[_idx] = 32;
                scr_hud_flush(_asset);
            }
        }
    }

    // ===============================================================
    // CHAR STRIP — under the canvas, rendered in the current screen mode
    // ===============================================================
    var _sy = _cvy + _cvh + 16;
    draw_set_color(_c_lbl);
    draw_text(_cvx, _sy, "CHARSET");
    draw_set_color(_c_dim);
    draw_text(_cvx + 70, _sy, "CLICK = ACTIVE CHAR   ALT+CLICK THE PANEL TO PICK   ARROWS MOVE THE CURSOR   CTRL+Z/Y UNDO");
    var _csy  = _sy + 14;
    var _cssz = 18;
    for (var _ki = 0; _ki < 256; _ki++) {
        var _kx = _cvx + (_ki mod 32) * _cssz;
        var _ky = _csy + (_ki div 32) * _cssz;
        draw_set_color(scr_c64_pepto_colour(_bg_col));
        draw_rectangle(_kx, _ky, _kx + _cssz - 1, _ky + _cssz - 1, false);
        if (_have_atlas) {
            _draw_glyph(_m, _kx, _ky, _cssz, _ki, _m.active_colour, _scr_mc);
        }
        var _khov = point_in_rectangle(_mx, _my, _kx, _ky, _kx + _cssz - 1, _ky + _cssz - 1);
        if (_ki == _m.active_char) {
            draw_set_color(c_white);
            draw_rectangle(_kx, _ky, _kx + _cssz - 1, _ky + _cssz - 1, true);
        } else if (_khov) {
            draw_set_color(c_yellow);
            draw_rectangle(_kx, _ky, _kx + _cssz - 1, _ky + _cssz - 1, true);
        }
        if (_khov && mouse_check_button_pressed(mb_left)) { _m.active_char = _ki; }
    }

    // ===============================================================
    // RIGHT COLUMN
    // ===============================================================
    var _ry0 = _cvy - 8;

    // ── TILE — the charset's own editor, on the active char ──
    var _tile_h = 196;
    draw_set_color(_c_box);
    draw_rectangle(_rcx, _ry0, _rcx + _rcw, _ry0 + _tile_h, false);
    draw_set_color(_c_edge);
    draw_rectangle(_rcx, _ry0, _rcx + _rcw, _ry0 + _tile_h, true);
    draw_set_color(_c_head);
    draw_text(_rcx + 8, _ry0 + 5, "TILE");
    draw_set_color(_c_dim);
    draw_text(_rcx + 44, _ry0 + 5, "CHR " + string(_m.active_char) + "  -  EDITS " + _m.chr_asset);

    var _tile_ox = _rcx + 10;
    var _tile_oy = _ry0 + 22;
    var _tile_rect_w = 232;
    var _tile_rect_h = 170;
    var _over_tile = point_in_rectangle(_mx, _my, _tile_ox, _tile_oy, _tile_ox + _tile_rect_w, _tile_oy + _tile_rect_h);

    if (_chr != noone && buffer_exists(_chr.buffer)) {
        // The editor paints the pixel format the cell will be shown in: MC
        // pairs when the screen is MC and the active colour marks an MC cell.
        var _ed_mc = 0;
        if (_scr_mc && (_m.active_colour & 8) != 0) { _ed_mc = 1; }

        chr_edit_idx = clamp(_m.active_char, 0, (buffer_get_size(_chr.buffer) div 8) - 1);

        // Temporarily push the HUD's colours into the charset so its editor
        // and swatches show the cell as the panel will — same trick the map
        // editor uses.
        var _save_bg   = _chr.meta.mc_bg;
        var _save_col1 = _chr.meta.mc_col1;
        var _save_col2 = _chr.meta.mc_col2;
        var _save_fg   = _chr.meta.mc_fg;
        _chr.meta.mc_bg   = _bg_col;
        _chr.meta.mc_col1 = _col1;
        _chr.meta.mc_col2 = _col2;
        if (_ed_mc == 1) { _chr.meta.mc_fg = _m.active_colour & 7; } else { _chr.meta.mc_fg = _m.active_colour & 15; }

        scr_chr_editor_draw(_chr, _tile_ox, _tile_oy, _ed_mc, false, !_over_canvas);

        _chr.meta.mc_bg   = _save_bg;
        _chr.meta.mc_col1 = _save_col1;
        _chr.meta.mc_col2 = _save_col2;
        _chr.meta.mc_fg   = _save_fg;

        // Keep the atlases in step with the glyph being painted: one cell per
        // frame while the mouse works in the editor; a full rebuild after an
        // undo/redo or paste, which can touch any tile.
        if (_over_tile && (mouse_check_button(mb_left) || mouse_check_button(mb_right))) {
            scr_hud_atlas_char(_asset, _chr, chr_edit_idx);
        }
        if (_ctrl && (keyboard_check_pressed(ord("Z")) || keyboard_check_pressed(ord("Y")) || keyboard_check_pressed(ord("V")))) {
            _m.atlas_key = "";
        }
    } else {
        draw_set_color(_c_dim);
        draw_text(_tile_ox, _tile_oy + 8, "PICK A CHARSET ABOVE TO EDIT ITS TILES HERE");
    }

    // ── PAINT ──
    var _py0 = _ry0 + _tile_h + 10;
    var _paint_h = 118;
    draw_set_color(_c_box);
    draw_rectangle(_rcx, _py0, _rcx + _rcw, _py0 + _paint_h, false);
    draw_set_color(_c_edge);
    draw_rectangle(_rcx, _py0, _rcx + _rcw, _py0 + _paint_h, true);
    draw_set_color(_c_head);
    draw_text(_rcx + 8, _py0 + 5, "PAINT");

    // Row 1: active swatch, readout, 16 colours in two rows, cell kind button
    var _swx = _rcx + 10;
    var _swy = _py0 + 22;
    var _swz = 40;
    draw_set_color(scr_c64_pepto_colour(_bg_col));
    draw_rectangle(_swx, _swy, _swx + _swz, _swy + _swz, false);
    if (_have_atlas) { _draw_glyph(_m, _swx, _swy, _swz, _m.active_char, _m.active_colour, _scr_mc); }
    draw_set_color(c_white);
    draw_rectangle(_swx, _swy, _swx + _swz, _swy + _swz, true);
    draw_text(_swx + _swz + 8, _swy + 2,  "CHR " + string(_m.active_char));
    draw_text(_swx + _swz + 8, _swy + 14, "COL " + string(_m.active_colour));
    var _cell_lbl = "HR CELL";
    if (_scr_mc && (_m.active_colour & 8) != 0) { _cell_lbl = "MC CELL"; }
    draw_set_color(_c_dim);
    draw_text(_swx + _swz + 8, _swy + 26, _cell_lbl);

    var _colx = _swx + _swz + 74;
    for (var _ci = 0; _ci < 16; _ci++) {
        var _cx1 = _colx + (_ci mod 8) * 21;
        var _cy1 = _swy + (_ci div 8) * 21;
        var _chov2 = point_in_rectangle(_mx, _my, _cx1, _cy1, _cx1 + 18, _cy1 + 18);
        draw_set_color(scr_c64_pepto_colour(_ci));
        draw_rectangle(_cx1, _cy1, _cx1 + 18, _cy1 + 18, false);
        draw_set_color(make_color_rgb(60, 60, 80));
        if ((_m.active_colour & 15) == _ci) { draw_set_color(c_white); }
        if (_chov2) { draw_set_color(c_yellow); }
        draw_rectangle(_cx1, _cy1, _cx1 + 18, _cy1 + 18, true);
        if (_chov2 && mouse_check_button_pressed(mb_left)) {
            // On an MC screen with an MC cell active the swatch picks the
            // cell's own colour (0-7) and keeps bit 3; otherwise it is the
            // raw nibble — 8-15 on an MC screen is an MC cell, as on the VIC.
            if (_scr_mc && (_m.active_colour & 8) != 0) {
                _m.active_colour = (_ci & 7) | 8;
            } else {
                _m.active_colour = _ci;
            }
        }
        if (_chov2 && mouse_check_button_pressed(mb_right)) {
            _m.hud_mc_bg = _ci;
            _m.atlas_key = "";
        }
    }

    // CELL HR/MC sits to the right of the colours, clear of everything else.
    var _cellx = _colx + 8 * 21 + 12;
    if (_scr_mc) {
        var _mc_on = ((_m.active_colour & 8) != 0);
        var _mcl = "CELL HR";
        if (_mc_on) { _mcl = "CELL MC"; }
        if (_button(_cellx, _swy, 76, 16, _mcl, _mc_on, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) {
            _m.active_colour = _m.active_colour ^ 8;
        }
        draw_set_color(_c_dim);
        draw_text(_cellx, _swy + 22, "BIT 3 OF");
        draw_text(_cellx, _swy + 33, "COLOUR RAM");
    }

    // Row 2: what the mouse buttons do
    var _hy2 = _swy + _swz + 8;
    draw_set_color(_c_dim);
    draw_text(_swx, _hy2, "LEFT = PAINT COLOUR   RIGHT = SCREEN BACKGROUND $D021 (" + string(_bg_col) + ")");

    // Row 3: shared MC colours ($D022 / $D023) — click to step through the palette
    if (_scr_mc) {
        var _hy3 = _hy2 + 16;
        draw_set_color(_c_dim);
        draw_text(_swx, _hy3 + 3, "C1");
        draw_set_color(scr_c64_pepto_colour(_col1));
        draw_rectangle(_swx + 20, _hy3, _swx + 36, _hy3 + 16, false);
        draw_set_color(_c_dim);
        draw_text(_swx + 46, _hy3 + 3, "C2");
        draw_set_color(scr_c64_pepto_colour(_col2));
        draw_rectangle(_swx + 66, _hy3, _swx + 82, _hy3 + 16, false);
        draw_set_color(_c_dim);
        draw_text(_swx + 92, _hy3 + 3, "SHARED MC COLOURS $D022 / $D023  -  CLICK = NEXT");
        if (mouse_check_button_pressed(mb_left) && point_in_rectangle(_mx, _my, _swx + 20, _hy3, _swx + 36, _hy3 + 16)) {
            _m.hud_mc_col1 = (_col1 + 1) mod 16;
            _m.atlas_key = "";
        }
        if (mouse_check_button_pressed(mb_left) && point_in_rectangle(_mx, _my, _swx + 66, _hy3, _swx + 82, _hy3 + 16)) {
            _m.hud_mc_col2 = (_col2 + 1) mod 16;
            _m.atlas_key = "";
        }
    }

    // ── FIELDS ──
    var _fy0 = _py0 + _paint_h + 10;
    var _fh  = (_csy + _strip_h) - _fy0;
    if (_fh < 200) { _fh = 200; }
    draw_set_color(_c_box);
    draw_rectangle(_rcx, _fy0, _rcx + _rcw, _fy0 + _fh, false);
    draw_set_color(_c_edge);
    draw_rectangle(_rcx, _fy0, _rcx + _rcw, _fy0 + _fh, true);
    draw_set_color(_c_head);
    draw_text(_rcx + 8, _fy0 + 5, "FIELDS");
    draw_set_color(_c_dim);
    draw_text(_rcx + 60, _fy0 + 5, "CELLS THE GAME WRITES  -  EACH IS AN ENTRY POINT ON THE HUD NODE");

    var _aby = _fy0 + 20;
    if (_button(_rcx + 8, _aby, 70, 16, "+ FIELD", false, _mx, _my, make_color_rgb(30, 80, 40), make_color_rgb(60, 160, 80), _c_on, _c_ontx)) {
        array_push(_m.fields, { name: "FIELD" + string(array_length(_m.fields)), fx: _m.cur_x, fy: _m.cur_y,
                                flen: 2, kind: 1, base: 48, pad: 0, full: 81, empty: 32 });
        _m.sel_field = array_length(_m.fields) - 1;
        global.addresses_dirty = true;
    }
    if (_button(_rcx + 84, _aby, 60, 16, "DELETE", false, _mx, _my, make_color_rgb(80, 30, 30), make_color_rgb(170, 60, 60), _c_on, _c_ontx)) {
        if (_m.sel_field >= 0 && _m.sel_field < array_length(_m.fields)) {
            array_delete(_m.fields, _m.sel_field, 1);
            _m.sel_field = -1;
            _m.name_edit_active = false;
            global.addresses_dirty = true;
        }
    }
    draw_set_color(_c_dim);
    draw_text(_rcx + 152, _aby + 3, "SHIFT+CLICK THE PANEL TO MOVE THE SELECTED ONE");

    // List (left half) and properties (right half) side by side
    var _lx  = _rcx + 8;
    var _lw  = min(300, _rcw * 0.5);
    var _ly  = _aby + 24;
    var _kind_names = ["TEXT", "DIGITS", "BAR"];
    var _max_rows = max(1, (_fh - 50) div 16);
    for (var _fi = 0; _fi < array_length(_m.fields); _fi++) {
        if (_fi >= _max_rows) { break; }
        var _f    = _m.fields[_fi];
        var _ry1  = _ly + _fi * 16;
        var _rhov = point_in_rectangle(_mx, _my, _lx, _ry1, _lx + _lw, _ry1 + 14);
        if (_fi == _m.sel_field) {
            draw_set_color(make_color_rgb(60, 30, 60));
            draw_rectangle(_lx, _ry1, _lx + _lw, _ry1 + 14, false);
        } else if (_rhov) {
            draw_set_color(make_color_rgb(40, 40, 60));
            draw_rectangle(_lx, _ry1, _lx + _lw, _ry1 + 14, false);
        }
        draw_set_color(c_white);
        draw_text(_lx + 4, _ry1 + 2, _f.name);
        draw_set_color(make_color_rgb(140, 140, 170));
        draw_text(_lx + 130, _ry1 + 2, _kind_names[_f.kind]);
        draw_text(_lx + 190, _ry1 + 2, string(_f.fx) + "," + string(_f.fy));
        draw_text(_lx + 240, _ry1 + 2, "L" + string(_f.flen));
        if (_rhov && mouse_check_button_pressed(mb_left)) {
            _m.sel_field = _fi;
            _m.name_edit_active = false;
        }
    }

    if (_m.sel_field >= 0 && _m.sel_field < array_length(_m.fields)) {
        var _f2 = _m.fields[_m.sel_field];
        var _ppx = _lx + _lw + 16;
        var _ppy = _ly;
        var _ppw = (_rcx + _rcw - 10) - _ppx;

        // NAME
        draw_set_color(_c_lbl);
        draw_text(_ppx, _ppy + 3, "NAME");
        var _nbx1 = _ppx + 50;
        var _nbx2 = _ppx + _ppw;
        var _nhov = point_in_rectangle(_mx, _my, _nbx1, _ppy, _nbx2, _ppy + 16);
        draw_set_color(make_color_rgb(20, 35, 25));
        if (_m.name_edit_active) { draw_set_color(make_color_rgb(20, 60, 30)); }
        draw_rectangle(_nbx1, _ppy, _nbx2, _ppy + 16, false);
        draw_set_color(c_lime);
        if (_m.name_edit_active) {
            var _blink = " ";
            if ((current_time mod 600) < 300) { _blink = "_"; }
            draw_text(_nbx1 + 5, _ppy + 3, _m.name_edit_buf + _blink);
        } else {
            draw_text(_nbx1 + 5, _ppy + 3, _f2.name);
        }
        if (_nhov && mouse_check_button_pressed(mb_left) && !_m.name_edit_active) {
            _m.name_edit_active = true;
            _m.name_edit_buf    = _f2.name;
            keyboard_string     = "";
        }
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
                    if (_ok && string_length(_m.name_edit_buf) < 16) { _m.name_edit_buf += _nch; }
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
        _ppy += 20;

        // KIND + LEN on one row
        draw_set_color(_c_lbl);
        draw_text(_ppx, _ppy + 3, "KIND");
        if (_button(_ppx + 50, _ppy, 70, 16, _kind_names[_f2.kind], false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) {
            _f2.kind = (_f2.kind + 1) mod 3;
            global.addresses_dirty = true;
        }
        draw_set_color(_c_lbl);
        draw_text(_ppx + 132, _ppy + 3, "LEN");
        if (_button(_ppx + 162, _ppy, 14, 16, "-", false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) {
            _f2.flen = max(1, _f2.flen - 1);
            global.addresses_dirty = true;
        }
        draw_set_color(c_aqua);
        draw_set_halign(fa_center);
        draw_text(_ppx + 188, _ppy + 3, string(_f2.flen));
        draw_set_halign(fa_left);
        if (_button(_ppx + 200, _ppy, 14, 16, "+", false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) {
            _f2.flen = min(_m.hud_w - _f2.fx, _f2.flen + 1);
            global.addresses_dirty = true;
        }
        _ppy += 20;

        if (_f2.kind == 1) {
            draw_set_color(_c_lbl);
            draw_text(_ppx, _ppy + 3, "ZERO");
            if (_button(_ppx + 50, _ppy, 120, 16, "CHR " + string(_f2.base) + "  < ACTIVE", false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) {
                _f2.base = _m.active_char;
                global.addresses_dirty = true;
            }
            _ppy += 20;
            draw_set_color(_c_lbl);
            draw_text(_ppx, _ppy + 3, "LEAD");
            var _pad_lbl = "ZEROS";
            if (_f2.pad == 1) { _pad_lbl = "BLANK"; }
            if (_button(_ppx + 50, _ppy, 70, 16, _pad_lbl, false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) {
                _f2.pad = 1 - _f2.pad;
                global.addresses_dirty = true;
            }
            _ppy += 20;
            draw_set_color(_c_dim);
            draw_text(_ppx, _ppy, "A = 0-255, WRITTEN RIGHT-ALIGNED");
        }
        if (_f2.kind == 2) {
            draw_set_color(_c_lbl);
            draw_text(_ppx, _ppy + 3, "FULL");
            if (_button(_ppx + 50, _ppy, 120, 16, "CHR " + string(_f2.full) + "  < ACTIVE", false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) {
                _f2.full = _m.active_char;
                global.addresses_dirty = true;
            }
            _ppy += 20;
            draw_set_color(_c_lbl);
            draw_text(_ppx, _ppy + 3, "EMPTY");
            if (_button(_ppx + 50, _ppy, 120, 16, "CHR " + string(_f2.empty) + "  < ACTIVE", false, _mx, _my, _c_btn, _c_btnh, _c_on, _c_ontx)) {
                _f2.empty = _m.active_char;
                global.addresses_dirty = true;
            }
            _ppy += 20;
            draw_set_color(_c_dim);
            draw_text(_ppx, _ppy, "A = HOW MANY CELLS TO FILL");
        }
        if (_f2.kind == 0) {
            draw_set_color(_c_dim);
            draw_text(_ppx, _ppy, "POSITION ONLY - NO CODE EMITTED.");
            draw_text(_ppx, _ppy + 12, "THE NODE SHOWS ITS SCREEN ADDRESS.");
        }
    }

    // ===============================================================
    // KEYBOARD — type into the panel (not while a name is being edited)
    // ===============================================================
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

        // Grid undo takes ctrl+Z/Y only while the mouse is over the canvas;
        // elsewhere the tile editor owns them (see _own_undo above).
        if (_over_canvas && _ctrl && keyboard_check_pressed(ord("Z")) && array_length(_m.undo_stack) > 0) {
            var _snap = array_pop(_m.undo_stack);
            array_push(_m.redo_stack, { char_grid: array_copy_shallow(_m.char_grid), colour_grid: array_copy_shallow(_m.colour_grid) });
            _m.char_grid   = _snap.char_grid;
            _m.colour_grid = _snap.colour_grid;
            scr_hud_flush(_asset);
        }
        if (_over_canvas && _ctrl && keyboard_check_pressed(ord("Y")) && array_length(_m.redo_stack) > 0) {
            var _snap2 = array_pop(_m.redo_stack);
            array_push(_m.undo_stack, { char_grid: array_copy_shallow(_m.char_grid), colour_grid: array_copy_shallow(_m.colour_grid) });
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
}
