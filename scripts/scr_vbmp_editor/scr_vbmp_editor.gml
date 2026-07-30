/// @function scr_vbmp_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my)
/// Inline editor for VECTOR_BITMAP assets. The command list (meta.commands) is
/// the source of truth; the preview surface is rebuilt from it by
/// scr_vbmp_replay_to_surface after every change. Tools append command structs.
function scr_vbmp_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _m = _asset.meta;

    // Stream byte cost of one command — MUST match the byte emission in the
    // MACRO_VECTOR_BMP compile case, or the readout lies about PRG size.
    // setcol 2, plot 4, line/rect/rectfill/ellipse/ellipsefill/fill 5,
    // recolour 6, copyregion 7. Unknown ops cost 0 (not emitted).
    var _vbmp_cmd_bytes = function(_c) {
        if (!is_struct(_c) || !variable_struct_exists(_c, "op")) return 0;
        var _o = string(_c.op);
        if (_o == "setcol") return 2;
        if (_o == "plot") return 4;
        if (_o == "line" || _o == "rect" || _o == "rectfill"
         || _o == "ellipse" || _o == "ellipsefill" || _o == "fill") return 5;
        if (_o == "recolor_cram" || _o == "recolor_sram") return 6;
        if (_o == "copyregion") return 7;
        return 0;
    };

    // ── Ensure all editor state exists (Create should set these, but guard) ──
    if (!variable_struct_exists(_m, "commands"))      _m.commands = [];
    if (!variable_struct_exists(_m, "tool"))          _m.tool = "LINE";
    if (!variable_struct_exists(_m, "active_col"))    _m.active_col = 1;
    if (!variable_struct_exists(_m, "draw_x1"))       _m.draw_x1 = -1;
    if (!variable_struct_exists(_m, "draw_y1"))       _m.draw_y1 = -1;
    if (!variable_struct_exists(_m, "vbmp_dirty"))    _m.vbmp_dirty = true;
    if (!variable_struct_exists(_m, "cmd_scroll"))    _m.cmd_scroll = 0;
    if (!variable_struct_exists(_m, "bg"))            _m.bg = 0;
    if (!variable_struct_exists(_m, "col1"))          _m.col1 = 1;
    if (!variable_struct_exists(_m, "col2"))          _m.col2 = 2;
    if (!variable_struct_exists(_m, "col3"))          _m.col3 = 3;
    if (!variable_struct_exists(_m, "last_emitted_col")) _m.last_emitted_col = -1;
    if (!variable_struct_exists(_m, "dither_pat")) _m.dither_pat = 0; // 0 solid,1 checker,2 interlace
    if (!variable_struct_exists(_m, "dither_colb")) _m.dither_colb = 2; // second dither colour 0..3
    if (!variable_struct_exists(_m, "vbmp_zoom")) _m.vbmp_zoom = 0; // 0 = full surface, 1 = zoom into 192x120 window
    if (!variable_struct_exists(_m, "vbmp_grid")) _m.vbmp_grid = false; // char-cell grid overlay on/off

    // First entry (or after any change) — rebuild preview from commands.
    // Also rebuild if the surface was freed (window minimise / resize / focus
    // loss all destroy surfaces in GameMaker), otherwise the canvas goes blank.
    var _surf_lost = (!variable_struct_exists(_m, "preview_surf") || !surface_exists(_m.preview_surf));
    if (_m.vbmp_dirty || _surf_lost) {
        scr_vbmp_replay_to_surface(_asset);
        _m.vbmp_dirty = false;
    }

    // ── CANVAS BOX (identical size/position in both views) ───────────────
    var _box_x = _vx1 + 20;
    var _box_y = _cy + 60;
    var _box_w = 320 * 2.6; // 832
    var _box_h = 200 * 2.6; // 520

    // The 192x120 usable window in surface px (24x15 chars): X 64..255, Y 40..159
    var _win_pw = 192; // 256 - 64
    var _win_ph = 120; // 160 - 40

    // _cw/_ch = on-screen size the FULL 320x200 surface WOULD be at this zoom.
    // _sx/_sy = where the surface's (0,0) is drawn. Every pixel<->screen calc
    // below uses /320 & /200 against _sx/_cw, so they follow the pan for free.
    var _zoom, _cw, _ch, _sx, _sy;
    if (_m.vbmp_zoom == 1) {
        // ZOOM: blow the 192x120 window up to fill the box, pan it to box origin.
        _cw = (320 / _win_pw) * _box_w;   // implied full-surface width
        _ch = (200 / _win_ph) * _box_h;   // implied full-surface height
        _sx = _box_x - (64 / 320) * _cw;  // pan window-left  to box origin
        _sy = _box_y - (40 / 200) * _ch;  // pan window-top   to box origin
    } else {
        // FULL: whole surface fills the box (original behaviour).
        _cw = _box_w;
        _ch = _box_h;
        _sx = _box_x;
        _sy = _box_y;
    }
    _zoom = _cw / 320; // kept for anything that references it

    // Draw canvas. Instead of scissoring (which uses window px, not GUI px, and
    // breaks under GUI scaling on hi-DPI), draw only the visible slice of the
    // surface with draw_surface_part_ext — works in GUI space in both views.
    var _prev_filter = gpu_get_texfilter();
    gpu_set_texfilter(false);
    if (surface_exists(_m.preview_surf)) {
        // Scale factors: surface px -> screen px (same in x and y per view).
        var _scl_x = _cw / 320;
        var _scl_y = _ch / 200;
        // Which surface px map to the visible box left/top: invert the pan.
        var _src_l = (_box_x - _sx) / _scl_x;
        var _src_t = (_box_y - _sy) / _scl_y;
        // How many surface px fill the box.
        var _src_w = _box_w / _scl_x;
        var _src_h = _box_h / _scl_y;
        draw_surface_part_ext(_m.preview_surf, _src_l, _src_t, _src_w, _src_h, _box_x, _box_y, _scl_x, _scl_y, c_white, 1);
    }
    gpu_set_texfilter(_prev_filter);
    draw_set_color(make_color_rgb(80, 80, 100));
    draw_rectangle(_box_x, _box_y, _box_x + _box_w, _box_y + _box_h, true);

    // ── EDITABLE WINDOW BOUNDS (surface px) ──────────────────────────────
    // Always the 192x120 centred window; zoom just magnifies it on screen.
    var _win_x0 = 64;
    var _win_x1 = 255;
    var _win_y0 = 40;
    var _win_y1 = 159;

    // Window overlay: shade outside the usable area, outline the usable region.
    // In zoom view the bands fall outside the box (scissored away); the outline
    // sits on the box edge.
    var _wx0 = _sx + (_win_x0       / 320) * _cw;
    var _wx1 = _sx + ((_win_x1 + 1) / 320) * _cw;
    var _wy0 = _sy + (_win_y0       / 200) * _ch;
    var _wy1 = _sy + ((_win_y1 + 1) / 200) * _ch;
    if (_m.vbmp_zoom == 0) {
        draw_set_alpha(0.45);
        draw_set_color(c_black);
        draw_rectangle(_sx, _sy, _sx + _cw, _wy0, false);          // top band
        draw_rectangle(_sx, _wy1, _sx + _cw, _sy + _ch, false);    // bottom band
        draw_rectangle(_sx, _wy0, _wx0, _wy1, false);              // left band
        draw_rectangle(_wx1, _wy0, _sx + _cw, _wy1, false);        // right band
        draw_set_alpha(1.0);
    }
    draw_set_color(make_color_rgb(90, 200, 220));
    draw_rectangle(_wx0, _wy0, _wx1, _wy1, true);

    // ── GRID OVERLAY (char cells, 8 surface px) ──────────────────────────
    // Lines are drawn through the same _sx/_cw mapping as the canvas, so they
    // track the pan/zoom automatically. Only the drawable window is gridded.
    // Verticals every 8px from the window left; horizontals every 8px from the
    // window top. Clipped to the on-screen box in FULL view via the window
    // bands; in ZOOM view the box edge does the clipping.
    if (_m.vbmp_grid) {
        var _grid_x0 = _win_x0;      // 64
        var _grid_x1 = _win_x1 + 1;  // 256 (exclusive edge)
        var _grid_y0 = _win_y0;      // 40
        var _grid_y1 = _win_y1 + 1;  // 160
        draw_set_alpha(0.35);
        draw_set_color(make_color_rgb(70, 130, 150));
        // vertical lines
        var _gvx = _grid_x0;
        while (_gvx <= _grid_x1) {
            var _lx = _sx + (_gvx / 320) * _cw;
            var _ly0 = _sy + (_grid_y0 / 200) * _ch;
            var _ly1 = _sy + (_grid_y1 / 200) * _ch;
            draw_line(_lx, _ly0, _lx, _ly1);
            _gvx += 8;
        }
        // horizontal lines
        var _ghy = _grid_y0;
        while (_ghy <= _grid_y1) {
            var _gy = _sy + (_ghy / 200) * _ch;
            var _gx0 = _sx + (_grid_x0 / 320) * _cw;
            var _gx1 = _sx + (_grid_x1 / 320) * _cw;
            draw_line(_gx0, _gy, _gx1, _gy);
            _ghy += 8;
        }
        draw_set_alpha(1.0);
    }

    // Hit-test / drawing region is the on-screen box.
    var _in_canvas = point_in_rectangle(_mx, _my, _box_x, _box_y, _box_x + _box_w, _box_y + _box_h);

    // Mouse -> canvas pixel, then clamp into the window (MC-snapped X)
    var _raw_px = clamp(floor(((_mx - _sx) / _cw) * 320), _win_x0, _win_x1);
    var _raw_py = clamp(floor(((_my - _sy) / _ch) * 200), _win_y0, _win_y1);
    var _snap_px = (_raw_px div 2) * 2;

    // ── TOOL PALETTE (right of canvas) ───────────────────────────────────
    var _tx = _box_x + _box_w + 30;
    var _ty = _box_y;
    var _tw = 90;
    var _th = 18;

    var _tools = ["PLOT", "LINE", "RECT", "RECTFILL", "ELLIPSE", "ELLIPSEFILL", "FILL", "RECOL_C", "RECOL_S", "COPYRGN"];
    draw_set_font(fnt_c64_tiny);
    for (var _i = 0; _i < array_length(_tools); _i++) {
        var _tn  = _tools[_i];
        var _act = (_m.tool == _tn);
        var _hov = point_in_rectangle(_mx, _my, _tx, _ty, _tx + _tw, _ty + _th);
        draw_set_color(_hov ? make_color_rgb(80, 80, 110) : (_act ? make_color_rgb(20, 60, 60) : make_color_rgb(40, 40, 60)));
        draw_rectangle(_tx, _ty, _tx + _tw, _ty + _th, false);
        draw_set_color(_hov ? c_white : (_act ? c_aqua : make_color_rgb(90, 90, 110)));
        draw_rectangle(_tx, _ty, _tx + _tw, _ty + _th, true);
        draw_set_color(_act ? c_aqua : c_white);
        draw_text(_tx + 4, _ty + 3, _tn);
        if (_hov && mouse_check_button_pressed(mb_left)) {
            _m.tool = _tn;
            _m.draw_x1 = -1;    // cancel any in-progress 2-point op
            vbmp_recol_ax = -1; // cancel any in-progress recolour selection
            // Reset the copy-region tool to phase 0 (drop any half-done source).
            vbmp_copy_phase = 0;
            vbmp_copy_ax    = -1;
            vbmp_copy_ay    = -1;
            // Seed the recolour pickers from the page's CURRENT palette at the
            // moment the tool is chosen, so overrides start from the live
            // on-screen colours rather than stale picker defaults. RECOL_S seeds
            // col1/col2 (screen-RAM pair); RECOL_C seeds col3 (colour-RAM).
            if (_tn == "RECOL_S") {
                vbmp_recol_c1 = variable_struct_exists(_m, "col1") ? _m.col1 : 1;
                vbmp_recol_c2 = variable_struct_exists(_m, "col2") ? _m.col2 : 2;
            } else if (_tn == "RECOL_C") {
                vbmp_recol_c3 = variable_struct_exists(_m, "col3") ? _m.col3 : 3;
            }
        }
        _ty += _th + 3;
    }

    // ── VIEW TOGGLE (full surface / zoom into window) ────────────────────
    _ty += 8;
    var _fhov = point_in_rectangle(_mx, _my, _tx, _ty, _tx + _tw, _ty + _th);
    draw_set_color(_fhov ? make_color_rgb(80, 80, 110) : make_color_rgb(40, 40, 60));
    draw_rectangle(_tx, _ty, _tx + _tw, _ty + _th, false);
    draw_set_color(_fhov ? c_white : make_color_rgb(90, 90, 110));
    draw_rectangle(_tx, _ty, _tx + _tw, _ty + _th, true);
    draw_set_color(c_aqua);
    draw_text(_tx + 4, _ty + 3, (_m.vbmp_zoom == 1) ? "VIEW: ZOOM" : "VIEW: FULL");
    if (_fhov && mouse_check_button_pressed(mb_left)) {
        _m.vbmp_zoom = (_m.vbmp_zoom + 1) mod 2;
        _m.draw_x1 = -1; // cancel any in-progress op on view change
    }
    _ty += _th + 3;

    // ── GRID TOGGLE (char-cell overlay) ──────────────────────────────────
    var _ghov = point_in_rectangle(_mx, _my, _tx, _ty, _tx + _tw, _ty + _th);
    draw_set_color(_ghov ? make_color_rgb(80, 80, 110) : (_m.vbmp_grid ? make_color_rgb(20, 60, 60) : make_color_rgb(40, 40, 60)));
    draw_rectangle(_tx, _ty, _tx + _tw, _ty + _th, false);
    draw_set_color(_ghov ? c_white : (_m.vbmp_grid ? c_aqua : make_color_rgb(90, 90, 110)));
    draw_rectangle(_tx, _ty, _tx + _tw, _ty + _th, true);
    draw_set_color(_m.vbmp_grid ? c_aqua : c_white);
    draw_text(_tx + 4, _ty + 3, _m.vbmp_grid ? "GRID: ON" : "GRID: OFF");
    if (_ghov && mouse_check_button_pressed(mb_left)) {
        _m.vbmp_grid = !_m.vbmp_grid;
    }
    _ty += _th + 3;

    // ── PAGE SWITCHER ────────────────────────────────────────────────────
    // pages[] is the source of truth; the editor edits the top-level fields
    // for the active page. Switching stores the current page down into
    // pages[active], then loads the target up into the top-level fields.
    // ADD appends a fresh blank page; DEL removes the current one (min 1).
    if (!variable_struct_exists(_m, "pages") || !is_array(_m.pages) || array_length(_m.pages) == 0) {
        // Safety: synthesise a page 0 from current top-level fields if missing.
        _m.pages = [ {
            commands: variable_struct_exists(_m, "commands") ? _m.commands : [],
            bg:   variable_struct_exists(_m, "bg")   ? _m.bg   : 0,
            col1: variable_struct_exists(_m, "col1") ? _m.col1 : 1,
            col2: variable_struct_exists(_m, "col2") ? _m.col2 : 2,
            col3: variable_struct_exists(_m, "col3") ? _m.col3 : 3
        } ];
    }
    if (!variable_struct_exists(_m, "active_page")) _m.active_page = 0;
    var _pg_count = array_length(_m.pages);
    _m.active_page = clamp(_m.active_page, 0, _pg_count - 1);

    _ty += 6;
    draw_set_color(c_ltgray);
    draw_text(_tx, _ty, "PAGE:");
    _ty += 14;

    // ◀ button
    var _pw_btn = 22;
    var _prev_hov = point_in_rectangle(_mx, _my, _tx, _ty, _tx + _pw_btn, _ty + 18);
    draw_set_color(_prev_hov ? make_color_rgb(80, 80, 110) : make_color_rgb(40, 40, 60));
    draw_rectangle(_tx, _ty, _tx + _pw_btn, _ty + 18, false);
    draw_set_color(_prev_hov ? c_white : make_color_rgb(140, 140, 160));
    draw_rectangle(_tx, _ty, _tx + _pw_btn, _ty + 18, true);
    draw_set_color(c_white);
    draw_text(_tx + 6, _ty + 3, "<");
    if (_prev_hov && mouse_check_button_pressed(mb_left) && _m.active_page > 0) {
        scr_vbmp_page_store(_asset);
        scr_vbmp_page_load(_asset, _m.active_page - 1);
        _m.draw_x1 = -1;
    }

    // n/N readout
    var _rd_x = _tx + _pw_btn + 4;
    var _rd_w = 40;
    draw_set_color(make_color_rgb(20, 20, 32));
    draw_rectangle(_rd_x, _ty, _rd_x + _rd_w, _ty + 18, false);
    draw_set_color(make_color_rgb(70, 70, 90));
    draw_rectangle(_rd_x, _ty, _rd_x + _rd_w, _ty + 18, true);
    draw_set_color(c_aqua);
    draw_set_halign(fa_center);
    draw_text(_rd_x + _rd_w / 2, _ty + 3, string(_m.active_page) + "/" + string(_pg_count - 1));
    draw_set_halign(fa_left);

    // ▶ button
    var _nx_x = _rd_x + _rd_w + 4;
    var _next_hov = point_in_rectangle(_mx, _my, _nx_x, _ty, _nx_x + _pw_btn, _ty + 18);
    draw_set_color(_next_hov ? make_color_rgb(80, 80, 110) : make_color_rgb(40, 40, 60));
    draw_rectangle(_nx_x, _ty, _nx_x + _pw_btn, _ty + 18, false);
    draw_set_color(_next_hov ? c_white : make_color_rgb(140, 140, 160));
    draw_rectangle(_nx_x, _ty, _nx_x + _pw_btn, _ty + 18, true);
    draw_set_color(c_white);
    draw_text(_nx_x + 6, _ty + 3, ">");
    if (_next_hov && mouse_check_button_pressed(mb_left) && _m.active_page < _pg_count - 1) {
        scr_vbmp_page_store(_asset);
        scr_vbmp_page_load(_asset, _m.active_page + 1);
        _m.draw_x1 = -1;
    }

    // +ADD / DEL move to their own row directly below the page arrows.
    _ty += 24;

    // +ADD button
    var _add_x = _tx;
    var _add_w = 34;
    var _add_hov = point_in_rectangle(_mx, _my, _add_x, _ty, _add_x + _add_w, _ty + 18);
    draw_set_color(_add_hov ? make_color_rgb(40, 120, 60) : make_color_rgb(25, 70, 35));
    draw_rectangle(_add_x, _ty, _add_x + _add_w, _ty + 18, false);
    draw_set_color(_add_hov ? c_white : make_color_rgb(100, 160, 110));
    draw_rectangle(_add_x, _ty, _add_x + _add_w, _ty + 18, true);
    draw_set_color(c_white);
    draw_text(_add_x , _ty , "+ADD");
    if (_add_hov && mouse_check_button_pressed(mb_left)) {
        // Store current, append a fresh blank page inheriting current colours,
        // then jump to it.
        scr_vbmp_page_store(_asset);
        array_push(_m.pages, {
            commands: [],
            bg:   _m.bg,
            col1: _m.col1,
            col2: _m.col2,
            col3: _m.col3
        });
        scr_vbmp_page_load(_asset, array_length(_m.pages) - 1);
        _m.draw_x1 = -1;
    }

    // DEL button (only when more than one page exists)
    var _del_x = _add_x + _add_w + 6;
    var _del_w = 30;
    if (_pg_count > 1) {
        var _del_hov = point_in_rectangle(_mx, _my, _del_x, _ty, _del_x + _del_w, _ty + 18);
        draw_set_color(_del_hov ? make_color_rgb(200, 60, 60) : make_color_rgb(120, 30, 30));
        draw_rectangle(_del_x, _ty, _del_x + _del_w, _ty + 18, false);
        draw_set_color(c_white);
        draw_rectangle(_del_x, _ty, _del_x + _del_w, _ty + 18, true);
        draw_text(_del_x +2 , _ty , "DEL");
        if (_del_hov && mouse_check_button_pressed(mb_left)) {
            // Remove the active page; clamp active_page and load the neighbour.
            var _removed = _m.active_page;
            array_delete(_m.pages, _removed, 1);
            var _new_idx = clamp(_removed, 0, array_length(_m.pages) - 1);
            scr_vbmp_page_load(_asset, _new_idx);
            _m.draw_x1 = -1;
        }
    }
    _ty += 24;

    // ── COLOUR SELECTOR (4 slots: bg + 3) ────────────────────────────────
    _ty += 10;
    draw_set_color(c_ltgray);
    draw_text(_tx, _ty, "COLOUR (selector):");
    _ty += 16;
    var _slots = [_m.bg, _m.col1, _m.col2, _m.col3];
    var _slot_lbl = ["0 BG", "1", "2", "3"];
    var _sw2 = 25;
    for (var _s = 0; _s < 4; _s++) {
        var _bx = _tx + (_s * (_sw2 + 4));
        var _bhov = point_in_rectangle(_mx, _my, _bx, _ty, _bx + _sw2, _ty + 24);
        draw_set_color(scr_c64_pepto_colour(_slots[_s]));
        draw_rectangle(_bx, _ty, _bx + _sw2, _ty + 24, false);
        if (_m.active_col == _s) {
            draw_set_color(c_white);
            draw_rectangle(_bx - 2, _ty - 2, _bx + _sw2 + 2, _ty + 26, true);
        } else {
            draw_set_color(make_color_rgb(90, 90, 110));
            draw_rectangle(_bx, _ty, _bx + _sw2, _ty + 24, true);
        }
        draw_set_color(c_white);
        draw_text(_bx + 3, _ty + 26, _slot_lbl[_s]);
        if (_bhov && mouse_check_button_pressed(mb_left)) _m.active_col = _s;
        // Right-click cycles the actual C64 colour of that slot
        if (_bhov && mouse_check_button_pressed(mb_right)) {
            if (_s == 0) _m.bg   = (_m.bg   + 1) mod 16;
            if (_s == 1) _m.col1 = (_m.col1 + 1) mod 16;
            if (_s == 2) _m.col2 = (_m.col2 + 1) mod 16;
            if (_s == 3) _m.col3 = (_m.col3 + 1) mod 16;
            _m.vbmp_dirty = true;
            // Propagate the colour change into pages[active_page] immediately, so
            // the PAGE node's compile (which reads pages[]) sees the live colours
            // without waiting for a page-switch or save to flush them.
            scr_vbmp_page_store(_asset);
        }
    }
    _ty += 44;
    draw_set_color(make_color_rgb(70, 70, 90));
    draw_text(_tx, _ty, "L=select  R=cycle colour");
    _ty += 20;

    // ── DITHER CONTROLS (FILL tool only) ─────────────────────────────────
    if (_m.tool == "FILL") {
        draw_set_color(c_ltgray);
        draw_text(_tx, _ty, "DITHER:");
        _ty += 16;
        // Pattern mode buttons: SOLID / CHECKER / INTERLACE
        var _pat_lbls = ["SOLID", "CHECKER", "INTERLACE"];
        var _pat_bw = 88;
        for (var _p = 0; _p < 3; _p++) {
            var _pbx = _tx;
            var _pby = _ty + _p * 20;
            var _pact = (_m.dither_pat == _p);
            var _phov = point_in_rectangle(_mx, _my, _pbx, _pby, _pbx + _pat_bw, _pby + 18);
            draw_set_color(_phov ? make_color_rgb(80, 80, 110) : (_pact ? make_color_rgb(20, 60, 60) : make_color_rgb(40, 40, 60)));
            draw_rectangle(_pbx, _pby, _pbx + _pat_bw, _pby + 18, false);
            draw_set_color(_pact ? c_aqua : make_color_rgb(90, 90, 110));
            draw_rectangle(_pbx, _pby, _pbx + _pat_bw, _pby + 18, true);
            draw_set_color(_pact ? c_aqua : c_white);
            draw_text(_pbx + 4, _pby + 3, _pat_lbls[_p]);
            if (_phov && mouse_check_button_pressed(mb_left)) _m.dither_pat = _p;
        }
        _ty += 3 * 20 + 4;
        // Second colour swatch (only meaningful when pattern > 0)
        draw_set_color(c_ltgray);
        draw_text(_tx, _ty, "2ND COL:");
        var _d2x = _tx + 74;
        var _d2hov = point_in_rectangle(_mx, _my, _d2x, _ty - 2, _d2x + 18, _ty + 16);
        var _d2slots = [_m.bg, _m.col1, _m.col2, _m.col3];
        draw_set_color(scr_c64_pepto_colour(_d2slots[_m.dither_colb]));
        draw_rectangle(_d2x, _ty - 2, _d2x + 18, _ty + 16, false);
        draw_set_color(c_white);
        draw_rectangle(_d2x, _ty - 2, _d2x + 18, _ty + 16, true);
        draw_text(_d2x + 22, _ty, string(_m.dither_colb));
        // Left-click cycles which selector slot (0..3) is the 2nd colour
        if (_d2hov && mouse_check_button_pressed(mb_left)) {
            _m.dither_colb = (_m.dither_colb + 1) mod 4;
        }
        _ty += 22;

        // Blocked-fill warning line (auto-clears). Shown only while the timer
        // is running; counts down once per drawn frame.
        if (vbmp_fill_warn_timer > 0) {
            draw_set_color(c_red);
            draw_text(_tx, _ty, vbmp_fill_warn_msg);
            _ty += 36;
            vbmp_fill_warn_timer -= 1;
        }
    }

    // ── RECOLOUR PICKERS (RECOL_C / RECOL_S tools only) ──────────────────
    // Dedicated colour choosers for the recolour override commands. CRAM
    // overrides one colour (col3 / colour-RAM nibble); SRAM overrides two
    // (col1/col2 / screen-RAM nibbles). Right-click a swatch to cycle 0..15.
    // Pickers are asset-manager instance vars (vbmp_recol_*), not per-asset
    // meta — one recolour palette shared across the editor session.
    if (_m.tool == "RECOL_C" || _m.tool == "RECOL_S") {
        draw_set_color(c_ltgray);
        draw_text(_tx, _ty, (_m.tool == "RECOL_C") ? "RECOLOUR CRAM (col3):" : "RECOLOUR SRAM (col1/col2):");
        _ty += 16;

        if (_m.tool == "RECOL_C") {
            var _rcx = _tx;
            var _rc_hov = point_in_rectangle(_mx, _my, _rcx, _ty, _rcx + 25, _ty + 24);
            draw_set_color(scr_c64_pepto_colour(vbmp_recol_c3));
            draw_rectangle(_rcx, _ty, _rcx + 25, _ty + 24, false);
            draw_set_color(c_white);
            draw_rectangle(_rcx, _ty, _rcx + 25, _ty + 24, true);
            draw_text(_rcx + 3, _ty + 26, "C3:" + string(vbmp_recol_c3));
            if (_rc_hov && mouse_check_button_pressed(mb_right)) vbmp_recol_c3 = (vbmp_recol_c3 + 1) mod 16;
        } else {
            var _rc1x = _tx;
            var _rc1_hov = point_in_rectangle(_mx, _my, _rc1x, _ty, _rc1x + 25, _ty + 24);
            draw_set_color(scr_c64_pepto_colour(vbmp_recol_c1));
            draw_rectangle(_rc1x, _ty, _rc1x + 25, _ty + 24, false);
            draw_set_color(c_white);
            draw_rectangle(_rc1x, _ty, _rc1x + 25, _ty + 24, true);
            draw_text(_rc1x + 3, _ty + 26, "C1:" + string(vbmp_recol_c1));
            if (_rc1_hov && mouse_check_button_pressed(mb_right)) vbmp_recol_c1 = (vbmp_recol_c1 + 1) mod 16;

            var _rc2x = _tx + 35;
            var _rc2_hov = point_in_rectangle(_mx, _my, _rc2x, _ty, _rc2x + 25, _ty + 24);
            draw_set_color(scr_c64_pepto_colour(vbmp_recol_c2));
            draw_rectangle(_rc2x, _ty, _rc2x + 25, _ty + 24, false);
            draw_set_color(c_white);
            draw_rectangle(_rc2x, _ty, _rc2x + 25, _ty + 24, true);
            draw_text(_rc2x + 3, _ty + 26, "C2:" + string(vbmp_recol_c2));
            if (_rc2_hov && mouse_check_button_pressed(mb_right)) vbmp_recol_c2 = (vbmp_recol_c2 + 1) mod 16;
        }
        _ty += 44;
        draw_set_color(make_color_rgb(70, 70, 90));
        draw_text(_tx, _ty, "R=cycle colour  drag=cell area");
        _ty += 18;
    }

    // ── UNDO / CLEAR ─────────────────────────────────────────────────────
    var _ubx = _tx;
    var _ub_hov = point_in_rectangle(_mx, _my, _ubx, _ty, _ubx + 80, _ty + 18);
    draw_set_color(_ub_hov ? make_color_rgb(120, 90, 40) : make_color_rgb(70, 50, 20));
    draw_rectangle(_ubx, _ty, _ubx + 80, _ty + 18, false);
    draw_set_color(c_white);
    draw_text(_ubx + 6, _ty + 3, "UNDO LAST");
    if (_ub_hov && mouse_check_button_pressed(mb_left) && array_length(_m.commands) > 0) {
        array_delete(_m.commands, array_length(_m.commands) - 1, 1);
        _m.last_emitted_col = -1; // force next commit to re-establish colour
        _m.vbmp_dirty = true;
    }
    // Advance _ty past the UNDO LAST row (CLEAR no longer lives here, so the
    // column's flow ends at UNDO).
    _ty += 26;

    // CLEAR — fully decoupled, fixed position below the canvas box, centred
    // under it. Independent of _ty and the active tool, so nothing above can
    // shove it around. Destructive, so kept well clear of every other control.
    var _cl_w  = 60;
    var _clbx  = _box_x + (_box_w * 0.5) - (_cl_w * 0.5); // centred under canvas
    var _cl_y  = _box_y + _box_h + 24;                    // just below box bottom edge
    var _cl_hov = point_in_rectangle(_mx, _my, _clbx, _cl_y, _clbx + _cl_w, _cl_y + 18);
    draw_set_color(_cl_hov ? make_color_rgb(200, 60, 60) : make_color_rgb(120, 30, 30));
    draw_rectangle(_clbx, _cl_y, _clbx + _cl_w, _cl_y + 18, false);
    draw_set_color(c_white);
    draw_text(_clbx + 8, _cl_y + 3, "CLEAR");
    if (_cl_hov && mouse_check_button_pressed(mb_left)) {
        _m.commands = [];
        _m.last_emitted_col = -1;
        _m.vbmp_dirty = true;
    }
	
	
    // ── COMMAND LIST (own column, far right, full panel height) ──────────
    var _clx  = _box_x + _box_w + 295;    // far-right column start (further 10px left)
    if (_clx > _vx2 - 295) _clx = _vx2 - 295; // keep it inside the panel (clamp follows the shift)
    var _cly  = _box_y - 40;               // align near canvas top
    var _col_w = 260;                      // list column width 
    var _total = array_length(_m.commands);

    // Compute this page's stream byte total (sum of per-command costs plus the
    // 1-byte END terminator the compiler appends per page), and the grand total
    // across every page in the asset — so the readout reflects the whole PRG
    // footprint, not just the page on screen.
    var _page_bytes = 1; // END byte
    for (var _bi = 0; _bi < _total; _bi++) {
        _page_bytes += _vbmp_cmd_bytes(_m.commands[_bi]);
    }
    var _all_bytes = 0;
    var _all_pages = 0;
    if (variable_struct_exists(_m, "pages") && is_array(_m.pages)) {
        _all_pages = array_length(_m.pages);
        for (var _pgi = 0; _pgi < _all_pages; _pgi++) {
            var _pgs = _m.pages[_pgi];
            var _pgc = (is_struct(_pgs) && variable_struct_exists(_pgs, "commands") && is_array(_pgs.commands))
                ? _pgs.commands : [];
            var _pb = 1; // END byte for this page
            for (var _pci = 0; _pci < array_length(_pgc); _pci++) {
                _pb += _vbmp_cmd_bytes(_pgc[_pci]);
            }
            _all_bytes += _pb;
        }
    } else {
        _all_pages = 1;
        _all_bytes = _page_bytes;
    }

    draw_set_color(c_ltgray);
    draw_text(_clx, _cly, "COMMANDS (" + string(_total) + "):");
    // Byte readout: this page, then all pages combined.
    draw_set_color(make_color_rgb(150, 200, 150));
    draw_text(_clx, _cly - 14, "PAGE " + string(_page_bytes) + "b   ALL " + string(_all_pages) + "pg " + string(_all_bytes) + "b");
    var _cly_list = _cly + 18;

    var _list_h   = ((_box_y + _box_h) - _cly_list) * 1.3; // taller list column
    var _row_h    = 14;
    var _rows_vis = max(0, floor(_list_h / _row_h));
    if (_rows_vis > 0) {
        _m.cmd_scroll = clamp(_m.cmd_scroll, 0, max(0, _total - _rows_vis));
    } else {
        _m.cmd_scroll = 0;
    }
    var _start = _m.cmd_scroll;

    // Faint column background so the list reads as its own panel
    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_clx - 4, _cly_list - 2, _clx + _col_w + 4, _cly_list + _rows_vis * _row_h + 2, false);
    draw_set_color(make_color_rgb(50, 50, 70));
    draw_rectangle(_clx - 4, _cly_list - 2, _clx + _col_w + 4, _cly_list + _rows_vis * _row_h + 2, true);

    for (var _r = 0; _r < _rows_vis && (_start + _r) < _total; _r++) {
        var _idx = _start + _r;
        if (_idx < 0 || _idx >= array_length(_m.commands)) continue;
        var _cmd = _m.commands[_idx];
        var _ry  = _cly_list + _r * _row_h;
        var _rhov = point_in_rectangle(_mx, _my, _clx, _ry, _clx + _col_w, _ry + _row_h);
        if (_rhov) {
            draw_set_color(make_color_rgb(40, 40, 60));
            draw_rectangle(_clx, _ry, _clx + _col_w, _ry + _row_h, false);
        }
        draw_set_color(c_white);
        var _lbl = string(_idx) + ": " + string(_cmd.op);
        if (variable_struct_exists(_cmd, "x"))  _lbl += " " + string(_cmd.x) + "," + string(_cmd.y);
        if (variable_struct_exists(_cmd, "x0")) _lbl += " " + string(_cmd.x0) + "," + string(_cmd.y0) + "-" + string(_cmd.x1) + "," + string(_cmd.y1);
        if (variable_struct_exists(_cmd, "cx")) _lbl += " c" + string(_cmd.cx) + "," + string(_cmd.cy);
        if (_cmd.op == "setcol") _lbl += " " + string(_cmd.col);
        if (variable_struct_exists(_cmd, "row")) _lbl += " r" + string(_cmd.row) + " c" + string(_cmd.col) + " " + string(_cmd.w) + "x" + string(_cmd.h);
        if (variable_struct_exists(_cmd, "sc"))  _lbl += " s" + string(_cmd.sc) + "," + string(_cmd.sr) + "->" + string(_cmd.dc) + "," + string(_cmd.dr) + " " + string(_cmd.w) + "x" + string(_cmd.h);
        // Per-command stream byte cost, right-aligned-ish before the [X] button.
        _lbl += "  <" + string(_vbmp_cmd_bytes(_cmd)) + "b>";
        draw_text(_clx + 2, _ry + 1, _lbl);
        // Delete button at the column's right edge
        var _delx = _clx + _col_w - 24;
        var _dhov = point_in_rectangle(_mx, _my, _delx, _ry, _delx + 24, _ry + _row_h);
        draw_set_color(_dhov ? c_red : make_color_rgb(120, 60, 60));
        draw_text(_delx, _ry + 1, "[X]");
        if (_dhov && mouse_check_button_pressed(mb_left)) {
            array_delete(_m.commands, _idx, 1);
            _m.vbmp_dirty = true;
            break; // array mutated — stop iterating this frame, redraw next frame
        }
    }
    // Scroll with wheel when hovering the list column
    if (point_in_rectangle(_mx, _my, _clx - 4, _cly_list - 2, _clx + _col_w + 4, _cly_list + _rows_vis * _row_h + 2)) {
        if (mouse_wheel_up())   _m.cmd_scroll = max(0, _m.cmd_scroll - 1);
        if (mouse_wheel_down()) _m.cmd_scroll = min(max(0, _total - _rows_vis), _m.cmd_scroll + 1);
    }

    // ── TOOL INPUT ON CANVAS ─────────────────────────────────────────────
    if (_in_canvas) {
        var _tool = _m.tool;

        // Single-click tools: PLOT, FILL
        if (mouse_check_button_pressed(mb_left) && (_tool == "PLOT" || _tool == "FILL")) {
            // ── Dither-fill guard ──────────────────────────────────────────
            // A dither fill self-walls on the C64 when colA (the active
            // selector) equals the colour already under the seed: the flood
            // matches the seed colour and paints colA on one parity, leaving
            // those pixels still seed-coloured and floodable while the colB
            // pixels wall it off — the scan strangles. Block it and warn.
            // Only dither fills (pattern != 0) are affected; solid fills are
            // fine. Seed colour is read from the preview surface at the click
            // point and reverse-mapped to a selector index (0..3).
            var _block_fill = false;
            if (_tool == "FILL" && _m.dither_pat != 0 && surface_exists(_m.preview_surf)) {
                // Resolve the 4 slot colours to compare against.
                var _g_bg   = variable_struct_exists(_m, "bg")   ? _m.bg   : 0;
                var _g_col1 = variable_struct_exists(_m, "col1") ? _m.col1 : 1;
                var _g_col2 = variable_struct_exists(_m, "col2") ? _m.col2 : 2;
                var _g_col3 = variable_struct_exists(_m, "col3") ? _m.col3 : 3;
                var _g_slots = [
                    scr_c64_pepto_colour(_g_bg),
                    scr_c64_pepto_colour(_g_col1),
                    scr_c64_pepto_colour(_g_col2),
                    scr_c64_pepto_colour(_g_col3)
                ];
                // Sample the seed pixel (MC-snapped, same as the fill will use).
                var _seed_col = surface_getpixel(_m.preview_surf, _snap_px, _raw_py);
                var _seed_r = color_get_red(_seed_col);
                var _seed_g = color_get_green(_seed_col);
                var _seed_b = color_get_blue(_seed_col);
                // Reverse-map to a selector index (first slot whose RGB matches).
                var _seed_sel = -1;
                for (var _gi = 0; _gi < 4; _gi++) {
                    if (color_get_red(_g_slots[_gi]) == _seed_r
                     && color_get_green(_g_slots[_gi]) == _seed_g
                     && color_get_blue(_g_slots[_gi]) == _seed_b) {
                        _seed_sel = _gi;
                        break;
                    }
                }
                // Block only if colA (active selector) == the seed's selector.
                if (_seed_sel != -1 && _m.active_col == _seed_sel) {
                    _block_fill = true;
                    vbmp_fill_warn_msg   = "DITHER: col 1 must differ\nfrom fill area colour";
                    vbmp_fill_warn_timer = game_get_speed(gamespeed_fps) * 4; // ~4s
                }
            }

            if (!_block_fill) {
                // Emit setcol only when the active selector changed since the last commit.
                if (_m.active_col != _m.last_emitted_col) {
                    array_push(_m.commands, { op: "setcol", col: _m.active_col });
                    _m.last_emitted_col = _m.active_col;
                }
                if (_tool == "PLOT") {
                    array_push(_m.commands, { op: "plot", x: _snap_px, y: _raw_py });
                } else {
                    array_push(_m.commands, { op: "fill", x: _snap_px, y: _raw_py, pattern: _m.dither_pat, colb: _m.dither_colb });
                }
                _m.vbmp_dirty = true;
            }
        }

        // Two-point tools: press sets anchor, release commits
        var _two_pt = (_tool == "LINE" || _tool == "RECT" || _tool == "RECTFILL" || _tool == "ELLIPSE" || _tool == "ELLIPSEFILL");
        if (_two_pt) {
            if (mouse_check_button_pressed(mb_left)) {
                _m.draw_x1 = _snap_px;
                _m.draw_y1 = _raw_py;
            }
            if (_m.draw_x1 >= 0 && mouse_check_button_released(mb_left)) {
                var _x0 = _m.draw_x1, _y0 = _m.draw_y1;
                var _x1 = _snap_px,   _y1 = _raw_py;
                if (_m.active_col != _m.last_emitted_col) {
                    array_push(_m.commands, { op: "setcol", col: _m.active_col });
                    _m.last_emitted_col = _m.active_col;
                }
                switch (_tool) {
                    case "LINE":        array_push(_m.commands, { op: "line",        x0: _x0, y0: _y0, x1: _x1, y1: _y1 }); break;
                    case "RECT":        array_push(_m.commands, { op: "rect",        x0: _x0, y0: _y0, x1: _x1, y1: _y1 }); break;
                    case "RECTFILL":    array_push(_m.commands, { op: "rectfill",    x0: _x0, y0: _y0, x1: _x1, y1: _y1 }); break;
                    case "ELLIPSE": {
                        var _ecx = (_x0 + _x1) div 2, _ecy = (_y0 + _y1) div 2;
                        var _erx = abs(_x1 - _x0) div 4, _ery = abs(_y1 - _y0) div 2;
                        array_push(_m.commands, { op: "ellipse", cx: _ecx, cy: _ecy, rx: max(1, _erx), ry: max(1, _ery) });
                    } break;
                    case "ELLIPSEFILL": {
                        var _ecx = (_x0 + _x1) div 2, _ecy = (_y0 + _y1) div 2;
                        var _erx = abs(_x1 - _x0) div 4, _ery = abs(_y1 - _y0) div 2;
                        array_push(_m.commands, { op: "ellipsefill", cx: _ecx, cy: _ecy, rx: max(1, _erx), ry: max(1, _ery) });
                    } break;
                }
                _m.draw_x1 = -1;
                _m.vbmp_dirty = true;
            }
        }
    }

    // ── RECOLOUR SELECTION (cell-snapped rectangle) ──────────────────────
    // RECOL_C / RECOL_S: press sets a cell anchor, release commits a
    // {recolor_cram|recolor_sram, col,row,w,h, colour(s)} command. Coords are
    // absolute char cells (col 0..39, row 0..24); the mouse is already clamped
    // to the drawable window so selections land inside it. Snaps to 8px cells.
    // No SETCOL is emitted — the command carries its own colours. Anchor lives
    // on the asset manager (vbmp_recol_ax/ay), not per-asset meta.
    if (_in_canvas && (_m.tool == "RECOL_C" || _m.tool == "RECOL_S")) {
        var _cell_c = _raw_px div 8;
        var _cell_r = _raw_py div 8;
        if (mouse_check_button_pressed(mb_left)) {
            vbmp_recol_ax = _cell_c;
            vbmp_recol_ay = _cell_r;
        }
        if (vbmp_recol_ax >= 0 && mouse_check_button_released(mb_left)) {
            var _c0  = min(vbmp_recol_ax, _cell_c);
            var _r0  = min(vbmp_recol_ay, _cell_r);
            var _cw2 = abs(_cell_c - vbmp_recol_ax) + 1;
            var _ch2 = abs(_cell_r - vbmp_recol_ay) + 1;
            if (_m.tool == "RECOL_C") {
                array_push(_m.commands, { op: "recolor_cram", col: _c0, row: _r0, w: _cw2, h: _ch2, c3: vbmp_recol_c3 });
            } else {
                array_push(_m.commands, { op: "recolor_sram", col: _c0, row: _r0, w: _cw2, h: _ch2, c1: vbmp_recol_c1, c2: vbmp_recol_c2 });
            }
            vbmp_recol_ax = -1;
            vbmp_recol_ay = -1;
            _m.vbmp_dirty = true;
        }
    }
	
	// ── COPYRGN SELECTION (two-phase, cell-snapped) ──────────────────────
    // Phase 0: drag marks the source rect (press anchors, release locks the
    // source + advances to phase 1). Phase 1: the source size is fixed; the
    // next click places the dest top-left cell and emits a copyregion command,
    // then returns to phase 0. Coords are absolute char cells (0..39, 0..24);
    // the mouse is already clamped to the drawable window. Anchor + locked
    // source live on the asset manager (vbmp_copy_*), not per-asset meta.
    if (_in_canvas && _m.tool == "COPYRGN") {
        var _cc = _raw_px div 8;
        var _cr = _raw_py div 8;
        if (vbmp_copy_phase == 0) {
            // Source drag.
            if (mouse_check_button_pressed(mb_left)) {
                vbmp_copy_ax = _cc;
                vbmp_copy_ay = _cr;
            }
            if (vbmp_copy_ax >= 0 && mouse_check_button_released(mb_left)) {
                vbmp_copy_sc = min(vbmp_copy_ax, _cc);
                vbmp_copy_sr = min(vbmp_copy_ay, _cr);
                vbmp_copy_sw = abs(_cc - vbmp_copy_ax) + 1;
                vbmp_copy_sh = abs(_cr - vbmp_copy_ay) + 1;
                vbmp_copy_ax = -1;
                vbmp_copy_ay = -1;
                vbmp_copy_phase = 1; // now awaiting dest click
            }
        } else {
            // Phase 1: dest placement. Click sets the dest top-left cell.
            // Clamp so the dest block stays on the 40x25 grid regardless of
            // where the cursor is (matches compile/runtime clamping).
            if (mouse_check_button_pressed(mb_left)) {
                var _dc = _cc;
                var _dr = _cr;
                // Clamp the dest block inside the DRAWABLE WINDOW (cols 8..31,
                // rows 5..19), not the full 40x25 grid — a copy must not land
                // in the shaded border outside the cyan editable region.
                if (_dc + vbmp_copy_sw > 32) _dc = 32 - vbmp_copy_sw;
                if (_dr + vbmp_copy_sh > 20) _dr = 20 - vbmp_copy_sh;
                if (_dc < 8) _dc = 8;
                if (_dr < 5) _dr = 5;
                array_push(_m.commands, {
                    op: "copyregion",
                    sc: vbmp_copy_sc, sr: vbmp_copy_sr,
                    dc: _dc,          dr: _dr,
                    w:  vbmp_copy_sw, h:  vbmp_copy_sh
                });
                _m.vbmp_dirty = true;
                vbmp_copy_phase = 0; // ready for the next copy
            }
        }
    }

    // ── LIVE RUBBER-BAND PREVIEW for in-progress 2-point op ──────────────
    // Route the pending op through the SAME commit + replay path the drop uses,
    // instead of re-rasterising in GUI space (which can't match: the surface is
    // scaled by draw_surface_part_ext, GUI rects are positioned independently).
    // Build the pending op exactly as the commit block does, append it to a temp
    // command list, replay onto preview_surf, blit, then replay the REAL list
    // back so the surface ends the frame committed-only (no flag, no artifact).
    if (_m.draw_x1 >= 0 && _in_canvas) {
        var _px0 = _m.draw_x1;
        var _py0 = _m.draw_y1;
        var _px1 = _snap_px;
        var _py1 = _raw_py;

        var _pending = -1;
        if (_m.tool == "LINE") {
            _pending = { op: "line", x0: _px0, y0: _py0, x1: _px1, y1: _py1 };
        }
        else if (_m.tool == "RECT") {
            _pending = { op: "rect", x0: _px0, y0: _py0, x1: _px1, y1: _py1 };
        }
        else if (_m.tool == "RECTFILL") {
            _pending = { op: "rectfill", x0: _px0, y0: _py0, x1: _px1, y1: _py1 };
        }
        else if (_m.tool == "ELLIPSE") {
            var _ecx = (_px0 + _px1) div 2;
            var _ecy = (_py0 + _py1) div 2;
            var _erx = max(1, abs(_px1 - _px0) div 4);
            var _ery = max(1, abs(_py1 - _py0) div 2);
            _pending = { op: "ellipse", cx: _ecx, cy: _ecy, rx: _erx, ry: _ery };
        }
        else if (_m.tool == "ELLIPSEFILL") {
            var _ecx = (_px0 + _px1) div 2;
            var _ecy = (_py0 + _py1) div 2;
            var _erx = max(1, abs(_px1 - _px0) div 4);
            var _ery = max(1, abs(_py1 - _py0) div 2);
            _pending = { op: "ellipsefill", cx: _ecx, cy: _ecy, rx: _erx, ry: _ery };
        }

        if (_pending != -1) {
            // Temp list = committed commands + setcol(active) + pending op.
            // Shallow-copy so the real list is never mutated.
            var _real_cmds = _m.commands;
            var _temp_cmds = [];
            var _rc = array_length(_real_cmds);
            for (var _c = 0; _c < _rc; _c++) {
                _temp_cmds[_c] = _real_cmds[_c];
            }
            array_push(_temp_cmds, { op: "setcol", col: _m.active_col });
            array_push(_temp_cmds, _pending);

            // Replay temp onto the surface (surface = committed + pending).
            _m.commands = _temp_cmds;
            scr_vbmp_replay_to_surface(_asset);

            // Blit with the SAME parameters as the top-of-function canvas draw,
            // so the pending op appears composited exactly as it will on commit.
            var _prev_filter2 = gpu_get_texfilter();
            gpu_set_texfilter(false);
            if (surface_exists(_m.preview_surf)) {
                var _scl_x2 = _cw / 320;
                var _scl_y2 = _ch / 200;
                var _src_l2 = (_box_x - _sx) / _scl_x2;
                var _src_t2 = (_box_y - _sy) / _scl_y2;
                var _src_w2 = _box_w / _scl_x2;
                var _src_h2 = _box_h / _scl_y2;
                draw_surface_part_ext(_m.preview_surf, _src_l2, _src_t2, _src_w2, _src_h2, _box_x, _box_y, _scl_x2, _scl_y2, c_white, 1);
            }
            gpu_set_texfilter(_prev_filter2);

            // Restore the real list and rebuild the surface committed-only, so
            // ending the drag or leaving the canvas shows the clean image with
            // no sticky rubber-band and no page_store side effects.
            _m.commands = _real_cmds;
            scr_vbmp_replay_to_surface(_asset);
        }
    }

    // ── RECOLOUR RUBBER-BAND (cell-aligned) ──────────────────────────────
    if (vbmp_recol_ax >= 0 && _in_canvas && (_m.tool == "RECOL_C" || _m.tool == "RECOL_S")) {
        var _cc0 = min(vbmp_recol_ax, _raw_px div 8);
        var _cr0 = min(vbmp_recol_ay, _raw_py div 8);
        var _cc1 = max(vbmp_recol_ax, _raw_px div 8) + 1; // exclusive right/bottom edge
        var _cr1 = max(vbmp_recol_ay, _raw_py div 8) + 1;
        var _selx0 = _sx + ((_cc0 * 8) / 320) * _cw;
        var _sely0 = _sy + ((_cr0 * 8) / 200) * _ch;
        var _selx1 = _sx + ((_cc1 * 8) / 320) * _cw;
        var _sely1 = _sy + ((_cr1 * 8) / 200) * _ch;
        draw_set_color(c_yellow);
        draw_rectangle(_selx0, _sely0, _selx1, _sely1, true);
        draw_set_alpha(0.18);
        draw_rectangle(_selx0, _sely0, _selx1, _sely1, false);
        draw_set_alpha(1.0);
    }
	
	// ── COPYRGN RUBBER-BAND (cell-aligned, two-phase) ────────────────────
    // Phase 0: yellow source rect while dragging. Phase 1: locked source rect
    // drawn solid, plus a cyan dest-sized ghost tracking the cursor (clamped
    // on-grid) so the drop target is visible before the confirming click.
    if (_in_canvas && _m.tool == "COPYRGN") {
        // Live source drag (phase 0).
        if (vbmp_copy_phase == 0 && vbmp_copy_ax >= 0) {
            var _qc0 = min(vbmp_copy_ax, _raw_px div 8);
            var _qr0 = min(vbmp_copy_ay, _raw_py div 8);
            var _qc1 = max(vbmp_copy_ax, _raw_px div 8) + 1;
            var _qr1 = max(vbmp_copy_ay, _raw_py div 8) + 1;
            var _qx0 = _sx + ((_qc0 * 8) / 320) * _cw;
            var _qy0 = _sy + ((_qr0 * 8) / 200) * _ch;
            var _qx1 = _sx + ((_qc1 * 8) / 320) * _cw;
            var _qy1 = _sy + ((_qr1 * 8) / 200) * _ch;
            draw_set_color(c_yellow);
            draw_rectangle(_qx0, _qy0, _qx1, _qy1, true);
            draw_set_alpha(0.18);
            draw_rectangle(_qx0, _qy0, _qx1, _qy1, false);
            draw_set_alpha(1.0);
        }
        // Phase 1: locked source (yellow outline) + dest ghost (cyan).
        if (vbmp_copy_phase == 1) {
            // Locked source rect.
            var _sxc0 = _sx + ((vbmp_copy_sc * 8) / 320) * _cw;
            var _syc0 = _sy + ((vbmp_copy_sr * 8) / 200) * _ch;
            var _sxc1 = _sx + (((vbmp_copy_sc + vbmp_copy_sw) * 8) / 320) * _cw;
            var _syc1 = _sy + (((vbmp_copy_sr + vbmp_copy_sh) * 8) / 200) * _ch;
            draw_set_color(c_yellow);
            draw_rectangle(_sxc0, _syc0, _sxc1, _syc1, true);

            // Dest ghost at the cursor cell, clamped to the DRAWABLE WINDOW
            // (mirror the commit — cols 8..31, rows 5..19).
            var _gdc = _raw_px div 8;
            var _gdr = _raw_py div 8;
            if (_gdc + vbmp_copy_sw > 32) _gdc = 32 - vbmp_copy_sw;
            if (_gdr + vbmp_copy_sh > 20) _gdr = 20 - vbmp_copy_sh;
            if (_gdc < 8) _gdc = 8;
            if (_gdr < 5) _gdr = 5;
            var _gx0 = _sx + ((_gdc * 8) / 320) * _cw;
            var _gy0 = _sy + ((_gdr * 8) / 200) * _ch;
            var _gx1 = _sx + (((_gdc + vbmp_copy_sw) * 8) / 320) * _cw;
            var _gy1 = _sy + (((_gdr + vbmp_copy_sh) * 8) / 200) * _ch;
            draw_set_color(c_aqua);
            draw_rectangle(_gx0, _gy0, _gx1, _gy1, true);
            draw_set_alpha(0.15);
            draw_rectangle(_gx0, _gy0, _gx1, _gy1, false);
            draw_set_alpha(1.0);
        }
    }

    // Cursor crosshair
    if (_in_canvas) {
        draw_set_color(c_white);
        draw_set_alpha(0.5);
        draw_line(_box_x, _my, _box_x + _box_w, _my);
        draw_line(_mx, _box_y, _mx, _box_y + _box_h);
        draw_set_alpha(1.0);
        draw_set_color(c_yellow);
        draw_text(_tx - 860, _box_y + _box_h + 6, "X POS:" + string(_snap_px) + " Y POS: " + string(_raw_py));
    }
	draw_set_color(c_aqua);
	draw_text( _tx - 860,930,"PLEASE NOTE THE FINAL RESULT MAY DIFFER DUE TO DIFFERENT\nALGORTHIMS USED IN RUN TIME AS WELL AS COLOUR CLASH")
	

    // Keep pages[active_page] continuously in sync with the live top-level
    // editor fields. Any edit this frame (draw, delete, colour, undo, clear)
    // set vbmp_dirty; flush it into the active page so the PAGE node's compile
    // — which reads pages[] — always reflects exactly what's on the canvas,
    // with no dependency on a save or page-switch to propagate the change.
    if (_m.vbmp_dirty) {
        scr_vbmp_page_store(_asset);
    }

    // Reset draw state so nothing leaks into subsequent GUI draws.
    draw_set_alpha(1.0);
    draw_set_color(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}