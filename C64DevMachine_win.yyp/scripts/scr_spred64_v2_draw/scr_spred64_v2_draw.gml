/// @function scr_spred64_v2_draw(_asset, _vx1, _vy1, _vx2, _vy2, _mx, _my)
/// @desc Renders and handles input for the SPRED64 V2 built-in editor.
///       Layout (within the asset viewer panel):
///         LEFT       : 64-sprite picker grid (4 cols x 16 rows, 2x zoom)
///         TOP-RIGHT  : pixel editor + palette swatches + HR/MC toggle
///         BOTTOM-RIGHT : reserved area for compositor/animator (phase 2+)
function scr_spred64_v2_draw(_asset, _vx1, _vy1, _vx2, _vy2, _mx, _my) {

    with (obj_asset_manager) {

        // Safety — should not be called if V2 isn't active on this asset,
        // but guard anyway.
        if (!spred64_v2.active) exit;
        if (spred64_v2.asset_index < 0) exit;

        var _v2 = spred64_v2;

        // Decrement paint cooldown. Used to swallow stray clicks that
        // opened V2 from outside (e.g. picker-click in the asset viewer).
        if (_v2.paint_cooldown > 0) {
            _v2.paint_cooldown--;
        }

        // ----- KEYBOARD SHORTCUTS -----
        // A / D       = previous / next frame (manual scrub)
        // CTRL+C / V  = copy / paste selected slots or current sprite
        // All suppressed while any text-input mode is active so they don't
        // collide with typing in an asset name, address, etc.
       if (!global.is_any_text_active) {
            var _ctrl_held = keyboard_check(vk_control);
            // Debug — log every C / V key press to find out where they get swallowed
            if (keyboard_check_pressed(ord("C"))) {
                show_debug_message("V2 SHORTCUT: C pressed, ctrl_held=" + string(_ctrl_held)
                    + " text_active=" + string(global.is_any_text_active));
            }
            if (keyboard_check_pressed(ord("V"))) {
                show_debug_message("V2 SHORTCUT: V pressed, ctrl_held=" + string(_ctrl_held)
                    + " text_active=" + string(global.is_any_text_active));
            }
            if (_ctrl_held && keyboard_check_pressed(ord("C"))) {
                scr_spred64_v2_batch_copy(_asset);
                keyboard_clear(ord("C"));
            }
            else if (_ctrl_held && keyboard_check_pressed(ord("V"))) {
                scr_spred64_v2_batch_paste(_asset);
                keyboard_clear(ord("V"));
            }
            else if (!_ctrl_held) {
                if (keyboard_check_pressed(ord("A"))) {
                    scr_spred64_v2_anim_frame_goto(-1);
                }
                if (keyboard_check_pressed(ord("D"))) {
                    scr_spred64_v2_anim_frame_goto(1);
                }
            }
        }

        // -------------------------------------------------------
        // LAYOUT RECTANGLES
        // -------------------------------------------------------
        // Left sprite picker: 8 columns x 8 rows, cell = 96x84 (4x zoom + border)
        var _pick_cell_w = 96;
        var _pick_cell_h = 84;
        var _pick_cols   = 8;
        var _pick_rows   = 8;
        var _pick_gap    = 4;  // gap between cells (set 0 for flush)
        var _pick_w      = _pick_cols * (_pick_cell_w + _pick_gap) + 4;
        var _pick_h      = _pick_rows * (_pick_cell_h + _pick_gap) + 4;

        var _pick_x1 = _vx1 + 10;
        var _pick_y1 = _vy1 + 10;
        var _pick_x2 = _pick_x1 + _pick_w;
        var _pick_y2 = _pick_y1 + _pick_h;

        // Right side: split horizontally into top (pixel editor) and bottom (reserved)
        var _right_x1 = _pick_x2 + 16;
        var _right_x2 = _vx2 - 10;
        var _right_w  = _right_x2 - _right_x1;

        // Editor takes ~38% of the height; compositor sits lower down, leaving
        // a deliberate empty band between them for the future animation panel.
        // The compositor's top edge is offset from _split_y in the _rsv_y1 calc
        // below, so changing the offset there controls the band size.
        var _split_y  = _vy1 + 10 + floor((_vy2 - _vy1 - 20) * 0.38);

        var _ed_x1 = _right_x1;
        var _ed_y1 = _vy1 + 10;
        var _ed_x2 = _right_x2;
        var _ed_y2 = _split_y - 4;

        // Reserve a compact band between the editor and compositor for the
        // animation controls panel. With tight button heights the panel
        // fits comfortably in ~52px.
        var _anim_band_h = 54;
        var _rsv_x1 = _right_x1;
        var _rsv_y1 = _split_y + 4 + _anim_band_h;
        var _rsv_x2 = _right_x2;
        var _rsv_y2 = _vy2 - 10;
        // -------------------------------------------------------
        // BACKDROP PANELS
        // -------------------------------------------------------
        draw_set_color(make_color_rgb(12, 12, 20));
        draw_rectangle(_pick_x1, _pick_y1, _pick_x2, _pick_y2, false);
        draw_set_color(make_color_rgb(60, 40, 20));
        draw_rectangle(_pick_x1, _pick_y1, _pick_x2, _pick_y2, true);

        draw_set_color(make_color_rgb(12, 12, 20));
        draw_rectangle(_ed_x1, _ed_y1, _ed_x2, _ed_y2, false);
        draw_set_color(make_color_rgb(60, 40, 20));
        draw_rectangle(_ed_x1, _ed_y1, _ed_x2, _ed_y2, true);

        draw_set_color(make_color_rgb(10, 10, 16));
        draw_rectangle(_rsv_x1, _rsv_y1, _rsv_x2, _rsv_y2, false);
        draw_set_color(make_color_rgb(40, 30, 15));
        draw_rectangle(_rsv_x1, _rsv_y1, _rsv_x2, _rsv_y2, true);

        // -------------------------------------------------------
        // SPRITE PICKER GRID (LEFT)
        // -------------------------------------------------------
        // Cache existing sprite previews so picker shows live thumbnails.
        // We don't rebuild them here — they're updated on commit (close).
        // For the active slot, we update its preview ourselves so the
        // user sees their paint reflected immediately.

        // Hover detection — only over used slots. The "+ add" cell sits at
        // index used_count and is hover-tracked separately below.
        var _pick_used     = clamp(_v2.used_count, 1, 64);
        var _pick_add_slot = (_pick_used < 64) ? _pick_used : -1; // -1 = bank full
        var _pick_hover    = -1;
        for (var _ph_slot = 0; _ph_slot < _pick_used; _ph_slot++) {
            var _ph_col = _ph_slot mod _pick_cols;
            var _ph_row = _ph_slot div _pick_cols;
            var _ph_x   = _pick_x1 + 2 + _ph_col * (_pick_cell_w + _pick_gap);
            var _ph_y   = _pick_y1 + 2 + _ph_row * (_pick_cell_h + _pick_gap);
            if (point_in_rectangle(_mx, _my, _ph_x, _ph_y,
                                   _ph_x + _pick_cell_w,
                                   _ph_y + _pick_cell_h)) {
                _pick_hover = _ph_slot;
                break;
            }
        }
        // Hover for the + add cell
        var _pick_add_hover = false;
        if (_pick_add_slot >= 0) {
            var _pa_col = _pick_add_slot mod _pick_cols;
            var _pa_row = _pick_add_slot div _pick_cols;
            var _pa_x   = _pick_x1 + 2 + _pa_col * (_pick_cell_w + _pick_gap);
            var _pa_y   = _pick_y1 + 2 + _pa_row * (_pick_cell_h + _pick_gap);
            _pick_add_hover = point_in_rectangle(_mx, _my, _pa_x, _pa_y,
                _pa_x + _pick_cell_w, _pa_y + _pick_cell_h);
        }

        // Draw each slot cell
        for (var _slot = 0; _slot < _pick_used; _slot++) {

            var _col = _slot mod _pick_cols;
            var _row = _slot div _pick_cols;
            var _cx  = _pick_x1 + 2 + _col * (_pick_cell_w + _pick_gap);
            var _cy_p = _pick_y1 + 2 + _row * (_pick_cell_h + _pick_gap);

            var _is_sel = (_slot == _v2.selected_slot);
            var _is_hov = (_slot == _pick_hover);

            // Cell background
            draw_set_color(_is_sel
                ? make_color_rgb(80, 60, 20)
                : (_is_hov ? make_color_rgb(40, 40, 60) : make_color_rgb(20, 20, 30)));
            draw_rectangle(_cx, _cy_p, _cx + _pick_cell_w, _cy_p + _pick_cell_h, false);

            // Paint the C64 BG colour behind the sprite. The sprite itself
            // has transparent BG pixels (so it composites correctly in the
            // compositor area), so without this fill the picker cell's
            // brown selection/hover background would show through.
            // The cached sprite is 48x42 drawn at 2x scale = 96x84 footprint,
            // matching one picker cell exactly.
            if (variable_struct_exists(_asset.meta, "spr_sprites")
            &&  _asset.meta.spr_sprites[_slot] != -1
            &&  sprite_exists(_asset.meta.spr_sprites[_slot])) {
                draw_set_color(scr_c64_pepto_colour(_v2.bg_col));
                draw_rectangle(_cx + 1, _cy_p + 1, _cx + 1 + 96, _cy_p + 1 + 84, false);
                gpu_set_tex_filter(false);
                draw_sprite_ext(_asset.meta.spr_sprites[_slot], 0,
                                _cx + 1, _cy_p + 1, 2, 2, 0, c_white, 1);
								gpu_set_tex_filter(true);
            }

            // Slot number — only show if slot has no painted pixels
            var _slot_empty = true;
            var _empty_base = _slot * 504;
            for (var _eb = 0; _eb < 504; _eb++) {
                if (_v2.bits[_empty_base + _eb] == 1) {
                    _slot_empty = false;
                    break;
                }
            }
            if (_slot_empty) {
                draw_set_font(fnt_c64_tiny);
                draw_set_color(make_color_rgb(160, 160, 80));
                draw_text(_cx + 2, _cy_p + _pick_cell_h - 14, string(_slot));
            }

            // ALT-click-to-remove hint — only on the LAST slot, only when
            // it's blank and there's more than one slot. Peels back from
            // the end; clear a sprite first, then ALT-click to drop it.
            if (_slot == _pick_used - 1 && _pick_used > 1 && _slot_empty && _is_hov) {
                draw_set_font(fnt_c64_tiny);
                draw_set_color(make_color_rgb(255, 120, 120));
                draw_set_halign(fa_center);
                draw_set_valign(fa_middle);
                draw_text(_cx + _pick_cell_w * 0.5, _cy_p + 14, "EMPTY");
                draw_text(_cx + _pick_cell_w * 0.5, _cy_p + _pick_cell_h * 0.5, "ALT-CLICK");
                draw_text(_cx + _pick_cell_w * 0.5, _cy_p + _pick_cell_h * 0.5 + 12, "TO REMOVE");
                draw_set_halign(fa_left);
                draw_set_valign(fa_top);
            }

            

            // Selection / hover outline
            if (_is_sel) {
                draw_set_color(make_color_rgb(255, 220, 120));
                draw_rectangle(_cx, _cy_p,
                               _cx + _pick_cell_w +4, _cy_p + _pick_cell_h +4, true);
            } else if (_is_hov) {
                draw_set_color(c_white);
                draw_rectangle(_cx, _cy_p,
                               _cx + _pick_cell_w +4, _cy_p + _pick_cell_h +4, true);
            }

            // Batch-select bracket — cyan, doubled so it reads clearly over
            // the yellow (primary) and white (hover) outlines. Drawn last so
            // a slot that's both primary AND multi-selected still shows the
            // cyan membership marker on top.
            if (_v2.multi_select[_slot]) {
                draw_set_color(make_color_rgb(80, 220, 255));
                draw_rectangle(_cx + 1, _cy_p + 1,
                               _cx + _pick_cell_w + 3, _cy_p + _pick_cell_h + 3, true);
                draw_rectangle(_cx + 2, _cy_p + 2,
                               _cx + _pick_cell_w + 2, _cy_p + _pick_cell_h + 2, true);
            }
        }

        // ----- "+" ADD-SLOT CELL -----
        // Sits immediately after the last used slot. Click adds one blank
        // sprite (up to the 64 cap) via scr_spred64_v2_add_slot.
        if (_pick_add_slot >= 0) {
            var _add_col = _pick_add_slot mod _pick_cols;
            var _add_row = _pick_add_slot div _pick_cols;
            var _add_cx  = _pick_x1 + 2 + _add_col * (_pick_cell_w + _pick_gap);
            var _add_cy  = _pick_y1 + 2 + _add_row * (_pick_cell_h + _pick_gap);

            draw_set_color(_pick_add_hover
                ? make_color_rgb(40, 90, 50)
                : make_color_rgb(24, 40, 28));
            draw_rectangle(_add_cx, _add_cy,
                           _add_cx + _pick_cell_w, _add_cy + _pick_cell_h, false);

            draw_set_color(_pick_add_hover
                ? make_color_rgb(120, 255, 120)
                : make_color_rgb(80, 160, 90));
            draw_rectangle(_add_cx, _add_cy,
                           _add_cx + _pick_cell_w, _add_cy + _pick_cell_h, true);

            draw_set_font(fnt_c64_code);
            draw_set_color(_pick_add_hover ? c_white : make_color_rgb(120, 200, 130));
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text(_add_cx + _pick_cell_w * 0.5,
                      _add_cy + _pick_cell_h * 0.5, "+");
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);

            if (_pick_add_hover && mouse_check_button_pressed(mb_left)
            && !global.ui_click_consumed && !global.any_picker_open) {
                scr_spred64_v2_add_slot();
                global.ui_click_consumed = true;
            }
        }

        // Click on picker = select slot, OR ALT/OPT-click the LAST slot to
        // remove it (trailing-only, blank-only — the remove script enforces
        // both guards). ALT-click is checked first so it doesn't fall through
        // to a normal select.
        if (_pick_hover >= 0
        && mouse_check_button_pressed(mb_left)
        && (keyboard_check(vk_alt) || keyboard_check(vk_lalt) || keyboard_check(vk_ralt))
        && _pick_hover == _pick_used - 1
        && !global.ui_click_consumed
        && !global.any_picker_open) {
            scr_spred64_v2_remove_last_slot();
            global.ui_click_consumed = true;
        }
        // CTRL+click — toggle this slot's membership in the batch-edit
        // selection set. Does NOT move selected_slot or rebuild the edit
        // surface: the pixel canvas stays on the primary slot while the
        // user builds up a set to mode/colour all at once. Checked before
        // the normal-select branch so it doesn't fall through to a select.
        else if (_pick_hover >= 0
        && mouse_check_button_pressed(mb_left)
        && keyboard_check(vk_control)
        && !global.ui_click_consumed
        && !global.any_picker_open) {
            _v2.multi_select[_pick_hover] = !_v2.multi_select[_pick_hover];
            global.ui_click_consumed = true;
        }
        else if (_pick_hover >= 0
        && mouse_check_button_pressed(mb_left)
        && !global.ui_click_consumed
        && !global.any_picker_open) {
            // Plain click — single-select. Clear any batch selection so the
            // set doesn't silently linger after the user moves on.
            for (var _ms_clr = 0; _ms_clr < 64; _ms_clr++) {
                _v2.multi_select[_ms_clr] = false;
            }
            if (_v2.selected_slot != _pick_hover) {
                _v2.selected_slot = _pick_hover;
                // Force rebuild of edit surface on next draw
                if (surface_exists(_v2.edit_surface)) {
                    surface_free(_v2.edit_surface);
                }
                _v2.edit_surface = -1;
                // Disarm tools — changing slot mid-arm would surprise.
                _v2.fill_armed    = false;
                _v2.line_armed    = false;
                _v2.line_anchor_x = -1;
                _v2.line_anchor_y = -1;
            }
        }

        // -------------------------------------------------------
        // PIXEL EDITOR (TOP-RIGHT)
        // -------------------------------------------------------
        // The canvas needs to be inside _ed_x1.._ed_x2 / _ed_y1.._ed_y2.
        // Above the canvas we put: title bar, palette swatches, HR/MC toggle.
        // Layout from top of _ed_y1 down:
        //   row 1 (y +6 ..+22)   : title + slot info
        //   row 2 (y +28..+56)   : palette swatches BG / MC1 / MC2 / UC
        //   row 3 (y +60..+82)   : HR/MC toggle + active colour selector
        //   row 4 (y +88..rest)  : pixel canvas (24x21 cells)

// Header text
        draw_set_font(fnt_c64_code);
        draw_set_color(make_color_rgb(255, 200, 120));
        draw_text(_ed_x1 + 8, _ed_y1 + 6,
            "SLOT " + string(_v2.selected_slot)
            + "   MODE: " + ((_v2.sprite_modes[_v2.selected_slot] == 1) ? "MULTICOLOUR" : "HIRES"));

        // ----- HR/MC TOGGLE ROW (on the same line as the title, to the right) -----
        // Sits on the title row to save vertical space — the canvas moves up.
        var _toolrow_y = _ed_y1 + 4;

        // ----- HR/MC TOGGLE -----
        // X-shifted past the SLOT/MODE title text since it shares the title row.
        var _hmx1 = _ed_x1 + 374;
        var _hmx2 = _hmx1 + 100;
        var _hmy1 = _toolrow_y;
        var _hmy2 = _hmy1 + 20;
        var _hm_is_mc = (_v2.sprite_modes[_v2.selected_slot] == 1);
        var _hm_hov   = point_in_rectangle(_mx, _my, _hmx1, _hmy1, _hmx2, _hmy2);
        draw_set_color(_hm_is_mc
            ? (_hm_hov ? make_color_rgb(220, 120, 40) : make_color_rgb(160, 80, 20))
            : (_hm_hov ? make_color_rgb(80, 140, 200) : make_color_rgb(40, 80, 130)));
        draw_rectangle(_hmx1, _hmy1, _hmx2, _hmy2, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_hmx1 + 50, _hmy1 + 2, _hm_is_mc ? "MC MODE" : "HR MODE");
        draw_set_halign(fa_left);
        if (_hm_hov && mouse_check_button_pressed(mb_left)
        && !global.ui_click_consumed && !global.any_picker_open) {
            // New mode = the opposite of the PRIMARY slot's current mode, so
            // the button's label reflects what the click will apply.
            var _hm_new_mode = _hm_is_mc ? 0 : 1;
            _v2.sprite_modes[_v2.selected_slot] = _hm_new_mode;

            // Fan out to the batch selection, if any. Bound to used_count so
            // a stale entry on a removed slot can't refresh out of range.
            var _hm_used = clamp(_v2.used_count, 1, 64);
            for (var _hm_i = 0; _hm_i < _hm_used; _hm_i++) {
                if (_v2.multi_select[_hm_i] && _hm_i != _v2.selected_slot) {
                    _v2.sprite_modes[_hm_i] = _hm_new_mode;
                    scr_spred64_v2_refresh_slot_sprite(_asset, _hm_i);
                }
            }

            _v2.dirty = true;
            if (surface_exists(_v2.edit_surface)) {
                surface_free(_v2.edit_surface);
            }
            _v2.edit_surface = -1;
            scr_spred64_v2_refresh_slot_sprite(_asset, _v2.selected_slot);
        }

        // ----- COMP PREVIEW TOGGLE -----
        // Renders the OTHER layers of the active compositor cell behind the
        // pixel editor canvas so the user can paint in context. The active
        // layer's pixels still draw on top and remain the only editable
        // surface. The button is on the title row, right of HR/MC.
        var _cpx1 = _hmx2 -238;
        var _cpx2 = _cpx1 + 100;
        var _cpy1 = _hmy1;
        var _cpy2 = _hmy2;
        var _cp_on  = _v2.comp_preview;
        var _cp_hov = point_in_rectangle(_mx, _my, _cpx1, _cpy1, _cpx2, _cpy2);
        if (_cp_on) {
            if (_cp_hov) {
                draw_set_color(make_color_rgb(60, 140, 60));
            } else {
                draw_set_color(make_color_rgb(40, 100, 40));
            }
        } else {
            if (_cp_hov) {
                draw_set_color(make_color_rgb(70, 50, 25));
            } else {
                draw_set_color(make_color_rgb(40, 30, 15));
            }
        }
        draw_rectangle(_cpx1, _cpy1, _cpx2, _cpy2, false);
        if (_cp_on) {
            draw_set_color(make_color_rgb(120, 255, 120));
            draw_rectangle(_cpx1,     _cpy1,     _cpx2,     _cpy2,     true);
            draw_rectangle(_cpx1 + 1, _cpy1 + 1, _cpx2 - 1, _cpy2 - 1, true);
        } else {
            draw_set_color(make_color_rgb(200, 140, 60));
            draw_rectangle(_cpx1, _cpy1, _cpx2, _cpy2, true);
        }
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        if (_cp_on) {
            draw_text(_cpx1 + 50, _cpy1 + 2, "COMP ON");
        } else {
            draw_text(_cpx1 + 50, _cpy1 + 2, "COMP OFF");
        }
        draw_set_halign(fa_left);
        if (_cp_hov && mouse_check_button_pressed(mb_left)
        && !global.ui_click_consumed && !global.any_picker_open) {
            _v2.comp_preview = !_v2.comp_preview;
            // Force edit surface rebuild so the next draw picks up the
            // change in clear behaviour (transparent vs solid BG fill).
            if (surface_exists(_v2.edit_surface)) {
                surface_free(_v2.edit_surface);
            }
            _v2.edit_surface = -1;
        }

        // -------------------------------------------------------
        // PIXEL CANVAS
        // -------------------------------------------------------
        // Reserve strips on both sides of the canvas:
        //   LEFT  — FX button column (FLIPX / FLIPY / ROT90), affect raw bits
        //   RIGHT — palette strip (BG / MC1 \/ MC2 / UC) 4 vertical columns
        var _fx_strip_w  = 60;         // 1 column, fits 3 stacked buttons
        var _pal_strip_w = 132;        // 4 cols * 30 + 3 gaps = 132
        var _canvas_top  = _hmy2 + 12;
        var _canvas_bot  = _ed_y2 - 8;
        var _canvas_h_av = _canvas_bot - _canvas_top;
        var _canvas_w_av = _ed_x2 - _ed_x1 - 16 - _pal_strip_w - 8 - _fx_strip_w - 8;

        // C64 sprite is 24x21. We want square cells.
        // Pick max integer cell size that fits both dimensions.
        var _cell_size = min(floor(_canvas_w_av / 24), floor(_canvas_h_av / 21));
        if (_cell_size < 4) _cell_size = 4;
        if (_cell_size > 24) _cell_size = 24;

        var _canvas_w  = 24 * _cell_size;
        var _canvas_h  = 21 * _cell_size;
        // Canvas sits between FX strip (left) and palette strip (right).
        // Centre within the area available between those two strips.
        var _canvas_x  = _ed_x1 + 8 + _fx_strip_w + 8
                       + floor((_canvas_w_av - _canvas_w) * 0.5);
        var _canvas_y  = _canvas_top;

        // Build / rebuild edit surface if missing or if canvas size changed
        if (!surface_exists(_v2.edit_surface)) {
            _v2.edit_surface = surface_create(_canvas_w, _canvas_h);
            _v2._edit_dirty = true;
        } else if (surface_get_width(_v2.edit_surface) != _canvas_w
               ||  surface_get_height(_v2.edit_surface) != _canvas_h) {
            surface_free(_v2.edit_surface);
            _v2.edit_surface = surface_create(_canvas_w, _canvas_h);
            _v2._edit_dirty = true;
        }

        // Rebuild edit surface from bits
        // (We do this every frame for now — cheap at 24x21 cells.
        //  If it costs too much later we can add a dirty flag.)
        var _slot     = _v2.selected_slot;
        var _bit_base = _slot * 504;
        var _is_mc    = (_v2.sprite_modes[_slot] == 1);
        var _uc_pen   = _v2.sprite_uc[_slot];

// ----- VIEW MODE : COMP ON vs COMP OFF -----
        // COMP OFF (default) — the canvas shows the currently selected
        //                      slot's bits, rendered into the edit surface
        //                      by the HR/MC block below. This is the
        //                      direct-edit view.
        // COMP ON            — the canvas shows what the COMPOSITOR sees
        //                      at the active (row, col), composited from
        //                      whatever layer cells are placed there. The
        //                      selected slot is NOT drawn unless it
        //                      happens to be placed at one of those
        //                      layers. The user is still painting the
        //                      selected slot's bits (cached sprite
        //                      refreshes per paint), so any placed cell
        //                      using that slot will update live.
        // The decision flag _comp_view_active controls whether the edit
        // surface rebuild (below) actually renders the selected slot, or
        // skips it in favour of the composite render done here.
        var _comp_view_active = false;
        if (_v2.comp_preview) {
            var _cu_comp  = _v2.compositor;
            var _cu_frame = _cu_comp.frames[_cu_comp.active_frame];
            // COMP view anchors off the (row, col) the user last selected
            // in the grid (comp_anchor_*), NOT off active_cell. This way
            // switching to an empty layer keeps the composite view live —
            // the user sees the rest of the layers at this position even
            // when the layer they're editing doesn't have a cell yet.
            // Fall back to active_cell's position if no anchor was ever
            // set (e.g. user opened V2 and immediately enabled COMP).
            var _cu_row = _v2.comp_anchor_row;
            var _cu_col = _v2.comp_anchor_col;
            if (_cu_row < 0 || _cu_col < 0) {
                if (_cu_comp.active_cell >= 0
                &&  _cu_comp.active_cell < array_length(_cu_frame.cells)) {
                    var _cu_fb_active = _cu_frame.cells[_cu_comp.active_cell];
                    _cu_row = _cu_fb_active.row;
                    _cu_col = _cu_fb_active.col;
                }
            }
            if (_cu_row >= 0 && _cu_col >= 0) {
                _comp_view_active = true;
                // 1) Fill the canvas area with the C64 BG colour so
                //    transparent sprite pixels reveal BG — same as the
                //    compositor grid renders.
                draw_set_color(scr_c64_pepto_colour(_v2.bg_col));
                draw_rectangle(_canvas_x, _canvas_y,
                               _canvas_x + _canvas_w,
                               _canvas_y + _canvas_h, false);
                // 2) Walk every layer at this (row, col) in draw order
                //    (layer 0 base first, up to layer 7). Each cell is
                //    rectangle-clipped against the canvas bounds via
                //    draw_sprite_part_ext, so expand X/Y and offsets
                //    can't bleed over neighbouring editor UI. Doing the
                //    clip in the data avoids GPU scissor — scissor in
                //    Draw GUI operates on back-buffer pixels rather than
                //    GUI pixels, which makes it the wrong tool here.
                gpu_set_tex_filter(false);
                for (var _cu_ly = 0; _cu_ly < 8; _cu_ly++) {
                    for (var _cu_ci = 0; _cu_ci < array_length(_cu_frame.cells); _cu_ci++) {
                        var _cu_cd = _cu_frame.cells[_cu_ci];
                        if (_cu_cd.layer != _cu_ly) { continue; }
                        // Determine whether this cell's footprint touches
                        // the anchor (_cu_row, _cu_col). Always include the
                        // anchor cell itself. Additionally, include
                        // neighbours whose expand mode causes their sprite
                        // to overflow into the anchor:
                        //   left neighbour  (col - 1) with expand "x"    or "both"
                        //   above neighbour (row - 1) with expand "y"    or "both"
                        //   above-left      (-1,-1)   with expand "both"
                        // dr / dc are the offset from the cell's own
                        // (row, col) to the anchor; we use them later to
                        // shift the draw origin so the cell renders into
                        // the correct screen position relative to the
                        // canvas (top-left == anchor).
                        var _cu_dr = _cu_row - _cu_cd.row;
                        var _cu_dc = _cu_col - _cu_cd.col;
                        var _cu_include = false;
                        if (_cu_dr == 0 && _cu_dc == 0) {
                            _cu_include = true;
                        }
                        else if (_cu_dr == 0 && _cu_dc == 1
                              && (_cu_cd.expand == "x" || _cu_cd.expand == "both")) {
                            _cu_include = true;
                        }
                        else if (_cu_dr == 1 && _cu_dc == 0
                              && (_cu_cd.expand == "y" || _cu_cd.expand == "both")) {
                            _cu_include = true;
                        }
                        else if (_cu_dr == 1 && _cu_dc == 1 && _cu_cd.expand == "both") {
                            _cu_include = true;
                        }
                        if (!_cu_include) { continue; }
                        if (!variable_struct_exists(_asset.meta, "spr_sprites")) {
                            continue;
                        }
                        if (_cu_cd.slot < 0
                        ||  _cu_cd.slot >= array_length(_asset.meta.spr_sprites)) { continue; }
                        var _cu_spr = _asset.meta.spr_sprites[_cu_cd.slot];
                        if (_cu_spr == -1 || !sprite_exists(_cu_spr)) { continue; }
                        // Scale: source sprite is 48x42 = 2x C64 native.
                        // Canvas wants 1 C64 pixel = _cell_size screen px,
                        // so source pixel = _cell_size / 2. Expand axes
                        // double that. Use float scale; tex filter is off.
                        var _cu_base = _cell_size * 0.5;
                        var _cu_sx = _cu_base;
                        var _cu_sy = _cu_base;
                        if (_cu_cd.expand == "x" || _cu_cd.expand == "both") {
                            _cu_sx = _cu_base * 2;
                        }
                        if (_cu_cd.expand == "y" || _cu_cd.expand == "both") {
                            _cu_sy = _cu_base * 2;
                        }
                        // xo/yo are in C64 pixels — one unit = _cell_size px.
                        // For neighbour cells (left / above / above-left),
                        // we additionally shift the origin so the cell
                        // renders at its true position relative to the
                        // anchor. One grid step = 24 C64 px horizontally,
                        // 21 vertically. The expanded portion of the
                        // sprite that overflows into the anchor cell is
                        // then naturally clipped by the canvas-rect
                        // intersection below.
                        var _cu_dx = _canvas_x + _cu_cd.xo * _cell_size
                                   - _cu_dc * 24 * _cell_size;
                        var _cu_dy = _canvas_y + _cu_cd.yo * _cell_size
                                   - _cu_dr * 21 * _cell_size;

                        // Full unclipped sprite footprint in screen pixels
                        var _cu_full_w = 48 * _cu_sx;
                        var _cu_full_h = 42 * _cu_sy;
                        // Intersect the sprite's screen rect with the
                        // canvas rect — gives us the visible draw region
                        var _cu_clip_x1 = max(_cu_dx,             _canvas_x);
                        var _cu_clip_y1 = max(_cu_dy,             _canvas_y);
                        var _cu_clip_x2 = min(_cu_dx + _cu_full_w, _canvas_x + _canvas_w);
                        var _cu_clip_y2 = min(_cu_dy + _cu_full_h, _canvas_y + _canvas_h);
                        // Fully off-screen — skip
                        if (_cu_clip_x2 <= _cu_clip_x1) { continue; }
                        if (_cu_clip_y2 <= _cu_clip_y1) { continue; }
                        // Convert the visible screen rect back into
                        // source-sprite-pixel space. Floor on the left
                        // and top so we don't accidentally skip a partial
                        // source pixel, ceil on the right and bottom so
                        // we cover the whole visible region.
                        var _cu_src_x = floor((_cu_clip_x1 - _cu_dx) / _cu_sx);
                        var _cu_src_y = floor((_cu_clip_y1 - _cu_dy) / _cu_sy);
                        var _cu_src_w = ceil((_cu_clip_x2 - _cu_clip_x1) / _cu_sx);
                        var _cu_src_h = ceil((_cu_clip_y2 - _cu_clip_y1) / _cu_sy);
                        // Clamp source rect to the 48x42 sprite bounds
                        if (_cu_src_x < 0)              { _cu_src_w += _cu_src_x; _cu_src_x = 0; }
                        if (_cu_src_y < 0)              { _cu_src_h += _cu_src_y; _cu_src_y = 0; }
                        if (_cu_src_x + _cu_src_w > 48) { _cu_src_w = 48 - _cu_src_x; }
                        if (_cu_src_y + _cu_src_h > 42) { _cu_src_h = 42 - _cu_src_y; }
                        if (_cu_src_w <= 0) { continue; }
                        if (_cu_src_h <= 0) { continue; }
                        // Draw destination — start the part draw at the
                        // sprite's intended origin plus the cropped
                        // source offset scaled back into screen pixels.
                        var _cu_part_dx = _cu_dx + _cu_src_x * _cu_sx;
                        var _cu_part_dy = _cu_dy + _cu_src_y * _cu_sy;
                        draw_sprite_part_ext(_cu_spr, 0,
                            _cu_src_x, _cu_src_y, _cu_src_w, _cu_src_h,
                            _cu_part_dx, _cu_part_dy,
                                                      _cu_sx, _cu_sy,
                            c_white, 1);
                        
                    }
                }
            }
        }
        gpu_set_tex_filter(true);

        surface_set_target(_v2.edit_surface);
		
        // COMP ON  — clear transparent so the canvas reveals the composite
        //            render done above. The selected-slot bit walk below
        //            is suppressed by _comp_view_active.
        // COMP OFF — clear with BG colour as the normal direct-edit view.
        if (_comp_view_active) {
            draw_clear_alpha(c_black, 0);
        } else {
            draw_clear(scr_c64_pepto_colour(_v2.bg_col));
        }


        if (_comp_view_active) {
            // COMP view is active — the canvas is showing the composite
            // render done above the surface_set_target call. Skip the
            // selected-slot bit walk entirely so we don't overlay it on
            // top of the composite.
        } else if (_is_mc) {
            // MC mode: each pair of horizontal pixels makes 1 wide pixel
            // bits indices: 0..23 per row, but MC pairs are (0,1)(2,3)..
            for (var _py = 0; _py < 21; _py++) {
                for (var _px = 0; _px < 24; _px += 2) {
                    var _b0 = _v2.bits[_bit_base + _py * 24 + _px];
                    var _b1 = _v2.bits[_bit_base + _py * 24 + _px + 1];
                    var _pair_col = -1;
                    if (_b0 == 0 && _b1 == 0) _pair_col = -1;          // transparent (BG)
                    else if (_b0 == 0 && _b1 == 1) _pair_col = _v2.mc1_col;
                    else if (_b0 == 1 && _b1 == 0) _pair_col = _uc_pen;
                    else if (_b0 == 1 && _b1 == 1) _pair_col = _v2.mc2_col;
                    if (_pair_col >= 0) {
                        draw_set_color(scr_c64_pepto_colour(_pair_col));
                        draw_rectangle(_px * _cell_size,
                                       _py * _cell_size,
                                       (_px + 2) * _cell_size,
                                       (_py + 1) * _cell_size, false);
                    }
                }
            }
        } else {
            // HR mode: 1 bit per pixel, UC for set, BG already cleared
            draw_set_color(scr_c64_pepto_colour(_uc_pen));
            for (var _py = 0; _py < 21; _py++) {
                for (var _px = 0; _px < 24; _px++) {
                    if (_v2.bits[_bit_base + _py * 24 + _px] == 1) {
                        draw_rectangle(_px * _cell_size,
                                       _py * _cell_size,
                                       (_px + 1) * _cell_size ,
                                       (_py + 1) * _cell_size , false);
                    }
                }
            }
        }
        surface_reset_target();

        // Draw the surface
        draw_surface(_v2.edit_surface, _canvas_x, _canvas_y);

        // Border
        draw_set_color(make_color_rgb(80, 60, 20));
        draw_rectangle(_canvas_x, _canvas_y,
                       _canvas_x + _canvas_w, _canvas_y + _canvas_h, true);

        // Pan hint underneath the canvas
        draw_set_font(fnt_c64_tiny);
        if (_v2.pan_active) {
            draw_set_color(make_color_rgb(120, 255, 120));
            draw_set_halign(fa_center);
            draw_text(_canvas_x + _canvas_w * 0.5,
                      _canvas_y + _canvas_h + 4,
                      "PANNING — RELEASE TO COMMIT");
            draw_set_halign(fa_left);
        } else {
            draw_set_color(make_color_rgb(100, 100, 120));
            draw_set_halign(fa_center);
            draw_text(_canvas_x + _canvas_w * 0.5,
                      _canvas_y + _canvas_h + 4,
                      "[MMB / SPACE+LMB to PAN]");
            draw_set_halign(fa_left);
        }

        // Grid overlay — light lines every cell, brighter every 8
        if (_cell_size >= 8) {
            draw_set_alpha(0.25);
            draw_set_color(make_color_rgb(80, 80, 100));
            for (var _gx = 1; _gx < 24; _gx++) {
                draw_line(_canvas_x + _gx * _cell_size, _canvas_y,
                          _canvas_x + _gx * _cell_size, _canvas_y + _canvas_h);
            }
            for (var _gy = 1; _gy < 21; _gy++) {
                draw_line(_canvas_x, _canvas_y + _gy * _cell_size,
                          _canvas_x + _canvas_w, _canvas_y + _gy * _cell_size);
            }
            draw_set_alpha(1.0);
        }

        // Hover cell highlight + click-paint
        var _canvas_hover = point_in_rectangle(_mx, _my,
            _canvas_x, _canvas_y, _canvas_x + _canvas_w, _canvas_y + _canvas_h);

        // ----- PAN ACTIVATION / UPDATE / DEACTIVATION -----
        // MMB or SPACE+LMB starts the pan when over the canvas.
        // Subsequent frames update the shift in real time, with mode-aware
        // step thresholds (HR=1px, MC=2px-pair in X).
        var _space_held    = keyboard_check(vk_space);
        var _pan_start_btn = mouse_check_button_pressed(mb_middle)
                          || (_space_held && mouse_check_button_pressed(mb_left));
        var _pan_held_btn  = mouse_check_button(mb_middle)
                          || (_space_held && mouse_check_button(mb_left));

        if (!_v2.pan_active && _canvas_hover && _pan_start_btn
        && !global.ui_click_consumed && !global.any_picker_open) {
            _v2.pan_active    = true;
            _v2.pan_slot      = _v2.selected_slot;
            _v2.pan_anchor_mx = _mx;
            _v2.pan_anchor_my = _my;
            _v2.pan_last_mx   = _mx;
            _v2.pan_last_my   = _my;
            _v2.pan_accum_dx  = 0;
            _v2.pan_accum_dy  = 0;
        }
        if (_v2.pan_active) {
            scr_spred64_v2_pan_update(_asset, _mx, _my, _cell_size);
            // Release: stop panning. Both triggers must be released.
            if (!_pan_held_btn) {
                _v2.pan_active = false;
                _v2.pan_slot   = -1;
            }
        }

        _v2.canvas_pix_hover = false;
        _v2.canvas_pix_x     = -1;
        _v2.canvas_pix_y     = -1;
        // Set true below when the cursor is over the canvas AND the edited
        // sprite is expanded in COMP mode — we hide the OS pointer then so
        // it doesn't compete with the compositor-grid marker. Resolved once
        // at the end of the canvas section so every other case restores it.
        var _hide_os_cursor = false;
        if (_canvas_hover && !_v2.pan_active) {
            var _hx = floor((_mx - _canvas_x) / _cell_size);
            var _hy = floor((_my - _canvas_y) / _cell_size);

            // In MC mode, snap hover X to the MC pair (even index)
            var _snap_x = _is_mc ? (_hx - (_hx mod 2)) : _hx;

            // Record the hovered sprite pixel so the compositor grid can
            // float a "where this pixel lands" marker at the matching spot.
            // MC snaps to the pair's left cell. Bounds-checked so an
            // out-of-range hover (shouldn't happen, but cheap to guard)
            // doesn't drive the marker off the cell.
            if (_hx >= 0 && _hx < 24 && _hy >= 0 && _hy < 21) {
                _v2.canvas_pix_hover = true;
                _v2.canvas_pix_x     = _is_mc ? _snap_x : _hx;
                _v2.canvas_pix_y     = _hy;
            }

            if (_hx >= 0 && _hx < 24 && _hy >= 0 && _hy < 21) {
                // Is the sprite we're editing placed expanded anywhere in
                // this frame? Only relevant in COMP mode — outside COMP the
                // canvas is the direct 1:1 view, so the hover rect is correct
                // and the hint would be misleading. In COMP mode a stretched
                // placement means the on-canvas rect would misalign (the true
                // position is shown by the floating marker in the compositor
                // grid instead), so we suppress the rect and show a hint.
                var _hov_expanded = false;
                if (_v2.comp_preview) {
                    var _hov_cf = _v2.compositor.frames[_v2.compositor.active_frame];
                    for (var _he_i = 0; _he_i < array_length(_hov_cf.cells); _he_i++) {
                        var _he_c = _hov_cf.cells[_he_i];
                        if (_he_c.slot == _v2.selected_slot
                        && (_he_c.expand == "x" || _he_c.expand == "y" || _he_c.expand == "both")) {
                            _hov_expanded = true;
                            break;
                        }
                    }
                }

                if (_hov_expanded) {
                    // Hint instead of the misaligned rect — placed just below
                    // the canvas top, centred, so it doesn't fight the sprite.
                    // Also hide the OS pointer so it doesn't compete with the
                    // compositor-grid marker that's doing the real work.
                    _hide_os_cursor = true;
                    draw_set_font(fnt_c64_tiny);
                    draw_set_color(make_color_rgb(120, 255, 120));
                    draw_set_halign(fa_center);
                    draw_set_valign(fa_top);
                    draw_text(_canvas_x + _canvas_w * 0.5, _canvas_y + 4,
                        "USE CURSOR IN COMPOSITOR VIEW");
                    draw_set_halign(fa_left);
                    draw_set_valign(fa_top);
                } else {
                    // Outline cell (or MC pair). Green when a tool is armed
                    // (FILL or LINE) so the user has clear feedback that the
                    // next click will trigger the tool action.
                    if (_v2.fill_armed || _v2.line_armed) {
                        draw_set_color(make_color_rgb(120, 255, 120));
                    } else {
                        draw_set_color(c_white);
                    }
                    draw_set_alpha(0.5);
                    var _cell_w_h = _is_mc ? (2 * _cell_size) : _cell_size;
                    draw_rectangle(_canvas_x + _snap_x * _cell_size,
                                   _canvas_y + _hy * _cell_size,
                                   _canvas_x + _snap_x * _cell_size + _cell_w_h,
                                   _canvas_y + (_hy + 1) * _cell_size, true);
                    draw_set_alpha(1.0);
                }

                // ----- LINE TOOL : pixel-accurate preview overlay -----
                // When armed AND anchor set, walk the same Bresenham path
                // that scr_spred64_v2_fx_line uses on commit, drawing each
                // plotted pixel as a filled cell on the canvas. MC mode
                // snaps endpoints to pair boundaries and renders 2-wide
                // blocks per step so the preview matches the commit
                // 1:1. The active paint colour is used so the user sees
                // exactly what will be written.
                if (_v2.line_armed
                &&  _v2.line_anchor_x >= 0
                &&  _v2.line_anchor_y >= 0) {

                    // Endpoint coords in sprite-pixel space (24x21 grid)
                    var _lp_x0 = _v2.line_anchor_x;
                    var _lp_y0 = _v2.line_anchor_y;
                    var _lp_x1 = _is_mc ? _snap_x : _hx;
                    var _lp_y1 = _hy;

                    // MC mode — snap both endpoints to pair boundaries.
                    // Mirrors the snap done in scr_spred64_v2_fx_line.
                    if (_is_mc) {
                        _lp_x0 = _lp_x0 - (_lp_x0 mod 2);
                        _lp_x1 = _lp_x1 - (_lp_x1 mod 2);
                    }

                    // Determine the preview colour. For MC mode use the
                    // active_colour role; for HR mode use the slot's UC.
                    var _lp_paint_idx = 0;
                    if (_is_mc) {
                        switch (_v2.active_colour) {
                            case 1: _lp_paint_idx = _v2.mc1_col;            break;
                            case 2: _lp_paint_idx = _v2.mc2_col;            break;
                            case 3: _lp_paint_idx = _v2.sprite_uc[_slot];   break;
                            default: _lp_paint_idx = _v2.bg_col;            break;
                        }
                    } else {
                        _lp_paint_idx = _v2.sprite_uc[_slot];
                    }
                    var _lp_paint_col = scr_c64_pepto_colour(_lp_paint_idx);

                    // Bresenham — same maths as scr_spred64_v2_fx_line so
                    // the preview cannot diverge from the committed line.
                    var _lp_dx     = abs(_lp_x1 - _lp_x0);
                    var _lp_dy     = abs(_lp_y1 - _lp_y0);
                    var _lp_sxstep = _is_mc ? 2 : 1;
                    var _lp_sx     = (_lp_x0 < _lp_x1) ? _lp_sxstep : -_lp_sxstep;
                    var _lp_sy     = (_lp_y0 < _lp_y1) ? 1 : -1;
                    var _lp_dxeff  = _is_mc ? floor(_lp_dx / 2) : _lp_dx;
                    var _lp_err    = _lp_dxeff - _lp_dy;
                    var _lp_cx     = _lp_x0;
                    var _lp_cy     = _lp_y0;
                    var _lp_safety = 64;

                    draw_set_alpha(0.85);
                    draw_set_color(_lp_paint_col);

                    while (_lp_safety > 0) {
                        _lp_safety--;

                        // Plot at (_lp_cx, _lp_cy) — render as a filled
                        // canvas cell (or MC pair) at the same scale as
                        // the underlying pixel grid.
                        if (_lp_cx >= 0 && _lp_cx < 24
                        &&  _lp_cy >= 0 && _lp_cy < 21) {
                            var _lp_w = _is_mc ? (2 * _cell_size) : _cell_size;
                            var _lp_px1 = _canvas_x + _lp_cx * _cell_size;
                            var _lp_py1 = _canvas_y + _lp_cy * _cell_size;
                            var _lp_px2 = _lp_px1 + _lp_w - 1;
                            var _lp_py2 = _lp_py1 + _cell_size - 1;
                            draw_rectangle(_lp_px1, _lp_py1, _lp_px2, _lp_py2, false);
                        }

                        // End condition — reached the hover endpoint
                        if (_lp_cx == _lp_x1 && _lp_cy == _lp_y1) {
                            break;
                        }

                        var _lp_e2 = _lp_err * 2;
                        if (_lp_e2 > -_lp_dy) {
                            _lp_err -= _lp_dy;
                            _lp_cx  += _lp_sx;
                        }
                        if (_lp_e2 < _lp_dxeff) {
                            _lp_err += _lp_dxeff;
                            _lp_cy  += _lp_sy;
                        }
                    }

                    draw_set_alpha(1.0);

                    // Anchor marker — small green outline square on the
                    // anchor cell so the user can always see where the
                    // line will originate, even if it's been overdrawn
                    // by the preview pixels at the start of the run.
                    var _lp_anchor_w = _is_mc ? (2 * _cell_size) : _cell_size;
                    var _lp_ax1 = _canvas_x + _lp_x0 * _cell_size;
                    var _lp_ay1 = _canvas_y + _lp_y0 * _cell_size;
                    var _lp_ax2 = _lp_ax1 + _lp_anchor_w;
                    var _lp_ay2 = _lp_ay1 + _cell_size;
                    draw_set_color(make_color_rgb(120, 255, 120));
                    draw_rectangle(_lp_ax1, _lp_ay1, _lp_ax2, _lp_ay2, true);
                    draw_rectangle(_lp_ax1 + 1, _lp_ay1 + 1, _lp_ax2 - 1, _lp_ay2 - 1, true);
                }

                // If flood-fill is armed, intercept LEFT click to run the
                // flood, instead of falling through to per-pixel paint.
                // Right-click in armed mode disarms (alternate cancel path).
                if (_v2.fill_armed && mouse_check_button_pressed(mb_left)
                && !global.ui_click_consumed && !global.any_picker_open) {
                    scr_spred64_v2_fx_flood_fill(_v2.selected_slot, _hx, _hy);
                    // flood script clears fill_armed and refreshes
                }
                else if (_v2.fill_armed && mouse_check_button_pressed(mb_right)) {
                    _v2.fill_armed = false;
                }
                // LINE tool — two-stage: first click sets anchor, second
                // click commits the line. Right-click disarms.
                else if (_v2.line_armed && mouse_check_button_pressed(mb_left)
                && !global.ui_click_consumed && !global.any_picker_open) {
                    if (_v2.line_anchor_x < 0) {
                        // First click — set anchor
                        _v2.line_anchor_x = _is_mc ? _snap_x : _hx;
                        _v2.line_anchor_y = _hy;
                    } else {
                        // Second click — commit line
                        scr_spred64_v2_fx_line(
                            _v2.selected_slot,
                            _v2.line_anchor_x, _v2.line_anchor_y,
                            _is_mc ? _snap_x : _hx, _hy);
                        _v2.line_anchor_x = -1;
                        _v2.line_anchor_y = -1;
                    }
                }
                else if (_v2.line_armed && mouse_check_button_pressed(mb_right)) {
                    _v2.line_armed    = false;
                    _v2.line_anchor_x = -1;
                    _v2.line_anchor_y = -1;
                }
                // Painting (skipped while armed so user doesn't accidentally
                // paint over the fill/line target with the standard left-button,
                // and skipped during cooldown after V2 opened from a picker
                // click so the opening click doesn't bleed through).
                else if ((mouse_check_button(mb_left) || mouse_check_button(mb_right))
                && !global.ui_click_consumed && !global.any_picker_open
                && !_v2.fill_armed && !_v2.line_armed && _v2.paint_cooldown <= 0) {

                    var _idx = _bit_base + _hy * 24 + _snap_x;

                    if (_is_mc) {
                        // MC: write bit-pair according to active colour or right-click clear
                        var _new_b0 = 0;
                        var _new_b1 = 0;
                        if (mouse_check_button(mb_left)) {
                            switch (_v2.active_colour) {
                                case 1: _new_b0 = 0; _new_b1 = 1; break; // MC1
                                case 2: _new_b0 = 1; _new_b1 = 1; break; // MC2
                                case 3: _new_b0 = 1; _new_b1 = 0; break; // UC
                                default: _new_b0 = 0; _new_b1 = 0; break;
                            }
                        }
                        // (right-click = 0,0 = BG, already initialised)

                        var _old_b0 = _v2.bits[_idx];
                        var _old_b1 = _v2.bits[_idx + 1];
                        if (_old_b0 != _new_b0 || _old_b1 != _new_b1) {
                            _v2.bits[_idx]     = _new_b0;
                            _v2.bits[_idx + 1] = _new_b1;
                            _v2.dirty = true;
							scr_spred64_v2_invalidate_sot(_slot);
                            scr_spred64_v2_refresh_slot_sprite(_asset, _slot);
                        }
                    } else {
                        // HR: 1 = on (UC), 0 = off (BG)
                        var _new_bit = mouse_check_button(mb_left) ? 1 : 0;
                        if (_v2.bits[_idx] != _new_bit) {
                            _v2.bits[_idx] = _new_bit;
                            _v2.dirty = true;
							scr_spred64_v2_invalidate_sot(_slot);
                            scr_spred64_v2_refresh_slot_sprite(_asset, _slot);
                        }
                    }
                }
            }
        }

		// Apply the OS-cursor visibility resolved above. Hidden only while
        // hovering the canvas over an expanded sprite in COMP mode; restored
        // to default in every other case so the pointer never gets stuck
        // invisible after the mouse moves away.
        if (_hide_os_cursor) {
            window_set_cursor(cr_none);
        } else {
            window_set_cursor(cr_default);
        }

		// -------------------------------------------------------
        // FX STRIP (LEFT OF CANVAS)
        // -------------------------------------------------------
        // Three buttons stacked vertically, operating on the raw bits[] of
        // the active slot. Aligned to the canvas vertically — top of the
        // first button matches the canvas top.
        var _fx_strip_x  = _ed_x1 + 8;
        var _fx_strip_y  = _canvas_y;
        var _fx_btn_h    = 28;
        var _fx_btn_gap  = 6;
        var _fx_lbls     = ["FLIPX", "FLIPY", "ROT90", "CLEAR", "FILL", "LINE"];
        draw_set_font(fnt_c64_tiny);
        for (var _fxi = 0; _fxi < array_length(_fx_lbls); _fxi++) {
            var _fbx1 = _fx_strip_x;
            var _fbx2 = _fbx1 + _fx_strip_w;
            var _fby1 = _fx_strip_y + _fxi * (_fx_btn_h + _fx_btn_gap);
            var _fby2 = _fby1 + _fx_btn_h;
            var _fb_hov = point_in_rectangle(_mx, _my, _fbx1, _fby1, _fbx2, _fby2);
            // Fill colour and border vary by button type and state:
            //   CLEAR (index 3) — red, destructive
            //   FILL  (index 4) — bright green when armed, orange otherwise
            //   Others — orange
            var _is_destructive = (_fxi == 3);
            var _is_fill_armed  = (_fxi == 4 && _v2.fill_armed);
            var _is_line_armed  = (_fxi == 5 && _v2.line_armed);
            if (_is_fill_armed || _is_line_armed) {
                if (_fb_hov) {
                    draw_set_color(make_color_rgb(60, 140, 60));
                } else {
                    draw_set_color(make_color_rgb(40, 100, 40));
                }
            } else if (_is_destructive) {
                if (_fb_hov) {
                    draw_set_color(make_color_rgb(160, 40, 40));
                } else {
                    draw_set_color(make_color_rgb(80, 20, 20));
                }
            } else {
                if (_fb_hov) {
                    draw_set_color(make_color_rgb(70, 50, 25));
                } else {
                    draw_set_color(make_color_rgb(40, 30, 15));
                }
            }
            draw_rectangle(_fbx1, _fby1, _fbx2, _fby2, false);
            // Border — armed FILL/LINE = bright green (doubled), destructive = bright red, else orange
            if (_is_fill_armed || _is_line_armed) {
                draw_set_color(make_color_rgb(120, 255, 120));
                draw_rectangle(_fbx1,     _fby1,     _fbx2,     _fby2,     true);
                draw_rectangle(_fbx1 + 1, _fby1 + 1, _fbx2 - 1, _fby2 - 1, true);
            } else if (_is_destructive) {
                draw_set_color(make_color_rgb(255, 80, 80));
                draw_rectangle(_fbx1, _fby1, _fbx2, _fby2, true);
            } else {
                draw_set_color(make_color_rgb(200, 140, 60));
                draw_rectangle(_fbx1, _fby1, _fbx2, _fby2, true);
            }
            // Label
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text((_fbx1 + _fbx2) * 0.5, (_fby1 + _fby2) * 0.5, _fx_lbls[_fxi]);
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
            // Click handling — fires the relevant FX script on the active slot
            if (_fb_hov && mouse_check_button_pressed(mb_left)
            && !global.ui_click_consumed && !global.any_picker_open) {
                switch (_fxi) {
                    case 0:
                    case 1:
                    case 2:
					case 3:
                        // Geometry FX (FLIPX / FLIPY / ROT90) apply to the
                        // primary slot AND every batch-selected slot. Each
                        // FX script self-invalidates and refreshes its own
                        // slot, so we just call it once per target. Bound to
                        // used_count so a stale entry on a removed slot can't
                        // dispatch out of range.
                        var _fx_used = clamp(_v2.used_count, 1, 64);
                        for (var _fx_i = 0; _fx_i < _fx_used; _fx_i++) {
                            // Apply to primary, plus any multi-selected slot.
                            var _fx_do = (_fx_i == _v2.selected_slot)
                                      || _v2.multi_select[_fx_i];
                            if (!_fx_do) { continue; }
                            switch (_fxi) {
                                case 0: scr_spred64_v2_fx_flipx(_fx_i); break;
                                case 1: scr_spred64_v2_fx_flipy(_fx_i); break;
                                case 2: scr_spred64_v2_fx_rot90(_fx_i); break;
								case 3: scr_spred64_v2_fx_clear(_fx_i); break;
                            }
                        }
                        break;
 
                    case 4:
                        // FILL is two-stage: clicking the button arms or
                        // disarms flood-fill mode. The actual fill happens
                        // when the user next clicks a pixel on the canvas.
                        // Arming FILL disarms LINE (mutually exclusive).
                        _v2.fill_armed = !_v2.fill_armed;
                        if (_v2.fill_armed) {
                            _v2.line_armed    = false;
                            _v2.line_anchor_x = -1;
                            _v2.line_anchor_y = -1;
                        }
                        break;
                    case 5:
                        // LINE is two-stage per line: first canvas click
                        // sets the anchor, second click commits and clears
                        // anchor. Tool stays armed for repeat lines until
                        // user toggles it off or arms FILL.
                        _v2.line_armed = !_v2.line_armed;
                        if (_v2.line_armed) {
                            _v2.fill_armed    = false;
                        }
                        _v2.line_anchor_x = -1;
                        _v2.line_anchor_y = -1;
                        break;
                }
            }
        }

        // -------------------------------------------------------
        // PALETTE STRIP (RIGHT OF CANVAS)
        // -------------------------------------------------------
        // 4 vertical columns: BG / MC1 / MC2 / UC. Each column shows:
        //   - tiny label at the top
        //   - the current selected colour as a larger swatch (with index)
        //   - 16 picker swatches stacked vertically
        // Total column height is locked to match the canvas height exactly,
        // so the bottom row lines up with the bottom of the canvas.
        var _pal_col_w   = 30;
        var _pal_col_g   = 4;
        var _pal_strip_x = _ed_x2 - 18 - _pal_strip_w;
        var _pal_strip_y = _canvas_y + 4
        var _pal_strip_h = _canvas_h;

        // Layout per column: label (12px) + current swatch (square = _pal_col_w)
        // + gap (4) + 16 swatches that fill the remaining vertical space.
        var _pal_lbl_h    = 12;
        var _pal_cur_h    = _pal_col_w;
        var _pal_inner_g  = 4;
        var _pal_pickers_top = _pal_strip_y + _pal_lbl_h + _pal_cur_h + _pal_inner_g;
        var _pal_pickers_h   = _pal_strip_h - _pal_lbl_h - _pal_cur_h - _pal_inner_g;
        // 16 swatches share the available height with 1px gap between them
        var _pal_sw_h        = floor((_pal_pickers_h - 15) / 16);
        if (_pal_sw_h < 4) _pal_sw_h = 4;

        var _pal_lbls = ["UC", "MC1", "MC2", "BG"];
        var _pal_vals = [_v2.sprite_uc[_v2.selected_slot], _v2.mc1_col, _v2.mc2_col, _v2.bg_col];

        draw_set_font(fnt_c64_tiny);
        for (var _pci = 0; _pci < 4; _pci++) {
            var _pcol_x  = _pal_strip_x + _pci * (_pal_col_w + _pal_col_g);
            var _pcol_x2 = _pcol_x + _pal_col_w;
            var _cur_val = _pal_vals[_pci];

            // Label
            draw_set_color(make_color_rgb(160, 160, 200));
            draw_set_halign(fa_center);
            draw_text(_pcol_x + _pal_col_w * 0.5, _pal_strip_y -7 , _pal_lbls[_pci]);
            draw_set_halign(fa_left);

            // Current swatch (with index number bottom-right).
            // Highlighted when this column's role is the active paint target.
            // BG can't be the paint target — only MC1/MC2/UC light up.
            // Clickable to switch paint role without changing the colour.
            var _cur_y1 = _pal_strip_y + _pal_lbl_h;
            var _cur_y2 = _cur_y1 + _pal_cur_h;
            var _cur_hov = point_in_rectangle(_mx, _my, _pcol_x, _cur_y1, _pcol_x2, _cur_y2);
            draw_set_color(scr_c64_pepto_colour(_cur_val));
            draw_rectangle(_pcol_x, _cur_y1, _pcol_x2, _cur_y2, false);
            // Column order is now [UC, MC1, MC2, BG]. Paint roles map:
            //   col 0 = UC  (active_colour 3)
            //   col 1 = MC1 (active_colour 1)
            //   col 2 = MC2 (active_colour 2)
            //   col 3 = BG  (no paint role)
            var _is_paint_active = (_pci == 0 && _v2.active_colour == 3)
                                || (_pci == 1 && _v2.active_colour == 1)
                                || (_pci == 2 && _v2.active_colour == 2);
            if (_is_paint_active) {
                draw_set_color(make_color_rgb(120, 255, 120));
                draw_rectangle(_pcol_x,     _cur_y1,     _pcol_x2,     _cur_y2,     true);
                draw_rectangle(_pcol_x + 1, _cur_y1 + 1, _pcol_x2 - 1, _cur_y2 - 1, true);
            } else if (_cur_hov && _pci < 3) {
                // Hover hint for selectable columns (UC/MC1/MC2) — white border.
                // Column 3 is now BG, which isn't a paint target.
                draw_set_color(c_white);
                draw_rectangle(_pcol_x, _cur_y1, _pcol_x2, _cur_y2, true);
            } else {
                draw_set_color(make_color_rgb(120, 120, 140));
                draw_rectangle(_pcol_x, _cur_y1, _pcol_x2, _cur_y2, true);
            }
            // Click: set active paint role to this column's role. BG (col 3)
            // can't be a paint target so its click is a no-op. Other columns
            // map: UC=0 -> active 3, MC1=1 -> active 1, MC2=2 -> active 2.
            if (_cur_hov && _pci < 3
            && mouse_check_button_pressed(mb_left)
            && !global.ui_click_consumed && !global.any_picker_open) {
                if (_pci == 0) {
                    _v2.active_colour = 3;
                } else {
                    _v2.active_colour = _pci;
                }
            }
            // Index label — small, on a contrasting strip for legibility
            var _idx_txt = string(_cur_val);
            var _idx_tw  = string_width(_idx_txt) + 4;
            draw_set_color(make_color_rgb(0, 0, 0));
            draw_set_alpha(0.6);
            draw_rectangle(_pcol_x2 - _idx_tw, _cur_y2 - 10,
                           _pcol_x2,             _cur_y2,        false);
            draw_set_alpha(1.0);
            draw_set_color(c_white);
            draw_text(_pcol_x2 - _idx_tw + 2, _cur_y2 - 11, _idx_txt);

            // 16 picker swatches stacked vertically
            for (var _pi = 0; _pi < 16; _pi++) {
                var _psy1 = _pal_pickers_top + _pi * (_pal_sw_h + 1);
                var _psy2 = _psy1 + _pal_sw_h;
                var _ps_hov = point_in_rectangle(_mx, _my, _pcol_x, _psy1, _pcol_x2, _psy2);
                draw_set_color(scr_c64_pepto_colour(_pi));
                draw_rectangle(_pcol_x, _psy1, _pcol_x2, _psy2, false);

                // Selection / hover border
                if (_cur_val == _pi) {
                    draw_set_color(make_color_rgb(255, 220, 120));
                    draw_rectangle(_pcol_x,     _psy1,     _pcol_x2,     _psy2,     true);
                    draw_rectangle(_pcol_x + 1, _psy1 + 1, _pcol_x2 - 1, _psy2 - 1, true);
                } else if (_ps_hov) {
                    draw_set_color(c_white);
                    draw_rectangle(_pcol_x, _psy1, _pcol_x2, _psy2, true);
                }

                if (_ps_hov && mouse_check_button_pressed(mb_left)
                && !global.ui_click_consumed && !global.any_picker_open) {
                    // Column order is now [UC, MC1, MC2, BG].
                    switch (_pci) {
                        case 0:
                            _v2.sprite_uc[_v2.selected_slot] = _pi;
                            _v2.active_colour = 3;
                            // Fan the UC pen out to every batch-selected slot.
                            // Bound to used_count so a stale entry on a
                            // removed slot can't refresh out of range. The
                            // per-slot refresh below (the _pci == 0 branch)
                            // only refreshes selected_slot, so refresh the
                            // rest here.
                            var _uc_used = clamp(_v2.used_count, 1, 64);
                            for (var _uc_i = 0; _uc_i < _uc_used; _uc_i++) {
                                if (_v2.multi_select[_uc_i] && _uc_i != _v2.selected_slot) {
                                    _v2.sprite_uc[_uc_i] = _pi;
                                    scr_spred64_v2_refresh_slot_sprite(_asset, _uc_i);
                                }
                            }
                            break;
                        case 1:
                            _v2.mc1_col = _pi;
                            _v2.active_colour = 1;
                            break;
                        case 2:
                            _v2.mc2_col = _pi;
                            _v2.active_colour = 2;
                            break;
                        case 3:
                            _v2.bg_col  = _pi;
                            // BG isn't a paint role — don't change active_colour
                            break;
                    }
                    _v2.dirty = true;
                    // Force edit surface rebuild
                    if (surface_exists(_v2.edit_surface)) {
                        surface_free(_v2.edit_surface);
                    }
                    _v2.edit_surface = -1;
                    // Refresh picker thumbnails. UC is per-slot (col 0);
                    // MC1/MC2/BG are shared so every cached slot needs a
                    // rebuild to reflect the new palette.
                    if (_pci == 0) {
                        scr_spred64_v2_refresh_slot_sprite(_asset, _v2.selected_slot);
                    } else {
                        var _refresh_count = clamp(_v2.used_count, 1, 64);
                        for (var _refresh_i = 0; _refresh_i < _refresh_count; _refresh_i++) {
                            scr_spred64_v2_refresh_slot_sprite(_asset, _refresh_i);
                        }
                    }
                }
            }
        }

        // -------------------------------------------------------
        // ANIMATION ZONE (between editor and compositor)
        // -------------------------------------------------------
        // Drives compositor.active_frame over time. Layout:
        //   LEFT   — PLAY + direction tabs (FWD/REV/PNG/ONCE), SPEED, START/END
        //   MIDDLE — state pill (STOPPED / PLAYING — MODE), PREV/NEXT buttons
        //   RIGHT  — frame management (NEW / DUP / CLEAR / DELETE)
        scr_spred64_v2_anim_step();

        var _anim_x1 = _right_x1;
        var _anim_x2 = _right_x2;
        var _anim_y1 = _split_y + 4;
        var _anim_y2 = _rsv_y1 - 4;

        // Panel backdrop
        draw_set_color(make_color_rgb(10, 10, 16));
        draw_rectangle(_anim_x1, _anim_y1, _anim_x2, _anim_y2, false);
        draw_set_color(make_color_rgb(40, 30, 15));
        draw_rectangle(_anim_x1, _anim_y1, _anim_x2, _anim_y2, true);

        // Convenience: total frame count for clamping steppers
        var _frame_count_total = array_length(_v2.compositor.frames);
        var _max_frame = max(0, _frame_count_total - 1);

        // Column splits
        var _anim_left_w  = 240;
        var _anim_right_w = 130;     // 2 cols of compact buttons + gap
        var _anim_lx1 = _anim_x1 + 8;
        var _anim_lx2 = _anim_lx1 + _anim_left_w;
        var _anim_rx2 = _anim_x2 - 8;
        var _anim_rx1 = _anim_rx2 - _anim_right_w;
        var _anim_mx1 = _anim_lx2 + 10;
        var _anim_mx2 = _anim_rx1 - 10;

        // ===== LEFT COLUMN : transport =====
        // Row 1: PLAY + direction tabs — compact heights, smaller padding.
        var _row_h = 16;
        var _r1_y1 = _anim_y1 + 4;
        var _r1_y2 = _r1_y1 + _row_h;

       // PLAY button
        var _play_x1 = _anim_lx1;
        var _play_x2 = _play_x1 + 44;
        var _play_hov = point_in_rectangle(_mx, _my, _play_x1, _r1_y1, _play_x2, _r1_y2);
        if (_v2.anim_playing) {
            draw_set_color(_play_hov ? make_color_rgb(60, 140, 200) : make_color_rgb(40, 90, 160));
        } else {
            draw_set_color(_play_hov ? make_color_rgb(70, 50, 25) : make_color_rgb(40, 30, 15));
        }
        draw_rectangle(_play_x1, _r1_y1, _play_x2, _r1_y2, false);
        if (_v2.anim_playing) {
            draw_set_color(make_color_rgb(120, 255, 120));
            draw_rectangle(_play_x1,     _r1_y1,     _play_x2,     _r1_y2,     true);
            draw_rectangle(_play_x1 + 1, _r1_y1 + 1, _play_x2 - 1, _r1_y2 - 1, true);
        } else {
            draw_set_color(make_color_rgb(200, 140, 60));
            draw_rectangle(_play_x1, _r1_y1, _play_x2, _r1_y2, true);
        }
        draw_set_color(c_white);
        draw_set_font(fnt_c64_tiny);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        var _play_lbl = _v2.anim_playing ? "STOP" : "PLAY";
        draw_text((_play_x1 + _play_x2) * 0.5, (_r1_y1 + _r1_y2) * 0.5, _play_lbl);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        if (_play_hov && mouse_check_button_pressed(mb_left)
        && !global.ui_click_consumed && !global.any_picker_open) {
            _v2.anim_playing       = !_v2.anim_playing;
            _v2.anim_last_step_ms  = current_time;
            if (_v2.anim_playing) {
                // Starting playback: snap active_frame back to a sensible
                // starting position depending on direction. This makes ONCE
                // replayable (press PLAY after stop -> starts from anim_start)
                // and also fixes any case where the user nav'd outside the
                // play range manually.
                var _frame_count = array_length(_v2.compositor.frames);
                var _start = clamp(_v2.anim_start, 0, _frame_count - 1);
                var _end_clamped = clamp(_v2.anim_end, 0, _frame_count - 1);
                if (_start > _end_clamped) {
                    var _tmp = _start;
                    _start = _end_clamped;
                    _end_clamped = _tmp;
                }
                var _cur = _v2.compositor.active_frame;
                switch (_v2.anim_direction) {
                    case "fwd":
                        // If sitting at or past end, restart from start.
                        // Also handles fresh playback that just naturally
                        // wraps, so safe to leave _cur in range otherwise.
                        if (_cur >= _end_clamped || _cur < _start) {
                            _v2.compositor.active_frame = _start;
                        }
                        break;
                    case "rev":
                        if (_cur <= _start || _cur > _end_clamped) {
                            _v2.compositor.active_frame = _end_clamped;
                        }
                        break;
                    case "png":
                        // Always start ping-pong fwd from start
                        _v2.compositor.active_frame = _start;
                        _v2.anim_png_dir = 1;
                        break;
                    case "once":
                        // ONCE always plays the full range from scratch
                        _v2.compositor.active_frame = _start;
                        break;
                }
            }
        }

        // Direction tabs — 4 equal-width buttons
        var _dir_x1 = _play_x2 + 6;
        var _dir_x2 = _anim_lx2;
        var _dir_btn_w = floor((_dir_x2 - _dir_x1 - 6) / 4);
        var _dir_opts  = ["fwd", "rev", "png", "once"];
        var _dir_lbls  = ["FWD", "REV", "PNG", "ONCE"];
        for (var _di = 0; _di < 4; _di++) {
            var _dx1 = _dir_x1 + _di * (_dir_btn_w + 2);
            var _dx2 = _dx1 + _dir_btn_w;
            var _d_active = (_v2.anim_direction == _dir_opts[_di]);
            var _d_hov    = point_in_rectangle(_mx, _my, _dx1, _r1_y1, _dx2, _r1_y2);
            if (_d_active) {
                draw_set_color(_d_hov ? make_color_rgb(60, 140, 200) : make_color_rgb(40, 90, 160));
            } else {
                draw_set_color(_d_hov ? make_color_rgb(30, 50, 80) : make_color_rgb(20, 25, 40));
            }
            draw_rectangle(_dx1, _r1_y1, _dx2, _r1_y2, false);
            if (_d_active) {
                draw_set_color(make_color_rgb(120, 255, 120));
                draw_rectangle(_dx1,     _r1_y1,     _dx2,     _r1_y2,     true);
                draw_rectangle(_dx1 + 1, _r1_y1 + 1, _dx2 - 1, _r1_y2 - 1, true);
            } else {
                draw_set_color(make_color_rgb(40, 40, 60));
                draw_rectangle(_dx1, _r1_y1, _dx2, _r1_y2, true);
            }
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text((_dx1 + _dx2) * 0.5, (_r1_y1 + _r1_y2) * 0.5, _dir_lbls[_di]);
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
            if (_d_hov && mouse_check_button_pressed(mb_left)
            && !global.ui_click_consumed && !global.any_picker_open) {
                _v2.anim_direction = _dir_opts[_di];
                if (_dir_opts[_di] == "png") {
                    _v2.anim_png_dir = 1;
                }
            }
        }

// Row 2: START / END / SPEED — all on one row, three steppers.
        // Each stepper: LABEL - [num] +   spaced equally across the left column.
        var _r2_y1 = _r1_y2 + 12;
        var _r2_y2 = _r2_y1 + 14;
        var _sp_btn_w = 14;
        var _sp_num_w = 22;

        // Helper inline: render three steppers via array iteration so it's
        // tight and easy to tune positions in one place.
        var _steppers = [
            { lbl:"START", value:_v2.anim_start, kind:"start" },
            { lbl:" END ", value:_v2.anim_end,   kind:"end"   },
            { lbl:" FPS ", value:_v2.anim_speed, kind:"speed" }
        ];
        var _stepper_unit = _sp_btn_w + 10 + _sp_num_w + 10 + _sp_btn_w + 10;  // - num + spacer
        var _label_w      = 45;       // space reserved for the leading label
        var _group_w      = _label_w + _stepper_unit;
        var _row_left     = _anim_lx1;
		var _c_butBorder = make_colour_rgb(150,180,180);
		
        for (var _si = 0; _si < array_length(_steppers); _si++) {
            var _sd = _steppers[_si];
            var _gx = _row_left + _si * _group_w;

            // Label
            draw_set_color(make_color_rgb(160, 160, 200));
            draw_set_valign(fa_middle);
            draw_text(_gx, (_r2_y1 + _r2_y2) * 0.5, _sd.lbl);
            draw_set_valign(fa_top);

			
            // - button
            var _sm_x1 = _gx + _label_w;
            var _sm_x2 = _sm_x1 + _sp_btn_w;
            var _sm_hov = point_in_rectangle(_mx, _my, _sm_x1, _r2_y1, _sm_x2, _r2_y2);
            draw_set_color(_sm_hov ? make_color_rgb(60, 40, 20) : make_color_rgb(30, 25, 15));
            draw_rectangle(_sm_x1, _r2_y1, _sm_x2, _r2_y2, false);
            draw_set_color(_c_butBorder);
            draw_rectangle(_sm_x1, _r2_y1, _sm_x2, _r2_y2, true);
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            //draw_text( (_sm_x1 + _sm_x2) * 0.5, (_r2_y1 + _r2_y2) * 0.5, "-");
			draw_text(((_sm_x1 + _sm_x2) * 0.5) -1, ((_r2_y1 + _r2_y2) * 0.5)-1 , "-");
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
            if (_sm_hov && mouse_check_button_pressed(mb_left)
            && !global.ui_click_consumed && !global.any_picker_open) {
                if (_sd.kind == "start") {
                    _v2.anim_start = max(0, _v2.anim_start - 1);
                } else if (_sd.kind == "end") {
                    _v2.anim_end = max(0, _v2.anim_end - 1);
                } else {
                    _v2.anim_speed = max(1, _v2.anim_speed - 1);
                }
            }

            // Number
            var _sn_x1 = _sm_x2 + 2;
            var _sn_x2 = _sn_x1 + _sp_num_w;
            draw_set_color(make_color_rgb(20, 20, 30));
            draw_rectangle(_sn_x1, _r2_y1, _sn_x2, _r2_y2, false);
            draw_set_color(make_color_rgb(40, 40, 60));
            draw_rectangle(_sn_x1, _r2_y1, _sn_x2, _r2_y2, true);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text((_sn_x1 + _sn_x2) * 0.5, (_r2_y1 + _r2_y2) * 0.5, string(_sd.value));
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);

            // + button
            var _sp_x1 = _sn_x2 + 2;
            var _sp_x2 = _sp_x1 + _sp_btn_w;
            var _sp_hov = point_in_rectangle(_mx, _my, _sp_x1, _r2_y1, _sp_x2, _r2_y2);
            draw_set_color(_sp_hov ? make_color_rgb(60, 40, 20) : make_color_rgb(30, 25, 15));
            draw_rectangle(_sp_x1, _r2_y1, _sp_x2, _r2_y2, false);
            draw_set_color(_c_butBorder);
            draw_rectangle(_sp_x1, _r2_y1, _sp_x2, _r2_y2, true);
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text(((_sp_x1 + _sp_x2) * 0.5) -1, ((_r2_y1 + _r2_y2) * 0.5)-1 , "+");
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
            if (_sp_hov && mouse_check_button_pressed(mb_left)
            && !global.ui_click_consumed && !global.any_picker_open) {
                if (_sd.kind == "start") {
                    _v2.anim_start = min(_max_frame, _v2.anim_start + 1);
                } else if (_sd.kind == "end") {
                    _v2.anim_end = min(_max_frame, _v2.anim_end + 1);
                } else {
                    _v2.anim_speed = min(30, _v2.anim_speed + 1);
                }
            }
        }

        // Track the bottom of this combined row so any later references
        // to _r3_y2 still resolve. The animation panel only uses these
        // two row variables, so keeping _r2_y2 alive is enough.

        // ===== MIDDLE COLUMN : state pill + PREV/NEXT =====
        // State pill, centred horizontally within the middle column. Compact.
        var _mid_cx = (_anim_mx1 + _anim_mx2) * 0.5;
        var _pill_w = 160;
        var _pill_x1 = _mid_cx - _pill_w * 0.5;
        var _pill_x2 = _mid_cx + _pill_w * 0.5;
        var _pill_y1 = _anim_y1 + 4;
        var _pill_y2 = _pill_y1 + 14;
        var _state_lbl = "";
        var _state_col = c_white;
        if (_v2.anim_playing) {
            _state_col = make_color_rgb(120, 255, 120);
            switch (_v2.anim_direction) {
                case "fwd":  _state_lbl = "PLAYING - FWD LOOP";   break;
                case "rev":  _state_lbl = "PLAYING - REV LOOP";   break;
                case "png":  _state_lbl = "PLAYING - PING-PONG";  break;
                case "once": _state_lbl = "PLAYING - ONCE";       break;
            }
        } else {
            _state_col = make_color_rgb(140, 140, 160);
            _state_lbl = "STOPPED";
        }
		var _reposx = 100;
		var _reposy = 55;
        draw_set_color(make_color_rgb(20, 20, 30));
        draw_rectangle(_pill_x1+_reposx, _pill_y1+_reposy, _pill_x2+_reposx, _pill_y2+_reposy, false);
        draw_set_color(_state_col);
        draw_rectangle(_pill_x1+_reposx, _pill_y1+_reposy, _pill_x2+_reposx, _pill_y2+_reposy, true);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text(_mid_cx+_reposx, ((_pill_y1 + _pill_y2) * 0.5)+_reposy, _state_lbl);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);

        // PREV / NEXT — narrow, centred under the pill. Compact.
        var _pn_w = 48;
        var _pn_gap = 3;
        var _pn_y1 = _pill_y2 -14;
        var _pn_y2 = _pn_y1 + 14;
        var _prev_x1 = _mid_cx - _pn_w - _pn_gap * 0.5;
        var _prev_x2 = _prev_x1 + _pn_w;
        var _next_x1 = _mid_cx + _pn_gap * 0.5;
        var _next_x2 = _next_x1 + _pn_w;

        var _prev_hov = point_in_rectangle(_mx, _my, _prev_x1, _pn_y1, _prev_x2, _pn_y2);
        draw_set_color(_prev_hov ? make_color_rgb(30, 50, 80) : make_color_rgb(20, 25, 40));
        draw_rectangle(_prev_x1, _pn_y1, _prev_x2, _pn_y2, false);
        draw_set_color(_prev_hov ? c_white : make_color_rgb(40, 40, 60));
        draw_rectangle(_prev_x1, _pn_y1, _prev_x2, _pn_y2, true);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text((_prev_x1 + _prev_x2) * 0.5, (_pn_y1 + _pn_y2) * 0.5, "< PREV");
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        if (_prev_hov && mouse_check_button_pressed(mb_left)
        && !global.ui_click_consumed && !global.any_picker_open) {
            scr_spred64_v2_anim_frame_goto(-1);
        }

        var _next_hov = point_in_rectangle(_mx, _my, _next_x1, _pn_y1, _next_x2, _pn_y2);
        draw_set_color(_next_hov ? make_color_rgb(30, 50, 80) : make_color_rgb(20, 25, 40));
        draw_rectangle(_next_x1, _pn_y1, _next_x2, _pn_y2, false);
        draw_set_color(_next_hov ? c_white : make_color_rgb(40, 40, 60));
        draw_rectangle(_next_x1, _pn_y1, _next_x2, _pn_y2, true);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text((_next_x1 + _next_x2) * 0.5, (_pn_y1 + _pn_y2) * 0.5, "NEXT >");
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        if (_next_hov && mouse_check_button_pressed(mb_left)
        && !global.ui_click_consumed && !global.any_picker_open) {
            scr_spred64_v2_anim_frame_goto(1);
        }

        // ===== RIGHT COLUMN : frame management (2x2 compact buttons) =====
        var _fm_btn_w = 58;
        var _fm_btn_h = 14;
        var _fm_gap_x = 3;
        var _fm_gap_y = 3;
        var _fm_grid_x = _anim_rx1 + (_anim_right_w - (_fm_btn_w * 2 + _fm_gap_x)) * 0.5;
        var _fm_grid_y = _anim_y1 + 4;
        // Definitions
        var _fm_btns = [
            { lbl:"+ NEW",   col:0, row:0, action:"new",    enabled:true,                              fill_idle:make_color_rgb(40, 90, 64),  fill_hov:make_color_rgb(60, 130, 90),  border:make_color_rgb(120, 220, 160) },
            { lbl:"DUP",     col:1, row:0, action:"dup",    enabled:(_frame_count_total > 0),          fill_idle:make_color_rgb(30, 40, 72),  fill_hov:make_color_rgb(50, 70, 120),  border:make_color_rgb(120, 160, 220) },
            { lbl:"CLEAR",   col:0, row:1, action:"clear",  enabled:(_frame_count_total > 0),          fill_idle:make_color_rgb(72, 56, 32),  fill_hov:make_color_rgb(120, 90, 50),  border:make_color_rgb(220, 180, 120) },
            { lbl:"DELETE",  col:1, row:1, action:"delete", enabled:(_frame_count_total > 1),          fill_idle:make_color_rgb(72, 24, 24),  fill_hov:make_color_rgb(140, 40, 40),  border:make_color_rgb(255, 100, 100) }
        ];
        for (var _fi = 0; _fi < array_length(_fm_btns); _fi++) {
            var _fb = _fm_btns[_fi];
            var _fbx1 = _fm_grid_x + _fb.col * (_fm_btn_w + _fm_gap_x);
            var _fbx2 = _fbx1 + _fm_btn_w;
            var _fby1 = _fm_grid_y + _fb.row * (_fm_btn_h + _fm_gap_y);
            var _fby2 = _fby1 + _fm_btn_h;
            var _fb_hov = _fb.enabled && point_in_rectangle(_mx, _my, _fbx1, _fby1, _fbx2, _fby2);
            // Fill
            if (!_fb.enabled) {
                draw_set_color(make_color_rgb(28, 28, 36));
            } else if (_fb_hov) {
                draw_set_color(_fb.fill_hov);
            } else {
                draw_set_color(_fb.fill_idle);
            }
            draw_rectangle(_fbx1, _fby1, _fbx2, _fby2, false);
            // Border
            if (!_fb.enabled) {
                draw_set_color(make_color_rgb(50, 50, 60));
            } else {
                draw_set_color(_fb.border);
            }
            draw_rectangle(_fbx1, _fby1, _fbx2, _fby2, true);
            // Label
            if (_fb.enabled) {
                draw_set_color(c_white);
            } else {
                draw_set_color(make_color_rgb(70, 70, 85));
            }
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text((_fbx1 + _fbx2) * 0.5, (_fby1 + _fby2) * 0.5, _fb.lbl);
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
            // Click
            if (_fb_hov && mouse_check_button_pressed(mb_left)
            && !global.ui_click_consumed && !global.any_picker_open) {
                switch (_fb.action) {
                    case "new":    scr_spred64_v2_anim_frame_new();    break;
                    case "dup":    scr_spred64_v2_anim_frame_dup();    break;
                    case "clear":  scr_spred64_v2_anim_frame_clear();  break;
                    case "delete": scr_spred64_v2_anim_frame_delete(); break;
                }
            }
        }

        // -------------------------------------------------------
        // COMPOSITOR (BOTTOM-RIGHT)
        // -------------------------------------------------------
        //   Top strip   : 8 layer buttons + frame readout
        //   Left column : D-pad + slot + expand + clear (controls)
        //   Right col   : 4x4 composited grid (gets the bulk of the space)
        var _comp      = _v2.compositor;
        var _cur_frame = _comp.frames[_comp.active_frame];

        // ----- TOP STRIP : LAYER BUTTONS + FRAME READOUT -----
        var _ts_h      = 22;
        var _ts_y1     = _rsv_y1 + 10;
        var _ts_y2     = _ts_y1 + _ts_h;
        var _lyr_btn_w = 36;
        var _lyr_btn_g = 2;
        var _lyr_x     = _rsv_x1 + 8;

        draw_set_font(fnt_c64_tiny);
        for (var _ly = 0; _ly < 8; _ly++) {
            var _lbx1 = _lyr_x + _ly * (_lyr_btn_w + _lyr_btn_g);
            var _lbx2 = _lbx1 + _lyr_btn_w;
            var _ly_is_active = (_comp.active_layer == _ly);
            var _ly_hov       = point_in_rectangle(_mx, _my, _lbx1, _ts_y1, _lbx2, _ts_y2);

            if (_ly == 0) {
                draw_set_color(_ly_is_active
                    ? make_color_rgb(120, 80, 30)
                    : (_ly_hov ? make_color_rgb(70, 50, 20) : make_color_rgb(40, 30, 15)));
            } else {
                draw_set_color(_ly_is_active
                    ? make_color_rgb(40, 90, 140)
                    : (_ly_hov ? make_color_rgb(30, 50, 80) : make_color_rgb(20, 25, 40)));
            }
            draw_rectangle(_lbx1, _ts_y1, _lbx2, _ts_y2, false);

            if (_ly_is_active) {
                draw_set_color(make_color_rgb(255, 220, 120));
                draw_rectangle(_lbx1,     _ts_y1,     _lbx2,     _ts_y2,     true);
                draw_rectangle(_lbx1 + 1, _ts_y1 + 1, _lbx2 - 1, _ts_y2 - 1, true);
            } else if (_ly_hov) {
                draw_set_color(c_white);
                draw_rectangle(_lbx1, _ts_y1, _lbx2, _ts_y2, true);
            } else {
                draw_set_color(make_color_rgb(40, 40, 60));
                draw_rectangle(_lbx1, _ts_y1, _lbx2, _ts_y2, true);
            }

            draw_set_color(c_white);
            draw_set_halign(fa_center);
            var _lbl = (_ly == 0) ? "BASE" : ("L" + string(_ly));
            draw_text(_lbx1 + _lyr_btn_w * 0.5, _ts_y1 + 2, _lbl);
            draw_set_halign(fa_left);

            if (_ly_hov && mouse_check_button_pressed(mb_left)
            && !global.ui_click_consumed && !global.any_picker_open) {
                _comp.active_layer = _ly;
                // Preserve the anchor (row, col) across layer switches.
                // Try the existing anchor first — that's the position
                // the user last selected on the grid. Only fall back to
                // hover if no anchor has ever been set (first interaction).
                var _ls_row = _v2.comp_anchor_row;
                var _ls_col = _v2.comp_anchor_col;
                if (_ls_row < 0 || _ls_col < 0) {
                    _ls_row = _v2.comp_hover_row;
                    _ls_col = _v2.comp_hover_col;
                }
                if (_ls_row >= 0 && _ls_col >= 0) {
                    _comp.active_cell = scr_spred64_v2_compositor_find_cell(
                        _cur_frame, _ly, _ls_row, _ls_col);
                    // active_cell may be -1 here if the new layer has no
                    // cell at this position — that's fine. The anchor
                    // (comp_anchor_row/col) stays set, so COMP view and
                    // pan can still target this position.
                } else {
                    _comp.active_cell = -1;
                }
            }
        }

        var _fr_x = _lyr_x + 8 * (_lyr_btn_w + _lyr_btn_g) + 50;
        draw_set_color(make_color_rgb(160, 160, 200));
        draw_text(_fr_x, _ts_y1 + 8,
            "FRAME " + string(_comp.active_frame+1)
            + " / " + string(array_length(_comp.frames)));

        // ----- HORIZONTAL SPLIT : LEFT CONTROLS / RIGHT GRID -----
        var _ctrl_w   = 90;
        var _ctrl_x1  = _rsv_x1 + 8;
        var _ctrl_x2  = _ctrl_x1 + _ctrl_w;
        var _ctrl_y1  = _ts_y2 + 8;
        var _ctrl_y2  = _rsv_y2 - 8;

        var _grid_x1  = _ctrl_x2 + 8;
        var _grid_x2  = _rsv_x2 - 8;
        var _grid_y1  = _ctrl_y1;
        var _grid_y2  = _ctrl_y2;

        // Need _has_active_cell for the controls column
        var _has_active_cell = (_comp.active_cell >= 0
                             && _comp.active_cell < array_length(_cur_frame.cells));

		// -------- COMPOSITOR GRID (RIGHT, 4x4) --------
        // Tight packing: cells touch with only a 1px faint divider between
        // them, like a real composite sprite layout rather than a grid of
        // separate panels.
        var _grid_w_av = _grid_x2 - _grid_x1;
        var _grid_h_av = _grid_y2 - _grid_y1;
        var _grid_gap  = 1;
        var _cell_max_w = floor((_grid_w_av - _grid_gap * 5) / 4);
        var _cell_max_h = floor((_grid_h_av - _grid_gap * 5) / 4);
        // Source preview is 48x42; integer scale
        var _cell_scale = min(floor(_cell_max_w / 48), floor(_cell_max_h / 42));
        if (_cell_scale < 1) _cell_scale = 1;
        // Double the rendered cell size — _cell_scale stays the same so that
        // sprite scaling, offsets, and expand maths in pass 2 (which multiply
        // by _cell_scale) keep their original step granularity; only the
        // visual footprint grows. Cells may overflow the available area at
        // smaller viewport widths, which is fine.
        var _gc_w = 48 * _cell_scale ;
        var _gc_h = 42 * _cell_scale ;
        var _gtot_w = 4 * _gc_w + 5 * _grid_gap;
        var _gtot_h = 4 * _gc_h + 5 * _grid_gap;
        var _gox = _grid_x1 + floor((_grid_w_av - _gtot_w) * 0.5);
        var _goy = _grid_y1 + floor((_grid_h_av - _gtot_h) * 0.5);

        _v2.comp_hover_layer = -1;
        _v2.comp_hover_row   = -1;
        _v2.comp_hover_col   = -1;

        // -------- PASS 1: GLOBAL BACKGROUND + DIVIDERS + HOVER TRACKING --------
        // Single full-area BG fill, matching how the real C64 renders the
        // screen background once and lets sprites composite on top.
        // Sprites are rendered with transparent zero-bit pixels in pass 2,
        // so this colour shows through anywhere a sprite isn't.
        var _grid_area_x1 = _gox + _grid_gap;
        var _grid_area_y1 = _goy + _grid_gap;
        var _grid_area_x2 = _grid_area_x1 + 4 * _gc_w + 3 * _grid_gap;
        var _grid_area_y2 = _grid_area_y1 + 4 * _gc_h + 3 * _grid_gap;
        draw_set_color(scr_c64_pepto_colour(_v2.bg_col));
        draw_rectangle(_grid_area_x1, _grid_area_y1,
                       _grid_area_x2, _grid_area_y2, false);
        // Faint dividers: 1px lines on top of the BG fill, at the gap
        // positions between cells. These read as subtle gridlines no matter
        // what the C64 BG colour is, so the 4x4 structure is always legible.
		gpu_set_tex_filter(true);
        draw_set_alpha(0.25);
        draw_set_color(make_color_rgb(180, 180, 200));
        for (var _di = 1; _di < 4; _di++) {
            // Vertical divider after column (_di - 1)
            var _vd_x = _grid_area_x1 + _di * _gc_w + (_di - 1) * _grid_gap;
            draw_line_width(_vd_x, _grid_area_y1, _vd_x, _grid_area_y2, 3);
            // Horizontal divider after row (_di - 1)
            var _hd_y = _grid_area_y1 + _di * _gc_h + (_di - 1) * _grid_gap;
            draw_line_width(_grid_area_x1, _hd_y, _grid_area_x2, _hd_y, 3);
        }
        draw_set_alpha(1.0);

        for (var _gr = 0; _gr < 4; _gr++) {
            for (var _gc = 0; _gc < 4; _gc++) {
                var _gx1 = _gox + _grid_gap + _gc * (_gc_w + _grid_gap);
                var _gy1 = _goy + _grid_gap + _gr * (_gc_h + _grid_gap);
                var _gx2 = _gx1 + _gc_w;
                var _gy2 = _gy1 + _gc_h;
                if (point_in_rectangle(_mx, _my, _gx1, _gy1, _gx2, _gy2)) {
                    _v2.comp_hover_row = _gr;
                    _v2.comp_hover_col = _gc;
                }
            }
        }

        // -------- MOUSE-WHEEL LAYER CYCLING --------
        // While the cursor is over the compositor grid, the wheel steps the
        // active layer: up toward L7, down toward BASE (L0), clamped at both
        // ends. Switching layer re-resolves active_cell at the anchor cell
        // (comp_anchor_*, else the current hover) so the controls column and
        // brackets follow — mirrors the layer-button click behaviour.
        var _wheel_over_grid = (_v2.comp_hover_row >= 0 && _v2.comp_hover_col >= 0);
        if (_wheel_over_grid && !global.any_picker_open) {
            var _wheel_dir = 0;
            if (mouse_wheel_up())   { _wheel_dir = 1; }
            if (mouse_wheel_down()) { _wheel_dir = -1; }
            if (_wheel_dir != 0) {
                var _wheel_new = clamp(_comp.active_layer + _wheel_dir, 0, 7);
                if (_wheel_new != _comp.active_layer) {
                    _comp.active_layer = _wheel_new;
                    // Re-resolve the active cell at the anchor (or hover if
                    // no anchor set yet) on the newly-selected layer.
                    var _wl_row = _v2.comp_anchor_row;
                    var _wl_col = _v2.comp_anchor_col;
                    if (_wl_row < 0 || _wl_col < 0) {
                        _wl_row = _v2.comp_hover_row;
                        _wl_col = _v2.comp_hover_col;
                    }
                    if (_wl_row >= 0 && _wl_col >= 0) {
                        _comp.active_cell = scr_spred64_v2_compositor_find_cell(
                            _cur_frame, _comp.active_layer, _wl_row, _wl_col);
                    } else {
                        _comp.active_cell = -1;
                    }
                }
            }
        }

        // -------- PASS 2: LAYER CONTENT, BORDERS, CLICKS --------
        for (var _gr = 0; _gr < 4; _gr++) {
            for (var _gc = 0; _gc < 4; _gc++) {
                var _gx1 = _gox + _grid_gap + _gc * (_gc_w + _grid_gap);
                var _gy1 = _goy + _grid_gap + _gr * (_gc_h + _grid_gap);
                var _gx2 = _gx1 + _gc_w;
                var _gy2 = _gy1 + _gc_h;

                var _gc_hov = point_in_rectangle(_mx, _my, _gx1, _gy1, _gx2, _gy2);

                var _cells = _cur_frame.cells;
                for (var _layer_draw = 0; _layer_draw < 8; _layer_draw++) {
                    for (var _ci = 0; _ci < array_length(_cells); _ci++) {
                        var _cd = _cells[_ci];
                        if (_cd.layer == _layer_draw
                        &&  _cd.row   == _gr
                        &&  _cd.col   == _gc) {
                            if (variable_struct_exists(_asset.meta, "spr_sprites")
                            &&  _cd.slot >= 0
                            &&  _cd.slot < array_length(_asset.meta.spr_sprites)
                            &&  _asset.meta.spr_sprites[_cd.slot] != -1
                            &&  sprite_exists(_asset.meta.spr_sprites[_cd.slot])) {
                                // Sprite scale = _cell_scale * 2 (cached sprite is
                                // 48x42 = 2x the C64 native 24x21).
                                var _base_scale = _cell_scale ;
                                var _sx = _base_scale;
                                var _sy = _base_scale;
                                if (_cd.expand == "x" || _cd.expand == "both") {
                                    _sx = _base_scale * 2;
                                }
                                if (_cd.expand == "y" || _cd.expand == "both") {
                                    _sy = _base_scale * 2;
                                }
                                // XO/YO are stored in native C64 pixels. On the
                                // grid a native pixel renders at _cell_scale * 2
                                // screen px (source is 48x42 = 2x native, drawn
                                // at _cell_scale), so each offset unit must move
                                // by _base_scale * 2 to visually match one
                                // on-screen pixel step.
                                var _pixel_step = _base_scale * 2;
                               var _draw_x = _gx1 + _cd.xo * _pixel_step;
                                var _draw_y = _gy1 + _cd.yo * _pixel_step;
                                // Y-expanded (and BOTH) sprites sit one
                                // screen pixel high relative to the
                                // unexpanded ones in the grid render —
                                // nudge them down by 1 to line up.
                                if (_cd.expand == "y" || _cd.expand == "both") {
                                    _draw_y = _draw_y + 1;
                                }
                                gpu_set_tex_filter(false);
                                draw_sprite_ext(_asset.meta.spr_sprites[_cd.slot], 0,
                                    _draw_x, _draw_y, _sx, _sy,
                                    0, c_white, 1);
									gpu_set_tex_filter(true);
                            }
                        }
                    }
                }

                var _layer_cell_idx = scr_spred64_v2_compositor_find_cell(
                    _cur_frame, _comp.active_layer, _gr, _gc);
                var _has_layer_cell = (_layer_cell_idx >= 0);

                // Selection states use L-shaped corner brackets (12px arms),
                // less visually heavy than a full border and don't obscure
                // sprite content at the cell edges.
                //   active        — yellow brackets, doubled
                //   has-layer     — orange brackets, single
                //   hover (idle)  — full white outline (kept as before)
                //   empty         — nothing
                //
                // ALL bracket / hover overlays are suppressed while the
                // animation is playing — gives a clean playback view
                // without the editor's "what's placed" markers cluttering it.
                if (!_v2.anim_playing) {
                    var _is_active = (_has_layer_cell && _comp.active_cell == _layer_cell_idx);
                    if (_is_active) {
                        draw_set_color(make_color_rgb(255, 220, 120));
                        scr_spred64_v2_draw_corners(_gx1, _gy1, _gx2, _gy2, 12, 2);
                    } else if (_has_layer_cell) {
                        draw_set_color(make_color_rgb(220, 120, 40));
                        scr_spred64_v2_draw_corners(_gx1, _gy1, _gx2, _gy2, 12, 1);
                    } else if (_gc_hov) {
                        draw_set_color(c_white);
                        draw_rectangle(_gx1, _gy1, _gx2, _gy2, true);
                    }
                }

                if (_gc_hov && !global.ui_click_consumed && !global.any_picker_open) {
                    if (mouse_check_button_pressed(mb_left)) {
                        // Clicking a grid cell always updates the anchor
                        // to this (row, col), so subsequent layer switches
                        // stay locked here.
                        _v2.comp_anchor_row = _gr;
                        _v2.comp_anchor_col = _gc;
                        if (_has_layer_cell) {
                            _comp.active_cell = _layer_cell_idx;
                        } else {
                            _comp.active_cell = scr_spred64_v2_compositor_set_cell(
                                _cur_frame, _comp.active_layer, _gr, _gc,
                                _v2.selected_slot);
                            _v2.dirty = true;
                        }
                    }
                    if (mouse_check_button_pressed(mb_right) && _has_layer_cell) {
                        scr_spred64_v2_compositor_clear_cell(
                            _cur_frame, _comp.active_layer, _gr, _gc);
                        _comp.active_cell = -1;
                        _v2.dirty = true;
                    }
                }
            }
        }

        // Re-check active cell validity after the grid pass
        _has_active_cell = (_comp.active_cell >= 0
                         && _comp.active_cell < array_length(_cur_frame.cells));

        // -------- FLOATING PIXEL-PLACEMENT MARKER --------
        // While hovering the sprite canvas, float a flashing black/white
        // rectangle over the matching pixel position on the compositor
        // grid, sized to the stretched-pixel shape (2x wide for X-expand,
        // 2x tall for Y-expand). Shows exactly where the pixel under the
        // cursor lands in the composite, at its real on-screen footprint.
        //
        // The marker is drawn on the ANCHOR cell — the (row, col) the
        // canvas is currently showing. In COMP-OFF the canvas shows the
        // selected slot's bits directly, so we anchor to the cell where
        // that slot is placed on the active layer (if any). In COMP-ON the
        // canvas is anchored to comp_anchor_row/col, so we use that.
        //
        // A cell must exist to anchor to; without one there's no grid
        // position to map the pixel onto, so the marker is suppressed.
        if (_v2.canvas_pix_hover && !_v2.anim_playing) {

            // Resolve the anchor (row, col) to draw the marker on. This is
            // the SELECTED compositor tile — comp_anchor_row/col, the cell
            // the user last clicked (the one the yellow brackets mark). It
            // persists across layer switches, so the marker follows the
            // user's chosen tile rather than jumping to wherever the slot
            // first appears in the cell array. Same source in both COMP-OFF
            // and COMP-ON.
            var _mk_row    = _v2.comp_anchor_row;
            var _mk_col    = _v2.comp_anchor_col;
            var _mk_expand = "none";

            // Fall back to the active cell's position if no anchor has been
            // set yet (user opened V2 and hovered the canvas before ever
            // clicking a grid cell).
            if ((_mk_row < 0 || _mk_col < 0) && _has_active_cell) {
                var _mk_ac_fb = _cur_frame.cells[_comp.active_cell];
                _mk_row = _mk_ac_fb.row;
                _mk_col = _mk_ac_fb.col;
            }

            // Expand footprint: if the slot currently being edited
            // (selected_slot) is placed at the marker's cell on ANY layer
            // and that placement is expanded, the marker takes that expand
            // shape. Layer-independent — what matters is that the sprite
            // under the pixel canvas has an expanded placement at this cell,
            // so the cursor reflects the fat-pixel footprint it'll paint
            // into. First matching placement wins.
            if (_mk_row >= 0 && _mk_col >= 0) {
                for (var _mk_ei = 0; _mk_ei < array_length(_cur_frame.cells); _mk_ei++) {
                    var _mk_ec = _cur_frame.cells[_mk_ei];
                    if (_mk_ec.row  == _mk_row
                    &&  _mk_ec.col  == _mk_col
                    &&  _mk_ec.slot == _v2.selected_slot) {
                        _mk_expand = _mk_ec.expand;
                        break;
                    }
                }
            }

            if (_mk_row >= 0 && _mk_col >= 0 && _mk_row < 4 && _mk_col < 4) {
                // Grid cell top-left in screen space (mirrors pass 2 maths).
                var _mk_gx1 = _gox + _grid_gap + _mk_col * (_gc_w + _grid_gap);
                var _mk_gy1 = _goy + _grid_gap + _mk_row * (_gc_h + _grid_gap);

                // One C64 native pixel = _cell_scale * 2 screen px on the
                // grid: the cached sprite is 48x42 (2x native) drawn at
                // _cell_scale, so each native pixel spans two grid px.
                var _mk_step = _cell_scale * 2;

                // Fat-pixel footprint. X-expand doubles width, Y-expand
                // doubles height. MC pixels are already 2 native px wide;
                // fold that into the width so the marker matches the pair.
                var _mk_w = _mk_step;
                var _mk_h = _mk_step;
                if (_is_mc) { _mk_w = _mk_step * 2; }
                if (_mk_expand == "x" || _mk_expand == "both") { _mk_w *= 2; }
                if (_mk_expand == "y" || _mk_expand == "both") { _mk_h *= 2; }

                // Pixel position within the cell — canvas_pix_x/y are in
                // native sprite pixels; scale to grid px. Expanded axes
                // also stretch the *position*, since every pixel before
                // this one is twice as wide/tall too.
                var _mk_px_step_x = _mk_step;
                var _mk_px_step_y = _mk_step;
                if (_mk_expand == "x" || _mk_expand == "both") { _mk_px_step_x = _mk_step * 2; }
                if (_mk_expand == "y" || _mk_expand == "both") { _mk_px_step_y = _mk_step * 2; }

                var _mk_x1 = _mk_gx1 + _v2.canvas_pix_x * _mk_px_step_x;
                var _mk_y1 = _mk_gy1 + _v2.canvas_pix_y * _mk_px_step_y;
                var _mk_x2 = _mk_x1 + _mk_w;
                var _mk_y2 = _mk_y1 + _mk_h;

                // Resolve the current paint colour — same mapping the
                // line-tool preview uses. MC mode keys off active_colour
                // (MC1/MC2/UC); HR mode always paints the slot's UC pen.
                var _mk_paint_idx = 0;
                if (_is_mc) {
                    switch (_v2.active_colour) {
                        case 1:  _mk_paint_idx = _v2.mc1_col;          break;
                        case 2:  _mk_paint_idx = _v2.mc2_col;          break;
                        case 3:  _mk_paint_idx = _v2.sprite_uc[_slot]; break;
                        default: _mk_paint_idx = _v2.bg_col;           break;
                    }
                } else {
                    _mk_paint_idx = _v2.sprite_uc[_slot];
                }
                var _mk_paint_col = scr_c64_pepto_colour(_mk_paint_idx);

                // Flash on a ~4Hz cycle.
                //   Phase 1 (on)  — hollow double outline: white inner,
                //                   black outer. No fill, so the sprite
                //                   underneath shows through and the marker
                //                   never reads as "paint black here".
                //   Phase 2 (off) — solid fill in the current paint colour,
                //                   so you see exactly what will land.
                var _mk_on = ((current_time div 125) mod 2) == 0;
                if (_mk_on) {
                    // Outer black ring, then inner white ring one px inside.
                    draw_set_color(c_black);
                    draw_rectangle(_mk_x1, _mk_y1, _mk_x2, _mk_y2, true);
                    draw_set_color(c_white);
                    draw_rectangle(_mk_x1 + 1, _mk_y1 + 1, _mk_x2 - 1, _mk_y2 - 1, true);
                } else {
                    draw_set_color(_mk_paint_col);
                    draw_rectangle(_mk_x1, _mk_y1, _mk_x2, _mk_y2, false);
                }
            }
        }

        // -------- LEFT CONTROLS COLUMN --------
        // Background panel for the controls column
        draw_set_color(make_color_rgb(14, 14, 22));
        draw_rectangle(_ctrl_x1, _ctrl_y1, _ctrl_x2, _ctrl_y2, false);
        draw_set_color(make_color_rgb(40, 30, 15));
        draw_rectangle(_ctrl_x1, _ctrl_y1, _ctrl_x2, _ctrl_y2, true);

        if (_has_active_cell) {
            var _ac = _cur_frame.cells[_comp.active_cell];

            // ----- D-PAD (top of left column) -----
            // Classic plus shape: UP / DN / LF / RT / RST (centre).
            // 3 buttons + 2 gaps = 76px wide, fits within 90px column.
            var _dpad_btn = 24;
            var _dpad_gap = 2;
            var _dpad_total = _dpad_btn * 3 + _dpad_gap * 2;
            var _dpad_x = _ctrl_x1 + floor(((_ctrl_x2 - _ctrl_x1) - _dpad_total) * 0.5);
            var _dpad_y = _ctrl_y1 + 8;

            // Label
            draw_set_color(make_color_rgb(160, 160, 200));
            draw_set_halign(fa_center);
            draw_text((_ctrl_x1 + _ctrl_x2) * 0.5, _dpad_y-4, "OFFSET");
            draw_set_halign(fa_left);
            _dpad_y += 14;

            // Helper: draw a D-pad button. Returns true if clicked this frame.
            // (Inline — keeps the patch self-contained, no new script.)
            var _dpad_btns = [
                { col:1, row:0, lbl:"UP",  dx: 0, dy:-1, is_reset:false },
                { col:0, row:1, lbl:"LF",  dx:-1, dy: 0, is_reset:false },
                { col:1, row:1, lbl:"RST", dx: 0, dy: 0, is_reset:true  },
                { col:2, row:1, lbl:"RT",  dx: 1, dy: 0, is_reset:false },
                { col:1, row:2, lbl:"DN",  dx: 0, dy: 1, is_reset:false }
            ];
            for (var _di = 0; _di < array_length(_dpad_btns); _di++) {
                var _db   = _dpad_btns[_di];
                var _dbx1 = _dpad_x + _db.col * (_dpad_btn + _dpad_gap);
                var _dby1 = _dpad_y + _db.row * (_dpad_btn + _dpad_gap);
                var _dbx2 = _dbx1 + _dpad_btn;
                var _dby2 = _dby1 + _dpad_btn;
                var _db_hov = point_in_rectangle(_mx, _my, _dbx1, _dby1, _dbx2, _dby2);

                if (_db.is_reset) {
                    draw_set_color(_db_hov ? make_color_rgb(160, 40, 40) : make_color_rgb(80, 20, 20));
                } else {
                    draw_set_color(_db_hov ? make_color_rgb(60, 100, 160) : make_color_rgb(30, 50, 80));
                }
                draw_rectangle(_dbx1, _dby1, _dbx2, _dby2, false);
                draw_set_color(c_white);
                draw_rectangle(_dbx1, _dby1, _dbx2, _dby2, true);
                draw_set_halign(fa_center);
                draw_set_valign(fa_middle);
                draw_text((_dbx1 + _dbx2) * 0.5, (_dby1 + _dby2) * 0.5, _db.lbl);
                draw_set_halign(fa_left);
                draw_set_valign(fa_top);

                if (_db_hov && mouse_check_button_pressed(mb_left)
                && !global.ui_click_consumed && !global.any_picker_open) {
                    if (_db.is_reset) {
                        _ac.xo = 0;
                        _ac.yo = 0;
                    } else {
                        _ac.xo = _ac.xo + _db.dx;
                        _ac.yo = _ac.yo + _db.dy;
                    }
                    _v2.dirty = true;
                }
            }

            // Offset readout under the D-pad
            var _readout_y = _dpad_y + 3 * _dpad_btn + 2 * _dpad_gap + 6;
            draw_set_color(make_color_rgb(180, 180, 220));
            draw_set_halign(fa_center);
            draw_text((_ctrl_x1 + _ctrl_x2) * 0.5, _readout_y,
                "XO: " + string(_ac.xo) + "   YO: " + string(_ac.yo));
            draw_set_halign(fa_left);

// ----- VERTICAL BUTTON STACK -----
            // Single column: EXPAND toggle group (NONE/X/Y/BOTH), CLEAR
            // action, then FX placeholders (FLIPX/FLIPY/ROT90). The expand
            // group behaves as a radio set; CLEAR is a one-shot action;
            // FX entries are greyed and non-clickable until phase 2 FX work.
            var _stk_y    = _readout_y + 18;
            var _stk_x1   = _ctrl_x1 + 6;
            var _stk_x2   = _ctrl_x2 - 6;
            var _stk_btn_h = 20;
            var _stk_gap   = 2;

            // Definition list — kind tells the per-button code what to do:
            //   "exp"     : expand toggle, value in op
            //   "clear"   : clear-cell action
            //   "fx_todo" : placeholder, greyed, non-interactive
            // EXPAND toggle group only — CLEAR is rendered separately,
            // anchored to the bottom of the controls column.
            var _stk = [
                { kind:"exp", lbl:"NONE", op:"none" },
                { kind:"exp", lbl:"X",    op:"x"    },
                { kind:"exp", lbl:"Y",    op:"y"    },
                { kind:"exp", lbl:"BOTH", op:"both" }
            ];

            for (var _bi = 0; _bi < array_length(_stk); _bi++) {
                var _b   = _stk[_bi];
                var _by1 = _stk_y + _bi * (_stk_btn_h + _stk_gap);
                var _by2 = _by1 + _stk_btn_h;
                var _b_hov = point_in_rectangle(_mx, _my, _stk_x1, _by1, _stk_x2, _by2);

                // Fill colour by kind / state
                if (_b.kind == "exp") {
                    var _eb_is_active = (_ac.expand == _b.op);
                    if (_eb_is_active) {
                        draw_set_color(make_color_rgb(40, 90, 140));
                    } else if (_b_hov) {
                        draw_set_color(make_color_rgb(30, 50, 80));
                    } else {
                        draw_set_color(make_color_rgb(20, 25, 40));
                    }
                } else if (_b.kind == "clear") {
                    if (_b_hov) {
                        draw_set_color(make_color_rgb(160, 40, 40));
                    } else {
                        draw_set_color(make_color_rgb(80, 20, 20));
                    }
                } else {
                    // fx_todo — greyed, no hover response
                    draw_set_color(make_color_rgb(30, 30, 38));
                }
                draw_rectangle(_stk_x1, _by1, _stk_x2, _by2, false);

                // Border
                if (_b.kind == "exp") {
                    var _eb_is_active2 = (_ac.expand == _b.op);
                    if (_eb_is_active2) {
                        draw_set_color(make_color_rgb(120, 255, 120));
                        draw_rectangle(_stk_x1,     _by1,     _stk_x2,     _by2,     true);
                        draw_rectangle(_stk_x1 + 1, _by1 + 1, _stk_x2 - 1, _by2 - 1, true);
                    } else if (_b_hov) {
                        draw_set_color(c_white);
                        draw_rectangle(_stk_x1, _by1, _stk_x2, _by2, true);
                    } else {
                        draw_set_color(make_color_rgb(40, 40, 60));
                        draw_rectangle(_stk_x1, _by1, _stk_x2, _by2, true);
                    }
                } else if (_b.kind == "clear") {
                    draw_set_color(c_white);
                    draw_rectangle(_stk_x1, _by1, _stk_x2, _by2, true);
                } else {
                    // fx_todo
                    draw_set_color(make_color_rgb(50, 50, 60));
                    draw_rectangle(_stk_x1, _by1, _stk_x2, _by2, true);
                }

                // Label
                if (_b.kind == "fx_todo") {
                    draw_set_color(make_color_rgb(80, 80, 95));
                } else {
                    draw_set_color(c_white);
                }
                draw_set_halign(fa_center);
                draw_set_valign(fa_middle);
                draw_text((_stk_x1 + _stk_x2) * 0.5, (_by1 + _by2) * 0.5, _b.lbl);
                draw_set_halign(fa_left);
                draw_set_valign(fa_top);

                // Click handling — fx_todo deliberately ignored
                if (_b_hov && mouse_check_button_pressed(mb_left)
                && !global.ui_click_consumed && !global.any_picker_open) {
                    if (_b.kind == "exp") {
                        _ac.expand = _b.op;
                        _v2.dirty = true;
                    }
                    // fx_todo: no-op (placeholder until phase 2 FX work)
                }
            }

            // ----- CLEAR CELL BUTTON (bottom-anchored) -----
            // Separated from the EXPAND toggle group, pinned to the
            // bottom of the controls column so it's spatially distinct
            // and harder to misclick when adjusting expand state.
            var _clr_btn_h = _stk_btn_h + 4;
            var _clr_x1 = _stk_x1;
            var _clr_x2 = _stk_x2;
            var _clr_y1 = _ctrl_y2 - _clr_btn_h - 6;
            var _clr_y2 = _clr_y1 + _clr_btn_h;
            var _clr_hov = point_in_rectangle(_mx, _my, _clr_x1, _clr_y1, _clr_x2, _clr_y2);
            // Fill — red for destructive
            if (_clr_hov) {
                draw_set_color(make_color_rgb(160, 40, 40));
            } else {
                draw_set_color(make_color_rgb(80, 20, 20));
            }
            draw_rectangle(_clr_x1, _clr_y1, _clr_x2, _clr_y2, false);
            // Border
            draw_set_color(make_color_rgb(255, 80, 80));
            draw_rectangle(_clr_x1, _clr_y1, _clr_x2, _clr_y2, true);
            // Label
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text((_clr_x1 + _clr_x2) * 0.5, (_clr_y1 + _clr_y2) * 0.5, "CLEAR");
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
            // Click
            if (_clr_hov && mouse_check_button_pressed(mb_left)
            && !global.ui_click_consumed && !global.any_picker_open) {
                scr_spred64_v2_compositor_clear_cell(
                    _cur_frame, _ac.layer, _ac.row, _ac.col);
                _comp.active_cell = -1;
                _v2.dirty = true;
            }
        } else {
            // No active cell — show a prompt centred in the controls column
			
            draw_set_color(make_color_rgb(100, 100, 120));
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            var _ph_cx = (_ctrl_x1 + _ctrl_x2) * 0.5;
            var _ph_cy = (_ctrl_y1 + _ctrl_y2) * 0.5;
            draw_text(_ph_cx, _ph_cy - 16, "CLICK A GRID");
            draw_text(_ph_cx, _ph_cy + 0,  "CELL TO PLACE");
            draw_text(_ph_cx, _ph_cy + 16, "SLOT "+ string(_v2.selected_slot));
			draw_text(_ph_cx, _ph_cy + 32, " ON LAYER " + string(_comp.active_layer));
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
        }
    }
	
}