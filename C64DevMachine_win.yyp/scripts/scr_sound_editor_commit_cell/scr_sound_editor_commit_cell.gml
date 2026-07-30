/// @function scr_sound_editor_commit_cell(_m, _push_undo_fn, _snap_fn)
/// @desc Validates the in-progress cell edit and writes it back. "---" and
///       empty both clear the step to a rest; anything else that fails
///       scr_note_name_to_freq is rejected with a warning rather than silently
///       stored — a typo'd note name should never compile into a rest.
function scr_sound_editor_commit_cell(_m, _push_undo_fn, _snap_fn, _col_pat) {
    if (!_m.edit_active) {
        return;
    }
    if (_col_pat[_m.edit_voice] == noone) {
        _m.edit_active = false;
        return;
    }
    var _step = _col_pat[_m.edit_voice].steps[_m.edit_step];

    var _raw = string_trim(_m.edit_buf);
    var _up  = string_upper(_raw);
    var _all_dash = (string_length(_up) > 0);
    for (var _di = 1; _di <= string_length(_up); _di++) {
        if (string_char_at(_up, _di) != "-") {
            _all_dash = false;
            break;
        }
    }

    _push_undo_fn(_m, _snap_fn);

    if (_raw == "" ) {
        _step.note      = "";
        _step.instr_idx = -1;
        _step.empty     = true;
    } else if (_all_dash) {
        _step.note      = "---";
        _step.instr_idx = -1;
        _step.empty     = false;
    } else {
        var _freq = scr_note_name_to_freq(_raw);
        if (_freq < 0) {
            _m.warn_msg   = "'" + _raw + "' ISN'T A VALID NOTE — CELL NOT CHANGED";
            _m.warn_timer = game_get_speed(gamespeed_fps) * 3;
            _m.edit_active = false;
            return;
        }
        _step.note      = _up;
        _step.instr_idx = _m.sel_instr;
        _step.empty     = false;
    }

    _m.edit_active    = false;
    global.undo_dirty = true;
}