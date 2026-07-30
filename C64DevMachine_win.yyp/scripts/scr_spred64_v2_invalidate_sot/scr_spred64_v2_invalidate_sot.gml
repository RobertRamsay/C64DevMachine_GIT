/// @function scr_spred64_v2_invalidate_sot(_slot)
/// @desc Marks the rotation source-of-truth for _slot as invalid. Called by
///       every destructive op (paint, flip, clear, fill, flood) so the next
///       ROT90 takes a fresh snapshot from the post-edit state.
///       Resets rot_angle to 0 so the post-edit state IS the new baseline.
function scr_spred64_v2_invalidate_sot(_slot) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;
        spred64_v2.rot_sot_valid[_slot] = false;
        spred64_v2.rot_angle[_slot]     = 0;
    }
}