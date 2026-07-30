/// @function scr_sound_editor_play_step(_m, _step, _channel)
/// @desc Routes note playback through the step's assigned instrument if it
///       has one; falls back to the default preview beep otherwise — so an
///       asset with no instruments yet, or a step with none assigned, sounds
///       exactly as it always has.
/// _max_sec is optional: pass the row duration during playback so the
/// instrument preview doesn't render a release tail the next row will cut
/// off anyway. Omitted for one-off auditions, which should ring out fully.
function scr_sound_editor_play_step(_m, _step, _channel, _max_sec = -1) {
    if (_step.instr_idx >= 0 && _step.instr_idx < array_length(_m.instruments)) {
        scr_sound_instrument_preview_play(_m.instruments[_step.instr_idx], _step.note, _channel, _max_sec);
    } else {
        scr_sound_preview_play(_step.note, "SQUARE", _channel);
    }
}