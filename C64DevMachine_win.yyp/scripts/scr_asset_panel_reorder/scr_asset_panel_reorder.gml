/// @function scr_asset_panel_reorder(_drag_idx, _target_idx, _after)
/// @desc Asset panel drag-and-drop between rows. Moves asset _drag_idx to sit
///       just before (or, with _after, just after) asset _target_idx, joins
///       the target's group, and switches the panel to the OWN sort so the
///       hand-made order is what shows. The order starts from whatever the
///       panel showed (NAME / TYPE / ADDR / OWN), so nothing else jumps.
///       Only the panel order changes: asset_list indices, addresses and the
///       build are untouched.
function scr_asset_panel_reorder(_drag_idx, _target_idx, _after) {
    with (obj_asset_manager) {
        if (_drag_idx == _target_idx) return;
        var _seq = scr_asset_sorted_indices();
        var _from = -1;
        for (var _i = 0; _i < array_length(_seq); _i++) {
            if (_seq[_i] == _drag_idx) { _from = _i; break; }
        }
        if (_from < 0) return;
        array_delete(_seq, _from, 1);
        var _to = -1;
        for (var _j = 0; _j < array_length(_seq); _j++) {
            if (_seq[_j] == _target_idx) { _to = _j; break; }
        }
        if (_to < 0) return;
        if (_after) _to += 1;
        array_insert(_seq, _to, _drag_idx);
        for (var _k = 0; _k < array_length(_seq); _k++) {
            ds_list_find_value(asset_list, _seq[_k]).order = _k;
        }
        var _moved  = ds_list_find_value(asset_list, _drag_idx);
        var _target = ds_list_find_value(asset_list, _target_idx);
        _moved.group = variable_struct_exists(_target, "group") ? _target.group : "";
        asset_sort_mode       = "OWN";
        global.undo_dirty     = true;
        global.autosave_dirty = true;
    }
}
