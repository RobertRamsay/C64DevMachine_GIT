/// MUSIC MAKER DIGI TRACK — the "4th voice".
///
/// DATA (asset meta, seeded in scr_sound_editor_create):
///   digi_rate      the rate a sample plays at for note C-4, Hz. Other notes
///                  scale it (C-5 = double rate = an octave up).
///   digi_samples   16 slots of SAMPLE asset names ("" = empty). A digi step's
///                  sample number is a slot index.
///   digi_patterns  separate pool from patterns[], so voice pattern indices
///                  never shift. { name, pattern_len, steps[] }, each step
///                  { smp, vol, note }:
///                    smp   -1 empty (a playing sample carries on), -2 OFF (cut),
///                          0-15 trigger that slot
///                    vol   0-3, 3 = full (0 = 1/4, 1 = 1/2, 2 = 3/4 amplitude)
///                    note  0-95, DIGI_NOTE_BASE (C-4) = the sample's own pitch
///   order rows     dg = digi pattern index, -1 = none.
///
/// TIMING: the digi track follows the shared row clock (the compiled player
/// supports nothing else; the editor preview follows voice 1 under TIMING: PER
/// VOICE). It does not count towards an order row's length: a shorter digi
/// pattern simply ends (REPEAT does not wrap it), a longer one is cut at the
/// row's length.

#macro DIGI_SLOTS     16
#macro DIGI_SMP_EMPTY -1
#macro DIGI_SMP_OFF   -2
#macro DIGI_NOTE_BASE 48

/// Brings every order row and digi pattern up to the current shape. Rows are
/// created in several places in the editor, so this runs every frame the
/// Music Maker is open — it is a handful of struct reads.
function scr_digi_ensure(_m) {
    while (array_length(_m.digi_samples) < DIGI_SLOTS) {
        array_push(_m.digi_samples, "");
    }
    for (var _si = 0; _si < array_length(_m.songs); _si++) {
        var _ord = _m.songs[_si].order;
        for (var _ri = 0; _ri < array_length(_ord); _ri++) {
            if (is_undefined(_ord[_ri][$ "dg"])) {
                _ord[_ri].dg = -1;
            }
            if (_ord[_ri].dg >= array_length(_m.digi_patterns)) {
                _ord[_ri].dg = -1;
            }
        }
    }
    for (var _pi = 0; _pi < array_length(_m.digi_patterns); _pi++) {
        scr_digi_ensure_steps(_m.digi_patterns[_pi]);
    }
}

/// Grows / truncates a digi pattern's steps to its length; steps saved before
/// notes existed play at the sample's own pitch.
function scr_digi_ensure_steps(_pat) {
    _pat.pattern_len = clamp(real(_pat.pattern_len), 4, 128);
    while (array_length(_pat.steps) < _pat.pattern_len) {
        array_push(_pat.steps, scr_digi_step_blank());
    }
    if (array_length(_pat.steps) > _pat.pattern_len) {
        array_resize(_pat.steps, _pat.pattern_len);
    }
    for (var _i = 0; _i < array_length(_pat.steps); _i++) {
        if (is_undefined(_pat.steps[_i][$ "note"])) {
            _pat.steps[_i].note = DIGI_NOTE_BASE;
        }
        if (is_undefined(_pat.steps[_i][$ "spd"])) {
            _pat.steps[_i].spd = 0;     // saved before the speed command existed
        }
    }
}

function scr_digi_step_blank() {
    return { smp: DIGI_SMP_EMPTY, vol: 3, note: DIGI_NOTE_BASE, spd: 0 };
}

/// "C-4", "C#4" ...
function scr_digi_note_name(_note) {
    static _names = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"];
    var _n = clamp(round(_note), 0, 95);
    return _names[_n mod 12] + string(_n div 12);
}

/// Appends a new empty digi pattern; returns its index, or -1 if the pool is full.
function scr_digi_pattern_new(_m, _len) {
    if (array_length(_m.digi_patterns) >= 64) {
        return -1;
    }
    var _n = array_length(_m.digi_patterns);
    var _name = "DIGI " + string(_n);
    if (_n < 10) {
        _name = "DIGI 0" + string(_n);
    }
    var _pat = { name: _name, pattern_len: _len, steps: [] };
    scr_digi_ensure_steps(_pat);
    array_push(_m.digi_patterns, _pat);
    return _n;
}

// ═══════════════════════════ UNDO ═══════════════════════════
// The Music Maker's undo entries carry a digi snapshot (dgs) next to their
// patterns snapshot, plus whether the digi lane had the cursor (dgf, dgstep),
// so one Ctrl+Z / Ctrl+Y stack covers voices and digi alike.

/// Deep copy of the digi patterns and every order row's dg.
function scr_digi_snapshot(_m) {
    var _pats = [];
    for (var _p = 0; _p < array_length(_m.digi_patterns); _p++) {
        var _src = _m.digi_patterns[_p];
        var _steps = [];
        for (var _s = 0; _s < array_length(_src.steps); _s++) {
            var _st = _src.steps[_s];
            array_push(_steps, { smp: _st.smp, vol: _st.vol, note: _st.note, spd: _st.spd });
        }
        array_push(_pats, { name: _src.name, pattern_len: _src.pattern_len, steps: _steps });
    }
    var _ords = [];
    for (var _g = 0; _g < array_length(_m.songs); _g++) {
        var _o = _m.songs[_g].order;
        var _row_dg = [];
        for (var _r = 0; _r < array_length(_o); _r++) {
            array_push(_row_dg, _o[_r].dg);
        }
        array_push(_ords, _row_dg);
    }
    return { pats: _pats, ords: _ords };
}

/// Puts a snapshot back. Order rows added or removed since are matched by
/// position; anything past the snapshot keeps its value.
function scr_digi_restore(_m, _snap) {
    _m.digi_patterns = _snap.pats;
    for (var _g = 0; _g < array_length(_m.songs) && _g < array_length(_snap.ords); _g++) {
        var _o = _m.songs[_g].order;
        var _row_dg = _snap.ords[_g];
        for (var _r = 0; _r < array_length(_o) && _r < array_length(_row_dg); _r++) {
            _o[_r].dg = _row_dg[_r];
        }
    }
    scr_digi_ensure(_m);
}

/// After an undo / redo entry has been applied: restore its digi data and,
/// when the edit was made in the digi lane, give the lane the cursor back.
function scr_digi_undo_apply(_m, _ent) {
    var _dgs = _ent[$ "dgs"];
    if (!is_undefined(_dgs)) {
        scr_digi_restore(_m, _dgs);
    }
    _m.dg_focus = false;
    if (_ent[$ "dgf"] == true) {
        _m.dg_focus    = true;
        _m.dg_sel_step = _ent.dgstep;
        _m.dg_anchor   = _ent.dgstep;
    }
}

/// Ctrl+Z (_redo false) / Ctrl+Y while the digi lane has the cursor. Same
/// stacks and entry shape as the voice grid's handler.
function scr_digi_undo_step(_m, _redo, _snapf, _gotof, _vis) {
    var _from = _m.undo_stack;
    var _to   = _m.redo_stack;
    var _msg  = "UNDO";
    if (_redo) {
        _from = _m.redo_stack;
        _to   = _m.undo_stack;
        _msg  = "REDO";
    }
    if (array_length(_from) <= 0) {
        return;
    }
    var _top = array_length(_from) - 1;
    var _ent = _from[_top];
    array_delete(_from, _top, 1);
    var _chip = 0;
    if (!is_undefined(_ent[$ "chip"])) {
        _chip = _ent.chip;
    }
    array_push(_to, { pats: _snapf(_m), voice: _ent.voice, step: _ent.step, sub: _ent.sub, ord: _ent.ord, chip: _chip,
                      dgs: scr_digi_snapshot(_m), dgf: _ent[$ "dgf"] == true, dgstep: _m.dg_sel_step });
    _m.patterns = _ent.pats;
    _gotof(_m, _ent, _vis);
    scr_digi_undo_apply(_m, _ent);
    _m.bank_sel_pattern = clamp(_m.bank_sel_pattern, 0, array_length(_m.patterns) - 1);
    _m.warn_msg   = _msg;
    _m.warn_timer = game_get_speed(gamespeed_fps);
    global.undo_dirty      = true;
    global.addresses_dirty = true;
}

/// Undo point for a digi edit (the voice grid's push, tagged as a digi edit).
function scr_digi_push_undo(_m, _pushf, _snapf) {
    var _was = _m.dg_focus;
    _m.dg_focus = true;
    _pushf(_m, _snapf);
    _m.dg_focus = _was;
}

