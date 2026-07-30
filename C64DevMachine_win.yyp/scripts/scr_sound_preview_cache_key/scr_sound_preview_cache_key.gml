/// @function scr_sound_preview_cache_key(_instr, _note_name, _max_sec)
/// @desc Builds the cache key for a rendered instrument audition.
///
/// The key covers EVERY input the synth reads, so an instrument edit
/// automatically produces a different key and the stale entry is simply never
/// looked up again. That is cheaper and far less error-prone than hunting down
/// each place an instrument can be modified and invalidating from there —
/// there are five (text commit, four ADSR steppers, pulse width) and adding a
/// sixth later would silently break the cache.
///
/// _max_sec is in the key because it changes the rendered LENGTH: the same
/// note auditioned bare (full tail) and during row playback (trimmed) are
/// different buffers.
function scr_sound_preview_cache_key(_instr, _note_name, _max_sec) {

    var _sig = "";

    // Compiled bytecode — the actual command stream, not the source text, so
    // a whitespace-only edit doesn't needlessly drop the cache.
    var _b = _instr.compiled.bytes;
    for (var _i = 0; _i < array_length(_b); _i++) {
        _sig += string(_b[_i]) + ",";
    }

    _sig += "|" + string(variable_struct_exists(_instr, "attack")      ? _instr.attack      : 0);
    _sig += "," + string(variable_struct_exists(_instr, "decay")       ? _instr.decay       : 8);
    _sig += "," + string(variable_struct_exists(_instr, "sustain")     ? _instr.sustain     : 8);
    _sig += "," + string(variable_struct_exists(_instr, "release")     ? _instr.release     : 0);
    _sig += "," + string(variable_struct_exists(_instr, "pulse_width") ? _instr.pulse_width : 2048);

    // Round _max_sec so float noise in a row duration can't produce a fresh
    // key every single row.
    var _ms = -1;
    if (_max_sec > 0) {
        _ms = round(_max_sec * 1000);
    }

    return _sig + "|" + string(_note_name) + "|" + string(_ms);
}