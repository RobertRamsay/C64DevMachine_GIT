/// =============================================================
/// scr_nloc_rebuild_meta_map()
/// Rebuilds the name -> meta struct lookup map from the array.
/// Call (or set global.named_loc_meta_dirty = true) whenever
/// global.named_loc_meta changes.
/// =============================================================
function scr_nloc_rebuild_meta_map() {
    if (!variable_global_exists("named_loc_meta_map") || global.named_loc_meta_map == -1) {
        global.named_loc_meta_map = ds_map_create();
    }
    ds_map_clear(global.named_loc_meta_map);
    for (var _i = 0; _i < array_length(global.named_loc_meta); _i++) {
        global.named_loc_meta_map[? string_upper(global.named_loc_meta[_i].name)] = global.named_loc_meta[_i];
    }
    global.named_loc_meta_dirty = false;
}