/// SAMPLE asset by name, or undefined.
function scr_digi_find_sample(_name) {
    if (_name == "" || !instance_exists(obj_asset_manager)) {
        return undefined;
    }
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "SAMPLE" && _a.name == _name) {
            return _a;
        }
    }
    return undefined;
}

/// Names of every SAMPLE asset in the project.
function scr_digi_sample_names() {
    var _out = [];
    if (!instance_exists(obj_asset_manager)) {
        return _out;
    }
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "SAMPLE") {
            array_push(_out, _a.name);
        }
    }
    return _out;
}

// ═══════════════════════════ PREVIEW AUDIO ═══════════════════════════

/// Buffer sound of _asset encoded at _rate, as the $D418 DAC outputs it.
/// Cached on the SAMPLE asset and rebuilt when any setting that changes the
/// bytes changes. Returns -1 when the sample has no audio.
function scr_digi_sample_sound(_asset, _rate) {
    var _sm = _asset.meta;
    var _key = string(_rate) + ":" + string(_sm.data_ver) + ":" + string(_sm.gain) + ":"
             + string(_sm.dither) + ":" + string(_sm.pack) + ":" + string(_sm.normalise) + ":" + string(_sm.compress) + ":"
             + string(_sm.trim_start) + ":" + string(_sm.trim_end);
    if (_sm.pv_dg_key == _key) {
        return _sm.pv_dg_snd;
    }
    scr_digi_free_sample_sound(_asset);
    _sm.pv_dg_key = _key;

    var _r = scr_sample_encode_at(_asset, _rate, _sm.pack);
    var _cnt = array_length(_r.enc);
    if (_cnt <= 0) {
        return -1;
    }
    var _out_rate = SAMPLE_PV_RATE;
    var _n = floor(_cnt * _out_rate / _rate);
    if (_n <= 0) {
        return -1;
    }
    var _buf = buffer_create(_n * 2, buffer_fixed, 2);
    for (var _i = 0; _i < _n; _i++) {
        var _k = min(_cnt - 1, floor(_i * _rate / _out_rate));
        var _v = (_r.enc[_k] - 7.5) / 7.5;
        buffer_write(_buf, buffer_s16, round(_v * 24000));
    }
    _sm.pv_dg_buf = _buf;
    _sm.pv_dg_snd = audio_create_buffer_sound(_buf, buffer_s16, _out_rate, 0, _n * 2, audio_mono);
    return _sm.pv_dg_snd;
}

/// Releases a SAMPLE asset's cached digi sound (stopping any instance of it).
function scr_digi_free_sample_sound(_asset) {
    var _sm = _asset.meta;
    if (_sm.pv_dg_snd != -1) {
        audio_stop_sound(_sm.pv_dg_snd);
        audio_free_buffer_sound(_sm.pv_dg_snd);
    }
    if (_sm.pv_dg_buf != -1) {
        buffer_delete(_sm.pv_dg_buf);
    }
    _sm.pv_dg_snd = -1;
    _sm.pv_dg_buf = -1;
    _sm.pv_dg_key = "";
}

/// Cuts the digi channel.
function scr_digi_stop(_m) {
    if (_m.dg_inst != -1) {
        if (audio_is_playing(_m.dg_inst)) {
            audio_stop_sound(_m.dg_inst);
        }
    }
    _m.dg_inst = -1;
}


/// Acts on one digi step: trigger, cut, or nothing. Monophonic, like the
/// hardware: a new trigger cuts whatever was playing. The note sets the
/// playback rate: DIGI_NOTE_BASE is the sample's own pitch.
function scr_digi_play_step(_m, _st) {
    if (_st.smp == DIGI_SMP_OFF) {
        scr_digi_stop(_m);
        return;
    }
    if (_st.smp < 0 || _st.smp >= DIGI_SLOTS) {
        return;
    }
    var _a = scr_digi_find_sample(_m.digi_samples[_st.smp]);
    if (is_undefined(_a)) {
        return;
    }
    var _snd = scr_digi_sample_sound(_a, _m.digi_rate);
    if (_snd == -1) {
        return;
    }
    scr_digi_stop(_m);
    _m.dg_inst = audio_play_sound(_snd, 10, false);
    var _gains = [0.25, 0.5, 0.75, 1.0];
    audio_sound_gain(_m.dg_inst, _gains[clamp(_st.vol, 0, 3)], 0);
    audio_sound_pitch(_m.dg_inst, power(2, (_st.note - DIGI_NOTE_BASE) / 12));
}

/// Follows playback and fires digi steps as their rows come up. Called once a
/// frame after the editor's playback block has settled the position.
function scr_digi_preview_tick(_m, _cur_song, _voice_pos) {
    var _active = (_m.playing || _m.song_playing) && (_m.digi_on == 1);
    if (!_active) {
        if (_m.dg_last_key != -1) {
            scr_digi_stop(_m);
            _m.dg_last_key = -1;
        }
        _m.dg_run_sp  = _m.digi_speed;
        _m.dg_own_ord = -1;
        _m.dg_own_row = -1;
        return;
    }
    var _ord  = _m.preview_display_order;
    var _step = _m.preview_display_step;
    if (is_array(_voice_pos)) {
        _ord  = _voice_pos[0][0];
        _step = _voice_pos[0][1];
    }
    if (_ord < 0 || _ord >= array_length(_cur_song.order) || _step < 0) {
        return;
    }
    // The digi lane keeps its own row: it follows the song's rows while its
    // speed is 0 (SONG), or runs its own clock at dg_run_sp frames a row
    // (set by DIGI SPEED, or by an Fxx step). Every order row restarts it at
    // row 0, like the C64 player.
    var _key = _ord * 1000 + _step;
    if (_key != _m.dg_last_key) {
        _m.dg_last_key = _key;
        if (_step == 0 || _ord != _m.dg_own_ord) {
            _m.dg_own_ord   = _ord;
            _m.dg_own_row   = _step;
            _m.dg_sync_time = current_time;
            if (_m.dg_run_sp > 0) {
                _m.dg_own_row = 0;
            }
            scr_digi_preview_row(_m, _cur_song);
            return;
        }
        if (_m.dg_run_sp == 0) {
            _m.dg_own_row = _step;
            scr_digi_preview_row(_m, _cur_song);
            return;
        }
    }
    if (_m.dg_run_sp > 0 && _m.dg_own_ord >= 0) {
        var _row_ms = _m.dg_run_sp * 20;    // PAL: 20 ms a frame
        if (current_time - _m.dg_sync_time >= _row_ms) {
            _m.dg_sync_time += _row_ms;
            _m.dg_own_row   += 1;
            scr_digi_preview_row(_m, _cur_song);
        }
    }
}

/// Plays the digi lane's current row (dg_own_row of the synced order row's
/// digi pattern) and applies its speed command.
function scr_digi_preview_row(_m, _cur_song) {
    if (_m.dg_own_ord < 0 || _m.dg_own_ord >= array_length(_cur_song.order)) {
        return;
    }
    var _row = _cur_song.order[_m.dg_own_ord];
    if (_row.dg < 0 || _row.dg >= array_length(_m.digi_patterns)) {
        return;
    }
    var _pat = _m.digi_patterns[_row.dg];
    // Like the C64 player: past the digi pattern's own length there is nothing
    // (REPEAT does not wrap the digi track).
    if (_m.dg_own_row < 0 || _m.dg_own_row >= _pat.pattern_len) {
        return;
    }
    var _st = _pat.steps[_m.dg_own_row];
    if (_st.spd == DIGI_SPD_SONG) {
        _m.dg_run_sp = 0;
    } else if (_st.spd > 0) {
        _m.dg_run_sp    = _st.spd;
        _m.dg_sync_time = current_time;
    }
    scr_digi_play_step(_m, _st);
}

// ═══════════════════════════ GRID LANE ═══════════════════════════

