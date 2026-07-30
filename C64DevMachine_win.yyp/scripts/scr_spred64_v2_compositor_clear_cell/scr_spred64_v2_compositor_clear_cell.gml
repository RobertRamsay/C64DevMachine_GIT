/// @function scr_spred64_v2_compositor_clear_cell(_frame, _layer, _row, _col)
/// @desc Removes the compositor cell at (_layer, _row, _col) from the sparse
///       array. No-op if no such cell exists. Returns true if a cell was
///       removed, false otherwise.
function scr_spred64_v2_compositor_clear_cell(_frame, _layer, _row, _col) {
    var _idx = scr_spred64_v2_compositor_find_cell(_frame, _layer, _row, _col);
    if (_idx < 0) {
        return false;
    }
    array_delete(_frame.cells, _idx, 1);
    return true;
}