/// @desc Sync MAP_DATA buffer — writes map_w x map_h from physical grid_w x grid_h storage
function scr_asset_map_flush(_asset) {
    if (!variable_struct_exists(_asset, "meta")) exit;
    var _m    = _asset.meta;
	var _mw   = _m.map_w;
    var _mh   = _m.map_h;
    // Backfill physical grid dims. CRITICAL: infer stride from the stored array
    // length, never from map_w/map_h — map_w/map_h are the logical window and may
    // already be shrunk, which would pin the stride wrong and scramble lower rows.
    if (!variable_struct_exists(_m, "grid_w") || !variable_struct_exists(_m, "grid_h")) {
        var _known_len = 0;
        if (variable_struct_exists(_m, "char_grid")) {
            _known_len = array_length(_m.char_grid);
        } else if (variable_struct_exists(_m, "colour_grid")) {
            _known_len = array_length(_m.colour_grid);
        } else if (variable_struct_exists(_m, "override_grid")) {
            _known_len = array_length(_m.override_grid);
        }
        if (_known_len > 0 && _mh > 0 && (_known_len mod _mh) == 0) {
            _m.grid_w = _known_len div _mh;
            _m.grid_h = _mh;
        } else {
            _m.grid_w = _mw;
            _m.grid_h = _mh;
        }
    }
    var _gw   = _m.grid_w;
var _sz     = _mw * _mh;
    var _buf_sz = _sz * 3; // char + colour + override
    if (!buffer_exists(_asset.buffer) || buffer_get_size(_asset.buffer) != _buf_sz) {
        if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
        _asset.buffer = buffer_create(_buf_sz, buffer_fixed, 1);
    }
// Backfill override_grid if missing or wrong size (must match physical grid)
    var _phys_sz = _gw * _m.grid_h;
    if (!variable_struct_exists(_m, "override_grid") ||
        array_length(_m.override_grid) != _phys_sz) {
        var _old_ov  = variable_struct_exists(_m, "override_grid") ? _m.override_grid : [];
        var _old_len = array_length(_old_ov);
        _m.override_grid = array_create(_phys_sz, 0);
        for (var _oi = 0; _oi < min(_old_len, _phys_sz); _oi++)
            _m.override_grid[_oi] = _old_ov[_oi];
    }
    // Char grid
    // Backfill char_grid if missing or wrong size
    if (!variable_struct_exists(_m, "char_grid") ||
        array_length(_m.char_grid) != _phys_sz) {
        var _old_cg  = variable_struct_exists(_m, "char_grid") ? _m.char_grid : [];
        var _old_len = array_length(_old_cg);
        _m.char_grid = array_create(_phys_sz, 0);
        for (var _oi = 0; _oi < min(_old_len, _phys_sz); _oi++)
            _m.char_grid[_oi] = _old_cg[_oi];
    }
    // Backfill colour_grid if missing or wrong size
    if (!variable_struct_exists(_m, "colour_grid") ||
        array_length(_m.colour_grid) != _phys_sz) {
        var _old_colg = variable_struct_exists(_m, "colour_grid") ? _m.colour_grid : [];
        var _old_len  = array_length(_old_colg);
        _m.colour_grid = array_create(_phys_sz, 1);
        for (var _oi = 0; _oi < min(_old_len, _phys_sz); _oi++)
            _m.colour_grid[_oi] = _old_colg[_oi];
    }

    // Char grid
    for (var _row = 0; _row < _mh; _row++) {
        for (var _col = 0; _col < _mw; _col++) {
            var _src = _row * _gw + _col;
            var _dst = _row * _mw + _col;
            buffer_poke(_asset.buffer, _dst, buffer_u8, _m.char_grid[_src]);
        }
    }
// Colour grid — compose final colour RAM byte:
    // MIXED mode:  bits 0-2 = colour (3-bit), bit 3 = MC flag per cell override_grid
    // HR16 mode:   bits 0-3 = full colour nibble, bit 3 NOT used as MC flag
    var _global_mixed = obj_workspace_manager.map_global_mixed;
    for (var _row = 0; _row < _mh; _row++) {
        for (var _col = 0; _col < _mw; _col++) {
            var _src  = _row * _gw + _col;
            var _dst  = _sz + _row * _mw + _col;
            var _ov   = _m.override_grid[_src]; // 0=HR, 1=MC
            var _byte = 0;
if (_global_mixed == 1) {
                // Mixed mode: low 3 bits = colour, bit 3 = MC flag
                // MC cell: colour | $08 so C64 reads bit3=1 → multicolor
                // HR cell: colour & $07 so C64 reads bit3=0 → hires
                var _col_val = _m.colour_grid[_src] & 0x07;
                if (_ov == 1) {
                    _byte = _col_val | 0x08;
                } else {
                    _byte = _col_val;
                }
            } else {
                // HR16 mode: full 4-bit colour, bit3 is just colour not MC flag
                _byte = _m.colour_grid[_src] & 0x0F;
            }
            buffer_poke(_asset.buffer, _dst, buffer_u8, _byte);
        }
    }
    // Override grid — third block (editor use only, not sent to C64)
    for (var _row = 0; _row < _mh; _row++) {
        for (var _col = 0; _col < _mw; _col++) {
            var _src = _row * _gw + _col;
            var _dst = _sz * 2 + _row * _mw + _col;
            buffer_poke(_asset.buffer, _dst, buffer_u8, _m.override_grid[_src]);
        }
    }
}