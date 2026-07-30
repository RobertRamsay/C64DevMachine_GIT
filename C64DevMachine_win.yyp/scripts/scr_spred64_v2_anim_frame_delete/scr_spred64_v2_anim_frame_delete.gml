/// @function scr_spred64_v2_anim_frame_delete()
/// @desc Removes the current frame. Guards against deleting the last frame
///       (must keep at least one). Clamps active_frame and anim_start/end
///       to the new frame count.
function scr_spred64_v2_anim_frame_delete() {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        var _v2   = spred64_v2;
        var _comp = _v2.compositor;
        var _n = array_length(_comp.frames);
        if (_n <= 1) exit;   // refuse — must keep at least one frame
        var _idx = _comp.active_frame;
        if (_idx < 0 || _idx >= _n) exit;
        array_delete(_comp.frames, _idx, 1);
        var _new_n = _n - 1;
        if (_comp.active_frame >= _new_n) {
            _comp.active_frame = _new_n - 1;
        }
        _comp.active_cell = -1;
        // Clamp play range
        if (_v2.anim_start >= _new_n) {
            _v2.anim_start = _new_n - 1;
        }
        if (_v2.anim_end >= _new_n) {
            _v2.anim_end = _new_n - 1;
        }
        _v2.dirty = true;
    }
}