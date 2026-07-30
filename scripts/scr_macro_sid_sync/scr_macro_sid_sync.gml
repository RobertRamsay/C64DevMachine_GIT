function scr_macro_sid_sync(_node_id) {
    if (!instance_exists(_node_id)) exit;
    if (!_node_id.is_expanded) exit;

    var _volume = is_real(_node_id.instructions[0][3]) ? clamp(real(_node_id.instructions[0][3]), 0, 15) : 12;
    var _track  = is_real(_node_id.instructions[0][2]) ? clamp(real(_node_id.instructions[0][2]), 0, 31) : 0;

    // Walk all child nodes that belong to this macro
    with(obj_c64_node) {
        if ((macro_owner == noone)) continue;
        if (macro_owner != _node_id) continue;  // ← compare to _node_id, not _node_id.macro_owner

        var _inst = string_lower(instructions[0][0]);
        var _val  = instructions[0][1];

        // LDA #volume is the node whose immediate next sibling stores to $D418
        if (_inst == "lda_imm" && is_real(_val)) {
            // Find the next node below this one that also belongs to this macro
            var _next    = noone;
            var _best_y  = 999999;
            var _self_y  = y;
            with(obj_c64_node) {
                if (variable_instance_exists(id, "macro_owner") &&
                    macro_owner == _node_id &&
                    y > _self_y && y < _best_y) {
                    _best_y = y;
                    _next   = id;
                }
            }
            if (instance_exists(_next)) {
                var _next_inst = string_lower(_next.instructions[0][0]);
                var _next_val  = _next.instructions[0][1];
                if (_next_inst == "sta_abs" && _next_val == 0xD418) {
                    instructions[0][1] = _volume;
                }
                if (_next_inst == "jsr") {
                    instructions[0][1] = _track;
                }
            }
        }
    }

    scr_c64_update_addresses();
}