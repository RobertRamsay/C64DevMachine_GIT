function scr_node_step_macro_sid(_draw_x) {
    var _header_h = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;



    // Row 1: Asset name field — open picker
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _fy, _draw_x + width - 8, _fy + 16)) {
        if (instance_exists(obj_asset_manager)) {
            var _node_id = id;
            with (obj_asset_manager) {
                sid_picker_open = true;
                sid_picker_node = _node_id;
            }
        }
        exit;
    }
    _fy += _line_h; // sid addr - read only
    _fy += _line_h; // track - editable
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 70, _fy, _draw_x + width - 8, _fy + 16)) {
        with (obj_workspace_manager) {
            is_entering_text = true; input_target_node = other.id; input_target_index = 2;
            current_input_string = string(other.instructions[0][2]);
            keyboard_string = ""; cursor_pos = string_length(current_input_string);
        }
        exit;
    }
_fy += _line_h; // irq line - editable
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 90, _fy, _draw_x + width - 8, _fy + 16)) {
        with (obj_workspace_manager) {
            is_entering_text = true; input_target_node = other.id; input_target_index = 4;
            while (array_length(other.instructions[0]) <= 4) array_push(other.instructions[0], 0);
            other.instructions[0][4] = 96;
            current_input_string = string(other.instructions[0][4]);
            keyboard_string = ""; cursor_pos = string_length(current_input_string);
        }
        exit;
    }
	
// Enforce sid_exit stays below all MACRO_IRQs (skip if IRQ_HANDLER is managing things)
    var _has_irq_handler = false;
    with (obj_c64_node) {
         if (node_type == "MACRO_IRQ_HANDLER" && org_parent == noone && is_connected) {
            _has_irq_handler = true; break;
        }
    }
    if (is_connected && org_parent == noone && !_has_irq_handler) {
        var _exit_node = noone;
        var _lowest_irq = noone;
        var _lowest_irq_y = -1;
        with (obj_c64_node) {
            if (is_connected && org_parent == noone) {
                if (node_type == "LABEL" && array_length(instructions) > 0 && array_length(instructions[0]) > 1 && string(instructions[0][1]) == "sid_exit") {
                    _exit_node = id;
                }
                if (node_type == "MACRO_IRQ") {
                    if (y > _lowest_irq_y) {
                        _lowest_irq_y = y;
                        _lowest_irq = id;
                    }
                }
            }
        }
		
		
        if (_exit_node != noone && _lowest_irq != noone) {
            var _new_y = _lowest_irq.y + _lowest_irq.height;
            if (_exit_node.y != _new_y) {
                var _old_y  = _exit_node.y;
                var _lbl_id = _exit_node;
                with (obj_c64_node) {
                    if (id != _lbl_id && is_connected && org_parent == noone &&
                        y >= _new_y && y < _old_y) {
                        y += _lbl_id.height;
                    }
                }
                _exit_node.y = _new_y;
                _exit_node.is_auto_adjusting = true;
                scr_c64_update_addresses();
            }
        }
    }
	
	
}