/// Draws the digi lane header (above the grid) and its cells, and handles the
/// mouse. Returns true when a digi cell was clicked this frame (the caller
/// commits any open voice-cell edit).
///   _hl_row  row to light as playing, or -1
///   _pushf / _snapf  the editor's undo push and patterns snapshot
function scr_digi_lane(_m, _order_row, _x, _gy0, _w, _row_h, _vis, _grid_len, _txt_scale, _hl_row, _mx, _my, _pushf, _snapf) {
    var _clicked = false;
    var _pat = noone;
    if (_order_row.dg >= 0 && _order_row.dg < array_length(_m.digi_patterns)) {
        _pat = _m.digi_patterns[_order_row.dg];
    }
    var _c_lane = make_color_rgb(255, 130, 170);
    var _c_btn  = make_color_rgb(60, 130, 150);

    // ── HEADER ── row 1: length stepper (or NEW) + "DIGI"; row 2: SAMPLES button.
    draw_set_font_l(fnt_c64_tiny);
    var _by1 = _gy0 - 22;
    var _by2 = _gy0 - 5;
    var _bhov = point_in_rectangle(_mx, _my, _x, _by1, _x + _w, _by2);
    scr_mm_info(_bhov, "OPENS / CLOSES THE DIGI SAMPLES PANEL: SAMPLE SLOTS, RATE, BOOST, SPEED");
    var _bcol = make_color_rgb(120, 40, 80);
    if (_bhov || _m.dg_slots_open) {
        _bcol = make_color_rgb(190, 70, 120);
    }
    draw_set_color(_bcol);
    draw_rectangle(_x, _by1, _x + _w, _by2, false);
    draw_set_color(_c_lane);
    draw_rectangle(_x, _by1, _x + _w, _by2, true);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    var _cs = string(_m.dg_cur_slot);
    if (_m.dg_cur_slot < 10) {
        _cs = "0" + _cs;
    }
    draw_text_l(_x + _w * 0.5, _by1 + 1, "SAMPLES  [" + _cs + "]");   // in line with the VOICE n labels
    draw_set_halign(fa_left);
    if (_bhov && mouse_check_button_pressed(mb_left)) {
        _m.dg_slots_open = !_m.dg_slots_open;
    }

    draw_set_font_l(fnt_c64_pico);
    var _hy = _gy0 - 34;
    if (_pat != noone) {
        var _lx = _x;
        var _lhov = point_in_rectangle(_mx, _my, _lx, _hy - 4, _lx + 12, _hy + 10);
        scr_mm_info(_lhov, "DIGI PATTERN LENGTH: 4 ROWS SHORTER (4-128)");
        draw_set_color(_c_btn);
        if (_lhov) {
            draw_set_color(c_aqua);
        }
        draw_text_l(_lx, _hy, "<");
        if (_lhov && mouse_check_button_pressed(mb_left)) {
            scr_digi_push_undo(_m, _pushf, _snapf);
            _pat.pattern_len = clamp(_pat.pattern_len - 4, 4, 128);
            scr_digi_ensure_steps(_pat);
            global.undo_dirty = true;
        }
        draw_set_color(c_white);
        draw_text_l(_lx + 12, _hy, string(_pat.pattern_len));
        var _rx = _lx + 34;
        var _rhov = point_in_rectangle(_mx, _my, _rx, _hy - 4, _rx + 12, _hy + 10);
        scr_mm_info(_rhov, "DIGI PATTERN LENGTH: 4 ROWS LONGER (4-128)");
        draw_set_color(_c_btn);
        if (_rhov) {
            draw_set_color(c_aqua);
        }
        draw_text_l(_rx, _hy, ">");
        if (_rhov && mouse_check_button_pressed(mb_left)) {
            scr_digi_push_undo(_m, _pushf, _snapf);
            _pat.pattern_len = clamp(_pat.pattern_len + 4, 4, 128);
            scr_digi_ensure_steps(_pat);
            global.undo_dirty = true;
        }
        draw_set_color(make_color_rgb(110, 100, 130));
        draw_text_l(_lx + 56, _hy, _pat.name);
    } else {
        // NEW: make a digi pattern and put it on the selected order row.
        var _nx = _x;
        var _nhov = point_in_rectangle(_mx, _my, _nx, _hy - 4, _nx + 34, _hy + 10);
        scr_mm_info(_nhov, "MAKES A NEW DIGI PATTERN AND PUTS IT ON THE SELECTED ORDER ROW");
        draw_set_color(_c_btn);
        if (_nhov) {
            draw_set_color(c_aqua);
        }
        draw_text_l(_nx, _hy, "NEW");
        if (_nhov && mouse_check_button_pressed(mb_left)) {
            scr_digi_push_undo(_m, _pushf, _snapf);
            var _np = scr_digi_pattern_new(_m, max(4, min(128, _grid_len)));
            if (_np >= 0) {
                _order_row.dg = _np;
                global.undo_dirty = true;
            }
        }
    }
    draw_set_color(_c_lane);
    draw_set_halign(fa_right);
    draw_text_l(_x + _w, _hy, "DIGI");
    draw_set_halign(fa_left);
    draw_set_font_l(fnt_c64_tiny);

    // ── CELLS ── same metrics as the voice grid's cells
    var _ty = max(2, floor((_row_h - 10 * _txt_scale) / 2));
    var _x_slot = 8 + round(38 * _txt_scale);
    var _x_vol  = 8 + round(66 * _txt_scale);
    var _press = mouse_check_button_pressed(mb_left);
    var _in_lane = false;
    var _sel_lo = min(_m.dg_anchor, _m.dg_sel_step);
    var _sel_hi = max(_m.dg_anchor, _m.dg_sel_step);
    for (var _r = 0; _r < _vis; _r++) {
        var _row = _r + _m.list_scroll;
        if (_row >= _grid_len) {
            break;
        }
        var _ry = _gy0 + _r * _row_h;
        var _x2 = _x + _w;
        var _hov = point_in_rectangle(_mx, _my, _x, _ry, _x2, _ry + _row_h);
        scr_mm_info(_hov && _pat != noone, (_mx >= _x + 84) ? "DIGI COMMAND CELL: CLICK, TYPE F01-F1F (OWN SPEED) OR F00 (SONG ROWS). RMB CLEARS IT" : "DIGI CELL: CLICK SELECTS (SHIFT EXTENDS), TYPE A NOTE TO PLACE THE CURRENT SAMPLE. RMB CLEARS");
        if (_hov) {
            _in_lane = true;
        }

        if (_pat == noone) {
            draw_set_color(make_color_rgb(26, 22, 26));
            draw_rectangle(_x, _ry, _x2, _ry + _row_h, false);
            draw_set_color(make_color_rgb(110, 90, 100));
            draw_text_transformed_l(_x + 8, _ry + _ty, "----", _txt_scale, _txt_scale, 0);
        } else if (_row >= _pat.pattern_len) {
            draw_set_color(make_color_rgb(18, 18, 24));
            draw_rectangle(_x, _ry, _x2, _ry + _row_h, false);
        } else {
            var _st = _pat.steps[_row];
            if (_m.dg_focus && _sel_lo != _sel_hi && _row >= _sel_lo && _row <= _sel_hi) {
                draw_set_color(make_color_rgb(70, 40, 70));
                draw_rectangle(_x, _ry, _x2, _ry + _row_h, false);
            }
            if (_hl_row == _row) {
                draw_set_color(make_color_rgb(40, 100, 60));
                draw_set_alpha(0.5);
                draw_rectangle(_x, _ry, _x2, _ry + _row_h, false);
                draw_set_alpha(1.0);
            }
            // Laid out like a voice lane: note and sample slot (like a note and its
            // instrument), then the command column at the voice grid's offset,
            // volume small at the right edge.
            var _cmd_x = _x + 90;     // = _cmd_off in scr_sound_editor_editor
            if (_st.smp >= 0) {
                var _s_str = string(_st.smp);
                if (_st.smp < 10) {
                    _s_str = "0" + _s_str;
                }
                var _n_str = scr_digi_note_name(_st.note) + " ";
                draw_set_color(_c_lane);
                draw_text_transformed_l(_x + 8, _ry + _ty, _n_str, _txt_scale, _txt_scale, 0);
                draw_set_color(make_color_rgb(255, 190, 210));
                if (is_undefined(scr_digi_find_sample(_m.digi_samples[_st.smp]))) {
                    draw_set_color(make_color_rgb(200, 90, 70));   // empty / missing slot
                }
                draw_text_transformed_l(_x + 8 + string_width_l(_n_str) * _txt_scale, _ry + _ty, _s_str, _txt_scale, _txt_scale, 0);
                draw_set_font_l(fnt_c64_pico);
                draw_set_halign(fa_right);
                draw_set_color(make_color_rgb(150, 120, 150));
                draw_text_l(_x2 - 4, _ry + floor(_row_h / 2) - 4, "V" + string(_st.vol));
                draw_set_halign(fa_left);
                draw_set_font_l(fnt_c64_tiny);
            } else if (_st.smp == DIGI_SMP_OFF) {
                draw_set_color(make_color_rgb(230, 120, 90));
                draw_text_transformed_l(_x + 8, _ry + _ty, "OFF", _txt_scale, _txt_scale, 0);
            } else {
                draw_set_color(make_color_rgb(70, 60, 80));
                draw_text_transformed_l(_x + 8, _ry + _ty, "...", _txt_scale, _txt_scale, 0);
            }
            // Command column: F01-F1F own tempo, F00 back to the song's rows.
            if (_m.dg_cmd_on && _m.dg_focus && _m.dg_sel_step == _row) {
                var _ty_str = "F" + _m.dg_cmd_buf;
                while (string_length(_ty_str) < 3) {
                    _ty_str += "_";
                }
                draw_set_color(c_yellow);
                draw_text_transformed_l(_cmd_x, _ry + _ty, _ty_str, _txt_scale, _txt_scale, 0);
            } else if (_st.spd > 0) {
                var _cmd_txt = "F00";
                if (_st.spd != DIGI_SPD_SONG) {
                    _cmd_txt = string_upper(decimal_to_hex(_st.spd));
                    while (string_length(_cmd_txt) < 2) {
                        _cmd_txt = "0" + _cmd_txt;
                    }
                    _cmd_txt = "F" + _cmd_txt;
                }
                draw_set_color(make_color_rgb(255, 170, 90));
                draw_text_transformed_l(_cmd_x, _ry + _ty, _cmd_txt, _txt_scale, _txt_scale, 0);
            } else {
                draw_set_color(make_color_rgb(60, 60, 70));
                draw_text_transformed_l(_cmd_x, _ry + _ty, "...", _txt_scale, _txt_scale, 0);
            }
            if (_hov && mouse_check_button_pressed(mb_right)) {
                scr_digi_push_undo(_m, _pushf, _snapf);
                if (_mx >= _cmd_x - 6) {
                    _st.spd = 0;                     // command column: just the command
                } else {
                    var _blank = scr_digi_step_blank();
                    _st.smp  = _blank.smp;
                    _st.vol  = _blank.vol;
                    _st.note = _blank.note;
                    _st.spd  = _blank.spd;
                }
                global.undo_dirty = true;
            }
        }
        if (_m.dg_focus && _m.dg_sel_step == _row) {
            // Cursor like the voice grid's: the note part or the command column.
            draw_set_color(c_yellow);
            if (_m.dg_sel_sub == 1) {
                draw_rectangle(_x + 84, _ry, _x2, _ry + _row_h, true);
            } else {
                draw_rectangle(_x, _ry, _x + 82, _ry + _row_h, true);
            }
        }
        if (_hov && _press) {
            _m.dg_focus    = true;
            _m.dg_sel_step = _row;
            _m.dg_cmd_on   = false;      // a click drops a half-typed command, like the voice grid
            _m.dg_cmd_buf  = "";
            _m.dg_sel_sub  = 0;
            if (_mx >= _x + 84) {
                _m.dg_sel_sub = 1;       // command column
            }
            if (!keyboard_check(vk_shift)) {
                _m.dg_anchor = _row;
            }
            _clicked = true;
        }
    }
    // Any other click takes focus away from the lane. Clicks inside the slots
    // panel never reach here (the editor hides the mouse from everything
    // under it).
    if (_press && !_in_lane) {
        _m.dg_focus  = false;
        _m.dg_cmd_on = false;
    }
    _m.dg_sel_step = clamp(_m.dg_sel_step, 0, max(0, _grid_len - 1));
    _m.dg_anchor   = clamp(_m.dg_anchor, 0, max(0, _grid_len - 1));
    return _clicked;
}

