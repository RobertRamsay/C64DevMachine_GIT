/// @function scr_sound_preview_cache_clear()
/// @desc Frees every cached audition buffer and sound asset, then empties the
///       map. Called when the cache hits its entry cap, and on editor close so
///       the last session's renders don't sit allocated for the rest of the run.
///
/// Order matters: stop any playing instance first, then free the asset, then
/// delete the buffer. Freeing an asset that is still playing, or deleting a
/// buffer an asset still references, is undefined.
function scr_sound_preview_cache_clear() {
    if (!variable_global_exists("snd_preview_cache")) {
        return;
    }

    for (var _ch = 0; _ch < 3; _ch++) {
        scr_sound_preview_free_channel(_ch);
    }

    var _k = ds_map_find_first(global.snd_preview_cache);
    while (!is_undefined(_k)) {
        var _e = global.snd_preview_cache[? _k];
        if (audio_exists(_e.snd)) {
            audio_free_buffer_sound(_e.snd);
        }
        if (buffer_exists(_e.buf)) {
            buffer_delete(_e.buf);
        }
        _k = ds_map_find_next(global.snd_preview_cache, _k);
    }

    ds_map_clear(global.snd_preview_cache);
}