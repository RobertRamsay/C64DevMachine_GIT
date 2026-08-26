// Advance the asynchronous C64U REU upload.
scr_c64u_reu_step();

// Deferred flow-overlay rebuild — queued (not run inline) by whichever
// trigger below needs it, so the "CONSTRUCTING FLOW DATA" toast gets a
// full frame to actually render before this (potentially slow) compile
// pass blocks the next one.
if (flow_overlay_build_pending) {
    flow_overlay_edges = scr_build_flow_graph();
    flow_overlay_dirty = false;
    flow_overlay_build_pending = false;
    global.qmenu_toast_text = flow_overlay_pending_toast_text;
    global.qmenu_toast_col  = flow_overlay_pending_toast_col;
    global.qmenu_toast_t    = global.qmenu_toast_dur;
}

// === EXIT CONFIRM HANDLER ===
if (global.question_result == "exit_confirm_yes")
    {
     global.question_result = "";
     scr_save_workspace_as();
     game_end();
    }
else if (global.question_result == "exit_confirm_no")
    {
     global.question_result = "";
     game_end();
    }
	
// === WELCOME SCREEN (modal — blocks everything else while open) ===
if (welcome_open) {
    var _pw = 560;
    var _ph = 560;
    var _px = (global.gui_w - _pw) / 2;
    var _py = (display_get_gui_height() - _ph) / 2;

    // Auto-scroll the credits crawl
    var _cr_line_h  = 16;
    var _cr_total_h = array_length(welcome_credits_lines) * _cr_line_h;
    var _cr_view_h  = 180;
    welcome_credits_y += 0.4;
    if (welcome_credits_y > _cr_total_h + _cr_view_h) {
        welcome_credits_y = 0;
    }

    var _wmx = device_mouse_x_to_gui(0);
    var _wmy = device_mouse_y_to_gui(0);

    // Close button (top-right)
    var _cbx1 = _px + _pw - 36;
    var _cby1 = _py + 8;
    var _cbx2 = _cbx1 + 28;
    var _cby2 = _cby1 + 28;
    if (point_in_rectangle(_wmx, _wmy, _cbx1, _cby1, _cbx2, _cby2)
        && mouse_check_button_pressed(mb_left)) {
        // The particle system works in room space (it tracks node positions
        // on the canvas), but this panel is drawn in GUI space — convert the
        // panel's screen rectangle into the equivalent room rectangle so the
        // burst appears in the right place regardless of camera pan/zoom.
        if (variable_global_exists("fx_sys") && global.node_destroy_fx && global.visual_fx) {
            var _vx = camera_get_view_x(view_camera[0]);
            var _vy = camera_get_view_y(view_camera[0]);
            var _vw = camera_get_view_width(view_camera[0]);
            var _vh = camera_get_view_height(view_camera[0]);
            var _sx = global.gui_w / _vw;
            var _sy = display_get_gui_height() / _vh;

            var _room_x1 = _vx + (_px / _sx);
            var _room_y1 = _vy + (_py / _sy);
            var _room_x2 = _vx + ((_px + _pw) / _sx);
            var _room_y2 = _vy + ((_py + _ph) / _sy);

            part_emitter_region(global.fx_sys, 0, _room_x1, _room_x2, _room_y1, _room_y2, ps_shape_rectangle, ps_distr_linear);
            part_emitter_burst(global.fx_sys, 0, global.pt_node_vapor, 640);
        }
        welcome_open = false;
    }

    // Checkbox (bottom-left)
    var _chkx1 = _px + 20;
    var _chky1 = _py + _ph - 40;
    var _chkx2 = _chkx1 + 18;
    var _chky2 = _chky1 + 18;
    if (point_in_rectangle(_wmx, _wmy, _chkx1, _chky1, _chkx2, _chky2)
        && mouse_check_button_pressed(mb_left)) {
        welcome_hide_checked = !welcome_hide_checked;
        scr_welcome_save_pref(welcome_hide_checked);
    }

    // Keep the actual camera view in sync even though everything else is
    // blocked below — otherwise cam_x/cam_y can still change elsewhere
    // (window/zoom restore, etc.) while this modal is up, but never get
    // applied to the real view until Step's normal flow resumes, making
    // the camera appear frozen here and then jump the instant this closes.
    camera_set_view_pos(cam_view, cam_x, cam_y);

    exit;
}

// F1 reopens the welcome screen at any time
if (!is_entering_text && !global.is_any_text_active && keyboard_check_pressed(vk_f1)) {
    welcome_open = true;
}

// F toggles the flow overlay — rebuilds only if a node was added/removed
// since the last build (flow_overlay_dirty), so re-toggling with no graph
// changes is instant instead of re-running a full compile+assemble pass.
// Deliberately excludes any modifier so it doesn't clash with existing
// Ctrl/Shift/Cmd+F bindings.
if (!is_entering_text && !global.is_any_text_active && keyboard_check_pressed(ord("F")) && !box_popup_open && !code_editor_open
&& !keyboard_check(vk_control) && !keyboard_check(vk_shift) && !keyboard_check(vk_alt) && !scr_cmd_held()) {
    flow_overlay_mode = (flow_overlay_mode + 1) mod 3; // Cycles 0 -> 1 -> 2 -> 0
	

    
    // Set the toast message based on the new mode
    if (flow_overlay_mode == 1) {
        global.qmenu_toast_text = "FLOW LINES in LOCAL MODE\nHOVER over NODES to VIEW";
        global.qmenu_toast_col  = c_yellow;
        global.qmenu_toast_t    = global.qmenu_toast_dur;
    } else if (flow_overlay_mode == 2) {
        global.qmenu_toast_text = "FLOW LINES in GLOBAL MODE\nPRESS F to HIDE";
        global.qmenu_toast_col  = c_yellow;
        global.qmenu_toast_t    = global.qmenu_toast_dur;
    } else {
        global.qmenu_toast_text = "FLOW LINES: OFF";
        global.qmenu_toast_col  = c_yellow;
        global.qmenu_toast_t    = global.qmenu_toast_dur;
    }

    if (flow_overlay_mode > 0 && (flow_overlay_dirty || array_length(flow_overlay_edges) == 0)) {
        flow_overlay_pending_toast_text = global.qmenu_toast_text;
        flow_overlay_pending_toast_col  = global.qmenu_toast_col;
        global.qmenu_toast_text = "CONSTRUCTING FLOW DATA";
        global.qmenu_toast_col  = c_yellow;
        global.qmenu_toast_t    = global.qmenu_toast_dur;
        flow_overlay_build_pending = true;
    }
}

// Auto-refresh the flow overlay the moment a real node-based change makes
// it stale, right when the drag/edit that caused it ends (mouse release) —
// no F-key press needed while the overlay is actively showing. The dirty
// flag is only ever set for a genuine connected move/add/delete (see
// obj_c64_node), so this fires once per real change, not every release.
if (mouse_check_button_released(mb_left) && flow_overlay_mode > 0 && flow_overlay_dirty) {
    flow_overlay_pending_toast_text = "FLOW LINES updated";
    flow_overlay_pending_toast_col  = c_yellow;
    global.qmenu_toast_text = "CONSTRUCTING FLOW DATA";
    global.qmenu_toast_col  = c_yellow;
    global.qmenu_toast_t    = global.qmenu_toast_dur;
    flow_overlay_build_pending = true;
}

if (code_editor_open) {
        scr_code_editor_step();
        
        // If F5 was pressed inside the editor, we bypass the early exit 
        // for just ONE frame so the compiler block further down can execute!
        if (trigger_build) {
            // Clear the keyboard so the "fall-through" doesn't accidentally trigger workspace shortcuts
            keyboard_clear(vk_anykey); 
        } else {
            exit;
        }
    }
	 
	if (save_pending) {
    save_pending = false;
    if (keyboard_check(vk_shift)) {
        scr_save_workspace_as();
    } else {
        if (global.workspace_path != "") {
            scr_save_workspace_as_path(global.workspace_path);
        } else {
            scr_save_workspace_as();
        }
    }
    last_save_hour   = current_hour;
    last_save_minute = current_minute;
    global.isSaving  = false;
}

// The asset viewer (sound editor, bitmap builder, byte/text editors) owns the
// screen while open, so workspace shortcuts below are suppressed — otherwise
// typing a note name would pan the camera and hitting X would flip hex mode.
//
// F5/F6 are the exception: a build should work from inside an editor, same as
// it does from the code editor above. Catch them here, before the exit, and
// fall through for the one frame the build needs. Any pending edit buffer is
// committed first, or the compile reads the pre-edit content.
if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) {
    if (keyboard_check_pressed(vk_f5)) {
        scr_asset_inline_editor_commit_all();
        trigger_build = true;
    }
    if (keyboard_check_pressed(vk_f4)) {
        scr_asset_inline_editor_commit_all();
        trigger_export = true;
    }

    // F6 mirrors the workspace handler below, including its no-IP branch:
    // without a saved address the overlay opens instead of building, or the
    // compile would run with nowhere to send the PRG. With an IP, commit the
    // pending edit and set both flags so the build routes to the Ultimate.
    if (keyboard_check_pressed(vk_f6) && !global.asset_reload_in_progress) {
        if (global.c64u_ip == "") {
            global.c64u_overlay_active = true;
            global.c64u_overlay_text   = "";
            global.c64u_overlay_error  = "";
            global.c64u_overlay_after  = "send_prg";
            global.canEditNode         = 0;
            keyboard_string = "";
            keyboard_clear(vk_anykey);
            exit;   // overlay owns input now; nothing to build yet
        }
        scr_asset_inline_editor_commit_all();
        trigger_c64u  = true;
        trigger_build = true;
    }

    if (!trigger_build && !trigger_export) {
        exit;
    }
    // Falling through: stop the keypress reaching the workspace shortcuts
    // further down, which would otherwise act on it a second time.
    keyboard_clear(vk_anykey);
}
if (instance_exists(obj_asset_manager) && obj_asset_manager.editing_name) exit;

// =============================================
// DEFERRED DIALOG RESULTS (memory bar unlock prompts)
// =============================================

if (global.question_result == "basic_unlock_yes") {
    global.question_result = "";
    if (global.pending_unlock_type == "BASIC") {
        var _ix = global.pending_unlock_inject_x;
        var _iy = global.pending_unlock_inject_y;
        var _ii = global.pending_unlock_init_id;
        if (instance_exists(_ii)) {
            // Check for an existing KERNAL unlock node we can fold into one combined node.
            var _existing_kernal = noone;
            with (obj_c64_node) {
                if (node_title == "KERNAL RAM UNLOCK") {
                    _existing_kernal = id;
                    break;
                }
            }

            if (_existing_kernal != noone) {
                // Combine: bank out BOTH ROMs. Banking out KERNAL strands the IRQ
                // vector at $FFFE/$FFFF, so use Shallan's safe sequence: mask CPU
                // IRQs, disable both CIA interrupt sources, ack pending, then bank.
                // Result $01 low bits = %101 (and $F8 / ora $05): both ROMs out,
                // I/O visible.
                var _kx = _existing_kernal.x;
                var _ky = _existing_kernal.y;
                instance_destroy(_existing_kernal);
                var _n1          = instance_create_layer(_kx, _ky, "Layer_Nodes", obj_c64_node);
                _n1.node_title   = "RAM UNLOCK (BASIC+KERNAL)";
                _n1.node_type    = "NORMAL";
                _n1.is_connected = true;
                _n1.org_parent   = noone;
                _n1.instructions = [
                    ["sei", 0],
                    ["lda_imm", 0x7F],
                    ["sta_abs", 0xDC0D],
                    ["sta_abs", 0xDD0D],
                    ["lda_abs", 0xDC0D],
                    ["lda_zp",  0x01],
                    ["and_imm", 0xF8],
                    ["ora_imm", 0x05],
                    ["sta_zp",  0x01]
                ];
                with (_n1) { event_user(0); }
            } else {
                // No KERNAL unlock present — emit a standalone BASIC unlock.
                var _n1          = instance_create_layer(_ix, _iy, "Layer_Nodes", obj_c64_node);
                _n1.node_title   = "BASIC RAM UNLOCK";
                _n1.node_type    = "NORMAL";
                _n1.is_connected = true;
                _n1.org_parent   = noone;
                _n1.instructions = [["lda_zp", 0x01], ["and_imm", 0xFE], ["sta_zp", 0x01]];
                with (_n1) { event_user(0); }
                var _sh = 100;
                with (obj_c64_node) {
                    if (id != _ii && id != _n1 && is_connected && org_parent == noone && y >= _iy) {
                        y += _sh;
                    }
                }
            }

            global.basic_unlocked = true;
            global.undo_dirty     = true;
            global.autosave_dirty = true;
            scr_c64_update_addresses();
        }
    }
    global.pending_unlock_type = "";
}


if (global.question_result == "kernal_unlock_yes") {
    global.question_result = "";
    if (global.pending_unlock_type == "KERNAL") {
        var _ix = global.pending_unlock_inject_x;
        var _iy = global.pending_unlock_inject_y;
        var _ii = global.pending_unlock_init_id;
        if (instance_exists(_ii)) {
            // Check for an existing BASIC unlock node we can fold into one combined node.
            var _existing_basic = noone;
            with (obj_c64_node) {
                if (node_title == "BASIC RAM UNLOCK") {
                    _existing_basic = id;
                    break;
                }
            }

            if (_existing_basic != noone) {
                // Combine: bank out BOTH ROMs. Banking out KERNAL strands the IRQ
                // vector at $FFFE/$FFFF, so use Shallan's safe sequence: mask CPU
                // IRQs, disable both CIA interrupt sources, ack pending, then bank.
                // Result $01 low bits = %101 (and $F8 / ora $05): both ROMs out,
                // I/O visible. Banking out KERNAL frees BASIC too (hardware rule).
                var _bx = _existing_basic.x;
                var _by = _existing_basic.y;
                instance_destroy(_existing_basic);
                var _n1          = instance_create_layer(_bx, _by, "Layer_Nodes", obj_c64_node);
                _n1.node_title   = "RAM UNLOCK (BASIC+KERNAL)";
                _n1.node_type    = "NORMAL";
                _n1.is_connected = true;
                _n1.org_parent   = noone;
                _n1.instructions = [
                    ["sei"],
                    ["lda_imm", 0x7F],
                    ["sta_abs", 0xDC0D],
                    ["sta_abs", 0xDD0D],
                    ["lda_abs", 0xDC0D],
                    ["lda_zp",  0x01],
                    ["and_imm", 0xF8],
                    ["ora_imm", 0x05],
                    ["sta_zp",  0x01]
                ];
                with (_n1) { event_user(0); }
            } else {
                // Standalone KERNAL bank-out. Banking out KERNAL frees BASIC too
                // and strands the IRQ vector, so this is effectively a both-out and
                // gets the same safe sequence. Result $01 low bits = %101.
                var _n1          = instance_create_layer(_ix, _iy, "Layer_Nodes", obj_c64_node);
                _n1.node_title   = "RAM UNLOCK (BASIC+KERNAL)";
                _n1.node_type    = "NORMAL";
                _n1.is_connected = true;
                _n1.org_parent   = noone;
                _n1.instructions = [
                    ["sei"],
                    ["lda_imm", 0x7F],
                    ["sta_abs", 0xDC0D],
                    ["sta_abs", 0xDD0D],
                    ["lda_abs", 0xDC0D],
                    ["lda_zp",  0x01],
                    ["and_imm", 0xF8],
                    ["ora_imm", 0x05],
                    ["sta_zp",  0x01]
                ];
                with (_n1) { event_user(0); }
                var _sh = 100;
                with (obj_c64_node) {
                    if (id != _ii && id != _n1 && is_connected && org_parent == noone && y >= _iy) {
                        y += _sh;
                    }
                }
            }

            global.kernal_unlocked = true;
            global.undo_dirty      = true;
            global.autosave_dirty  = true;
            scr_c64_update_addresses();
        }
    }
    global.pending_unlock_type = "";
}

if (global.question_result == "kernal_unlock_no") {
    global.question_result     = "";
    global.pending_unlock_type = "";
}

if ( (keyboard_check_pressed(223)) or (keyboard_check_pressed(ord("I")))) and !opcode_finder_active and !is_entering_text and !box_popup_open and !keyboard_check(vk_shift) and !global.any_picker_open {
	
    global.show_stats = !global.show_stats;
    with (obj_c64_node) { stats_cache_dirty = true; }
}

if (keyboard_check_pressed(vk_delete) && array_length(global.selected_nodes) > 0 && !global.any_picker_open) {

    // ------------------------------------------------------------
    // BATCH VARIABLE DELETE REFERENCE GUARD
    // Scan every selected VAR node BEFORE deleting anything. If any is
    // still referenced by a known VAR-consuming node, abort the whole
    // batch and raise the merged warning list. Refs are de-duped by node
    // id (a node referencing two blocked vars shows once). Nodes inside
    // the selection don't count as external references.
    // ------------------------------------------------------------
    var _blocked_vars   = [];
    var _merged_refs    = [];
    var _merged_seen    = ds_map_create();

    for (var _bvi = 0; _bvi < array_length(global.selected_nodes); _bvi++) {
        var _bv = global.selected_nodes[_bvi];
        if (!instance_exists(_bv)) continue;
        if (_bv.node_type != "NAMED_LOC" && _bv.node_type != "NEW_STR") continue;

        var _bv_name = string(_bv.instructions[0][1]);
        var _bv_refs = scr_find_var_references(_bv_name, _bv);

        // Drop references that are themselves in the selection (deleting together)
        for (var _bri = 0; _bri < array_length(_bv_refs); _bri++) {
            var _br_node = _bv_refs[_bri].node;
            var _in_sel  = false;
            for (var _sci = 0; _sci < array_length(global.selected_nodes); _sci++) {
                if (global.selected_nodes[_sci] == _br_node) { _in_sel = true; break; }
            }
            if (_in_sel) continue;

            var _key = string(real(_br_node));
            if (ds_map_exists(_merged_seen, _key)) continue;
            ds_map_add(_merged_seen, _key, true);
            array_push(_merged_refs, _bv_refs[_bri]);
        }

        // Track this var as blocked only if it has external references
        var _has_ext = false;
        for (var _bri2 = 0; _bri2 < array_length(_bv_refs); _bri2++) {
            var _br_node2 = _bv_refs[_bri2].node;
            var _in_sel2  = false;
            for (var _sci2 = 0; _sci2 < array_length(global.selected_nodes); _sci2++) {
                if (global.selected_nodes[_sci2] == _br_node2) { _in_sel2 = true; break; }
            }
            if (!_in_sel2) { _has_ext = true; break; }
        }
        if (_has_ext) array_push(_blocked_vars, _bv_name);
    }

    ds_map_destroy(_merged_seen);

    if (array_length(_merged_refs) > 0) {
        // Abort the entire batch — raise the merged warning list
        global.var_del_warn_active   = true;
        global.var_del_warn_clicked  = false;
        global.var_del_warn_fade     = 1.0;
        global.var_del_warn_scroll   = 0;
        global.var_del_warn_refs     = _merged_refs;
        global.var_del_warn_batch    = array_length(_blocked_vars);
        if (array_length(_blocked_vars) == 1) {
            global.var_del_warn_name = _blocked_vars[0];
        } else {
            global.var_del_warn_name = string(array_length(_blocked_vars)) + " VARS";
        }
        exit;
    }

    var _did_delete = false;
    for (var _di = 0; _di < array_length(global.selected_nodes); _di++) {
        var _dn = global.selected_nodes[_di];
        if (!instance_exists(_dn)) continue;
        if (_dn.node_type == "INIT") continue;
        if (_dn.node_type == "ORG" && _dn.node_title == "VARIABLES") {
            var _vars_count = 0;
            with (obj_c64_node) { if (node_type == "ORG" && node_title == "VARIABLES") _vars_count++; }
            if (_vars_count <= 1) continue;
        }
        if (_dn.node_type == "ORG" && _dn.node_title == "HW REGISTERS") continue; // not visiable
	with (_dn) {
            if (node_type == "BITMAP_KLA") {
                if (kla_buffer != -1 && buffer_exists(kla_buffer)) buffer_delete(kla_buffer);
                if (surface_exists(preview_surf)) surface_free(preview_surf);
            }
            last_overlap_check = false;
            overlap_check_dirty = true;
            // Pull nodes below this one up by its height
            var _del_y      = y;
            var _del_h      = height;
            var _del_parent = org_parent;
			if (_del_parent != noone) {
                with (obj_c64_node) {
                    if (is_connected && !is_dragging && y > _del_y &&
                        org_parent == _del_parent) {
                        y -= _del_h;
                    }
                }
            }
        }
        instance_destroy(_dn);
        _did_delete = true;
    }
    if (_did_delete) {
        global.selected_nodes = [];
        global.undo_dirty = true;
        global.addresses_dirty = true;
        with (obj_c64_node) { last_overlap_check = false; overlap_check_dirty = true; }
        scr_c64_update_addresses();
    }
}

// Tick autosave countdown display
if (global.autosave_dirty && alarm[4] > 0) {
    autosave_countdown = alarm[4] / game_get_speed(gamespeed_fps);
} else {
    autosave_countdown = 0;
}

if (box_popup_open) {
    // Name typing routed here
    if (keyboard_string != "") {
        var _add = scr_strip_key_ghosts(keyboard_string);
        if (_add != "" && string_length(box_popup_name) + string_length(_add) <= 24) {
            box_popup_name  = string_insert(_add, box_popup_name, box_cursor_pos + 1);
            box_cursor_pos += string_length(_add);
        }
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_backspace) && box_cursor_pos > 0) {
        box_popup_name = string_delete(box_popup_name, box_cursor_pos, 1);
        box_cursor_pos--;
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_left))  box_cursor_pos = max(0, box_cursor_pos - 1);
    if (keyboard_check_pressed(vk_right)) box_cursor_pos = min(string_length(box_popup_name), box_cursor_pos + 1);
    exit; // block all other step logic while popup is open
}

if (label_search_open) {
    if (!label_search_ready) {
        // Absorb the F keypress that opened the modal
        keyboard_string     = "";
        label_search_ready  = true;
    } else {
        if (keyboard_string != "") {
            var _lsadd = scr_strip_key_ghosts(keyboard_string);
            if (_lsadd != "" && string_length(label_search_query) + string_length(_lsadd) <= 30) {
                label_search_query  = string_insert(_lsadd, label_search_query, label_search_cursor + 1);
                label_search_cursor += string_length(_lsadd);
            }
            keyboard_string = "";
        }
        if (keyboard_check_pressed(vk_backspace) && label_search_cursor > 0) {
            label_search_query = string_delete(label_search_query, label_search_cursor, 1);
            label_search_cursor--;
            keyboard_string = "";
        }
        if (keyboard_check_pressed(vk_left))  label_search_cursor = max(0, label_search_cursor - 1);
        if (keyboard_check_pressed(vk_right)) label_search_cursor = min(string_length(label_search_query), label_search_cursor + 1);

        if (keyboard_check_pressed(vk_enter)) {
            label_search_results = scr_label_search_run(label_search_query);
            label_search_index   = (array_length(label_search_results) > 0) ? 0 : -1;
            if (label_search_index >= 0 && instance_exists(label_search_results[label_search_index])) {
	            scr_focus_camera_on_node_offset(label_search_results[label_search_index], 0.2);
	            camera_set_view_pos(cam_view, cam_x, cam_y);
	        }
	    }

        // Up/Down cycle through results as a keyboard alternative to < >
        var _lscount = array_length(label_search_results);
        if (_lscount > 0) {
            if (keyboard_check_pressed(vk_down)) {
                label_search_index = (label_search_index + 1) mod _lscount;
                if (instance_exists(label_search_results[label_search_index])) {
                    scr_focus_camera_on_node_offset(label_search_results[label_search_index], 0.2);
                    camera_set_view_pos(cam_view, cam_x, cam_y);
                }
            }
            if (keyboard_check_pressed(vk_up)) {
                label_search_index = (label_search_index - 1 + _lscount) mod _lscount;
                if (instance_exists(label_search_results[label_search_index])) {
                    scr_focus_camera_on_node_offset(label_search_results[label_search_index], 0.2);
                    camera_set_view_pos(cam_view, cam_x, cam_y);
                }
            }
        }
    }

    if (keyboard_check_pressed(vk_escape)) {
        label_search_open    = false;
        label_search_results = [];
        label_search_index   = -1;
    }
    exit; // block all other step logic while search modal is open
}


