/// @function scr_sound_preview_cache_clear()
/// @desc Frees every cached audition buffer and sound asset, then empties the
///       map. Used for explicit teardown; normal cache pressure evicts only unused sounds so
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
    global.snd_preview_cache_bytes = 0;
}
/// Cache insertion evicts only the oldest unused sound. Never stop a voice
/// merely because another note needs a cache entry. A 64 MiB PCM budget also
/// bounds long ADSR releases; the engine's own sound allocation is additional.
function scr_sound_preview_cache_store(_key, _snd, _buf) {
    if (!variable_global_exists("snd_preview_cache_bytes")) {
        global.snd_preview_cache_bytes = 0;
        var _init_key = ds_map_find_first(global.snd_preview_cache);
        while (!is_undefined(_init_key)) {
            var _init_entry = global.snd_preview_cache[? _init_key];
            global.snd_preview_cache_bytes += buffer_get_size(_init_entry.buf);
            _init_key = ds_map_find_next(global.snd_preview_cache, _init_key);
        }
    }
    var _bytes = buffer_get_size(_buf);
    while (ds_map_size(global.snd_preview_cache) >= 512
        || global.snd_preview_cache_bytes + _bytes > 64 * 1024 * 1024) {
        var _oldest_key = undefined;
        var _oldest_time = infinity;
        var _key_scan = ds_map_find_first(global.snd_preview_cache);
        while (!is_undefined(_key_scan)) {
            var _entry = global.snd_preview_cache[? _key_scan];
            var _used = variable_struct_exists(_entry, "last_used") ? _entry.last_used : 0;
            if (_used < _oldest_time && !audio_is_playing(_entry.snd)) {
                _oldest_time = _used;
                _oldest_key = _key_scan;
            }
            _key_scan = ds_map_find_next(global.snd_preview_cache, _key_scan);
        }
        // All entries sounding: preserve them. With only three preview voices
        // this cannot normally reach either limit, but never free live audio.
        if (is_undefined(_oldest_key)) break;
        var _victim = global.snd_preview_cache[? _oldest_key];
        global.snd_preview_cache_bytes -= buffer_get_size(_victim.buf);
        if (audio_exists(_victim.snd)) audio_free_buffer_sound(_victim.snd);
        if (buffer_exists(_victim.buf)) buffer_delete(_victim.buf);
        ds_map_delete(global.snd_preview_cache, _oldest_key);
    }
    global.snd_preview_cache[? _key] = { snd: _snd, buf: _buf, last_used: get_timer() };
    global.snd_preview_cache_bytes += _bytes;
}
