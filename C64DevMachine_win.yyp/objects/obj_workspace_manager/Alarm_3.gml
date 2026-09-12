/// Alarm 3 - deferred snapshot after box popup confirm
if (global.undo_dirty) {
    // Alarm 1 snapshots after address packing. Do not capture an intermediate
    // drag state or create a second undo entry while that refresh is pending.
    if (mouse_check_button(mb_any) || alarm[1] >= 0) {
        alarm[3] = 2;
        exit;
    }
    scr_undo_snapshot();
    global.undo_dirty = false;
}