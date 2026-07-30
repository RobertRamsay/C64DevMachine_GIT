/// =============================================================
/// scr_nloc_find_meta(name)
/// Returns the metadata struct for a named location, or undefined.
/// O(1) via global.named_loc_meta_map, rebuilt on demand.
/// =============================================================
function scr_nloc_find_meta(_name) {
    if (!variable_global_exists("named_loc_meta_map")
        || global.named_loc_meta_map == -1
        || global.named_loc_meta_dirty) {
        scr_nloc_rebuild_meta_map();
    }
    var _key = string_upper(_name);
    if (ds_map_exists(global.named_loc_meta_map, _key)) {
        return global.named_loc_meta_map[? _key];
    }
    return undefined;
}

