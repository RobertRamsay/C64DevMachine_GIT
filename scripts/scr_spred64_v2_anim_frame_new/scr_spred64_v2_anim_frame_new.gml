/// @function scr_spred64_v2_anim_frame_new()
/// @desc Appends an empty compositor frame at the end. Extends anim_end
///       to include the new frame. Selects the new frame as active so
///       the user immediately sees their new working canvas.
function scr_spred64_v2_anim_frame_new() {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        var _v2   = spred64_v2;
        var _comp = _v2.compositor;
        array_push(_comp.frames, scr_spred64_v2_compositor_init_frame());
        var _new_idx = array_length(_comp.frames) - 1;
        _comp.active_frame = _new_idx;
        _comp.active_cell  = -1;
        // Extend the play range to include the new frame
        _v2.anim_end = _new_idx;
        _v2.dirty    = true;
    }
}