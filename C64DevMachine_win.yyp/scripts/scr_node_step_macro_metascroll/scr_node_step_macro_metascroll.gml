/// @desc Step MACRO_METASCROLL node - pickers, toggles, and the JSR drops
function scr_node_step_macro_metascroll(_draw_x) {

    if (!mouse_check_button_pressed(mb_left)) return;
    if (global.ui_click_consumed) return;
    if (global.any_picker_open) return;

    // Row geometry - must match scr_node_draw_macro_metascroll exactly.
    // The font is set here too, because the value column is measured from the
    // widest label and string_width reports against whatever font is current.
    draw_set_font(fnt_c64_tiny);
    var _lh  = 12;
    var _ly0 = y + 24 + 4;
    var _rx  = _draw_x + width - 8;
    var _vx  = _draw_x + 8 + string_width("BLANK CH:") + 8;

    // ── The five JSR entry names (rows 10-12) ─────────────
    // The draw event records where each one landed; clicking one drops a
    // ready-made JSR node beside this one, the way the JOYSTICK macro drops
    // its direction labels.
    for (var _ei = 0; _ei < array_length(msc_entry_rects); _ei++) {
        var _er = msc_entry_rects[_ei];
        if (point_in_rectangle(mouse_x, mouse_y, _er[0], _er[1], _er[2], _er[3])) {
            scr_msc_drop_jsr(_er[4]);
            exit;
        }
    }

    // ── ROW 0 - TILESET PICKER ────────────────────────────
    var _ts_ly = _ly0;
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _ts_ly - 2, _rx, _ts_ly + 12)) {
        with (obj_asset_manager) {
            metamap_picker_open       = true;
            metamap_picker_node       = other.id;
            metamap_picker_hover      = -1;
            metamap_picker_name_idx   = 1;
            metamap_picker_mapidx_idx = 2;
        }
        exit;
    }

    // ── ROW 1 - MAP INDEX: left half steps back, right half steps on ──
    var _mi_ly  = _ly0 + _lh;
    var _mi_x2  = _vx + 48;
    var _mi_mid = _vx + 24;
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _mi_ly - 2, _mi_x2, _mi_ly + 12)) {

        // Resolve map_count so the step can clamp
        var _map_count = 0;
        var _tn = "";
        if (array_length(instructions[0]) > 1) _tn = string(instructions[0][1]);
        if (_tn != "" && instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = ds_list_find_value(_am.asset_list, _ai);
                if (_a.type == "META_TILESET" && _a.name == _tn) {
                    if (variable_struct_exists(_a.meta, "map_count")) _map_count = _a.meta.map_count;
                    break;
                }
            }
        }
        var _max_idx = max(0, _map_count - 1);
        var _cur     = 0;
        if (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) _cur = real(instructions[0][2]);

        if (mouse_x < _mi_mid) {
            instructions[0][2] = max(0, _cur - 1);
        } else {
            instructions[0][2] = min(_max_idx, _cur + 1);
        }
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }

    // ── ROW 2 - PLANE BASE ADDRESS (hex input) ────────────
    var _ba_ly = _ly0 + _lh * 2;
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _ba_ly - 2, _rx, _ba_ly + 12)) {
        var _ba_cur = 0x4000;
        if (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) _ba_cur = real(instructions[0][3]);
        var _ba_hex = string_upper(decimal_to_hex(_ba_cur));
        while (string_length(_ba_hex) < 4) _ba_hex = "0" + _ba_hex;
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 3;
        obj_workspace_manager.current_input_string = _ba_hex;
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        exit;
    }

    // ── ROW 4 - ZP BASE (hex input) ───────────────────────
    var _zp_ly = _ly0 + _lh * 4;
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _zp_ly - 2, _vx + 40, _zp_ly + 12)) {
        var _zp_cur = 0x60;
        if (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) _zp_cur = real(instructions[0][4]);
        var _zp_hex = string_upper(decimal_to_hex(_zp_cur));
        while (string_length(_zp_hex) < 2) _zp_hex = "0" + _zp_hex;
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 4;
        obj_workspace_manager.current_input_string = _zp_hex;
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        exit;
    }

    // ── ROW 5 - COLOUR MODE toggle, and the fixed nibble ──
    var _cm_ly = _ly0 + _lh * 5;
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _cm_ly - 2, _vx + 64, _cm_ly + 12)) {
        // Two modes only: 0 FIXED (stock C64) and 2 SHIFT C64U (turbo).
        // The old mode 1 (2-frame SHIFT) is gone - it always wore one frame
        // in eight of the neighbour's colour, whatever the CPU speed. A
        // project saved with it toggles straight to SHIFT C64U from FIXED.
        var _cm_cur = 0;
        if (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) _cm_cur = real(instructions[0][6]);
        if (_cm_cur == 2) {
            _cm_cur = 0;
        } else {
            _cm_cur = 2;
        }
        instructions[0][6] = _cm_cur;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    // right-hand value: cycles the FIXED nibble, -1 (auto) then 0..15
    if (point_in_rectangle(mouse_x, mouse_y, _rx - 60, _cm_ly - 2, _rx, _cm_ly + 12)) {
        var _cm_now = 0;
        if (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) _cm_now = real(instructions[0][6]);
        if (_cm_now == 0) {
            var _fc_cur = -1;
            if (array_length(instructions[0]) > 7 && is_real(instructions[0][7])) _fc_cur = real(instructions[0][7]);
            _fc_cur = _fc_cur + 1;
            if (_fc_cur > 15) {
                _fc_cur = -1;
            }
            instructions[0][7] = _fc_cur;
            global.undo_dirty  = true;
        }
        exit;
    }

    // ── ROW 6 - BLANK CHAR (decimal input) ────────────────
    var _bc_ly = _ly0 + _lh * 6;
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _bc_ly - 2, _vx + 40, _bc_ly + 12)) {
        var _bc_cur = 0;
        if (array_length(instructions[0]) > 8 && is_real(instructions[0][8])) _bc_cur = real(instructions[0][8]);
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 8;
        obj_workspace_manager.current_input_string = string(_bc_cur);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        exit;
    }

    // ── ROW 7 - CLAMP toggle ──────────────────────────────
    var _cl_ly = _ly0 + _lh * 7;
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _cl_ly - 2, _vx + 40, _cl_ly + 12)) {
        var _cl_cur = 1;
        if (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) _cl_cur = real(instructions[0][5]);
        if (_cl_cur == 1) {
            instructions[0][5] = 0;
        } else {
            instructions[0][5] = 1;
        }
        global.undo_dirty = true;
        exit;
    }

    // ── ROW 8 - OMIT TOP (decimal input, 0-8) ─────────────
    var _ot_ly = _ly0 + _lh * 8;
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _ot_ly - 2, _vx + 40, _ot_ly + 12)) {
        var _ot_cur = 0;
        if (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) _ot_cur = real(instructions[0][11]);
        scr_msc_pad_slots();
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 11;
        obj_workspace_manager.current_input_string = string(_ot_cur);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        exit;
    }

    // ── ROW 9 - OMIT BOTTOM (decimal input, 0-8) ──────────
    var _ob_ly = _ly0 + _lh * 9;
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _ob_ly - 2, _vx + 40, _ob_ly + 12)) {
        var _ob_cur = 0;
        if (array_length(instructions[0]) > 12 && is_real(instructions[0][12])) _ob_cur = real(instructions[0][12]);
        scr_msc_pad_slots();
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 12;
        obj_workspace_manager.current_input_string = string(_ob_cur);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        exit;
    }
}

