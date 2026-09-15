/// @function scr_hud_flush(_asset)
/// @desc Serialises a HUD asset's two grids into its buffer: hud_w * hud_h
///       char bytes followed by the same count of colour bytes.
///
/// The compile chain reads the GRIDS, not the buffer — but the buffer is what
/// the workspace saver blobs out and what the asset list sizes itself from, so
/// it has to stay in step with every edit. Call this after any change to
/// char_grid, colour_grid or the rect.
function scr_hud_flush(_asset) {
    if (!variable_struct_exists(_asset, "meta")) exit;

    var _m  = _asset.meta;
    var _sz = _m.hud_w * _m.hud_h;
    if (_sz <= 0) exit;

    // A resize leaves the grids the wrong length — pad with space/white rather
    // than writing past the end of them.
    if (array_length(_m.char_grid) != _sz) {
        var _old_c = _m.char_grid;
        _m.char_grid = array_create(_sz, 32);
        var _n_c = min(array_length(_old_c), _sz);
        for (var _i = 0; _i < _n_c; _i++) {
            _m.char_grid[_i] = _old_c[_i];
        }
    }
    if (array_length(_m.colour_grid) != _sz) {
        var _old_k = _m.colour_grid;
        _m.colour_grid = array_create(_sz, 1);
        var _n_k = min(array_length(_old_k), _sz);
        for (var _i = 0; _i < _n_k; _i++) {
            _m.colour_grid[_i] = _old_k[_i];
        }
    }

    if (buffer_exists(_asset.buffer) && buffer_get_size(_asset.buffer) != _sz * 2) {
        buffer_delete(_asset.buffer);
        _asset.buffer = -1;
    }
    if (!buffer_exists(_asset.buffer)) {
        _asset.buffer = buffer_create(_sz * 2, buffer_fixed, 1);
    }

    for (var _i = 0; _i < _sz; _i++) {
        buffer_poke(_asset.buffer, _i,       buffer_u8, _m.char_grid[_i]   & 0xFF);
        buffer_poke(_asset.buffer, _sz + _i, buffer_u8, _m.colour_grid[_i] & 0x0F);
    }
}
