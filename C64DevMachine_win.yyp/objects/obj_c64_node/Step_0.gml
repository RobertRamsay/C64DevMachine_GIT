/// @desc Node Step Event - Input, Dragging, Wedge Insertion & ORG Child Dragging

// Skip all per-node logic once asleep (wakes instantly on input via Begin Step)
if (global.idle_active && global.idle_fade < 0.1) exit;

if global.gui_mouse_y<50 exit; // skip menu bars clicks from hitting buttons etc
if !global.canEditNode exit;
if (obj_workspace_manager.gui_menu_open != -1) exit;

// =============================================================
// INIT NODE [CLEAR] BUTTON
// =============================================================
if (node_type == "INIT" && array_length(instructions) > 0) {
    var _btn_w  = 60;
    var _btn_h  = 20;
    var _btn_x1 = x + width - _btn_w - 8;
    var _btn_y1 = y + height - _btn_h - 6;
    var _btn_x2 = _btn_x1 + _btn_w;
    var _btn_y2 = _btn_y1 + _btn_h;

    if (mouse_check_button_pressed(mb_left)
    && point_in_rectangle(mouse_x, mouse_y, _btn_x1, _btn_y1, _btn_x2, _btn_y2)) {
        instructions          = [];
        total_node_size       = 0;
        node_cycles           = 0;
        stats_cache_dirty     = true;
        height_dirty          = true;
        last_overlap_check    = false;
        overlap_check_dirty   = true;
        global.undo_dirty     = true;
        global.addresses_dirty = true;
        scr_c64_do_update_addresses();
    }
}

if obj_workspace_manager.code_editor_open exit;

// Block interaction when asset viewer or info window is open
if obj_workspace_manager.code_editor_open exit;
if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) exit;
if (global.show_info_window) exit;
if (obj_workspace_manager.label_search_open) exit;

/////////////////////////////////////////////////////////////////
// LABEL-REFERENCE HOVER HIGHLIGHT (LABEL nodes only)
// Gated: only LABEL nodes need this, and only when no drag/picker is
// active. Non-LABEL nodes skip the whole block immediately.
/////////////////////////////////////////////////////////////////
if (node_type == "LABEL" && !is_dragging && !global.any_picker_open) {
    var _hov_x = x + x_indent;
    if (point_in_rectangle(mouse_x, mouse_y, _hov_x, y, _hov_x + width, y + height)) {
        hover_timer += 1;
        if (hover_timer >= hover_threshold && global.ref_highlight_source != id) {
            if (array_length(instructions) > 0 && array_length(instructions[0]) > 1) {
                global.ref_highlight_source = id;
                global.ref_highlight_name   = string(instructions[0][1]);
            }
        }
    } else {
        hover_timer = 0;
    }

    // Press Enter while this LABEL is broadcasting -> cycle camera through referencing nodes
    if (global.ref_highlight_source == id && keyboard_check_pressed(vk_enter)
        && !obj_workspace_manager.is_entering_text
		&& !global.mouse_in_asset_panel)
		{

        var _target_name = global.ref_highlight_name;
        var _ref_list    = [];

        // Collect every referencing node
        with (obj_c64_node) {
            if (id == other.id) continue;
            var _refs = false;
            for (var _ri = 0; _ri < array_length(instructions); _ri++) {
                for (var _rj = 0; _rj < array_length(instructions[_ri]); _rj++) {
                    var _slot = instructions[_ri][_rj];
                    if (is_string(_slot) && _slot == _target_name) { _refs = true; break; }
                }
                if (_refs) break;
            }
            if (_refs) array_push(_ref_list, id);
        }

        var _ref_count = array_length(_ref_list);
        if (_ref_count > 0) {
            // Sort topmost-first so cycle order is stable
            array_sort(_ref_list, function(_a, _b) { return _a.y - _b.y; });

            // Clamp/wrap the cycle index (handles refs being deleted mid-session)
            if (ref_jump_index >= _ref_count) ref_jump_index = 0;

            var _target = _ref_list[ref_jump_index];
            if (instance_exists(_target)) {
                scr_focus_camera_on_node(_target);
            }

            // Advance for next press, wrapping back to the top
            ref_jump_index = (ref_jump_index + 1) mod _ref_count;
        }
    }
}

/////////////////////////////////////////////////////////////////
// HEADER TOOLTIP HOVER
// Hovering the right 20% of a node's header bar, with no mouse button
// held, for node_tooltip_delay frames surfaces a floating description
// of that node/macro (drawn by obj_workspace_manager in Draw GUI, since
// that always renders on top of every node's own Draw event).
/////////////////////////////////////////////////////////////////
if (!is_dragging && !global.any_picker_open) {
    var _tt_hdr_x1 = x + x_indent + (width * 0.8);
    var _tt_hdr_x2 = x + x_indent + width;
    var _tt_hov = point_in_rectangle(mouse_x, mouse_y, _tt_hdr_x1, y, _tt_hdr_x2, y + 24)
               && !mouse_check_button(mb_left) && !mouse_check_button(mb_right) && !mouse_check_button(mb_middle);

    if (_tt_hov) {
        tooltip_hover_timer += 1;
        if (tooltip_hover_timer >= obj_workspace_manager.node_tooltip_delay) {
            obj_workspace_manager.node_tooltip_node = id;
        }
    } else {
        tooltip_hover_timer = 0;
        if (obj_workspace_manager.node_tooltip_node == id) {
            obj_workspace_manager.node_tooltip_node = noone;
        }
    }
}

// Check if this node is a group drag follower (used to skip conflicting logic below)
var _is_group_follower = false;
if (global.group_drag_active && id != global.group_drag_handle) {
    for (var _gfi = 1; _gfi < array_length(global.group_drag_nodes); _gfi++) {
        if (global.group_drag_nodes[_gfi].node == id) { _is_group_follower = true; break; }
    }
}

/////////////////////////////////////////////////////////////////
// DRAG-OVER-SHELF DESTROY
/////////////////////////////////////////////////////////////////
if (!obj_workspace_manager.expert_mode && is_dragging && mouse_check_button_released(mb_left)) {
    var _cam_x     = obj_workspace_manager.cam_x;
    var _cam_zoom  = obj_workspace_manager.cam_zoom;
    var _screen_x  = (x - _cam_x) / _cam_zoom;
    var _node_mid_x = _screen_x + (width / _cam_zoom / 2);
  
    if (_node_mid_x < obj_workspace_manager.shelf_width + (width / _cam_zoom / 2)) {
        if (node_type == "INIT") {  exit; }
        if (node_type == "ORG" && node_title == "VARIABLES") { exit; }
       
		global.undo_dirty = true;
        instance_destroy();
        exit;
    }
}

/////////////////////////////////////////////////////////////////
// RMB DESTROY right click delete right mouse button
/////////////////////////////////////////////////////////////////
if (mouse_check_button_pressed(mb_right)) {

    // Wire dot right-click — check BEFORE the rectangle guard since dots sit on edges
    if (node_type == "ORG" ) {
		

		
        var _dot_r     = 9;
        var _dot_in_x  = x + x_indent;
        var _dot_out_x = x + x_indent + width;
        var _dot_y     = y + 10;
        var _hit_in    = point_in_circle(mouse_x, mouse_y, _dot_in_x,  _dot_y, _dot_r);
        var _hit_out   = point_in_circle(mouse_x, mouse_y, _dot_out_x, _dot_y, _dot_r);

        if (_hit_in && wire_in_source != -1) {
            var _dead_src = wire_in_source;
            with (obj_c64_node) {
                if (node_type == "ORG" && org_uid == _dead_src) {
                    wire_out_target = -1;
                    break;
                }
            }
            wire_in_source         = -1;
            global.addresses_dirty = true;
            global.undo_dirty      = true;
            scr_c64_update_addresses();
            exit;
        }

        if (_hit_out && wire_out_target != -1) {
            var _dead_dst = wire_out_target;
            with (obj_c64_node) {
                if (node_type == "ORG" && org_uid == _dead_dst) {
                    wire_in_source = -1;
                    break;
                }
            }
            wire_out_target        = -1;
            global.addresses_dirty = true;
            global.undo_dirty      = true;
            scr_c64_update_addresses();
            exit;
        }
    }

    if (point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + height)) {
        if (node_type == "INIT") exit;
        
        // Double-click within 1 second required to delete
        var _now = current_time;
        if (rmb_first_click_time < 0 || (_now - rmb_first_click_time) > 250) {
           
            rmb_first_click_time = _now;
            rmb_flash = 30;
            exit;
        }
        rmb_first_click_time = -1;
       
        // --- proceed to deletion below ---
        if (node_type == "INIT") exit;
        
       // 1. VARIABLES ORG is indestructible if it has children
        if (node_type == "ORG" && node_title == "VARIABLES") {
            var _has_children = false;
            var _org_ref = id;
            with (obj_c64_node) {
                if (org_parent == _org_ref) { 
                    _has_children = true; 
                    break; 
                }
            }
            
            if (_has_children) {
                scr_show_message("BLOCK is NOT EMPTY.. May contain Comments or VARS");
                exit; // Stop destruction because it has children
            }
			else
			{
			instance_destroy();
            scr_c64_update_addresses();
			exit;
			}
			
           
        }

        // 2. Specialized check for NAMED_LOC and NEW_STR (Variables inside the box)
        if ((node_type == "NAMED_LOC" || node_type == "NEW_STR") && org_parent != noone) {

            // ------------------------------------------------------------
            // VARIABLE DELETE REFERENCE GUARD
            // Block deletion while any known VAR-consuming node still names
            // this variable. Reference slots per type mirror the VAR pickers
            // and the compile chain (COND_IF cmp-var = slot 5; METAMAP name
            // relocates 6->7; SEEK/COLL_ADV multi-slot, etc). Rendered by the
            // left-side list in obj_workspace_manager Draw GUI.
            // ------------------------------------------------------------
            var _del_var_name = string(instructions[0][1]);
            var _refs         = scr_find_var_references(_del_var_name, id);

            if (array_length(_refs) > 0) {
                // Referenced — abort deletion and raise the warning list
                global.var_del_warn_active  = true;
                global.var_del_warn_clicked = false;
                global.var_del_warn_fade    = 1.0;
                global.var_del_warn_scroll  = 0;
                global.var_del_warn_name    = _del_var_name;
                global.var_del_warn_refs    = _refs;
                global.var_del_warn_batch   = 0;
                rmb_first_click_time        = -1;
                exit;
            }

            global.addresses_dirty = true;
            global.undo_dirty = true;
            with (obj_c64_node) { last_overlap_check = false; overlap_check_dirty = true; }
            instance_destroy();
            scr_c64_update_addresses();
            exit;
        }



        // 3. General spine connection / parent safety
        if (org_parent != noone && node_type != "COMMENT") {
            var _parent_title = instance_exists(org_parent) ? org_parent.node_title : "DEAD_INSTANCE";
            
            if (!instance_exists(org_parent) || org_parent.node_title == "VARIABLES") {
                
                exit;
            }
            
			global.addresses_dirty = true;
            global.undo_dirty = true;
            with (obj_c64_node) { last_overlap_check = false; overlap_check_dirty = true; }
            instance_destroy();
            scr_c64_update_addresses();
            exit;
        }



        // 4. Resource cleanup
        if (node_type == "BITMAP_KLA") {
          
            if (kla_buffer != -1 && buffer_exists(kla_buffer)) buffer_delete(kla_buffer);
            if (surface_exists(preview_surf)) surface_free(preview_surf);
        }

		// 5. Wire cleanup before destruction
        if (node_type == "ORG") {
            var _dead_uid = org_uid;
            with (obj_c64_node) {
                if (node_type != "ORG") continue;
                if (wire_in_source == _dead_uid) {
                    wire_in_source = -1;
                    proxy          = false;
                }
                if (wire_out_target == _dead_uid) {
                    wire_out_target = -1;
                }
            }
        }

        // 5. Final Destruction
        global.undo_dirty = true;
        with (obj_c64_node) { last_overlap_check = false; overlap_check_dirty = true; }
        instance_destroy();
        scr_c64_update_addresses();
    }
}

/////////////////////////////////////////////////////////////////
// RMB FLASH DECAY
/////////////////////////////////////////////////////////////////
if (rmb_flash > 0) rmb_flash--;

// Conflict alpha smooth
//if (!variable_instance_exists(id, "conflict_alpha")) conflict_alpha = 0;
//var _conflict_target = (variable_instance_exists(id, "is_conflicted") && is_conflicted) ? 1.0 : 0.0;
//conflict_alpha = lerp(conflict_alpha, _conflict_target, 0.06);

/////////////////////////////////////////////////////////////////
// CAMERA / SHELF HELPERS
/////////////////////////////////////////////////////////////////
// is_data_node and is_free_node cached at creation

var _cam_x    = obj_workspace_manager.cam_x;
var _cam_zoom = obj_workspace_manager.cam_zoom;
var _spine_x  = floor(((room_width / 2) - (global.node_display_width / 2)) / 20) * 20;
var draw_x    = x + x_indent;
var _latch_h  = 120;
var _sticky_h = 300;

var _gui_mouse_x     = global.gui_mouse_x;
var _gui_mouse_y     = global.gui_mouse_y;
var _gui_w           = global.gui_w;
var _shelf_w         = obj_workspace_manager.shelf_width;
var _mouse_in_shelf     = (_gui_mouse_x <= _shelf_w)
                       && (!obj_workspace_manager.expert_mode || _gui_mouse_y < 47);
var _mouse_in_shortcuts = (_gui_mouse_x >= global.sc_x_start && _gui_mouse_x <= _gui_w);

var _mouse_in_gui = _mouse_in_shelf
                 || _mouse_in_shortcuts
                 || obj_workspace_manager.is_entering_text
                 || obj_workspace_manager.box_popup_open
                 || global.show_info_window
                 || global.show_helper_window
                 || instance_exists(global.breakdown_node);

