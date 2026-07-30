/// @function scr_spred64_v2_anim_frame_clear()
/// @desc Empties the current frame's cells, leaving the frame in place.
///       Useful for starting a frame from scratch without changing indices.
function scr_spred64_v2_anim_frame_clear() {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        var _v2   = spred64_v2;
        var _comp = _v2.compositor;
        if (array_length(_comp.frames) == 0) exit;
        var _idx = _comp.active_frame;
        if (_idx < 0 || _idx >= array_length(_comp.frames)) exit;
        _comp.frames[_idx].cells = [];
        _comp.active_cell = -1;
        _v2.dirty = true;
    }
}