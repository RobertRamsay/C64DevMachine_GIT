/// Alarm 3 - deferred snapshot after box popup confirm
if (global.undo_dirty) {
    scr_undo_snapshot();
    global.undo_dirty = false;
}