// Triple Verification: Check if any UI element is capturing input
var _ui_blocking = (is_entering_text || box_popup_open || global.show_info_window || global.show_helper_window);
var _editor_active = (obj_asset_manager.viewer_open || obj_asset_manager.editing_name);

// If the editor JUST closed this frame (via your alarm/flag), skip the quit logic
if (obj_asset_manager.editorClosed != -1) {
    // We don't exit here, we just let the frame finish so the flag can reset
}



// =============================================
// MACRO_JOY LABEL VALIDATION
// =============================================
if (mouse_check_button_pressed(mb_left)    || 
    mouse_check_button_released(mb_left)   || 
    mouse_check_button_pressed(mb_right)   || 
    mouse_check_button_released(mb_right)  || 
    keyboard_check_pressed(vk_anykey)      || 
    keyboard_check_released(vk_anykey)) 
	{
		


	// Unlock flags are derived from real instructions in scr_detect_bank_unlock(),
	// which is also called from scr_c64_do_update_addresses(). Trigger a refresh
	// here so the memory bar updates on click/key without waiting for a drag-release.
	scr_detect_bank_unlock();
	
	
       // Build LABEL lookup table once instead of searching every node
    var _label_lookup = ds_map_create();

    with (obj_c64_node) {
        if (node_type == "LABEL") {
            var _this_label = string_replace_all(string(instructions[0][1]), " ", "_");
            _label_lookup[? _this_label] = true;
        }
    }

    with (obj_c64_node) {
        if (node_type != "MACRO_JOY") continue;

        if (!variable_instance_exists(id, "joy_label_missing")) {
            joy_label_missing = array_create(10, false);
        }

        for (var _ji = 1; _ji <= 10; _ji++) {

            var _enabled = real(instructions[_ji][2]);
            var _label   = string(instructions[_ji][1]);

            if (!_enabled || _label == "" || _label == "target") {
                joy_label_missing[_ji - 1] = false;
                continue;
            }

            var _search = string_replace_all(_label, " ", "_");

            joy_label_missing[_ji - 1] =
                !ds_map_exists(_label_lookup, _search);
        }
    }

    ds_map_destroy(_label_lookup);
}

// =============================================================
// 0. CUSTOM GUI INPUT COMMIT
// =============================================================

//  GLOBAL INPUT BLOCK 
if (global.show_info_window) {
    if (keyboard_check_pressed(vk_escape)) {
        global.show_info_window  = false;
        info_scroll_offset       = 0;
        info_timer               = 0;
    }
    exit;
}

if (global.show_helper_window) {
    if (keyboard_check_pressed(vk_escape)) {
        global.show_helper_window = false;
        helper_timer              = 0;
    }
    exit;
}

if (!variable_instance_exists(id, "cursor_pos"))      cursor_pos = 0;
if (!variable_instance_exists(id, "backspace_timer")) backspace_timer = 0;

// Clear keyboard buffer on the frame text input opens
if (is_entering_text && !_was_entering_text) {
    keyboard_string = "";
    keyboard_clear(vk_anykey);
    input_sel_start = -1;
    input_sel_end   = -1;
    input_key_timer = 0;
    // Cursor always lands at end of the seeded value, regardless of
    // whether the opening step script set it.
    cursor_pos      = string_length(current_input_string);
}
_was_entering_text = is_entering_text;

// =============================================================
// OPCODE FINDER KEYBOARD INPUT
// =============================================================
// Expert Mode: Ctrl/Cmd+E. The opcode shelf becomes live canvas below Y=47.
if (scr_ctrl_held() && keyboard_check_pressed(ord("E"))
    && !is_entering_text && !global.is_any_text_active
    && !global.any_picker_open && !box_popup_open && !code_editor_open) {
    expert_mode = !expert_mode;
    opcode_finder_active     = false;
    opcode_finder_was_active = false;
    opcode_finder_text       = "";
    opcode_finder_matches    = [];
    opcode_hover_key         = "";
    opcode_hover_timer       = 0;
    ini_open("c64devmachine.ini");
    ini_write_real("Settings", "expert_mode", expert_mode ? 1 : 0);
    ini_close();
}

if (opcode_finder_active) {
    if (!opcode_finder_was_active) {
        keyboard_string          = "";
        opcode_finder_was_active = true;
    }
    if (keyboard_string != "") {
        var _fadd    = string_upper(keyboard_string);
        var _allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
        for (var _fc = 0; _fc < string_length(_fadd); _fc++) {
            var _fch = string_char_at(_fadd, _fc + 1);
            if (string_pos(_fch, _allowed) > 0 && string_length(opcode_finder_text) < 8) {
                opcode_finder_text += _fch;
            }
        }
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_backspace) && string_length(opcode_finder_text) > 0) {
        opcode_finder_text = string_copy(opcode_finder_text, 1, string_length(opcode_finder_text) - 1);
        keyboard_string    = "";
    }
    if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(vk_enter)) {
        opcode_finder_active     = false;
        opcode_finder_was_active = false;
        opcode_finder_text       = "";
        opcode_finder_matches    = [];
        keyboard_string          = "";
    }
    exit;
}

if (is_entering_text) {
    if (global.show_info_window) is_entering_text = false;

    var target        = input_target_node;
    var idx           = input_target_index;
    var is_comment    = (instance_exists(target) && target.node_type == "COMMENT");
    var _is_long_text = (input_target_node != noone &&
                         input_target_node.node_type == "MACRO_TEXT_SCROLL" &&
                         input_target_index == 6);

    var _is_address_field = false;
    if (input_target_node != noone && instance_exists(input_target_node)) {
        var _ntype = input_target_node.node_type;
        var _nidx  = input_target_index;
        if (_nidx == -1) {
            _is_address_field = true;
        } else if (_ntype == "MACRO_FLIP_X"     && _nidx == 1) { _is_address_field = true; }
        else if (_ntype == "MACRO_MOVE_MEM")                 { _is_address_field = true; }
        else if (_ntype == "MACRO_MOVE_BMP_BLOCK" && (_nidx == 1 || _nidx == 2)) { _is_address_field = true; }
        else if (_ntype == "MACRO_PRINT"        && (_nidx == 6 || _nidx == 13)) { _is_address_field = true; }
	// Slot 1 is the target bitmap base — typed as hex, like every other bmp addr.
	else if (_ntype == "MACRO_CLEAR_BMP_RECT" && _nidx == 1)                { _is_address_field = true; }
		else if (_ntype == "MACRO_PLACE_CHAR"   && (_nidx == 16 || _nidx == 17)) { _is_address_field = true; }
		else if (_ntype == "MACRO_CLR_SCREEN"   && _nidx == 1)                   { _is_address_field = true; }
		else if (_ntype == "MACRO_GET_CHAR"     && (_nidx == 10 || _nidx == 11)) { _is_address_field = true; }
		else if (_ntype == "MACRO_RANDOM"       && (_nidx == 2  || _nidx == 8))  { _is_address_field = true; }
		else if (_ntype == "MACRO_SID_SOUND"    && (_nidx == 8  || _nidx == 11 || _nidx == 14 || _nidx == 18 || _nidx == 20)) { _is_address_field = true; }
        else if (_ntype == "MACRO_TEXT_SCROLL"  && _nidx == 5) { _is_address_field = true; }
        else if (_ntype == "MACRO_SID"          && _nidx == 1) { _is_address_field = true; }
        else if (_ntype == "MACRO_SCROLL"       && _nidx == 9) { _is_address_field = true; }
        else if (_ntype == "MACRO_BMP")                        { _is_address_field = true; }
        else if (_ntype == "MACRO_VWAIT"        && _nidx == 1 && (array_length(input_target_node.instructions[0]) <= 2 || real(input_target_node.instructions[0][2]) == 0)) { _is_address_field = true; }
        
    }

    var char_limit = is_comment ? 160 : (_is_long_text ? 512 : (_is_address_field ? 5 : 40));

    var _shift = keyboard_check(vk_shift);
    var _ctrl  = keyboard_check(vk_control);
    var _len   = string_length(current_input_string);

    var _has_sel = (input_sel_start != -1 && input_sel_start != input_sel_end);
    var _sel_lo  = _has_sel ? min(input_sel_start, input_sel_end) : cursor_pos;
    var _sel_hi  = _has_sel ? max(input_sel_start, input_sel_end) : cursor_pos;

    // ── Ctrl+A: select all ──
    if (_ctrl && keyboard_check_pressed(ord("A"))) {
        input_sel_start = 0;
        input_sel_end   = string_length(current_input_string);
        cursor_pos      = input_sel_end;
        keyboard_string = "";
    }

    // ── Ctrl+C: copy ──
    if (_ctrl && keyboard_check_pressed(ord("C"))) {
        if (_has_sel) {
            clipboard_set_text(string_copy(current_input_string, _sel_lo + 1, _sel_hi - _sel_lo));
        }
        keyboard_string = "";
    }

    // ── Ctrl+X: cut ──
    if (_ctrl && keyboard_check_pressed(ord("X"))) {
        if (_has_sel) {
            clipboard_set_text(string_copy(current_input_string, _sel_lo + 1, _sel_hi - _sel_lo));
            current_input_string = string_delete(current_input_string, _sel_lo + 1, _sel_hi - _sel_lo);
            cursor_pos      = _sel_lo;
            input_sel_start = -1;
            input_sel_end   = -1;
        }
        keyboard_string = "";
    }

// ── Ctrl+V: paste ──
    if (_ctrl && keyboard_check_pressed(ord("V"))) {
        var _clip = clipboard_get_text();
        if (_clip != "") {
            _clip = string_replace_all(_clip, "\r\n", "\n");
            _clip = string_replace_all(_clip, "\r",   "\n");
            if (!is_comment && !_is_long_text) {
                var _nl = string_pos("\n", _clip);
                if (_nl > 0) _clip = string_copy(_clip, 1, _nl - 1);
            }
            if (_has_sel) {
                current_input_string = string_delete(current_input_string, _sel_lo + 1, _sel_hi - _sel_lo);
                cursor_pos      = _sel_lo;
                input_sel_start = -1;
                input_sel_end   = -1;
            }
            if (string_length(current_input_string) + string_length(_clip) <= char_limit) {
                current_input_string = string_insert(_clip, current_input_string, cursor_pos + 1);
                cursor_pos += string_length(_clip);
            } else {
                // Truncate clip to fit within char limit
                var _room = char_limit - string_length(current_input_string);
                if (_room > 0) {
                    var _clipped = string_copy(_clip, 1, _room);
                    current_input_string = string_insert(_clipped, current_input_string, cursor_pos + 1);
                    cursor_pos += string_length(_clipped);
                }
            }
            // Force wrap scan on pasted content
            if (is_comment || _is_long_text) {
                var _wrap_limit = _is_long_text ? 50 : 25;
                var _line_limit = _is_long_text ? 20 : 6;
                var _pass = 0;
                while (_pass < 40) {
                    _pass++;
                    var _lines2 = string_split(current_input_string, "\n");
                    if (array_length(_lines2) >= _line_limit) break;
                    var _changed = false;
                    var _off2 = 0;
                    for (var _li2 = 0; _li2 < array_length(_lines2); _li2++) {
                        var _ln2 = _lines2[_li2];
                        if (string_length(_ln2) > _wrap_limit) {
                            var _sp2 = string_last_pos(" ", string_copy(_ln2, 1, _wrap_limit));
                            if (_sp2 > 1) {
                                var _brk = _off2 + _sp2;
                                current_input_string = string_delete(current_input_string, _brk, 1);
                                current_input_string = string_insert("\n", current_input_string, _brk);
                            } else {
                                var _brk = _off2 + _wrap_limit;
                                current_input_string = string_insert("\n", current_input_string, _brk + 1);
                            }
                            _changed = true;
                            break;
                        }
                        _off2 += string_length(_ln2) + 1;
                    }
                    if (!_changed) break;
                }
                // Hard cut: if still over line limit, truncate at last valid line end
                var _final_lines = string_split(current_input_string, "\n");
                if (array_length(_final_lines) > _line_limit) {
                    var _cut = 0;
                    for (var _fli = 0; _fli < _line_limit; _fli++) {
                        _cut += string_length(_final_lines[_fli]) + 1;
                    }
                    current_input_string = string_copy(current_input_string, 1, _cut - 1);
                    _final_lines = string_split(current_input_string, "\n");
                }
                // Also trim the last line if it exceeds wrap limit
                var _last_line_idx = array_length(_final_lines) - 1;
                if (_last_line_idx >= 0 && string_length(_final_lines[_last_line_idx]) > _wrap_limit) {
                    var _trim_at = string_length(current_input_string) - string_length(_final_lines[_last_line_idx]) + _wrap_limit;
                    current_input_string = string_copy(current_input_string, 1, _trim_at);
                }
                cursor_pos = min(cursor_pos, string_length(current_input_string));
            }
        }
        keyboard_string = "";
    }

    // ── Key repeat system (mirrors scr_code_editor_step) ──
    var _do_action = false;
    var _any_nav   = keyboard_check(vk_left) || keyboard_check(vk_right) ||
                     keyboard_check(vk_backspace) || keyboard_check(vk_delete);
    if (_any_nav) {
        if (keyboard_check_pressed(vk_left)      || keyboard_check_pressed(vk_right) ||
            keyboard_check_pressed(vk_backspace)  || keyboard_check_pressed(vk_delete)) {
            _do_action      = true;
            input_key_timer = 20;
        } else {
            input_key_timer--;
            if (input_key_timer <= 0) {
                _do_action      = true;
                input_key_timer = 2;
            }
        }
    } else {
        input_key_timer = 0;
    }

    if (_do_action) {

        // ── LEFT ──
        if (keyboard_check(vk_left)) {
            if (_shift) {
                if (input_sel_start == -1) input_sel_start = cursor_pos;
                cursor_pos    = max(0, cursor_pos - 1);
                input_sel_end = cursor_pos;
            } else {
                if (_has_sel) {
                    cursor_pos = _sel_lo;
                } else {
                    cursor_pos = max(0, cursor_pos - 1);
                }
                input_sel_start = -1;
                input_sel_end   = -1;
            }
        }

        // ── RIGHT ──
        if (keyboard_check(vk_right)) {
            if (_shift) {
                if (input_sel_start == -1) input_sel_start = cursor_pos;
                cursor_pos    = min(string_length(current_input_string), cursor_pos + 1);
                input_sel_end = cursor_pos;
            } else {
                if (_has_sel) {
                    cursor_pos = _sel_hi;
                } else {
                    cursor_pos = min(string_length(current_input_string), cursor_pos + 1);
                }
                input_sel_start = -1;
                input_sel_end   = -1;
            }
        }

        // ── BACKSPACE ──
        if (keyboard_check(vk_backspace)) {
            if (_has_sel) {
                current_input_string = string_delete(current_input_string, _sel_lo + 1, _sel_hi - _sel_lo);
                cursor_pos      = _sel_lo;
                input_sel_start = -1;
                input_sel_end   = -1;
            } else if (_ctrl) {
                current_input_string = "";
                cursor_pos      = 0;
                input_sel_start = -1;
                input_sel_end   = -1;
            } else if (cursor_pos > 0) {
                var _char_to_del = string_char_at(current_input_string, cursor_pos);
                if (_char_to_del == "\n") {
                    current_input_string = string_delete(current_input_string, cursor_pos - 1, 2);
                    cursor_pos -= 2;
                } else {
                    current_input_string = string_delete(current_input_string, cursor_pos, 1);
                    cursor_pos--;
                }
            }
            keyboard_string = "";
        }

        // ── DELETE ──
        if (keyboard_check(vk_delete)) {
            if (_has_sel) {
                current_input_string = string_delete(current_input_string, _sel_lo + 1, _sel_hi - _sel_lo);
                cursor_pos      = _sel_lo;
                input_sel_start = -1;
                input_sel_end   = -1;
            } else if (cursor_pos < string_length(current_input_string)) {
                current_input_string = string_delete(current_input_string, cursor_pos + 1, 1);
            }
            keyboard_string = "";
        }
    }

    // ── Home ──
    if (keyboard_check_pressed(vk_home)) {
        if (_shift) {
            if (input_sel_start == -1) input_sel_start = cursor_pos;
            cursor_pos    = 0;
            input_sel_end = cursor_pos;
        } else {
            cursor_pos      = 0;
            input_sel_start = -1;
            input_sel_end   = -1;
        }
    }

    // ── End ──
    if (keyboard_check_pressed(vk_end)) {
        if (_shift) {
            if (input_sel_start == -1) input_sel_start = cursor_pos;
            cursor_pos    = string_length(current_input_string);
            input_sel_end = cursor_pos;
        } else {
            cursor_pos      = string_length(current_input_string);
            input_sel_start = -1;
            input_sel_end   = -1;
        }
    }

    // ── Line break handling ──
    var _is_code_editor = (input_target_node != noone &&
                           input_target_node.node_type == "MACRO_CODE" &&
                           input_target_index == 0);

    if (_is_code_editor) {
        if (keyboard_check_pressed(vk_enter) && !_ctrl) {
            if (string_count("\n", current_input_string) < 200) {
                current_input_string = string_insert("\n", current_input_string, cursor_pos + 1);
                cursor_pos++;
            }
            keyboard_clear(vk_enter);
        }
    } else {
        if (keyboard_check_pressed(vk_enter) && _shift) {
            if (is_comment || _is_long_text) {
                if (string_count("\n", current_input_string) < 5) {
                    current_input_string = string_insert("\n", current_input_string, cursor_pos + 1);
                    cursor_pos++;
                }
                keyboard_clear(vk_enter);
            }
        }
    }

// ── Auto word-wrap for comment/long text ──
    if ((is_comment || _is_long_text) && !keyboard_check(vk_backspace)) {
        var _lines         = string_split(current_input_string, "\n");
        var _temp_len      = 0;
        var _curr_line_idx = 0;
        for (var _i = 0; _i < array_length(_lines); _i++) {
            var _line_total = string_length(_lines[_i]) + 1;
            if (cursor_pos < _temp_len + _line_total) { _curr_line_idx = _i; break; }
            _temp_len += _line_total;
        }
        var _current_line_text = _lines[_curr_line_idx];
        var _wrap_limit = _is_long_text ? 50 : 25;
        var _line_limit = _is_long_text ? 20 : 6;
        if (string_length(_current_line_text) >= _wrap_limit && array_length(_lines) < _line_limit) {
            var _last_space = string_last_pos(" ", _current_line_text);
            if (_last_space > 0 && _last_space > 5) {
                var _break_at        = (_temp_len + _last_space);
                current_input_string = string_delete(current_input_string, _break_at, 1);
                current_input_string = string_insert("\n", current_input_string, _break_at);
            } else {
                var _force_brk = _temp_len + _wrap_limit;
                current_input_string = string_insert("\n", current_input_string, _force_brk + 1);
                cursor_pos = min(cursor_pos + 1, string_length(current_input_string));
            }
        }
        // Hard trim: last line must not exceed wrap limit
        var _trim_lines = string_split(current_input_string, "\n");
        var _last_idx   = array_length(_trim_lines) - 1;
        if (_last_idx >= 0 && string_length(_trim_lines[_last_idx]) > _wrap_limit) {
            var _trim_at = string_length(current_input_string) - string_length(_trim_lines[_last_idx]) + _wrap_limit;
            current_input_string = string_copy(current_input_string, 1, _trim_at);
            cursor_pos = min(cursor_pos, string_length(current_input_string));
        }
    }

    // ── Mouse click to place cursor ──
    // Skipped on the frame the modal opens: the click that opened the field
    // is still "pressed" this step and would drag the caret to wherever the
    // node's value happened to sit on screen.
    if (mouse_check_button_pressed(mb_left) && _was_entering_text) {
        var _gmx    = global.gui_mouse_x;
        var _gmy    = global.gui_mouse_y;
        var _is_ml  = (is_comment || _is_long_text || _is_code_editor);
        var _txt_x  = _is_ml ? ((input_target_node != noone && (input_target_node.node_type == "MACRO_TEXT_SCROLL" || input_target_node.node_type == "MACRO_CODE")) ? (global.gui_w / 2) - 180 : (global.gui_w / 2) - 125) : (global.gui_w / 2);
        var _txt_y0 = (display_get_gui_height() / 2) - 60;
        var _lh_px  = 18 * 1.2;

        draw_set_font(fnt_c64_code);

        if (_is_ml) {
            var _ml_lines = string_split(current_input_string, "\n");
            var _ml_off   = 0;
            for (var _mli = 0; _mli < array_length(_ml_lines); _mli++) {
                var _line_y1 = _txt_y0 + (_mli * _lh_px);
                var _line_y2 = _line_y1 + _lh_px;
                if (_gmy >= _line_y1 && _gmy < _line_y2) {
                    var _ml_line = _ml_lines[_mli];
                    var _ml_len  = string_length(_ml_line);
                    var _best_col = _ml_len;
                    for (var _ci = 0; _ci <= _ml_len; _ci++) {
                        var _cx1 = _txt_x + string_width(string_copy(_ml_line, 1, _ci)) * 1.2;
                        var _cx2 = _txt_x + string_width(string_copy(_ml_line, 1, _ci + 1)) * 1.2;
                        if (_gmx < (_cx1 + _cx2) * 0.5) {
                            _best_col = _ci;
                            break;
                        }
                    }
                    cursor_pos      = _ml_off + _best_col;
                    input_sel_start = -1;
                    input_sel_end   = -1;
                    break;
                }
                _ml_off += string_length(_ml_lines[_mli]) + 1;
            }
        } else {
            var _full_str = current_input_string;
            var _full_w   = string_width(_full_str) * 1.5;
            var _start_x  = (global.gui_w / 2) - _full_w * 0.5;
            var _row_y1   = (display_get_gui_height() / 2) - 14;
            var _row_y2   = (display_get_gui_height() / 2) + 14;
            if (_gmy >= _row_y1 && _gmy < _row_y2) {
                var _len     = string_length(_full_str);
                var _best    = _len;
                for (var _ci = 0; _ci <= _len; _ci++) {
                    var _cx1 = _start_x + string_width(string_copy(_full_str, 1, _ci)) * 1.5;
                    var _cx2 = _start_x + string_width(string_copy(_full_str, 1, _ci + 1)) * 1.5;
                    if (_gmx < (_cx1 + _cx2) * 0.5) {
                        _best = _ci;
                        break;
                    }
                }
                cursor_pos      = _best;
                input_sel_start = -1;
                input_sel_end   = -1;
            }
        }
    }

    // ── Character input (only when not a ctrl combo) ──
    if (keyboard_string != "" && !_ctrl) {
        var _added = keyboard_string;

        // MACRO_ANIM frame/X/Y offset fields: digits, minus and comma only
        var _anim_numeric = false;
        if (input_target_node != noone && instance_exists(input_target_node)) {
            if (input_target_node.node_type == "MACRO_ANIM"
            &&  input_target_index >= 2 && input_target_index <= 26) {
                _anim_numeric = true;
            }
        }
        if (_anim_numeric) {
            var _clean = "";
            for (var _aci = 1; _aci <= string_length(_added); _aci++) {
                var _ach = string_char_at(_added, _aci);
                if ((_ach >= "0" && _ach <= "9") || _ach == "-" || _ach == ",") {
                    _clean += _ach;
                }
            }
            _added = _clean;
        }

        if (_has_sel) {
            current_input_string = string_delete(current_input_string, _sel_lo + 1, _sel_hi - _sel_lo);
            cursor_pos      = _sel_lo;
            input_sel_start = -1;
            input_sel_end   = -1;
        }
       if (_added != "" && string_length(current_input_string) + string_length(_added) <= char_limit) {
            current_input_string = string_insert(_added, current_input_string, cursor_pos + 1);
            cursor_pos += string_length(_added);
        }
        keyboard_string = "";
    }

    // ── Commit ──
    var _do_commit = false;
    if (_is_code_editor) {
        _do_commit = (keyboard_check_pressed(vk_enter) && _ctrl);
    } else {
        _do_commit = (keyboard_check_pressed(vk_enter) && !_shift);
    }
    if (_do_commit) {
        scr_node_commit(input_target_node, input_target_index, current_input_string);
        if (instance_exists(input_target_node)) input_target_node.height_dirty = true;
        is_entering_text = false;
        input_sel_start  = -1;
        input_sel_end    = -1;
        global.undo_dirty        = true;
        global.node_change_dirty = true;
        alarm[3]               = 6;
        keyboard_string        = "";
        global.addresses_dirty = true;
        scr_c64_do_update_addresses();
        with (obj_c64_node) { last_overlap_check = false; overlap_check_dirty = true; stats_cache_dirty = true; }
    }

    // ── Escape ──
    if (keyboard_check_pressed(vk_escape)) {
        if (input_target_node != noone &&
            input_target_node.node_type == "MACRO_CODE" &&
            input_target_index == 0) {
            scr_node_commit(input_target_node, input_target_index, current_input_string);
            if (instance_exists(input_target_node)) input_target_node.height_dirty = true;
            global.undo_dirty        = true;
            global.node_change_dirty = true;
            global.addresses_dirty   = true;
            scr_c64_do_update_addresses();
            with (obj_c64_node) { last_overlap_check = false; overlap_check_dirty = true; stats_cache_dirty = true; }
        }
        is_entering_text = false;
        input_sel_start  = -1;
        input_sel_end    = -1;
    }
    exit;
}

