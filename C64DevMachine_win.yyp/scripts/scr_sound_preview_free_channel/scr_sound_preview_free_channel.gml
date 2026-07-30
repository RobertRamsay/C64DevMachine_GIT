/// @desc Stops whatever preview is sounding on a channel. Does NOT free the
///       asset or buffer — those belong to global.snd_preview_cache and are
///       reused on the next audition of the same sound. See
///       scr_sound_preview_cache_clear for the teardown path.
///
/// Safe to call on a channel that has never been used — the arrays are grown
/// and seeded with -1 here rather than at each call site.
function scr_sound_preview_free_channel(_channel) {
    if (!variable_global_exists("snd_preview_instance")) {
        global.snd_preview_instance = array_create(3, -1);
    }
    if (!variable_global_exists("snd_preview_asset")) {
        global.snd_preview_asset = array_create(3, -1);
    }
    if (!variable_global_exists("snd_preview_buffer")) {
        global.snd_preview_buffer = array_create(3, -1);
    }

    while (array_length(global.snd_preview_instance) <= _channel) {
        array_push(global.snd_preview_instance, -1);
    }
    while (array_length(global.snd_preview_asset) <= _channel) {
        array_push(global.snd_preview_asset, -1);
    }
    while (array_length(global.snd_preview_buffer) <= _channel) {
        array_push(global.snd_preview_buffer, -1);
    }

    if (global.snd_preview_instance[_channel] != -1) {
        audio_stop_sound(global.snd_preview_instance[_channel]);
        global.snd_preview_instance[_channel] = -1;
    }

    // STOP ONLY — the asset and buffer are NOT freed here. Every rendered
    // audition is owned by global.snd_preview_cache and replayed on the next
    // press of the same note, so freeing on channel takeover would destroy an
    // asset the cache still hands out. scr_sound_preview_cache_clear() is the
    // single owner of teardown; it runs at the entry cap and on editor close.
    //
    // The per-channel asset/buffer globals are now just a record of what last
    // played on the channel, kept because both preview scripts write them.
    global.snd_preview_asset[_channel]  = -1;
    global.snd_preview_buffer[_channel] = -1;
}