/////////////////////////////////////////////////////////////////
// A. LABEL PICKER — handle clicks before main LMB block
/////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////
// A0. LABEL PICKER — filter list by first-letter keypress
/////////////////////////////////////////////////////////////////
if (label_picker_open) {
    if (!label_picker_was_open) {
        // Picker just opened this frame — discard any stale keyboard_string
        // left over from the click/keypress that opened it, and start with
        // a clean filter so the previous letter never carries over.
        label_picker_filter_char = "";
        keyboard_string          = "";
        label_picker_was_open    = true;
    } else if (keyboard_check_pressed(vk_space) || keyboard_check_pressed(vk_backspace) || keyboard_check_pressed(vk_delete)) {
        label_picker_filter_char = "";
        label_picker_scroll      = 0;
        keyboard_string          = "";
    } else if (keyboard_string != "") {
        var _fchar = string_upper(string_char_at(keyboard_string, 1));
        if (string_pos(_fchar, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") > 0) {
            label_picker_filter_char = _fchar;
            label_picker_scroll      = 0;
        }
        keyboard_string = "";
    }
} else {
    label_picker_was_open = false;
}

if (label_picker_open && mouse_check_button_pressed(mb_left)) {
   // ---- ASSET PICKER (BYTE_DATA / TEXT_DATA / LINE_COLL) ----
    if (label_picker_mode == "BYTE_ASSET" || label_picker_mode == "TEXT_ASSET"
	 || label_picker_mode == "SOUND_ASSET" || label_picker_mode == "LINE_ASSET") {
        var _want_type = "BYTE_DATA";
        if (label_picker_mode == "TEXT_ASSET") {
            _want_type = "TEXT_DATA";
        } else if (label_picker_mode == "SOUND_ASSET") {
            _want_type = "MUSIC_MAKER";
        } else if (label_picker_mode == "LINE_ASSET") {
            _want_type = "LINE_COLL";
        }
        var _px      = draw_x + width + 8;
        var _py      = y + 36;
        var _pw      = 160;
        var _row_h   = 16;
        var _visible = 24;
        var _list_y  = _py + 18;
        var _arrow_y = _list_y + (_visible * _row_h) + 2;
        var _total_h = _arrow_y + 20 - _py;

        // Build BYTE_DATA list
        var _alist = ["[clear]"];
        if (instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = _am.asset_list[| _ai];
                if (_a.type == _want_type) array_push(_alist, _a.name);
            }
        }
        var _count = array_length(_alist);

        // X close
        if (point_in_rectangle(mouse_x, mouse_y, _px, _py - 16, _px + _pw, _py)) {
            label_picker_open = false; global.any_picker_open = false;
            depth = label_picker_prev_depth;
            global.was_editor_open = true; obj_asset_manager.alarm[2] = 60;
            exit;
        }
        // Scroll up
        if (point_in_rectangle(mouse_x, mouse_y, _px + 4, _arrow_y, _px + 20, _arrow_y + 16)) {
            label_picker_scroll = max(0, label_picker_scroll - 1); exit;
        }
        // Scroll down
        if (point_in_rectangle(mouse_x, mouse_y, _px + _pw - 20, _arrow_y, _px + _pw - 4, _arrow_y + 16)) {
            label_picker_scroll = min(max(0, _count - _visible), label_picker_scroll + 1); exit;
        }
        // Row commit
        for (var _li = 0; _li < _visible; _li++) {
            var _idx = _li + label_picker_scroll;
            if (_idx >= _count) break;
            var _ry = _list_y + (_li * _row_h);
            if (point_in_rectangle(mouse_x, mouse_y, _px, _ry, _px + _pw, _ry + _row_h)) {
                if (instance_exists(label_picker_target)) {
                    var _picked = _alist[_idx];
                    if (_picked == "[clear]") _picked = "";
                    var _ba_idx = label_picker_target.label_picker_index;
                    if (_ba_idx <= 0) _ba_idx = 3; // GET_VAR default
                    label_picker_target.instructions[0][_ba_idx] = _picked;
                    global.addresses_dirty = true;
					global.undo_dirty      = true;
                    scr_c64_do_update_addresses();
                }
                label_picker_open = false; depth = label_picker_prev_depth;
                global.any_picker_open = false; global.ui_click_block_timer = 6;
                exit;
            }
        }
        // Click outside — close
        if (!point_in_rectangle(mouse_x, mouse_y, _px, _py, _px + _pw, _py + _total_h)) {
            label_picker_open = false; depth = label_picker_prev_depth;
            global.any_picker_open = false;
            global.was_editor_open = true; obj_asset_manager.alarm[2] = 60;
            exit;
        }
        exit;
    }

    // VAR picker uses Draw block F for commits — only handle JUMP picker here
    if (label_picker_mode == "VAR" || label_picker_mode == "VAR_SRC") {
        // label_picker_tab initialised in Create

        var _px      = draw_x + width + 8;
        var _py      = y + 36;
        var _pw      = 160;
        var _row_h   = 16;
        var _visible = 24;
        var _tab_h   = 20;
        var _list_y  = _py + _tab_h + 18;
        var _arrow_y = _list_y + (_visible * _row_h) + 2;
        var _total_h = _arrow_y + 20 - _py;

// Count for scroll clamping
        var _count = 0;
        if (label_picker_tab == "HW") {
            if (global.hw_picker_active_category == -1) {
                _count = array_length(global.hw_picker_categories);
            } else {
                _count = array_length(global.hw_picker_categories[global.hw_picker_active_category].items);
            }
        } else {
            for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                if (global.named_loc_meta[_ki].type != "UV") continue;
                if (label_picker_filter_char != "") {
                    var _fc_cnt_name = global.named_loc_meta[_ki].name;
                    if (string_pos("UV_", _fc_cnt_name) == 1) _fc_cnt_name = string_delete(_fc_cnt_name, 1, 3);
                    if (string_upper(string_char_at(_fc_cnt_name, 1)) != label_picker_filter_char) continue;
                }
                _count++;
            }
        }

        // Tab clicks
        var _tab_w = _pw / 2;
        for (var _ti = 0; _ti < 2; _ti++) {
            var _tx = _px + (_ti * _tab_w);
            var _tl = (_ti == 0) ? "UV" : "HW";
            if (point_in_rectangle(mouse_x, mouse_y, _tx, _py, _tx + _tab_w, _py + _tab_h)) {
               
               label_picker_tab    = _tl;
                label_picker_scroll = 0;
                global.hw_picker_active_category = -1; // Reset category state
                exit;
            }
        }

    
		// Back Button (HW Tab)
        if (label_picker_tab == "HW" && global.hw_picker_active_category != -1) {
            if (point_in_rectangle(mouse_x, mouse_y, _px, _py + _tab_h, _px + _pw, _py + _tab_h + 16)) {
                global.hw_picker_active_category = -1;
                label_picker_scroll = 0;
                exit;
            }
        }

        // X close (Full width header)
        if (point_in_rectangle(mouse_x, mouse_y, _px, _py - 16, _px + _pw, _py)) {
            label_picker_open      = false;
            global.any_picker_open = false;
            depth                  = label_picker_prev_depth;
            label_picker_word_only = false;
            label_picker_byte_only = false;
            label_picker_filter_char = "";
            global.was_editor_open = true;
            obj_asset_manager.alarm[2]  = 60;
            exit;
        }

        // Scroll up
        if (point_in_rectangle(mouse_x, mouse_y, _px + 4, _arrow_y, _px + 20, _arrow_y + 16)) {
          
            label_picker_scroll = max(0, label_picker_scroll - 1);
            exit;
        }

        // Scroll down
        if (point_in_rectangle(mouse_x, mouse_y, _px + _pw - 20, _arrow_y, _px + _pw - 4, _arrow_y + 16)) {
            var _scroll_max_src = (label_picker_group == "KERNAL") ? array_length(scr_kernal_routine_list()) : array_length(label_picker_list);
            label_picker_scroll = min(max(0, _scroll_max_src - _visible), label_picker_scroll + 1);
            exit;
        }
        // Row 1: group tab clicks (swallow so they never hit a row)
        if (point_in_rectangle(mouse_x, mouse_y, _px, _py + 2, _px + 68, _py + 19)) {
            label_picker_group  = "LABELS";
            label_picker_scroll = 0;
            exit;
        }
        if (label_picker_is_jsr && point_in_rectangle(mouse_x, mouse_y, _px + 74, _py + 2, _px + 141, _py + 19)) {
            label_picker_group  = "KERNAL";
            label_picker_scroll = 0;
            exit;
        }
        // Row 2: INC CODE toggle (LABELS group only)
        if (label_picker_group == "LABELS" && point_in_rectangle(mouse_x, mouse_y, _px + 4, _py + 18, _px + 86, _py + 18 + _row_h)) {
            label_picker_inc_code = !label_picker_inc_code;
            exit;
        }
        // Build active row source to match Draw
        var _active_list = [];
        var _hw_showing_categories = false;
        if (label_picker_tab == "HW") {
            if (global.hw_picker_active_category == -1) {
                _hw_showing_categories = true;
                for (var _c = 0; _c < array_length(global.hw_picker_categories); _c++) {
                    var _cat_name = global.hw_picker_categories[_c].name;
                    if (label_picker_filter_char != "" &&
                        string_upper(string_char_at(_cat_name, 1)) != label_picker_filter_char) continue;
                    array_push(_active_list, _cat_name);
                }
            } else {
                var _hw_items = global.hw_picker_categories[global.hw_picker_active_category].items;
                for (var _hi = 0; _hi < array_length(_hw_items); _hi++) {
                    if (label_picker_filter_char != "" &&
                        string_upper(string_char_at(_hw_items[_hi], 1)) != label_picker_filter_char) continue;
                    array_push(_active_list, _hw_items[_hi]);
                }
            }
        } else {
            for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                var _entry = global.named_loc_meta[_ki];
                if (_entry.type != "UV") continue;
                if (label_picker_word_only) {
                    var _wenc = variable_struct_exists(_entry, "encoding") ? _entry.encoding : "byte";
                    if (_wenc != "word") continue;
                }
                if (label_picker_byte_only) {
                    var _bsz = variable_struct_exists(_entry, "size") ? _entry.size : 1;
                    if (_bsz != 1) continue;
                }
                if (label_picker_filter_char != "") {
                    var _fc_name = _entry.name;
                    if (string_pos("UV_", _fc_name) == 1) _fc_name = string_delete(_fc_name, 1, 3);
                    if (string_upper(string_char_at(_fc_name, 1)) != label_picker_filter_char) continue;
                }
                array_push(_active_list, _entry.name);
            }
            array_sort(_active_list, true);
            array_insert(_active_list, 0, "[clear]");
        }
        for (var _li = 0; _li < _visible; _li++) {
            var _idx = _li + label_picker_scroll;
            if (_idx >= array_length(_active_list)) break;
            var _ry = _list_y + (_li * _row_h);
	if (point_in_rectangle(mouse_x, mouse_y, _px, _ry, _px + _pw, _ry + _row_h)) {
                
                // Dive into category instead of closing
                if (_hw_showing_categories) {
                    global.hw_picker_active_category = _idx;
                    label_picker_scroll = 0;
                    exit;
                }

                // If not showing categories, commit the selection normally
                if (instance_exists(label_picker_target)) {
                    var _target_idx = label_picker_target.label_picker_index;
                    var _picked_name = _active_list[_idx];
                    if (_picked_name == "[clear]") {
                        _picked_name = "";
                    }
                    // Canonicalize UV var names to uppercase so they match named_loc_map/
                    // named_loc_meta keys regardless of the case the var was declared in.
                    // HW_ picker entries (label_picker_tab == "HW") are pre-defined constants
                    // and already correctly cased — leave those untouched.
                    if (_picked_name != "" && label_picker_target.label_picker_tab != "HW") {
                        _picked_name = string_upper(_picked_name);
                    }
                    if (label_picker_target.label_picker_mode == "VAR_SRC") {
                        // SET_VAR source byte — write to slot 6, keep src_mode = VAR
                        while (array_length(label_picker_target.instructions[0]) < 7) array_push(label_picker_target.instructions[0], "");
                        label_picker_target.instructions[0][6] = _picked_name;
                    } else if (_target_idx == 0) {
                        // Standard VAR nodes — always write to instructions[0][1]
                        label_picker_target.instructions[0][1] = _picked_name;
                    } else {
                        // Custom index (e.g. MACRO_IRQ raster var at index 7, MACRO_MOVE DX/DY at 8/10)
                        label_picker_target.instructions[0][_target_idx] = _picked_name;
                    }
                    global.addresses_dirty = true;
					global.undo_dirty      = true;
                    scr_c64_do_update_addresses();
                    label_picker_target.label_picker_word_only = false;
                    label_picker_target.label_picker_byte_only = false;
                }
                label_picker_open           = false;
                depth                       = label_picker_prev_depth;
                global.any_picker_open      = false;
                global.ui_click_block_timer = 6;
                label_picker_filter_char    = "";
                exit;
            }
        }
        // Click outside — close
        if (!point_in_rectangle(mouse_x, mouse_y, _px, _py, _px + _pw, _py + _total_h)) {
           
            label_picker_open      = false;
            depth                  = label_picker_prev_depth;
            global.any_picker_open = false;
            label_picker_filter_char = "";
            global.was_editor_open = true;
            obj_asset_manager.alarm[2]  = 60;
            exit;
        }
        exit;

    } else {
        // JUMP picker
        var _px      = draw_x + width + 8;
        var _py      = y + 36;
        var _pw      = 140;
        var _row_h   = 16;
        var _visible = 24;
        var _arrow_y = _py + 18 + _row_h + (_visible * _row_h) + 2;


		// X close (Full width header)
        if (point_in_rectangle(mouse_x, mouse_y, _px, _py - 16, _px + _pw, _py)) {
            label_picker_open      = false;
            global.any_picker_open = false;
            depth                  = label_picker_prev_depth;
            label_picker_filter_char = "";
            global.was_editor_open = true;
            obj_asset_manager.alarm[2]  = 60;
            exit;
        }
        // Scroll up
        if (point_in_rectangle(mouse_x, mouse_y, _px + 4, _arrow_y, _px + 20, _arrow_y + 16)) {
           
            label_picker_scroll = max(0, label_picker_scroll - 1);
            exit;
        }
        // Build active row source to match Draw (filtered by first-letter keypress)
        var _rows_src = [];
        if (label_picker_group == "KERNAL") {
            var _krn = scr_kernal_routine_list();
            for (var _ki = 0; _ki < array_length(_krn); _ki++) {
                if (label_picker_filter_char != "" && _krn[_ki].name != "[clear]" &&
                    string_upper(string_char_at(_krn[_ki].name, 1)) != label_picker_filter_char) continue;
                array_push(_rows_src, _krn[_ki].name);
            }
        } else {
            for (var _li2 = 0; _li2 < array_length(label_picker_list); _li2++) {
                var _lp_name = label_picker_list[_li2];
                if (label_picker_filter_char != "" && _lp_name != "[clear]") {
                    var _fc_name2 = _lp_name;
                    if (string_pos("UV_", _fc_name2) == 1) _fc_name2 = string_delete(_fc_name2, 1, 3);
                    if (string_upper(string_char_at(_fc_name2, 1)) != label_picker_filter_char) continue;
                }
                array_push(_rows_src, _lp_name);
            }
        }

        // Scroll down
        if (point_in_rectangle(mouse_x, mouse_y, _px + _pw - 20, _arrow_y, _px + _pw - 4, _arrow_y + 16)) {
           
            label_picker_scroll = min(max(0, array_length(_rows_src) - _visible), label_picker_scroll + 1);
            exit;
        }
        // Row commit
        var _list_y = _py + 18 + _row_h;
        for (var _li = 0; _li < _visible; _li++) {
            var _idx = _li + label_picker_scroll;
            if (_idx >= array_length(_rows_src)) break;
            var _ry = _list_y + (_li * _row_h);
            if (point_in_rectangle(mouse_x, mouse_y, _px, _ry, _px + _pw, _ry + _row_h)) {
                var _picked = _rows_src[_idx];
			   if (_picked == "[clear]") { _picked = ""; }
               
				if (node_type == "COND_IF" ||
                    node_type == "COND_IF_WORD" ||
                    node_type == "MACRO_IRQ" ||
                    node_type == "MACRO_COLLISION" ||
					node_type == "MACRO_COLL_ADV") {
                    instructions[0][label_picker_index] = _picked;
                } else {
                    instructions[label_picker_index][1] = _picked;
                }
                label_picker_open           = false;
                depth                       = label_picker_prev_depth;
                global.any_picker_open      = false;
                global.ui_click_block_timer = 6;
                global.addresses_dirty      = true;
				global.undo_dirty           = true;
                global.was_editor_open      = true;
                obj_asset_manager.alarm[2]  = 60;
                label_picker_filter_char    = "";
                if (node_type == "COND_IF" || node_type == "COND_IF_WORD") scr_c64_do_update_addresses();
                exit;
            }
        }

        // Click outside — close
        var _jump_total_h = (_arrow_y + 16) - (_py - 16);
        if (!point_in_rectangle(mouse_x, mouse_y, _px, _py - 16, _px + _pw, _py - 16 + _jump_total_h)) {
            label_picker_open      = false;
            depth                  = label_picker_prev_depth;
            global.any_picker_open = false;
            label_picker_filter_char = "";
            global.was_editor_open = true;
            obj_asset_manager.alarm[2]  = 60;
            exit;
        }
    }
}

