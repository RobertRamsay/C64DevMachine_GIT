function scr_c64_update_addresses() {
    // Step consumes this flag for spine traversal. Alarm 1 independently owns
    // the expensive sizing pass, so clearing the traversal flag cannot lose it.
    global.addresses_dirty = true;
    var _refresh_active = variable_global_exists("c64_address_refresh_active")
                       && global.c64_address_refresh_active;
    if (!_refresh_active && instance_exists(obj_workspace_manager)) {
        // Leave one complete Step for every node's drop/reconnect handler and
        // the workspace traversal before compiling the settled graph.
        obj_workspace_manager.alarm[1] = 2;
    }
}