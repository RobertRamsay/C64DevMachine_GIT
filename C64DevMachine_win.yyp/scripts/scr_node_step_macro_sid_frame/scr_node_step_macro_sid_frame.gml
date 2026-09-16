/// @desc Settle the sid_exit label at _target_y, but only when it is above it.
/// @param {real} _target_y  the highest Y sid_exit is allowed to sit at
/// @return {bool} true when the label was moved
//
// Every repositioner in the project used to write sid_exit's Y unconditionally,
// every frame. A node whose height was recalculated, or a MACRO_IRQ dragged
// anywhere, moved the label with it — and because none of them checked what was
// already parked at the destination, it regularly landed on top of another
// spine node. Two nodes on the same Y is the one arrangement _walk_spine cannot
// survive: it picks the next node by smallest Y strictly greater than the
// current one, so one of the pair is silently dropped from the build.
//
// The rule here is the weakest one that still holds the constraint: sid_exit
// has to be BELOW the macro that jumps to it. If it already is, it is left
// exactly where the user put it. If it is not, it moves down to _target_y and
// anything sitting in that slot is pushed clear first.
function scr_sid_exit_settle(_target_y) {
    var _exit_node = noone;
    with (obj_c64_node) {
        if (node_type == "LABEL" && is_connected && org_parent == noone &&
            array_length(instructions) > 0 && array_length(instructions[0]) > 1 &&
            string(instructions[0][1]) == "sid_exit") {
            _exit_node = id;
            break;
        }
    }
    if (_exit_node == noone) return false;
    if (_exit_node.y >= _target_y) return false;   // already legal — hands off

    var _lbl_id = _exit_node;
    var _lbl_h  = max(20, _exit_node.height);

    // Only disturb the workspace if the slot is actually taken.
    var _clash = false;
    with (obj_c64_node) {
        if (id != _lbl_id && is_connected && org_parent == noone &&
            y >= _target_y && y < _target_y + _lbl_h) {
            _clash = true;
        }
    }
    if (_clash) {
        with (obj_c64_node) {
            if (id != _lbl_id && is_connected && org_parent == noone && y >= _target_y) {
                y += _lbl_h;
            }
        }
    }

    _exit_node.y = _target_y;
    _exit_node.is_auto_adjusting = true;
    scr_c64_update_addresses();
    return true;
}

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
	    // Directly below this node, and that is the whole rule — the same one
	    // the IRQ_HANDLER branch uses, so MACRO_SID behaves identically either
	    // way. It used to be forced below every MACRO_IRQ as well, which made
	    // the label unplaceable whenever the SID node came first on the spine.
	    // It does not need to be: MACRO_IRQ wraps its own handler body in
	    // JSR init / JMP skip ... skip:, so it jumps over itself. The only run
	    // sid_exit has to clear is the one MACRO_SID emits inline after the
	    // JMP - sid_irq and sid_init_entry - and that ends at this node.
	    scr_sid_exit_settle(y + height);
	}
}