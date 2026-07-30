/// @desc Sync MACRO_MAP node — looks up MAP_DATA asset and sets node size
/// @param {Id.Instance} _node
function scr_macro_map_sync(_node) {
    var _asset_name = string(_node.instructions[0][1]);
    var _map_w      = 40;
    var _map_h      = 25;

    if (instance_exists(obj_asset_manager)) {
        with (obj_asset_manager) {
            for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
                var _a = ds_list_find_value(asset_list, _i);
                if (_a.type == "MAP_DATA" && _a.name == _asset_name) {
                    if (variable_struct_exists(_a.meta, "map_w")) _map_w = _a.meta.map_w;
                    if (variable_struct_exists(_a.meta, "map_h")) _map_h = _a.meta.map_h;
                    break;
                }
            }
        }
    }

    // Byte cost: copy char_grid to $0400 + copy colour_grid to $D800
    // Each copy loop: ~10 bytes overhead + map_w*map_h iterations
    // Simplified flat copy using page loop pattern
    // Actual instruction rebuild happens in scr_compile_chain MACRO_MAP case
    _node.instructions[0][2] = _map_w;
    _node.instructions[0][3] = _map_h;

    show_debug_message("MACRO_MAP sync: " + _asset_name
        + " " + string(_map_w) + "x" + string(_map_h));

    global.addresses_dirty = true;
    scr_c64_update_addresses();
}
