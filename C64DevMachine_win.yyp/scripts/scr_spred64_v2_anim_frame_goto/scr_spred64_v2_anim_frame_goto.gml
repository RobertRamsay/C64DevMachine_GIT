/// @function scr_spred64_v2_anim_frame_goto(_delta)
/// @desc Steps active_frame by _delta with wrap-around against the full
///       frame array (not anim_start/anim_end). Used by the PREV/NEXT
///       buttons in the anim zone — they navigate manually, ignoring
///       the play range.
function scr_spred64_v2_anim_frame_goto(_delta) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        var _v2   = spred64_v2;
        var _comp = _v2.compositor;
        var _n = array_length(_comp.frames);
        if (_n <= 0) exit;
        var _cur = _comp.active_frame + _delta;
        // Wrap within the full frame range
        _cur = ((_cur mod _n) + _n) mod _n;
        _comp.active_frame = _cur;
        _comp.active_cell  = -1;
    }
}