// =============================================================
// WORKSPACE KEYBOARD SHORTCUTS
// =============================================================
// --- QUICK DEMO TOGGLE (CTRL+SHIFT+D) ---
/*
if (keyboard_check(vk_control) && keyboard_check(vk_shift)) {
    if (keyboard_check_pressed(ord("D"))) {
        global.lite = !global.lite;
        // Visual feedback in debug console
        show_debug_message("DEMO MODE: " + (global.lite ? "ON" : "OFF"));
    }
}*/

if (keyboard_check(vk_control) || scr_cmd_held()) {
    if (keyboard_check_pressed(ord("S"))) {
        global.isSaving = true;
        save_pending = true;
        exit;
    }
	
    if (keyboard_check_pressed(ord("L"))) { scr_load_workspace_dialog();  exit; }
    if (keyboard_check_pressed(ord("Z")) && !global.is_any_text_active) { scr_undo_step(-1); exit; }
    if (keyboard_check_pressed(ord("Y")) && !global.is_any_text_active) { scr_undo_step(1);  exit; }
}

if (keyboard_check_pressed(vk_f1))  { scr_cleanup_nodes(); scr_c64_update_addresses(); }
if (keyboard_check_pressed(vk_f4))  { trigger_export = true; }
if (keyboard_check_pressed(vk_f5))  { trigger_build = true; }
	if (keyboard_check_pressed(vk_f7)) {
	    global.autosave_mode = (global.autosave_mode + 1) mod 4;
	    var _ivs = [120, 300, 600, -1];
	    global.autosave_interval = _ivs[global.autosave_mode];
	    ini_open("c64devmachine.ini");
	    ini_write_real("autosave", "mode", global.autosave_mode);
	    ini_close();
	    var _next_iv = (global.autosave_mode != 3) ? global.autosave_interval : 9999;
	    alarm[4] = game_get_speed(gamespeed_fps) * _next_iv;
	    autosave_countdown = _next_iv;
	}





//if (keyboard_check_pressed(vk_f9)) {
//    var _undo_dir      = working_directory + "temp/undo/";
//    var _manifest_path = _undo_dir + "manifest.json";
//    if (file_exists(_manifest_path)) file_delete(_manifest_path);
//    game_restart();
//}

var zoom_speed = 0.01
if (!global.c64u_overlay_active and !opcode_finder_active and !global.any_picker_open) {
	if (keyboard_check_pressed(ord("X"))) { global.use_hex_display = !global.use_hex_display; }
}
var _pgzoom_mul = (keyboard_check(vk_control) || scr_cmd_held()) ? 5.0 : 3.0;
if (!global.c64u_overlay_active && !global.any_picker_open) {
	if (keyboard_check(vk_pageup))   cam_zoom_target -= zoom_speed * _pgzoom_mul;
	if (keyboard_check(vk_pagedown)) cam_zoom_target += zoom_speed * _pgzoom_mul;
}
if (!is_entering_text && !global.is_any_text_active && !global.c64u_overlay_active && !global.any_picker_open && !obj_asset_manager.viewer_open) {
    var _pan_mul = 1.0;
    if (keyboard_check(vk_shift)) {
        _pan_mul = 3.0;
    }
    var _pan_spd = 5 * cam_zoom * _pan_mul;
    var _cam_moved = false;
    if (keyboard_check(vk_up))    { cam_y -= _pan_spd; _cam_moved = true; }
    if (keyboard_check(vk_down))  { cam_y += _pan_spd; _cam_moved = true; }
    if (keyboard_check(vk_left))  { cam_x -= _pan_spd; _cam_moved = true; }
    if (keyboard_check(vk_right)) { cam_x += _pan_spd; _cam_moved = true; }
    if (_cam_moved) { global.undo_dirty = true; alarm[3] = 30; } // note: intentionally does not set autosave_dirty
	// quick zooms
	
	
	if keyboard_check_pressed(ord("1")) cam_zoom_target=1.0;
	if keyboard_check_pressed(ord("2")) cam_zoom_target=2.0;
	if keyboard_check_pressed(ord("3")) cam_zoom_target=3.5;
	if keyboard_check_pressed(ord("4")) cam_zoom_target=4.3;
	if keyboard_check_pressed(ord("5")) cam_zoom_target=6.0;		
	if keyboard_check_pressed(ord("6"))  showGrid =!showGrid
	if keyboard_check_pressed(ord("7")) 
	{paletteStyle++;
		if paletteStyle>sprite_get_number(spr_bkg)-1 paletteStyle=0
		badgeStyle=0
		buttonStyle=0
		if (paletteStyle == sprite_get_number(spr_palette_page)-1) {
			badgeStyle = sprite_get_number(spr_logobadge)-1;
			buttonStyle = sprite_get_number(spr_opcode_button)-2;
		} else if (paletteStyle>1) {
			badgeStyle=1;
			buttonStyle=2;
		} 
	}	
	if keyboard_check_pressed(ord("8")) 
	{bkgImg++;
		if bkgImg>sprite_get_number(spr_bkg)-1 bkgImg=0
	}	
	if keyboard_check_pressed(ord("9")) { uiChromeStyle = (uiChromeStyle + 1) mod 2; niceSliceFrm = (uiChromeStyle == 0) ? 0 : sprite_get_number(spr_glassSlice)-1; }
	if keyboard_check_pressed(ord("0")) {uiChromeStyle=0;niceSliceFrm=0;bkgImg=0;paletteStyle=0;buttonStyle=0}
	
}





if (keyboard_check_pressed(ord("B")) && !is_entering_text && !global.is_any_text_active && !global.any_picker_open) {
    global.box_drag_active = true;
    box_drag_live          = false;
}


if (keyboard_check_pressed(vk_home)) {
    cam_zoom_target = 1.0;
    cam_zoom        = 1.0;
    cam_x           = (room_width / 2) - (1920 / 2);
    cam_y           = 0;
    global.undo_dirty = true;
    alarm[3] = 6;
}


if (keyboard_check_pressed(vk_escape)) {
    if (readyToQuit == 0 and obj_asset_manager.editorClosed==1 && !obj_c64_node.label_picker_open && !global.any_picker_open && !global.c64u_overlay_active) { readyToQuit = 1; keyboard_clear(vk_escape); }
	if global.any_picker_open {
		obj_c64_node.label_picker_open = false;
		global.any_picker_open =false;
	}
}



if (keyboard_check_pressed(ord("Y")) && readyToQuit == 1) {
    game_end();
}

if (keyboard_check_pressed(ord("N")) && readyToQuit == 1) {
    readyToQuit = 0;
	keyboard_clear(ord("N"));
}


// --- Q QUICK-SPAWN MENU ---
// Start is gated by the standard text-entry/picker guard so it can't
// fire while typing or with another modal open. The progress/release
// branch below runs UNCONDITIONALLY once active, so qmenu_active can
// never get stuck true if that guard flips mid-hold (e.g. a picker
// opens while Q is still held) — it just cancels without spawning.
var _qmenu_can_start = !is_entering_text && !global.is_any_text_active && !global.any_picker_open && (gui_menu_open == -1);

if (_qmenu_can_start && keyboard_check_pressed(ord("W")) && !qmenu_active) {
    qmenu_active   = true;
    qmenu_open     = false;
    qmenu_timer    = 0;
    qmenu_anchor_x = mouse_x;
    qmenu_anchor_y = mouse_y;
    qmenu_gui_x    = device_mouse_x_to_gui(0);
    qmenu_gui_y    = device_mouse_y_to_gui(0);
    qmenu_hover    = -1;
}

if (qmenu_active) {
    if (keyboard_check(ord("W"))) {
        if (!qmenu_open) {
            qmenu_timer++;
            if (qmenu_timer >= 4) { // ~0.07s at 60fps
                qmenu_open = true;
            }
        }

        if (qmenu_open) {
            var _qmx = device_mouse_x_to_gui(0);
            var _qmy = device_mouse_y_to_gui(0);
            qmenu_hover = -1;
            for (var _qi = 0; _qi < array_length(qmenu_items); _qi++) {
                var _qr = scr_qmenu_layout(_qi, qmenu_gui_x, qmenu_gui_y);
                if (point_in_rectangle(_qmx, _qmy, _qr[0], _qr[1], _qr[2], _qr[3])) {
                    qmenu_hover = _qi;
                    break;
                }
            }
        }
    } else {
        // Q is no longer held (covers a normal release AND edge cases like
        // focus loss/alt-tab where a "released" event might not fire).
        // Only spawn if the guard is still clear at this moment.
        if (qmenu_open && qmenu_hover > -1 && _qmenu_can_start) {
            scr_node_spawn(qmenu_items[qmenu_hover].type, qmenu_anchor_x, qmenu_anchor_y);
            global.undo_dirty = true;
            alarm[3] = 6;
        }
        qmenu_active = false;
        qmenu_open   = false;
        qmenu_hover  = -1;
    }
}

// --- SHIFT+Q: add the hovered MACROS menu item to the custom quick menu ---
// gui_menu_open == 0 (MACROS dropdown open) and == -1 (nothing open) are
// mutually exclusive, so this can never collide with the Q-hold-to-open
// logic below — no extra guarding needed between the two.
if (gui_menu_open == 0 && hover_macro_type != ""
    && keyboard_check(vk_shift) && keyboard_check_pressed(ord("Q"))) {
    if (scr_uqmenu_add_item(hover_macro_type, hover_macro_title)) {
        global.qmenu_toast_text = "ADDED \"" + hover_macro_title + "\" to Quick menu (Q)";
        global.qmenu_toast_col  = c_lime;
        global.qmenu_toast_t    = global.qmenu_toast_dur;
    }
}

// --- Q CUSTOM QUICK-SPAWN MENU (user-built, circular) ---
var _uqmenu_can_start = !is_entering_text && !global.is_any_text_active && !global.any_picker_open && (gui_menu_open == -1);

if (_uqmenu_can_start && keyboard_check_pressed(ord("Q")) && !uqmenu_active) {
    uqmenu_active   = true;
    uqmenu_open     = false;
    uqmenu_timer    = 0;
    uqmenu_anchor_x = mouse_x;
    uqmenu_anchor_y = mouse_y;
    uqmenu_gui_x    = device_mouse_x_to_gui(0);
    uqmenu_gui_y    = device_mouse_y_to_gui(0);
    uqmenu_hover    = -1;
}

if (uqmenu_active) {
    if (keyboard_check(ord("Q"))) {
        if (!uqmenu_open) {
            uqmenu_timer++;
            if (uqmenu_timer >= 4) { // ~0.07s at 60fps, matches the W-menu speed
                uqmenu_open = true;
            }
        }

        var _ucount = array_length(global.user_quick_menu);
        if (uqmenu_open && _ucount > 0) {
            var _uqmx = device_mouse_x_to_gui(0);
            var _uqmy = device_mouse_y_to_gui(0);
            uqmenu_hover = -1;
            for (var _ui = 0; _ui < _ucount; _ui++) {
                var _ur = scr_uqmenu_layout_circular(_ui, _ucount, uqmenu_gui_x, uqmenu_gui_y, global.user_quick_menu[_ui].label);
                if (point_in_rectangle(_uqmx, _uqmy, _ur[0], _ur[1], _ur[2], _ur[3])) {
                    uqmenu_hover = _ui;
                    break;
                }
            }

            // Right-click a hovered item to remove it from the menu. Closes
            // the gesture on removal rather than keeping it open, since the
            // remaining items' indices shift and holding Q for a second
            // right-click on "the same spot" would silently hit whatever
            // slid into that position instead.
            if (uqmenu_hover > -1 && mouse_check_button_pressed(mb_right)) {
                var _uqmenu_removed_label = global.user_quick_menu[uqmenu_hover].label;
                scr_uqmenu_remove_item(uqmenu_hover);
                global.qmenu_toast_text = "REMOVED \"" + _uqmenu_removed_label + "\" from Quick menu";
                global.qmenu_toast_col  = make_color_rgb(255, 140, 60);
                global.qmenu_toast_t    = global.qmenu_toast_dur;
                uqmenu_active = false;
                uqmenu_open   = false;
                uqmenu_hover  = -1;
            }
        }
    } else {
        if (uqmenu_open && uqmenu_hover > -1 && _uqmenu_can_start) {
            var _uitem = global.user_quick_menu[uqmenu_hover];
            scr_node_spawn(_uitem.type, uqmenu_anchor_x, uqmenu_anchor_y);
            global.undo_dirty = true;
            alarm[3] = 6;
        }
        uqmenu_active = false;
        uqmenu_open   = false;
        uqmenu_hover  = -1;
    }
}

