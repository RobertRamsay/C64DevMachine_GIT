// Periodic autosave (every 30s if dirty)
if (global.autosave_dirty && global.autosave_mode != 3) scr_autosave();
var _next = (global.autosave_mode != 3) ? global.autosave_interval : 9999;
alarm[4] = game_get_speed(gamespeed_fps) * _next;
autosave_countdown = _next;


