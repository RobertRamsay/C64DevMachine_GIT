// Periodic autosave (every 30s if dirty)
// Not while an editor is open: a full save is heavy and the editor wants the
// frames. Check again in 2 s, so it saves soon after the editor closes.
if ((instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) || code_editor_open) {
    alarm[4] = game_get_speed(gamespeed_fps) * 2;
    exit;
}
if (global.autosave_dirty && global.autosave_mode != 3) scr_autosave();
var _next = (global.autosave_mode != 3) ? global.autosave_interval : 9999;
alarm[4] = game_get_speed(gamespeed_fps) * _next;
autosave_countdown = _next;