// --- NODE SPAWNING (blocked during text entry) ---
if (!is_entering_text && !global.is_any_text_active and !obj_asset_manager.viewer_open) {

    // Block shortcut spawning when hovering a connected node that isn't a
    // NORMAL node (i.e. a macro/data/etc node) — only NORMAL nodes are
    // eligible for the in-place toggle behaviour (J/R/L/S/etc).
    var _hover_node = noone;
    with (obj_c64_node) {
        if (node_type != "INIT" && is_connected &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            _hover_node = id;
            break;
        }
    }
    var _picker_is_open = global.any_picker_open;
    with (obj_c64_node) {
        if (label_picker_open) { _picker_is_open = true; break; }
    }
    // Block spawning while hovering ANY connected node (NORMAL included) — the
    // toggle-capable keys (R/J/S/L family) still work via their own in-place
    // toggle logic above, which runs independently of this flag.
    var _hover_blocks_spawn = (_hover_node != noone) || _picker_is_open;

    // Canvas utility nodes - keyboard shortcuts
if (keyboard_check_pressed(ord("A")) && !_hover_blocks_spawn) { scr_node_spawn("LABEL",   mouse_x, mouse_y); global.undo_dirty = true; alarm[3] = 6; }
if (keyboard_check_pressed(ord("C")) && global.comments_visible && !keyboard_check(vk_alt) && !keyboard_check(vk_shift) && !keyboard_check(vk_control) && !_hover_blocks_spawn) { scr_node_spawn("COMMENT", mouse_x, mouse_y); global.undo_dirty = true; alarm[3] = 6; }
if (keyboard_check_pressed(ord("C")) && keyboard_check(vk_alt) && !keyboard_check(vk_shift) && !keyboard_check(vk_control) && !global.lite && !_hover_blocks_spawn) {
	scr_node_spawn("MACRO_CODE", mouse_x, mouse_y); 
    global.undo_dirty = true; 
    alarm[3] = 6;
}
if (keyboard_check_pressed(ord("O")) && !_hover_blocks_spawn) { scr_node_spawn("ORG",     mouse_x, mouse_y); global.undo_dirty = true; alarm[3] = 6; }
	
	if (keyboard_check_pressed(ord("R"))) {
        var _toggled = false;
        with (obj_c64_node) {
            if (!_toggled && node_type == "NORMAL" &&
                point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
                var _mn = string_lower(string(instructions[0][0]));
                if (_mn == "rts") {
                    instructions[0][0] = "rti";
                    node_title         = "RTI";
                    global.addresses_dirty = true;
                    _toggled = true;
                } else if (_mn == "rti") {
                    instructions[0][0] = "rts";
                    node_title         = "RTS";
                    global.addresses_dirty = true;
                    _toggled = true;
                }
            }
        }
		if (!_toggled && !_hover_blocks_spawn) {
            var _n          = instance_create_layer(mouse_x, mouse_y, "Layer_Nodes", obj_c64_node);
            _n.node_title   = "RTS";
            _n.node_type    = "NORMAL";
            _n.instructions = [["rts", 0]];
            _n.pc_address   = global.start_pc;
            with(_n) { event_user(0); }
        }
        global.undo_dirty = true;
        alarm[3] = 6;
    }
	
	if (keyboard_check_pressed(ord("N")) && !_hover_blocks_spawn) {
            var _n          = instance_create_layer(mouse_x, mouse_y, "Layer_Nodes", obj_c64_node);
            _n.node_title   = "NOP";
            _n.node_type    = "NORMAL";
            _n.instructions = [["nop", 0]];
            _n.pc_address   = global.start_pc;
            with(_n) { event_user(0); }
            global.undo_dirty = true;
            alarm[3] = 6;
		 }

if (keyboard_check_pressed(ord("J"))  && !keyboard_check(vk_alt) )   {
        // If hovering a NORMAL node with jmp/jsr as first instruction, toggle between them
        var _toggled = false;
        with (obj_c64_node) {
            if (!_toggled && node_type == "NORMAL" &&
                point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
                var _mn = string_lower(string(instructions[0][0]));
                if (_mn == "jmp_abs" || _mn == "jmp_ind" || _mn == "jmp") {
                    instructions[0][0] = "jsr";
                    node_title         = "JSR";
                    global.addresses_dirty = true;
                    _toggled = true;
                } else if (_mn == "jsr") {
                    instructions[0][0] = "jmp_abs";
                    node_title         = "JMP";
                    global.addresses_dirty = true;
                    _toggled = true;
                }
            }
        }
		if (!_toggled && !_hover_blocks_spawn) {
            var _n          = instance_create_depth(mouse_x, mouse_y, -500, obj_c64_node);
            _n.node_title   = "JMP";
            _n.node_type    = "NORMAL";
            _n.instructions = [["jmp_abs", "target"]];
            with(_n) { event_user(0); }
            _n.pc_address         = 0;
            _n.last_overlap_check = false;
            with (obj_c64_node) { last_overlap_check = false; }
        }
        global.undo_dirty = true;
        alarm[3] = 6;
    }

if (keyboard_check_pressed(ord("S")) && !keyboard_check(vk_control) && !keyboard_check(vk_shift) && !keyboard_check(vk_lalt) && !obj_workspace_manager.is_entering_text) {
    // STA addressing-mode cycle order (matches palette grid left-to-right, top-to-bottom)
    // No IMM - you can't store an immediate
    var _sta_cycle    = ["sta_zp", "sta_zpx", "sta_abs", "sta_abx", "sta_aby", "sta_izx", "sta_izy"];
    var _sta_titles   = ["STA_ZP", "STA_ZPX", "STA_ABS", "STA_ABX", "STA_ABY", "STA_IZX", "STA_IZY"];
    var _sta_defaults = [0,        0,         0xD020,    0xD020,    0xD020,    0xFB,      0xFB     ];

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_sta_cycle); _ci++) {
                if (_sta_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next = (_idx + 1) mod array_length(_sta_cycle);
                instructions[0][0]     = _sta_cycle[_next];
                instructions[0][1]     = _sta_defaults[_next];
                node_title             = _sta_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "STA_ABS";
        _n.instructions = [["sta_abs", 0xD020]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}

if (keyboard_check_pressed(ord("S")) && keyboard_check(vk_shift) && !keyboard_check(vk_control) && !obj_workspace_manager.is_entering_text) {
    // STX addressing-mode cycle order (no IMM - can't store immediate; X can't index itself)
    var _stx_cycle    = ["stx_zp", "stx_zpy", "stx_abs"];
    var _stx_titles   = ["STX_ZP", "STX_ZPY", "STX_ABS"];
    var _stx_defaults = [0,        0,         0xD020   ];

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_stx_cycle); _ci++) {
                if (_stx_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next = (_idx + 1) mod array_length(_stx_cycle);
                instructions[0][0]     = _stx_cycle[_next];
                instructions[0][1]     = _stx_defaults[_next];
                node_title             = _stx_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "STX_ZP";
        _n.instructions = [["stx_zp", 0]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}

if (keyboard_check_pressed(ord("S")) && keyboard_check(vk_lalt) && !keyboard_check(vk_control) && !obj_workspace_manager.is_entering_text) {
    // STY addressing-mode cycle order (no IMM - can't store immediate; Y can't index itself)
    var _sty_cycle    = ["sty_zp", "sty_zpx", "sty_abs"];
    var _sty_titles   = ["STY_ZP", "STY_ZPX", "STY_ABS"];
    var _sty_defaults = [0,        0,         0xD020   ];

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_sty_cycle); _ci++) {
                if (_sty_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next = (_idx + 1) mod array_length(_sty_cycle);
                instructions[0][0]     = _sty_cycle[_next];
                instructions[0][1]     = _sty_defaults[_next];
                node_title             = _sty_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "STY_ZP";
        _n.instructions = [["sty_zp", 0]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}

if (keyboard_check_pressed(ord("C")) && keyboard_check(vk_shift) && !keyboard_check(vk_control) && !keyboard_check(vk_alt) && !obj_workspace_manager.is_entering_text) {
    // Compare family cycle: CMP (all 8 modes) -> CPX (3 modes) -> CPY (3 modes)
    // Matches palette grid left-to-right, top-to-bottom
    var _cmp_cycle    = ["cmp_imm", "cmp_zp", "cmp_zpx", "cmp_abs", "cmp_abx", "cmp_aby", "cmp_izx", "cmp_izy",
                         "cpx_imm", "cpx_zp", "cpx_abs",
                         "cpy_imm", "cpy_zp", "cpy_abs"];
    var _cmp_titles   = ["CMP_IMM", "CMP_ZP", "CMP_ZPX", "CMP_ABS", "CMP_ABX", "CMP_ABY", "CMP_IZX", "CMP_IZY",
                         "CPX_IMM", "CPX_ZP", "CPX_ABS",
                         "CPY_IMM", "CPY_ZP", "CPY_ABS"];
    var _cmp_defaults = [0,         0,        0,         0xD020,    0xD020,    0xD020,    0xFB,      0xFB,
                         0,         0,        0xD020,
                         0,         0,        0xD020   ];

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_cmp_cycle); _ci++) {
                if (_cmp_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next = (_idx + 1) mod array_length(_cmp_cycle);
                instructions[0][0]     = _cmp_cycle[_next];
                instructions[0][1]     = _cmp_defaults[_next];
                node_title             = _cmp_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "CMP_IMM";
        _n.instructions = [["cmp_imm", 0]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}

if (keyboard_check_pressed(ord("D")) && keyboard_check(vk_shift) && !keyboard_check(vk_control) && !keyboard_check(vk_lalt) && !obj_workspace_manager.is_entering_text) {
    // DEC family cycle (matches palette grid)
    // Mix of implied (DEX/DEY, no operand) and addressed (DEC_xxx, with operand)
    var _dec_cycle    = ["dex", "dey", "dec_zp", "dec_zpx", "dec_abs", "dec_abx"];
    var _dec_titles   = ["DEX", "DEY", "DEC_ZP", "DEC_ZPX", "DEC_ABS", "DEC_ABX"];
    var _dec_defaults = [-1,    -1,    0,        0,         0xD020,    0xD020   ]; // -1 = implied, no operand

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_dec_cycle); _ci++) {
                if (_dec_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next     = (_idx + 1) mod array_length(_dec_cycle);
                var _next_def = _dec_defaults[_next];
                if (_next_def == -1) {
                    instructions[0] = [_dec_cycle[_next]];
                } else {
                    instructions[0] = [_dec_cycle[_next], _next_def];
                }
                node_title             = _dec_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "DEX";
        _n.instructions = [["dex",0]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}

if (keyboard_check_pressed(ord("I")) && keyboard_check(vk_shift) && !keyboard_check(vk_control) && !keyboard_check(vk_lalt) && !obj_workspace_manager.is_entering_text) {
    // INC family cycle (matches palette grid)
    // Mix of implied (INX/INY, no operand) and addressed (INC_xxx, with operand)
    var _inc_cycle    = ["inx", "iny", "inc_zp", "inc_zpx", "inc_abs", "inc_abx"];
    var _inc_titles   = ["INX", "INY", "INC_ZP", "INC_ZPX", "INC_ABS", "INC_ABX"];
    var _inc_defaults = [-1,    -1,    0,        0,         0xD020,    0xD020   ]; // -1 = implied, no operand

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_inc_cycle); _ci++) {
                if (_inc_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next     = (_idx + 1) mod array_length(_inc_cycle);
                var _next_def = _inc_defaults[_next];
                if (_next_def == -1) {
                    instructions[0] = [_inc_cycle[_next]];
                } else {
                    instructions[0] = [_inc_cycle[_next], _next_def];
                }
                node_title             = _inc_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "INX";
        _n.instructions = [["inx",0]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}

if (keyboard_check_pressed(ord("T")) && !keyboard_check(vk_control) && !keyboard_check(vk_shift) && !keyboard_check(vk_lalt) && !obj_workspace_manager.is_entering_text) {
    // Transfer instruction cycle (matches palette grid left-to-right, top-to-bottom)
    // No operands - these are 1-byte implied-addressing opcodes
    var _t_cycle  = ["tax", "tay", "tsx", "txa", "tya", "txs"];
    var _t_titles = ["TAX", "TAY", "TSX", "TXA", "TYA", "TXS"];

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_t_cycle); _ci++) {
                if (_t_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next = (_idx + 1) mod array_length(_t_cycle);
                instructions[0][0]     = _t_cycle[_next];
                node_title             = _t_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "TAX";
        _n.instructions = [["tax",0]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}

if (keyboard_check_pressed(ord("L")) && !keyboard_check(vk_shift) && !keyboard_check(vk_lalt) && !obj_workspace_manager.is_entering_text) {
    // LDA addressing-mode cycle order (matches palette grid left-to-right, top-to-bottom)
    var _lda_cycle    = ["lda_imm", "lda_zp", "lda_zpx", "lda_abs", "lda_abx", "lda_aby", "lda_izx", "lda_izy"];
    var _lda_titles   = ["LDA_IMM", "LDA_ZP", "LDA_ZPX", "LDA_ABS", "LDA_ABX", "LDA_ABY", "LDA_IZX", "LDA_IZY"];
    var _lda_defaults = [0,         0,        0,         0xD020,    0xD020,    0xD020,    0xFB,      0xFB     ];

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_lda_cycle); _ci++) {
                if (_lda_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next = (_idx + 1) mod array_length(_lda_cycle);
                instructions[0][0]     = _lda_cycle[_next];
                instructions[0][1]     = _lda_defaults[_next];
                node_title             = _lda_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "LDA_IMM";
        _n.instructions = [["lda_imm", 0]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}

if (keyboard_check_pressed(ord("L")) && keyboard_check(vk_shift) && !obj_workspace_manager.is_entering_text) {
    // LDX addressing-mode cycle order (no ZPX, no ABX, no IZX/IZY - X can't index itself)
    var _ldx_cycle    = ["ldx_imm", "ldx_zp", "ldx_zpy", "ldx_abs", "ldx_aby"];
    var _ldx_titles   = ["LDX_IMM", "LDX_ZP", "LDX_ZPY", "LDX_ABS", "LDX_ABY"];
    var _ldx_defaults = [0,         0,        0,         0xD020,    0xD020   ];

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_ldx_cycle); _ci++) {
                if (_ldx_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next = (_idx + 1) mod array_length(_ldx_cycle);
                instructions[0][0]     = _ldx_cycle[_next];
                instructions[0][1]     = _ldx_defaults[_next];
                node_title             = _ldx_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "LDX_IMM";
        _n.instructions = [["ldx_imm", 0]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}

if (keyboard_check_pressed(ord("L")) && keyboard_check(vk_lalt) && !obj_workspace_manager.is_entering_text) {
    // LDY addressing-mode cycle order (no ZPY, no ABY, no IZX/IZY - Y can't index itself)
    var _ldy_cycle    = ["ldy_imm", "ldy_zp", "ldy_zpx", "ldy_abs", "ldy_abx"];
    var _ldy_titles   = ["LDY_IMM", "LDY_ZP", "LDY_ZPX", "LDY_ABS", "LDY_ABX"];
    var _ldy_defaults = [0,         0,        0,         0xD020,    0xD020   ];

    var _toggled = false;
    with (obj_c64_node) {
        if (!_toggled && node_type == "NORMAL" &&
            point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
            var _mn  = string_lower(string(instructions[0][0]));
            var _idx = -1;
            for (var _ci = 0; _ci < array_length(_ldy_cycle); _ci++) {
                if (_ldy_cycle[_ci] == _mn) {
                    _idx = _ci;
                    break;
                }
            }
            if (_idx >= 0) {
                var _next = (_idx + 1) mod array_length(_ldy_cycle);
                instructions[0][0]     = _ldy_cycle[_next];
                instructions[0][1]     = _ldy_defaults[_next];
                node_title             = _ldy_titles[_next];
                global.addresses_dirty = true;
                _toggled               = true;
            }
        }
    }

    if (!_toggled && !_hover_blocks_spawn) {
        var _n          = scr_node_spawn("NORMAL", mouse_x, mouse_y);
        _n.node_title   = "LDY_IMM";
        _n.instructions = [["ldy_imm", 0]];
    }

    global.undo_dirty = true;
    alarm[3] = 6;
}
	
if keyboard_check_pressed(ord("J"))  {
    if (keyboard_check(vk_alt) && !_hover_blocks_spawn) {
        var _n        = scr_node_spawn("MACRO_JOY", mouse_x, mouse_y);
        _n.node_title = "JOYSTICK";
        global.undo_dirty = true;
        alarm[3] = 6;
	}
}

if keyboard_check_pressed(ord("M"))  {
    if (keyboard_check(vk_alt) && !_hover_blocks_spawn) {
        var _n        = scr_node_spawn("MACRO_MOVE", mouse_x, mouse_y);
        _n.node_title = "MACRO_MOVE";
        global.undo_dirty = true;
        alarm[3] = 6;
	}
}

if (keyboard_check_pressed(ord("V"))) {
    if (keyboard_check(vk_alt) && !_hover_blocks_spawn) {
        var _n        = scr_node_spawn("MACRO_VWAIT", mouse_x, mouse_y);
        _n.node_title = "VWAIT";
        global.undo_dirty = true;
        alarm[3] = 6;
    } else if (!_hover_blocks_spawn) {
        var _n            = instance_create_layer(mouse_x, mouse_y, "Layer_Nodes", obj_c64_node);
        _n.node_title     = "VARIABLES";
        _n.node_type      = "ORG";
        _n.proxy          = false;
        _n.is_draggable   = true;
        with (_n) { event_user(0); }
        _n.pc_address     = 0xC000;
        _n.proxy_address  = 0xC000;
        _n.end_address    = 0xC000;
        global.undo_dirty = true;
        alarm[3] = 6;
    }
}

    // Macro nodes are drag-only from the shelf - no shortcuts

	if (keyboard_check_pressed(vk_f3)) global.comments_visible = !global.comments_visible;
}



// =============================================================
// 2. LIVE PC BROADCAST & SPINE TRAVERSAL (DIRTY FLAG GATED)
// =============================================================
if (global.addresses_dirty) {
    global.addresses_dirty = false;

    var _spine_x   = (room_width / 2) - (global.node_display_width / 2);
    var current_nest = 0;
    ds_list_clear(global.node_chain);

    var _curr = noone;
    with(obj_c64_node) {
        if (node_type == "INIT" && x > 160) _curr = id;
    }

    var loop_guard = 0;
    while (instance_exists(_curr) && loop_guard < 256) {
        ds_list_add(global.node_chain, _curr);

        var first_inst = (array_length(_curr.instructions) > 0) ? string_lower(_curr.instructions[0][0]) : "";
        var is_branch  = (string_char_at(first_inst, 1) == "b" && string_length(first_inst) == 3);
        var is_jump    = (first_inst == "jmp" || first_inst == "jsr");
        _curr.nest_level = current_nest;
        if (_curr.node_type == "LABEL" || is_branch || is_jump) current_nest++;

        var max_content_width = global.node_display_width;
        if (variable_instance_exists(_curr, "instructions")) {
	for (var j = 0; j < array_length(_curr.instructions); j++) {
	    if (array_length(_curr.instructions[j]) < 2) continue;
	    var mnem = string_lower(_curr.instructions[j][0]);
                if (_curr.node_type == "DATA_TEXT" || mnem == "text" || mnem == "ascii") {
                    var txt_content = string(_curr.instructions[j][1]);
                    if (txt_content != "BIN_DATA_ACTIVE") {
                        var string_w = string_width("\"" + txt_content + "\"") + 220;
                        if (string_w > max_content_width) max_content_width = string_w;
                    }
                }
            }
        }
		if (_curr.node_type != "INIT") {
            _curr.width = clamp(max_content_width, global.node_display_width, 480);
        } 

        var _next     = noone;
        var _best_y   = 999999;
        var _curr_ref = _curr;
        var _curr_y   = _curr.y;
        with(obj_c64_node) {
            if (id != _curr_ref &&
                is_connected &&
                node_type != "EXECUTE" &&
                node_type != "ORG" &&
                org_parent == noone &&
abs(x - _spine_x) < global.node_display_width &&
                y > _curr_y &&
                y < (_curr_y + 300) &&
                y < _best_y) {
                _best_y = y;
                _next   = id;
            }
        }

        if (_next != noone) {
            _curr = _next;
        } else {
            _curr        = noone;
            current_nest = 0;
        }
        loop_guard++;
    }

}

// =============================================================
// 3. COMPILER & AUTO-VICE LAUNCH
// =============================================================

// F2: Silent build + VICE dump
if (keyboard_check_pressed(vk_f2)) {
    silent_build  = true;
    pending_dump  = true;
    trigger_build = true;
}

// --- F6: build & send to C64 Ultimate ---
if (keyboard_check_pressed(vk_f6) && !global.asset_reload_in_progress) {
    if (global.c64u_ip == "") {
        // No IP saved — open overlay; it ping-tests, saves on success, then kicks off build
        global.c64u_overlay_active = true;
        global.c64u_overlay_text   = "";
        global.c64u_overlay_error  = "";
        global.c64u_overlay_after  = "send_prg";
		global.canEditNode=0; // dont allow node editing until we close
		keyboard_string = "";
        keyboard_clear(vk_anykey);
    } else {
        trigger_c64u  = true;
        trigger_build = true;
    }
}

if (keyboard_check_pressed(vk_f8)) { scr_c64u_reset_ip(); }

if ( (scr_cmd_held()||keyboard_check(vk_control)) && keyboard_check(vk_shift) && keyboard_check_pressed(ord("F"))
    && !is_entering_text && !global.any_picker_open && !box_popup_open && !code_editor_open
    && !(instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open)) {
    label_search_open    = true;
    label_search_query   = "";
    label_search_cursor  = 0;
    label_search_ready   = false;
    label_search_results = [];
    label_search_index   = -1;
    keyboard_string       = "";
}

// --- C64U overlay input handling ---
scr_c64u_overlay_step();

var build_trigger = keyboard_check_pressed(vk_f5) || trigger_build;

// If F5 arrives while an asynchronous asset/MetaMap reload is still active,
// latch the request instead of losing the one-frame keypress. trigger_build
// remains set until the reload completes, then the normal build path runs.
if (keyboard_check_pressed(vk_f5) && global.asset_reload_in_progress) {
    trigger_build = true;
}

if (build_trigger && !global.asset_reload_in_progress) {
        trigger_build = false;
        global.egg_temp_node_ids = [];

        // =============================================================
        // SAFETY: Block build if any ORG is at $0000 with children
        // Zero page is not executable — building this crashes the C64
        // AND the assembler (negative byte-array offsets).
        // =============================================================
       var _zero_orgs = [];
        with (obj_c64_node) {
            if (node_type != "ORG") continue;
            if (node_title == "VARIABLES") continue;
            if (node_title == "HW REGISTERS") continue;
            if (pc_address != 0 && pc_address != -1) continue;
            var _self_zoid = id;
            var _has_kids_z = false;
            with (obj_c64_node) {
                if (org_parent == _self_zoid && is_connected) {
                    _has_kids_z = true;
                    break;
                }
            }
            if (_has_kids_z) array_push(_zero_orgs, id);
        }
        if (array_length(_zero_orgs) > 0) {
            // Focus camera on the first offending ORG at zoom level 1 so the
            // user is already looking at the problem when the dialog closes.
            var _first_offender = _zero_orgs[0];
            if (instance_exists(_first_offender)) {
                scr_focus_camera_on_node(_first_offender);
            }

            var _zmsg = "BUILD BLOCKED:\n\n";
            _zmsg += string(array_length(_zero_orgs)) + " ORG block(s) at $0000 with attached code/data.\n\n";
            _zmsg += "Zero page is not executable memory — this would crash the C64.\n\n";
            _zmsg += "Affected ORG titles:\n";
            for (var _zi = 0; _zi < array_length(_zero_orgs); _zi++) {
                var _zorg = _zero_orgs[_zi];
                _zmsg += "  - " + string(_zorg.node_title);
                if (variable_instance_exists(_zorg, "proxy") && _zorg.proxy) {
                    _zmsg += " (proxy not sensing)";
                }
                _zmsg += "\n";
            }
            _zmsg += "\nFix: enable PROXY on the ORG and chain it to a sized parent ORG,\nor set a manual address above $0800.";
            scr_show_message(_zmsg);
            silent_build = false;
            pending_dump = false;
            exit;
        }

        // =============================================================
        // SAFETY: Warn if the spine has no core loop and doesn't return
        // A "core loop" is a connected LABEL earlier in the chain whose
        // name is targeted by a connected JMP/JMP_ABS/JMP_IND further
        // down it (name-linked, label-before-jump). If none exists and
        // the spine's last node isn't RTS/RTI either, the C64 will run
        // off the end of the program into whatever memory follows it —
        // "bad code." Offer to append an RTS node and re-build.
        // =============================================================
        if (!ds_list_empty(global.node_chain)) {
            // Scan every CONNECTED node in the whole workspace, not just the
            // linear main-spine chain — a loop can just as validly live
            // inside an ORG block (org_parent != noone), which global.node_chain
            // deliberately excludes from the main traversal. MACRO_CODE blocks
            // are also parsed for their own labels/jumps, since a loop or an
            // RTS written as hand-typed text is just as real as one built
            // from LABEL/JMP/RTS nodes.
            //
            // A label+jump pair only counts as a genuine loop if the JMP
            // sits AFTER (below) its LABEL, in the same context (same
            // org_parent). A jump that targets a label further down the
            // spine is a forward jump, not a loop — it still runs off the
            // end if there's nothing after that label, so it must not be
            // allowed to silence this check. Within the same MACRO_CODE
            // block, "after" is decided by position in the text instead.
            var _loop_labels = []; // { name, node, y, org_parent, sub }
var _loop_jmps   = []; // { target, node, y, org_parent, sub }
var _any_return_found = false;

            with (obj_c64_node) {
                if (!is_connected) continue;
                if (array_length(instructions) == 0 || array_length(instructions[0]) == 0) continue;
                var _cmnem = string_lower(string(instructions[0][0]));
				// Any connected RTS/RTI anywhere is sufficient.
if (_cmnem == "rts" || _cmnem == "rti") {
    _any_return_found = true;
}

                if (_cmnem == "label" && array_length(instructions[0]) > 1) {
                    array_push(_loop_labels, { name: string(instructions[0][1]), node: id, y: y, org_parent: org_parent, sub: 0 });
                } else if ((_cmnem == "jmp" || _cmnem == "jmp_abs" || _cmnem == "jmp_ind")
                        && array_length(instructions[0]) > 1) {
                    array_push(_loop_jmps, { target: string(instructions[0][1]), node: id, y: y, org_parent: org_parent, sub: 0 });
                } else if (_cmnem == "code_block" && array_length(instructions[0]) > 1) {
                    var _cc_text = string(instructions[0][1]);
                    if (_cc_text != "") {
                        var _cc_parsed = scr_parse_asm_text(_cc_text);
                        for (var _cpi = 0; _cpi < array_length(_cc_parsed); _cpi++) {
                            var _cinst = _cc_parsed[_cpi];
                            var _ctype = string_lower(string(_cinst[0]));
							if (_ctype == "rts" || _ctype == "rti") {
    _any_return_found = true;
}
                            if (_ctype == "label" && array_length(_cinst) > 1) {
                                array_push(_loop_labels, { name: string(_cinst[1]), node: id, y: y, org_parent: org_parent, sub: _cpi });
                            } else if ((_ctype == "jmp" || _ctype == "jmp_abs" || _ctype == "jmp_ind")
                                    && array_length(_cinst) > 1) {
                                array_push(_loop_jmps, { target: string(_cinst[1]), node: id, y: y, org_parent: org_parent, sub: _cpi });
                            }
                        }
                    }
                }
            }

            var _core_loop_found = false;
            for (var _jti = 0; _jti < array_length(_loop_jmps) && !_core_loop_found; _jti++) {
                var _jmp = _loop_jmps[_jti];
                for (var _lti = 0; _lti < array_length(_loop_labels); _lti++) {
                    var _lbl = _loop_labels[_lti];
                    if (_lbl.name != _jmp.target || _lbl.org_parent != _jmp.org_parent) continue;
                    var _lbl_before = (_lbl.node == _jmp.node) ? (_lbl.sub < _jmp.sub) : (_lbl.y < _jmp.y);
                    if (_lbl_before) {
                        _core_loop_found = true;
                        break;
                    }
                }
            }

            var _chain_size = ds_list_size(global.node_chain);
            var _tail_node  = ds_list_find_value(global.node_chain, _chain_size - 1);
            var _tail_mnem = "";
            if (array_length(_tail_node.instructions) > 0 && array_length(_tail_node.instructions[0]) > 0) {
                _tail_mnem = string_lower(string(_tail_node.instructions[0][0]));
            }
            var _tail_is_return = (_tail_mnem == "rts" || _tail_mnem == "rti");

            // If the tail node is a MACRO_CODE block, its own last real
            // instruction decides this instead — walking back past any
            // trailing labels/comments/directives to find it.
            if (_tail_mnem == "code_block" && array_length(_tail_node.instructions[0]) > 1) {
                var _tail_code_text = string(_tail_node.instructions[0][1]);
                if (_tail_code_text != "") {
                    var _tail_parsed = scr_parse_asm_text(_tail_code_text);
                    for (var _tpi = array_length(_tail_parsed) - 1; _tpi >= 0; _tpi--) {
                        var _tp_type = string_lower(string(_tail_parsed[_tpi][0]));
                        if (_tp_type == "_line_map_" || _tp_type == "label" || _tp_type == "const" || _tp_type == "pc") continue;
                        _tail_is_return = (_tp_type == "rts" || _tp_type == "rti");
                        break;
                    }
                }
            }

            if (!_core_loop_found && !_any_return_found && !silent_build) {
                if (scr_show_question_bool("No core loop or RTS found in your spine.\n\nWithout one of these, the C64 will run off the end of your program into whatever memory comes next - usually a crash.\n\nAdd an RTS node at the end so it returns cleanly instead?")) {
                    var _rts_x = _tail_node.x;
                    var _rts_y = _tail_node.y + _tail_node.height + 20;
                    var _rts_n = instance_create_depth(_rts_x, _rts_y, -500, obj_c64_node);
                    _rts_n.node_title   = "RTS";
                    _rts_n.node_type    = "NORMAL";
                    _rts_n.instructions = [["rts"]];
                    with (_rts_n) { event_user(0); }
                    _rts_n.pc_address         = 0;
                    _rts_n.is_connected       = true;
                    _rts_n.height_dirty       = true;
                    _rts_n.last_overlap_check = false;
                    with (obj_c64_node) { last_overlap_check = false; overlap_check_dirty = true; }

                    global.undo_dirty        = true;
                    global.addresses_dirty   = true;
                    global.node_change_dirty = true;
					scr_c64_do_update_addresses();
                    alarm[3] = 6;

                    // Node just changed — let the spine rebuild and re-run
                    // the build fresh next frame instead of continuing now
                    // with a chain that no longer matches the graph.
                    trigger_build = true;
                    exit;

                } else if (scr_is_pristine_default_workspace()) {
                    // Declined the RTS fix, AND the workspace is still
                    // exactly the untouched default project (see
                    // scr_is_pristine_default_workspace) — silently attach
                    // a small pre-authored program below the real SYSTEM
                    // INIT node instead (the exact MACRO_PRINT/opcode
                    // nodes tested and saved in C64DM_START.json), so the
                    // normal compile pipeline picks them up and compiles
                    // them exactly as it would for a real spine. Falls
                    // straight through into the normal build — no exit —
                    // and the temp nodes are destroyed immediately after
                    // asset injection (see below), before this frame ever
                    // draws, so the real project is untouched
                    // and nothing is ever visible in the editor. Only
                    // reachable when the "no core loop / no RTS" question
                    // above was answered No — saying Yes just builds the
                    // (now no-longer-pristine) real project as normal.
                    var _egg_init = _tail_node; // the tail IS SYSTEM INIT when pristine
                    var _egg_x    = _egg_init.x;
                    var _egg_y    = _egg_init.y;

                    // Locate the pristine proxy ORG that becomes the hidden
                    // moveSprite subroutine container.
                    var _egg_org = noone;
                    for (var _eoi = 0; _eoi < instance_number(obj_c64_node); _eoi++) {
                        var _eon = instance_find(obj_c64_node, _eoi);
                        if (_eon.node_type == "ORG" && _eon.proxy) {
                            _egg_org = _eon;
                            break;
                        }
                    }

                    // The pristine proxy ORG still carries the address from
                    // the tiny default project. The full egg's main spine
                    // ends at $09A0, so place moveSprite there temporarily.
                    // Otherwise the secondary ORG pass overwrites the main
                    // program while it is being assembled.
                    global.egg_temp_org = _egg_org;
                    global.egg_temp_org_pc = instance_exists(_egg_org) ? _egg_org.pc_address : 0;
                    if (instance_exists(_egg_org)) _egg_org.pc_address = 0x09A0;

                    // The sprite asset exists only during this synchronous
                    // build. It is removed immediately after asset injection,
                    // before Draw GUI or autosave can expose it to the user.
                    var _egg_sprite_blob = "b64:AAAAAAAAAPgAA/4AB/4AD/4AHwYAHgH4PAHwPAHgPAAAPAAAPAAAHgAAHwYAD/4AB/4AA/4AAPgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB4AAB8AAB+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/gAD/gAH/gAP/gAfAfgeAfA8AeA8AAA8AAA8AAA8AAAeAAAfAAAP/gAH/gAD/gAA/gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHgAAHwAAH4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPAAB/AAH/HgP/fAfweA+AcA8AAB4AAB4AAB4AAB4AAB4AAA8AAA+AAAfwAAP/AAH/AAB/AAAPAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHAAAHgAAHwAAB4AAAAAAAAAAAAAAAAAAAAAAAAAA+AAD/wAH/wAPzwAPAAAeB+AeD8AeFQAeAAAeAAAPAAAPzwAH/wAD/wAA+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAqAAA/AAAfgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                    var _egg_sprite_buf  = scr_blob_decode(_egg_sprite_blob);
                    var _egg_asset_name  = "__C64DM_EGG_SPRITES";
                    var _egg_asset = {
                        name: _egg_asset_name,
                        type: "SPRITE_SET",
                        address: 0x2800,
                        file: "",
                        buffer: _egg_sprite_buf,
                        blob: _egg_sprite_blob,
                        linked_assets: [],
                        reu_used: 0,
                        reu_size: 0,
                        reu_filename: "",
                        d64_filename: "",
                        load_later: false,
                        egg_temp: true,
                        meta: {
                            used_count: 8,
                            sprite_mcs: [0,0,0,0,0,0,0,0],
                            sprite_ucs: [6,2,6,2,6,2,6,2],
                            format: "binary",
                            total_size: 512,
                            mc1_col: 1,
                            mc2_col: 2,
                            mc_fg: 1,
                            mc_bg: 0,
                            mc_col1: 1,
                            mc_col2: 2,
                            mc_mode: 0,
                            bg_col: 0
                        }
                    };
                    ds_list_add(obj_asset_manager.asset_list, _egg_asset);
                    global.egg_temp_asset = _egg_asset;

                    // Node specification copied from C64DM_START.json. The
                    // first ten entries extend SYSTEM INIT; the final four are
                    // children of the proxy ORG and form moveSprite.
                    var _egg_specs = [
                        { type:"MACRO_PRINT", title:"PRINT", dy:80, child:false, code:[["macro_print",4,1,13,0,"**** COMMODORE 64 DEV.MACH ****",8192,0,0,0,"",0,0,1024,0,"",0,""]] },
                        { type:"MACRO_PRINT", title:"PRINT", dy:280, child:false, code:[["macro_print",1,3,3,0,"64K RAM SYSTEM - POLYTRICITY (C) 2026 ",8224,0,0,0,"",0,0,1024,0,"",0,""]] },
                        { type:"MACRO_SPR", title:"SPRITE", dy:480, child:false, code:[["macro_spr",_egg_asset_name,0,20,231,0,1]] },
                        { type:"MACRO_SPR", title:"SPRITE", dy:620, child:false, code:[["macro_spr",_egg_asset_name,1,20,231,1,1]] },
                        { type:"MACRO_ANIM", title:"ANIMATE", dy:760, child:false, alias:"anim100742", code:[["macro_anim",4,"0,2,4,0,6","1,3,5,1,7","","","","","","","1","","","","","","","","","","","","","","","","","","","","","","","","",""]] },
                        { type:"MACRO_IRQ_HANDLER", title:"IRQ HANDLER", dy:1120, child:false, code:[["macro_irq_handler",0]] },
                        { type:"MACRO_IRQ", title:"MACRO IRQ", dy:1220, child:false, code:[["macro_irq",96,0,"","irq_0","moveSprite",1,""]] },
                        { type:"NORMAL", title:"LDA_IMM", dy:1320, child:false, code:[["lda_imm",4]] },
                        { type:"NORMAL", title:"STA_ABS", dy:1380, child:false, code:[["sta_abs",646]] },
                        { type:"NORMAL", title:"RTS", dy:1440, child:false, code:[["rts",0]] },
                        { type:"LABEL", title:"ADDRESS LABEL", dy:80, child:true, code:[["label","moveSprite"]] },
                        { type:"MACRO_MOVE", title:"MACRO MOVE", dy:120, child:true, code:[["macro_move",3,1,0,1,0,0,0,"",0,"",24,320,50,229]] },
                        { type:"NORMAL", title:"JSR", dy:260, child:true, code:[["jsr","anim100742_sub"]] },
                        { type:"NORMAL", title:"RTS", dy:320, child:true, code:[["rts",0]] }
                    ];

                    global.egg_temp_node_ids = [];
                    for (var _esi = 0; _esi < array_length(_egg_specs); _esi++) {
                        var _es = _egg_specs[_esi];
                        var _base_x = _es.child ? _egg_org.x : _egg_x;
                        var _base_y = _es.child ? _egg_org.y : _egg_y;
                        var _en = instance_create_depth(_base_x, _base_y + _es.dy, -500, obj_c64_node);
                        _en.node_type    = _es.type;
                        _en.node_title   = _es.title;
                        _en.instructions = _es.code;
                        _en.pc_address   = 0;
                        _en.is_connected = true;
                        _en.egg_temp     = true;
                        if (variable_struct_exists(_es, "alias")) _en.anim_alias = _es.alias;
                        with (_en) { event_user(0); }
                        // User Event 0 performs the node's normal defaults,
                        // including resetting org_parent. Attach ORG children
                        // only after that initialization has completed.
                        if (_es.child) _en.org_parent = _egg_org;
                        _en.height_dirty = true;
                        array_push(global.egg_temp_node_ids, _en);
                    }
                }
            }
        }

        show_debug_message("BUILD START: asset_reload_in_progress=" + string(global.asset_reload_in_progress));
        with (obj_asset_manager) {
            for (var _dbi = 0; _dbi < ds_list_size(asset_list); _dbi++) {
                var _dba = ds_list_find_value(asset_list, _dbi);
                show_debug_message("  ASSET: " + _dba.name + " type=" + _dba.type + " buf=" + string(buffer_exists(_dba.buffer)) + " sz=" + string(buffer_exists(_dba.buffer) ? buffer_get_size(_dba.buffer) : -1));
            }
        }
    
    // Trigger the scanline effect immediately before the compile
    // This catches F5, UI buttons, and code editor triggers!
    if !silent_build scan_active = true;
    scan_y = cam_y;

    // --- PREMIUM FEATURE CHECK ---
    if (global.lite == 1) {
        var _premium_found = false;
        with (obj_c64_node) {
            if (variable_instance_exists(id, "egg_temp") && egg_temp) continue;
            if ( is_connected && (
				        node_type == "MACRO_CODE"
				        || node_type == "MACRO_IRQ"
				        || node_type == "MACRO_MOVE_MEM"
				    )
				) {
                _premium_found = true;
                break;
            }
        }
        
        if (_premium_found) {
            if (show_question("BUILDING PRO FEATURES\n\nYour spine contains premium nodes (Code or IRQ) which cannot be built in the LITE version.\nPLEASE CONSIDER PURCHASING.\nWould you like to open the store page now?")) {
                url_open("https://polytricity.itch.io/the-c64-dev-machine");
            }
            exit; // Abort the build
        }
    }
    // -----------------------------


// -------------------------------------------------------------
// VICE launch sequencing
// Do NOT kill VICE before an expensive build. The old VICE instance is
// terminated only after the final PRG/D64 exists and the build queue is quiet.
// -------------------------------------------------------------
    if (ds_list_empty(global.node_chain)) {
        scr_show_message("BUILD FAILED: Spine is empty");
        exit;
    }

    var p_buf   = buffer_create(65536, buffer_fixed, 1);
    var base_pc = 0x0801;
 with (obj_c64_node) { if (node_type == "MACRO_VIC") show_debug_message("MACRO_VIC found - instructions[0]: " + string(instructions[0])); }
    // BASIC stub: 10 SYS 2062
    buffer_write(p_buf, buffer_u16, base_pc);
    buffer_write(p_buf, buffer_u16, 0x080B);
    buffer_write(p_buf, buffer_u16, 10);
    buffer_write(p_buf, buffer_u8,  0x9E);
    buffer_write(p_buf, buffer_u8,  0x20);
    buffer_write(p_buf, buffer_u8,  0x32);
    buffer_write(p_buf, buffer_u8,  0x30);
    buffer_write(p_buf, buffer_u8,  0x36);
    buffer_write(p_buf, buffer_u8,  0x32);
    buffer_write(p_buf, buffer_u8,  0x00);
    buffer_write(p_buf, buffer_u16, 0x0000);

	var final_code = scr_compile_chain();
show_debug_message("COMPILE RESULT: " + string(array_length(final_code)) + " instructions");
	var p          = c64_new_program();

	// Inject SID labels before assembling
// Inject KERNAL constant unconditionally
ds_map_replace(p.labels, "sid_getin", 0xFFE4);
//ds_map_replace(p.labels, "irq_hook_scroll", 0xEA81);

// Inject sid_init/sid_play from asset manager (MACRO_SID source of truth)
var _sid_labels_set = false;
with (obj_c64_node) {
    if (node_type == "MACRO_SID" && !_sid_labels_set) {
        var _asset_name_l = string(instructions[0][1]);
        if (instance_exists(obj_asset_manager)) {
            var _am_l = obj_asset_manager;
            for (var _ali = 0; _ali < ds_list_size(_am_l.asset_list); _ali++) {
                var _al = ds_list_find_value(_am_l.asset_list, _ali);
                if (_al.type == "SID_MUSIC" && (_al.name == _asset_name_l || _asset_name_l == "")) {
                    var _si = variable_struct_exists(_al.meta, "sid_init_addr") ? _al.meta.sid_init_addr : _al.address;
                    var _sp = variable_struct_exists(_al.meta, "sid_play_addr") ? _al.meta.sid_play_addr : _al.address + 3;
                    ds_map_replace(p.labels, "sid_init", _si);
                    ds_map_replace(p.labels, "sid_play", _sp);
                    _sid_labels_set = true;
                    show_debug_message("LABELS: sid_init=$" + string_upper(decimal_to_hex(_si))
                        + " sid_play=$" + string_upper(decimal_to_hex(_sp))
                        + " sid_getin=$FFE4");
                    break;
                }
            }
        }
    }
}
// Fallback: DATA_SID node on spine (legacy path)
if (!_sid_labels_set) {
    with (obj_c64_node) {
        if (node_type == "DATA_SID" && variable_instance_exists(id, "sid_init_addr") && sid_init_addr > 0) {
            ds_map_replace(p.labels, "sid_init", sid_init_addr);
            ds_map_replace(p.labels, "sid_play", sid_play_addr);
            _sid_labels_set = true;
            show_debug_message("LABELS (legacy DATA_SID): sid_init=$" + string_upper(decimal_to_hex(sid_init_addr)));
        }
    }
}

// ── Publish MACRO_CODE labels to global registry ──
    global.code_block_labels = {};
    var _pc_walk = global.start_pc;
    for (var _gi = 0; _gi < array_length(final_code); _gi++) {
        var _ge = final_code[_gi];
        var _gm = string_lower(_ge[0]);
        if (_gm == "label") {
            global.code_block_labels[$ string(_ge[1])] = _pc_walk;
        } else if (_gm != "org" && _gm != "comment" && _gm != "") {
            var _gsz = obj_opCodeManager.get_size(_gm);
            _pc_walk += max(0, _gsz);
        }
    }

show_debug_message("jsr_abs size=" + string(obj_opCodeManager.get_size("jsr_abs")));
// Pass 1: emit dummy bytes to track PC correctly, register all labels
var _p1_fixups_save = p.fixups;
p.fixups = [];
var _p1_byte_count = 0;

var _p1_debug_skip = "";
for (var i = 0; i < array_length(final_code); i++) {
    var _fc_mnem = string_lower(final_code[i][0]);
    if (_fc_mnem == "_line_map_" || _fc_mnem == "const") continue;
    if (_fc_mnem == "label" || _fc_mnem == "org") {
    p.assemble_instruction(_fc_mnem, final_code[i][1]);
    if (_fc_mnem == "label" && string_pos("L_EXIT_", string(final_code[i][1])) > 0)
        show_debug_message("P1 SKIP LABEL: " + string(final_code[i][1]) + " pc=$" + string_upper(decimal_to_hex(p.current_pc())));
    if (_fc_mnem == "label" && string_pos("L_SUB_", string(final_code[i][1])) > 0)
        show_debug_message("P1 L_SUB: [" + string(final_code[i][1]) + "] pc=$" + string_upper(decimal_to_hex(p.current_pc())) + " bytes_len=" + string(array_length(p.bytes)) + " override=" + string(p.pc_override));
} else {
        // Emit correct number of dummy bytes to keep PC accurate
        var _sz = obj_opCodeManager.get_size(_fc_mnem);
        if (_fc_mnem == "byte" || _fc_mnem == "byt") { _sz = 1; }
        if (_fc_mnem == "byte_lab_lo" || _fc_mnem == "byte_lab_hi") { _sz = 1; }
        if (_sz > 0) {
            if (_p1_byte_count <= 338 && _p1_byte_count + _sz > 335)
                show_debug_message("P1 near pos 338: i=" + string(i) + " mnem=[" + _fc_mnem + "] val=[" + string(final_code[i][1]) + "] sz=" + string(_sz) + " pc=$" + string_upper(decimal_to_hex(p.current_pc())));
            p.add(array_create(_sz, 0));
            _p1_byte_count += _sz;
        }
    }
}
// Reset for pass 2
p.bytes     = [];
p.fixups    = _p1_fixups_save;
p.pc_override = -1; 

// Pass 2: emit all instructions with labels already resolved
for (var i = 0; i < array_length(final_code); i++) {
    var _fc_mnem = string_lower(final_code[i][0]);
    if (_fc_mnem == "_line_map_" || _fc_mnem == "const") continue;
    if (array_length(final_code[i]) < 2) {
        show_debug_message("BARE INSTRUCTION (no operand): [" + _fc_mnem + "] at index " + string(i));
        p.assemble_instruction(_fc_mnem, 0);
        continue;
    }
    p.assemble_instruction(_fc_mnem, final_code[i][1]);
}


for (var _fi = 0; _fi < array_length(p.fixups); _fi++) {
    var _f = p.fixups[_fi];
    if (string_pos("fox_", string(_f.label)) > 0)
        show_debug_message("FOX FIXUP: label=[" + string(_f.label) + "] pos=" + string(_f.pos) + " type=" + _f.type + " in_labels=" + string(ds_map_exists(p.labels, _f.label)));
}
p.assemble();
var _vscroll_keys = ds_map_keys_to_array(p.labels);
for (var _di = 0; _di < array_length(_vscroll_keys); _di++) {
    if (string_pos("vs", _vscroll_keys[_di]) > 0 || string_pos("Scroller", _vscroll_keys[_di]) > 0)
        show_debug_message("VSCROLL LBL: " + _vscroll_keys[_di] + " = $" + string_upper(decimal_to_hex(p.labels[? _vscroll_keys[_di]])));
}
var _sid_off = (0x1000 - 0x0801 - 13);
if (_sid_labels_set) {
    if ((_sid_off + 3) < array_length(p.bytes)) {
        show_debug_message("SID Data @$1000: " + string(p.bytes[_sid_off]) + " " + string(p.bytes[_sid_off+1]) + " " + string(p.bytes[_sid_off+2]) + " " + string(p.bytes[_sid_off+3]));
    } else {
        show_debug_message("SID enabled but $1000 out of range (len=" + string(array_length(p.bytes)) + ")");
    }
}
// TEMP DEBUG - remove after fix
var _c000_off = (0xC000 - 0x0801 - 13);
if (_c000_off + 2 < array_length(p.bytes)) {
    show_debug_message("PRE-INJECT @$C000: "
        + string(p.bytes[_c000_off]) + " "
        + string(p.bytes[_c000_off+1]) + " "
        + string(p.bytes[_c000_off+2]));
} else {
    show_debug_message("PRE-INJECT: $C000 offset=" + string(_c000_off) + " NOT IN BYTES (len=" + string(array_length(p.bytes)) + ")");
}

var _dbk = ds_map_keys_to_array(p.labels);
for (var _di = 0; _di < array_length(_dbk); _di++) {
    if (string_pos("scroll", _dbk[_di]) > 0)
        show_debug_message("LABEL: " + _dbk[_di] + " = $" + string_upper(decimal_to_hex(p.labels[? _dbk[_di]])));
}

var _dbg_keys = ds_map_keys_to_array(p.labels);
    for (var _di = 0; _di < array_length(_dbg_keys); _di++) {
        if (string_pos("vflag", _dbg_keys[_di]) > 0 || string_pos("vcol", _dbg_keys[_di]) > 0 ||
            string_pos("vdir", _dbg_keys[_di]) > 0  || string_pos("vspd", _dbg_keys[_di]) > 0)
            show_debug_message("VAR " + _dbg_keys[_di] + " = $" + string_upper(decimal_to_hex(p.labels[? _dbg_keys[_di]])));
    }


    global.last_base_pc = global.start_pc;
    global.last_built   = true;


// Patch IRQ vector ($AA/$BB placeholders → sid_irq or ts_irq address)
    var _patch_irq_label = "";
    if (ds_map_exists(p.labels, "sid_irq")) {
        _patch_irq_label = "sid_irq";
    } else {
        var _allk = ds_map_keys_to_array(p.labels);
        for (var _ki = 0; _ki < array_length(_allk); _ki++) {
            if (string_pos("_irq", _allk[_ki]) > 0) { _patch_irq_label = _allk[_ki]; break; }
        }
    }
    if (_patch_irq_label != "") {
        var _irq_addr = ds_map_find_value(p.labels, _patch_irq_label);
        var _irq_lo   = _irq_addr & 0xFF;
        var _irq_hi   = (_irq_addr >> 8) & 0xFF;
        for (var _bi = 2; _bi < array_length(p.bytes) - 4; _bi++) {
			if (p.bytes[_bi] == 0xA9 && p.bytes[_bi+1] == 0xAA && p.bytes[_bi+2] == 0x8D &&
	                ((p.bytes[_bi+3] == 0x14 && p.bytes[_bi+4] == 0x03) ||
	                 (p.bytes[_bi+3] == 0xFE && p.bytes[_bi+4] == 0xFF))) {
	                p.bytes[_bi+1] = _irq_lo;
	            }
	            if (p.bytes[_bi] == 0xA9 && p.bytes[_bi+1] == 0xBB && p.bytes[_bi+2] == 0x8D &&
	                ((p.bytes[_bi+3] == 0x15 && p.bytes[_bi+4] == 0x03) ||
	                 (p.bytes[_bi+3] == 0xFF && p.bytes[_bi+4] == 0xFF))) {
	                p.bytes[_bi+1] = _irq_hi;
	            }
	        }
        show_debug_message("IRQ patch: " + _patch_irq_label + " = $" + string_upper(decimal_to_hex(_irq_addr)));
    }
	// Patch TEXT_SCROLL standalone IRQ vector — $CC/$DD placeholders → ts_irq address
	var _ds = ds_map_keys_to_array(p.labels);
	for (var _li = 0; _li < array_length(_ds); _li++) {
	    var _lname = string(_ds[_li]);
	    if (string_pos("_irq", _lname) == 0) continue;
	    if (_lname == "sid_irq") continue;
	    var _irq_addr = ds_map_find_value(p.labels, _lname);
	    var _irq_lo   = _irq_addr & 0xFF;
	    var _irq_hi   = (_irq_addr >> 8) & 0xFF;
	    for (var _bi = 2; _bi < array_length(p.bytes) - 4; _bi++) {
	        if (p.bytes[_bi] == 0xA9 && p.bytes[_bi+1] == 0xCC && p.bytes[_bi+2] == 0x8D && p.bytes[_bi+3] == 0x14 && p.bytes[_bi+4] == 0x03) {
	            p.bytes[_bi+1] = _irq_lo;
	        }
	        if (p.bytes[_bi] == 0xA9 && p.bytes[_bi+1] == 0xDD && p.bytes[_bi+2] == 0x8D && p.bytes[_bi+3] == 0x15 && p.bytes[_bi+4] == 0x03) {
	            p.bytes[_bi+1] = _irq_hi;
	        }
	    }
	}


show_debug_message("CC scan: bytes len=" + string(array_length(p.bytes)));
    for (var _bi2 = 2; _bi2 < min(array_length(p.bytes) - 4, 200); _bi2++) {
        if (p.bytes[_bi2] == 0xA9 && p.bytes[_bi2+1] == 0xCC) {
            show_debug_message("FOUND CC at byte idx=" + string(_bi2) + " next=" + string(p.bytes[_bi2+2]));
        }
        if (p.bytes[_bi2] == 0xA9 && p.bytes[_bi2+1] == 0xDD) {
            show_debug_message("FOUND DD at byte idx=" + string(_bi2));
        }
    }
// Verify text data at $C000
/*
    var _c000_off = (0xC000 - 0x0801 - 13);
    if (_c000_off < array_length(p.bytes)) {
        show_debug_message("TEXT@$C000: " + string(p.bytes[_c000_off]) + " " + string(p.bytes[_c000_off+1]) + " " + string(p.bytes[_c000_off+2]));
    } else {
        show_debug_message("TEXT@$C000: NOT IN BYTES ARRAY (len=" + string(array_length(p.bytes)) + ")");
    }
	*/
    // Cache AFTER IRQ patch so dump reflects final bytes
    var _len = array_length(p.bytes);
    global.last_bytes = array_create(_len, 0);
    for (var _ci = 0; _ci < _len; _ci++) {
        global.last_bytes[_ci] = p.bytes[_ci];
    }

    // Write assembled bytes to PRG buffer
    var _write_count = 0;
    for (var i = 0; i < array_length(p.bytes); i++) {
        var _raw = p.bytes[i];
        var _val = -1;
        if (is_real(_raw)) {
            _val = _raw;
        } else {
            var _str    = string(_raw);
            var _digits = string_digits(_str);
            if (_digits != "" && _digits == _str) _val = real(_digits);
        }
        if (_val != -1) {
            var _c64_addr   = base_pc + 13 + i;
            var _buf_offset = (_c64_addr - base_pc) + 2;
            if (_buf_offset >= 2 && _buf_offset < 65535) {
                buffer_seek(p_buf, buffer_seek_start, _buf_offset);
                buffer_write(p_buf, buffer_u8, _val);
                _write_count++;
            }
        } 
    }

show_debug_message("BYTES LEN=" + string(array_length(p.bytes))
    + " LAST_PC=$" + string_upper(decimal_to_hex(p.base_address + p.header_size + array_length(p.bytes))));
var _dbk2 = ds_map_keys_to_array(p.labels);
for (var _di2 = 0; _di2 < array_length(_dbk2); _di2++) {
    var _lname2 = _dbk2[_di2];
    if (string_pos("Scroller", _lname2) > 0 || string_pos("vs", _lname2) > 0
    || _lname2 == "target") {
        show_debug_message("  LBL " + _lname2 + " = $"
            + string_upper(decimal_to_hex(p.labels[? _lname2])));
    }
}
// ── DEBUG: check $2000 region in p.bytes BEFORE scr_node_build_inject ──
// MACRO_PRINT default text address is $2000 — verify the text bytes are still there
var _print_off = (0x2000 - 0x0801 - 13);
if (_print_off >= 0 && _print_off + 16 < array_length(p.bytes)) {
    var _print_dbg = "PRINT@$2000 (p.bytes): ";
    for (var _pi = 0; _pi < 16; _pi++) {
        _print_dbg += string(p.bytes[_print_off + _pi]) + " ";
    }
    show_debug_message(_print_dbg);
}

// Also check what's in p_buf at $2000 BEFORE inject
var _pb_off = (0x2000 - 0x0801) + 2; // base_pc=$0801 offset, +2 PRG header
var _pbuf_dbg = "PRINT@$2000 (p_buf pre-inject): ";
buffer_seek(p_buf, buffer_seek_start, _pb_off);
for (var _pi = 0; _pi < 16; _pi++) {
    _pbuf_dbg += string(buffer_read(p_buf, buffer_u8)) + " ";
}
show_debug_message(_pbuf_dbg);

scr_node_build_inject(p_buf, base_pc);

// Easter-egg nodes and its private sprite asset must survive until the
// injection above, then disappear before this frame can draw or autosave.
if (array_length(global.egg_temp_node_ids) > 0) {
    for (var _egi = 0; _egi < array_length(global.egg_temp_node_ids); _egi++) {
        var _egg_id = global.egg_temp_node_ids[_egi];
        if (instance_exists(_egg_id)) instance_destroy(_egg_id);
    }
    global.egg_temp_node_ids = [];
}
if (variable_global_exists("egg_temp_asset") && is_struct(global.egg_temp_asset)) {
    var _egg_asset_ref = global.egg_temp_asset;
    for (var _eai = ds_list_size(obj_asset_manager.asset_list) - 1; _eai >= 0; _eai--) {
        var _eat = ds_list_find_value(obj_asset_manager.asset_list, _eai);
        if (_eat == _egg_asset_ref || (variable_struct_exists(_eat, "egg_temp") && _eat.egg_temp)) {
            if (buffer_exists(_eat.buffer)) buffer_delete(_eat.buffer);
            ds_list_delete(obj_asset_manager.asset_list, _eai);
        }
    }
    global.egg_temp_asset = undefined;
}
if (variable_global_exists("egg_temp_org") && instance_exists(global.egg_temp_org)) {
    global.egg_temp_org.pc_address = global.egg_temp_org_pc;
}
global.egg_temp_org = noone;
scr_reu_build_images(export_dir);

// Check $2000 in p_buf AFTER inject
var _pbuf_dbg2 = "PRINT@$2000 (p_buf post-inject): ";
buffer_seek(p_buf, buffer_seek_start, _pb_off);
for (var _pi = 0; _pi < 16; _pi++) {
    _pbuf_dbg2 += string(buffer_read(p_buf, buffer_u8)) + " ";
}
show_debug_message(_pbuf_dbg2);

    // Check for LOAD_ORG assets → D64 build
    var _has_load_org = false;
    if (instance_exists(obj_asset_manager)) {
        var _am_chk = obj_asset_manager;
        for (var _ci = 0; _ci < ds_list_size(_am_chk.asset_list); _ci++) {
            if (ds_list_find_value(_am_chk.asset_list, _ci).type == "LOAD_ORG") {
                _has_load_org = true; break;
            }
        }
    }

    // Require a connected MACRO_LOADER, MACRO_SAVE_GAME, or MACRO_LOAD_GAME
    // node to justify a D64 build
    var _has_loader = false;
    with (obj_c64_node) {
        if ((node_type == "MACRO_LOADER" || node_type == "MACRO_SAVE_GAME" || node_type == "MACRO_LOAD_GAME") && is_connected) {
            _has_loader = true;
        }
    }

    if (_has_load_org && _has_loader) {
        // ---------------------------------------------------------
        // Compute TRUE boot size by trimming trailing bytes that fall
        // inside LOAD_ORG asset address ranges (those load from disk,
        // not from BOOT) and trailing zero padding.
        // ---------------------------------------------------------
        var _load_org_ranges = [];
        if (instance_exists(obj_asset_manager)) {
            var _am_bs = obj_asset_manager;
            for (var _lai = 0; _lai < ds_list_size(_am_bs.asset_list); _lai++) {
                var _la = ds_list_find_value(_am_bs.asset_list, _lai);
                if (_la.type != "LOAD_ORG") continue;
                if (!variable_struct_exists(_la, "linked_assets")) continue;
                var _lal = _la.linked_assets;
                for (var _lli = 0; _lli < array_length(_lal); _lli++) {
                    var _lnk = _lal[_lli];
                    if (variable_struct_exists(_lnk, "load_later") && _lnk.load_later) continue;
                    var _lname = _lnk.asset_name;
                    for (var _lbi = 0; _lbi < ds_list_size(_am_bs.asset_list); _lbi++) {
                        var _lb = ds_list_find_value(_am_bs.asset_list, _lbi);
                        if (_lb.name != _lname) continue;
                        if (!buffer_exists(_lb.buffer)) break;
                        var _lstart = _lb.address;
                        var _lend   = _lstart + buffer_get_size(_lb.buffer);
                        // BITMAP regions extend to $23E8 + 1000 from base
                        if (_lb.type == "BITMAP") {
                            _lend = _lstart + 0x27D0;
                        }
                        array_push(_load_org_ranges, { s: _lstart, e: _lend });
                        break;
                    }
                }
            }
        }

        // Walk p.bytes backwards, find the last byte that is NOT inside a
        // LOAD_ORG region AND is NOT trailing zero padding.
        var _true_end_idx = -1;
        var _byte_count   = array_length(p.bytes);
        for (var _bi = _byte_count - 1; _bi >= 0; _bi--) {
            var _byte_addr = global.start_pc + _bi;
            var _in_load   = false;
            for (var _ri = 0; _ri < array_length(_load_org_ranges); _ri++) {
                if (_byte_addr >= _load_org_ranges[_ri].s && _byte_addr < _load_org_ranges[_ri].e) {
                    _in_load = true;
                    break;
                }
            }
            if (_in_load) continue;
            // Skip trailing zero padding
            if (p.bytes[_bi] == 0) continue;
            _true_end_idx = _bi;
            break;
        }

        var _trimmed_byte_count = (_true_end_idx >= 0) ? (_true_end_idx + 1) : 0;

        // BOOT size = 2-byte PRG header + 13-byte BASIC stub + trimmed code
        var _boot_size = 15 + _trimmed_byte_count;
        show_debug_message("D64 BOOT: raw bytes=" + string(_byte_count)
            + " trimmed=" + string(_trimmed_byte_count)
            + " load_org_ranges=" + string(array_length(_load_org_ranges)));

        ds_map_destroy(p.labels);

        var _d64_path = scr_build_d64(p_buf, base_pc, _boot_size);

        // Save the boot PRG to a temp path BEFORE deleting p_buf, so we can
        // DMA-run it via run_prg while the D64 stays mounted for MACRO_LOADER.
        var _boot_prg_path = obj_workspace_manager.export_dir + "boot.prg";
        var _boot_prg_buf  = buffer_create(_boot_size, buffer_fixed, 1);
        buffer_copy(p_buf, 0, _boot_size, _boot_prg_buf, 0);
        buffer_save(_boot_prg_buf, _boot_prg_path);
        buffer_delete(_boot_prg_buf);

        buffer_delete(p_buf);
		
		if (!silent_build && _d64_path != "") {
            full_save_path = _d64_path;
            if (trigger_c64u) {
                trigger_c64u = false;
                scr_c64u_reu_begin("D64", _d64_path, _boot_prg_path);
            } else {
                global.vice_path_cache = scr_resolve_vice_path();
                if (global.vice_path_cache == "") {
                    show_debug_message("VICE not found - check installation or set override path.");
                }
                vice_launch_target  = full_save_path;
                    vice_launch_pending = true;
                    vice_launch_phase   = 0;
                    vice_launch_retry   = 0;
                    alarm[0] = 1;
            }
        }
		
		
    } else {
        buffer_save(p_buf, full_save_path);
        buffer_delete(p_buf);
        ds_map_destroy(p.labels);
        if (!silent_build) {
            if (trigger_c64u) {
                trigger_c64u = false;
                scr_c64u_reu_begin("PRG", full_save_path, "");
            } else {
                global.vice_path_cache = scr_resolve_vice_path();
                if (global.vice_path_cache == "") {
                    show_debug_message("VICE not found - check installation or set override path.");
                } else {
                    vice_launch_target  = full_save_path;
                    vice_launch_pending = true;
                    vice_launch_phase   = 0;
                    vice_launch_retry   = 0;
                    alarm[0] = 1;
                }
            }
        }
    }



    // Generate VICE dump if requested
    if (pending_dump) {
        pending_dump = false;
		
////////////////////////////////////////
// F2 CODE DUMP CODEDUMP
///////////////////////////////////////

#region
// ─── CODE-BLOCK COMPATIBLE DUMP ─────────────────────────────
        var _cb_txt = "; =============================================\n";
        _cb_txt += "; CODE BLOCK EXPORT - C64 DEV MACHINE\n";
        _cb_txt += "; (C) 2026 POLYTRICITY LTD\n";
        _cb_txt += "; =============================================\n\n";

// Build a flat list indexed by node instance ID so each node gets its own slice
        var _cb_node_slices = ds_map_create();

        // Build a NAMED_LOC address -> name lookup so references show // VARNAME comments
        var _cb_named_locs = ds_map_create();
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC") {
                if (array_length(instructions) > 0 && array_length(instructions[0]) > 1) {
                    var _nl_name = string_upper(string(instructions[0][1]));
                    var _nl_hex = string_upper(decimal_to_hex(pc_address));
                    while (string_length(_nl_hex) < 4) {
                        _nl_hex = "0" + _nl_hex;
                    }
                    ds_map_set(_cb_named_locs, "$" + _nl_hex, _nl_name);
                }
            }
        }

        var _cb_flat_pc = global.start_pc;
        // Build per-node slices directly from the [2] node tag on each instruction
        for (var _fi = 0; _fi < array_length(final_code); _fi++) {
            var _fe_raw = final_code[_fi];
            var _fm = string_lower(_fe_raw[0]);
            if (_fm == "_node_ref_" || _fm == "const" || _fm == "_line_map_") continue;
            // ORG resets the program counter mid-stream — follow it so PCs stay correct
            if (_fm == "org") {
                var _org_pc_a = _fe_raw[1];
                if (is_string(_org_pc_a)) {
                    _org_pc_a = real(_org_pc_a);
                }
                _cb_flat_pc = _org_pc_a;
                continue;
            }
            var _fv = (array_length(_fe_raw) > 1) ? _fe_raw[1] : 0; // bare instruction (e.g. plain RTS) — same guard as the pass 2 assembler above
            var _flabel = "";
            // If [1] is itself a string label (e.g. COND_IF branch targets), capture it
            if (is_string(_fv) && _fv != "" && _fv != "0") {
                _flabel = _fv;
                _fv = 0;
            }
            // Element [2] is the node tag (instance id) if it's a real/instance reference
            var _ftag = (array_length(_fe_raw) > 2) ? _fe_raw[2] : noone;
            var _fnode_key = "";
            if (_ftag != noone && !is_string(_ftag)) {
                _fnode_key = string(_ftag);
            }
            var _fs = obj_opCodeManager.get_size(_fm);
            if (_fm == "label") {
                if (_fnode_key != "" && !ds_map_exists(_cb_node_slices, _fnode_key)) {
                    ds_map_set(_cb_node_slices, _fnode_key, []);
                }
                if (_fnode_key != "") {
                    array_push(ds_map_find_value(_cb_node_slices, _fnode_key), { m: "label", v: _flabel, lbl: "", pc: _cb_flat_pc, sz: 0 });
                }
                continue;
            }
            if (_fm == "byte" || _fm == "byt") {
                if (_fnode_key != "") {
                    if (!ds_map_exists(_cb_node_slices, _fnode_key)) {
                        ds_map_set(_cb_node_slices, _fnode_key, []);
                    }
                    array_push(ds_map_find_value(_cb_node_slices, _fnode_key), { m: "byte", v: _fv, lbl: "", pc: _cb_flat_pc, sz: 1 });
                }
                _cb_flat_pc += 1;
                continue;
            }
            if (_fs <= 0) continue;
            if (_fnode_key != "") {
                if (!ds_map_exists(_cb_node_slices, _fnode_key)) {
                    ds_map_set(_cb_node_slices, _fnode_key, []);
                }
                array_push(ds_map_find_value(_cb_node_slices, _fnode_key), { m: _fm, v: _fv, lbl: _flabel, pc: _cb_flat_pc, sz: _fs });
            }
            _cb_flat_pc += _fs;
        }


        // Fallback flat list for nodes without sentinel tracking
        var _cb_flat = [];
        _cb_flat_pc = global.start_pc;
        for (var _fi = 0; _fi < array_length(final_code); _fi++) {
            var _fm = string_lower(final_code[_fi][0]);
            if (_fm == "_node_ref_") continue;
            // ORG resets the program counter mid-stream — follow it so label PCs stay correct
            if (_fm == "org") {
                var _org_pc_b = final_code[_fi][1];
                if (is_string(_org_pc_b)) {
                    _org_pc_b = real(_org_pc_b);
                }
                _cb_flat_pc = _org_pc_b;
                continue;
            }
            if (_fm == "const" || _fm == "_line_map_") continue;
            var _fv = final_code[_fi][1];
            var _flabel = "";
            if (is_string(_fv) && _fv != "" && _fv != "0") {
                _flabel = _fv;
                _fv = 0;
            } else if (array_length(final_code[_fi]) > 2 && is_string(final_code[_fi][2])) {
                _flabel = final_code[_fi][2];
            }
            if (_fm == "label") {
                array_push(_cb_flat, { m: "label", v: _flabel, lbl: "", pc: _cb_flat_pc, sz: 0 });
                continue;
            }
            if (_fm == "byte" || _fm == "byt") {
                array_push(_cb_flat, { m: "byte", v: _fv, lbl: "", pc: _cb_flat_pc, sz: 1 });
                _cb_flat_pc += 1;
                continue;
            }
            var _fs2 = obj_opCodeManager.get_size(_fm);
            if (_fs2 <= 0) {
                continue;
            }
            array_push(_cb_flat, { m: _fm, v: _fv, lbl: _flabel, pc: _cb_flat_pc, sz: _fs2 });
            _cb_flat_pc += _fs2;
        }

        // ─── GLOBAL POSITIONAL LABEL TABLE ──────────────────────────
        // Every label is placed purely by its own PC, claimed exactly once.
        // Built from both the slices (tagged labels) and the flat list
        // (untagged skip labels), so nothing is missed.
        var _cb_pending_labels = [];
        var _cb_label_seen = ds_map_create();

        // (a) pull tagged labels out of the slices
        var _slice_keys = ds_map_keys_to_array(_cb_node_slices);
        for (var _ski = 0; _ski < array_length(_slice_keys); _ski++) {
            var _slc = ds_map_find_value(_cb_node_slices, _slice_keys[_ski]);
            for (var _sei = 0; _sei < array_length(_slc); _sei++) {
                if (_slc[_sei].m == "label") {
                    var _ln = "";
                    if (is_string(_slc[_sei].v) && _slc[_sei].v != "") {
                        _ln = string(_slc[_sei].v);
                    } else if (_slc[_sei].lbl != "") {
                        _ln = string(_slc[_sei].lbl);
                    }
                    if (_ln != "") {
                        var _lk = _ln + "@" + string(_slc[_sei].pc);
                        if (!ds_map_exists(_cb_label_seen, _lk)) {
                            ds_map_set(_cb_label_seen, _lk, 1);
                            array_push(_cb_pending_labels, { name: _ln, pc: _slc[_sei].pc });
                        }
                    }
                }
            }
        }

        // (b) pull untagged labels out of the flat list
        for (var _pli = 0; _pli < array_length(_cb_flat); _pli++) {
            if (_cb_flat[_pli].m == "label") {
                var _pl_name = "";
                if (is_string(_cb_flat[_pli].v) && _cb_flat[_pli].v != "") {
                    _pl_name = string(_cb_flat[_pli].v);
                } else if (_cb_flat[_pli].lbl != "") {
                    _pl_name = string(_cb_flat[_pli].lbl);
                }
                if (_pl_name != "") {
                    var _pk = _pl_name + "@" + string(_cb_flat[_pli].pc);
                    if (!ds_map_exists(_cb_label_seen, _pk)) {
                        ds_map_set(_cb_label_seen, _pk, 1);
                        array_push(_cb_pending_labels, { name: _pl_name, pc: _cb_flat[_pli].pc });
                    }
                }
            }
        }
        ds_map_destroy(_cb_label_seen);

        array_sort(_cb_pending_labels, function(_a, _b) {
            if (_a.pc < _b.pc) {
                return -1;
            }
            if (_a.pc > _b.pc) {
                return 1;
            }
            return 0;
        });
        var _cb_label_claimed = ds_map_create();

        // Helper: append a // VARNAME comment if the formatted line references a known NAMED_LOC address
        var _cb_annotate_named = function(_line, _named_map) {
            var _addr_pos = string_pos("$", _line);
            if (_addr_pos == 0) {
                return _line;
            }
            var _hex = "";
            var _ci = _addr_pos + 1;
            while (_ci <= string_length(_line)) {
                var _ch = string_upper(string_char_at(_line, _ci));
                var _is_hex = (string_pos(_ch, "0123456789ABCDEF") > 0);
                if (!_is_hex) {
                    break;
                }
                _hex += _ch;
                _ci += 1;
            }
            if (string_length(_hex) < 4) {
                return _line;
            }
            var _key = "$" + string_copy(_hex, 1, 4);
            if (ds_map_exists(_named_map, _key)) {
                _line += "    // " + ds_map_find_value(_named_map, _key);
            }
            return _line;
        };

        // Helper: flush pending labels whose PC exactly matches _at_pc, once each.
        // Purely positional — a label prints immediately before the instruction
        // sitting at its own address, regardless of which node owns that PC.
        var _cb_flush_labels = function(_at_pc, _buf, _pending, _claimed) {
            for (var _fl_i = 0; _fl_i < array_length(_pending); _fl_i++) {
                var _pl = _pending[_fl_i];
                if (_pl.pc > _at_pc) {
                    break;
                }
                if (_pl.pc != _at_pc) {
                    continue;
                }
                var _pl_key = _pl.name + "@" + string(_pl.pc);
                if (ds_map_exists(_claimed, _pl_key)) {
                    continue;
                }
                ds_map_set(_claimed, _pl_key, 1);
                var _pl_hex = string_upper(decimal_to_hex(_pl.pc));
                while (string_length(_pl_hex) < 4) {
                    _pl_hex = "0" + _pl_hex;
                }
                _buf += _pl.name + ":    ; ($" + _pl_hex + ")\n";
            }
            return _buf;
        };

        // Helper: dump a node's instructions — takes and returns _cb_txt to avoid closure issues
        var _cb_dump_node = function(_nd, _running_pc, _buf, _flat, _slices, _named_map, _pending, _claimed) {
            if (_nd.node_type == "MACRO_CODE") {
                var _src = "";
                if (array_length(_nd.instructions) > 0 && array_length(_nd.instructions[0]) > 1) {
                    _src = string(_nd.instructions[0][1]);
                }
                var _src_lines = string_split(_src, "\n");
                for (var _sli = 0; _sli < array_length(_src_lines); _sli++) {
                    _buf += _src_lines[_sli] + "\n";
                }
            } else if (_nd.node_type == "NAMED_LOC") {
                if (array_length(_nd.instructions) > 0 && array_length(_nd.instructions[0]) > 1) {
                    var _vname = string_upper(string(_nd.instructions[0][1]));
                    var _vh2 = decimal_to_hex(_running_pc);
                    while (string_length(_vh2) < 4) {
                        _vh2 = "0" + _vh2;
                    }
                    _buf += _vname + " = $" + string_upper(_vh2) + "    ; named location\n";
                    // Claim both raw and upper-cased forms so the flush does not re-emit it
                    ds_map_set(_claimed, _vname + "@" + string(_running_pc), 1);
                    ds_map_set(_claimed, string(_nd.instructions[0][1]) + "@" + string(_running_pc), 1);
                }
            } else if (_nd.node_type == "LABEL") {
                if (array_length(_nd.instructions) > 0 && array_length(_nd.instructions[0]) > 1) {
                    var _lbl_addr_hex = decimal_to_hex(_running_pc);
                    while (string_length(_lbl_addr_hex) < 4) {
                        _lbl_addr_hex = "0" + _lbl_addr_hex;
                    }
                    var _lbl_name = string(_nd.instructions[0][1]);
                    _buf += _lbl_name + ":    ; ($" + string_upper(_lbl_addr_hex) + ")\n";
                    // Claim it so the positional flush in later nodes does not re-emit it
                    ds_map_set(_claimed, _lbl_name + "@" + string(_running_pc), 1);
                }
            } else if (_nd.node_type == "COMMENT") {
                if (array_length(_nd.instructions) > 0 && array_length(_nd.instructions[0]) > 1) {
                    var _cmt_src = string(_nd.instructions[0][1]);
                    var _cmt_lines = string_split(_cmt_src, "\n");
                    _buf += "\n";
                    for (var _cli = 0; _cli < array_length(_cmt_lines); _cli++) {
                        var _cl = string_trim(_cmt_lines[_cli]);
                        if (_cl != "") {
                            _buf += "// " + _cl + "\n";
                        }
                    }
                    _buf += "\n";
                }
            } else {
                // For simple NORMAL nodes, emit directly from instructions array
                // This avoids PC range bleed and correctly handles label operands
                if (_nd.node_type == "NORMAL") {
                    var _nr_pc = _running_pc;
                    for (var _ni2 = 0; _ni2 < array_length(_nd.instructions); _ni2++) {
                        var _nm = string_lower(string(_nd.instructions[_ni2][0]));
                        var _nv = _nd.instructions[_ni2][1];
                        var _ns = obj_opCodeManager.get_size(_nm);
                        if (_ns <= 0) continue;
                        // Flush labels sitting exactly at this PC
                        for (var _nfl_i = 0; _nfl_i < array_length(_pending); _nfl_i++) {
                            var _nfl = _pending[_nfl_i];
                            if (_nfl.pc > _nr_pc) {
                                break;
                            }
                            if (_nfl.pc != _nr_pc) {
                                continue;
                            }
                            var _nfl_key = _nfl.name + "@" + string(_nfl.pc);
                            if (ds_map_exists(_claimed, _nfl_key)) {
                                continue;
                            }
                            ds_map_set(_claimed, _nfl_key, 1);
                            var _nfl_hex = string_upper(decimal_to_hex(_nfl.pc));
                            while (string_length(_nfl_hex) < 4) {
                                _nfl_hex = "0" + _nfl_hex;
                            }
                            _buf += _nfl.name + ":    ; ($" + _nfl_hex + ")\n";
                        }
                        var _ca_hex = decimal_to_hex(_nr_pc);
                        while (string_length(_ca_hex) < 4) {
                            _ca_hex = "0" + _ca_hex;
                        }
                        // If operand is a string label, emit mnemonic + label directly
                        if (is_string(_nv) && _nv != "" && _nv != "0") {
                            _buf += scr_format_asm_label(_nm, string(_nv)) + "\n";
                        } else {
                            var _norm_line = scr_format_asm(_nm, _nv);
                            var _na_pos = string_pos("$", _norm_line);
                            if (_na_pos > 0) {
                                var _na_hex = "";
                                var _na_ci = _na_pos + 1;
                                while (_na_ci <= string_length(_norm_line)) {
                                    var _na_ch = string_upper(string_char_at(_norm_line, _na_ci));
                                    if (string_pos(_na_ch, "0123456789ABCDEF") == 0) {
                                        break;
                                    }
                                    _na_hex += _na_ch;
                                    _na_ci += 1;
                                }
                                if (string_length(_na_hex) >= 4) {
                                    var _na_key = "$" + string_copy(_na_hex, 1, 4);
                                    if (ds_map_exists(_named_map, _na_key)) {
                                        _norm_line += "    // " + ds_map_find_value(_named_map, _na_key);
                                    }
                                }
                            }
                            _buf += _norm_line + "\n";
                        }
                        _nr_pc += _ns;
                    }
                } else {
                    // Use per-node slice if available, else fall back to PC-range scan
                    var _use_slice = ds_map_exists(_slices, string(_nd.id));
                    var _slice = _use_slice ? ds_map_find_value(_slices, string(_nd.id)) : [];

                    if (!_use_slice) {
                        // PC range fallback
                        var _node_sz = _nd.total_node_size;
                        if (_node_sz <= 0) {
                            for (var _sz_i = 0; _sz_i < array_length(_nd.instructions); _sz_i++) {
                                var _sz_m = string_lower(string(_nd.instructions[_sz_i][0]));
                                _node_sz += max(obj_opCodeManager.get_size(_sz_m), 0);
                            }
                        }
                        if (_node_sz <= 0) _node_sz = 64;
                        var _node_end = _running_pc + _node_sz;
                        for (var _fi2 = 0; _fi2 < array_length(_flat); _fi2++) {
                            var _fe = _flat[_fi2];
                            if (_fe.pc < _running_pc) continue;
                            if (_fe.pc >= _node_end) break;
                            array_push(_slice, _fe);
                        }
                    }

                    for (var _si2 = 0; _si2 < array_length(_slice); _si2++) {
                        var _fe = _slice[_si2];
                        // Flush labels sitting exactly at this entry's PC (positional, once each)
                        for (var _sfl_i = 0; _sfl_i < array_length(_pending); _sfl_i++) {
                            var _sfl = _pending[_sfl_i];
                            if (_sfl.pc > _fe.pc) {
                                break;
                            }
                            if (_sfl.pc != _fe.pc) {
                                continue;
                            }
                            var _sfl_key = _sfl.name + "@" + string(_sfl.pc);
                            if (ds_map_exists(_claimed, _sfl_key)) {
                                continue;
                            }
                            ds_map_set(_claimed, _sfl_key, 1);
                            var _sfl_hex = string_upper(decimal_to_hex(_sfl.pc));
                            while (string_length(_sfl_hex) < 4) {
                                _sfl_hex = "0" + _sfl_hex;
                            }
                            _buf += _sfl.name + ":    ; ($" + _sfl_hex + ")\n";
                        }
                        if (_fe.m == "label") {
                            // Labels owned by the global positional table; already flushed above
                            continue;
                        }
                        var _ca_hex = decimal_to_hex(_fe.pc);
                        while (string_length(_ca_hex) < 4) {
                            _ca_hex = "0" + _ca_hex;
                        }
                        var _disp = "";
                        if (_fe.lbl != "" && is_string(_fe.lbl)) {
                            _disp = scr_format_asm_label(_fe.m, _fe.lbl);
                        } else if (_fe.m == "byte" || _fe.m == "byt") {
                            var _bh2 = string_upper(decimal_to_hex(_fe.v));
                            while (string_length(_bh2) < 2) {
                                _bh2 = "0" + _bh2;
                            }
                            _disp = ".byte $" + _bh2;
                        } else {
                            // RESCUE LOGIC: If this is a COND_IF jump that hasn't resolved yet
                            if ((_fe.m == "jmp_abs" || _fe.m == "jmp") && _fe.v == 0 && (_nd.node_type == "COND_IF" || _nd.node_type == "COND_IF_WORD")) {
						    		
                                var _cond_tgt = "";
                                if (array_length(_nd.instructions) > 0 && array_length(_nd.instructions[0]) > 3) {
                                    _cond_tgt = string(_nd.instructions[0][3]);
                                }
                                if (_cond_tgt != "") {
                                    _disp = "JMP " + _cond_tgt;
                                } else {
                                    _disp = scr_format_asm(_fe.m, _fe.v);
                                }
                            } else {
                                _disp = scr_format_asm(_fe.m, _fe.v);
                            }
                        }
                        var _da_pos = string_pos("$", _disp);
                        if (_da_pos > 0) {
                            var _da_hex = "";
                            var _da_ci = _da_pos + 1;
                            while (_da_ci <= string_length(_disp)) {
                                var _da_ch = string_upper(string_char_at(_disp, _da_ci));
                                if (string_pos(_da_ch, "0123456789ABCDEF") == 0) {
                                    break;
                                }
                                _da_hex += _da_ch;
                                _da_ci += 1;
                            }
                            if (string_length(_da_hex) >= 4) {
                                var _da_key = "$" + string_copy(_da_hex, 1, 4);
                                if (ds_map_exists(_named_map, _da_key)) {
                                    _disp += "    // " + ds_map_find_value(_named_map, _da_key);
                                }
                            }
                        }
                        _buf += _disp + "\n";
                    }
                }
            }
            return _buf;
        };

// Main spine chain — all node types, using a cursor to avoid PC-range bleed
        var _cb_flat_cursor = 0;
        for (var _cni = 0; _cni < ds_list_size(global.node_chain); _cni++) {
            var _cnode = ds_list_find_value(global.node_chain, _cni);
            if (!instance_exists(_cnode)) continue;

            var _cn_hex = decimal_to_hex(_cnode.pc_address);
            while (string_length(_cn_hex) < 4) _cn_hex = "0" + _cn_hex;
            var _cn_title = string_upper(_cnode.node_title);

            var _skip_header = (_cnode.node_type == "COMMENT" || _cn_title == "RTS" || _cn_title == "RTI" || _cn_title == "NOP");
            var _brief_header = (_cnode.node_type == "NORMAL" || _cnode.node_type == "LABEL" || _cnode.node_type == "NAMED_LOC");
            if (!_skip_header) {
                if (_brief_header) {
                    _cb_txt += "\n; --- " + _cn_title + " @ $" + string_upper(_cn_hex) + " ---\n";
                } else {
                    _cb_txt += "\n///////////////////////////////////////////\n";
                    _cb_txt += "// " + _cn_title + " [" + string_upper(_cnode.node_type) + "] @ $" + string_upper(_cn_hex) + "\n";
                    _cb_txt += "///////////////////////////////////////////\n";
                }
            }

            // Calculate this node's byte size for cursor advancement
            var _node_sz_cur = _cnode.total_node_size;
            if (_node_sz_cur <= 0) {
                _node_sz_cur = 0;
                for (var _isz = 0; _isz < array_length(_cnode.instructions); _isz++) {
                    var _ism = string_lower(string(_cnode.instructions[_isz][0]));
                    if (_ism == "byte" || _ism == "byt") {
                        _node_sz_cur += 1;
                    } else {
                        _node_sz_cur += max(obj_opCodeManager.get_size(_ism), 0);
                    }
                }
            }

            if (_cnode.node_type == "NORMAL" || _cnode.node_type == "LABEL" ||
                _cnode.node_type == "NAMED_LOC" || _cnode.node_type == "COMMENT" ||
                _cnode.node_type == "MACRO_CODE" ||
                ds_map_exists(_cb_node_slices, string(_cnode.id))) {
                // Emit via dump_node, but still advance cursor to stay in sync
                _cb_txt = _cb_dump_node(_cnode, _cnode.pc_address, _cb_txt, _cb_flat, _cb_node_slices, _cb_named_locs, _cb_pending_labels, _cb_label_claimed);
                var _skip = 0;
                while (_cb_flat_cursor < array_length(_cb_flat) && _skip < _node_sz_cur) {
                    _skip += _cb_flat[_cb_flat_cursor].sz;
                    _cb_flat_cursor++;
                }
            } else {
                // Flat cursor emit for macro nodes
                var _emitted = 0;
                while (_cb_flat_cursor < array_length(_cb_flat) && _emitted < _node_sz_cur) {
                    var _fe = _cb_flat[_cb_flat_cursor];
                    _cb_flat_cursor++;
                    _emitted += _fe.sz;
                    if (_fe.m == "label") {
                        _cb_txt = _cb_flush_labels(_fe.pc, _cb_txt, _cb_pending_labels, _cb_label_claimed);
                        continue;
                    }
                    _cb_txt = _cb_flush_labels(_fe.pc, _cb_txt, _cb_pending_labels, _cb_label_claimed);
                    if (_fe.lbl != "" && is_string(_fe.lbl)) {
                        _cb_txt += scr_format_asm_label(_fe.m, _fe.lbl) + "\n";
                    } else if (_fe.m == "byt" || _fe.m == "byte") {
                        var _bh = string_upper(decimal_to_hex(_fe.v));
                        while (string_length(_bh) < 2) {
                            _bh = "0" + _bh;
                        }
                        _cb_txt += ".byte $" + _bh + "\n";
                    } else {
                        var _mc_line = scr_format_asm(_fe.m, _fe.v);
                        _mc_line = _cb_annotate_named(_mc_line, _cb_named_locs);
                        _cb_txt += _mc_line + "\n";
                    }
                }
            }

            if (!_skip_header && !_brief_header) {
                _cb_txt += "// end of " + _cn_title + "\n";
            }
        }

// ORG blocks — all child node types, using same cursor approach as spine
        var _org_flat_cursor = 0; // separate cursor per ORG block, reset each ORG
        with (obj_c64_node) {
            if (node_type != "ORG") continue;
            var _org_ref2 = id;
            var _org_kids = [];
            with (obj_c64_node) {
                if (org_parent == _org_ref2 && is_connected) {
                    array_push(_org_kids, id);
                }
            }
            array_sort(_org_kids, function(_a, _b) {
                var _ay = 0;
                var _by = 0;
                if (instance_exists(_a)) {
                    _ay = _a.y;
                }
                if (instance_exists(_b)) {
                    _by = _b.y;
                }
                if (_ay < _by) {
                    return -1;
                }
                if (_ay > _by) {
                    return 1;
                }
                return 0;
            });

            var _oh2 = decimal_to_hex(pc_address);
            while (string_length(_oh2) < 4) _oh2 = "0" + _oh2;
            var _org_block_label = "ORG BLOCK";
            if (node_title == "VARIABLES") {
                _org_block_label = "VARS BLOCK";
            }
            _cb_txt += "\n///////////////////////////////////////////\n";
            _cb_txt += "// " + _org_block_label + " @ $" + string_upper(_oh2) + "\n";
            _cb_txt += "///////////////////////////////////////////\n";

            // Build a local flat list starting at this ORG's PC for cursor use
            var _org_flat = [];
            var _org_start_pc = pc_address;
            for (var _ofi = 0; _ofi < array_length(_cb_flat); _ofi++) {
                if (_cb_flat[_ofi].pc >= _org_start_pc) array_push(_org_flat, _cb_flat[_ofi]);
            }
            _org_flat_cursor = 0;

            for (var _oki = 0; _oki < array_length(_org_kids); _oki++) {
                var _ok = _org_kids[_oki];
                var _ok_hex = decimal_to_hex(_ok.pc_address);
                while (string_length(_ok_hex) < 4) _ok_hex = "0" + _ok_hex;
                var _ok_title = string_upper(_ok.node_title);
                var _ok_skip_header = (_ok.node_type == "COMMENT" || _ok_title == "RTS" || _ok_title == "RTI" || _ok_title == "NOP");
                var _ok_brief_header = (_ok.node_type == "NORMAL" || _ok.node_type == "LABEL" || _ok.node_type == "NAMED_LOC");

                if (!_ok_skip_header) {
                    if (_ok_brief_header) {
                        _cb_txt += "\n; --- " + _ok_title + " @ $" + string_upper(_ok_hex) + " ---\n";
                    } else {
                        _cb_txt += "\n///////////////////////////////////////////\n";
                        _cb_txt += "// " + _ok_title + " [" + string_upper(_ok.node_type) + "] @ $" + string_upper(_ok_hex) + "\n";
                        _cb_txt += "///////////////////////////////////////////\n";
                    }
                }

                // Compute size
                var _ok_sz = _ok.total_node_size;
                if (_ok_sz <= 0) {
                    _ok_sz = 0;
                    for (var _oisz = 0; _oisz < array_length(_ok.instructions); _oisz++) {
                        var _oism = string_lower(string(_ok.instructions[_oisz][0]));
                        if (_oism == "byte" || _oism == "byt") {
                            _ok_sz += 1;
                            continue;
                        }
                        _ok_sz += max(obj_opCodeManager.get_size(_oism), 0);
                    }
                }

                if (_ok.node_type == "NORMAL" || _ok.node_type == "LABEL" ||
                    _ok.node_type == "NAMED_LOC" || _ok.node_type == "COMMENT" ||
                    _ok.node_type == "MACRO_CODE" ||
                    ds_map_exists(_cb_node_slices, string(_ok.id))) {
                    _cb_txt = _cb_dump_node(_ok, _ok.pc_address, _cb_txt, _cb_flat, _cb_node_slices, _cb_named_locs, _cb_pending_labels, _cb_label_claimed);
                    // Advance org cursor
                    var _oskip = 0;
                    while (_org_flat_cursor < array_length(_org_flat) && _oskip < _ok_sz) {
                        _oskip += _org_flat[_org_flat_cursor].sz;
                        _org_flat_cursor++;
                    }
                } else {
                    // Flat cursor emit for macro nodes
                    var _oemitted = 0;
                    while (_org_flat_cursor < array_length(_org_flat) && _oemitted < _ok_sz) {
                        var _ofe = _org_flat[_org_flat_cursor];
                        _org_flat_cursor++;
                        _oemitted += _ofe.sz;
                        if (_ofe.m == "label") {
                            _cb_txt = _cb_flush_labels(_ofe.pc, _cb_txt, _cb_pending_labels, _cb_label_claimed);
                            continue;
                        }
                        _cb_txt = _cb_flush_labels(_ofe.pc, _cb_txt, _cb_pending_labels, _cb_label_claimed);
                        if (_ofe.lbl != "" && is_string(_ofe.lbl)) {
                            _cb_txt += scr_format_asm_label(_ofe.m, _ofe.lbl) + "\n";
                        } else if (_ofe.m == "byt" || _ofe.m == "byte") {
                            var _obh = string_upper(decimal_to_hex(_ofe.v));
                            while (string_length(_obh) < 2) {
                                _obh = "0" + _obh;
                            }
                            _cb_txt += ".byte $" + _obh + "\n";
                        } else {
                            var _org_line = scr_format_asm(_ofe.m, _ofe.v);
                            _org_line = _cb_annotate_named(_org_line, _cb_named_locs);
                            _cb_txt += _org_line + "\n";
                        }
                    }
                }
            }
        }

        // Sweep any labels that never matched an emitted instruction PC, so
        // nothing is silently dropped. Printed at the end, in PC order.
        var _cb_leftover = "";
        for (var _lf_i = 0; _lf_i < array_length(_cb_pending_labels); _lf_i++) {
            var _lf = _cb_pending_labels[_lf_i];
            var _lf_key = _lf.name + "@" + string(_lf.pc);
            if (ds_map_exists(_cb_label_claimed, _lf_key)) {
                continue;
            }
            ds_map_set(_cb_label_claimed, _lf_key, 1);
            var _lf_hex = string_upper(decimal_to_hex(_lf.pc));
            while (string_length(_lf_hex) < 4) {
                _lf_hex = "0" + _lf_hex;
            }
            _cb_leftover += _lf.name + ":    ; ($" + _lf_hex + ")\n";
        }
        if (_cb_leftover != "") {
            _cb_txt += "\n///////////////////////////////////////////\n";
            _cb_txt += "// UNPLACED LABELS (no instruction at exact PC)\n";
            _cb_txt += "///////////////////////////////////////////\n";
            _cb_txt += _cb_leftover;
        }

        ds_map_destroy(_cb_node_slices);
        ds_map_destroy(_cb_named_locs);
        ds_map_destroy(_cb_label_claimed);

        // Save code block dump — timestamp the filename so each dump is a unique
        // file. open() will not reload a same-named file on macOS, so a fresh
        // name guarantees the new contents are shown.
        var _cb_now = date_current_datetime();
        var _cb_mon = date_get_month(_cb_now);
        var _cb_day = date_get_day(_cb_now);
        var _cb_min = date_get_minute(_cb_now);
        var _cb_sec = date_get_second(_cb_now);

        var _cb_mon_s = string(_cb_mon);
        while (string_length(_cb_mon_s) < 2) {
            _cb_mon_s = "0" + _cb_mon_s;
        }
        var _cb_day_s = string(_cb_day);
        while (string_length(_cb_day_s) < 2) {
            _cb_day_s = "0" + _cb_day_s;
        }
        var _cb_min_s = string(_cb_min);
        while (string_length(_cb_min_s) < 2) {
            _cb_min_s = "0" + _cb_min_s;
        }
        var _cb_sec_s = string(_cb_sec);
        while (string_length(_cb_sec_s) < 2) {
            _cb_sec_s = "0" + _cb_sec_s;
        }

        var _cb_stamp = "_" + _cb_mon_s + "_" + _cb_day_s + "_" + _cb_min_s + "_" + _cb_sec_s;
        var _cb_path = export_dir + "vice_codedump" + _cb_stamp + ".txt";
        var _cbbuf = buffer_create(string_byte_length(_cb_txt) + 1, buffer_fixed, 1);
        buffer_write(_cbbuf, buffer_string, _cb_txt);
        buffer_save(_cbbuf, _cb_path);
        buffer_delete(_cbbuf);

        var _answer = show_question("Code block dump saved!\n" + _cb_path + "\n\nOpen it?");

        if (string(_answer) == "Yes" || string(_answer) == "1" || string(_answer) == "true") {

            if (os_type == os_macosx) {
                // Mac: wrap in /bin/sh -c "..." and call async, matching the VICE launch pattern.
                var _mac_cmd = "/bin/sh -c \"/usr/bin/open '" + _cb_path + "'\"";
                ProcessExecuteAsync(_mac_cmd);
            } else {
                execute_shell_simple("notepad.exe", _cb_path);
            }
        }

// ─── END CODE-BLOCK DUMP ─────────────────────────────────────
#endregion


/////////////////////////////////////

	silent_build  = false;
    } // end if (pending_dump)
silent_build  = false;
} // end if (build_trigger)

// =============================================================
// EXPORT .PRG (F4)
// =============================================================
var export_trigger = keyboard_check_pressed(vk_f4) || trigger_export;
if (export_trigger) {
    trigger_export = false;

    // =============================================================
    // SAFETY: Block export if any ORG is at $0000 with children
    // =============================================================
    var _zero_orgs_e = [];
    with (obj_c64_node) {
        if (node_type != "ORG") continue;
        if (node_title == "VARIABLES") continue;
        if (node_title == "HW REGISTERS") continue;
        if (pc_address != 0 && pc_address != -1) continue;
        var _self_zoid_e = id;
        var _has_kids_ze = false;
        with (obj_c64_node) {
            if (org_parent == _self_zoid_e && is_connected) {
                _has_kids_ze = true;
                break;
            }
        }
        if (_has_kids_ze) array_push(_zero_orgs_e, id);
    }
    if (array_length(_zero_orgs_e) > 0) {
        var _zmsg_e = "EXPORT BLOCKED:\n\n";
        _zmsg_e += string(array_length(_zero_orgs_e)) + " ORG block(s) at $0000 with attached code/data.\n\n";
        _zmsg_e += "Zero page is not executable memory — this would crash the C64.\n\n";
        _zmsg_e += "Fix: enable PROXY on the ORG and chain it to a sized parent ORG,\nor set a manual address above $0800.";
        scr_show_message(_zmsg_e);
        exit;
    }

    // --- PREMIUM FEATURE CHECK ---
    if (global.lite == 1) {
        var _premium_found = false;
        with (obj_c64_node) {
            if (is_connected && (node_type == "MACRO_CODE" || node_type == "MACRO_IRQ")) {
                _premium_found = true;
                break;
            }
        }
        if (_premium_found) {
            show_question(
                "BUILDING PRO FEATURES\n\nYour spine contains premium nodes (Code or IRQ) which cannot be built in the LITE version.\nPLEASE CONSIDER PURCHASING.\nWould you like to open the store page now?");
            exit; // Abort the build — answer handled async below
        }
    }
    // -----------------------------

    if (ds_list_empty(global.node_chain)) {
        scr_show_message("EXPORT FAILED: Spine is empty");
        pending_export_path = "";
        exit;
    }

    // Detect whether this build is a D64 (LOAD_ORG asset + connected MACRO_LOADER).
    // If so, there is NO .prg dialog — it exports program.d64 to export_dir,
    // identical to the F5 automatic path.
    var _exp_has_load_org = false;
    if (instance_exists(obj_asset_manager)) {
        var _exp_am_chk = obj_asset_manager;
        for (var _eci = 0; _eci < ds_list_size(_exp_am_chk.asset_list); _eci++) {
            if (ds_list_find_value(_exp_am_chk.asset_list, _eci).type == "LOAD_ORG") {
                _exp_has_load_org = true;
                break;
            }
        }
    }
    var _exp_has_loader = false;
    with (obj_c64_node) {
        if ((node_type == "MACRO_LOADER" || node_type == "MACRO_SAVE_GAME" || node_type == "MACRO_LOAD_GAME") && is_connected) {
            _exp_has_loader = true;
        }
    }
    var _exp_build_d64 = (_exp_has_load_org && _exp_has_loader);

    // Resolve the target path via dialog / pending path.
    var _chosen = pending_export_path;
    pending_export_path = "";
    if (_exp_build_d64) {
        if (_chosen == "") {
            _chosen = get_save_filename("C64 Disk Image|*.d64", "program");
            if (_chosen == "") exit;
            if (string_lower(filename_ext(_chosen)) != ".d64") _chosen += ".d64";
        }
    } else {
        if (_chosen == "") {
            _chosen = get_save_filename("C64 Program|*.prg", "export");
            if (_chosen == "") exit;
            if (string_lower(filename_ext(_chosen)) != ".prg") _chosen += ".prg";
        }
    }

    var _exp_buf = buffer_create(65536, buffer_fixed, 1);
    var _base_pc = 0x0801;
    buffer_write(_exp_buf, buffer_u16, _base_pc);
    buffer_write(_exp_buf, buffer_u16, 0x080B);
    buffer_write(_exp_buf, buffer_u16, 10);
    buffer_write(_exp_buf, buffer_u8,  0x9E);
    buffer_write(_exp_buf, buffer_u8,  0x20);
    buffer_write(_exp_buf, buffer_u8,  0x32);
    buffer_write(_exp_buf, buffer_u8,  0x30);
    buffer_write(_exp_buf, buffer_u8,  0x36);
    buffer_write(_exp_buf, buffer_u8,  0x32);
    buffer_write(_exp_buf, buffer_u8,  0x00);
    buffer_write(_exp_buf, buffer_u16, 0x0000);

    var _exp_code = scr_compile_chain();
    var _exp_p    = c64_new_program();

    // === SAME LABEL INJECTION AS F5 ===
    ds_map_replace(_exp_p.labels, "sid_getin",        0xFFE4);
    ds_map_replace(_exp_p.labels, "irq_hook_scroll",  0xEA81);

var _exp_sid_set = false;
with (obj_c64_node) {
    if (node_type == "MACRO_SID" && !_exp_sid_set) {
        var _an = string(instructions[0][1]);
        if (instance_exists(obj_asset_manager)) {
                var _am = obj_asset_manager;
                for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                    var _a = ds_list_find_value(_am.asset_list, _ai);
                    if (_a.type == "SID_MUSIC" && _a.name == _an) {
                        var _si = variable_struct_exists(_a.meta, "sid_init_addr") ? _a.meta.sid_init_addr : _a.address;
                        var _sp = variable_struct_exists(_a.meta, "sid_play_addr") ? _a.meta.sid_play_addr : _a.address + 3;
                        ds_map_replace(_exp_p.labels, "sid_init", _si);
                        ds_map_replace(_exp_p.labels, "sid_play", _sp);
                        _exp_sid_set = true;
                        break;
                    }
                }
            }
        }
    }
    if (!_exp_sid_set) {
        with (obj_c64_node) {
            if (node_type == "DATA_SID" && variable_instance_exists(id, "sid_init_addr") && sid_init_addr > 0) {
                ds_map_replace(_exp_p.labels, "sid_init", sid_init_addr);
                ds_map_replace(_exp_p.labels, "sid_play", sid_play_addr);
                _exp_sid_set = true;
            }
        }
    }
    // === END LABEL INJECTION ===

for (var i = 0; i < array_length(_exp_code); i++) {
    var _ec_mnem = string_lower(_exp_code[i][0]);
    if (_ec_mnem == "_line_map_" || _ec_mnem == "const") continue;
    _exp_p.assemble_instruction(_ec_mnem, _exp_code[i][1]);
}

    // === FIXUP PASS: resolve all forward JSR/JMP/branch/lab references ===
    _exp_p.assemble();
    // === END FIXUP PASS ===

    // === SAME IRQ PATCHING AS F5 ===
    var _exp_irq_label = "";
    if (ds_map_exists(_exp_p.labels, "sid_irq")) {
        _exp_irq_label = "sid_irq";
    } else {
        var _ek = ds_map_keys_to_array(_exp_p.labels);
        for (var _ei = 0; _ei < array_length(_ek); _ei++) {
            if (string_pos("_irq", _ek[_ei]) > 0) { _exp_irq_label = _ek[_ei]; break; }
        }
    }
    if (_exp_irq_label != "") {
        var _ea  = ds_map_find_value(_exp_p.labels, _exp_irq_label);
        var _elo = _ea & 0xFF;
        var _ehi = (_ea >> 8) & 0xFF;
        for (var _bi = 2; _bi < array_length(_exp_p.bytes) - 4; _bi++) {
            if (_exp_p.bytes[_bi] == 0xA9 && _exp_p.bytes[_bi+1] == 0xAA && _exp_p.bytes[_bi+2] == 0x8D &&
                ((_exp_p.bytes[_bi+3] == 0x14 && _exp_p.bytes[_bi+4] == 0x03) ||
                 (_exp_p.bytes[_bi+3] == 0xFE && _exp_p.bytes[_bi+4] == 0xFF))) {
                _exp_p.bytes[_bi+1] = _elo;
            }
            if (_exp_p.bytes[_bi] == 0xA9 && _exp_p.bytes[_bi+1] == 0xBB && _exp_p.bytes[_bi+2] == 0x8D &&
                ((_exp_p.bytes[_bi+3] == 0x15 && _exp_p.bytes[_bi+4] == 0x03) ||
                 (_exp_p.bytes[_bi+3] == 0xFF && _exp_p.bytes[_bi+4] == 0xFF))) {
                _exp_p.bytes[_bi+1] = _ehi;
            }
        }
    }
    // CC/DD text scroll IRQ patch
    var _edk = ds_map_keys_to_array(_exp_p.labels);
    for (var _li = 0; _li < array_length(_edk); _li++) {
        var _ln = string(_edk[_li]);
        if (string_pos("_irq", _ln) == 0) continue;
        if (_ln == "sid_irq") continue;
        var _la  = ds_map_find_value(_exp_p.labels, _ln);
        var _llo = _la & 0xFF;
        var _lhi = (_la >> 8) & 0xFF;
        for (var _bi = 2; _bi < array_length(_exp_p.bytes) - 4; _bi++) {
            if (_exp_p.bytes[_bi] == 0xA9 && _exp_p.bytes[_bi+1] == 0xCC && _exp_p.bytes[_bi+2] == 0x8D && _exp_p.bytes[_bi+3] == 0x14 && _exp_p.bytes[_bi+4] == 0x03) {
                _exp_p.bytes[_bi+1] = _llo;
            }
            if (_exp_p.bytes[_bi] == 0xA9 && _exp_p.bytes[_bi+1] == 0xDD && _exp_p.bytes[_bi+2] == 0x8D && _exp_p.bytes[_bi+3] == 0x15 && _exp_p.bytes[_bi+4] == 0x03) {
                _exp_p.bytes[_bi+1] = _lhi;
            }
        }
    }
    // === END IRQ PATCHING ===

    // Write bytes
    buffer_seek(_exp_buf, buffer_seek_start, 15);
    for (var i = 0; i < array_length(_exp_p.bytes); i++) {
        buffer_write(_exp_buf, buffer_u8, _exp_p.bytes[i]);
    }

    scr_node_build_inject(_exp_buf, _base_pc);
    scr_reu_build_images(filename_path(_chosen));

    var _exp_msg = "";

    if (!_exp_build_d64) {
        buffer_save(_exp_buf, _chosen);
        _exp_msg = "PRG exported to:\n" + _chosen;
    }

    // -------------------------------------------------------------
    // D64 EXPORT — a connected MACRO_LOADER + LOAD_ORG forces a .d64
    // (never a .prg). Writes program.d64 into export_dir, mirroring the
    // F5 automatic path, including the boot-trim logic: strip trailing
    // bytes that live inside LOAD_ORG asset ranges (those load from
    // disk) and trailing zero padding, so BOOT holds only resident code.
    // -------------------------------------------------------------
    if (_exp_build_d64) {
        var _exp_lor_ranges = [];
        if (instance_exists(obj_asset_manager)) {
            var _exp_am_bs = obj_asset_manager;
            for (var _elai = 0; _elai < ds_list_size(_exp_am_bs.asset_list); _elai++) {
                var _ela = ds_list_find_value(_exp_am_bs.asset_list, _elai);
                if (_ela.type != "LOAD_ORG") continue;
                if (!variable_struct_exists(_ela, "linked_assets")) continue;
                var _elal = _ela.linked_assets;
                for (var _elli = 0; _elli < array_length(_elal); _elli++) {
                    var _elnk = _elal[_elli];
                    if (variable_struct_exists(_elnk, "load_later") && _elnk.load_later) continue;
                    var _elname = _elnk.asset_name;
                    for (var _elbi = 0; _elbi < ds_list_size(_exp_am_bs.asset_list); _elbi++) {
                        var _elb = ds_list_find_value(_exp_am_bs.asset_list, _elbi);
                        if (_elb.name != _elname) continue;
                        if (!buffer_exists(_elb.buffer)) break;
                        var _elstart = _elb.address;
                        var _elend   = _elstart + buffer_get_size(_elb.buffer);
                        if (_elb.type == "BITMAP") {
                            _elend = _elstart + 0x27D0;
                        }
                        array_push(_exp_lor_ranges, { s: _elstart, e: _elend });
                        break;
                    }
                }
            }
        }

        // Walk emitted bytes backwards for last resident, non-padding byte.
        var _exp_true_end = -1;
        var _exp_bcount   = array_length(_exp_p.bytes);
        for (var _ebi = _exp_bcount - 1; _ebi >= 0; _ebi--) {
            var _ebyte_addr = _base_pc + _ebi;
            var _ein_load   = false;
            for (var _eri = 0; _eri < array_length(_exp_lor_ranges); _eri++) {
                if (_ebyte_addr >= _exp_lor_ranges[_eri].s && _ebyte_addr < _exp_lor_ranges[_eri].e) {
                    _ein_load = true;
                    break;
                }
            }
            if (_ein_load) continue;
            if (_exp_p.bytes[_ebi] == 0) continue;
            _exp_true_end = _ebi;
            break;
        }

        var _exp_trimmed = (_exp_true_end >= 0) ? (_exp_true_end + 1) : 0;
        // BOOT size = 2-byte PRG header + 13-byte BASIC stub + trimmed code
        var _exp_boot_size = 15 + _exp_trimmed;
        show_debug_message("D64 EXPORT: raw bytes=" + string(_exp_bcount)
            + " trimmed=" + string(_exp_trimmed)
            + " lor_ranges=" + string(array_length(_exp_lor_ranges)));

        var _exp_d64_path = scr_build_d64(_exp_buf, _base_pc, _exp_boot_size, _chosen);
        _exp_msg = "D64 exported to:\n" + _exp_d64_path;
    }

    buffer_delete(_exp_buf);
    ds_map_destroy(_exp_p.labels);

    show_debug_message("EXPORTED: " + _chosen);
    scr_show_message(_exp_msg);
}


// =============================================================
// 4. CAMERA & NAVIGATION
// =============================================================
var mouse_room_x = mouse_x;
var mouse_room_y = mouse_y;
var zoom_speed   = 0.1;



if (!instance_exists(obj_asset_manager) || 
    !point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y,
     obj_asset_manager.panel_x, obj_asset_manager.panel_y,
     obj_asset_manager.panel_x + obj_asset_manager.panel_w,
     display_get_gui_height() - 100)) {
		// Check if any node has a picker open
		var _any_picker = false;
		var _picker_node = noone;
		with (obj_c64_node) {
		    if (label_picker_open) {
		        _any_picker  = true;
		        _picker_node = id;
		        break;
		    }
		}

		if (_any_picker) {
		    // Route mousewheel to picker scroll
		    if (mouse_wheel_up()) {
		        _picker_node.label_picker_scroll = max(0, _picker_node.label_picker_scroll - 1);
		    }
		    if (mouse_wheel_down()) {
		        // Count for clamp
		        var _count = 0;
		        if (_picker_node.label_picker_mode == "VAR") {
		           if (_picker_node.label_picker_tab == "HW") {
                if (global.hw_picker_active_category == -1) {
                    _count = array_length(global.hw_picker_categories);
                } else {
                    _count = array_length(global.hw_picker_categories[global.hw_picker_active_category].items);
                }
            } else {
		                for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
	                    if (global.named_loc_meta[_ki].type != "UV") continue;
	                    if (_picker_node.label_picker_word_only) {
	                        var _wenc = variable_struct_exists(global.named_loc_meta[_ki], "encoding") ? global.named_loc_meta[_ki].encoding : "byte";
	                        if (_wenc != "word") continue;
	                    }
	                    if (_picker_node.label_picker_byte_only) {
	                        var _bsz = variable_struct_exists(global.named_loc_meta[_ki], "size") ? global.named_loc_meta[_ki].size : 1;
	                        if (_bsz != 1) continue;
	                    }
	                    _count++;
	                }
		            }
		        } else {
		            _count = array_length(_picker_node.label_picker_list);
		        }
		        var _visible = (_picker_node.label_picker_mode == "VAR") ? 10 : 8;
		        _picker_node.label_picker_scroll = min(max(0, _count - _visible), _picker_node.label_picker_scroll + 1);
		    }
		} else {
		// Normal camera zoom
var _zoom_mul = keyboard_check(vk_control) ? 5.0 : 3.0;
if (mouse_wheel_up())   { cam_zoom_target -= zoom_speed * _zoom_mul; global.undo_dirty = true; alarm[3] = 30; } // no autosave_dirty
if (mouse_wheel_down()) { cam_zoom_target += zoom_speed * _zoom_mul; global.undo_dirty = true; alarm[3] = 30; } // no autosave_dirty
	}
	cam_zoom_target = clamp(cam_zoom_target, 0.3, 6.0);
	cam_zoom        = lerp(cam_zoom, cam_zoom_target, 0.4);
	camera_set_view_size(cam_view, 1920 * cam_zoom, 1080 * cam_zoom);
	//global.mac_x2     = global.mac_x1 + macro_col_width;
	global.sc_x_start = global.gui_w - 20 - 280;
}

if (abs(cam_zoom - cam_zoom_target) > 0.001) {
    cam_x += (mouse_room_x - mouse_x);
    cam_y += (mouse_room_y - mouse_y);
}

var _any_node_dragging = false;
with (obj_c64_node) {
    if (is_dragging) { _any_node_dragging = true; break; }
}
// Any asset editor overlay (map painter, bitmap editor, etc.) that's open
// handles its own middle-mouse/space pan internally — without this guard,
// the same input also starts a workspace pan underneath it, so both the
// editor content and the node graph behind it move at once.
var _viewer_capturing_pan = instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open;
if ((mouse_check_button_pressed(mb_middle) || mouse_check_button_pressed(mb_right) || keyboard_check_pressed(vk_space)) && !_any_node_dragging && !_viewer_capturing_pan) {
    is_panning  = true;
    pan_x_start = device_mouse_raw_x(0);
    pan_y_start = device_mouse_raw_y(0);
}

if (is_panning) {
    if (_viewer_capturing_pan) {
        is_panning = false;
    } else {
    cam_x      -= (device_mouse_raw_x(0) - pan_x_start) * cam_zoom;
    cam_y      -= (device_mouse_raw_y(0) - pan_y_start) * cam_zoom;
    pan_x_start = device_mouse_raw_x(0);
    pan_y_start = device_mouse_raw_y(0);
	if (mouse_check_button_released(mb_middle) || mouse_check_button_released(mb_right) || keyboard_check_released(vk_space) || !window_has_focus()) {
        is_panning    = false;
        _was_panning  = true;
        //global.undo_dirty = true;
    }
    }
}
camera_set_view_pos(cam_view, cam_x, cam_y);

// MISC UPDATES
global.link_pulse += 0.025;
if (global.link_pulse > 1) global.link_pulse -= 1;

/////////////////////////////////////////////////////////////////
// MAPPING BOX DRAG
// Start point stored in room space so zoom/pan during drag is safe.
/////////////////////////////////////////////////////////////////
if (global.box_drag_active) {
	 show_debug_message("active=" + string(global.box_drag_active) + " live=" + string(box_drag_live));
	 
    // LMB down - record start in room space
    if (mouse_check_button_pressed(mb_left) && !box_drag_live) {
        box_drag_start_x = mouse_x;
        box_drag_start_y = mouse_y;
        box_drag_live    = true;
    }

    // LMB release - spawn box
    if (box_drag_live && mouse_check_button_released(mb_left)) {
        var _x1 = min(box_drag_start_x, mouse_x);
        var _y1 = min(box_drag_start_y, mouse_y);
        var _x2 = max(box_drag_start_x, mouse_x);
        var _y2 = max(box_drag_start_y, mouse_y);
        var _w  = _x2 - _x1;
        var _h  = _y2 - _y1;

        // Minimum size guard
        if (_w > 40 && _h > 40) {

            var _x1r = round(_x1 / 20) * 20;
            var _y1r = round(_y1 / 20) * 20;
            var _x2r = round(_x2 / 20) * 20;
            var _y2r = round(_y2 / 20) * 20;
            var _box          = instance_create_layer(_x1r, _y1r, "Layer_Boxes", obj_mapping_box);
            _box.box_w        = _x2r - _x1r;
            _box.box_h        = _y2r - _y1r;
            _box.box_name     = "BOX";
            _box.box_col_idx  = 0;
			global.undo_dirty = true;
            // Open popup
			box_popup_open    = true;
            box_popup_target  = _box;
            box_popup_name    = "BOX";
            box_popup_col_idx = box_next_col_idx;
            box_next_col_idx  = (box_next_col_idx + 1) mod 16;
            box_cursor_pos    = string_length(box_popup_name);
			box_popup_ready   = false; 
        }

        global.box_drag_active = false;
        box_drag_live          = false;
    }

    // Cancel with RMB or Escape
    if (mouse_check_button_pressed(mb_right) || keyboard_check_pressed(vk_escape)) {
        global.box_drag_active = false;
        box_drag_live          = false;
    }
}

/////////////////////////////////////////////////////////////////
// MAPPING BOX POPUP INPUT
/////////////////////////////////////////////////////////////////
if (box_popup_open && instance_exists(box_popup_target)) {

    // Absorb the spawning keypress on first frame
    if (!box_popup_ready) {
        keyboard_string = "";
        box_popup_ready = true;
    } else {
        // Ctrl+Backspace - clear entire name
        if (keyboard_check(vk_control) && keyboard_check_pressed(vk_backspace)) {
            box_popup_name  = "";
            box_cursor_pos  = 0;
            keyboard_string = "";
        } else {
            // Normal character input
            if (keyboard_string != "") {
                var _add = keyboard_string;
                if (string_length(box_popup_name) + string_length(_add) <= 24) {
                    box_popup_name  = string_insert(_add, box_popup_name, box_cursor_pos + 1);
                    box_cursor_pos += string_length(_add);
                }
                keyboard_string = "";
            }
            // Backspace
            if (keyboard_check_pressed(vk_backspace) && box_cursor_pos > 0) {
                box_popup_name = string_delete(box_popup_name, box_cursor_pos, 1);
                box_cursor_pos--;
                keyboard_string = "";
            }
            // Cursor movement
            if (keyboard_check_pressed(vk_left))  box_cursor_pos = max(0, box_cursor_pos - 1);
            if (keyboard_check_pressed(vk_right)) box_cursor_pos = min(string_length(box_popup_name), box_cursor_pos + 1);
        }
    }
    exit;
}


// =============================================================
// 5. QUIT & ESCAPE
// =============================================================
if (keyboard_check_pressed(vk_escape) && !global.c64u_overlay_active) {
    if (is_entering_text) {
        is_entering_text = false;
        keyboard_string  = "";
    } else if (readyToQuit == 0) {
       
        keyboard_clear(vk_escape);
    }
}

// MAPPING BOX QUICK NAV
if (!keyboard_check(vk_alt) && keyboard_check_pressed(ord("M")) && !is_entering_text && !global.any_picker_open) {

    global.show_map_nav = true;
	global.map_nav_x = global.gui_mouse_x;
    global.map_nav_y = global.gui_mouse_y;
}

if (!keyboard_check(vk_alt) && keyboard_check_released(ord("M")) && global.show_map_nav) {
    global.show_map_nav = false;

    var _nav_x = global.map_nav_x;
    var _nav_y = global.map_nav_y;
    var _row_h = 20;
    var _idx   = 0;

    with (obj_mapping_box) {
        var _ry = _nav_y + 20 + (_idx * _row_h);
        if (point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y,
            _nav_x, _ry, _nav_x + 200, _ry + _row_h)) {

            // Effective viewport in GUI pixels (shelf eats the left side)
            var _shelf_w  = expert_mode ? 0 : obj_workspace_manager.shelf_width;
            var _view_w   = 1920 - _shelf_w;   // usable width in GUI px
            var _view_h   = 1080;

            // Find zoom so the box fills 80% of the usable area
            var _fit_w    = (box_w > 0) ? (_view_w * 0.8) / box_w : 1.0;
            var _fit_h    = (box_h > 0) ? (_view_h * 0.8) / box_h : 1.0;
            var _new_zoom = 1.0 / min(_fit_w, _fit_h);
            _new_zoom     = clamp(_new_zoom, 0.3, 6.0);

            // Centre of the box in world space
            var _cx = x + box_w * 0.5;
            var _cy = y + box_h * 0.5;

            // Camera top-left so the box centre lands in the middle of the
            // usable area (right of shelf), not the middle of the full window.
            // cam_x/cam_y are world-space origins of the full 1920x1080 view,
            // so we shift right by the shelf width (in world units at new zoom).
            var _usable_centre_x = _shelf_w + (_view_w * 0.5);  // GUI px from left
            var _usable_centre_y = _view_h * 0.5;

            obj_workspace_manager.cam_x = _cx - (_usable_centre_x * _new_zoom);
            obj_workspace_manager.cam_y = _cy - (_usable_centre_y * _new_zoom);

			obj_workspace_manager.cam_zoom_target = _new_zoom;
            obj_workspace_manager.cam_zoom        = _new_zoom;
            global.undo_dirty = true;
            alarm[3] = 6;
            break;
        }
        _idx++;
    }
}

/////////////////////////////////////////////////////////////////
// BOX SELECT
/////////////////////////////////////////////////////////////////
var _in_gui = ((global.gui_mouse_x <= shelf_width) && (!expert_mode || global.gui_mouse_y < 47))
           || (global.gui_mouse_x >= (global.gui_w - 20 - 280))
           || is_entering_text
           || box_popup_open
           || global.show_info_window
           || global.show_helper_window;
		   
// Start drag
if (mouse_check_button_pressed(mb_left) && keyboard_check(vk_control) && !_in_gui && !box_select_active) {
    var _hit = false;
with (obj_c64_node) {
        if (node_type == "INIT") continue;
        if (point_in_rectangle(mouse_x, mouse_y, x + x_indent, y, x + x_indent + width, y + height)) { _hit = true; break; }
    }
    if (!_hit) {
        box_select_active = true;
        box_select_x1     = mouse_x;
        box_select_y1     = mouse_y;
        box_select_x2     = mouse_x;
        box_select_y2     = mouse_y;
    }
}

// Update drag
if (box_select_active) {
    box_select_x2 = mouse_x;
    box_select_y2 = mouse_y;

    // Release — commit selection
    if (mouse_check_button_released(mb_left)) {
        var _rx1 = min(box_select_x1, box_select_x2);
        var _ry1 = min(box_select_y1, box_select_y2);
        var _rx2 = max(box_select_x1, box_select_x2);
        var _ry2 = max(box_select_y1, box_select_y2);
	global.selected_nodes = [];
	with (obj_c64_node) {
	            if (node_type == "INIT") continue;
	            var _passes = (x + x_indent < _rx2 && x + x_indent + width > _rx1 && y < _ry2 && y + height > _ry1);
	            if (_passes) show_debug_message("SELECTED: " + node_type + " x=" + string(x) + " indent=" + string(x_indent) + " w=" + string(width) + " rx1=" + string(_rx1) + " rx2=" + string(_rx2));
	            if (_passes) array_push(global.selected_nodes, id);
	        }
box_select_active = false;

// ---- PRE-COMPUTE GROUP HANDLE (topmost eligible node) ----
        global.group_drag_handle = noone;
        var _best_y = 999999;
        for (var _si = 0; _si < array_length(global.selected_nodes); _si++) {
            var _sn = global.selected_nodes[_si];
            if (!instance_exists(_sn)) continue;
            if (_sn.node_type == "INIT" || _sn.node_type == "ORG") continue;
            var _is_free = (string_pos("DATA", _sn.node_type) > 0 ||
                            _sn.node_type == "RAW_DATA" ||
                            _sn.node_type == "SPR64"    ||
                            _sn.node_type == "BITMAP_KLA");
            if (_is_free) continue;
            show_debug_message("CANDIDATE: " + _sn.node_type + " x=" + string(_sn.x) + " y=" + string(_sn.y));
            if (_sn.y < _best_y) {
                _best_y = _sn.y;
                global.group_drag_handle = _sn;
            }
        }
        if (instance_exists(global.group_drag_handle))
            show_debug_message("HANDLE SET: " + global.group_drag_handle.node_type + " y=" + string(global.group_drag_handle.y));
    }
}

// Deselect on any click in scene (no ctrl) — but not if clicking the group drag handle
var _clicking_handle = false;
if (instance_exists(global.group_drag_handle) && mouse_check_button_pressed(mb_left)) {
    var _hn = global.group_drag_handle;
    if (point_in_rectangle(mouse_x, mouse_y, _hn.x, _hn.y, _hn.x + _hn.width, _hn.y + _hn.height)) {
        _clicking_handle = true;
    }
}
if ((mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right))
    && !keyboard_check(vk_control) && !_in_gui && !_clicking_handle) {
    global.selected_nodes    = [];
    global.group_drag_handle = noone;
    global.group_drag_active = false;
    global.group_drag_nodes  = [];
}

// Clear label-reference highlight on any left click
if (mouse_check_button_pressed(mb_left)) {
    global.ref_highlight_source = noone;
    global.ref_highlight_name   = "";
}

/////////////////////////////////////////////////////////////////
// DOUBLE-CLICK BOX BODY ZOOM (cam_zoom > 3)
/////////////////////////////////////////////////////////////////
if (box_body_dbl_timer > 0) box_body_dbl_timer--;

if (mouse_check_button_pressed(mb_left)  && !box_popup_open) {
    var _hit_box = noone;
    with (obj_mapping_box) {
        var _z  = obj_workspace_manager.cam_zoom;
        var _cx = obj_workspace_manager.cam_x;
        var _cy = obj_workspace_manager.cam_y;
        var _sx1 = (x         - _cx) / _z;
        var _sy1 = (y         - _cy) / _z;
        var _sx2 = (x + box_w - _cx) / _z;
        var _sy2 = (y + box_h - _cy) / _z;
        if (global.gui_mouse_x >= _sx1 && global.gui_mouse_x <= _sx2 &&
            global.gui_mouse_y >= _sy1 && global.gui_mouse_y <= _sy2) {
            _hit_box = id;
            break;
        }
    }

	
    if (instance_exists(_hit_box) && keyboard_check(vk_alt)) {
        if (box_body_dbl_timer > 0 && box_body_dbl_target == _hit_box) {
            // Double-click confirmed — zoom to box
            var _shelf_w  = expert_mode ? 0 : shelf_width;
            var _view_w   = 1920 - _shelf_w;
            var _view_h   = 1080;
            var _fit_w    = (_hit_box.box_w > 0) ? (_view_w * 0.8) / _hit_box.box_w : 1.0;
            var _fit_h    = (_hit_box.box_h > 0) ? (_view_h * 0.8) / _hit_box.box_h : 1.0;
            var _new_zoom = 1.0 / min(_fit_w, _fit_h);
            _new_zoom     = clamp(_new_zoom, 0.3, 6.0);
            var _bx = _hit_box.x + _hit_box.box_w * 0.5;
            var _by = _hit_box.y + _hit_box.box_h * 0.5;
            cam_x          = _bx - (_shelf_w + _view_w * 0.5) * _new_zoom;
            cam_y          = _by - (_view_h * 0.5) * _new_zoom;
            cam_zoom_target = _new_zoom;
            cam_zoom        = _new_zoom;
            global.undo_dirty = true;
            alarm[3] = 6;
            box_body_dbl_timer  = 0;
            box_body_dbl_target = noone;
        } else {
            box_body_dbl_timer  = 20;
            box_body_dbl_target = _hit_box;
        }
    } else {
        box_body_dbl_timer  = 0;
        box_body_dbl_target = noone;
    }
}

// Tab indent on selected nodes
if (keyboard_check_pressed(vk_tab) && array_length(global.selected_nodes) > 0 && !is_entering_text && !code_editor_open) {
    var _dir = keyboard_check(vk_shift) ? -40 : 40;
    for (var _si = 0; _si < array_length(global.selected_nodes); _si++) {
        var _sn = global.selected_nodes[_si];
        if (instance_exists(_sn)) {
            _sn.x_indent = max(-100, _sn.x_indent + _dir);
            _sn.stats_cache_dirty = true; // Refresh the bytes/cyc display
        }
    }
    global.addresses_dirty = true; // Trigger the final update block below
}

// =============================================================
// FINAL UPDATE & CLEANUP
// =============================================================

// 1. Handle Release Logic (Snapshots and Autosave)
if (mouse_check_button_released(mb_any)) {
    alarm[1] = 6;
    with (obj_c64_node) { stats_cache_dirty = true; }
    
    // If we were dragging or changing things, finalize the addresses now
    if (global.undo_dirty || global.addresses_dirty) {
        scr_c64_do_update_addresses();
        global.addresses_dirty = false;
        
        // Snapshot the stable state
        scr_undo_snapshot();
        global.undo_dirty = false;
        
// Handle Autosave timer
        if (!_was_panning && !is_panning && global.autosave_mode != 3) {
            var _was_clean = !global.autosave_dirty;
            global.autosave_dirty = true;
            global.manual_saved   = false;
            if (_was_clean && alarm[4] < game_get_speed(gamespeed_fps) * 5) {
                alarm[4] = game_get_speed(gamespeed_fps) * 5;
            }
        }
    }
    _was_panning = false;
}

// 2. Catch-all for non-mouse changes (Keyboard/Dirty Flags)
// NOTICE: mouse_check_button_pressed is REMOVED from here to stop the flash.
if (keyboard_check_pressed(vk_enter) || 
    keyboard_check_pressed(vk_escape) || 
    global.addresses_dirty) {
    
    scr_c64_do_update_addresses();
    global.addresses_dirty = false;
}

// Move the scanline downwards
if (scan_active) {
    // Scale speed by zoom so the visual speed remains consistent
    scan_y += (scan_speed * cam_zoom); 
    
    var _cutoff = cam_y + (1080 * cam_zoom) + (200 * cam_zoom);

    
    // Deactivate once it passes the bottom of the screen + the effect height
    if (scan_y > _cutoff) {
        scan_active = false;
        show_debug_message("=== SCAN FINISHED ===");
    }
}
