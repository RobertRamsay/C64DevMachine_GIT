/// @function scr_sound_editor_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my)
/// @desc Inline editor for SOUND_EDITOR assets.
///
/// PATTERNS ARE SINGLE-LANE. The song order table (right panel) assigns a
/// pattern index to each of the 3 voice columns for the currently selected
/// order row — the LEFT grid always shows and edits whichever patterns that
/// row currently points at. Two columns pointing at the same pattern index
/// show and edit THE SAME DATA, since they're literally the same object.
///
/// Space loops the CURRENT ORDER ROW indefinitely (quick audition).
/// Ctrl+Space plays the whole song, walking every order row once, honouring
/// each row's Rs/NRs + Force Length settings.
function scr_sound_editor_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _m = _asset.meta;

    // ── BACKFILL ──
    if (!variable_struct_exists(_m, "instruments"))  _m.instruments = [];
    if (!variable_struct_exists(_m, "sel_instr"))    _m.sel_instr   = -1;

    // Old triplet-shaped patterns (if any exist from a prior session) don't
    // match the new single-lane shape — detect and reset rather than crash
    // on a missing "steps" field. This discards old pattern data on
    // migration; acceptable during active development.
    var _pat_needs_reset = (!variable_struct_exists(_m, "patterns") || !is_array(_m.patterns) || array_length(_m.patterns) == 0);
    if (!_pat_needs_reset && !variable_struct_exists(_m.patterns[0], "steps")) {
        _pat_needs_reset = true;
    }
    if (_pat_needs_reset) {
        _m.patterns = [
            { name: "PATTERN 00", steps: [], pattern_len: 64 },
            { name: "PATTERN 01", steps: [], pattern_len: 64 },
            { name: "PATTERN 02", steps: [], pattern_len: 64 }
        ];
    }
    if (!variable_struct_exists(_m, "bank_sel_pattern")) _m.bank_sel_pattern = 0;
    _m.bank_sel_pattern = clamp(_m.bank_sel_pattern, 0, array_length(_m.patterns) - 1);

    // ── SONGS MIGRATION ── an asset saved before songs[] existed has a bare
    // song_order/song_loop/song_loop_row triple. Fold it into songs[0] rather
    // than discarding it. The old fields are then left alone permanently —
    // nothing reads them again.
    if (!variable_struct_exists(_m, "songs") || !is_array(_m.songs) || array_length(_m.songs) == 0) {
        var _mig_order = [];
        if (variable_struct_exists(_m, "song_order") && is_array(_m.song_order) && array_length(_m.song_order) > 0) {
            _mig_order = _m.song_order;
        } else {
            _mig_order = [
                { v1: 0, v2: min(1, array_length(_m.patterns) - 1), v3: min(2, array_length(_m.patterns) - 1),
                  repeat_short: false, force_len: 0 }
            ];
        }
        var _mig_loop = true;
        if (variable_struct_exists(_m, "song_loop")) {
            _mig_loop = _m.song_loop;
        }
        var _mig_loop_row = 0;
        if (variable_struct_exists(_m, "song_loop_row")) {
            _mig_loop_row = real(_m.song_loop_row);
        }
        _m.songs = [ { name: "SONG 00", order: _mig_order, loop: _mig_loop, loop_row: _mig_loop_row } ];
    }
    if (!variable_struct_exists(_m, "sel_song")) _m.sel_song = 0;
    _m.sel_song = clamp(_m.sel_song, 0, array_length(_m.songs) - 1);
    if (!variable_struct_exists(_m, "song_name_edit_active")) {
        _m.song_name_edit_active = false;
        _m.song_name_edit_buf    = "";
        _m.song_name_edit_cursor = 0;
    }

    // Per-song backfill — a song saved mid-development may be missing a field.
    for (var _sgi = 0; _sgi < array_length(_m.songs); _sgi++) {
        var _sg_bf = _m.songs[_sgi];
        if (!variable_struct_exists(_sg_bf, "name"))  _sg_bf.name  = "SONG " + string(_sgi);
        if (!variable_struct_exists(_sg_bf, "order") || !is_array(_sg_bf.order) || array_length(_sg_bf.order) == 0) {
            _sg_bf.order = [ { v1: 0, v2: -1, v3: -1, repeat_short: false, force_len: 0 } ];
        }
        if (!variable_struct_exists(_sg_bf, "loop"))     _sg_bf.loop     = true;
        if (!variable_struct_exists(_sg_bf, "loop_row")) _sg_bf.loop_row = 0;
        _sg_bf.loop_row = clamp(real(_sg_bf.loop_row), 0, array_length(_sg_bf.order) - 1);
    }

    // THE selected song. Everything below reads _cur_song.order directly —
    // there is no _m.song_order, deliberately (see scr_sound_editor_create).
    var _cur_song = _m.songs[_m.sel_song];

    if (!variable_struct_exists(_m, "sel_order_row")) _m.sel_order_row = 0;
    _m.sel_order_row = clamp(_m.sel_order_row, 0, array_length(_cur_song.order) - 1);
    if (!variable_struct_exists(_m, "order_scroll")) _m.order_scroll = 0;

    if (!variable_struct_exists(_m, "sel_voice"))   _m.sel_voice   = 0;
    if (!variable_struct_exists(_m, "sel_step"))    _m.sel_step    = 0;
    if (!variable_struct_exists(_m, "list_scroll")) _m.list_scroll = 0;
    if (!variable_struct_exists(_m, "undo_stack"))  _m.undo_stack  = [];
    if (!variable_struct_exists(_m, "redo_stack"))  _m.redo_stack  = [];
    if (!variable_struct_exists(_m, "warn_msg"))    _m.warn_msg    = "";
    if (!variable_struct_exists(_m, "warn_timer"))  _m.warn_timer  = 0;
    if (!variable_struct_exists(_m, "cur_octave"))  _m.cur_octave  = 4;
    if (!variable_struct_exists(_m, "instr_list_scroll"))      _m.instr_list_scroll      = 0;
    if (!variable_struct_exists(_m, "instr_edit_active")) {
        _m.instr_edit_active      = false;
        _m.instr_edit_buf         = "";
        _m.instr_edit_cursor      = 0;
        _m.instr_name_edit_active = false;
        _m.instr_name_edit_buf    = "";
        _m.instr_name_edit_cursor = 0;
    }
    if (!variable_struct_exists(_m, "instr_last_click_time")) {
        _m.instr_last_click_time = -10000;
        _m.instr_last_click_idx  = -1;
    }
    if (!variable_struct_exists(_m, "instr_name_edit_opened_time")) {
        _m.instr_name_edit_opened_time = -10000;
    }
    for (var _adbi = 0; _adbi < array_length(_m.instruments); _adbi++) {
        var _adb_instr = _m.instruments[_adbi];
        if (!variable_struct_exists(_adb_instr, "attack"))      _adb_instr.attack      = 0;
        if (!variable_struct_exists(_adb_instr, "decay"))       _adb_instr.decay       = 8;
        if (!variable_struct_exists(_adb_instr, "sustain"))     _adb_instr.sustain     = 8;
        if (!variable_struct_exists(_adb_instr, "release"))     _adb_instr.release     = 0;
        if (!variable_struct_exists(_adb_instr, "pulse_width")) _adb_instr.pulse_width = 2048; // $0800 (50% square)
    }

    // Row-audition playback (Space / Shift+Space) — loops the current order row
    if (!variable_struct_exists(_m, "playing"))     _m.playing     = false;
    if (!variable_struct_exists(_m, "play_row"))    _m.play_row    = 0;
    if (!variable_struct_exists(_m, "play_tick"))   _m.play_tick   = 0;
    if (!variable_struct_exists(_m, "play_speed"))  _m.play_speed  = 6;
    // 1 is frantic, 24 is a dirge; the emitter clamps to 1-255 anyway, but
    // there's no musical reason to go past this from the UI.
    _m.play_speed = clamp(real(_m.play_speed), 1, 24);

    // Full-song playback (Ctrl+Space)
    if (!variable_struct_exists(_m, "song_playing"))    _m.song_playing    = false;
    if (!variable_struct_exists(_m, "song_order_row"))  _m.song_order_row  = 0;
    if (!variable_struct_exists(_m, "song_master_row")) _m.song_master_row = 0;
    if (!variable_struct_exists(_m, "song_tick"))       _m.song_tick       = 0;

    if (!variable_struct_exists(_m, "nav_up_timer")) {
        _m.nav_up_timer   = 0;
        _m.nav_down_timer = 0;
        _m.bksp_timer     = 0;
        _m.ins_timer      = 0;
    }
    if (!variable_struct_exists(_m, "ins_timer")) {
        _m.ins_timer = 0;   // migration for assets saved before INSERT existed
    }
	
    if (!variable_struct_exists(_m, "last_click_time")) {
        _m.last_click_time  = -10000;
        _m.last_click_voice = -1;
        _m.last_click_step  = -1;
    }
    if (!variable_struct_exists(_m, "edit_active")) {
        _m.edit_active = false;
        _m.edit_voice  = 0;
        _m.edit_step   = 0;
        _m.edit_buf    = "";
        _m.edit_cursor = 0;
    }
    if (!variable_struct_exists(_m, "sel_anchor_voice")) {
        _m.sel_anchor_voice = _m.sel_voice;
        _m.sel_anchor_step  = _m.sel_step;
    }
    if (!variable_global_exists("se_clipboard")) {
        global.se_clipboard = noone;
    }

    // ── STEP-ARRAY SYNC ── grows/truncates a pattern's steps to match its own
    // pattern_len. Called on every pattern this frame actually touches.
    var _se_ensure_steps = function(_pat) {
        while (array_length(_pat.steps) < _pat.pattern_len) {
            array_push(_pat.steps, { instr_idx: -1, note: "", empty: true });
        }
        if (array_length(_pat.steps) > _pat.pattern_len) {
            array_resize(_pat.steps, _pat.pattern_len);
        }
    };

    // ── UNDO / REDO ── whole-patterns-array snapshot. Simpler and safer than
    // per-pattern snapshots now that one paste or edit can touch a pattern
    // shared across multiple voice columns.
    var _se_snap = function(_mm) {
        var _pats = [];
        for (var _pi = 0; _pi < array_length(_mm.patterns); _pi++) {
            var _src = _mm.patterns[_pi];
            var _steps = [];
            for (var _si = 0; _si < array_length(_src.steps); _si++) {
                var _st = _src.steps[_si];
                array_push(_steps, { instr_idx: _st.instr_idx, note: _st.note, empty: _st.empty });
            }
            array_push(_pats, { name: _src.name, steps: _steps, pattern_len: _src.pattern_len });
        }
        return _pats;
    };
    var _se_push_undo = function(_mm, _snapf) {
        array_push(_mm.undo_stack, _snapf(_mm));
        if (array_length(_mm.undo_stack) > 50) {
            array_delete(_mm.undo_stack, 0, 1);
        }
        _mm.redo_stack = [];
        // Every undo-able edit changes what MACRO_SID_SONG emits, and the node's
        // byte size is derived from this meta at compile time. Without this the
        // node keeps a stale size until something else triggers a recompute, and
        // every node downstream sits at the wrong address.
        global.addresses_dirty = true;
    };

    // ── RESOLVE THE 3 ACTIVE PATTERNS FOR THE CURRENT ORDER ROW ──
    var _order_row = _cur_song.order[_m.sel_order_row];
    var _col_pat_idx = [_order_row.v1, _order_row.v2, _order_row.v3];
    var _col_pat = [noone, noone, noone];
    for (var _cpi = 0; _cpi < 3; _cpi++) {
        if (_col_pat_idx[_cpi] >= 0 && _col_pat_idx[_cpi] < array_length(_m.patterns)) {
            _col_pat[_cpi] = _m.patterns[_col_pat_idx[_cpi]];
            _se_ensure_steps(_col_pat[_cpi]);
        }
    }

    // Grid shows rows up to the LONGEST active pattern; a column whose own
    // pattern is shorter shows dim "END" cells past its own length, and a
    // column with no pattern assigned shows "NO PATTERN" throughout.
    var _grid_len = 16;   // fallback if every column is unassigned
    for (var _gli = 0; _gli < 3; _gli++) {
        if (_col_pat[_gli] != noone) {
            _grid_len = max(_grid_len, _col_pat[_gli].pattern_len);
        }
    }

    var _se_row_target_len = function(_mm, _row) {
        // FORCE overrides outright when set — it's a hard row length, not a
        // minimum. Without it, the target is the longest pattern present.
        if (_row.force_len > 0) {
            return _row.force_len;
        }
        var _r_len = 0;
        var _voices = [_row.v1, _row.v2, _row.v3];
        for (var _vi = 0; _vi < 3; _vi++) {
            if (_voices[_vi] >= 0 && _voices[_vi] < array_length(_mm.patterns)) {
                _r_len = max(_r_len, _mm.patterns[_voices[_vi]].pattern_len);
            }
        }
        if (_r_len <= 0) {
            _r_len = 64;
        }
        return _r_len;
    };

    // ── LAYOUT ──
    var _txt_scale = 2;
    var _row_h    = 36;
    var _vis      = 16;
    var _lane_w   = 180;
    var _gutter_w = 60;
    var _lane_gap = 12;

    // ═════════════════════════════════════════════════════════════════════
    // PLAYBACK — ROW AUDITION (Space / Shift+Space, loops sel_order_row)
    // ═════════════════════════════════════════════════════════════════════
    if (!_m.edit_active) {
        if (keyboard_check_pressed(vk_space) && keyboard_check(vk_shift) && !(keyboard_check(vk_control) || scr_cmd_held())) {
            _m.playing      = true;
            _m.song_playing = false;
            _m.play_row     = 0;
            _m.play_tick    = 0;
        } else if (keyboard_check_pressed(vk_space) && (keyboard_check(vk_control) || scr_cmd_held())) {
            if (_m.song_playing) {
                _m.song_playing = false;
            } else {
                _m.playing         = false;
                _m.song_playing    = true;
                _m.song_order_row  = 0;
                _m.song_master_row = 0;
                _m.song_tick       = 0;
            }
        } else if (keyboard_check_pressed(vk_space)) {
            if (_m.playing) {
                _m.playing = false;
            } else {
                _m.playing      = true;
                _m.song_playing = false;
                _m.play_row     = _m.sel_step;
                _m.play_tick    = 0;
            }
        }
    }

    if (_m.playing) {
        var _pa_target = _se_row_target_len(_m, _order_row);
        if (_m.play_tick <= 0) {
            for (var _pv = 0; _pv < 3; _pv++) {
                if (_col_pat[_pv] == noone) {
                    continue;
                }
                var _pv_local = _order_row.repeat_short
                              ? (_m.play_row mod _col_pat[_pv].pattern_len)
                              : _m.play_row;
                if (_pv_local >= _col_pat[_pv].pattern_len) {
                    continue;   // NRs: this voice finished early, stays silent
                }
                var _p_step = _col_pat[_pv].steps[_pv_local];
                if (_p_step.empty) {
                    // Empty row — hold, same as the runtime's $FE.
                } else if (_p_step.note == "" || _p_step.note == "---") {
                    scr_sound_preview_free_channel(_pv);
                } else {
                    scr_sound_editor_play_step(_m, _p_step, _pv);
                }
            }
            if (_m.play_row < _m.list_scroll) {
                _m.list_scroll = _m.play_row;
            }
            if (_m.play_row >= _m.list_scroll + _vis) {
                _m.list_scroll = _m.play_row - _vis + 1;
            }
            _m.play_tick = _m.play_speed;
            _m.play_row += 1;
        } else {
            _m.play_tick -= 1;
        }
        if (_m.play_row >= _pa_target) {
            _m.play_row = 0;   // loops indefinitely — this IS the "audition" mode
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // PLAYBACK — FULL SONG (Ctrl+Space)
    // ═════════════════════════════════════════════════════════════════════
    if (_m.song_playing) {
        var _sp_row    = _cur_song.order[_m.song_order_row];
        var _sp_target = _se_row_target_len(_m, _sp_row);
        var _sp_voices = [_sp_row.v1, _sp_row.v2, _sp_row.v3];

        if (_m.song_tick <= 0) {
            for (var _sv = 0; _sv < 3; _sv++) {
                var _sv_idx = _sp_voices[_sv];
                if (_sv_idx < 0 || _sv_idx >= array_length(_m.patterns)) {
                    continue;
                }
                var _sv_pat = _m.patterns[_sv_idx];
                var _sv_local_row;
                if (_sp_row.repeat_short) {
                    _sv_local_row = _m.song_master_row mod _sv_pat.pattern_len;
                } else {
                    if (_m.song_master_row >= _sv_pat.pattern_len) {
                        continue;
                    }
                    _sv_local_row = _m.song_master_row;
                }
                var _sv_step = _sv_pat.steps[_sv_local_row];
                if (_sv_step.empty) {
                    // Empty row — leave whatever is ringing alone, matching
                    // the runtime's $FE hold.
                } else if (_sv_step.note == "" || _sv_step.note == "---") {
                    // Rest — silence this voice, matching the runtime's $FF,
                    // which now gates off AND stops the instrument.
                    scr_sound_preview_free_channel(_sv);
                } else {
                    scr_sound_editor_play_step(_m, _sv_step, _sv);
                }
            }
            _m.sel_order_row = _m.song_order_row;   // grid follows the song
            _m.song_tick = _m.play_speed;
            _m.song_master_row += 1;
        } else {
            _m.song_tick -= 1;
        }

        if (_m.song_master_row >= _sp_target) {
            _m.song_master_row = 0;
            _m.song_order_row += 1;
            if (_m.song_order_row >= array_length(_cur_song.order)) {
                if (_cur_song.loop) {
                    _m.song_order_row = clamp(real(_cur_song.loop_row), 0, array_length(_cur_song.order) - 1);
                } else {
                    _m.song_playing   = false;
                    _m.song_order_row = 0;
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // HEADER ROWS
    // ═════════════════════════════════════════════════════════════════════
    var _rowy = _cy + 40;
    draw_set_font(fnt_c64_tiny);

    // ── STATUS LINE — pushed above everything else, bigger font so it isn't
    // lost among the header controls. ──
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(120, 140, 190));
    draw_text(_vx1 + 20, _cy,
        "CLICK A CELL, TYPE A NOTE (C-4, C#3, ---)   |   ENTER COMMITS + DROPS A ROW   |   DEL CLEARS   |   BKSP PULLS UP   |   INS PUSHES DOWN   |   UP/DOWN MOVES   |   SPACE LOOP ROW   |   SHIFT+SPACE FROM START   |   CTRL+SPACE PLAY SONG");
   
   draw_set_font(fnt_c64_code);
   if (_m.playing) {
        draw_set_color(c_lime);
        draw_text(_vx1 + 20, _cy + 22, "> LOOPING ORDER ROW " + string(_m.sel_order_row) + " - STEP " + string(_m.play_row));
    } else if (_m.song_playing) {
        draw_set_color(c_aqua);
        draw_text(_vx1 + 20, _cy + 22, "> PLAYING SONG - ORDER ROW " + string(_m.song_order_row) + "   TICK " + string(_m.song_master_row));
    }
    draw_set_font(fnt_c64_tiny);

    // ── PATTERN BANK — create/delete patterns, independent of any voice ──
    draw_set_color(c_ltgray);
    draw_text(_vx1 + 20, _rowy + 4, "BANK:");

    var _bpx1 = _vx1 + 64;
    var _bpx2 = _bpx1 + 18;
    var _bp_hov = point_in_rectangle(_mx, _my, _bpx1, _rowy, _bpx2, _rowy + 18);
    draw_set_color(_bp_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_bpx1, _rowy, _bpx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_bpx1 + 9, _rowy + 4, "<");
    draw_set_halign(fa_left);
    if (_bp_hov && mouse_check_button_pressed(mb_left)) {
        _m.bank_sel_pattern = max(0, _m.bank_sel_pattern - 1);
    }

    draw_set_color(make_color_rgb(255, 200, 100));
    draw_set_halign(fa_center);
    var _bank_pat = _m.patterns[_m.bank_sel_pattern];
    draw_text(_bpx2 + 90, _rowy + 4, _bank_pat.name + "  (" + string(_m.bank_sel_pattern + 1) + "/" + string(array_length(_m.patterns)) + ")");
    draw_set_halign(fa_left);

    var _bnx1 = _bpx2 + 172;
    var _bnx2 = _bnx1 + 18;
    var _bn_hov = point_in_rectangle(_mx, _my, _bnx1, _rowy, _bnx2, _rowy + 18);
    draw_set_color(_bn_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_bnx1, _rowy, _bnx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_bnx1 + 9, _rowy + 4, ">");
    draw_set_halign(fa_left);
    if (_bn_hov && mouse_check_button_pressed(mb_left)) {
        _m.bank_sel_pattern = min(array_length(_m.patterns) - 1, _m.bank_sel_pattern + 1);
    }

    var _bax1 = _bnx2 + 20;
    var _bax2 = _bax1 + 100;
    var _ba_hov = point_in_rectangle(_mx, _my, _bax1, _rowy, _bax2, _rowy + 18);
    draw_set_color(_ba_hov ? make_color_rgb(60, 200, 80) : make_color_rgb(20, 100, 40));
    draw_rectangle(_bax1, _rowy, _bax2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_bax1 + _bax2) * 0.5, _rowy + 4, "+ NEW");
    draw_set_halign(fa_left);
    if (_ba_hov && mouse_check_button_pressed(mb_left)) {
        var _pat_num_str = string(array_length(_m.patterns));
        while (string_length(_pat_num_str) < 2) { _pat_num_str = "0" + _pat_num_str; }
        array_push(_m.patterns, { name: "PATTERN " + _pat_num_str, steps: [], pattern_len: 64 });
        _m.bank_sel_pattern = array_length(_m.patterns) - 1;
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    var _bdx1 = _bax2 + 8;
    var _bdx2 = _bdx1 + 90;
    var _bd_referenced = false;
    for (var _bri = 0; _bri < array_length(_cur_song.order); _bri++) {
        var _br = _cur_song.order[_bri];
        if (_br.v1 == _m.bank_sel_pattern || _br.v2 == _m.bank_sel_pattern || _br.v3 == _m.bank_sel_pattern) {
            _bd_referenced = true;
            break;
        }
    }
    var _bd_lock = (array_length(_m.patterns) <= 1) || _bd_referenced;
    var _bd_hov  = !_bd_lock && point_in_rectangle(_mx, _my, _bdx1, _rowy, _bdx2, _rowy + 18);
    draw_set_color(_bd_lock ? make_color_rgb(55, 40, 40) : (_bd_hov ? make_color_rgb(200, 60, 60) : make_color_rgb(100, 30, 30)));
    draw_rectangle(_bdx1, _rowy, _bdx2, _rowy + 18, false);
    draw_set_color(_bd_lock ? make_color_rgb(100, 80, 80) : c_white);
    draw_set_halign(fa_center);
    draw_text((_bdx1 + _bdx2) * 0.5, _rowy + 4, "DEL");
    draw_set_halign(fa_left);
    if (_bd_hov && mouse_check_button_pressed(mb_left)) {
        array_delete(_m.patterns, _m.bank_sel_pattern, 1);
        _m.bank_sel_pattern = clamp(_m.bank_sel_pattern, 0, array_length(_m.patterns) - 1);
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }
    if (_bd_referenced) {
        draw_set_font(fnt_c64_pico);
        draw_set_color(make_color_rgb(200, 140, 60));
        draw_text(_bdx2 + 12, _rowy + 6, "! IN USE - CAN'T DELETE");
        draw_set_font(fnt_c64_tiny);
    }

    // ── OCTAVE STEPPER ──
    var _ocx0 = _bdx2 + 200;
    draw_set_color(c_ltgray);
    draw_text(_ocx0, _rowy + 4, "OCTAVE:");

    var _opx1 = _ocx0 + 60;
    var _opx2 = _opx1 + 18;
    var _op_hov = point_in_rectangle(_mx, _my, _opx1, _rowy, _opx2, _rowy + 18);
    draw_set_color(_op_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_opx1, _rowy, _opx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_opx1 + 9, _rowy + 4, "<");
    draw_set_halign(fa_left);
    if (_op_hov && mouse_check_button_pressed(mb_left)) {
        _m.cur_octave = clamp(_m.cur_octave - 1, 1, 6);
    }

    draw_set_color(make_color_rgb(140, 220, 255));
    draw_set_halign(fa_center);
    draw_text(_opx2 + 16, _rowy + 4, string(_m.cur_octave));
    draw_set_halign(fa_left);

    var _onx1 = _opx2 + 32;
    var _onx2 = _onx1 + 18;
    var _on_hov = point_in_rectangle(_mx, _my, _onx1, _rowy, _onx2, _rowy + 18);
    draw_set_color(_on_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_onx1, _rowy, _onx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_onx1 + 9, _rowy + 4, ">");
    draw_set_halign(fa_left);
    if (_on_hov && mouse_check_button_pressed(mb_left)) {
        _m.cur_octave = clamp(_m.cur_octave + 1, 1, 6);
    }

    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 90, 120));
    draw_text(_onx2 + 16, _rowy + 6, "Z-ROW=OCT-1  Q-ROW=OCT  I/O/P=OCT+1");
    draw_set_font(fnt_c64_tiny);

    // ── TEMPO ── frames per row, shared by every song in this asset. The
    // emitter bakes it in as the _S_TICK reload value, so changing it resizes
    // nothing but does change what the node emits.
    var _tpx0 = _onx2 + 320;
    draw_set_color(c_ltgray);
    draw_text(_tpx0, _rowy + 4, "TEMPO:");

    var _tp_dx1 = _tpx0 + 58;
    var _tp_dx2 = _tp_dx1 + 18;
    var _tp_d_hov = point_in_rectangle(_mx, _my, _tp_dx1, _rowy, _tp_dx2, _rowy + 18);
    draw_set_color(_tp_d_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_tp_dx1, _rowy, _tp_dx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_tp_dx1 + 9, _rowy + 4, "<");
    draw_set_halign(fa_left);
    if (_tp_d_hov && mouse_check_button_pressed(mb_left)) {
        _m.play_speed          = clamp(real(_m.play_speed) - 1, 1, 24);
        global.addresses_dirty = true;
        global.undo_dirty      = true;
    }

    draw_set_color(make_color_rgb(140, 220, 255));
    draw_set_halign(fa_center);
    draw_text(_tp_dx2 + 20, _rowy + 4, string(_m.play_speed));
    draw_set_halign(fa_left);

    var _tp_ux1 = _tp_dx2 + 40;
    var _tp_ux2 = _tp_ux1 + 18;
    var _tp_u_hov = point_in_rectangle(_mx, _my, _tp_ux1, _rowy, _tp_ux2, _rowy + 18);
    draw_set_color(_tp_u_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_tp_ux1, _rowy, _tp_ux2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_tp_ux1 + 9, _rowy + 4, ">");
    draw_set_halign(fa_left);
    if (_tp_u_hov && mouse_check_button_pressed(mb_left)) {
        _m.play_speed          = clamp(real(_m.play_speed) + 1, 1, 24);
        global.addresses_dirty = true;
        global.undo_dirty      = true;
    }

    // Rough BPM readout, assuming 4 rows to the beat on a 50Hz PAL raster.
    // Informational only — nothing downstream reads it.
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 90, 120));
    var _tp_bpm = round((50 * 60) / (real(_m.play_speed) * 4));
    draw_text(_tp_ux2 + 12, _rowy + 6, "FRAMES/ROW  (~" + string(_tp_bpm) + " BPM @ 4 ROWS/BEAT)");
    draw_set_font(fnt_c64_tiny);

    _rowy += 24;

    // ═════════════════════════════════════════════════════════════════════
    // LEFT PANEL — PATTERN GRID (3 columns = whatever the selected order
    // row's v1/v2/v3 currently point at)
    // ═════════════════════════════════════════════════════════════════════
    var _gy0 = _rowy + 44;
    var _gx0 = _vx1 + 20;

    var _col_gutter_x = _gx0;
    var _col_x = [
        _gx0 + _gutter_w,
        _gx0 + _gutter_w + _lane_w + _lane_gap,
        _gx0 + _gutter_w + (_lane_w + _lane_gap) * 2
    ];
    var _grid_full_w = _gutter_w + (_lane_w * 3) + (_lane_gap * 2);

    var _lane_colours = [make_color_rgb(120, 220, 255), make_color_rgb(255, 200, 120), make_color_rgb(180, 255, 150)];
		_txt_scale =1;
    for (var _lh = 0; _lh < 3; _lh++) {
        draw_set_color(_lane_colours[_lh]);
        draw_set_halign(fa_center);
		        var _lh_label = "V O I C E  " + string(_lh + 1);
				
        draw_text_transformed(_col_x[_lh] + (_lane_w * 0.5), _gy0 - 20, _lh_label, _txt_scale, _txt_scale, 0);
        draw_set_halign(fa_left);
		
        // Which pattern + its own length, with a length stepper. Readout
        // only — WHICH pattern plays here is set via the order table, not here.
        draw_set_font(fnt_c64_pico);
        if (_col_pat[_lh] == noone) {
            draw_set_color(make_color_rgb(220, 120, 90));
            draw_text(_col_x[_lh], _gy0 - 34, "[ NO PATTERN ]");
        } else {
            draw_set_color(make_color_rgb(90, 90, 120));
            draw_text(_col_x[_lh], _gy0 - 34, "PAT " + _col_pat[_lh].name + "   LEN:");

            var _clx1 = _col_x[_lh] + 130;
            var _clx2 = _clx1 + 14;
            var _cl_hov = point_in_rectangle(_mx, _my, _clx1, _gy0 - 38, _clx2, _gy0 - 24);
            draw_set_color(_cl_hov ? c_aqua : make_color_rgb(60, 130, 150));
            draw_text(_clx1, _gy0 - 34, "<");
            if (_cl_hov && mouse_check_button_pressed(mb_left)) {
                _col_pat[_lh].pattern_len = clamp(_col_pat[_lh].pattern_len - 4, 4, 128);
                _se_ensure_steps(_col_pat[_lh]);
                global.addresses_dirty = true;
            }

            draw_set_color(c_white);
            draw_text(_clx2 + 4, _gy0 - 34, string(_col_pat[_lh].pattern_len));

            var _cnx1 = _clx2 + 30;
            var _cnx2 = _cnx1 + 14;
            var _cn_hov = point_in_rectangle(_mx, _my, _cnx1, _gy0 - 38, _cnx2, _gy0 - 24);
            draw_set_color(_cn_hov ? c_aqua : make_color_rgb(60, 130, 150));
            draw_text(_cnx1, _gy0 - 34, ">");
            if (_cn_hov && mouse_check_button_pressed(mb_left)) {
                _col_pat[_lh].pattern_len = clamp(_col_pat[_lh].pattern_len + 4, 4, 128);
                _se_ensure_steps(_col_pat[_lh]);
                global.addresses_dirty = true;
            }
        }
        draw_set_font(fnt_c64_tiny);
    }
	_txt_scale =2;
    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_col_gutter_x - 4, _gy0 - 2, _col_gutter_x + _grid_full_w + 4, _gy0 + _vis * _row_h + 2, false);
    draw_set_color(make_color_rgb(50, 50, 70));
    draw_rectangle(_col_gutter_x - 4, _gy0 - 2, _col_gutter_x + _grid_full_w + 4, _gy0 + _vis * _row_h + 2, true);

    _m.list_scroll = clamp(_m.list_scroll, 0, max(0, _grid_len - _vis));

    var _sel_v_lo = min(_m.sel_anchor_voice, _m.sel_voice);
    var _sel_v_hi = max(_m.sel_anchor_voice, _m.sel_voice);
    var _sel_s_lo = min(_m.sel_anchor_step,  _m.sel_step);
    var _sel_s_hi = max(_m.sel_anchor_step,  _m.sel_step);
    var _sel_multi = (_sel_v_lo != _sel_v_hi) || (_sel_s_lo != _sel_s_hi);

    for (var _r = 0; _r < _vis; _r++) {
        var _row = _r + _m.list_scroll;
        if (_row >= _grid_len) {
            break;
        }
        var _ry = _gy0 + _r * _row_h;

        var _shade = make_color_rgb(20, 20, 32);
        if (_row mod 16 == 0) {
            _shade = make_color_rgb(30, 30, 46);
        } else if (_row mod 4 == 0) {
            _shade = make_color_rgb(24, 24, 38);
        }
        draw_set_color(_shade);
        draw_rectangle(_col_gutter_x, _ry, _col_gutter_x + _grid_full_w, _ry + _row_h, false);

        var _highlight_row = -1;
        if (_m.playing) {
            _highlight_row = _m.play_row;
        } else if (_m.song_playing && _m.song_order_row == _m.sel_order_row) {
            _highlight_row = _order_row.repeat_short ? (_m.song_master_row mod max(1, _grid_len)) : _m.song_master_row;
        }
        if (_highlight_row == _row) {
            draw_set_color(make_color_rgb(40, 100, 60));
            draw_set_alpha(0.5);
            draw_rectangle(_col_gutter_x, _ry, _col_gutter_x + _grid_full_w, _ry + _row_h, false);
            draw_set_alpha(1.0);
        }

        draw_set_color((_row mod 16 == 0) ? make_color_rgb(220, 200, 120) : make_color_rgb(90, 90, 120));
        draw_text_transformed(_col_gutter_x + 8, _ry + 6, string(_row), _txt_scale, _txt_scale, 0);

        for (var _cv = 0; _cv < 3; _cv++) {
            var _cx1 = _col_x[_cv];
            var _cx2 = _cx1 + _lane_w;
            var _has_pat = (_col_pat[_cv] != noone);
            var _in_range = _has_pat && (_row < _col_pat[_cv].pattern_len);

            var _is_editing = (_m.edit_active && _m.edit_voice == _cv && _m.edit_step == _row);
            var _hov = _in_range && point_in_rectangle(_mx, _my, _cx1, _ry, _cx2, _ry + _row_h);
            var _is_cursor = (_in_range && !_m.edit_active && _m.sel_voice == _cv && _m.sel_step == _row);
            var _is_selected = (_in_range && _cv >= _sel_v_lo && _cv <= _sel_v_hi && _row >= _sel_s_lo && _row <= _sel_s_hi);

            if (!_has_pat) {
                draw_set_color(make_color_rgb(26, 22, 22));
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, false);
                draw_set_color(make_color_rgb(130, 100, 100));
                draw_text_transformed(_cx1 + 8, _ry + 8, "----", _txt_scale, _txt_scale, 0);
                continue;
            }
            if (!_in_range) {
                draw_set_color(make_color_rgb(26, 26, 38));
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, false);
                draw_set_color(make_color_rgb(110, 110, 130));
                draw_text_transformed(_cx1 + 8, _ry + 8, "END", _txt_scale, _txt_scale, 0);
                continue;
            }

            if (_is_editing) {
                draw_set_color(make_color_rgb(40, 90, 60));
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, false);
            } else if (_sel_multi && _is_selected) {
                draw_set_color(make_color_rgb(50, 70, 110));
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, false);
            } else if (_is_cursor) {
                draw_set_color(make_color_rgb(60, 60, 90));
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, false);
            } else if (_hov) {
                draw_set_color(make_color_rgb(30, 30, 46));
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, false);
            }

            var _step = _col_pat[_cv].steps[_row];

            if (_is_editing) {
                var _blink = (current_time mod 600) < 300;
                var _disp  = _blink ? string_insert("|", _m.edit_buf, _m.edit_cursor + 1) : _m.edit_buf;
                draw_set_color(c_lime);
                draw_text_transformed(_cx1 + 8, _ry + 8, _disp, _txt_scale, _txt_scale, 0);
            } else if (_step.empty) {
                draw_set_color(make_color_rgb(60, 60, 70));
                draw_text_transformed(_cx1 + 8, _ry + 8, "...", _txt_scale, _txt_scale, 0);
            } else if (_step.note == "---" || _step.note == "") {
                draw_set_color(make_color_rgb(140, 90, 90));
                draw_text_transformed(_cx1 + 8, _ry + 8, "---", _txt_scale, _txt_scale, 0);
            } else {
                var _missing   = (_step.instr_idx >= 0 && _step.instr_idx >= array_length(_m.instruments));
                var _has_instr = (_step.instr_idx >= 0 && !_missing);
                var _cell_txt  = _step.note;
                if (_has_instr) {
                    var _instr_str = string(_step.instr_idx);
                    while (string_length(_instr_str) < 2) { _instr_str = "0" + _instr_str; }
                    _cell_txt += " " + _instr_str;
                }
                draw_set_color(_missing ? c_red : c_white);
                draw_text_transformed(_cx1 + 8, _ry + 8, _cell_txt, _txt_scale, _txt_scale, 0);
                if (_missing) {
                    draw_set_font(fnt_c64_pico);
                    draw_set_color(c_red);
                    draw_text(_cx1 + 8, _ry + 26, "INSTRUMENT MISSING OR UNDEFINED");
                    draw_set_font(fnt_c64_tiny);
                }
            }

            if (_is_cursor) {
                draw_set_color(c_yellow);
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, true);
            }

            if (_hov && mouse_check_button_pressed(mb_left)) {
                if (_m.edit_active && (_m.edit_voice != _cv || _m.edit_step != _row)) {
                    scr_sound_editor_commit_cell(_m, _se_push_undo, _se_snap, _col_pat);
                }
                var _mc_shift = keyboard_check(vk_shift);
                if (_mc_shift) {
                    _m.sel_voice   = _cv;
                    _m.sel_step    = _row;
                    _m.edit_active = false;
                } else {
                    var _dbl = (_m.last_click_voice == _cv && _m.last_click_step == _row
                             && (current_time - _m.last_click_time) < 350);
                    _m.last_click_time  = current_time;
                    _m.last_click_voice = _cv;
                    _m.last_click_step  = _row;

                    _m.sel_voice        = _cv;
                    _m.sel_step         = _row;
                    _m.sel_anchor_voice = _cv;
                    _m.sel_anchor_step  = _row;

                    if (_dbl) {
                        _m.edit_active = true;
                        _m.edit_voice  = _cv;
                        _m.edit_step   = _row;
                        _m.edit_buf    = (_step.note != "") ? _step.note : "";
                        _m.edit_cursor = string_length(_m.edit_buf);
                    } else if (_m.edit_active && _m.edit_voice == _cv && _m.edit_step == _row) {
                        // leave open
                    } else {
                        _m.edit_active = false;
                    }
                }
            }

            if (_hov && mouse_check_button_pressed(mb_right)) {
                _se_push_undo(_m, _se_snap);
                _step.note      = "";
                _step.instr_idx = -1;
                _step.empty     = true;
                global.undo_dirty = true;
            }
        }
    }

    // ── TEXT INPUT WHILE EDITING A CELL ──
    if (_m.edit_active) {
        // Was vk_control || (vk_lalt && macos) — left-Alt was standing in for
        // Cmd, which is neither what a Mac user presses nor unambiguous to
        // read given GML's precedence. scr_cmd_held covers both platforms.
        var _ctrl = keyboard_check(vk_control) || scr_cmd_held();

        if (keyboard_check_pressed(vk_enter)) {
            scr_sound_editor_commit_cell(_m, _se_push_undo, _se_snap, _col_pat);
            var _next = _m.edit_step + 1;
            if (_col_pat[_m.edit_voice] != noone && _next < _col_pat[_m.edit_voice].pattern_len) {
                var _nx_step = _col_pat[_m.edit_voice].steps[_next];
                _m.sel_step    = _next;
                _m.edit_active = true;
                _m.edit_step   = _next;
                _m.edit_buf    = (_nx_step.note != "") ? _nx_step.note : "";
                _m.edit_cursor = string_length(_m.edit_buf);
                if (_next >= _m.list_scroll + _vis) {
                    _m.list_scroll = _next - _vis + 1;
                }
            } else {
                _m.edit_active = false;
            }
            keyboard_string = "";
        }

        if (keyboard_check_pressed(vk_escape)) {
            _m.edit_active = false;
            keyboard_string = "";
        }

        if (keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_down)) {
            scr_sound_editor_commit_cell(_m, _se_push_undo, _se_snap, _col_pat);
            if (_col_pat[_m.edit_voice] != noone) {
                var _dir = keyboard_check_pressed(vk_down) ? 1 : -1;
                var _tgt = clamp(_m.edit_step + _dir, 0, _col_pat[_m.edit_voice].pattern_len - 1);
                var _tg_step = _col_pat[_m.edit_voice].steps[_tgt];
                _m.sel_step    = _tgt;
                _m.edit_step   = _tgt;
                _m.edit_buf    = (_tg_step.note != "") ? _tg_step.note : "";
                _m.edit_cursor = string_length(_m.edit_buf);
                if (_tgt < _m.list_scroll) {
                    _m.list_scroll = _tgt;
                }
                if (_tgt >= _m.list_scroll + _vis) {
                    _m.list_scroll = _tgt - _vis + 1;
                }
            }
        }

        if (keyboard_check_pressed(vk_backspace) && _m.edit_cursor > 0) {
            _m.edit_buf    = string_delete(_m.edit_buf, _m.edit_cursor, 1);
            _m.edit_cursor -= 1;
        }

        if (!_ctrl && keyboard_string != "") {
            var _added = scr_strip_key_ghosts(keyboard_string);
            var _clean = "";
            for (var _aci = 1; _aci <= string_length(_added); _aci++) {
                var _ach = string_upper(string_char_at(_added, _aci));
                if ((_ach >= "A" && _ach <= "G") || _ach == "#" || _ach == "-"
                ||  (_ach >= "0" && _ach <= "9")) {
                    _clean += _ach;
                }
            }
            if (_clean != "" && string_length(_m.edit_buf) < 8) {
                _m.edit_buf    = string_insert(_clean, _m.edit_buf, _m.edit_cursor + 1);
                _m.edit_cursor += string_length(_clean);
            }
            keyboard_string = "";
        }
    } else if (!_m.instr_edit_active && !_m.instr_name_edit_active && !_m.song_name_edit_active) {
        // ── CURSOR MODE: PIANO-STYLE NOTE ENTRY ──
        // Stands down entirely while the INSTRUMENTS panel's text or name
        // box has focus — otherwise keyboard_string feeds both handlers at
        // once, planting real notes in the grid while you're just typing an
        // instrument's source text.
        //
        // Cursor mode reads keys via keyboard_check_pressed only, never
        // keyboard_string — but keyboard_string still SILENTLY FILLS from
        // the OS every frame regardless of who's listening. Left unflushed,
        // every letter typed here (Q, W, E...) sits queued and dumps into
        // the instrument text/name box the moment it next reads
        // keyboard_string. Flushing it here, every frame, is safe because
        // nothing else in cursor mode needs it.
        keyboard_string = "";

        // '[' '=' ']' aren't covered by ord() — using their actual Windows
        // OEM virtual-key codes so keyboard_check_pressed sees them.
        var _vk_lbracket = 0xDB;   // '['
        var _vk_equals   = 0xBB;   // '='
        var _vk_rbracket = 0xDD;   // ']'

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
            [ord("0"),  3,  1], [ord("P"),  4,  1],
            [_vk_lbracket, 5, 1], [_vk_equals, 6, 1], [_vk_rbracket, 7, 1]
        ];

        var _pk_names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
        var _cur_pat  = _col_pat[_m.sel_voice];
        var _cur_step = (_cur_pat != noone && _m.sel_step < _cur_pat.pattern_len) ? _cur_pat.steps[_m.sel_step] : noone;

        var _kb_ctrl = keyboard_check(vk_control) || scr_cmd_held();

        if (_kb_ctrl && keyboard_check_pressed(ord("C"))) {
            var _cp_w = (_sel_v_hi - _sel_v_lo) + 1;
            var _cp_h = (_sel_s_hi - _sel_s_lo) + 1;
            var _cp_rows = [];
            for (var _cpr = 0; _cpr < _cp_h; _cpr++) {
                var _cp_cols = [];
                for (var _cpc = 0; _cpc < _cp_w; _cpc++) {
                    var _cp_col_pat = _col_pat[_sel_v_lo + _cpc];
                    var _cp_row_idx = _sel_s_lo + _cpr;
                    if (_cp_col_pat != noone && _cp_row_idx < _cp_col_pat.pattern_len) {
                        var _cp_src = _cp_col_pat.steps[_cp_row_idx];
                        array_push(_cp_cols, { note: _cp_src.note, instr_idx: _cp_src.instr_idx, empty: _cp_src.empty });
                    } else {
                        array_push(_cp_cols, { note: "", instr_idx: -1, empty: true });
                    }
                }
                array_push(_cp_rows, _cp_cols);
            }
            global.se_clipboard = { w: _cp_w, h: _cp_h, rows: _cp_rows };
            _m.warn_msg   = "COPIED " + string(_cp_w) + "x" + string(_cp_h);
            _m.warn_timer = game_get_speed(gamespeed_fps) * 2;
        }

        if (_kb_ctrl && keyboard_check_pressed(ord("V")) && global.se_clipboard != noone) {
            _se_push_undo(_m, _se_snap);
            var _cb = global.se_clipboard;
            var _pv_max = 0;
            var _ps_max = 0;
            for (var _pr = 0; _pr < _cb.h; _pr++) {
                var _dest_step = _m.sel_step + _pr;
                for (var _pc = 0; _pc < _cb.w; _pc++) {
                    var _dest_voice = _m.sel_voice + _pc;
                    if (_dest_voice > 2) {
                        continue;
                    }
                    var _dest_pat = _col_pat[_dest_voice];
                    if (_dest_pat == noone || _dest_step >= _dest_pat.pattern_len) {
                        continue;   // no auto-grow on paste — skip cells past the pattern's own length
                    }
                    var _src_cell = _cb.rows[_pr][_pc];
                    var _dst_cell = _dest_pat.steps[_dest_step];
                    _dst_cell.note      = _src_cell.note;
                    _dst_cell.instr_idx = _src_cell.instr_idx;
                    _dst_cell.empty     = _src_cell.empty;
                    _pv_max = max(_pv_max, _pc);
                    _ps_max = max(_ps_max, _pr);
                }
            }
            _m.sel_anchor_voice = _m.sel_voice;
            _m.sel_anchor_step  = _m.sel_step;
            _m.sel_voice        = min(2, _m.sel_voice + _pv_max);
            _m.sel_step         = min(_grid_len - 1, _m.sel_step + _ps_max);
            global.undo_dirty   = true;
        }

        for (var _pki = 0; _pki < array_length(_pk_map) && !_kb_ctrl && _cur_step != noone; _pki++) {
            var _pk = _pk_map[_pki];
            if (keyboard_check_pressed(_pk[0])) {
                var _pk_oct  = clamp(_m.cur_octave + _pk[2], 0, 7);
                var _pk_name = _pk_names[_pk[1]];
                var _pk_note = (string_char_at(_pk_name, 2) == "#")
                             ? (_pk_name + string(_pk_oct))
                             : (string_char_at(_pk_name, 1) + "-" + string(_pk_oct));

                _se_push_undo(_m, _se_snap);
                _cur_step.note      = _pk_note;
                _cur_step.instr_idx = _m.sel_instr;
                _cur_step.empty     = false;
                global.undo_dirty   = true;

                scr_sound_editor_play_step(_m, _cur_step, _m.sel_voice);

                if (_m.sel_step + 1 < _cur_pat.pattern_len) {
                    _m.sel_step += 1;
                }
                if (_m.sel_step >= _m.list_scroll + _vis) {
                    _m.list_scroll = _m.sel_step - _vis + 1;
                }
                _m.sel_anchor_voice = _m.sel_voice;
                _m.sel_anchor_step  = _m.sel_step;
                break;
            }
        }

        if (_cur_step != noone && keyboard_check_pressed(ord("1"))) {
            _se_push_undo(_m, _se_snap);
            _cur_step.note      = "---";
            _cur_step.instr_idx = -1;
            _cur_step.empty     = false;
            global.undo_dirty   = true;
            if (_m.sel_step + 1 < _cur_pat.pattern_len) {
                _m.sel_step += 1;
            }
            if (_m.sel_step >= _m.list_scroll + _vis) {
                _m.list_scroll = _m.sel_step - _vis + 1;
            }
            _m.sel_anchor_voice = _m.sel_voice;
            _m.sel_anchor_step  = _m.sel_step;
        }

        if (_cur_step != noone && keyboard_check_pressed(vk_delete)) {
            _se_push_undo(_m, _se_snap);
            _cur_step.note      = "";
            _cur_step.instr_idx = -1;
            _cur_step.empty     = true;
            global.undo_dirty   = true;
        }

        if (_cur_step != noone && keyboard_check(vk_backspace)) {
            var _do_bksp = false;
            if (keyboard_check_pressed(vk_backspace)) {
                _do_bksp      = true;
                _m.bksp_timer = round(game_get_speed(gamespeed_fps) * 0.33);
            } else {
                _m.bksp_timer -= 1;
                if (_m.bksp_timer <= 0) {
                    _do_bksp      = true;
                    _m.bksp_timer = 2;
                }
            }
            if (_do_bksp) {
                _se_push_undo(_m, _se_snap);
                for (var _bsi = _m.sel_step; _bsi < _cur_pat.pattern_len - 1; _bsi++) {
                    var _bs_src = _cur_pat.steps[_bsi + 1];
                    var _bs_dst = _cur_pat.steps[_bsi];
                    _bs_dst.note      = _bs_src.note;
                    _bs_dst.instr_idx = _bs_src.instr_idx;
                    _bs_dst.empty     = _bs_src.empty;
                }
                var _bs_last = _cur_pat.steps[_cur_pat.pattern_len - 1];
                _bs_last.note      = "";
                _bs_last.instr_idx = -1;
                _bs_last.empty     = true;
                global.undo_dirty  = true;
            }
        } else {
            _m.bksp_timer = 0;
        }

        // ── INSERT ── mirror of backspace: push every step from the cursor
        // DOWN one row, leaving the cursor row blank. The pattern's own length
        // is fixed, so the last step falls off the end and is discarded —
        // same trade-off backspace makes at the top.
        //
        // Walks backwards from the end so each destination is written before
        // it is read as a source; a forward loop would smear the cursor row
        // down the whole pattern.
        if (_cur_step != noone && keyboard_check(vk_insert)) {
            var _do_ins = false;
            if (keyboard_check_pressed(vk_insert)) {
                _do_ins       = true;
                _m.ins_timer  = round(game_get_speed(gamespeed_fps) * 0.33);
            } else {
                _m.ins_timer -= 1;
                if (_m.ins_timer <= 0) {
                    _do_ins      = true;
                    _m.ins_timer = 2;
                }
            }
            if (_do_ins) {
                _se_push_undo(_m, _se_snap);
                for (var _isi = _cur_pat.pattern_len - 1; _isi > _m.sel_step; _isi--) {
                    var _is_src = _cur_pat.steps[_isi - 1];
                    var _is_dst = _cur_pat.steps[_isi];
                    _is_dst.note      = _is_src.note;
                    _is_dst.instr_idx = _is_src.instr_idx;
                    _is_dst.empty     = _is_src.empty;
                }
                var _is_cur = _cur_pat.steps[_m.sel_step];
                _is_cur.note      = "";
                _is_cur.instr_idx = -1;
                _is_cur.empty     = true;
                global.undo_dirty = true;
            }
        } else {
            _m.ins_timer = 0;
        }

        var _nav_delay = round(game_get_speed(gamespeed_fps) * 0.33);
        var _kb_shift_col = keyboard_check(vk_shift);

        if (keyboard_check(vk_up)) {
            if (keyboard_check_pressed(vk_up)) {
                _m.sel_step = max(0, _m.sel_step - 1);
                if (_m.sel_step < _m.list_scroll) { _m.list_scroll = _m.sel_step; }
                _m.nav_up_timer = _nav_delay;
                if (!_kb_shift_col) { _m.sel_anchor_voice = _m.sel_voice; _m.sel_anchor_step = _m.sel_step; }
            } else {
                _m.nav_up_timer -= 1;
                if (_m.nav_up_timer <= 0) {
                    _m.sel_step = max(0, _m.sel_step - 1);
                    if (_m.sel_step < _m.list_scroll) { _m.list_scroll = _m.sel_step; }
                    _m.nav_up_timer = 2;
                    if (!_kb_shift_col) { _m.sel_anchor_voice = _m.sel_voice; _m.sel_anchor_step = _m.sel_step; }
                }
            }
        } else {
            _m.nav_up_timer = 0;
        }

        if (keyboard_check(vk_down)) {
            if (keyboard_check_pressed(vk_down)) {
                _m.sel_step = min(_grid_len - 1, _m.sel_step + 1);
                if (_m.sel_step >= _m.list_scroll + _vis) { _m.list_scroll = _m.sel_step - _vis + 1; }
                _m.nav_down_timer = _nav_delay;
                if (!_kb_shift_col) { _m.sel_anchor_voice = _m.sel_voice; _m.sel_anchor_step = _m.sel_step; }
            } else {
                _m.nav_down_timer -= 1;
                if (_m.nav_down_timer <= 0) {
                    _m.sel_step = min(_grid_len - 1, _m.sel_step + 1);
                    if (_m.sel_step >= _m.list_scroll + _vis) { _m.list_scroll = _m.sel_step - _vis + 1; }
                    _m.nav_down_timer = 2;
                    if (!_kb_shift_col) { _m.sel_anchor_voice = _m.sel_voice; _m.sel_anchor_step = _m.sel_step; }
                }
            }
        } else {
            _m.nav_down_timer = 0;
        }

        if (keyboard_check_pressed(vk_home)) {
            _m.sel_step = 0;
            if (_m.sel_step < _m.list_scroll) { _m.list_scroll = _m.sel_step; }
            _m.sel_anchor_voice = _m.sel_voice;
            _m.sel_anchor_step  = _m.sel_step;
        }

        if (keyboard_check_pressed(vk_right) || (keyboard_check_pressed(vk_tab) && !_kb_shift_col)) {
            _m.sel_voice = _kb_shift_col ? min(2, _m.sel_voice + 1) : ((_m.sel_voice + 1) mod 3);
            if (!_kb_shift_col) { _m.sel_anchor_voice = _m.sel_voice; _m.sel_anchor_step = _m.sel_step; }
        }
        if (keyboard_check_pressed(vk_left) || (keyboard_check_pressed(vk_tab) && _kb_shift_col)) {
            _m.sel_voice = _kb_shift_col ? max(0, _m.sel_voice - 1) : ((_m.sel_voice + 2) mod 3);
            if (!_kb_shift_col) { _m.sel_anchor_voice = _m.sel_voice; _m.sel_anchor_step = _m.sel_step; }
        }

        if (_cur_step != noone && keyboard_check_pressed(vk_enter)) {
            _m.edit_active = true;
            _m.edit_voice  = _m.sel_voice;
            _m.edit_step   = _m.sel_step;
            _m.edit_buf    = (_cur_step.note != "") ? _cur_step.note : "";
            _m.edit_cursor = string_length(_m.edit_buf);
        }
    }

    if (_m.edit_active
    &&  !point_in_rectangle(_mx, _my, _col_gutter_x - 4, _gy0 - 2, _col_gutter_x + _grid_full_w + 4, _gy0 + _vis * _row_h + 2)
    &&  mouse_check_button_pressed(mb_left)) {
        scr_sound_editor_commit_cell(_m, _se_push_undo, _se_snap, _col_pat);
    }

    if (point_in_rectangle(_mx, _my, _col_gutter_x - 4, _gy0 - 2, _col_gutter_x + _grid_full_w + 4, _gy0 + _vis * _row_h + 2)) {
        if (mouse_wheel_up())   { _m.list_scroll = max(0, _m.list_scroll - 1); }
        if (mouse_wheel_down()) { _m.list_scroll = min(max(0, _grid_len - _vis), _m.list_scroll + 1); }
    }

    // ── PER-VOICE CLEAR ──
    // Wipes every step of whichever pattern that column currently points at.
    //
    // Patterns are a SHARED POOL: the same pattern index can sit in several
    // voice columns, several order rows and several songs at once, and they
    // are all literally the same object. So clearing "voice 1's pattern" also
    // clears every other place that pattern appears. That is correct — there
    // is only one pattern — but it is easy to forget, so the warning line
    // reports how many voice-slots reference it whenever the count is above
    // one. Undo covers a mis-click.
    var _clr_y = _gy0 + _vis * _row_h + 10;
    for (var _cli = 0; _cli < 3; _cli++) {
        var _cl_x1 = _col_x[_cli];
        var _cl_x2 = _cl_x1 + _lane_w;
        var _cl_pat = _col_pat[_cli];
        var _cl_lock = (_cl_pat == noone);
        var _cl_hov2 = !_cl_lock && point_in_rectangle(_mx, _my, _cl_x1, _clr_y, _cl_x2, _clr_y + 20);

        if (_cl_lock) {
            draw_set_color(make_color_rgb(45, 40, 40));
        } else if (_cl_hov2) {
            draw_set_color(make_color_rgb(200, 60, 60));
        } else {
            draw_set_color(make_color_rgb(90, 30, 30));
        }
        draw_rectangle(_cl_x1, _clr_y, _cl_x2, _clr_y + 20, false);

        draw_set_color(_cl_lock ? make_color_rgb(100, 80, 80) : c_white);
        draw_set_halign(fa_center);
        if (_cl_lock) {
            draw_text((_cl_x1 + _cl_x2) * 0.5, _clr_y + 5, "CLEAR");
        } else {
            draw_text((_cl_x1 + _cl_x2) * 0.5, _clr_y + 5, "CLEAR " + _cl_pat.name);
        }
        draw_set_halign(fa_left);

        if (_cl_hov2 && mouse_check_button_pressed(mb_left)) {
            _se_push_undo(_m, _se_snap);

            // Count references across EVERY song, not just this one — a
            // pattern shared with another song is exactly the case where a
            // silent wipe would be most surprising.
            var _cl_refs = 0;
            for (var _crs = 0; _crs < array_length(_m.songs); _crs++) {
                var _cr_song = _m.songs[_crs];
                for (var _cro = 0; _cro < array_length(_cr_song.order); _cro++) {
                    var _cr_row = _cr_song.order[_cro];
                    if (_cr_row.v1 == _col_pat_idx[_cli]) { _cl_refs += 1; }
                    if (_cr_row.v2 == _col_pat_idx[_cli]) { _cl_refs += 1; }
                    if (_cr_row.v3 == _col_pat_idx[_cli]) { _cl_refs += 1; }
                }
            }

            for (var _cs = 0; _cs < array_length(_cl_pat.steps); _cs++) {
                var _cs_step = _cl_pat.steps[_cs];
                _cs_step.note      = "";
                _cs_step.instr_idx = -1;
                _cs_step.empty     = true;
            }

            if (_cl_refs > 1) {
                _m.warn_msg = "CLEARED " + _cl_pat.name + " - USED IN " + string(_cl_refs) + " PLACES";
            } else {
                _m.warn_msg = "CLEARED " + _cl_pat.name;
            }
            _m.warn_timer = game_get_speed(gamespeed_fps) * 3;

            global.undo_dirty      = true;
            global.addresses_dirty = true;
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // RIGHT PANEL — SONG ORDER TABLE
    // ═════════════════════════════════════════════════════════════════════
    var _ox0 = _col_gutter_x + _grid_full_w + 60;
    // Right panel sits lower than the grid so the SONG selector strip has a
    // clear row of its own — at _gy0 it lands in the header band and collides
    // with the octave stepper.
    var _oy0 = _gy0 + 26;
    var _ord_row_h = 28;
    var _ord_vis   = 21;
    var _ord_col_w = [44, 70, 70, 70, 60, 70];
    var _ord_x = [_ox0];
    for (var _oc = 0; _oc < array_length(_ord_col_w); _oc++) {
        array_push(_ord_x, _ord_x[_oc] + _ord_col_w[_oc]);
    }
    var _ord_full_w = _ord_x[array_length(_ord_x) - 1] - _ox0;

    draw_set_font(fnt_c64_tiny);

    // ── SONG SELECTOR ── < NAME (n/N) >  + ADD  DEL
    // Sits above the order table because the table below it IS this song's
    // order; changing the selection swaps the whole panel's contents.
    var _sgy = _oy0 - 62;

    var _sg_px1 = _ox0;
    var _sg_px2 = _sg_px1 + 18;
    var _sg_p_hov = point_in_rectangle(_mx, _my, _sg_px1, _sgy, _sg_px2, _sgy + 18);
    draw_set_color(_sg_p_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_sg_px1, _sgy, _sg_px2, _sgy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_sg_px1 + 9, _sgy + 4, "<");
    draw_set_halign(fa_left);
    if (_sg_p_hov && mouse_check_button_pressed(mb_left)) {
        _m.sel_song              = max(0, _m.sel_song - 1);
        _m.sel_order_row         = 0;
        _m.order_scroll          = 0;
        _m.song_playing          = false;
        _m.playing               = false;
        _m.song_name_edit_active = false;
    }

    var _sg_nx1 = _sg_px2 + 6;
    var _sg_nx2 = _sg_nx1 + 190;
    var _sg_n_hov = point_in_rectangle(_mx, _my, _sg_nx1, _sgy, _sg_nx2, _sgy + 18);
    draw_set_color(make_color_rgb(20, 20, 32));
    draw_rectangle(_sg_nx1, _sgy, _sg_nx2, _sgy + 18, false);
    draw_set_halign(fa_center);
    if (_m.song_name_edit_active) {
        var _sg_blink = (current_time mod 600) < 300;
        var _sg_disp  = _sg_blink ? string_insert("|", _m.song_name_edit_buf, _m.song_name_edit_cursor + 1) : _m.song_name_edit_buf;
        draw_set_color(c_lime);
        draw_text((_sg_nx1 + _sg_nx2) * 0.5, _sgy + 4, _sg_disp);
    } else {
        draw_set_color(_sg_n_hov ? c_aqua : make_color_rgb(255, 200, 100));
        draw_text((_sg_nx1 + _sg_nx2) * 0.5, _sgy + 4,
            _cur_song.name + "  (" + string(_m.sel_song + 1) + "/" + string(array_length(_m.songs)) + ")");
        if (_sg_n_hov && mouse_check_button_pressed(mb_left)) {
            _m.song_name_edit_active = true;
            _m.song_name_edit_buf    = _cur_song.name;
            _m.song_name_edit_cursor = string_length(_cur_song.name);
            _m.edit_active           = false;
            _m.instr_edit_active     = false;
            _m.instr_name_edit_active = false;
        }
    }
    draw_set_halign(fa_left);

    var _sg_nnx1 = _sg_nx2 + 6;
    var _sg_nnx2 = _sg_nnx1 + 18;
    var _sg_nn_hov = point_in_rectangle(_mx, _my, _sg_nnx1, _sgy, _sg_nnx2, _sgy + 18);
    draw_set_color(_sg_nn_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_sg_nnx1, _sgy, _sg_nnx2, _sgy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_sg_nnx1 + 9, _sgy + 4, ">");
    draw_set_halign(fa_left);
    if (_sg_nn_hov && mouse_check_button_pressed(mb_left)) {
        _m.sel_song              = min(array_length(_m.songs) - 1, _m.sel_song + 1);
        _m.sel_order_row         = 0;
        _m.order_scroll          = 0;
        _m.song_playing          = false;
        _m.playing               = false;
        _m.song_name_edit_active = false;
    }

    var _sg_ax1 = _sg_nnx2 + 16;
    var _sg_ax2 = _sg_ax1 + 90;
    var _sg_a_hov = point_in_rectangle(_mx, _my, _sg_ax1, _sgy, _sg_ax2, _sgy + 18);
    draw_set_color(_sg_a_hov ? make_color_rgb(60, 200, 80) : make_color_rgb(20, 100, 40));
    draw_rectangle(_sg_ax1, _sgy, _sg_ax2, _sgy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_sg_ax1 + _sg_ax2) * 0.5, _sgy + 4, "+ SONG");
    draw_set_halign(fa_left);
    if (_sg_a_hov && mouse_check_button_pressed(mb_left)) {
        var _sg_num = string(array_length(_m.songs));
        while (string_length(_sg_num) < 2) { _sg_num = "0" + _sg_num; }
        array_push(_m.songs, {
            name     : "SONG " + _sg_num,
            order    : [ { v1: 0, v2: -1, v3: -1, repeat_short: false, force_len: 0 } ],
            loop     : true,
            loop_row : 0
        });
        _m.sel_song            = array_length(_m.songs) - 1;
        _m.sel_order_row       = 0;
        _m.order_scroll        = 0;
        _m.song_playing        = false;
        _m.playing             = false;
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    // Last song can't be deleted — the emitter and the whole editor assume at
    // least one exists, same guard the pattern bank uses.
    var _sg_dx1   = _sg_ax2 + 8;
    var _sg_dx2   = _sg_dx1 + 90;
    var _sg_d_lock = (array_length(_m.songs) <= 1);
    var _sg_d_hov  = !_sg_d_lock && point_in_rectangle(_mx, _my, _sg_dx1, _sgy, _sg_dx2, _sgy + 18);
    draw_set_color(_sg_d_lock ? make_color_rgb(55, 40, 40) : (_sg_d_hov ? make_color_rgb(200, 60, 60) : make_color_rgb(100, 30, 30)));
    draw_rectangle(_sg_dx1, _sgy, _sg_dx2, _sgy + 18, false);
    draw_set_color(_sg_d_lock ? make_color_rgb(100, 80, 80) : c_white);
    draw_set_halign(fa_center);
    draw_text((_sg_dx1 + _sg_dx2) * 0.5, _sgy + 4, "DEL SONG");
    draw_set_halign(fa_left);
    if (_sg_d_hov && mouse_check_button_pressed(mb_left)) {
        array_delete(_m.songs, _m.sel_song, 1);
        _m.sel_song            = clamp(_m.sel_song, 0, array_length(_m.songs) - 1);
        _m.sel_order_row       = 0;
        _m.order_scroll        = 0;
        _m.song_playing        = false;
        _m.playing             = false;
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    // ── SONG NAME TEXT ENTRY ──
    if (_m.song_name_edit_active) {
        if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_escape)) {
            if (keyboard_check_pressed(vk_enter) && string_trim(_m.song_name_edit_buf) != "") {
                _cur_song.name         = string_upper(string_trim(_m.song_name_edit_buf));
                global.undo_dirty      = true;
                global.addresses_dirty = true;
            }
            _m.song_name_edit_active = false;
            keyboard_string = "";
        } else if (keyboard_check_pressed(vk_backspace) && _m.song_name_edit_cursor > 0) {
            _m.song_name_edit_buf    = string_delete(_m.song_name_edit_buf, _m.song_name_edit_cursor, 1);
            _m.song_name_edit_cursor -= 1;
        } else if (keyboard_string != "") {
            var _sg_added = scr_strip_key_ghosts(keyboard_string);
            if (_sg_added != "" && string_length(_m.song_name_edit_buf) < 20) {
                _m.song_name_edit_buf    = string_insert(_sg_added, _m.song_name_edit_buf, _m.song_name_edit_cursor + 1);
                _m.song_name_edit_cursor += string_length(_sg_added);
            }
            keyboard_string = "";
        }
    }

    draw_set_color(make_color_rgb(255, 200, 100));
    draw_text(_ox0, _oy0 - 34, "SONG ORDER");

    var _ord_hdr = ["#", "V1", "V2", "V3", " REPEAT", " SIZE"];
    for (var _ohi = 0; _ohi < array_length(_ord_hdr); _ohi++) {
        draw_set_color(make_color_rgb(120, 120, 160));
        draw_set_halign(fa_center);
        draw_text(_ord_x[_ohi] + (_ord_col_w[_ohi] * 0.5), _oy0 - 16, _ord_hdr[_ohi]);
        draw_set_halign(fa_left);
    }

    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_ox0 - 4, _oy0 - 2, _ox0 + _ord_full_w + 4, _oy0 + _ord_vis * _ord_row_h + 2, false);
    draw_set_color(make_color_rgb(100, 100, 140));
    draw_rectangle(_ox0 - 4, _oy0 - 2, _ox0 + _ord_full_w + 4, _oy0 + _ord_vis * _ord_row_h + 2, true);

    _m.order_scroll = clamp(_m.order_scroll, 0, max(0, array_length(_cur_song.order) - _ord_vis));

    for (var _orv = 0; _orv < _ord_vis; _orv++) {
        var _ord_i = _orv + _m.order_scroll;
        if (_ord_i >= array_length(_cur_song.order)) {
            break;
        }
        var _orow = _cur_song.order[_ord_i];
        var _ory  = _oy0 + _orv * _ord_row_h;

        var _ord_active = (_m.song_playing && _ord_i == _m.song_order_row);
        var _ord_selected = (_ord_i == _m.sel_order_row);

        if (_ord_active) {
            draw_set_color(make_color_rgb(30, 90, 55));
        } else if (_ord_selected) {
            draw_set_color(make_color_rgb(45, 45, 70));
        } else {
            draw_set_color((_ord_i mod 2 == 0) ? make_color_rgb(20, 20, 32) : make_color_rgb(16, 16, 26));
        }
        draw_rectangle(_ox0, _ory, _ox0 + _ord_full_w, _ory + _ord_row_h, false);

        if (_cur_song.loop && _ord_i == real(_cur_song.loop_row)) {
            draw_set_color(c_aqua);
            draw_rectangle(_ox0, _ory, _ox0 + 3, _ory + _ord_row_h, false);   // left edge marker
        }

        draw_set_color(make_color_rgb(120, 120, 150));
        draw_set_halign(fa_center);
        draw_text(_ord_x[0] + (_ord_col_w[0] * 0.5), _ory + 6, string(_ord_i));
        draw_set_halign(fa_left);

        var _voice_keys = ["v1", "v2", "v3"];
        var _voice_colours = [make_color_rgb(120, 220, 255), make_color_rgb(255, 200, 120), make_color_rgb(180, 255, 150)];
        for (var _ovi = 0; _ovi < 3; _ovi++) {
            var _ocx = _ord_x[1 + _ovi];
            var _ocw = _ord_col_w[1 + _ovi];
            var _oc_hov = point_in_rectangle(_mx, _my, _ocx, _ory, _ocx + _ocw, _ory + _ord_row_h);
            var _oc_val = _orow[$ _voice_keys[_ovi]];

            draw_set_halign(fa_center);
            if (_oc_val < 0) {
                draw_set_color(make_color_rgb(80, 80, 90));
                draw_text(_ocx + (_ocw * 0.5), _ory + 6, "--");
            } else {
                draw_set_color(_voice_colours[_ovi]);
                var _oc_str = string(_oc_val);
                while (string_length(_oc_str) < 2) { _oc_str = "0" + _oc_str; }
                draw_text(_ocx + (_ocw * 0.5), _ory + 6, _oc_str);
            }
            draw_set_halign(fa_left);

            if (_oc_hov && mouse_check_button_pressed(mb_left)) {
                _se_push_undo(_m, _se_snap);
                if (keyboard_check(vk_control) || scr_cmd_held()) {
                    _orow[$ _voice_keys[_ovi]] = -1;
                } else {
                    _orow[$ _voice_keys[_ovi]] = (_oc_val + 1) mod array_length(_m.patterns);
                }
                _m.sel_order_row  = _ord_i;
                global.undo_dirty = true;
            }
            if (_oc_hov && mouse_check_button_pressed(mb_right)) {
                _se_push_undo(_m, _se_snap);
                var _oc_next = _oc_val - 1;
                if (_oc_next < -1) {
                    _oc_next = array_length(_m.patterns) - 1;
                }
                _orow[$ _voice_keys[_ovi]] = _oc_next;
                _m.sel_order_row  = _ord_i;
                global.undo_dirty = true;
            }
        }

        var _rsx = _ord_x[4];
        var _rsw = _ord_col_w[4];
        var _rs_hov = point_in_rectangle(_mx, _my, _rsx, _ory, _rsx + _rsw, _ory + _ord_row_h);
        draw_set_color(_orow.repeat_short ? c_lime : make_color_rgb(140, 90, 90));
        draw_set_halign(fa_center);
        draw_text(_rsx + (_rsw * 0.5), _ory + 6, _orow.repeat_short ? "RPT" : "NO");
        draw_set_halign(fa_left);
        if (_rs_hov && mouse_check_button_pressed(mb_left)) {
            _se_push_undo(_m, _se_snap);
            _orow.repeat_short = !_orow.repeat_short;
            global.undo_dirty  = true;
        }

        var _flx = _ord_x[5];
        var _flw = _ord_col_w[5];
        var _fl_dnx1 = _flx;
        var _fl_dnx2 = _flx + 16;
        var _fl_upx1 = _flx + _flw - 16;
        var _fl_upx2 = _flx + _flw;
        var _fl_hov_dn = point_in_rectangle(_mx, _my, _fl_dnx1, _ory, _fl_dnx2, _ory + _ord_row_h);
        var _fl_hov_up = point_in_rectangle(_mx, _my, _fl_upx1, _ory, _fl_upx2, _ory + _ord_row_h);

        draw_set_color(_fl_hov_dn ? c_aqua : make_color_rgb(100, 100, 100));
        draw_text(_fl_dnx1 + 4, _ory + 6, "-");
        draw_set_color(_fl_hov_up ? c_aqua : make_color_rgb(100, 100, 100));
        draw_text(_fl_upx1 + 4, _ory + 6, "+");

        draw_set_color((_orow.force_len > 0) ? c_aqua : make_color_rgb(90, 90, 110));
        draw_set_halign(fa_center);
        draw_text(_flx + (_flw * 0.5), _ory + 6, (_orow.force_len > 0) ? string(_orow.force_len) : "OFF");
        draw_set_halign(fa_left);

        if (_fl_hov_dn && mouse_check_button_pressed(mb_left)) {
            _orow.force_len        = max(0, _orow.force_len - 4);
            global.addresses_dirty = true;
        }
        if (_fl_hov_up && mouse_check_button_pressed(mb_left)) {
            _orow.force_len        = min(128, _orow.force_len + 4);
            global.addresses_dirty = true;
        }

        var _row_hov = point_in_rectangle(_mx, _my, _ox0, _ory, _ox0 + _ord_full_w, _ory + _ord_row_h);
        if (_row_hov && mouse_check_button_pressed(mb_left)
        &&  !point_in_rectangle(_mx, _my, _ord_x[1], _ory, _ord_x[6], _ory + _ord_row_h)) {
            _m.sel_order_row = _ord_i;
        }
    }

    // ── COLUMN DIVIDERS — drawn after rows so they sit on top of each
    // row's background fill instead of being painted over by it. ──
    draw_set_color(make_color_rgb(100, 100, 140));
    for (var _odiv = 1; _odiv <= 5; _odiv++) {
        draw_line(_ord_x[_odiv], _oy0 - 20, _ord_x[_odiv], _oy0 + _ord_vis * _ord_row_h);
    }

    var _oby = _oy0 + _ord_vis * _ord_row_h + 10;
    var _oax1 = _ox0;
    var _oax2 = _oax1 + 90;
    var _oa_hov = point_in_rectangle(_mx, _my, _oax1, _oby, _oax2, _oby + 18);
    draw_set_color(_oa_hov ? make_color_rgb(60, 200, 80) : make_color_rgb(20, 100, 40));
    draw_rectangle(_oax1, _oby, _oax2, _oby + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_oax1 + _oax2) * 0.5, _oby + 4, "+ ADD ROW");
    draw_set_halign(fa_left);
    if (_oa_hov && mouse_check_button_pressed(mb_left)) {
        array_push(_cur_song.order, { v1: 0, v2: -1, v3: -1, repeat_short: false, force_len: 0 });
        _m.sel_order_row = array_length(_cur_song.order) - 1;
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    // ── LOOP toggle + SET LOOP POINT ──
    var _llx1 = _oax2 + 8;
    var _llx2 = _llx1 + 60;
    var _ll_hov = point_in_rectangle(_mx, _my, _llx1, _oby, _llx2, _oby + 18);
    draw_set_color(_cur_song.loop ? make_color_rgb(30, 120, 60) : make_color_rgb(70, 40, 40));
    draw_rectangle(_llx1, _oby, _llx2, _oby + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_llx1 + _llx2) * 0.5, _oby + 4, _cur_song.loop ? "LOOP" : "NO LOOP");
    draw_set_halign(fa_left);
    if (_ll_hov && mouse_check_button_pressed(mb_left)) {
        _cur_song.loop         = !_cur_song.loop;
        global.addresses_dirty = true;
    }

    // Set the currently-selected order row as the loop-back point. Only
    // meaningful with LOOP on, but left clickable regardless — flipping LOOP
    // on later shouldn't require re-picking the point.
    var _lpx1 = _llx2 + 8;
    var _lpx2 = _lpx1 + 130;
    var _lp_hov2 = point_in_rectangle(_mx, _my, _lpx1, _oby, _lpx2, _oby + 18);
    draw_set_color(_lp_hov2 ? make_color_rgb(60, 130, 180) : make_color_rgb(30, 70, 100));
    draw_rectangle(_lpx1, _oby, _lpx2, _oby + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_lpx1 + _lpx2) * 0.5, _oby + 4, "SET LOOP @ ROW " + string(_m.sel_order_row));
    draw_set_halign(fa_left);
    if (_lp_hov2 && mouse_check_button_pressed(mb_left)) {
        _cur_song.loop_row     = _m.sel_order_row;
        global.addresses_dirty = true;
    }

    var _odx1 = _lpx2 + 16;
    var _odx2 = _odx1 + 90;
    var _od_lock = (array_length(_cur_song.order) <= 1);
    var _od_hov  = !_od_lock && point_in_rectangle(_mx, _my, _odx1, _oby, _odx2, _oby + 18);
    draw_set_color(_od_lock ? make_color_rgb(55, 40, 40) : (_od_hov ? make_color_rgb(200, 60, 60) : make_color_rgb(100, 30, 30)));
    draw_rectangle(_odx1, _oby, _odx2, _oby + 18, false);
    draw_set_color(_od_lock ? make_color_rgb(100, 80, 80) : c_white);
    draw_set_halign(fa_center);
    draw_text((_odx1 + _odx2) * 0.5, _oby + 4, "DEL ROW");
    draw_set_halign(fa_left);
    if (_od_hov && mouse_check_button_pressed(mb_left)) {
        array_delete(_cur_song.order, _m.sel_order_row, 1);
        _m.sel_order_row = clamp(_m.sel_order_row, 0, array_length(_cur_song.order) - 1);
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 110, 150));
    draw_text(_ox0, _oby + 24, "CLICK CELL/ROW: SELECT + NEXT PATTERN   |   RMB: PREV   |   CTRL+CLICK: NONE (--)");
    draw_set_font(fnt_c64_tiny);

    if (point_in_rectangle(_mx, _my, _ox0 - 4, _oy0 - 2, _ox0 + _ord_full_w + 4, _oy0 + _ord_vis * _ord_row_h + 2)) {
        if (mouse_wheel_up())   { _m.order_scroll = max(0, _m.order_scroll - 1); }
        if (mouse_wheel_down()) { _m.order_scroll = min(max(0, array_length(_cur_song.order) - _ord_vis), _m.order_scroll + 1); }
    }

    if (_m.warn_timer > 0) {
        draw_set_color(make_color_rgb(255, 200, 90));
        draw_text(_ox0, _oby + 44, _m.warn_msg);
        _m.warn_timer -= 1;
    }

    // ═════════════════════════════════════════════════════════════════════
    // FAR RIGHT PANEL — INSTRUMENTS
    // ═════════════════════════════════════════════════════════════════════
    var _ix0 = _ox0 + _ord_full_w + 80;
    scr_sound_editor_draw_instruments(_m, _ix0, _oy0, _mx, _my);

    draw_set_alpha(1.0);
    draw_set_color(c_white);
    draw_set_halign(fa_left);
}