/////////////////////////////////////////////////////////////////
// B0. ALT+CLICK — rename header (custom_title override)
/////////////////////////////////////////////////////////////////
var _alt_click = (mouse_check_button_pressed(mb_left) && keyboard_check(vk_alt));

var _dbl_click = false;
if (mouse_check_button_pressed(mb_left)) {
    if (dbl_click_timer > 0) {
        _dbl_click = true;
        dbl_click_timer = 0;
    }
    else {
        dbl_click_timer = dbl_click_threshold;
    }
}

if (dbl_click_timer > 0) {
    dbl_click_timer -= 1;
}

if ((_alt_click || _dbl_click) && !is_dragging && !_mouse_in_gui) {

    // VAR RENAME — NAMED_LOC / NEW_STR body double-click edits the real
    // variable name (instructions[0][1]), not the display-only custom_title.
    // Checked against the body (below the header) rather than the header
    // bar, since the header is reserved for dragging. Routed to idx -78 so
    // scr_node_commit can run the duplicate-name guard and rewrite every
    // referencing node.
    if ((node_type == "NAMED_LOC" || node_type == "NEW_STR") &&
        point_in_rectangle(mouse_x, mouse_y, draw_x, y + 24, draw_x + width, y + height)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = -78;
            current_input_string = string(other.instructions[0][1]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    if (point_in_rectangle(mouse_x, mouse_y, draw_x, y, draw_x + width, y + 24)) {
        var _is_opcode_node = (
            node_type != "ORG"        && node_type != "LABEL"     && node_type != "EXECUTE"  &&
            node_type != "INIT"       && node_type != "COMMENT"   && node_type != "RAW_DATA" &&
            node_type != "DATA_TEXT"  && node_type != "DATA_SID"  && node_type != "SPR64"    &&
            node_type != "BITMAP_KLA" && node_type != "NAMED_LOC" && node_type != "NEW_STR"  &&
            node_type != "GET_VAR"    && node_type != "SET_VAR"   && node_type != "INC_VAR"  &&
            node_type != "DEC_VAR"    && node_type != "COPY_VAR"  &&
            node_type != "BANK_SWITCH" &&
            string_pos("MACRO", node_type) == 0 && string_pos("COND_", node_type) == 0
        );
        if (_is_opcode_node) {
            exit;
        }

        var _title_src = node_title;
        if (custom_title != "") {
            _title_src = custom_title;
        }
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = -77;
            current_input_string = string(_title_src);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
}

/////////////////////////////////////////////////////////////////
// B. CTRL+CLICK — copy node and drag
/////////////////////////////////////////////////////////////////
if (mouse_check_button_pressed(mb_left) && (keyboard_check(vk_control) || scr_cmd_held()) && !is_dragging && !_mouse_in_gui && node_type != "NAMED_LOC") {
    if (point_in_rectangle(mouse_x, mouse_y, draw_x, y, draw_x + width, y + height)) {

        // ---- GROUP CLONE DRAG ----
        if (id == global.group_drag_handle && array_length(global.selected_nodes) > 1) {
            // Filter selection to same spine as handle
            var _handle_spine = org_parent;
            var _filtered = [];
            for (var _fi = 0; _fi < array_length(global.selected_nodes); _fi++) {
                var _fn = global.selected_nodes[_fi];
                if (!instance_exists(_fn)) continue;
                if (_fn.node_type == "INIT" || _fn.node_type == "ORG") continue;
                var _fn_free = (string_pos("DATA", _fn.node_type) > 0 ||
                                _fn.node_type == "RAW_DATA" || _fn.node_type == "SPR64" ||
                                _fn.node_type == "BITMAP_KLA");
                if (_fn_free) continue;
                if (_fn.org_parent == _handle_spine) array_push(_filtered, _fn);
            }
            // Deselect nodes not in filtered list
            global.selected_nodes = _filtered;
            // Recompute handle (topmost)
            array_sort(_filtered, function(_a, _b) { return _a.y - _b.y; });
            global.group_drag_handle = (array_length(_filtered) > 0) ? _filtered[0] : noone;

            if (global.group_drag_handle == id && array_length(_filtered) > 1) {
                // Clone each node
                global.group_drag_nodes   = [];
                global.group_drag_active  = true;
                global.group_drag_is_clone = true;

                for (var _ci = 0; _ci < array_length(_filtered); _ci++) {
                    var _src = _filtered[_ci];
                    var _clone = scr_node_spawn(_src.node_type, _src.x, _src.y);
                    _clone.instructions  = array_copy_deep(_src.instructions);
                    _clone.node_title    = _src.node_title;
					_clone.is_connected  = false;
                    _clone.org_parent    = noone;
                    _clone.pc_address    = global.start_pc;
                    _clone.depth         = -2000;
                    _clone.x_indent      = _src.x_indent;
                    if (variable_instance_exists(_src, "code_descriptor")) _clone.code_descriptor = _src.code_descriptor;

                    // Unique-name pass for LABEL clones
                    if (_src.node_type == "LABEL") {
                        if (array_length(_clone.instructions) > 0 && array_length(_clone.instructions[0]) > 1) {
                            var _base_nm_g = string(_clone.instructions[0][1]);
                            if (_base_nm_g != "") {
                                _clone.instructions[0][1] = scr_make_unique_node_name(_base_nm_g, _clone);
                            }
                        }
                    }

                    var _entry = { node: _clone, dx: _src.x - x, dy: _src.y - y };
                    array_push(global.group_drag_nodes, _entry);
                }

                // The handle clone leads the drag
                var _lead = global.group_drag_nodes[0].node;
                _lead.is_dragging   = true;
                _lead.was_dragged   = false;
                _lead.drag_offset_x = x - mouse_x;
                _lead.drag_offset_y = y - mouse_y;
                global.group_drag_handle = _lead;
                global.selected_nodes    = [];
                exit;
            }
        }

// ---- ORG CLONE DRAG (with children) ----
        if (node_type == "ORG") {
            var _org_copy           = scr_node_spawn("ORG", x, y);
            _org_copy.node_title    = node_title;
            _org_copy.instructions  = array_copy_deep(instructions);
            _org_copy.is_dragging   = true;
            _org_copy.was_dragged   = false;
            _org_copy.depth         = -2000;
            _org_copy.drag_offset_x = x - mouse_x;
            _org_copy.drag_offset_y = y - mouse_y;
            _org_copy.is_connected  = false;
            _org_copy.pc_address    = global.start_pc;
            if (node_title == "VARIABLES") {
                _org_copy.proxy      = false;
                _org_copy.pc_address = 0xC000;
            }
            // Clone all children of this ORG
            var _count = instance_number(obj_c64_node);
            for (var _ci = 0; _ci < _count; _ci++) {
                var _child = instance_find(obj_c64_node, _ci);
                if (!instance_exists(_child)) continue;
                if (_child.org_parent != id) continue;
                // Skip free-floating asset nodes
                var _is_free = (string_pos("DATA", _child.node_type) > 0 ||
                                _child.node_type == "RAW_DATA" ||
                                _child.node_type == "SPR64"     ||
                                _child.node_type == "BITMAP_KLA");
                if (_is_free) continue;
                var _cc          = scr_node_spawn(_child.node_type, _child.x, _child.y);
                _cc.instructions = array_copy_deep(_child.instructions);
                _cc.node_title   = _child.node_title;
                _cc.is_connected = true;
                _cc.org_parent   = _org_copy;
                _cc.pc_address   = global.start_pc;
                _cc.depth        = -2000;
                _cc.x_indent     = _child.x_indent;
                if (variable_instance_exists(_child, "code_descriptor")) {
                    _cc.code_descriptor = _child.code_descriptor;
                }

                // Unique-name pass for LABEL children
                if (_child.node_type == "LABEL") {
                    if (array_length(_cc.instructions) > 0 && array_length(_cc.instructions[0]) > 1) {
                        var _base_nm_c = string(_cc.instructions[0][1]);
                        if (_base_nm_c != "") {
                            _cc.instructions[0][1] = scr_make_unique_node_name(_base_nm_c, _cc);
                        }
                    }
                }
            }
            exit;
        }
        // ---- SINGLE NODE CLONE (original behaviour) ----
        var _copy           = scr_node_spawn(node_type, mouse_x, mouse_y);
        _copy.instructions  = array_copy_deep(instructions);
        _copy.node_title    = node_title;
        _copy.is_dragging   = true;
        _copy.was_dragged   = false;
        _copy.depth         = -2000;
        _copy.drag_offset_x = x - mouse_x;
        _copy.drag_offset_y = y - mouse_y;
        _copy.is_connected  = false;
        _copy.pc_address    = global.start_pc;
        if (variable_instance_exists(id, "code_descriptor")) _copy.code_descriptor = code_descriptor;
        if (node_type == "ORG" && node_title == "VARIABLES") {
            _copy.proxy      = false;
            _copy.pc_address = 0xC000;
        }

        // Unique-name pass for LABEL clones
        if (node_type == "LABEL") {
            if (array_length(_copy.instructions) > 0 && array_length(_copy.instructions[0]) > 1) {
                var _base_nm = string(_copy.instructions[0][1]);
                if (_base_nm != "") {
                    _copy.instructions[0][1] = scr_make_unique_node_name(_base_nm, _copy);
                }
            }
        }

        exit;
    }
}

/////////////////////////////////////////////////////////////////
// C. LMB CLICK — dispatched to per-type scripts
/////////////////////////////////////////////////////////////////
if (mouse_check_button_pressed(mb_left) && !is_dragging && !_mouse_in_gui && !global.any_picker_open && !label_picker_open && !instance_exists(obj_ui_color_picker) && _cam_zoom < 3.55 && !global.was_editor_open) {
   

    switch (node_type) {
        case "MACRO_TRACK":  scr_node_step_macro_track(draw_x);  break;
        case "MACRO_VWAIT":  scr_node_step_macro_vwait(draw_x);  break;
        case "MACRO_DISPLAY": scr_node_step_macro_display(draw_x); break;
        case "MACRO_WAIT":    scr_node_step_macro_wait(draw_x);    break;
        case "MACRO_JOY":    scr_node_step_macro_joy(draw_x);    break;
        case "MACRO_PRINT":  scr_node_step_macro_print(draw_x);  break;
		case "MACRO_CLEAR_BMP_RECT": scr_node_step_macro_clear_bmp_rect(draw_x); break;
        case "MACRO_PRINT_EXT": scr_node_step_macro_print_ext(draw_x); break;
        case "MACRO_PLACE_CHAR": scr_node_step_macro_place_char(draw_x); break;
        case "MACRO_CLR_SCREEN": scr_node_step_macro_clr_screen(draw_x); break;
        case "MACRO_MATH":       scr_node_step_macro_math(draw_x); break;
        case "MACRO_RANDOM":     scr_node_step_macro_random(draw_x);     break;
		case "MACRO_SID_SOUND":  scr_node_step_macro_sid_sound(draw_x);  break;
		case "MACRO_SID_SONG":   scr_node_step_macro_sid_song(draw_x);   break;
		case "MACRO_GET_CHAR":   scr_node_step_macro_get_char(draw_x);   break;
		case "MACRO_MOVE_MEM": scr_node_step_macro_move_mem(draw_x); break;
		case "MACRO_MOVE_BMP_BLOCK": scr_node_step_macro_move_bmp_block(draw_x); break;
        case "MACRO_BMP":    scr_node_step_macro_bmp(draw_x);    break;
        case "MACRO_VECTOR_BMP": scr_node_step_macro_vector_bmp(draw_x); break;
		case "MACRO_VECTOR_PAGE": scr_node_step_macro_vector_page(draw_x); break;
        case "MACRO_VIC":    scr_node_step_macro_vic(draw_x);    break;
        case "MACRO_SPR":    scr_node_step_macro_spr(draw_x);    break;
        case "MACRO_SID":    scr_node_step_macro_sid(draw_x);    break;
        case "MACRO_LOADER": scr_node_step_macro_loader(draw_x); break;
        case "MACRO_SAVE_GAME": scr_node_step_macro_save_game(draw_x); break;
        case "MACRO_LOAD_GAME": scr_node_step_macro_load_game(draw_x); break;
        case "MACRO_CHR":    scr_macro_chr_step(id);             break;
        case "MACRO_MAP":        scr_node_step_macro_map(id);        break;
		case "MACRO_METAMAP":    scr_node_step_macro_metamap(draw_x);    break;
		case "MACRO_MAP_SWITCH": scr_node_step_macro_map_switch(id); break;
        case "NEW_STR":      scr_node_step_new_str();            break;
       
        case "MACRO_MOVE":        scr_node_step_macro_move(draw_x);        break;
		case "MACRO_SEEK":        scr_node_step_macro_seek(draw_x);        break;
		case "MACRO_FLIP_X":      scr_node_step_macro_flip_x(draw_x);      break;
		case "MACRO_PRIORITY":    scr_node_step_macro_priority(draw_x);    break;
		case "MACRO_SPR_ENABLE":  scr_node_step_macro_spr_enable(draw_x);  break;
		case "MACRO_SPR_EXPAND":  scr_node_step_macro_spr_expand(draw_x);  break;
        case "MACRO_COLLISION":   scr_node_step_macro_collision(draw_x);   break;
		case "MACRO_COLL_ADV":    scr_node_step_macro_coll_adv(draw_x);    break;
		case "MACRO_COLL_LINE":   scr_node_step_macro_coll_line(draw_x);   break;
        case "MACRO_ANIM":        scr_node_step_macro_anim(draw_x);        break;
        case "MACRO_SFX":         scr_node_step_macro_sfx(draw_x);         break;
        case "MACRO_CODE":        scr_node_step_macro_code(draw_x);        break;
		case "MACRO_V_SCROLL":    scr_node_step_macro_vscroll();        break;
		case "MACRO_SCROLL":    scr_node_step_macro_scroll();        break;
        case "MACRO_IRQ":             scr_node_step_macro_irq();                    break;
        case "MACRO_IRQ_HANDLER":     scr_node_step_macro_irq_handler(draw_x);      break;
        case "MACRO_TEXT_SCROLL": scr_node_step_macro_text_scroll(); break;
        case "COND_IF":      scr_node_step_cond_if(draw_x); break;
		case "COND_IF_WORD": scr_node_step_cond_if_word(draw_x); break;
        case "BANK_SWITCH":  scr_node_step_bank_switch(draw_x); break;
        case "MACRO_REU":    scr_node_step_macro_reu(draw_x);   break;
		
		
		
	case "COMMENT":
	    if (!global.comments_visible) break;
	    if (point_in_rectangle(mouse_x, mouse_y, draw_x, y + 20, draw_x + width, y + height)) {
	        with (obj_workspace_manager) {
	            is_entering_text     = true;
	            input_target_node    = other.id;
	            input_target_index   = 0;
	            current_input_string = string(other.instructions[0][1]);
	            keyboard_string      = "";
	            cursor_pos           = string_length(current_input_string);
	        }
	    }
	    break;
    

	        case "ORG": {
	            var _chk_x   = draw_x + 10;
	            var _chk_y   = y + 60;
	            var _org_row_y = y + 24 + 6;
			
				// Fast-Add Variable Buttons Click Handler
	            if (node_title == "VARIABLES") {
		            var _btn_defs = [
		                { lbl: "+B",   type: "NEW_UV_BYTE",  sz: 1, enc: "byte" },
		                { lbl: "+sB",  type: "NEW_UV_SBYTE", sz: 1, enc: "sbyte" },
		                { lbl: "+W",   type: "NEW_UV_WORD",  sz: 2, enc: "word" },
		                { lbl: "+BCD", type: "NEW_UV_BCD",   sz: 1, enc: "bcd" },
		                { lbl: "+STR", type: "NEW_STR",      sz: 1, enc: "str" }
		            ];
		            var _bx = draw_x + 8;
		            var _by = y - 30; 
		            var _bw = 26;
		            var _bh = 16;
                
	                for (var _bi = 0; _bi < array_length(_btn_defs); _bi++) {
	                    var _bdef = _btn_defs[_bi];
	                    if (point_in_rectangle(mouse_x, mouse_y, _bx, _by, _bx + _bw, _by + _bh)) {
	                        with (obj_workspace_manager) {
	                            uv_pending_size      = _bdef.sz;
	                            uv_pending_enc       = _bdef.enc;
	                            is_entering_text     = true;
	                            input_target_node    = noone;
	                            input_target_index   = -99;
	                            current_input_string = "";
	                            keyboard_string      = "";
	                            cursor_pos           = 0;
								other.height_dirty = true;
	                        }
	                        exit;
	                    }
	                    _bx += _bw + 14;
	                }
	            }

	            // 0. Wire Dot Click
	            if (node_title != "VARIABLES" && node_title != "HW REGISTERS") {
	                var _dot_r     = 5;
	                var _dot_in_x  = draw_x;
	                var _dot_out_x = draw_x + width;
	                var _dot_y     = y + 10;
	                if (point_in_circle(mouse_x, mouse_y, _dot_in_x, _dot_y, _dot_r + 4)) {
	                    global.wire_drag_node   = id;
	                    global.wire_drag_is_out = false;
	                    exit;
	                }
	                if (point_in_circle(mouse_x, mouse_y, _dot_out_x, _dot_y, _dot_r + 4)) {
	                    global.wire_drag_node   = id;
	                    global.wire_drag_is_out = true;
	                    exit;
	                }
	            }

	            // 1. Proxy Toggle (Allow for VARIABLES)
	            if (node_title != "HW REGISTERS") {
	                if (point_in_rectangle(mouse_x, mouse_y, _chk_x, _chk_y, _chk_x + 12, _chk_y + 12)) {
                   
	                    if (!proxy) proxy_address = pc_address;
	                    proxy = !proxy;
                  
	                    global.addresses_dirty = true;
	                    exit;
	                }
	            }

	            // 2. Address Edit
	            var _in_address_zone = point_in_rectangle(mouse_x, mouse_y, draw_x, _org_row_y, draw_x + width, _org_row_y + 28);
	            if (_in_address_zone && node_title != "HW REGISTERS") {
             
	                proxy = false;
	                with (obj_workspace_manager) {
	                    is_entering_text   = true;
	                    input_target_node  = other.id;
	                    input_target_index = -1;
	                    var _h = decimal_to_hex(other.pc_address);
	                    while (string_length(_h) < 4) _h = "0" + _h;
	                    current_input_string = global.use_hex_display ? ("$" + string_upper(_h)) : string(other.pc_address);
	                    keyboard_string      = "";
	                    cursor_pos           = string_length(current_input_string);
	                }
	                exit;
	            }
	        } break;

	        case "DATA_SID": {
	            var _px = x + 10;
	            var _py = y + 24 + 6;
	            if (point_in_rectangle(mouse_x, mouse_y, _px, _py, x + width - 8, _py + 20)) {
               
	                scr_sid64_import(id);
	                exit;
	            }
	        } break;

	        case "SPR64": {
	            var _px = draw_x;
	            var _py = y + 24 + 6;
	            if (point_in_rectangle(mouse_x, mouse_y, _px, _py - 6, _px + (25 * 4), _py + 40)) {
               
	                exit;
	            }

	            var _btn_x1      = _px + (24 * 4) + 10;
	            var _frame_idx   = (array_length(instructions[0]) > 3) ? real(instructions[0][3]) : 0;
            var _chk_y       = _py + 26;
            var _nav_y       = _chk_y + 22;
            var _nav_left_x  = _btn_x1;
            var _nav_right_x = _nav_left_x + 56;
            var _arr_w = 24; var _arr_h = 28;

            if (point_in_rectangle(mouse_x, mouse_y, _btn_x1, _py, x + width - 8, _py + 20)) {
               
                scr_spr64_import(id); exit;
            }
            if (point_in_rectangle(mouse_x, mouse_y, _nav_left_x, _nav_y, _nav_left_x + _arr_w, _nav_y + _arr_h)) {
              
                instructions[0][3] = max(0, _frame_idx - 1); exit;
            }
            if (point_in_rectangle(mouse_x, mouse_y, _nav_right_x, _nav_y, _nav_right_x + _arr_w, _nav_y + _arr_h)) {
               
                instructions[0][3] = min(63, _frame_idx + 1); exit;
            }
        } break;

        case "RAW_DATA":
            if (point_in_rectangle(mouse_x, mouse_y, draw_x, y + 24, draw_x + width, y + height)) {
               
                with (obj_workspace_manager) {
                    is_entering_text     = true;
                    input_target_node    = other.id;
                    input_target_index   = 0;
                    current_input_string = string(other.instructions[0][1]);
                    keyboard_string      = "";
                    cursor_pos           = string_length(current_input_string);
                }
            }
            break;

        /// VARIABLE NODES
        case "COPY_VAR": {
            // SRC picker button
            var _sbx1 = draw_x + width - 58;
            var _sbx2 = draw_x + width - 4;
            var _sby1 = y + 30;
            var _sby2 = y + 44;
            if (point_in_rectangle(mouse_x, mouse_y, _sbx1, _sby1+2, _sbx2, _sby2)) {
                label_picker_open       = true;
                global.any_picker_open  = true;
                label_picker_prev_depth = depth;
                depth                   = -9999;
                label_picker_index      = 1; // SRC slot — writes to instructions[0][1]
                label_picker_scroll     = 0;
                label_picker_list       = [];
                label_picker_mode       = "VAR";
                label_picker_target     = id;
                exit;
            }
            // DST picker button
            var _dbx1 = draw_x + width - 58;
            var _dbx2 = draw_x + width - 4;
            var _dby1 = y + 50;
            var _dby2 = y + 64;
            if (point_in_rectangle(mouse_x, mouse_y, _dbx1, _dby1+2, _dbx2, _dby2)) {
                label_picker_open       = true;
                global.any_picker_open  = true;
                label_picker_prev_depth = depth;
                depth                   = -9999;
                label_picker_index      = 2; // DST slot — writes to instructions[0][2]
                label_picker_scroll     = 0;
                label_picker_list       = [];
                label_picker_mode       = "VAR";
                label_picker_target     = id;
                exit;
            }
        } break;

        case "INC_VAR":
        case "DEC_VAR": {
            // Name click opens VAR picker
            if (point_in_rectangle(mouse_x, mouse_y, draw_x, y + 24, draw_x + width, y + 40)) {
                label_picker_open       = true;
                global.any_picker_open  = true;
                label_picker_prev_depth = depth;
                depth = -9999;
                label_picker_index  = 0;
                label_picker_scroll = 0;
                label_picker_list   = [];
                label_picker_mode   = "VAR";
                label_picker_target = id;
                exit;
            }
        } break;

        case "GET_VAR": {
            // Backfill old saves
            while (array_length(instructions[0]) < 8) array_push(instructions[0], "");
            if (!is_real(instructions[0][2])) instructions[0][2] = 0;
            if (!is_real(instructions[0][4])) instructions[0][4] = 0;
            if (!is_real(instructions[0][5])) instructions[0][5] = 0;

            var _src_mode = real(instructions[0][2]);
            var _off_mode = real(instructions[0][4]);

            // Row anchors mirror the draw script (_ly starts at y+28, +17 per row)
            var _r0 = y + 28;   // SRC toggle / name / asset row
            var _r1 = _r0 + 17; // addr row (has VAR/ASSET button at +16)
            var _r2 = _r1 + 17; // size/offset row
            var _btn_y1 = _r0 + 16;
            var _btn_y2 = _r0 + 30;

            // 1. SRC MODE toggle (top-left)
            if (point_in_rectangle(mouse_x, mouse_y, draw_x + 10, _r0 - 2, draw_x + 80, _r0 + 12)) {
                instructions[0][2] = (_src_mode == 0) ? 1 : 0;
                global.addresses_dirty = true;
                global.undo_dirty = true;
                exit;
            }

            if (_src_mode == 0) {
                // VAR mode — click var name text (row 0, right of SRC toggle) to open picker
                if (point_in_rectangle(mouse_x, mouse_y, draw_x + 90, _r0 - 4, draw_x + width - 8, _r0 + 12)) {
                    label_picker_open   = true;
                    global.any_picker_open = true;
                    label_picker_prev_depth = depth;
                    depth = -9999;
                    label_picker_index  = 0;
                    label_picker_scroll = 0;
                    label_picker_list   = [];
                    label_picker_mode   = "VAR";
                    label_picker_target = id;
                    exit;
                }
            } else {
                // ASSET mode — click asset name text (row 0, right of SRC toggle) to open picker
                if (point_in_rectangle(mouse_x, mouse_y, draw_x + 90, _r0 - 4, draw_x + width - 8, _r0 + 12)) {
                    label_picker_open   = true;
                    global.any_picker_open = true;
                    label_picker_prev_depth = depth;
                    depth = -9999;
                    label_picker_index  = 3;            // writes asset name to instructions[0][3]
                    label_picker_scroll = 0;
                    label_picker_list   = [];
                    label_picker_mode   = "BYTE_ASSET";
                    label_picker_target = id;
                    exit;
                }

                // Offset mode toggle (row 2, left)
                if (point_in_rectangle(mouse_x, mouse_y, draw_x + 10, _r2, draw_x + 56, _r2 + 12)) {
                    instructions[0][4] = (real(instructions[0][4]) + 1) mod 4; // 0->1->2->3->0
                    global.addresses_dirty = true;
                    global.undo_dirty = true;
                    exit;
                }

                // Offset VAR name click (row 2) — only in var-offset mode
                if (_off_mode == 1) {
                    if (point_in_rectangle(mouse_x, mouse_y, draw_x + 64 + 8, _r2 - 3, draw_x + width - 8, _r2 + 12)) {
                        label_picker_open   = true;
                        global.any_picker_open = true;
                        label_picker_prev_depth = depth;
                        depth = -9999;
                        label_picker_index  = 6;        // writes offset var to instructions[0][6]
                        label_picker_scroll = 0;
                        label_picker_list   = [];
                        label_picker_mode   = "VAR";
                        label_picker_target = id;
                        exit;
                    }
                }

                // Offset literal text entry (row 2, middle) — only in lit mode
                if (_off_mode == 0) {
                    if (point_in_rectangle(mouse_x, mouse_y, draw_x + 64, _r2 - 2, draw_x + width - 60, _r2 + 12)) {
                        with (obj_workspace_manager) {
                            is_entering_text   = true;
                            input_target_node  = other.id;
                            input_target_index = 5;     // offset literal
                            var _ov = real(other.instructions[0][5]);
                            if (global.use_hex_display) {
                                var _oh = decimal_to_hex(_ov);
                                while (string_length(_oh) < 2) _oh = "0" + _oh;
                                current_input_string = "$" + string_upper(_oh);
                            } else {
                                current_input_string = string(_ov);
                            }
                            keyboard_string = "";
                            cursor_pos      = string_length(current_input_string);
                        }
                        exit;
                    }
                }

                // Dest var name click (row 3) — opens VAR picker into slot 7
                var _r3 = _r2 + 17;
                if (point_in_rectangle(mouse_x, mouse_y, draw_x + 10, _r3 - 3, draw_x + width - 8, _r3 + 12)) {
                    label_picker_open       = true;
                    global.any_picker_open  = true;
                    label_picker_prev_depth = depth;
                    depth = -9999;
                    label_picker_index  = 7;        // writes dest var to instructions[0][7]
                    label_picker_scroll = 0;
                    label_picker_list   = [];
                    label_picker_mode   = "VAR";
                    label_picker_target = id;
                    exit;
                }
            }
        } break;

        case "SET_VAR": {
            var _sv_mode  = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 0;
            var _sv_src_mode = (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) ? real(instructions[0][5]) : 0;
            var _sv_ptr_byte = (array_length(instructions[0]) > 7 && is_real(instructions[0][7])) ? real(instructions[0][7]) : 0;

            // Value-row Y (matches draw: y+28, +_lh, +_lh+6)
            var _sv_val_y = y + 58;
            var _sv_btn_x = draw_x + width - 46;

            // Offset ,X toggle (far right of name row) — offset-capable sources only
            var _sv_size = 1;
            var _sv_meta = scr_nloc_find_meta(string(instructions[0][1]));
            if (_sv_meta != undefined && variable_struct_exists(_sv_meta, "size")) {
                _sv_size = _sv_meta.size;
            }
            var _sv_offx_ok = (_sv_src_mode == 3)
                           || (_sv_src_mode == 1)
                           || (_sv_src_mode == 0 && _sv_mode == 0 && _sv_size < 2);
            if (_sv_offx_ok) {
                var _oxx1 = draw_x + width - 38;
                var _oxx2 = draw_x + width - 4;
                if (point_in_rectangle(mouse_x, mouse_y, _oxx1, y + 28 + 16, _oxx2, y + 28 + 28)) {
                    while (array_length(instructions[0]) < 9) array_push(instructions[0], 0);
                    if (!is_real(instructions[0][8])) instructions[0][8] = 0;
                    instructions[0][8] = (real(instructions[0][8]) == 0) ? 1 : 0;
                    global.addresses_dirty = true;
                    global.undo_dirty = true;
                    exit;
                }
            }

            // SRC mode toggle (LIT -> VAR -> PTR) — left of value row
            var _src_btn_x1 = draw_x + 10;
            var _src_btn_x2 = draw_x + 46;
            if (point_in_rectangle(mouse_x, mouse_y, _src_btn_x1, _sv_val_y, _src_btn_x2, _sv_val_y + 14)) {
                while (array_length(instructions[0]) < 8) array_push(instructions[0], 0);
                if (!is_real(instructions[0][5])) instructions[0][5] = 0;
                instructions[0][5] = (real(instructions[0][5]) + 1) mod 6;  // 0->1->2->3->4->5->0 (LIT/VAR/PTR/A/X/Y)
                global.addresses_dirty = true;
                global.undo_dirty = true;
                exit;
            }

            // ===== LIT MODE toggles =====
            if (_sv_src_mode == 0) {
                // ABS/REL toggle
                if (point_in_rectangle(mouse_x, mouse_y, _sv_btn_x, _sv_val_y, _sv_btn_x + 38, _sv_val_y + 14)) {
                    while (array_length(instructions[0]) < 4) array_push(instructions[0], 0);
                    instructions[0][3] = (_sv_mode == 0) ? 1 : 0;
                    global.addresses_dirty = true;
                    exit;
                }
                // NEG/POS toggle (REL only) — one row above value row
                if (_sv_mode == 1) {
                    var _sv_sbtn_y = _sv_val_y + 16;
                    if (point_in_rectangle(mouse_x, mouse_y, _sv_btn_x, _sv_sbtn_y, _sv_btn_x + 38, _sv_sbtn_y + 14)) {
                        while (array_length(instructions[0]) < 5) array_push(instructions[0], 0);
                        instructions[0][4] = (real(instructions[0][4]) == 0) ? 1 : 0;
                        global.addresses_dirty = true;
                        exit;
                    }
                }
            }

            // ===== PTR MODE: BYTE toggle (LIT/VAR) on value row =====
            if (_sv_src_mode == 2) {
                if (point_in_rectangle(mouse_x, mouse_y, _sv_btn_x, _sv_val_y, _sv_btn_x + 38, _sv_val_y + 14)) {
                    while (array_length(instructions[0]) < 8) array_push(instructions[0], 0);
                    if (!is_real(instructions[0][7])) instructions[0][7] = 0;
                    instructions[0][7] = (real(instructions[0][7]) == 0) ? 1 : 0;
                    global.addresses_dirty = true;
                    global.undo_dirty = true;
                    exit;
                }
            }

            // ===== SRC picker — click the var NAME (SRC SET button removed) =====
            // VAR mode: name is on the value row, drawn from x+52.
            // PTR-VAR mode: byte-src name is on the row below the value row, drawn from x+10.
            if (_sv_src_mode == 1) {
                if (point_in_rectangle(mouse_x, mouse_y, draw_x + 52, _sv_val_y, draw_x + width - 4, _sv_val_y + 12)) {
                    label_picker_open       = true;
                    global.any_picker_open  = true;
                    label_picker_prev_depth = depth;
                    depth                   = -9999;
                    label_picker_index      = 0;
                    label_picker_scroll     = 0;
                    label_picker_list       = [];
                    label_picker_mode       = "VAR_SRC";
                    label_picker_target     = id;
                    exit;
                }
            } else if (_sv_src_mode == 2 && _sv_ptr_byte == 1) {
                var _bsrc_y = _sv_val_y + 16;
                if (point_in_rectangle(mouse_x, mouse_y, draw_x + 10, _bsrc_y, draw_x + width - 4, _bsrc_y + 12)) {
                    label_picker_open       = true;
                    global.any_picker_open  = true;
                    label_picker_prev_depth = depth;
                    depth                   = -9999;
                    label_picker_index      = 0;
                    label_picker_scroll     = 0;
                    label_picker_list       = [];
                    label_picker_mode       = "VAR_SRC";
                    label_picker_target     = id;
                    exit;
                }
            }

            // ===== Text entry: LIT value (value row) or PTR-LIT byte (second row) =====
            // Block any other click inside the node body from mis-firing
            if (point_in_rectangle(mouse_x, mouse_y, draw_x, y + 24, draw_x + width, y + height)) {

                var _do_entry = false;
                var _entry_is_byte = false;

                // LIT mode: value row is editable (left portion only, toggles are on right)
                if (_sv_src_mode == 0
                    && point_in_rectangle(mouse_x, mouse_y, draw_x, _sv_val_y, draw_x + width - 50, _sv_val_y + 14)) {
                    _do_entry = true;
                }
                // PTR-LIT mode: byte row (y+74) is editable
                if (_sv_src_mode == 2 && _sv_ptr_byte == 0
                    && point_in_rectangle(mouse_x, mouse_y, draw_x, _sv_val_y + 16, draw_x + width - 10, _sv_val_y + 30)) {
                    _do_entry = true;
                    _entry_is_byte = true;
                }

                // Name row click (top) — opens the VAR picker directly (no text entry; dest must be an existing named var)
                // Exclude the far-right offset toggle zone so a ,X click doesn't also open the picker.
                var _is_name_click = point_in_rectangle(mouse_x, mouse_y, draw_x, y + 24, draw_x + width - 44, y + 40);
                if (_is_name_click) {
                    label_picker_open       = true;
                    global.any_picker_open  = true;
                    label_picker_prev_depth = depth;
                    depth                   = -9999;
                    label_picker_index      = 0;
                    label_picker_scroll     = 0;
                    label_picker_list       = [];
                    label_picker_mode       = "VAR";
                    label_picker_target     = id;
                    exit;
                }

                if (_do_entry) {
                    with (obj_workspace_manager) {
                        is_entering_text   = true;
                        input_target_node  = other.id;
                        input_target_index = 2;
                        if (_do_entry) {
                            var _v    = (array_length(other.instructions[0]) > 2 && is_real(other.instructions[0][2])) ? real(other.instructions[0][2]) : 0;
                            var _meta = scr_nloc_find_meta(string(other.instructions[0][1]));
                            var _bcd  = (_meta != undefined && variable_struct_exists(_meta, "encoding"))
                                        ? (string_pos("bcd", _meta.encoding) > 0)
                                        : false;
                            var _sz   = (_meta != undefined && variable_struct_exists(_meta, "size"))
                                        ? _meta.size
                                        : 1;
                            // PTR-LIT byte is always a single byte
                            if (_entry_is_byte) { _bcd = false; _sz = 1; }
                            if (_bcd || !global.use_hex_display) {
                                current_input_string = string(_v);
                            } else {
                                var _pad = (_sz >= 2) ? 4 : 2;
                                var _h   = decimal_to_hex(_v);
                                while (string_length(_h) < _pad) _h = "0" + _h;
                                current_input_string = "$" + string_upper(_h);
                            }
                        } else {
                            current_input_string = string(other.instructions[0][1]);
                        }
                        keyboard_string = "";
                        cursor_pos      = string_length(current_input_string);
                    }
                    exit;
                }

                // Otherwise: click landed in node body but not on an interactive zone — swallow it
                // (prevents VAR/PTR label rows from opening stray text entry)
                if (_sv_src_mode != 0) exit;
            }
        } break;

        default:
            if ((node_type == "NORMAL" || node_type == "LABEL" || is_data_node) &&
                 node_type != "DATA_SID" && node_type != "SPR64" && node_type != "BITMAP_KLA") {
                
                for (var i = 0; i < array_length(instructions); i++) {
                    var _line_y = y + 26 + (i * 12);
                    var _inst_raw = instructions[i][0];
                    var _inst_lower = string_lower(_inst_raw);
                    
                    var _implied = (
                        _inst_lower == "inx"   || _inst_lower == "iny"   || _inst_lower == "dex"   || _inst_lower == "dey"  ||
                        _inst_lower == "sei"   || _inst_lower == "cli"   || _inst_lower == "rts"   || _inst_lower == "rti"  ||
                        _inst_lower == "clc"   || _inst_lower == "sec"   || _inst_lower == "pha"   || _inst_lower == "pla"  ||
                        _inst_lower == "php"   || _inst_lower == "plp"   || _inst_lower == "tax"   || _inst_lower == "tay"  ||
                        _inst_lower == "txa"   || _inst_lower == "tya"   || _inst_lower == "tsx"   || _inst_lower == "txs"  ||
                        _inst_lower == "asl_a" || _inst_lower == "lsr_a" || _inst_lower == "nop"   || _inst_lower == "brk"
                    );

                    if (_implied && node_type != "LABEL") continue;

                    var _click_x1, _click_x2;
                    
                    if (_inst_lower == "label" || is_data_node) {
                        _click_x1 = draw_x;
                        _click_x2 = draw_x + width;
                    } else {
                        var _parts = scr_get_opcode_syntax_parts(_inst_raw);
                        var _prefix = _parts[0];
                        draw_set_font(fnt_c64_code);
                        _click_x1 = draw_x + 10 + string_width(_prefix);
                        var _val_str = "";
                        var _bv = instructions[i][1];
                        if (global.use_hex_display && is_real(_bv)) {
                            var _h = decimal_to_hex(_bv);
                            var _is_16bit = (string_pos("_abs", _inst_lower) > 0 || 
                                             string_pos("_abx", _inst_lower) > 0 || 
                                             string_pos("_aby", _inst_lower) > 0 || 
                                             string_pos("_ind", _inst_lower) > 0);
                            var _pad = _is_16bit ? 4 : 2;
                            while (string_length(_h) < _pad) _h = "0" + _h;
                            _val_str = "$" + string_upper(_h);
                        } else {
                            _val_str = string(_bv);
                        }
                        _click_x2 = _click_x1 + string_width(_val_str);
                    }

                    // 1. Operand Click
                    if (point_in_rectangle(mouse_x, mouse_y, _click_x1 - 4, _line_y, _click_x2 + 4, _line_y + 18)) {

                        // Jump/branch operands open the label picker directly (no text entry)
                        var _op_is_jump = (
                            _inst_lower == "jmp"     || _inst_lower == "jmp_abs" || _inst_lower == "jmp_ind" ||
                            _inst_lower == "jsr"     ||
                            _inst_lower == "bne"     || _inst_lower == "beq"     ||
                            _inst_lower == "bcc"     || _inst_lower == "bcs"     ||
                            _inst_lower == "bpl"     || _inst_lower == "bmi"     ||
                            _inst_lower == "bvc"     || _inst_lower == "bvs"
                        );
                        if (_op_is_jump) {
                            label_picker_open       = true;
                            global.any_picker_open  = true;
                            label_picker_prev_depth = depth;
                            depth                   = -9999;
                            label_picker_index      = i;
                            label_picker_scroll     = 0;
                            label_picker_list       = ["[clear]"];
                            label_picker_group      = "LABELS";
                            label_picker_is_jsr     = (_inst_lower == "jsr" && !global.kernal_unlocked);
                            with (obj_c64_node) {
                                if (node_type == "LABEL") {
                                    array_push(other.label_picker_list, string(instructions[0][1]));
                                }
                                if (node_type == "MACRO_ANIM") {
                                    if (anim_alias == "") anim_alias = "anim" + string(real(id));
                                    array_push(other.label_picker_list, anim_alias + "_sub");
                                    array_push(other.label_picker_list, anim_alias + "_reset");
                                }
                                if (node_type == "MACRO_SCROLL") {
				                    array_push(other.label_picker_list, "Scroller_L");
				                    array_push(other.label_picker_list, "Scroller_R");
				                    var _sc_src = (array_length(instructions[0]) > 6  && is_real(instructions[0][6]))  ? real(instructions[0][6])  : 0;
				                    var _sc_vm  = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
				                    if (_sc_src == 1 && _sc_vm == 1) {
				                        array_push(other.label_picker_list, "Scroller_MapSet");
				                    }
				                }
				                if (node_type == "MACRO_SID_SONG") {
				                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_play");
				                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_init");
				                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_seek");
				                }
                                if (node_type == "MACRO_VSCROLL") {
                                    array_push(other.label_picker_list, "Scroller_U");
                                    array_push(other.label_picker_list, "Scroller_D");
                                }
                                if (node_type == "MACRO_TEXT_SCROLL") {
                                    var _jsr_m = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
                                    if (_jsr_m == 1) {
                                        var _ts_alias = (array_length(instructions[0]) > 12 && is_string(instructions[0][12]) && string(instructions[0][12]) != "") ? string(instructions[0][12]) : ("ts" + string(real(id)));
                                        array_push(other.label_picker_list, _ts_alias + "_scrl");
                                    }
                                }
                                if (node_type == "MACRO_CODE" && other.label_picker_inc_code) {
                                    var _code_txt = string(instructions[0][1]);
                                    if (_code_txt != "") {
                                        var _code_lines = string_split(_code_txt, "\n");
                                        for (var _cli = 0; _cli < array_length(_code_lines); _cli++) {
                                            var _cl = string_trim(_code_lines[_cli]);
                                            var _colon_pos = string_pos(":", _cl);
                                            if (_colon_pos > 1) {
                                                var _lbl = string_trim(string_copy(_cl, 1, _colon_pos - 1));
                                                if (_lbl != "" && string_pos(" ", _lbl) == 0) {
                                                    array_push(other.label_picker_list, _lbl);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            exit;
                        }

                        with (obj_workspace_manager) {
                            is_entering_text   = true;
                            input_target_node  = other.id;
                            input_target_index = i;
        
                            var _bv  = other.instructions[i][1];
                            var _ins = string_lower(other.instructions[i][0]);
        
                            if (global.use_hex_display && is_real(_bv)) {
                                var _is_16bit = (string_pos("_abs", _ins) > 0 || 
                                                 string_pos("_abx", _ins) > 0 || 
                                                 string_pos("_aby", _ins) > 0 || 
                                                 string_pos("_ind", _ins) > 0);
                                var _pad = _is_16bit ? 4 : 2;
                                var _h   = decimal_to_hex(_bv);
                                while (string_length(_h) < _pad) _h = "0" + _h;
                                current_input_string = "$" + string_upper(_h);
                            } else {
                                current_input_string = string(_bv);
                            }
        
                            keyboard_string = "";
                            cursor_pos      = string_length(current_input_string);
                        }
                        exit;
                    }

                    // LOOK UP button removed — the operand click above opens the picker.
                }
            }
            break;
    }
} // end LMB click block

// Always-run per-frame logic for MACRO_SID (sid_exit repositioning)
if (node_type == "MACRO_SID" && is_connected && org_parent == noone) {
    scr_node_step_macro_sid_frame();
}

// Destroy sid_exit if no connected MACRO_SID exists on spine
if (node_type == "LABEL" && is_connected && org_parent == noone &&
    array_length(instructions) > 0 && array_length(instructions[0]) > 1 &&
    string(instructions[0][1]) == "sid_exit") {
    var _sid_still_connected = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected && org_parent == noone)
            { _sid_still_connected = true; break; }
    }
    if (!_sid_still_connected) {
        // Also reset exit_spawned on any disconnected MACRO_SID so it can respawn later
        with (obj_c64_node) {
            if (node_type == "MACRO_SID") exit_spawned = false;
        }
        instance_destroy();
        exit;
    }
}

/////////////////////////////////////////////////////////////////
// C2. WIRE DOT DRAG & RELEASE
/////////////////////////////////////////////////////////////////
if (mouse_check_button_released(mb_left) && instance_exists(global.wire_drag_node)) {
    var _drag_src     = global.wire_drag_node;
    var _drag_is_out  = global.wire_drag_is_out;
    var _dot_r        = 5;
    var _connected    = false;

    with (obj_c64_node) {
        if (id == _drag_src) continue;
        if (node_type != "ORG") continue;
        if (node_title == "VARIABLES" || node_title == "HW REGISTERS") continue;

        var _other_in_x  = x;
        var _other_out_x = x + width;
        var _other_dot_y = y + 10;

        var _hit_in  = point_in_circle(mouse_x, mouse_y, _other_in_x,  _other_dot_y, _dot_r + 4);
        var _hit_out = point_in_circle(mouse_x, mouse_y, _other_out_x, _other_dot_y, _dot_r + 4);

        if ((_drag_is_out && _hit_in) || (!_drag_is_out && _hit_out)) {
            var _src = _drag_is_out ? _drag_src : id;
            var _dst = _drag_is_out ? id : _drag_src;

            // Clear any previous connections on these dots
            _src.wire_out_target = -1;
            _dst.wire_in_source  = -1;

            _src.wire_out_target = _dst.org_uid;
            _dst.wire_in_source  = _src.org_uid;
            _connected           = true;
            global.addresses_dirty = true;
            global.undo_dirty      = true;
            scr_c64_update_addresses();
            break;
        }
    }

    global.wire_drag_node   = noone;
    global.wire_drag_is_out = false;
}

/////////////////////////////////////////////////////////////////
// D. NODE POSITIONING
/////////////////////////////////////////////////////////////////
if (node_type == "INIT") {
    x            = _spine_x;
    y            = 60;
    is_connected = true;


} else if (node_type == "EXECUTE") {
    instance_destroy();

} else {

    var _is_macro_child = (macro_owner != noone);

// Drag start — header bar only
if (mouse_check_button_pressed(mb_left) && !_mouse_in_gui && !obj_workspace_manager.is_panning && !instance_exists(obj_ui_color_picker) && _cam_zoom < 3.55 && !label_picker_open && !global.any_picker_open) {
         if (point_in_rectangle(mouse_x, mouse_y, draw_x, y, draw_x + width, y + 24) &&
            !(node_type == "LABEL" && array_length(instructions) > 0 && array_length(instructions[0]) > 1 && string(instructions[0][1]) == "sid_exit")) {

            // ---- GROUP MOVE DRAG ----
            if (id == global.group_drag_handle && array_length(global.selected_nodes) > 1
                && !(keyboard_check(vk_control) || scr_cmd_held())) {

                var _handle_spine = org_parent;
                var _filtered = [];
                for (var _fi = 0; _fi < array_length(global.selected_nodes); _fi++) {
                    var _fn = global.selected_nodes[_fi];
                    if (!instance_exists(_fn)) continue;
                    if (_fn.node_type == "INIT" || _fn.node_type == "ORG") continue;
                    var _fn_free = (string_pos("DATA", _fn.node_type) > 0 ||
                                    _fn.node_type == "RAW_DATA" || _fn.node_type == "SPR64" ||
                                    _fn.node_type == "BITMAP_KLA");
                    if (_fn_free) continue;
                    if (_fn.org_parent == _handle_spine) array_push(_filtered, _fn);
                }
                array_sort(_filtered, function(_a, _b) { return _a.y - _b.y; });
                global.selected_nodes    = _filtered;
                global.group_drag_handle = (array_length(_filtered) > 0) ? _filtered[0] : noone;
///
if (global.group_drag_handle == id) {
                    global.group_drag_active   = true;
                    global.group_drag_is_clone = false;
                    global.group_drag_nodes    = [];

				for (var _gi = 0; _gi < array_length(_filtered); _gi++) {
                        var _gn = _filtered[_gi];
                        array_push(global.group_drag_nodes, {
                            node: _gn,
                            dx:   _gn.x - x,
                            dy:   _gn.y - y
                        });
                        if (_gn != id) {
                            _gn.is_connected = false;
                            _gn.org_parent   = noone;
                            _gn.depth        = -2000;
                        }
                    }

// Compact spine — close gap left by removed followers
                    var _G = 20;
                    var _removed_h = 0;
                    for (var _gci = 1; _gci < array_length(_filtered); _gci++) {
                        _removed_h += _filtered[_gci].height;
                    }
                    if (_removed_h > 0) {
                        var _gap_y    = _filtered[1].y;
                        var _handle_spine = _filtered[0].org_parent;
                        var _init_bottom_ref = 80; // INIT y=60 + height=20
                        with (obj_c64_node) {
                            if (node_type == "INIT") { _init_bottom_ref = y + height; break; }
                        }
						with (obj_c64_node) {
                            if (is_connected && org_parent == _handle_spine &&
                                _handle_spine != noone &&
                                node_type != "ORG" && y > _gap_y) {
                                var _in_grp = false;
                                for (var _gci2 = 0; _gci2 < array_length(_filtered); _gci2++) {
                                    if (_filtered[_gci2] == id) { _in_grp = true; break; }
                                }
                                if (!_in_grp) y = max(_init_bottom_ref, y - _removed_h);
                            }
                        }
                        scr_c64_update_addresses();
                    }
                }
            }

            // ---- STANDARD DRAG START ----
            // Topmost (lowest depth) node under the pointer claims the drag.
            var _blocked = false;
            var _self_ref = id;
            with (obj_c64_node) {
                if (id == _self_ref) continue;
                if (is_dragging) continue;
                if (depth < _self_ref.depth) {
                    var _hdr_x = x + x_indent;
                    if (point_in_rectangle(mouse_x, mouse_y, _hdr_x, y, _hdr_x + width, y + 24)) {
                        _blocked = true;
                        break;
                    }
                }
            }
            if (_blocked || global.drag_claim_taken) exit;
            global.drag_claim_taken = true;

            is_dragging  = true;
            was_dragged  = false;
            drag_start_x = x + x_indent;
            global.active_drag_node = id;
            pre_click_depth = depth;
            depth           = -2000;
            // Stash indent and zero it for the duration of the drag so the Draw
            // event's "x += x_indent" does not double-apply while moving.
            drag_indent_stash = x_indent;
            x_indent          = 0;
            drag_offset_x     = x - mouse_x;
            drag_offset_y     = y - mouse_y;
            label_picker_open      = false;
            global.any_picker_open = false;
            depth                  = label_picker_prev_depth;
        }
    }

if (is_dragging && !_is_group_follower) {
        var _prev_x = x;
        var _prev_y = y;
        x = mouse_x + drag_offset_x;
        y = mouse_y + drag_offset_y;
		
		if (x != _prev_x || y != _prev_y) {
		    was_dragged = true;
		    if (!is_free_node && !_is_macro_child && !mouse_check_button_released(mb_left)) {
		        if (is_connected) {
		            if (instance_exists(obj_workspace_manager)) obj_workspace_manager.flow_overlay_dirty = true;
		        }
		        org_parent   = noone;
		        is_connected = false;
		    }
		}

// ---- MOVE GROUP FOLLOWERS (delta-based, same as ORG children) ----
        if (global.group_drag_active && id == global.group_drag_handle) {
            var _gdx = x - _prev_x;
            var _gdy = y - _prev_y;
            if (_gdx != 0 || _gdy != 0) {
                for (var _gfi = 1; _gfi < array_length(global.group_drag_nodes); _gfi++) {
                    var _gfn = global.group_drag_nodes[_gfi].node;
                    if (!instance_exists(_gfn)) continue;
                    _gfn.x += _gdx;
                    _gfn.y += _gdy;
                }
            }
        }

        // Snap to spine while dragging
        if (!is_free_node && !_is_macro_child && node_type != "ORG" && node_type != "NAMED_LOC" && org_parent == noone) {
            var _spine_bottom = 64;
            with (obj_c64_node) {
                if (is_connected && org_parent == noone && (macro_owner == noone) &&
                    node_type != "ORG" && node_type != "EXECUTE") {
                    if (y + height > _spine_bottom) _spine_bottom = y + height;
                }
            }
            var _node_cx  = x + width * 0.5;
            var _spine_cx = _spine_x + global.node_display_width * 0.5;
            if (y < _spine_bottom || y <= _spine_bottom + _sticky_h) {
               // snap suppressed
            }
        }

        // ORG drags its children with it
        if (node_type == "ORG") {
            var _dx = x - _prev_x;
            var _dy = y - _prev_y;
            if (_dx != 0 || _dy != 0) {
                var _org_ref = id;
                with (obj_c64_node) {
                    if (org_parent == _org_ref) { x += _dx; y += _dy; depth = -2000; }
                }
            }
        }

// ---- WEDGE PREVIEW ----
        // Restore all previously shifted nodes before recomputing
        with (obj_c64_node) {
            if (wedge_y_stored >= 0) {
                // Don't snap group followers back — handle moves them via delta
                var _wrf = false;
                if (global.group_drag_active) {
                    for (var _wfi = 1; _wfi < array_length(global.group_drag_nodes); _wfi++) {
                        if (global.group_drag_nodes[_wfi].node == id) { _wrf = true; break; }
                    }
                }
                if (!_wrf) { y = wedge_y_stored; wedge_y_stored = -1; }
            }
        }
        global.wedge_preview_y      = -1;
        global.wedge_preview_node   = noone;
        global.wedge_preview_h      = height;
        global.wedge_preview_spine  = true;
        global.wedge_preview_anchor = noone;

        if (!is_free_node && !_is_macro_child && org_parent == noone &&
            node_type != "ORG" && node_type != "INIT") {

            var _this_cx  = x + width * 0.5;
            var _spine_cx = _spine_x + global.node_display_width * 0.5;

			var _max_ind_prev = 0;
            with (obj_c64_node) {
                if (is_connected && org_parent == noone && x_indent > _max_ind_prev)
                    _max_ind_prev = x_indent;
            }
            if (abs(_this_cx - _spine_cx) <= global.node_display_width * 0.5 + 10 + _max_ind_prev) {
                // Main spine preview
                var _pa = noone; var _pb = noone;
                var _bay = -999999; var _bby = 999999;
				with (obj_c64_node) {
                    if (id != other.id && !is_dragging && is_connected && org_parent == noone &&
                        macro_owner == noone && node_type != "EXECUTE" && node_type != "ORG") {
                        if (y <= other.y && y > _bay) { _bay = y; _pa = id; }
                        if (y >  other.y && y < _bby) { _bby = y; _pb = id; }
                    }
                }
if (_pa != noone && _pb != noone) {
                    var _preview_insert_y = ceil((_pa.y + _pa.height) / 20) * 20;
                    if (abs(y - _preview_insert_y) <= _latch_h) {
                        global.wedge_preview_y     = _preview_insert_y;
                        global.wedge_preview_node  = _pb;
                        global.wedge_preview_spine = true;
                    }
                }
			} else {
                // ORG chain preview
                var _oa = noone; var _bd = global.node_display_width * 1.2;
                var _is_var_node_prev = (node_type == "NAMED_LOC" || node_type == "NEW_STR");
                with (obj_c64_node) {
                    if (node_type == "ORG") {
                        if (node_title == "VARIABLES" && !_is_var_node_prev) continue;
                        if (node_title != "VARIABLES" && _is_var_node_prev) continue;
						var _org_cx_prev   = x + width * 0.5;
                        var _cby_prev      = y + height;
                        var _oref_prev     = id;
                        with (obj_c64_node) {
                            if (org_parent == _oref_prev && is_connected)
                                if (y + height > _cby_prev) _cby_prev = y + height;
                        }
                        var _nearest_y_prev = clamp(other.y, y, _cby_prev + _latch_h);
                        var _pd = point_distance(other.x + other.width * 0.5, other.y, _org_cx_prev, _nearest_y_prev);
                        if (_pd < _bd) { _bd = _pd; _oa = id; }
                    }
                }
				if (_oa != noone) {
                    var _ia = _oa; var _iby = -999999;
                    with (obj_c64_node) {
                        if (org_parent == _oa && is_connected && y <= other.y && y > _iby) {
                            _iby = y; _ia = id;
                        }
                    }
                    var _ib = noone; var _ibby = 999999;
                    with (obj_c64_node) {
                        if (org_parent == _oa && is_connected && y > other.y && y < _ibby) {
                            _ibby = y; _ib = id;
                        }
                    }
                    if (_ib != noone) {
                        global.wedge_preview_y      = _ia.y + _ia.height;
                        global.wedge_preview_node   = _ib;
                        global.wedge_preview_spine  = false;
                        global.wedge_preview_anchor = _oa;
                    }
                }
            }
        }
        // Shift nodes below the preview Y down by this node's height
if (global.wedge_preview_y >= 0) {
            var _ph     = height;
            var _py     = global.wedge_preview_y;
            var _pspine = global.wedge_preview_spine;
            var _panch  = global.wedge_preview_anchor;
            var _drag_node = global.active_drag_node;
            var _is_new_node = instance_exists(_drag_node) && !_drag_node.is_connected;
            var _shift = _is_new_node ? _ph : 40;
            with (obj_c64_node) {
                if (!is_dragging && is_connected && wedge_y_stored < 0) {
                    var _on_spine = (_pspine && org_parent == noone);
                    var _on_org   = (!_pspine && org_parent == _panch);
                    if ((_on_spine || _on_org) && y >= _py) {
                        wedge_y_stored = y;
                        y += _shift;
                    }
                }
            }
        }

        // ---- END WEDGE PREVIEW ----

 
 // Drag release
            if (mouse_check_button_released(mb_left)) {
                // Restore wedge-shifted nodes BEFORE D2/D3 compute insert position
                with (obj_c64_node) {
                    if (wedge_y_stored >= 0) { y = wedge_y_stored; wedge_y_stored = -1; }
                }
                global.wedge_preview_y = -1;

                // Pure click (no movement) — restore the stashed indent so the node
                // stays exactly where it was. A real drag leaves indent at 0 here and
                // re-inherits it from neighbours in the D2/D3 wedge logic.
                if (!was_dragged) { x_indent = drag_indent_stash; }

				is_dragging            = false;
				depth                  = was_dragged ? -500 : pre_click_depth;
				global.addresses_dirty = true;
				scr_c64_update_addresses();
				if (was_dragged) {
				    x = round(x / 20) * 20;
				    y = round(y / 20) * 20;
				    
				    // Universal floating node overlap prevention — runs AFTER grid snap
				    // Applies to any node that is not attached to spine or ORG
				    if (!is_connected && org_parent == noone) {
				        var _overlap_found = true;
				        var _nudge_attempts = 0;
				        var _self_ref = id;
				        while (_overlap_found && _nudge_attempts < 64) {
				            _overlap_found = false;
				            with (obj_c64_node) {
				                if (id == _self_ref) continue;
				                if (is_connected || org_parent != noone) continue;
				                if (is_dragging) continue;
				                if (x == _self_ref.x && y == _self_ref.y) {
				                    _overlap_found = true;
				                    break;
				                }
				            }
				           if (_overlap_found) {
				                var _other_h = 20;
				                with (obj_c64_node) {
				                    if (id == _self_ref) continue;
				                    if (is_connected || org_parent != noone) continue;
				                    if (is_dragging) continue;
				                    if (x == _self_ref.x && y == _self_ref.y) {
				                        _other_h = height;
				                        break;
				                    }
				                }
				                y += ceil(_other_h / 20) * 20;
				                _nudge_attempts++;
				            }
				        }
				    }
				}
            global.active_drag_node = id; // Re-affirm so D2/D3 can identify this node
            global.drop_occurred_this_frame = true;
// Force overlap re-evaluation on all nodes after a drop
            with (obj_c64_node) { 
                last_overlap_check = false;
                overlap_check_dirty = true;
            }

			if (node_type == "ORG") {

                x = round(x / 20) * 20;
                y = round(y / 20) * 20;

                var _org_ref = id;
                with (obj_c64_node) {
                    if (org_parent == _org_ref) {
                        depth = other.was_dragged ? -500 : other.pre_click_depth;
                        x = other.x;
                        y = round(y / 20) * 20;
                    }
                }
            }

            var _sx = (x - _cam_x) / _cam_zoom;
            if (!obj_workspace_manager.expert_mode && _sx < obj_workspace_manager.shelf_width) {
               
                instance_destroy();
            } else {
			if (was_dragged && !is_free_node && !_is_macro_child) {
                    var _re_attached_to_org = false;
                    var _this_cx = x + width * 0.5;
                    var _this_cy = y + height * 0.5;
                    with (obj_c64_node) {
                        if (node_type == "ORG") {
                            var _org_cx = x + width * 0.5;
                            var _org_cy = y + height * 0.5;
                            if (point_distance(_this_cx, _this_cy, _org_cx, _org_cy) < global.node_display_width * 1.2)
                                _re_attached_to_org = true;
                        }
                    }
                    var _node_cx   = x + width * 0.5;
                    var _spine_cx  = _spine_x + global.node_display_width * 0.5;
					var _near_main = (abs(_node_cx - _spine_cx) <= global.node_display_width * 0.5 + 10);
                   
                    if (!_re_attached_to_org && !_near_main) {
                       
                        if (is_connected) {
                            if (instance_exists(obj_workspace_manager)) obj_workspace_manager.flow_overlay_dirty = true;
                        }
                        is_connected = false;
                    }
                    // NAMED_LOC and NEW_STR must never connect to main spine
                    if (node_type == "NAMED_LOC" || node_type == "NEW_STR") {
                        if (_re_attached_to_org && instance_exists(org_parent) && org_parent.node_title != "VARIABLES") {
                            is_connected = false;
                        }
                        if (_near_main) is_connected = false;
                    }
                }

                if (was_dragged && !is_free_node && org_parent == noone && node_type != "NAMED_LOC" && node_type != "ORG") {
                    var _node_cx      = x + width * 0.5;
                    var _spine_cx     = _spine_x + global.node_display_width * 0.5;
					var _spine_bottom = -1;
                    var _self_id = id;
                    with (obj_c64_node) {
                        if (id != _self_id && is_connected && org_parent == noone && macro_owner == noone &&
                            node_type != "ORG" && node_type != "EXECUTE") {
                            if (y + height > _spine_bottom) _spine_bottom = y + height;
                        }
                    }
                   
					var _started_on_spine = (abs(drag_start_x - _spine_x) <= global.node_display_width * 0.5);
					if (_spine_bottom > 0
                    &&  abs(_node_cx - _spine_cx) <= global.node_display_width * 0.5 + 10
                    &&  y >= _spine_bottom
                    &&  y <= _spine_bottom + _latch_h) {
                       
                        if (!is_connected) {
                            if (instance_exists(obj_workspace_manager)) obj_workspace_manager.flow_overlay_dirty = true;
                        }
                        is_connected = true;
                        x            = round(_spine_cx / 20) * 20;
                      //  x_indent     = 0;
                        y            = round(_spine_bottom / 20) * 20;
				} else {
                        // Snap X only if: mouse is over a header node (INIT or ORG) AND dragged from close to spine X
                        var _mouse_over_header = false;
                        var _snap_dist = global.node_display_width * 0.5;
                        with (obj_c64_node) {
                            if ((node_type == "INIT" || node_type == "ORG") &&
                                point_in_rectangle(mouse_x, mouse_y, x, y, x + width, y + 24)) {
                                _mouse_over_header = true;
                            }
                        }
                        var _started_near_spine = (abs(drag_start_x - _spine_x) <= _snap_dist);
						if (_mouse_over_header && _started_near_spine) {
                            x            = _spine_x;
                          //  x_indent     = 0;
                            is_connected = true;
                        }
                       
                    }
                }
                scr_c64_update_addresses();
            }
        }
    }

    /////////////////////////////////////////////////////////////////
    // D2. MAIN SPINE WEDGE INSERTION
    /////////////////////////////////////////////////////////////////

if (!_is_group_follower && mouse_check_button_released(mb_left) && was_dragged &&
        !_is_macro_child && org_parent == noone && !global.box_drag_active &&
        node_type != "ORG" && node_type != "INIT" && !is_free_node) {

        if (id != global.active_drag_node) exit;
        // Ensure all wedge-shifted nodes are restored before computing insert position
        with (obj_c64_node) {
            if (wedge_y_stored >= 0) { y = wedge_y_stored; wedge_y_stored = -1; }
        };
        var _G        = 20;
        var _this_y   = y - 8;
        var _this_cx  = x + width * 0.5;
        var _spine_cx = _spine_x + global.node_display_width * 0.5;

        // Only insert if dropped within or below INIT
        var _init_bottom = 0;
        with (obj_c64_node) {
            if (node_type == "INIT") { _init_bottom = y + height; break; }
        }
		
var _init_top = 0;
        with (obj_c64_node) {
            if (node_type == "INIT") { _init_top = y; break; }
        }
        if (_this_y < _init_top) {
           is_connected = false;
            exit;
        }
// Guard: skip wedge insertion if dropped above INIT top

       

        var _max_indent = 0;
        with (obj_c64_node) {
            if (is_connected && org_parent == noone && x_indent > _max_indent)
                _max_indent = x_indent;
        }
        if (abs(_this_cx - _spine_cx) <= global.node_display_width * 0.5 + 10 + _max_indent) {

            var _node_above = noone;
            var _node_below = noone;
            var _best_above_y = -999999;
            var _best_below_y =  999999;

            var _insert_above = noone;
            with (obj_c64_node) {
                if (node_type == "INIT") { _insert_above = id; break; }
            }

            with (obj_c64_node) {
                if (id != other.id && is_connected && org_parent == noone &&
                    (macro_owner == noone) &&
                    node_type != "EXECUTE" && node_type != "ORG") {
					if (y <= _this_y + 20 && y > _best_above_y) {
					    _best_above_y = y;
					    _insert_above = id;
					}
                    if (y > _this_y && y < _best_below_y) {
                        _best_below_y = y;
                        _node_below   = id;
                    }
                }
            }

           

			var _above_bottom = _insert_above.y + _insert_above.height;
			var _in_latch_zone = (_this_y >= _above_bottom - height && _this_y <= _above_bottom + _latch_h);
			var _is_mid_insert = (_node_below != noone);
			if (_insert_above != noone && (_is_mid_insert || _in_latch_zone)) {
				var _insert_y = (global.wedge_preview_y >= 0) ? global.wedge_preview_y : ceil(_above_bottom / _G) * _G;
               
				x        = _spine_x;
				y        = _insert_y;
				if (!is_connected) {
					if (instance_exists(obj_workspace_manager)) obj_workspace_manager.flow_overlay_dirty = true;
				}
				is_connected = true;
				// Inherit indent from neighbours — prefer the more indented of the two
                var _tab_above = instance_exists(_insert_above) ? _insert_above.x_indent : 0;
                var _tab_below = instance_exists(_node_below)   ? _node_below.x_indent   : 0;
                x_indent = max(_tab_above, _tab_below);

                if (_node_below != noone && (y + height) > _node_below.y - 1) {
                    var _push    = ceil((y + height - _node_below.y) / _G) * _G;
                    var _push_y0 = _node_below.y;
                    
                    with (obj_c64_node) {
                        if (id != other.id && is_connected && org_parent == noone &&
                            (macro_owner == noone) && node_type != "ORG" && !is_dragging &&
                            y >= _push_y0) {
                           
                            y += _push;
                        }
                    }
                }
                scr_c64_update_addresses();
            } else {
               
            }
        } else {
           
        }
    }

    /////////////////////////////////////////////////////////////////
    // D3. ORG CHAIN WEDGE INSERTION
    /////////////////////////////////////////////////////////////////
if (!_is_group_follower && mouse_check_button_released(mb_left) && was_dragged &&
        !_is_macro_child && org_parent == noone && !global.box_drag_active &&
        node_type != "ORG" && node_type != "INIT" && !is_free_node) {

        var _this_cx    = x + width * 0.5;
        var _this_y     = y - 8;
        var _org_anchor = noone;
        var _best_dist  = global.node_display_width * 0.5 + 10;

       

		with (obj_c64_node) {
            if (node_type == "ORG") {
				var _is_var_node_check = (other.node_type == "NAMED_LOC" || other.node_type == "NEW_STR" || other.node_type == "COMMENT");
                if (node_title == "VARIABLES" && !_is_var_node_check) continue;
                if (node_title != "VARIABLES" && _is_var_node_check && other.node_type != "COMMENT") continue;
                var _org_cx = x + global.node_display_width * 0.5;
                var _dist   = abs(_this_cx - _org_cx);
                if (_dist < _best_dist) {
var _cby     = y + height;
                    var _oref    = id;
                    var _org_cx2 = x + width * 0.5;
                    var _org_cy2 = y + height * 0.5;
                    with (obj_c64_node) {
                        if (org_parent == _oref && is_connected)
                            if (y + height > _cby) _cby = y + height;
                    }
					var _in_latch  = (_this_y >= _cby - height && _this_y <= _cby + _latch_h);
                    var _in_chain  = (_this_y >= y && _this_y < _cby);
                    var _nearest_y = clamp(_this_y, y, _cby + _latch_h);
                    var _pdist     = point_distance(_this_cx, _this_y, _org_cx2, _nearest_y);
                   
                    if ((_in_latch || _in_chain) && _pdist < global.node_display_width * 1.2) { _best_dist = _dist; _org_anchor = id; }
                }
            }
        }

		// Variable nodes (NAMED_LOC, NEW_STR) only go to VARIABLES ORG
        // All other nodes are blocked from VARIABLES ORG entirely
        if (_org_anchor != noone) {
var _is_var_node = (node_type == "NAMED_LOC" || node_type == "NEW_STR");
            var _is_comment  = (node_type == "COMMENT");
            var _is_vars_org = (_org_anchor.node_title == "VARIABLES");
            if (_is_var_node && !_is_vars_org) {
               
                _org_anchor = noone;
            }
            if (!_is_var_node && !_is_comment && _is_vars_org) {
              
                _org_anchor = noone;
            }
        }

        if (_org_anchor != noone) {
            var _insert_above = _org_anchor;
            var _insert_below = noone;
            var _best_above_y = _org_anchor.y;
            var _best_below_y = 999999;

            with (obj_c64_node) {
                if (org_parent == _org_anchor && is_connected && (macro_owner == noone)) {
                    if (y <= _this_y && y > _best_above_y) { _best_above_y = y; _insert_above = id; }
                    if (y > _this_y  && y < _best_below_y) { _best_below_y = y; _insert_below = id; }
                }
            }

          

			var _org_ind_above = (_insert_above != _org_anchor) ? _insert_above.x_indent : 0;
            var _org_ind_below = instance_exists(_insert_below) ? _insert_below.x_indent : 0;
            x                  = _org_anchor.x;
            y = (global.wedge_preview_y >= 0 && !global.wedge_preview_spine) ? global.wedge_preview_y : _insert_above.y + _insert_above.height;
            x_indent            = max(_org_ind_above, _org_ind_below);
            if (!is_connected) {
                if (instance_exists(obj_workspace_manager)) obj_workspace_manager.flow_overlay_dirty = true;
            }
            is_connected        = true;
            org_parent          = _org_anchor;
            last_overlap_check = false;
            global.addresses_dirty = true;
          
           

            if (_insert_below != noone) {
                var _push = (y + height) - _insert_below.y;
                if (_push > 0) {
                    var _push_start = _insert_below.y;
                  
                    with (obj_c64_node) {
                        if (org_parent == _org_anchor && is_connected && id != other.id &&
                            (macro_owner == noone) && y >= _push_start) {
                           
                            y += _push;
                        }
                    }
                }
            }
            scr_c64_update_addresses();
} else {
            // Dropped near an ORG column but above its header — disconnect
            if (was_dragged && !is_free_node && org_parent == noone) {
                var _self_cx   = x + width * 0.5;
                with (obj_c64_node) {
                    if (node_type == "ORG") {
                        var _org_cx = x + global.node_display_width * 0.5;
                        if (abs(_self_cx - _org_cx) <= global.node_display_width * 0.5 + 10
                        &&  other.y < y) {
                            other.is_connected = false;
                        }
                    }
                }
            }
        }
    }

if (mouse_check_button_released(mb_left)) {
        if (was_dragged) {
            global.undo_dirty = true;
            
            // --- RADIAL GRID TRACER EFFECT ---
            if (global.visual_fx && is_connected && !has_ever_connected) {
                has_ever_connected = true;
                
                // Spawn a random number of tracers
                var _num_tracers = irandom_range(4, 6 + height);
                
                for(var i = 0; i < _num_tracers; i++) {
                    var _t = instance_create_depth(x + (width / 2), y + (height / 2), depth - 100, obj_grid_tracer);
                    
                    // Pick a random cardinal direction for this tracer
                    _t.dir = choose(0, 90, 180, 270);
                    
                    // 50% chance to spawn a secondary runner in the same direction that goes further
                    if (choose(true, false)) {
                         var _t2 = instance_create_depth(x + (width / 2), y + (height / 2), depth - 100, obj_grid_tracer);
                         _t2.dir = _t.dir; // Match the parent tracer's direction
                         _t2.max_dist += 100;
                    }
                }
            }
            // ---------------------------------
        }
        
///
// ---- GROUP DROP FINALISE ----
        if (global.group_drag_active && id == global.group_drag_handle) {
            var _base_org = org_parent;
            var _G        = 20;
            array_sort(global.group_drag_nodes, function(_a, _b) { return _a.dy - _b.dy; });

            // Snap handle to grid (D2/D3 placed it, just clean up)
            x = round(x / _G) * _G;
            y = round(y / _G) * _G;

            // Calculate total height of all followers
            var _followers_total_h = 0;
            for (var _gdi = 1; _gdi < array_length(global.group_drag_nodes); _gdi++) {
                var _fn = global.group_drag_nodes[_gdi].node;
                if (instance_exists(_fn)) _followers_total_h += _fn.height;
            }

		// Push existing connected nodes below handle down to make room
		if (_followers_total_h > 0 && is_connected) {
		    var _insert_bottom = y + height;
		    with (obj_c64_node) {
		        if (is_connected && !is_dragging && org_parent == _base_org &&
		            node_type != "ORG" && y >= _insert_bottom) {
		            var _in_group = false;
		            for (var _gci = 0; _gci < array_length(global.group_drag_nodes); _gci++) {
		                if (global.group_drag_nodes[_gci].node == id) { _in_group = true; break; }
		            }
		            if (!_in_group) y += _followers_total_h;
		        }
		    }
		}

            // Now stack followers in the cleared space immediately below handle
            var _running_y = y + height;
            for (var _gdi = 1; _gdi < array_length(global.group_drag_nodes); _gdi++) {
                var _fn = global.group_drag_nodes[_gdi].node;
                if (!instance_exists(_fn)) continue;
                _fn.x            = x;
                _fn.y            = round(_running_y / _G) * _G;
                //_fn.x_indent     = x_indent;
                _fn.is_connected = is_connected;
                _fn.org_parent   = _base_org;
                _fn.depth        = -500;
                _running_y       = _fn.y + _fn.height;
            }

// Reset follower state
            for (var _gdi = 0; _gdi < array_length(global.group_drag_nodes); _gdi++) {
                var _fn = global.group_drag_nodes[_gdi].node;
                if (!instance_exists(_fn)) continue;
                _fn.was_dragged  = false;
                _fn.is_dragging  = false;
                _fn.wedge_y_stored = -1;
            }
            global.group_drag_active = false;
            global.group_drag_nodes  = [];
            global.group_drag_handle = noone;
            global.selected_nodes    = [];
            scr_c64_update_addresses();
        }

        was_dragged = false;
        global.active_drag_node = noone;
        global.drop_occurred_this_frame = false;
    }

/////////////////////////////////////////////////////////////////
    // D4. ORG CHAIN COMPACTION
    /////////////////////////////////////////////////////////////////
if (global.any_node_dragging && !is_dragging && !_is_macro_child && !_is_group_follower &&
        org_parent != noone && is_connected && wedge_y_stored < 0) {
        var _above      = noone;
        var _best_above = -9999;

        with (obj_c64_node) {
            if ((id == other.org_parent || org_parent == other.org_parent) &&
                id != other.id && is_connected && (macro_owner == noone) &&
                y < other.y && y > _best_above) {
                _best_above = y;
                _above      = id;
            }
        }
        if (_above == noone && instance_exists(org_parent)) _above = org_parent;

        if (_above != noone) {
            var _target_y = _above.y + _above.height;
            if (y > _target_y + 1) {
              
                y = _target_y;
                scr_c64_update_addresses();
            }
        }
    }
}

/////////////////////////////////////////////////////////////////
// D5. DYNAMIC HEIGHT ADJUSTMENT
/////////////////////////////////////////////////////////////////
if (!node_ready) { node_ready = true; prev_height = height; exit; }

// Removed the 'is_entering_text' requirement so that finishing text entry (pressing Enter) 
// triggers the push down automatically when the node height recalculates.
if (is_connected && prev_height != height && !global.drop_occurred_this_frame) {

    var _diff = height - prev_height;
    var _my_y = y;
    var _my_id = id;
    var _is_org_child = (org_parent != noone);

   

    with (obj_c64_node) {
        if (id != _my_id && is_connected && y > _my_y) {
            if (!_is_org_child && org_parent == noone && x == _my_id.x) {
               
                y += _diff;
            }
            else if (_is_org_child && org_parent == _my_id.org_parent) {
               
                y += _diff;
            }
        }
    }
    prev_height = height;
	
    global.addresses_dirty = true;
}

/////////////////////////////////////////////////////////////////
// E. ADDRESS DIRTY FLAG ON ANY CLICK
/////////////////////////////////////////////////////////////////
if (mouse_check_button_pressed(mb_left) || mouse_check_button_released(mb_left)) {
    global.addresses_dirty = true;
}

/////////////////////////////////////////////////////////////////
// E2. TAB INDENT
/////////////////////////////////////////////////////////////////
if (keyboard_check_pressed(vk_tab) && !obj_workspace_manager.is_entering_text
    && !obj_workspace_manager.code_editor_open
    && array_length(global.selected_nodes) == 0) {
    if (point_in_rectangle(mouse_x, mouse_y, x + x_indent, y, x + x_indent + width, y + height)) {
        if (keyboard_check(vk_shift)) {
          
            x_indent = clamp(x_indent - 40, -120, 120);
        } else {
           
            if x_indent<120 x_indent += 40;
        }
    }
}

/////////////////////////////////////////////////////////////////
// F. AUTO-INJECT EXIT LABEL BELOW MACRO_SID
// Gated: the three cross-node scans below are expensive (O(nodes) each,
// running once per node = O(nodes^2) per frame). They only need to react
// to user clicks, or to nodes that already have exit-label bookkeeping.
// Idle frames skip the entire section.
/////////////////////////////////////////////////////////////////
var _f_click_frame = (mouse_check_button_pressed(mb_left) || mouse_check_button_released(mb_left));
var _f_needs_run   = _f_click_frame
                  || (node_type == "MACRO_SID")
                  || (node_type == "LABEL" && array_length(instructions) > 0
                        && array_length(instructions[0]) > 1
                        && string(instructions[0][1]) == "sid_exit");

if (_f_needs_run) {

var _has_irq_handler = false;
with (obj_c64_node) {
     if (node_type == "MACRO_IRQ_HANDLER" && org_parent == noone && is_connected) {
        _has_irq_handler = true; break;
    }
}

if (_has_irq_handler && exit_spawned) {
    var _self_ref = id;
    with (obj_c64_node) {
        if (node_type == "LABEL" && is_connected && org_parent == noone &&
            array_length(instructions) > 0 && array_length(instructions[0]) > 1 &&
            string(instructions[0][1]) == "sid_exit") {
            var _target_y = _self_ref.y + _self_ref.height;
            if (y != _target_y) {
                var _old_y  = y;
                var _lbl_id = id;
                // Push nodes that are at the target position down to make room
                with (obj_c64_node) {
                    if (id != _lbl_id && id != _self_ref && is_connected &&
                        org_parent == noone && y >= _target_y && y < _old_y) {
                        y += _lbl_id.height;
                    }
                }
                y = _target_y;
                scr_c64_update_addresses();
            }
        }
    }
}


if (node_type == "MACRO_SID" && is_connected && !exit_spawned && org_parent == noone) {

    var _next_y    = 999999;
    var _next_node = noone;
    var _self_ref  = id;

    with (obj_c64_node) {
        if (id != _self_ref && is_connected && org_parent == noone &&
            y > _self_ref.y && y < _next_y) {
            _next_y    = y;
            _next_node = id;
        }
    }

    var _sid_exit_exists = false;
    with (obj_c64_node) {
        if (is_connected && org_parent == noone &&
            node_type == "LABEL" &&
            array_length(instructions) > 0 &&
            array_length(instructions[0]) > 1 &&
            string(instructions[0][1]) == "sid_exit") {
            _sid_exit_exists = true;
            break;
        }
    }
    if (!_sid_exit_exists) {
      
        exit_spawned = true;

        var _nl          = instance_create_layer(x, y + height, "Layer_Nodes", obj_c64_node);
        _nl.node_title   = "ADDRESS LABEL";
        _nl.node_type    = "LABEL";
        _nl.instructions = [["label", "sid_exit"]];
        _nl.pc_address   = global.start_pc;
        _nl.is_connected = true;
        with (_nl) { event_user(0); }

       

var _label_ref  = _nl;
		var _label_push = 60; // LABEL fixed height = _G * 3
        var _push_y     = _self_ref.y + _self_ref.height; // push from MACRO_SID bottom
       
        with (obj_c64_node) {
            if (id != _self_ref && id != _label_ref && is_connected &&
                org_parent == noone && y >= _push_y) {
               
                y += _label_push;
            }
        }
        scr_c64_update_addresses();
    } else {
       
        exit_spawned = true;
    }
}

} // end Section F gate (_f_needs_run)