/// Moves the cursor from the voice grid into the DIGI lane on the same row.
function scr_digi_focus_from_grid(_m) {
    _m.dg_focus    = true;
    _m.dg_sel_sub  = 0;
    _m.dg_cmd_on   = false;
    _m.dg_cmd_buf  = "";
    _m.dg_sel_step = _m.sel_step;
    _m.dg_anchor   = _m.sel_step;
    _m.edit_active = false;
}

/// Scrolls the grid just enough to show the digi cursor. Only called when the
/// cursor has moved, so the mouse wheel can still scroll it off-screen.
function scr_digi_scroll_to_cursor(_m, _vis) {
    if (_m.dg_sel_step < _m.list_scroll) {
        _m.list_scroll = _m.dg_sel_step;
    }
    if (_m.dg_sel_step >= _m.list_scroll + _vis) {
        _m.list_scroll = _m.dg_sel_step - _vis + 1;
    }
}

/// Keyboard for the digi lane, tracker-style:
///   piano keys    note with the current sample slot (Z-M octave below the
///                 OCTAVE setting, Q-U at it, I 9 O 0 P above)
///   , .           previous / next sample slot (also changes the selected cell)
///   [ ]           volume -/+        -  OFF        Del / Backspace  clear
///   Left / Right  between the note and command columns, then on to the voices
///   F + 2 hex     (command column) speed: F01-F1F frames a digi row from
///                 here on, F00 back to the song's rows (Esc cancels)
///   Up / Down     move (Shift extends the selection)        Esc  leave
///   Ctrl+C / X / V  copy / cut / paste rows   Ctrl+Z / Y  undo / redo
/// Typing into an order row with no digi pattern makes one first.
function scr_digi_keys(_m, _order_row, _grid_len, _vis, _pushf, _snapf, _gotof) {
    keyboard_string = "";
    var _ctrl  = keyboard_check(vk_control) || scr_cmd_held();
    var _shift = keyboard_check(vk_shift);
    if (keyboard_check_pressed(vk_escape)) {
        if (_m.dg_cmd_on) {
            _m.dg_cmd_on  = false;
            _m.dg_cmd_buf = "";
            return;
        }
        _m.dg_focus = false;
        return;
    }

    // ── UNDO / REDO ──
    if (_ctrl && keyboard_check_pressed(ord("Z")) && !_shift) {
        scr_digi_undo_step(_m, false, _snapf, _gotof, _vis);
        return;
    }
    if (_ctrl && (keyboard_check_pressed(ord("Y")) || (keyboard_check_pressed(ord("Z")) && _shift))) {
        scr_digi_undo_step(_m, true, _snapf, _gotof, _vis);
        return;
    }

    // ── LEFT / RIGHT / TAB ── back into the voice grid, like moving between
    // voices: Right (Tab) wraps to voice 1's note, Left (Shift+Tab) goes to
    // voice 3's command column. The keys are cleared so the voice grid's own
    // handler, which runs later this frame, doesn't move a second time.
    var _go_right = keyboard_check_pressed(vk_right) || (keyboard_check_pressed(vk_tab) && !_shift);
    var _go_left  = keyboard_check_pressed(vk_left)  || (keyboard_check_pressed(vk_tab) && _shift);
    if (_go_right && _m.dg_sel_sub == 0) {
        // Note -> command column, like a voice.
        _m.dg_sel_sub = 1;
        _m.dg_cmd_on  = false;
        _m.dg_cmd_buf = "";
        keyboard_clear(vk_right);
        keyboard_clear(vk_tab);
        return;
    }
    if (_go_left && _m.dg_sel_sub == 1) {
        _m.dg_sel_sub = 0;
        _m.dg_cmd_on  = false;
        _m.dg_cmd_buf = "";
        keyboard_clear(vk_left);
        keyboard_clear(vk_tab);
        return;
    }
    if (_go_right || _go_left) {
        _m.dg_cmd_on  = false;
        _m.dg_cmd_buf = "";
        _m.dg_focus  = false;
        _m.sel_step  = _m.dg_sel_step;
        _m.sel_sub   = 0;
        _m.sel_voice = 0;
        if (_go_left) {
            _m.sel_sub   = 1;
            _m.sel_voice = 2;
        }
        _m.sel_anchor_voice = _m.sel_voice;
        _m.sel_anchor_step  = _m.sel_step;
        keyboard_clear(vk_right);
        keyboard_clear(vk_left);
        keyboard_clear(vk_tab);
        return;
    }

    // ── MOVE ── held Up / Down repeat after the same delay as the voice grid
    // (a third of a second, then every 2 frames).
    var _moved = false;
    var _nav_delay = round(game_get_speed(gamespeed_fps) * 0.33);
    if (keyboard_check(vk_up)) {
        var _up_go = false;
        if (keyboard_check_pressed(vk_up)) {
            _up_go = true;
            _m.nav_up_timer = _nav_delay;
        } else {
            _m.nav_up_timer -= 1;
            if (_m.nav_up_timer <= 0) {
                _up_go = true;
                _m.nav_up_timer = 2;
            }
        }
        if (_up_go) {
            _m.dg_sel_step = max(0, _m.dg_sel_step - 1);
            _moved = true;
        }
    } else {
        _m.nav_up_timer = 0;
    }
    if (keyboard_check(vk_down)) {
        var _dn_go = false;
        if (keyboard_check_pressed(vk_down)) {
            _dn_go = true;
            _m.nav_down_timer = _nav_delay;
        } else {
            _m.nav_down_timer -= 1;
            if (_m.nav_down_timer <= 0) {
                _dn_go = true;
                _m.nav_down_timer = 2;
            }
        }
        if (_dn_go) {
            _m.dg_sel_step = min(_grid_len - 1, _m.dg_sel_step + 1);
            _moved = true;
        }
    } else {
        _m.nav_down_timer = 0;
    }
    if (keyboard_check_pressed(vk_home)) {
        _m.dg_sel_step = 0;
        _moved = true;
    }
    if (_moved) {
        _m.dg_cmd_on  = false;
        _m.dg_cmd_buf = "";
    }
    if (_moved && !_shift) {
        _m.dg_anchor = _m.dg_sel_step;
    }
    if (_moved) {
        scr_digi_scroll_to_cursor(_m, _vis);
    }

    var _has_pat = (_order_row.dg >= 0 && _order_row.dg < array_length(_m.digi_patterns));
    var _lo = min(_m.dg_anchor, _m.dg_sel_step);
    var _hi = max(_m.dg_anchor, _m.dg_sel_step);

    // ── COPY / CUT / PASTE ──
    if (_ctrl && (keyboard_check_pressed(ord("C")) || keyboard_check_pressed(ord("X")))) {
        if (!_has_pat) {
            return;
        }
        var _pat_c = _m.digi_patterns[_order_row.dg];
        var _rows = [];
        for (var _r = _lo; _r <= _hi; _r++) {
            if (_r < _pat_c.pattern_len) {
                var _s = _pat_c.steps[_r];
                array_push(_rows, { smp: _s.smp, vol: _s.vol, note: _s.note, spd: _s.spd });
            }
        }
        global.se_dg_clipboard = _rows;
        if (keyboard_check_pressed(ord("X"))) {
            scr_digi_push_undo(_m, _pushf, _snapf);
            for (var _r = _lo; _r <= _hi && _r < _pat_c.pattern_len; _r++) {
                var _b = scr_digi_step_blank();
                _pat_c.steps[_r].smp  = _b.smp;
                _pat_c.steps[_r].vol  = _b.vol;
                _pat_c.steps[_r].note = _b.note;
                _pat_c.steps[_r].spd  = _b.spd;
            }
            global.undo_dirty = true;
            _m.warn_msg = "CUT " + string(array_length(_rows)) + " DIGI ROWS";
        } else {
            _m.warn_msg = "COPIED " + string(array_length(_rows)) + " DIGI ROWS";
        }
        _m.warn_timer = game_get_speed(gamespeed_fps) * 2;
        return;
    }
    if (_ctrl && keyboard_check_pressed(ord("V"))) {
        if (array_length(global.se_dg_clipboard) == 0) {
            return;
        }
        scr_digi_push_undo(_m, _pushf, _snapf);
        if (!_has_pat) {
            var _npv = scr_digi_pattern_new(_m, max(4, min(128, _grid_len)));
            if (_npv < 0) {
                return;
            }
            _order_row.dg = _npv;
        }
        var _pat_v = _m.digi_patterns[_order_row.dg];
        var _cb = global.se_dg_clipboard;
        for (var _i = 0; _i < array_length(_cb); _i++) {
            var _dst = _m.dg_sel_step + _i;
            if (_dst >= _pat_v.pattern_len) {
                break;   // no auto-grow, like the voice grid
            }
            _pat_v.steps[_dst].smp  = _cb[_i].smp;
            _pat_v.steps[_dst].vol  = _cb[_i].vol;
            _pat_v.steps[_dst].note = _cb[_i].note;
            _pat_v.steps[_dst].spd  = _cb[_i].spd;
        }
        global.undo_dirty = true;
        _m.warn_msg   = "PASTED " + string(array_length(_cb)) + " DIGI ROWS";
        _m.warn_timer = game_get_speed(gamespeed_fps) * 2;
        return;
    }
    if (_ctrl) {
        return;   // no Ctrl chords below
    }

    // ── SPEED COMMAND ── F, then two hex digits. Piano keys are off while
    // it is being typed (A-E and the digits are both).
    if (_m.dg_cmd_on) {
        var _hex = "0123456789ABCDEF";
        for (var _hk = 1; _hk <= 16; _hk++) {
            if (keyboard_check_pressed(ord(string_char_at(_hex, _hk)))) {
                _m.dg_cmd_buf += string_char_at(_hex, _hk);
                break;
            }
        }
        if (string_length(_m.dg_cmd_buf) >= 2) {
            var _cval = (string_pos(string_char_at(_m.dg_cmd_buf, 1), _hex) - 1) * 16
                      + (string_pos(string_char_at(_m.dg_cmd_buf, 2), _hex) - 1);
            _m.dg_cmd_on  = false;
            _m.dg_cmd_buf = "";
            scr_digi_push_undo(_m, _pushf, _snapf);
            if (_order_row.dg < 0 || _order_row.dg >= array_length(_m.digi_patterns)) {
                var _npc = scr_digi_pattern_new(_m, max(4, min(128, _grid_len)));
                if (_npc < 0) {
                    return;
                }
                _order_row.dg = _npc;
            }
            var _pat_f = _m.digi_patterns[_order_row.dg];
            if (_m.dg_sel_step < _pat_f.pattern_len) {
                var _code = min(_cval, DIGI_SPD_MAX);
                if (_cval == 0) {
                    _code = DIGI_SPD_SONG;
                }
                _pat_f.steps[_m.dg_sel_step].spd = _code;
                _m.dg_sel_step = min(_grid_len - 1, _m.dg_sel_step + 1);
                _m.dg_anchor   = _m.dg_sel_step;
                scr_digi_scroll_to_cursor(_m, _vis);
            }
            global.undo_dirty = true;
        }
        return;
    }
    if (_m.dg_sel_sub == 1) {
        // Command column: F starts a command, Del / Backspace clears it.
        // Piano keys don't type here, like a voice's command column.
        if (keyboard_check_pressed(ord("F"))) {
            _m.dg_cmd_on  = true;
            _m.dg_cmd_buf = "";
        }
        if (keyboard_check_pressed(vk_delete) || keyboard_check_pressed(vk_backspace)) {
            if (_order_row.dg >= 0 && _order_row.dg < array_length(_m.digi_patterns)) {
                scr_digi_push_undo(_m, _pushf, _snapf);
                var _pat_d = _m.digi_patterns[_order_row.dg];
                for (var _rd = _lo; _rd <= _hi && _rd < _pat_d.pattern_len; _rd++) {
                    _pat_d.steps[_rd].spd = 0;
                }
                global.undo_dirty = true;
            }
        }
        return;
    }

    // ── ENTRY ──
    var _pk_map = [
        [ord("Z"),  0, -1], [ord("S"),  1, -1], [ord("X"),  2, -1],
        [ord("D"),  3, -1], [ord("C"),  4, -1], [ord("V"),  5, -1],
        [ord("G"),  6, -1], [ord("B"),  7, -1], [ord("H"),  8, -1],
        [ord("N"),  9, -1], [ord("J"), 10, -1], [ord("M"), 11, -1],
        [ord("Q"),  0,  0], [ord("2"),  1,  0], [ord("W"),  2,  0],
        [ord("3"),  3,  0], [ord("E"),  4,  0], [ord("R"),  5,  0],
        [ord("5"),  6,  0], [ord("T"),  7,  0], [ord("6"),  8,  0],
        [ord("Y"),  9,  0], [ord("7"), 10,  0], [ord("U"), 11,  0],
        [ord("I"),  0,  1], [ord("9"),  1,  1], [ord("O"),  2,  1],
        [ord("0"),  3,  1], [ord("P"),  4,  1]
    ];
    var _note = -1;
    for (var _k = 0; _k < array_length(_pk_map); _k++) {
        if (keyboard_check_pressed(_pk_map[_k][0])) {
            _note = clamp((_m.cur_octave + _pk_map[_k][2]) * 12 + _pk_map[_k][1], 0, 95);
        }
    }
    var _slot_dn  = keyboard_check_pressed(0xBC);   // ','
    var _slot_up  = keyboard_check_pressed(0xBE);   // '.'
    var _want_off = keyboard_check_pressed(189) || keyboard_check_pressed(vk_subtract);
    var _want_clr = keyboard_check_pressed(vk_delete) || keyboard_check_pressed(vk_backspace);
    var _vol_dn   = keyboard_check_pressed(0xDB);   // '['
    var _vol_up   = keyboard_check_pressed(0xDD);   // ']'

    if (_slot_dn) {
        _m.dg_cur_slot = max(0, _m.dg_cur_slot - 1);
    }
    if (_slot_up) {
        _m.dg_cur_slot = min(DIGI_SLOTS - 1, _m.dg_cur_slot + 1);
    }
    if (_note < 0 && !_want_off && !_want_clr && !_vol_dn && !_vol_up && !_slot_dn && !_slot_up) {
        return;
    }

    if (!_has_pat) {
        if (_note < 0 && !_want_off) {
            return;
        }
        scr_digi_push_undo(_m, _pushf, _snapf);
        var _np = scr_digi_pattern_new(_m, max(4, min(128, _grid_len)));
        if (_np < 0) {
            return;
        }
        _order_row.dg = _np;
    } else {
        scr_digi_push_undo(_m, _pushf, _snapf);
    }
    var _pat = _m.digi_patterns[_order_row.dg];

    // Volume, clear and slot changes act on the whole selection.
    if (_want_clr || _vol_dn || _vol_up || _slot_dn || _slot_up) {
        for (var _r = _lo; _r <= _hi && _r < _pat.pattern_len; _r++) {
            var _cs = _pat.steps[_r];
            if (_want_clr) {
                var _bl = scr_digi_step_blank();
                _cs.smp  = _bl.smp;
                _cs.vol  = _bl.vol;
                _cs.note = _bl.note;
                _cs.spd  = _bl.spd;
            }
            if (_cs.smp >= 0) {
                if (_vol_dn) {
                    _cs.vol = max(0, _cs.vol - 1);
                }
                if (_vol_up) {
                    _cs.vol = min(3, _cs.vol + 1);
                }
                if (_slot_dn || _slot_up) {
                    _cs.smp = _m.dg_cur_slot;
                }
            }
        }
    }
    if (_m.dg_sel_step < _pat.pattern_len && (_note >= 0 || _want_off)) {
        var _st = _pat.steps[_m.dg_sel_step];
        if (_want_off) {
            _st.smp = DIGI_SMP_OFF;
        } else {
            _st.smp  = _m.dg_cur_slot;
            _st.note = _note;
        }
        // Audition, then step down a row like note entry in the voice grid.
        scr_digi_play_step(_m, _st);
        _m.dg_sel_step = min(_grid_len - 1, _m.dg_sel_step + 1);
        _m.dg_anchor   = _m.dg_sel_step;
        scr_digi_scroll_to_cursor(_m, _vis);
    }
    global.undo_dirty = true;
}