/// @desc Make sure instructions[0] is long enough to hold slots 9-12 before
/// the text modal writes one of them. Nodes saved before OMIT TOP / OMIT
/// BOTTOM existed only have 9 entries, and the modal assigns by index rather
/// than growing the array itself. Slots 9 and 10 are reserved.
function scr_msc_pad_slots() {
    while (array_length(instructions[0]) < 13) {
        array_push(instructions[0], 0);
    }
}

/// @desc Drop a JSR node for one METASCROLL entry beside this node.
/// Mirrors how the JOYSTICK macro drops its direction labels: place it to
/// the right, then nudge down until the cell is free.
function scr_msc_drop_jsr(_name) {

    var _spawn_x = round((x + width + 60) / 20) * 20;
    var _spawn_y = round(y / 20) * 20;

    var _spawn_clear    = false;
    var _spawn_attempts = 0;
    while (!_spawn_clear && _spawn_attempts < 64) {
        _spawn_clear = true;
        with (obj_c64_node) {
            if (is_connected || org_parent != noone) continue;
            if (is_dragging) continue;
            if (x == _spawn_x && y == _spawn_y) {
                _spawn_clear = false;
                _spawn_y += ceil(height / 20) * 20;
                break;
            }
        }
        _spawn_attempts++;
    }

    var _n          = scr_node_spawn("NORMAL", _spawn_x, _spawn_y);
    _n.node_title   = "JSR " + _name;
    _n.instructions = [["jsr_lab", _name]];

    global.undo_dirty = true;
    scr_undo_snapshot();
}
