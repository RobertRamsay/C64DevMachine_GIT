// Deferred address refresh. Never size/pack a graph while a mouse gesture
// is still moving it; repeated requests share this one alarm.
if (mouse_check_button(mb_any)) {
    alarm[1] = 2;
    exit;
}

alarm[1] = -1; // This request is now being handled.
global.addresses_dirty = true;
scr_c64_do_update_addresses();

// The drop handlers have finished and addresses/layout are now settled.
// Snapshot once here, not both on release and again in a delayed callback.
if (global.undo_dirty) {
    scr_undo_snapshot();
    global.undo_dirty = false;
}