// ═══════════════════════════ SAMPLE SLOTS PANEL ═══════════════════════════

/// Panel rect for this frame, computed from the lane position. The editor
/// uses last frame's rect to hide the mouse from controls under the panel.
function scr_digi_slots_rect(_lane_x, _lane_w, _gy0) {
    var _w = 330;
    var _h = 106 + DIGI_SLOTS * 20 + 58;
    var _x1 = _lane_x + _lane_w - _w;
    var _y1 = _gy0 - 2;    // just under the SAMPLES button
    return [_x1, _y1, _x1 + _w, _y1 + _h];
}

/// Slot assignments + digi rate. Left-click a slot cycles through the
/// project's SAMPLE assets, right-click empties it, the play button auditions.
function scr_digi_slots_panel(_m, _rect, _mx, _my) {
    var _x1 = _rect[0];
    var _y1 = _rect[1];
    var _x2 = _rect[2];
    var _y2 = _rect[3];
    draw_set_color(make_color_rgb(16, 14, 24));
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_color(make_color_rgb(255, 130, 170));
    draw_rectangle(_x1, _y1, _x2, _y2, true);
    draw_set_font_l(fnt_c64_tiny);

    scr_digi_text_fit(_x1 + 10, _y1 + 8, "DIGI SAMPLES", _x2 - (_x1 + 10) - 8);
    var _cx = _x2 - 22;
    var _chov = point_in_rectangle(_mx, _my, _cx, _y1 + 4, _cx + 16, _y1 + 20);
    scr_mm_info(_chov, "CLOSES THE DIGI SAMPLES PANEL");
    draw_set_color(c_ltgray);
    if (_chov) {
        draw_set_color(c_white);
    }
    draw_text_l(_cx + 3, _y1 + 8, "X");
    if (_chov && mouse_check_button_pressed(mb_left)) {
        _m.dg_slots_open = false;
    }

    // RATE
    var _ry = _y1 + 26;
    draw_set_color(make_color_rgb(140, 150, 180));
    scr_digi_text_fit(_x1 + 10, _ry, "RATE", _x2 - (_x1 + 10) - 8);
    var _rates = scr_sample_rate_presets();
    var _ri = 0;
    var _best = 1000000;
    for (var _i = 0; _i < array_length(_rates); _i++) {
        if (abs(_rates[_i] - _m.digi_rate) < _best) {
            _best = abs(_rates[_i] - _m.digi_rate);
            _ri = _i;
        }
    }
    scr_mm_info(point_in_rectangle(_mx, _my, _x1 + 60, _ry - 4, _x1 + 78, _ry + 12), "DIGI SAMPLE RATE: ONE PRESET LOWER (SMALLER SAMPLES, LESS CPU)");
    if (scr_sample_button(_x1 + 60, _ry - 4, 18, 16, "<", false, (_ri > 0), _mx, _my)) {
        _m.digi_rate = _rates[_ri - 1];
        global.undo_dirty = true;
    }
    draw_set_color(c_white);
    scr_digi_text_fit(_x1 + 86, _ry, string(_m.digi_rate) + " HZ", _x2 - (_x1 + 86) - 8);
    scr_mm_info(point_in_rectangle(_mx, _my, _x1 + 160, _ry - 4, _x1 + 178, _ry + 12), "DIGI SAMPLE RATE: ONE PRESET HIGHER (BETTER SOUND, BIGGER, MORE CPU)");
    if (scr_sample_button(_x1 + 160, _ry - 4, 18, 16, ">", false, (_ri < array_length(_rates) - 1), _mx, _my)) {
        _m.digi_rate = _rates[_ri + 1];
        global.undo_dirty = true;
    }
    draw_set_color(make_color_rgb(95, 95, 115));
    scr_digi_text_fit(_x1 + 190, _ry, "= NOTE C-4", _x2 - (_x1 + 190) - 8);

    // BOOST: a voice held at full DC so the volume register has something to
    // scale — needed on the 8580, louder on the 6581. That voice stops
    // playing the music's notes in the compiled tune.
    var _by = _ry + 22;
    draw_set_color(make_color_rgb(140, 150, 180));
    scr_digi_text_fit(_x1 + 10, _by, "BOOST", _x2 - (_x1 + 10) - 8);
    var _bnames = ["OFF", "V1", "V2", "V3"];
    for (var _bi = 0; _bi < 4; _bi++) {
        scr_mm_info(point_in_rectangle(_mx, _my, _x1 + 60 + _bi * 40, _by - 4, _x1 + 96 + _bi * 40, _by + 12), (_bi == 0) ? "BOOST OFF: NO VOICE IS USED TO MAKE DIGIS LOUDER" : "BOOST: HOLDS VOICE " + string(_bi) + " AT FULL DC SO DIGIS ARE LOUDER; IT IS MUTED ON THE C64");
        if (scr_sample_button(_x1 + 60 + _bi * 40, _by - 4, 36, 16, _bnames[_bi], (_m.digi_boost == _bi), true, _mx, _my)) {
            _m.digi_boost = _bi;
            global.undo_dirty = true;
            global.addresses_dirty = true;
        }
    }
    draw_set_color(make_color_rgb(95, 95, 115));
    if (_m.digi_boost > 0) {
        draw_set_color(make_color_rgb(255, 160, 60));
        scr_digi_text_fit(_x1 + 224, _by, "V" + string(_m.digi_boost) + " MUTED ON C64", _x2 - (_x1 + 224) - 8);
    } else {
        scr_digi_text_fit(_x1 + 224, _by, "8580 NEEDS ONE", _x2 - (_x1 + 224) - 8);
    }

    // SPEED: frames per digi row. SONG = the digi rows go with the song's rows;
    // a number gives the digi lane its own tempo, restarted on every order row.
    var _spy = _by + 22;
    draw_set_color(make_color_rgb(140, 150, 180));
    scr_digi_text_fit(_x1 + 10, _spy, "SPEED", _x2 - (_x1 + 10) - 8);
    scr_mm_info(point_in_rectangle(_mx, _my, _x1 + 60, _spy - 4, _x1 + 78, _spy + 12), "DIGI SPEED: ONE FRAME PER DIGI ROW LESS (0 = GO WITH THE SONG ROWS)");
    if (scr_sample_button(_x1 + 60, _spy - 4, 18, 16, "<", false, (_m.digi_speed > 0), _mx, _my)) {
        _m.digi_speed -= 1;
        global.undo_dirty = true;
        global.addresses_dirty = true;
    }
    draw_set_color(c_white);
    if (_m.digi_speed == 0) {
        scr_digi_text_fit(_x1 + 86, _spy, "SONG", _x2 - (_x1 + 86) - 8);
    } else {
        scr_digi_text_fit(_x1 + 86, _spy, string(_m.digi_speed) + " FR", _x2 - (_x1 + 86) - 8);
    }
    scr_mm_info(point_in_rectangle(_mx, _my, _x1 + 160, _spy - 4, _x1 + 178, _spy + 12), "DIGI SPEED: ONE FRAME PER DIGI ROW MORE (OWN TEMPO, UP TO 31)");
    if (scr_sample_button(_x1 + 160, _spy - 4, 18, 16, ">", false, (_m.digi_speed < 31), _mx, _my)) {
        _m.digi_speed += 1;
        global.undo_dirty = true;
        global.addresses_dirty = true;
    }
    draw_set_color(make_color_rgb(95, 95, 115));
    if (_m.digi_speed > 0) {
        scr_digi_text_fit(_x1 + 190, _spy, "START SPEED", _x2 - (_x1 + 190) - 8);
    } else {
        scr_digi_text_fit(_x1 + 190, _spy, "= SONG ROWS", _x2 - (_x1 + 190) - 8);
    }
    scr_digi_text_fit(_x1 + 10, _spy + 14, "IN THE LANE: F01-F1F SPEED, F00 SONG ROWS", _x2 - (_x1 + 10) - 8);

    // SLOTS
    var _names = scr_digi_sample_names();
    for (var _s = 0; _s < DIGI_SLOTS; _s++) {
        var _sy = _y1 + 106 + _s * 20;
        var _num = string(_s);
        if (_s < 10) {
            _num = "0" + _num;
        }
        // The slot number picks the CURRENT slot: what note entry places.
        var _nhov = point_in_rectangle(_mx, _my, _x1 + 4, _sy, _x1 + 32, _sy + 17);
        scr_mm_info(_nhov, "MAKES SLOT " + _num + " THE CURRENT SLOT (WHAT NOTE ENTRY PLACES)");
        if (_s == _m.dg_cur_slot) {
            draw_set_color(make_color_rgb(190, 70, 120));
            draw_rectangle(_x1 + 4, _sy, _x1 + 32, _sy + 17, false);
        }
        draw_set_color(make_color_rgb(255, 130, 170));
        if (_s == _m.dg_cur_slot || _nhov) {
            draw_set_color(c_white);
        }
        scr_digi_text_fit(_x1 + 10, _sy + 3, _num, _x2 - (_x1 + 10) - 8);
        if (_nhov && mouse_check_button_pressed(mb_left)) {
            _m.dg_cur_slot = _s;
        }

        var _bx1 = _x1 + 36;
        var _bx2 = _x2 - 40;
        var _hov = point_in_rectangle(_mx, _my, _bx1, _sy, _bx2, _sy + 17);
        scr_mm_info(_hov, "SLOT " + _num + ": CLICK PICKS THE NEXT SAMPLE ASSET, RMB EMPTIES THE SLOT");
        draw_set_color(make_color_rgb(30, 28, 44));
        if (_hov) {
            draw_set_color(make_color_rgb(56, 50, 80));
        }
        draw_rectangle(_bx1, _sy, _bx2, _sy + 17, false);
        var _nm = _m.digi_samples[_s];
        var _a = scr_digi_find_sample(_nm);
        if (_nm == "") {
            draw_set_color(make_color_rgb(90, 90, 110));
            draw_text_l(_bx1 + 6, _sy + 3, "-- EMPTY --");
        } else if (is_undefined(_a)) {
            draw_set_color(make_color_rgb(220, 100, 80));
            draw_text_l(_bx1 + 6, _sy + 3, _nm + "  (MISSING)");
        } else {
            draw_set_color(c_white);
            var _cnt = scr_digi_sample_count(_a, _m.digi_rate);
            var _bytes = ceil(_cnt / 2);
            if (_a.meta.pack == 1) {
                _bytes = ceil(_cnt / 4);
            }
            var _info = _nm + "   " + scr_sample_secs(_cnt, _m.digi_rate) + "   " + string(_bytes) + " B";
            draw_text_l(_bx1 + 6, _sy + 3, _info);
        }
        if (_hov && mouse_check_button_pressed(mb_left)) {
            // Cycle: empty -> first sample -> ... -> last -> empty
            var _next = "";
            if (array_length(_names) > 0) {
                var _at = -1;
                for (var _ni = 0; _ni < array_length(_names); _ni++) {
                    if (_names[_ni] == _nm) {
                        _at = _ni;
                    }
                }
                if (_at + 1 < array_length(_names)) {
                    _next = _names[_at + 1];
                }
            }
            _m.digi_samples[_s] = _next;
            global.undo_dirty = true;
            if (_next != "") {
                scr_digi_check_warn_once(_m);
            }
        }
        if (_hov && mouse_check_button_pressed(mb_right)) {
            _m.digi_samples[_s] = "";
            global.undo_dirty = true;
        }
        if (!is_undefined(_a)) {
            scr_mm_info(point_in_rectangle(_mx, _my, _x2 - 34, _sy, _x2 - 10, _sy + 17), "PLAYS THIS SLOT'S SAMPLE AT ITS OWN PITCH");
            if (scr_sample_button(_x2 - 34, _sy, 24, 17, ">", false, true, _mx, _my)) {
                // Slot preview: play at the sample's own pitch
                scr_digi_play_step(_m, { smp: _s, vol: 3, note: DIGI_NOTE_BASE });
            }
        }
    }
    draw_set_color(make_color_rgb(95, 95, 115));
    scr_digi_text_fit(_x1 + 10, _y2 - 50, "NUMBER: CURRENT SLOT   BAR: NEXT SAMPLE   RMB: EMPTY", _x2 - (_x1 + 10) - 8);
    // Each sample costs one NMI; the estimate is for while a digi plays.
    var _cpu = round(_m.digi_rate * DIGI_NMI_CYCLES / SAMPLE_PAL_CLOCK * 100);
    draw_set_color(make_color_rgb(140, 150, 180));
    if (_cpu > 45) {
        draw_set_color(make_color_rgb(255, 160, 60));
    }
    scr_digi_text_fit(_x1 + 10, _y2 - 34, "CPU WHILE A DIGI PLAYS: ~" + string(_cpu) + "%  (EACH NOTE USED = OWN COPY)", _x2 - (_x1 + 10) - 8);
    // PROJECT CHECK: does this project leave room for samples? Hover for advice.
    var _chk = scr_digi_project_check(_m);
    var _worst = 0;
    for (var _ci = 0; _ci < array_length(_chk); _ci++) {
        _worst = max(_worst, _chk[_ci].lvl);
    }
    var _chk_hov = point_in_rectangle(_mx, _my, _x1 + 4, _y2 - 20, _x2 - 4, _y2 - 4);
    scr_mm_info(_chk_hov, "PROJECT CHECK: WHETHER THIS PROJECT LEAVES ROOM FOR SAMPLES (HOVER FOR ADVICE)");
    if (_worst == 0) {
        draw_set_color(make_color_rgb(120, 200, 120));
        scr_digi_text_fit(_x1 + 10, _y2 - 18, "PROJECT CHECK: OK FOR SAMPLES", _x2 - (_x1 + 10) - 8);
    } else {
        draw_set_color(make_color_rgb(255, 170, 70));
        if (_worst == 2) {
            draw_set_color(make_color_rgb(255, 100, 80));
        }
        scr_digi_text_fit(_x1 + 10, _y2 - 18, "PROJECT CHECK: " + string(array_length(_chk)) + " ISSUE(S) - HOVER FOR ADVICE", _x2 - (_x1 + 10) - 8);
        if (_chk_hov) {
            scr_digi_check_draw_advice(_chk, _x1, _y2 - 22);
        }
    }
}

