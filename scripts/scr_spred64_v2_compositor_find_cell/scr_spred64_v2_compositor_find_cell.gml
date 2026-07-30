/// @function scr_spred64_v2_compositor_find_cell(_frame, _layer, _row, _col)
/// @desc Returns the array index of the cell in _frame.cells matching
///       (_layer, _row, _col), or -1 if none. Linear scan — sparse cells
///       array is at most 4x4x8 = 128 entries, so this is fine.
function scr_spred64_v2_compositor_find_cell(_frame, _layer, _row, _col) {
    if (_layer < 0) {
        return -1;
    }
    if (_row < 0 || _col < 0) {
        return -1;
    }
    var _cells = _frame.cells;
    var _n     = array_length(_cells);
    for (var _i = 0; _i < _n; _i++) {
        var _c = _cells[_i];
        if (_c.layer == _layer && _c.row == _row && _c.col == _col) {
            return _i;
        }
    }
    return -1;
}