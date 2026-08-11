/// @desc Resize ALL maps in a META_TILESET (they share one W/H), reflowing
///       placements. Grow = blank (-1) cells; shrink = drop metatiles outside
///       the new bounds. Dimensions are CHAR cells; snap DOWN to whole metatiles.
/// @param {struct} _m         the tileset meta
/// @param {real}   _map_idx   ignored (kept for call-site compatibility)
/// @param {real}   _new_w_ch  new width  in char cells
/// @param {real}   _new_h_ch  new height in char cells
function scr_mts_resize_map(_m, _map_idx, _new_w_ch, _new_h_ch) {
    if (array_length(_m.maps) == 0) {
        return;
    }

    // Snap requested char dims DOWN to whole metatiles, then back to char cells.
    var _new_cols = max(1, floor(_new_w_ch / _m.stamp_w));
    var _new_rows = max(1, floor(_new_h_ch / _m.stamp_h));
    var _new_w    = _new_cols * _m.stamp_w;
    var _new_h    = _new_rows * _m.stamp_h;

    for (var _mi = 0; _mi < array_length(_m.maps); _mi++) {
        // Old grid dims in metatiles (per map, but they should all match).
        var _old_cols = floor(_m.map_w[_mi] / _m.stamp_w);
        var _old_rows = floor(_m.map_h[_mi] / _m.stamp_h);

        var _old_grid = _m.maps[_mi];
        var _new_grid = array_create(_new_cols * _new_rows, -1);

        // Copy overlapping metatile cells (top-left anchored).
        var _copy_cols = min(_old_cols, _new_cols);
        var _copy_rows = min(_old_rows, _new_rows);
        for (var _r = 0; _r < _copy_rows; _r++) {
            for (var _c = 0; _c < _copy_cols; _c++) {
                var _old_idx = _r * _old_cols + _c;
                if (_old_idx < array_length(_old_grid)) {
                    _new_grid[_r * _new_cols + _c] = _old_grid[_old_idx];
                }
            }
        }

        _m.maps[_mi]  = _new_grid;
        _m.map_w[_mi] = _new_w;
        _m.map_h[_mi] = _new_h;
    }

    _m.is_dirty = true;
    global.memory_bar_dirty = true;
}