/// Draws _s at _x,_y, scaled down (never up) so it fits in _maxw pixels. The
/// panel's texts use it so a long line can't run past the panel's edge.
function scr_digi_text_fit(_x, _y, _s, _maxw) {
    var _w = string_width_l(_s);
    var _sc = 1;
    if (_w > _maxw && _w > 0) {
        _sc = _maxw / _w;
    }
    draw_text_transformed_l(_x, _y, _s, _sc, _sc, 0);
}

/// Things in this project that make samples a bad fit, each with plain advice.
/// Returns an array of { lvl, msg, fix }: lvl 1 = not recommended,
/// lvl 2 = won't work as it is.
function scr_digi_project_check(_m) {
    var _out = [];
    // 1. Timing
    if (_m.free_voices) {
        array_push(_out, { lvl: 2,
            msg: "THIS SONG USES TIMING: PER VOICE. THE DIGI TRACK IS ONLY BUILT WHEN ALL THREE VOICES SHARE ONE ROW CLOCK, SO SAMPLES PLAY IN THE EDITOR BUT ARE SILENT ON THE C64.",
            fix: "SET TIMING TO SHARED IF THE VOICES CAN RUN AT THE SAME SPEED, OR LEAVE SAMPLES OUT OF THIS SONG." });
    }
    // 2. CPU: the player interrupts the program once for every sample
    var _cpu = round(_m.digi_rate * DIGI_NMI_CYCLES / SAMPLE_PAL_CLOCK * 100);
    if (_cpu > 60) {
        var _lvl_cpu = 1;
        if (_cpu > 90) {
            _lvl_cpu = 2;
        }
        array_push(_out, { lvl: _lvl_cpu,
            msg: "AT " + string(_m.digi_rate) + " HZ THE SAMPLE PLAYER USES ABOUT " + string(_cpu) + "% OF THE CPU WHILE A SAMPLE PLAYS: IT STOPS THE PROGRAM ONCE FOR EVERY SAMPLE (AN NMI), SO THE GAME AND MUSIC GET WHAT IS LEFT.",
            fix: "LOWER THE RATE IN THIS PANEL - 4000 TO 5000 HZ USES ABOUT 52-64% AND IS FINE FOR DRUMS AND SPEECH. IF THE GAME STILL SLOWS DOWN, DO LESS WORK PER FRAME WHILE SAMPLES PLAY." });
    }
    // 3. Code timed to the screen (raster waits / border tricks)
    var _raster = false;
    with (obj_c64_node) {
        if (!is_connected || array_length(instructions) == 0) {
            continue;
        }
        if (node_type == "MACRO_CODE" && is_string(instructions[0][1])) {
            if (string_pos("$d012", string_lower(instructions[0][1])) > 0) {
                _raster = true;
            }
        }
        if (string_pos("IRQ", node_type) > 0) {
            _raster = true;
        }
    }
    if (_raster) {
        array_push(_out, { lvl: 1,
            msg: "THIS PROJECT TIMES CODE TO THE SCREEN (IT WAITS FOR RASTER LINES OR USES RASTER INTERRUPTS). THE SAMPLE NMI CANNOT BE SWITCHED OFF WITH SEI, SO IT CAN DELAY THAT CODE BY UP TO ABOUT 2 RASTER LINES (ONE LINE = 63 CPU CYCLES) - SPLITS AND BORDER TRICKS MAY FLICKER.",
            fix: "GIVE TIMED CODE SOME SLACK: START WAITING A LINE OR TWO EARLIER (E.G. OPEN THE BORDER AT LINE 248 INSTEAD OF 249), OR ONLY PLAY SAMPLES IN PARTS OF THE GAME WITHOUT RASTER EFFECTS." });
    }
    // 4. Memory after the music block
    var _mem = scr_digi_check_memory(_m);
    if (!is_undefined(_mem)) {
        array_push(_out, _mem);
    }
    return _out;
}

