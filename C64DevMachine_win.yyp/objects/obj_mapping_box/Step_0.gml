/// @desc Mapping Box - Resize, Drag, Delete, Double-click Edit
var _cam_x    = obj_workspace_manager.cam_x;
var _cam_y    = obj_workspace_manager.cam_y;
var _cam_zoom = obj_workspace_manager.cam_zoom;
var _gmx      = global.gui_mouse_x;
var _gmy      = global.gui_mouse_y;

// Convert box corners to GUI screen space
var _sx1 = (x         - _cam_x) / _cam_zoom;
var _sy1 = (y         - _cam_y) / _cam_zoom;
var _sx2 = (x + box_w - _cam_x) / _cam_zoom;
var _sy2 = (y + box_h - _cam_y) / _cam_zoom;

/////////////////////////////////////////////////////////////////
// RESIZE HANDLE (bottom right)
/////////////////////////////////////////////////////////////////
var _rh_x1  = _sx2 - 16;
var _rh_y1  = _sy2 - 16;
var _rh_hov = (_gmx >= _rh_x1 && _gmx <= _sx2 &&
               _gmy >= _rh_y1 && _gmy <= _sy2);

if (_rh_hov && mouse_check_button_pressed(mb_left) && !is_resizing && !is_dragging) {
    is_resizing = true;
    resize_ox   = mouse_x;
    resize_oy   = mouse_y;
    resize_ow   = box_w;
    resize_oh   = box_h;
}
if (is_resizing) {
    box_w = max(80, resize_ow + (mouse_x - resize_ox));
    box_h = max(40, resize_oh + (mouse_y - resize_oy));
    if (mouse_check_button_released(mb_left)) {
        box_w       = round(box_w / 20) * 20;
        box_h       = round(box_h / 20) * 20;
        is_resizing = false;
		global.undo_dirty  = true;
    }
}

/////////////////////////////////////////////////////////////////
// DELETE BUTTON (top right corner, above box)
/////////////////////////////////////////////////////////////////
var _del_x1  = _sx2 - 18;
var _del_y1  = _sy1 - 18;
var _del_x2  = _sx2;
var _del_y2  = _sy1;
var _del_hov = (_gmx >= _del_x1 && _gmx <= _del_x2 &&
                _gmy >= _del_y1 && _gmy <= _del_y2);

if (_del_hov && mouse_check_button_pressed(mb_left) && !is_resizing && !is_dragging) {
	global.undo_dirty = true;
    instance_destroy();
    exit;
}

/////////////////////////////////////////////////////////////////
// TAB LABEL - DRAG + DOUBLE-CLICK EDIT
/////////////////////////////////////////////////////////////////
var _tw      = max(60, string_length(box_name) * 9 + 20);
var _tab_x1  = _sx1;
var _tab_y1  = _sy1 - 18;
var _tab_x2  = _sx1 + _tw;
var _tab_y2  = _sy1;
var _tab_hov = (_gmx >= _tab_x1 && _gmx <= _tab_x2 &&
                _gmy >= _tab_y1 && _gmy <= _tab_y2);

if (_tab_hov && mouse_check_button_pressed(mb_left) && !is_resizing) {
    if (dbl_click_timer > 0) {
        // Double-click → open edit popup
        with (obj_workspace_manager) {
            box_popup_open      = true;
            box_popup_target    = other.id;
            box_popup_name      = other.box_name;
            box_popup_col_idx   = other.box_col_idx;
            box_popup_is_edit   = true;
            box_popup_name_dupe = false;
            box_dropdown_open   = false;
            box_popup_ready     = false;
        }
        dbl_click_timer = 0;
    } else {
        dbl_click_timer = 20;
        // Begin drag
        is_dragging  = true;
        drag_ox      = mouse_x;
        drag_oy      = mouse_y;
        drag_start_x = x;
        drag_start_y = y;

        // Collect ORG parents inside this box and arm their own drag system
// Collect ORG parents inside this box and arm their own drag system
        drag_nodes   = [];
        drag_offsets = [];
        // Collect floating nodes (comments, labels, normal nodes etc)
        drag_floats   = [];
        drag_float_ox = [];
        drag_float_oy = [];
        with (obj_c64_node) {
            var _nx = x + (width  * 0.5);
            var _ny = y + (height * 0.5);
            var _inside = (_nx >= other.x && _nx <= other.x + other.box_w &&
                           _ny >= other.y && _ny <= other.y + other.box_h);
            if (!_inside) continue;

            if (node_type == "ORG" && org_parent == noone) {
                // ORG parent — arm its own drag to carry children
                array_push(other.drag_nodes,   id);
                array_push(other.drag_offsets, [x - other.x, y - other.y]);
                is_dragging   = true;
                depth         = -2000;
                drag_offset_x = x - mouse_x;
                drag_offset_y = y - mouse_y;
            } else if (node_type != "INIT" &&
                       node_type != "EXECUTE" &&
                       org_parent == noone &&
                       !is_connected) {
                // Floating node — teleport directly
                array_push(other.drag_floats,   id);
                array_push(other.drag_float_ox, x - other.x);
                array_push(other.drag_float_oy, y - other.y);
            }
        }
    }
}
if (dbl_click_timer > 0) dbl_click_timer--;

/////////////////////////////////////////////////////////////////
// ACTIVE DRAG
/////////////////////////////////////////////////////////////////
if (is_dragging) {
    var _dx = mouse_x - drag_ox;
    var _dy = mouse_y - drag_oy;
    x = drag_start_x + _dx;
    y = drag_start_y + _dy;

    // Move floating nodes directly
    for (var _i = 0; _i < array_length(drag_floats); _i++) {
        var _n = drag_floats[_i];
        if (!instance_exists(_n)) continue;
        _n.x = x + drag_float_ox[_i];
        _n.y = y + drag_float_oy[_i];
    }

if (mouse_check_button_released(mb_left)) {
        is_dragging  = false;
        // Snap box position to 20px grid
        x = round(x / 20) * 20;
        y = round(y / 20) * 20;
        drag_nodes   = [];
        drag_offsets = [];
        drag_floats   = [];
        drag_float_ox = [];
        drag_float_oy = [];
		//global.undo_dirty  = true;
        with (obj_workspace_manager) {
            global.addresses_dirty = true;
            scr_c64_update_addresses();
        }
    }
}