/// @function scr_sound_editor_play_step(_m, _step, _channel)
/// @desc Routes note playback through the step's assigned instrument if it
///       has one; falls back to the default preview beep otherwise — so an
///       asset with no instruments yet, or a step with none assigned, sounds
///       exactly as it always has.
/// _max_sec is optional: pass the row duration during playback so the
/// instrument preview doesn't render a release tail the next row will cut
/// off anyway. Omitted for one-off auditions, which should ring out fully.
function scr_sound_editor_play_step(_m, _step, _channel, _max_sec = -1, _prepare_only = false) {
    if (_step.instr_idx >= 0 && _step.instr_idx < array_length(_m.instruments)) {
        scr_sound_instrument_preview_play(_m.instruments[_step.instr_idx], _step.note, _channel, _max_sec, _prepare_only);
    } else {
        scr_sound_preview_play(_step.note, "SQUARE", _channel, 2048, _prepare_only);
    }
}
/// Collect the distinct sounds in the selected row/song. Keep full note tails:
/// an empty step is a HOLD, not permission to truncate at the next row.
/// Temporary playback fields are deliberately excluded by the music savers.
function scr_sound_editor_preview_prepare(_m, _song, _row_only) {
    _m.preview_jobs = [];
    _m.preview_job_index = 0;
    _m.preview_next_us = 0;
    var _seen_patterns = array_create(array_length(_m.patterns), false);
    var _seen_notes = ds_map_create();
    var _first = _row_only ? _m.sel_order_row : 0;
    var _last = _row_only ? _first + 1 : array_length(_song.order);
    for (var _oi = _first; _oi < _last; _oi++) {
        var _order = _song.order[_oi];
        var _voices = [_order.v1, _order.v2, _order.v3];
        for (var _vi = 0; _vi < 3; _vi++) {
            var _pi = _voices[_vi];
            if (_pi < 0 || _pi >= array_length(_m.patterns) || _seen_patterns[_pi]) continue;
            _seen_patterns[_pi] = true;
            var _pat = _m.patterns[_pi];
            for (var _si = 0; _si < min(_pat.pattern_len, array_length(_pat.steps)); _si++) {
                var _step = _pat.steps[_si];
                if (_step.empty || _step.note == "" || _step.note == "---") continue;
                var _key = "P|" + string(_step.note) + "|SQUARE|2048";
                if (_step.instr_idx >= 0 && _step.instr_idx < array_length(_m.instruments)) {
                    _key = scr_sound_preview_cache_key(_m.instruments[_step.instr_idx], _step.note, -1);
                }
                if (ds_map_exists(_seen_notes, _key)) continue;
                _seen_notes[? _key] = true;
                array_push(_m.preview_jobs, { instr_idx: _step.instr_idx, note: _step.note });
            }
        }
    }
    ds_map_destroy(_seen_notes);
}

/// Render at most one cache miss per editor frame; hits are cheap enough to
/// process in a 2 ms batch. No audio starts until preparation has finished.
/// Space can cancel between frames, including for a long song.
function scr_sound_editor_preview_warm(_m) {
    if (!variable_struct_exists(_m, "preview_jobs")) return true;
    var _start = get_timer();
    while (_m.preview_job_index < array_length(_m.preview_jobs)) {
        var _job = _m.preview_jobs[_m.preview_job_index];
        var _key = "P|" + string(_job.note) + "|SQUARE|2048";
        if (_job.instr_idx >= 0 && _job.instr_idx < array_length(_m.instruments)) {
            _key = scr_sound_preview_cache_key(_m.instruments[_job.instr_idx], _job.note, -1);
        }
        var _was_cached = variable_global_exists("snd_preview_cache")
                       && ds_map_exists(global.snd_preview_cache, _key);
        scr_sound_editor_play_step(_m, _job, 0, -1, true);
        _m.preview_job_index += 1;
        if (!_was_cached || get_timer() - _start >= 2000) break;
    }
    if (_m.preview_job_index < array_length(_m.preview_jobs)) return false;
    _m.preview_jobs = [];
    _m.preview_job_index = 0;
    return true;
}

/// PAL row time is speed * 20,000 us, independent of Draw GUI frequency.
/// Preserve deadline phase through ordinary late frames. After a long pause,
/// bound catch-up to eight rows rather than blocking the UI in an unbounded loop.
function scr_sound_editor_preview_due(_m, _now) {
    var _period = clamp(real(_m.play_speed), 1, 24) * 20000;
    if (!variable_struct_exists(_m, "preview_next_us") || _m.preview_next_us <= 0) {
        _m.preview_next_us = _now + _period;
        return 1;
    }
    if (_now < _m.preview_next_us) return 0;
    var _due = floor((_now - _m.preview_next_us) / _period) + 1;
    if (_due > 8) {
        _m.preview_next_us = _now + _period;
        return 8;
    }
    _m.preview_next_us += _due * _period;
    return _due;
}

/// Shared entry point for toolbar buttons and keyboard transport shortcuts.
/// HERE takes the selected order row AND selected pattern step, then uses
/// normal song progression (including the song's existing end/loop setting).
function scr_sound_editor_transport(_m, _song, _action) {
    scr_sound_preview_stop_all();
    _m.playing = false;
    _m.song_playing = false;
    _m.preview_jobs = [];
    _m.preview_job_index = 0;
    _m.preview_next_us = 0;
    _m.play_tick = 0;
    _m.song_tick = 0;
    if (_action == "STOP") return;

    var _order_index = clamp(floor(_m.sel_order_row), 0, array_length(_song.order) - 1);
    var _step_index = max(0, floor(_m.sel_step));
    if (_action == "SONG") {
        _order_index = 0;
        _step_index = 0;
    } else if (_action == "PAT") {
        _step_index = 0;
    }
    var _row = _song.order[_order_index];
    var _length = _row.force_len;
    if (_length <= 0) {
        var _voices = [_row.v1, _row.v2, _row.v3];
        for (var _v = 0; _v < 3; _v++) {
            var _p = _voices[_v];
            if (_p >= 0 && _p < array_length(_m.patterns)) {
                _length = max(_length, _m.patterns[_p].pattern_len);
            }
        }
    }
    if (_length <= 0) _length = 64;
    _step_index = clamp(_step_index, 0, _length - 1);
    _m.preview_display_order = _order_index;
    _m.preview_display_step = _step_index;
    if (_action == "PAT" || _action == "ROW_HERE") {
        _m.playing = true;
        _m.play_row = _step_index;
    } else {
        _m.song_playing = true;
        _m.song_order_row = _order_index;
        _m.song_master_row = _step_index;
    }
    scr_sound_editor_preview_prepare(_m, _song, _m.playing);
}