/// Room after this song's SID SONG node, up to the next ORG or placed asset.
/// Samples are stored inside the music block, so that gap is all they get.
function scr_digi_check_memory(_m) {
    if (_m.dg_asset_name == "") {
        return undefined;
    }
    var _end = -1;
    var _nm = _m.dg_asset_name;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID_SONG" && array_length(instructions) > 0
        && instructions[0][1] == _nm && end_address > pc_address) {
            _end = end_address;
        }
    }
    if (_end < 0) {
        return undefined;    // not placed / not built yet
    }
    var _next = 0x10000;
    var _next_name = "";
    with (obj_c64_node) {
        if (node_type == "ORG" && pc_address >= _end && pc_address < _next) {
            _next = pc_address;
            _next_name = code_descriptor;
        }
    }
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.address > 0 && _a.address >= _end && _a.address < _next) {
            _next = _a.address;
            _next_name = _a.name;
        }
    }
    if (_next >= 0xA000 && _end < 0xA000) {
        _next = 0xA000;
        _next_name = "BASIC ROM AREA";
    }
    var _gap = _next - _end;
    // Bytes the assigned samples need at this rate (one note each).
    var _need = 0;
    for (var _s = 0; _s < array_length(_m.digi_samples); _s++) {
        var _sa = scr_digi_find_sample(_m.digi_samples[_s]);
        if (!is_undefined(_sa)) {
            var _cnt = scr_digi_sample_count(_sa, _m.digi_rate);
            if (_sa.meta.pack == 1) {
                _need += ceil(_cnt / 4);
            } else {
                _need += ceil(_cnt / 2);
            }
        }
    }
    var _lvl = 0;
    if (_gap < 2048) {
        _lvl = 1;
    }
    if (_m.free_voices && _need > _gap) {
        _lvl = 2;            // not built yet, and would not fit
    }
    if (_gap < 0) {
        _lvl = 2;
    }
    if (_lvl == 0) {
        return undefined;
    }
    var _hex = string_upper(decimal_to_hex(_next));
    while (string_length(_hex) < 4) {
        _hex = "0" + _hex;
    }
    return { lvl: _lvl,
        msg: "ONLY " + string(max(0, _gap)) + " BYTES ARE FREE AFTER THE MUSIC BLOCK (UP TO " + _next_name + " AT $" + _hex + "). SAMPLES ARE STORED INSIDE THE MUSIC BLOCK: ABOUT " + string(_m.digi_rate div 2) + " BYTES A SECOND (4-BIT) OR " + string(_m.digi_rate div 4) + " (2-BIT), AND EVERY OTHER NOTE USED IS ANOTHER COPY. THE SAMPLES IN THE SLOTS NEED ABOUT " + string(_need) + " BYTES.",
        fix: "USE SHORT SAMPLES, 2-BIT PACKING, ONE NOTE PER SAMPLE AND A LOWER RATE - OR MOVE THE MUSIC'S ORG TO A BIGGER FREE AREA (THE MEMORY BAR SHOWS WHAT IS FREE)." };
}

