/// @function scr_spred64_v2_compositor_set_cell(_frame, _layer, _row, _col, _slot)
/// @desc Adds-or-updates a compositor cell at (_layer, _row, _col) pointing
///       at sprite slot _slot. Existing cells keep their xo/yo/expand;
///       newly created cells default to xo=0, yo=0, expand="none".
///       Returns the array index of the affected cell.
function scr_spred64_v2_compositor_set_cell(_frame, _layer, _row, _col, _slot) {
    var _existing = scr_spred64_v2_compositor_find_cell(_frame, _layer, _row, _col);
    if (_existing >= 0) {
        _frame.cells[_existing].slot = _slot;
        return _existing;
    }
    var _new_cell = {
        layer  : _layer,
        row    : _row,
        col    : _col,
        slot   : _slot,
        xo     : 0,
        yo     : 0,
        expand : "none"
    };
    array_push(_frame.cells, _new_cell);
    return array_length(_frame.cells) - 1;
}