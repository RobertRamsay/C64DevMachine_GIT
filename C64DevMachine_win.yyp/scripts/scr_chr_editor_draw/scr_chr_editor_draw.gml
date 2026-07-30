/// scr_chr_editor_draw(_asset, _ox, _oy, _mc_mode)
/// Draws the 8x8 pixel tile editor at (_ox, _oy).
/// Handles HR and MC rendering. Buttons: Flip X, Flip Y, Clear.
/// Click handling is done inline (Draw GUI can call this from both
/// the inline viewer and the undocked panel).
function scr_chr_editor_draw(_asset, _ox, _oy, _mc_mode, _show_fg_swatch = true) {

    var _mx = global.gui_mouse_x;
    var _my = global.gui_mouse_y;

    // Ensure save variables exist (prevents crash on old assets)
    if (!variable_struct_exists(_asset.meta, "autosave"))    _asset.meta.autosave    = true;
    if (!variable_struct_exists(_asset.meta, "is_dirty"))    _asset.meta.is_dirty    = false;
    if (!variable_struct_exists(_asset.meta, "flash_timer")) _asset.meta.flash_timer = 0;
    if (!variable_struct_exists(_asset.meta, "undo_stack"))  _asset.meta.undo_stack  = [];
    if (!variable_struct_exists(_asset.meta, "redo_stack"))  _asset.meta.redo_stack  = [];

    var _scale  = 16; // pixels per C64 pixel in HR; MC pairs are 2*_scale wide
    var _grid_w = 8 * _scale;
    var _grid_h = 8 * _scale;

    // Fill-tool toggle state (init in object Create; this is a safety net)
    if (!variable_instance_exists(id, "chr_fill_mode")) {
        chr_fill_mode = false;
    }

    // Resolve colours
    var _mc_fg_idx = variable_struct_exists(_asset.meta, "mc_fg")   ? _asset.meta.mc_fg   : 1;
    var _mc_bg_idx = variable_struct_exists(_asset.meta, "mc_bg")   ? _asset.meta.mc_bg   : 0;
    var _mc_c1_idx = variable_struct_exists(_asset.meta, "mc_col1") ? _asset.meta.mc_col1 : 1;
    var _mc_c2_idx = variable_struct_exists(_asset.meta, "mc_col2") ? _asset.meta.mc_col2 : 2;

    // Pixel BUFFER FORMAT: only true MC (_mc_mode == 1) packs 2-bit pairs.
    // ECM (_mc_mode == 2) stores pixels the same 1-bit-per-pixel way as HR —
    // the 4-background-colour selection lives at the map/tileset cell level,
    // not in the charset bitmap itself.
    var _pixel_is_mc = (_mc_mode == 1);

    // ECM background preview (BG0 = mc_bg, BG1-3 dedicated fields). Only used
    // to preview mode-2 chars; the real per-cell BG choice happens downstream.
    if (!variable_struct_exists(_asset.meta, "ecm_bg1")) _asset.meta.ecm_bg1 = 6;
    if (!variable_struct_exists(_asset.meta, "ecm_bg2")) _asset.meta.ecm_bg2 = 14;
    if (!variable_struct_exists(_asset.meta, "ecm_bg3")) _asset.meta.ecm_bg3 = 3;
    var _ecm_bg_fields = ["mc_bg", "ecm_bg1", "ecm_bg2", "ecm_bg3"];
    var _ecm_bg_sel     = clamp(chr_active_ecm_bg, 0, 3);
    var _ecm_bg_idx     = variable_struct_get(_asset.meta, _ecm_bg_fields[_ecm_bg_sel]);

    var _palette = [
        scr_c64_pepto_colour(_mc_mode == 2 ? _ecm_bg_idx : _mc_bg_idx),  // 00 / off
        scr_c64_pepto_colour(_mc_c1_idx),  // 01
        scr_c64_pepto_colour(_mc_c2_idx),  // 10
        scr_c64_pepto_colour(_mc_fg_idx),  // 11 / on
    ];

    // Background
    draw_set_color(c_black);
    draw_rectangle(_ox, _oy, _ox + _grid_w, _oy + _grid_h, false);

    var _tile_base = chr_edit_idx * 8;
    if (!buffer_exists(_asset.buffer) || _tile_base + 7 >= buffer_get_size(_asset.buffer)) {
        chr_edit_idx = 0;
        _tile_base   = 0;
    }

    // ---- DRAW PIXELS ----
    for (var _row = 0; _row < 8; _row++) {
        var _byte_pos = _tile_base + _row;
        if (!buffer_exists(_asset.buffer) || _byte_pos < 0 || _byte_pos >= buffer_get_size(_asset.buffer)) continue;
        var _byte = buffer_peek(_asset.buffer, _byte_pos, buffer_u8);

        if (_pixel_is_mc) {
            var _pair_w = _scale * 2;
            for (var _pair = 0; _pair < 4; _pair++) {
                var _bits = (_byte >> (6 - _pair * 2)) & 0x03;
                draw_set_color(_palette[_bits]);
                var _px1 = _ox + _pair * _pair_w;
                var _py1 = _oy + _row * _scale;
                draw_rectangle(_px1, _py1, _px1 + _pair_w, _py1 + _scale, false);
            }
        } else {
            for (var _col = 0; _col < 8; _col++) {
                var _val = (_byte >> (7 - _col)) & 0x01;
                draw_set_color(_val ? _palette[3] : _palette[0]);
                var _px1 = _ox + _col * _scale;
                var _py1 = _oy + _row * _scale;
                draw_rectangle(_px1, _py1, _px1 + _scale, _py1 + _scale, false);
            }
        }
    }

    // ---- GRID LINES ----
    draw_set_color(make_color_rgb(50, 50, 70));
    if (_pixel_is_mc) {
        for (var _gl = 0; _gl <= 4; _gl++)
            draw_line(_ox + _gl * _scale * 2, _oy, _ox + _gl * _scale * 2, _oy + _grid_h);
    } else {
        for (var _gl = 0; _gl <= 8; _gl++)
            draw_line(_ox + _gl * _scale, _oy, _ox + _gl * _scale, _oy + _grid_h);
    }
    for (var _gl = 0; _gl <= 8; _gl++)
        draw_line(_ox, _oy + _gl * _scale, _ox + _grid_w, _oy + _gl * _scale);

    // Border
    draw_set_color(make_color_rgb(100, 100, 160));
    draw_rectangle(_ox, _oy, _ox + _grid_w, _oy + _grid_h, true);

    // ---- TITLE + MODE — drawn below the grid ----
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_white);
    var _tile_label = (chr_edit_idx == 0) ? "BKG-TILE" : string(chr_edit_idx);
    var _mode_label = (_mc_mode == 2) ? "ECM" : (_mc_mode == 1 ? "MC" : "HR");
    draw_text(_ox, _oy + _grid_h + 6, "EDITING TILE:\n " + _tile_label
        + "  (" + _mode_label + ")");

    // ---- COPY & PASTE HANDLER ----
    if (!variable_struct_exists(global, "chr_clipboard")) {
        global.chr_clipboard = undefined;
    }

   // Skip inline single-tile Ctrl+C/V when:
    //  - a multi-SELECTION exists (grid handler owns Ctrl+C/V), OR
    //  - the multi-clipboard already has more than one entry and the
    //    user presses Ctrl+V (multi-paste must take priority).
    // A populated single-entry multi-clipboard does NOT block single
    // copy/paste — so a stale multi-clipboard never locks out the inline
    // shortcut.
    var _ed_grid_busy = false;
    if (instance_exists(obj_asset_manager)) {
        if (array_length(obj_asset_manager.chr_multi_select) > 0) {
            _ed_grid_busy = true;
        }
        if (array_length(obj_asset_manager.chr_clipboard) > 1
        &&  keyboard_check_pressed(ord("V"))) {
            _ed_grid_busy = true;
        }
    }

    if (scr_ctrl_held() && !_ed_grid_busy) {
        // Copy (CTRL+C) — single tile
        if (keyboard_check_pressed(ord("C"))) {
            global.chr_clipboard = array_create(8, 0);
            for (var _i = 0; _i < 8; _i++) {
                global.chr_clipboard[_i] = buffer_peek(_asset.buffer, _tile_base + _i, buffer_u8);
            }
            // Record the SOURCE char index so the META_TILESET case can copy its
            // char_lut entry (HR/MC mode + colour) across on paste.
            global.chr_clip_lut_src = chr_edit_idx;
            global.chr_clip_lut_dst = -1;
            // Clear any stale multi-clipboard so single paste wins next time
            if (instance_exists(obj_asset_manager)) {
                obj_asset_manager.chr_clipboard       = [];
                obj_asset_manager.chr_clipboard_owner = "";
            }
            show_debug_message("COPIED TILE: " + string(chr_edit_idx));
        }

        // Paste (CTRL+V) — single tile
        if (keyboard_check_pressed(ord("V")) && is_array(global.chr_clipboard)) {
            scr_chr_undo_push(_asset);
            for (var _i = 0; _i < 8; _i++) {
                buffer_poke(_asset.buffer, _tile_base + _i, buffer_u8, global.chr_clipboard[_i]);
            }
            // Flag the DEST char so the META_TILESET case copies char_lut
            // (HR/MC mode + colour) from src -> dst after this draw runs.
            global.chr_clip_lut_dst = chr_edit_idx;
            scr_asset_chr_build_preview(_asset);
            global.undo_dirty = true;
            _asset.meta.is_dirty = true;
            show_debug_message("PASTED TILE: " + string(chr_edit_idx));
        }
    }

    // ---- UNDO / REDO ----
    if (scr_ctrl_held() && keyboard_check_pressed(ord("Z"))) {
        if (array_length(_asset.meta.undo_stack) > 0) {
            var _last  = array_length(_asset.meta.undo_stack) - 1;
            var _entry = _asset.meta.undo_stack[_last];
            array_delete(_asset.meta.undo_stack, _last, 1);

            // Push current state to redo
            var _sz    = buffer_get_size(_asset.buffer);
            var _rsnap = buffer_create(_sz, buffer_fixed, 1);
            buffer_copy(_asset.buffer, 0, _sz, _rsnap, 0);
            var _redo_entry = {
                buf        : _rsnap,
                rows       : _asset.meta.rows,
                char_count : _asset.meta.char_count
            };
            array_push(_asset.meta.redo_stack, _redo_entry);

            // Restore undo entry
            if (is_struct(_entry)) {
                var _usize = buffer_get_size(_entry.buf);
                buffer_delete(_asset.buffer);
                _asset.buffer          = buffer_create(_usize, buffer_fixed, 1);
                buffer_copy(_entry.buf, 0, _usize, _asset.buffer, 0);
                _asset.meta.rows       = _entry.rows;
                _asset.meta.char_count = _entry.char_count;
                buffer_delete(_entry.buf);
            } else {
                var _usize = buffer_get_size(_entry);
                buffer_copy(_entry, 0, _usize, _asset.buffer, 0);
                buffer_delete(_entry);
            }

            scr_asset_chr_build_preview(_asset);
            _asset.meta.is_dirty = true;
        }
    }

    if (scr_ctrl_held() && keyboard_check_pressed(ord("Y"))) {
        if (array_length(_asset.meta.redo_stack) > 0) {
            var _last  = array_length(_asset.meta.redo_stack) - 1;
            var _entry = _asset.meta.redo_stack[_last];
            array_delete(_asset.meta.redo_stack, _last, 1);

            // Push current state to undo
            var _sz    = buffer_get_size(_asset.buffer);
            var _usnap = buffer_create(_sz, buffer_fixed, 1);
            buffer_copy(_asset.buffer, 0, _sz, _usnap, 0);
            var _undo_entry = {
                buf        : _usnap,
                rows       : _asset.meta.rows,
                char_count : _asset.meta.char_count
            };
            array_push(_asset.meta.undo_stack, _undo_entry);

            // Restore redo entry
            if (is_struct(_entry)) {
                var _rsize = buffer_get_size(_entry.buf);
                buffer_delete(_asset.buffer);
                _asset.buffer          = buffer_create(_rsize, buffer_fixed, 1);
                buffer_copy(_entry.buf, 0, _rsize, _asset.buffer, 0);
                _asset.meta.rows       = _entry.rows;
                _asset.meta.char_count = _entry.char_count;
                buffer_delete(_entry.buf);
            } else {
                var _rsize = buffer_get_size(_entry);
                buffer_copy(_entry, 0, _rsize, _asset.buffer, 0);
                buffer_delete(_entry);
            }

            scr_asset_chr_build_preview(_asset);
            _asset.meta.is_dirty = true;
        }
    }

    // ---- FLOOD FILL (when fill mode is ON) — intercepts left-click ----
    var _fill_consumed = false;
    if (chr_fill_mode &&
        mouse_check_button_pressed(mb_left) &&
        point_in_rectangle(_mx, _my, _ox, _oy, _ox + _grid_w, _oy + _grid_h)) {

        scr_chr_undo_push(_asset);

        // Resolve the clicked cell in cell-coords (0..7 for HR/ECM cols, 0..3 for MC pairs)
        if (_pixel_is_mc) {
            var _start_c = clamp(floor((_mx - _ox) / (_scale * 2)), 0, 3);
        } else {
            var _start_c = clamp(floor((_mx - _ox) / _scale), 0, 7);
        }
        var _start_r = clamp(floor((_my - _oy) / _scale), 0, 7);

        // Helper reads/writes operate on the buffer directly via _tile_base.
        // Read the value at a cell.
        var _read_cell = function(_buf, _base, _mc, _cc, _rr) {
            var _b = buffer_peek(_buf, _base + _rr, buffer_u8);
            if (_mc) {
                var _sh = 6 - _cc * 2;
                return (_b >> _sh) & 0x03;
            } else {
                return (_b >> (7 - _cc)) & 0x01;
            }
        };

        // Target = value under the click; replacement = current selected colour.
        var _target = _read_cell(_asset.buffer, _tile_base, _pixel_is_mc, _start_c, _start_r);

        if (_pixel_is_mc) {
            var _replace = chr_active_mc_colour & 0x03;
        } else if (_mc_mode == 2 && chr_active_ecm_target == "BG") {
            var _replace = 0; // ECM: BG swatch selected — fill clears to background
        } else {
            var _replace = 1; // HR (or ECM w/ FG selected) fill paints "on"
        }

        // Only flood if we'd actually change something.
        if (_target != _replace) {
            var _cols = _pixel_is_mc ? 4 : 8;

            // Visited grid + manual stack (8 rows x _cols).
            var _visited = array_create(8 * _cols, false);
            var _stack   = [];
            array_push(_stack, [_start_c, _start_r]);

            while (array_length(_stack) > 0) {
                var _node = array_pop(_stack);
                var _cc   = _node[0];
                var _rr   = _node[1];

                if (_cc < 0 || _cc >= _cols || _rr < 0 || _rr >= 8) {
                    continue;
                }
                var _vi = _rr * _cols + _cc;
                if (_visited[_vi]) {
                    continue;
                }
                if (_read_cell(_asset.buffer, _tile_base, _pixel_is_mc, _cc, _rr) != _target) {
                    continue;
                }

                _visited[_vi] = true;

                // Write replacement into this cell.
                var _byte_pos = _tile_base + _rr;
                var _cur      = buffer_peek(_asset.buffer, _byte_pos, buffer_u8);
                if (_pixel_is_mc) {
                    var _sh   = 6 - _cc * 2;
                    var _mask = ~(0x03 << _sh) & 0xFF;
                    buffer_poke(_asset.buffer, _byte_pos, buffer_u8, (_cur & _mask) | (_replace << _sh));
                } else {
                    var _fbit_mask = (1 << (7 - _cc));
                    if (_replace == 0) {
                        buffer_poke(_asset.buffer, _byte_pos, buffer_u8, _cur & ~_fbit_mask);
                    } else {
                        buffer_poke(_asset.buffer, _byte_pos, buffer_u8, _cur | _fbit_mask);
                    }
                }

                array_push(_stack, [_cc + 1, _rr]);
                array_push(_stack, [_cc - 1, _rr]);
                array_push(_stack, [_cc, _rr + 1]);
                array_push(_stack, [_cc, _rr - 1]);
            }

            scr_asset_chr_build_preview(_asset);
            global.undo_dirty    = true;
            _asset.meta.is_dirty = true;
        }

        _fill_consumed = true;
    }

    // ---- CLICK HANDLER — pixel edit ----
    if (!chr_fill_mode &&
        mouse_check_button_pressed(mb_left) &&
        point_in_rectangle(_mx, _my, _ox, _oy, _ox + _grid_w, _oy + _grid_h)) {
        scr_chr_undo_push(_asset);
    }
    if (!chr_fill_mode &&
        mouse_check_button(mb_left) &&
        point_in_rectangle(_mx, _my, _ox, _oy, _ox + _grid_w, _oy + _grid_h)) {

        if (_pixel_is_mc) {
            var _pair = floor((_mx - _ox) / (_scale * 2));
            var _row  = floor((_my - _oy) / _scale);
            _pair = clamp(_pair, 0, 3);
            _row  = clamp(_row, 0, 7);
            var _byte_pos = _tile_base + _row;
            var _cur  = buffer_peek(_asset.buffer, _byte_pos, buffer_u8);
            var _shift = 6 - _pair * 2;
            var _mask  = ~(0x03 << _shift) & 0xFF;
            var _new_byte = (_cur & _mask) | (chr_active_mc_colour << _shift);
            buffer_poke(_asset.buffer, _byte_pos, buffer_u8, _new_byte);
        } else {
            var _col = floor((_mx - _ox) / _scale);
            var _row = floor((_my - _oy) / _scale);
            _col = clamp(_col, 0, 7);
            _row = clamp(_row, 0, 7);
            var _byte_pos = _tile_base + _row;
            var _cur = buffer_peek(_asset.buffer, _byte_pos, buffer_u8);
            var _bit_mask = (1 << (7 - _col));
            // ECM: painting with a BG0-3 swatch selected clears the pixel
            // (acts as background/erase), matching MC's "paint with BG = erase"
            // behaviour. Plain HR, or ECM with FG selected, sets the pixel on.
            if (_mc_mode == 2 && chr_active_ecm_target == "BG") {
                buffer_poke(_asset.buffer, _byte_pos, buffer_u8, _cur & ~_bit_mask);
            } else {
                buffer_poke(_asset.buffer, _byte_pos, buffer_u8, _cur | _bit_mask);
            }
        }

        scr_asset_chr_build_preview(_asset);
        global.undo_dirty = true;
        _asset.meta.is_dirty = true;
    }

    // RMB — erase: MC clears bit-pair to BG, HR clears bit to 0
    if (mouse_check_button_pressed(mb_right) &&
        point_in_rectangle(_mx, _my, _ox, _oy, _ox + _grid_w, _oy + _grid_h)) {
        scr_chr_undo_push(_asset);
    }
    if (mouse_check_button(mb_right) &&
        point_in_rectangle(_mx, _my, _ox, _oy, _ox + _grid_w, _oy + _grid_h)) {
        if (_pixel_is_mc) {
            var _pair = floor((_mx - _ox) / (_scale * 2));
            var _row  = floor((_my - _oy) / _scale);
            _pair = clamp(_pair, 0, 3);
            _row  = clamp(_row, 0, 7);
            var _byte_pos = _tile_base + _row;
            var _cur  = buffer_peek(_asset.buffer, _byte_pos, buffer_u8);
            var _shift = 6 - _pair * 2;
            var _mask  = ~(0x03 << _shift) & 0xFF;
            buffer_poke(_asset.buffer, _byte_pos, buffer_u8, _cur & _mask);
        } else {
            var _col = floor((_mx - _ox) / _scale);
            var _row = floor((_my - _oy) / _scale);
            _col = clamp(_col, 0, 7);
            _row = clamp(_row, 0, 7);
            var _byte_pos = _tile_base + _row;
            var _cur = buffer_peek(_asset.buffer, _byte_pos, buffer_u8);
            var _bit_mask = (1 << (7 - _col));
            buffer_poke(_asset.buffer, _byte_pos, buffer_u8, _cur & ~_bit_mask);
        }
        scr_asset_chr_build_preview(_asset);
        global.undo_dirty = true;
        _asset.meta.is_dirty = true;
    }

    // ---- BUTTONS (to the right of the grid) ----
    var _btn_x   = _ox + _grid_w + 8;
    var _btn_w   = 80;
    var _btn_h   = 18;
    var _btn_y   = _oy;
    var _btn_gap = 4;

    // FLIP X
    var _fxhov = point_in_rectangle(_mx, _my, _btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h);
    draw_set_color(_fxhov ? make_color_rgb(80, 160, 200) : make_color_rgb(30, 60, 80));
    draw_rectangle(_btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_btn_x + _btn_w * 0.5, _btn_y + 3, "FLIP X");
    draw_set_halign(fa_left);
    if (_fxhov && mouse_check_button_pressed(mb_left)) {
        scr_chr_undo_push(_asset);
        for (var _r = 0; _r < 8; _r++) {
            var _b = buffer_peek(_asset.buffer, _tile_base + _r, buffer_u8);
            if (_pixel_is_mc) {
                var _p0 = (_b >> 6) & 0x03;
                var _p1 = (_b >> 4) & 0x03;
                var _p2 = (_b >> 2) & 0x03;
                var _p3 = (_b >> 0) & 0x03;
                _b = (_p3 << 6) | (_p2 << 4) | (_p1 << 2) | _p0;
            } else {
                var _nb = 0;
                for (var _bi = 0; _bi < 8; _bi++) {
                    if (_b & (1 << _bi)) _nb |= (1 << (7 - _bi));
                }
                _b = _nb;
            }
            buffer_poke(_asset.buffer, _tile_base + _r, buffer_u8, _b);
        }
        scr_asset_chr_build_preview(_asset);
        global.undo_dirty = true;
        _asset.meta.is_dirty = true;
    }
    _btn_y += _btn_h + _btn_gap;

    // FLIP Y
    var _fyhov = point_in_rectangle(_mx, _my, _btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h);
    draw_set_color(_fyhov ? make_color_rgb(80, 160, 200) : make_color_rgb(30, 60, 80));
    draw_rectangle(_btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_btn_x + _btn_w * 0.5, _btn_y + 3, "FLIP Y");
    draw_set_halign(fa_left);
    if (_fyhov && mouse_check_button_pressed(mb_left)) {
        scr_chr_undo_push(_asset);
        for (var _r = 0; _r < 4; _r++) {
            var _a = buffer_peek(_asset.buffer, _tile_base + _r,     buffer_u8);
            var _b = buffer_peek(_asset.buffer, _tile_base + 7 - _r, buffer_u8);
            buffer_poke(_asset.buffer, _tile_base + _r,     buffer_u8, _b);
            buffer_poke(_asset.buffer, _tile_base + 7 - _r, buffer_u8, _a);
        }
        scr_asset_chr_build_preview(_asset);
        global.undo_dirty = true;
        _asset.meta.is_dirty = true;
    }
    _btn_y += _btn_h + _btn_gap;

    // CLEAR
    var _clhov = point_in_rectangle(_mx, _my, _btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h);
    draw_set_color(_clhov ? make_color_rgb(180, 60, 60) : make_color_rgb(80, 25, 25));
    draw_rectangle(_btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_btn_x + _btn_w * 0.5, _btn_y + 3, "CLEAR");
    draw_set_halign(fa_left);
    if (_clhov && mouse_check_button_pressed(mb_left)) {
        scr_chr_undo_push(_asset);
        for (var _r = 0; _r < 8; _r++) {
            buffer_poke(_asset.buffer, _tile_base + _r, buffer_u8, 0);
        }
        scr_asset_chr_build_preview(_asset);
        global.undo_dirty = true;
        _asset.meta.is_dirty = true;
    }
    _btn_y += _btn_h + _btn_gap;

    // FILL (flood-fill toggle) — highlights green when active
    var _flhov = point_in_rectangle(_mx, _my, _btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h);
    if (chr_fill_mode) {
        draw_set_color(make_color_rgb(60, 200, 60));
    } else {
        draw_set_color(_flhov ? make_color_rgb(40, 120, 40) : make_color_rgb(25, 80, 25));
    }
    draw_rectangle(_btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h, false);
    draw_set_color(chr_fill_mode ? c_black : c_white);
    draw_set_halign(fa_center);
    draw_text(_btn_x + _btn_w * 0.5, _btn_y + 3, chr_fill_mode ? "FILL: ON" : "FILL");
    draw_set_halign(fa_left);
    if (_flhov && mouse_check_button_pressed(mb_left)) {
        chr_fill_mode = chr_fill_mode ? false : true;
    }
    _btn_y += _btn_h + _btn_gap * 2;

    // ---- COLOUR SWATCHES ----
    var _sw_labels, _sw_keys;
    if (_mc_mode == 1) {
        _sw_labels = ["BG", "C1", "C2", "FG"];
        _sw_keys   = ["mc_bg", "mc_col1", "mc_col2", "mc_fg"];
    } else if (_mc_mode == 2) {
        // FG is suppressed when called from META_TILESET/MAP_DATA — those
        // scenes already have their own COLOUR strip driving _m.active_colour
        // as the paint FG, so this row would be redundant (and, since those
        // callers no longer temp-swap mc_fg into this asset, it wouldn't
        // reflect anything meaningful anyway).
        if (_show_fg_swatch) {
            _sw_labels = ["BG0", "BG1", "BG2", "BG3", "FG"];
            _sw_keys   = ["mc_bg", "ecm_bg1", "ecm_bg2", "ecm_bg3", "mc_fg"];
        } else {
            _sw_labels = ["BG0", "BG1", "BG2", "BG3"];
            _sw_keys   = ["mc_bg", "ecm_bg1", "ecm_bg2", "ecm_bg3"];
        }
    } else {
        _sw_labels = ["BG", "FG"];
        _sw_keys   = ["mc_bg", "mc_fg"];
    }
    var _sw_sz = 18;
    draw_set_font(fnt_c64_tiny);
    for (var _swi = 0; _swi < array_length(_sw_labels); _swi++) {
        var _sw_col_idx = variable_struct_exists(_asset.meta, _sw_keys[_swi])
                        ? variable_struct_get(_asset.meta, _sw_keys[_swi]) : 0;
        var _sw_selected = (_mc_mode == 1 && chr_active_mc_colour == _swi)
                         || (_mc_mode == 2 && _swi < 4 && chr_active_ecm_bg == _swi);
        var _sw_x1 = _btn_x + 32;
        var _sw_y1 = _btn_y + _swi * (_sw_sz + 3);
        draw_set_color(_sw_selected ? c_yellow : make_color_rgb(100, 100, 140));
        draw_text(_btn_x, _sw_y1 + 3, _sw_labels[_swi] + ":");
        draw_set_color(scr_c64_pepto_colour(_sw_col_idx));
        draw_rectangle(_sw_x1, _sw_y1, _sw_x1 + _sw_sz, _sw_y1 + _sw_sz, false);
        draw_set_color(_sw_selected ? c_yellow : c_white);
        draw_rectangle(_sw_x1, _sw_y1, _sw_x1 + _sw_sz, _sw_y1 + _sw_sz, true);
        if (_sw_selected) {
            draw_set_color(c_yellow);
            draw_rectangle(_sw_x1 - 2, _sw_y1 - 2, _sw_x1 + _sw_sz + 2, _sw_y1 + _sw_sz + 2, true);
        }
        if (mouse_check_button_pressed(mb_left) &&
            point_in_rectangle(_mx, _my, _sw_x1, _sw_y1, _sw_x1 + _sw_sz, _sw_y1 + _sw_sz)) {
            if (_mc_mode == 2) {
                if (_swi < 4) {
                    chr_active_ecm_bg     = _swi;
                    chr_active_ecm_target = "BG";
                } else {
                    chr_active_ecm_target = "FG";
                }
            } else if (_mc_mode == 1) {
                chr_active_mc_colour = _swi;
            }
        }
    }
}