/// Advice box for the project check, drawn upward from _y.
function scr_digi_check_draw_advice(_chk, _x, _y) {
    var _txt = "";
    for (var _i = 0; _i < array_length(_chk); _i++) {
        if (_i > 0) {
            _txt += "\n\n";
        }
        var _tag = "NOT RECOMMENDED: ";
        if (_chk[_i].lvl == 2) {
            _tag = "WON'T WORK AS IT IS: ";
        }
        _txt += _tag + _chk[_i].msg + "\nWHAT TO DO: " + _chk[_i].fix;
    }
    draw_set_font_l(fnt_c64_tiny);
    var _w = 520;
    var _h = string_height_ext_l(_txt, 14, _w - 16) + 16;
    var _x2 = _x + _w;
    var _y1 = _y - _h;
    draw_set_color(make_color_rgb(24, 18, 28));
    draw_rectangle(_x, _y1, _x2, _y, false);
    draw_set_color(make_color_rgb(255, 170, 70));
    draw_rectangle(_x, _y1, _x2, _y, true);
    draw_set_color(c_white);
    draw_text_ext_l(_x + 8, _y1 + 8, _txt, 14, _w - 16);
}

/// Shown once per editor session, the first time a sample goes into a slot
/// while the project check has something to say.
function scr_digi_check_warn_once(_m) {
    if (_m.dg_check_shown) {
        return;
    }
    var _chk = scr_digi_project_check(_m);
    if (array_length(_chk) == 0) {
        return;
    }
    _m.dg_check_shown = true;
    var _txt = "SAMPLES ARE NOT RECOMMENDED FOR THIS PROJECT AS IT IS:";
    for (var _i = 0; _i < array_length(_chk); _i++) {
        _txt += "\n\n- " + _chk[_i].msg + "\n  WHAT TO DO: " + _chk[_i].fix;
    }
    _txt += "\n\n(THE DIGI SAMPLES PANEL SHOWS THIS AGAIN: HOVER 'PROJECT CHECK'.)";
    scr_show_message(_txt);
}

/// How many C64 samples _asset becomes at _rate (no encode needed).
function scr_digi_sample_count(_asset, _rate) {
    var _sm = _asset.meta;
    if (_sm.src_len <= 1 || _sm.src_rate <= 0) {
        return 0;
    }
    return max(0, floor((_sm.trim_end - _sm.trim_start) * _rate / _sm.src_rate));
}
