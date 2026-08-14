/// @function scr_code_editor_close(_commit)
/// @description Closes the code editor. Always commits (no cancel concept).
function scr_code_editor_close(_commit) {
    with (obj_workspace_manager) {
        if (_commit && instance_exists(code_editor_node)) {
            code_editor_node.instructions[0][1] = code_editor_text;
            code_editor_node.height_dirty = true;
            global.undo_dirty        = true;
            global.node_change_dirty = true;
            global.addresses_dirty   = true;
            scr_c64_do_update_addresses();
            with (obj_c64_node) { 
                last_overlap_check = false; 
                overlap_check_dirty = true; 
                stats_cache_dirty = true;
                if (node_type == "MACRO_CODE") code_cache_dirty = true;
            }
        }
        // Per-node undo/redo — save this session's history onto the node
        // itself before we lose the reference, so navigating away and
        // back within the same session doesn't wipe it. Only cleared by
        // an actual reload/reopen of the file, never just by closing the
        // editor modal.
        if (instance_exists(code_editor_node)) {
            code_editor_node.undo_stack = code_editor_undo_stack;
            code_editor_node.redo_stack = code_editor_redo_stack;
        }
        code_editor_open        = false;
    code_editor_max_line_px = 0;
    if (ds_exists(code_editor_local_labels,  ds_type_map)) ds_map_destroy(code_editor_local_labels);
    if (ds_exists(code_editor_local_consts,  ds_type_map)) ds_map_destroy(code_editor_local_consts);
    if (ds_exists(code_editor_global_labels, ds_type_map)) ds_map_destroy(code_editor_global_labels);
    code_editor_local_labels  = ds_map_create();
    code_editor_local_consts  = ds_map_create();
    code_editor_global_labels = ds_map_create();
        code_editor_node      = noone;
        code_editor_sel_start = -1;
        code_editor_sel_end   = -1;
        keyboard_string       = "";
    }
}