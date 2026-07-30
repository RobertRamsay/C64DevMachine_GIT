/// @desc ()
// Per-frame sid_exit repositioning — runs every step, not just on click
function scr_node_step_macro_sid_frame() {
    // Self-destruct sid_exit if no connected MACRO_SID on spine
    var _has_connected_sid = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected && org_parent == noone)
            { _has_connected_sid = true; break; }
    }
    if (!_has_connected_sid) {
        with (obj_c64_node) {
            if (node_type == "LABEL" && is_connected && org_parent == noone &&
                array_length(instructions) > 0 && array_length(instructions[0]) > 1 &&
                string(instructions[0][1]) == "sid_exit") {
                instance_destroy();
            }
        }
        exit;
    }

	var _has_irq_handler = false;
	with (obj_c64_node) {
	    if (node_type == "MACRO_IRQ_HANDLER" && org_parent == noone && is_connected) {
	        _has_irq_handler = true; break;
	    }
	}

	if (!_has_irq_handler && !is_dragging) {
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
	   var _anchor_node = _lowest_irq;
	    if (_anchor_node == noone) {
	        with (obj_c64_node) {
	            if (is_connected && org_parent == noone && node_type == "MACRO_SID") {
	                _anchor_node = id;
	                break;
	            }
	        }
	    }
	    if (_exit_node != noone && _anchor_node != noone) {
	        var _new_y = _anchor_node.y + _anchor_node.height;
	        if (_exit_node.y != _new_y) {
	            _exit_node.y = _new_y;
	            _exit_node.is_auto_adjusting = true;
	            scr_c64_update_addresses();
	        }
	    }
	}
}