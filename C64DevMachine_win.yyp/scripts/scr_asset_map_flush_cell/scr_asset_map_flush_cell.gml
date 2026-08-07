/// @desc Fast O(1) buffer update for one painted cell.
/// scr_asset_map_flush() re-serializes the ENTIRE map (three full passes,
/// one buffer_poke per cell per pass) — correct after a resize/undo/load,
/// but wildly wasteful when called every single frame during a paint drag,
/// which is what made large-map painting laggy. This updates only the one
/// cell that actually changed. Falls back to the full flush if the buffer
/// doesn't exist yet or is the wrong size (resize/undo edge cases) or the
/// cell is out of range, so it's always safe to call.
function scr_asset_map_flush_cell(_asset, _row, _col) {
    if (!variable_struct_exists(_asset, "meta")) exit;
    var _m  = _asset.meta;
    var _mw = _m.map_w;
    var _mh = _m.map_h;
    var _sz = _mw * _mh;
    var _buf_sz = _sz * 3;

    if (!buffer_exists(_asset.buffer) || buffer_get_size(_asset.buffer) != _buf_sz
    ||  _row < 0 || _row >= _mh || _col < 0 || _col >= _mw
    ||  !variable_struct_exists(_m, "char_grid") || !variable_struct_exists(_m, "colour_grid")
    ||  !variable_struct_exists(_m, "override_grid")) {
        scr_asset_map_flush(_asset);
        return;
    }

    var _gw  = variable_struct_exists(_m, "grid_w") ? _m.grid_w : _mw;
    var _src = _row * _gw + _col;
    var _dst = _row * _mw + _col;
    if (_src < 0 || _src >= array_length(_m.char_grid)
    ||  _src >= array_length(_m.colour_grid) || _src >= array_length(_m.override_grid)) {
        scr_asset_map_flush(_asset);
        return;
    }

    buffer_poke(_asset.buffer, _dst, buffer_u8, _m.char_grid[_src]);

    // Same colour-byte composition as scr_asset_map_flush — keep in sync if that changes.
    var _global_mixed = obj_workspace_manager.map_global_mixed;
    var _ov    = _m.override_grid[_src]; // 0=HR, 1=MC
    var _byte  = 0;
    if (_global_mixed == 1) {
        var _col_val = _m.colour_grid[_src] & 0x07;
        _byte = (_ov == 1) ? (_col_val | 0x08) : _col_val;
    } else {
        _byte = _m.colour_grid[_src] & 0x0F;
    }
    buffer_poke(_asset.buffer, _sz     + _dst, buffer_u8, _byte);
    buffer_poke(_asset.buffer, _sz * 2 + _dst, buffer_u8, _ov);
}
