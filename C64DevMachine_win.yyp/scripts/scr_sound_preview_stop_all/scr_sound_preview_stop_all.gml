/// @desc Stops whatever preview sound is playing on all 3 channels (the
///       SID's 3 voices). Call this before any playback-state transition
///       in the Music Maker (starting, stopping, or switching between row
///       preview and full song) so a note that was still ringing never
///       lingers into the new state.
function scr_sound_preview_stop_all() {
    for (var _sc = 0; _sc < 3; _sc++) {
        scr_sound_preview_free_channel(_sc);
    }
}
