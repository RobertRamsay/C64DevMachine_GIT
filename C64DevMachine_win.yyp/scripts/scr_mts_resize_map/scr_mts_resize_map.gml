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


/// @desc RAW ROWS size: every real map flattened to chars, maps back to back.
/// @param {struct} _m  the META_TILESET meta
function scr_mts_raw_rows_size(_m) {
    var _total = 0;
    for (var _mi = 0; _mi < array_length(_m.maps); _mi++) {
        var _cols = 1;
        if (_mi < array_length(_m.map_w)) {
            _cols = max(1, floor(_m.map_w[_mi] / _m.stamp_w));
        }
        var _rows = floor(array_length(_m.maps[_mi]) / _cols);
        _total += _cols * _m.stamp_w * _rows * _m.stamp_h;
    }
    return _total;
}

/// @desc RAW ROWS export (PASS 3). Emits every real map of the tileset as plain
///       char rows: map_w bytes a row, top row first, maps one after another
///       from wherever the caller's org left the PC. Each map gets a label,
///       <NAME>_MAP<n>. An empty cell (-1) or a stamp past stamp_count is char 0.
///       Same flattening as MACRO_METASCROLL, chars only - colour comes from the
///       engine (char_lut is only used by the editor here).
/// @param {array}  _list  instruction list
/// @param {struct} _a     the META_TILESET asset
function scr_mts_raw_rows_emit(_list, _a) {
    var _m     = _a.meta;
    var _sw    = _m.stamp_w;
    var _sh    = _m.stamp_h;
    var _cells = _sw * _sh;
    for (var _mi = 0; _mi < array_length(_m.maps); _mi++) {
        array_push(_list, ["label", _a.name + "_MAP" + string(_mi)]);
        var _grid = _m.maps[_mi];
        var _cols = 1;
        if (_mi < array_length(_m.map_w)) {
            _cols = max(1, floor(_m.map_w[_mi] / _sw));
        }
        var _rows = floor(array_length(_grid) / _cols);
        for (var _gy = 0; _gy < _rows; _gy++) {
            for (var _cy = 0; _cy < _sh; _cy++) {
                for (var _gx = 0; _gx < _cols; _gx++) {
                    var _mt = _grid[_gy * _cols + _gx];
                    for (var _cx = 0; _cx < _sw; _cx++) {
                        var _ch = 0;
                        if (_mt >= 0 && _mt < _m.stamp_count) {
                            var _db = _mt * _cells + _cy * _sw + _cx;
                            if (_db < array_length(_m.stamp_data)) {
                                _ch = _m.stamp_data[_db];
                            }
                        }
                        array_push(_list, ["byte", _ch & 0xFF]);
                    }
                }
            }
        }
    }
}
