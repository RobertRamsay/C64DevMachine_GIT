// All node Step handlers have completed before this event.
var _release_changed = editor_release_pending &&
    (editor_release_dirty || global.undo_dirty || global.addresses_dirty);
if (_release_changed || showcode_refresh_requested || editor_layout_refresh_requested) {
    // Never gate startup/load or this explicit panel refresh on the shared
    // addresses_dirty flag: the spine traversal can consume it first.
    scr_c64_do_update_addresses();
    global.addresses_dirty = false;
    showcode_refresh_requested = false;
    editor_layout_refresh_requested = false;
}

if (_release_changed) {
    scr_undo_snapshot();
    global.undo_dirty = false;
    if (!editor_release_panning && !is_panning && global.autosave_mode != 3) {
        var _was_clean = !global.autosave_dirty;
        global.autosave_dirty = true;
        global.manual_saved = false;
        if (_was_clean && alarm[4] < game_get_speed(gamespeed_fps) * 5) {
            alarm[4] = game_get_speed(gamespeed_fps) * 5;
        }
    }
}
editor_release_pending = false;
editor_release_dirty = false;
