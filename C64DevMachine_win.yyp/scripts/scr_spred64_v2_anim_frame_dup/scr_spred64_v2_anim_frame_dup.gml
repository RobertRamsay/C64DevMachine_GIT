/// @function scr_spred64_v2_anim_frame_dup()
/// @desc Duplicates the current frame, inserts the copy at active_frame + 1,
///       and selects the copy. Deep-clones the cells so edits on the copy
///       don't bleed back into the original.
function scr_spred64_v2_anim_frame_dup() {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        var _v2   = spred64_v2;
        var _comp = _v2.compositor;
        if (array_length(_comp.frames) == 0) exit;
        var _src_idx = _comp.active_frame;
        if (_src_idx < 0 || _src_idx >= array_length(_comp.frames)) exit;
        var _src_cells = _comp.frames[_src_idx].cells;
        var _new_cells = array_create(array_length(_src_cells));
        for (var _ci = 0; _ci < array_length(_src_cells); _ci++) {
            var _sc = _src_cells[_ci];
            _new_cells[_ci] = {
                layer  : _sc.layer,
                row    : _sc.row,
                col    : _sc.col,
                slot   : _sc.slot,
                xo     : _sc.xo,
                yo     : _sc.yo,
                expand : _sc.expand
            };
        }
        var _new_frame = { cells : _new_cells };
        array_insert(_comp.frames, _src_idx + 1, _new_frame);
        _comp.active_frame = _src_idx + 1;
        _comp.active_cell  = -1;
        // Extend play range if it ended at the previous-last frame
        if (_v2.anim_end >= _src_idx) {
            _v2.anim_end = array_length(_comp.frames) - 1;
        }
        _v2.dirty = true;
    }
}