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
    // The piano takes the bottom _pno_h pixels; everything else lays out above
    // it, so from here on _vy2 is the bottom of that upper area.
    var _pno_h    = 112;
    var _vy2_full = _vy2;
    _vy2 = _vy2 - _pno_h;
    var _m = _asset.meta;
    _m.pattern_hover_tip = "";
    // Pattern-command guide: while it's open nothing behind it reacts to the
    // mouse or keys; only its CLOSE button or Escape closes it.
    var _cg_mx = _mx;
    var _cg_my = _my;
    var _cg_click = mouse_check_button_pressed(mb_left);
    var _cg_esc = keyboard_check_pressed(vk_escape);
    var _cg_open = global.music_cmd_guide_open;
    if (_cg_open) {
        _mx = -100000;
        _my = -100000;
        io_clear();
    }
    if (!variable_struct_exists(_m, "order_pattern_edit_active")) _m.order_pattern_edit_active = false;
    // A click elsewhere cancels the pending entry before another control receives focus.
    if (_m.order_pattern_edit_active && mouse_check_button_pressed(mb_left)) {
        _m.order_pattern_edit_active = false;
        keyboard_string = "";
    }
    var _order_typing = _m.order_pattern_edit_active;

    // ── DIGI TRACK ── shape every row / digi pattern, and keep the SAMPLES
    // panel's clicks from reaching whatever it is drawn over (it is drawn
    // last, at the rect it used last frame).
    scr_digi_ensure(_m);
    var _dg_pmx = _mx;
    var _dg_pmy = _my;
    if (_m.dg_slots_open) {
        var _dpr = _m.dg_panel_rect;
        if (point_in_rectangle(_mx, _my, _dpr[0], _dpr[1], _dpr[2], _dpr[3])) {
            _mx = -100000;
            _my = -100000;
        }
    }

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
    // Migrate old assets once; active patterns are also checked by _se_ensure_steps.
    if (_pat_needs_reset || !variable_struct_exists(_m, "cmd_fields_migrated")) {
        for (var _cbp = 0; _cbp < array_length(_m.patterns); _cbp++) {
            var _cb_steps = _m.patterns[_cbp].steps;
            for (var _cbs = 0; _cbs < array_length(_cb_steps); _cbs++) {
                if (is_undefined(_cb_steps[_cbs][$ "cmd"])) {
                    _cb_steps[_cbs].cmd     = -1;
                    _cb_steps[_cbs].cmd_val = 0;
                }
            }
        }
        _m.cmd_fields_migrated = true;
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
    if (!variable_struct_exists(_m, "sid_page")) _m.sid_page = 0;
    _m.sid_page = clamp(_m.sid_page, 0, scr_music_sid_count(_m) - 1);
    var _voice_offset = _m.sid_page * 3;
    var _page_keys = ["v" + string(_voice_offset + 1), "v" + string(_voice_offset + 2), "v" + string(_voice_offset + 3)];

    if (!variable_struct_exists(_m, "sel_order_row")) _m.sel_order_row = 0;
    _m.sel_order_row = clamp(_m.sel_order_row, 0, array_length(_cur_song.order) - 1);
    if (!variable_struct_exists(_m, "order_scroll")) _m.order_scroll = 0;

    if (!variable_struct_exists(_m, "sel_voice"))   _m.sel_voice   = 0;
    // 0 = the note column, 1 = the command column of the selected voice.
    if (!variable_struct_exists(_m, "sel_sub"))     _m.sel_sub     = 0;
    // Instrument panel's command dropdowns ("" = none open) and ? help table.
    if (!variable_struct_exists(_m, "cmd_menu_open")) _m.cmd_menu_open = "";
    if (!variable_struct_exists(_m, "cmd_help_open")) _m.cmd_help_open = false;
    // Command being typed: digits so far, and the cell they belong to.
    if (!variable_struct_exists(_m, "cmd_entry_str"))   _m.cmd_entry_str   = "";
    if (!variable_struct_exists(_m, "cmd_entry_voice")) _m.cmd_entry_voice = -1;
    if (!variable_struct_exists(_m, "cmd_entry_step"))  _m.cmd_entry_step  = -1;
    if (!variable_struct_exists(_m, "sel_step"))    _m.sel_step    = 0;
    if (!variable_struct_exists(_m, "list_scroll")) _m.list_scroll = 0;
    if (!variable_struct_exists(_m, "undo_stack"))  _m.undo_stack  = [];
    if (!variable_struct_exists(_m, "redo_stack"))  _m.redo_stack  = [];
    if (!variable_struct_exists(_m, "warn_msg"))    _m.warn_msg    = "";
    if (!variable_struct_exists(_m, "warn_timer"))  _m.warn_timer  = 0;
    if (!variable_struct_exists(_m, "cur_octave"))  _m.cur_octave  = 4;
    // Piano: SPLIT (2 octaves per voice) or FULL (6 octaves); the key last
    // hovered (and its voice) so a key only plays once per visit.
    if (!variable_struct_exists(_m, "pno_mode"))    _m.pno_mode    = "SPLIT";
    if (!variable_struct_exists(_m, "pno_hover"))   _m.pno_hover   = -1;
    if (!variable_struct_exists(_m, "pno_hover_v")) _m.pno_hover_v = 0;
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
        if (!variable_struct_exists(_adb_instr, "vib_delay"))   _adb_instr.vib_delay   = 0;
        if (!variable_struct_exists(_adb_instr, "vib_speed"))   _adb_instr.vib_speed   = 0;
        if (!variable_struct_exists(_adb_instr, "vib_depth"))   _adb_instr.vib_depth   = 0;
        if (!variable_struct_exists(_adb_instr, "filt"))        _adb_instr.filt        = 0;
    }

    // Row-audition playback (Space / Shift+Space) — loops the current order row
    if (!variable_struct_exists(_m, "playing"))     _m.playing     = false;
    if (!variable_struct_exists(_m, "play_row"))    _m.play_row    = 0;
    if (!variable_struct_exists(_m, "play_tick"))   _m.play_tick   = 0;
    if (!variable_struct_exists(_m, "play_speed"))  _m.play_speed  = 6;
    if (!variable_struct_exists(_m, "filt_mode"))   _m.filt_mode   = 0;
    if (!variable_struct_exists(_m, "filt_res"))    _m.filt_res    = 0;
    if (!variable_struct_exists(_m, "filt_cut"))    _m.filt_cut    = 1024;
    if (!variable_struct_exists(_m, "note_table"))  _m.note_table  = [];
    if (!variable_struct_exists(_m, "free_voices")) _m.free_voices = false;
    if (!variable_struct_exists(_m, "chip_model"))  _m.chip_model  = 1;
    // The preview chip follows the song's saved choice.
    if (global.sid64_ok && global.sid64_model != _m.chip_model) {
        global.sid64_model = _m.chip_model;
        scr_sid64_reconfigure();
        _m.playing = false;
        _m.song_playing = false;
    }
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
            array_push(_pat.steps, { instr_idx: -1, note: "", empty: true, cmd: -1, cmd_val: 0 });
        }
        // Steps saved before the command column existed: cmd -1 = no command.
        for (var _bfi = 0; _bfi < array_length(_pat.steps); _bfi++) {
            var _bf_st = _pat.steps[_bfi];
            if (is_undefined(_bf_st[$ "cmd"])) {
                _bf_st.cmd     = -1;
                _bf_st.cmd_val = 0;
            }
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
                array_push(_steps, { instr_idx: _st.instr_idx, note: _st.note, empty: _st.empty,
                                     cmd: _st.cmd, cmd_val: _st.cmd_val });
            }
            array_push(_pats, { name: _src.name, steps: _steps, pattern_len: _src.pattern_len });
        }
        return _pats;
    };
    // Each undo entry is the patterns before the edit plus where the cursor
    // was when it was made, so undo/redo can put the cursor back on the edit.
    // Moves the cursor (and the order row / scroll it needs) to an undo entry's
    // location, dropping any selection or half-typed command.
    var _se_undo_goto = function(_mm, _ent, _visrows) {
        if (variable_struct_exists(_ent, "chip")) _mm.sid_page = clamp(_ent.chip, 0, scr_music_sid_count(_mm) - 1);
        _mm.sel_order_row = _ent.ord;
        _mm.sel_voice     = _ent.voice;
        _mm.sel_step      = _ent.step;
        _mm.sel_sub       = _ent.sub;
        _mm.sel_anchor_voice = _ent.voice;
        _mm.sel_anchor_step  = _ent.step;
        _mm.cmd_entry_str    = "";
        _mm.edit_active      = false;
        if (_mm.sel_step < _mm.list_scroll || _mm.sel_step >= _mm.list_scroll + _visrows) {
            _mm.list_scroll = max(0, _mm.sel_step - floor(_visrows / 2));
        }
    };
    var _se_push_undo = function(_mm, _snapf) {
        array_push(_mm.undo_stack, {
            pats  : _snapf(_mm),
            voice : _mm.sel_voice,
            step  : _mm.sel_step,
            sub   : _mm.sel_sub,
            chip  : _mm.sid_page,
            ord   : _mm.sel_order_row,
            // digi track: its data and whether the edit was made in its lane
            dgs    : scr_digi_snapshot(_mm),
            dgf    : _mm.dg_focus,
            dgstep : _mm.dg_sel_step
        });
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

    if (_order_typing) {
        if (_m.order_pattern_edit_song != _cur_song || _m.order_pattern_edit_page != _m.sid_page) {
            _m.order_pattern_edit_active = false;
        } else {
            var _typed = scr_strip_key_ghosts(keyboard_string);
            for (var _ti = 1; _ti <= string_length(_typed); _ti++) {
                var _tc = string_char_at(_typed, _ti);
                if ((_tc >= "0" && _tc <= "9") || _tc == "-") {
                    if (_m.order_pattern_edit_replace) { _m.order_pattern_edit_buf = ""; _m.order_pattern_edit_replace = false; }
                    if (string_length(_m.order_pattern_edit_buf) < 5) _m.order_pattern_edit_buf += _tc;
                }
            }
            if (keyboard_check_pressed(vk_backspace) || keyboard_check_pressed(vk_delete)) {
                if (_m.order_pattern_edit_replace || keyboard_check_pressed(vk_delete)) _m.order_pattern_edit_buf = "";
                else _m.order_pattern_edit_buf = string_delete(_m.order_pattern_edit_buf, string_length(_m.order_pattern_edit_buf), 1);
                _m.order_pattern_edit_replace = false;
            }
            if (keyboard_check_pressed(vk_escape)) _m.order_pattern_edit_active = false;
            if (keyboard_check_pressed(vk_enter)) {
                var _entry = _m.order_pattern_edit_buf;
                var _valid = true;
                var _number = -1;
                if (_entry != "" && _entry != "-" && _entry != "--") {
                    for (var _ei = 1; _ei <= string_length(_entry); _ei++) {
                        var _ec = string_char_at(_entry, _ei);
                        if (_ec < "0" || _ec > "9") _valid = false;
                    }
                    if (_valid) _number = real(_entry);
                }
                if (_valid && _number < array_length(_m.patterns)) {
                    _m.order_pattern_edit_row[$ _m.order_pattern_edit_key] = _number;
                    global.undo_dirty = true;
                    global.addresses_dirty = true;
                    _m.order_pattern_edit_active = false;
                }
            }
        }
        keyboard_string = "";
    }

    // ── RESOLVE THE 3 ACTIVE PATTERNS FOR THE CURRENT ORDER ROW ──
    var _order_row = _cur_song.order[_m.sel_order_row];
    var _col_pat_idx = [scr_music_sid_pattern(_order_row, _voice_offset), scr_music_sid_pattern(_order_row, _voice_offset + 1), scr_music_sid_pattern(_order_row, _voice_offset + 2)];
    var _col_pat = [noone, noone, noone];
    for (var _cpi = 0; _cpi < 3; _cpi++) {
        if (_col_pat_idx[_cpi] >= 0 && _col_pat_idx[_cpi] < array_length(_m.patterns)) {
            _col_pat[_cpi] = _m.patterns[_col_pat_idx[_cpi]];
            _se_ensure_steps(_col_pat[_cpi]);
        }
    }

    // ── CARRIED INSTRUMENT PER LANE ──
    // A note row with no instrument (e.g. a JXX tie) keeps the instrument the
    // voice is already playing. _carry_ins[lane][row] = that instrument
    // (-1 = none yet), worked out from every earlier order row of this song.
    var _carry_ins = [[], [], []];
    for (var _ci = 0; _ci < 3; _ci++) {
        var _run_ins = -1;
        for (var _co = 0; _co < _m.sel_order_row; _co++) {
            var _cp_idx = scr_music_sid_pattern(_cur_song.order[_co], _voice_offset + _ci);
            if (_cp_idx >= 0 && _cp_idx < array_length(_m.patterns)) {
                var _cp_pat = _m.patterns[_cp_idx];
                _se_ensure_steps(_cp_pat);
                var _cp_n = min(_cp_pat.pattern_len, array_length(_cp_pat.steps));
                for (var _cs = 0; _cs < _cp_n; _cs++) {
                    var _cp_st = _cp_pat.steps[_cs];
                    if (!_cp_st.empty && _cp_st.instr_idx >= 0) {
                        _run_ins = _cp_st.instr_idx;
                    }
                }
            }
        }
        if (_col_pat[_ci] != noone) {
            var _cl_n = min(_col_pat[_ci].pattern_len, array_length(_col_pat[_ci].steps));
            for (var _cs2 = 0; _cs2 < _cl_n; _cs2++) {
                var _cl_st = _col_pat[_ci].steps[_cs2];
                if (!_cl_st.empty && _cl_st.instr_idx >= 0) {
                    _run_ins = _cl_st.instr_idx;
                }
                _carry_ins[_ci][_cs2] = _run_ins;
            }
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

    var _se_row_target_len = function(_mm, _row) { return scr_music_sid_length(_mm, _row); };

    // ── LAYOUT ──
    // Grid metrics. Cells use fnt_c64_tiny at _txt_scale; the row height is
    // set below so 16 rows always fit (see _vis).
    var _txt_scale = 1.5;
    var _row_h    = 30;
    var _vis      = 16;
    var _lane_w   = 140;
    var _cmd_off  = 90;     // command column's x offset inside a voice lane
    var _gutter_w = 48;
    var _lane_gap = 12;

    // ═════════════════════════════════════════════════════════════════════
    // PLAYBACK — ROW AUDITION (Space / Shift+Space, loops sel_order_row)
    // ═════════════════════════════════════════════════════════════════════
    // Playback controls occupy a dedicated row above status/progress.
    var _transport_action = "";
    var _transport_x = _vx1 + 20;
    var _transport_y = _cy + 18;
    if(!variable_struct_exists(_m,"voice_mask")) _m.voice_mask=7;
    draw_set_font_l(fnt_c64_tiny);draw_set_color(c_white);
    draw_text_l(_vx1+540,_transport_y+5,"VOICES:");
    for(var _mv=0;_mv<3;_mv++) {
        var _bit=1<<_mv;
        if(scr_sfx_maker_button(_vx1+620+_mv*76,_transport_y,70,string(_voice_offset+_mv+1)+((scr_music_sid_mask(_m, _m.sid_page)&_bit)?" ON":" OFF"),_mx,_my)) {
            var _mask_key = (_m.sid_page == 0) ? "voice_mask" : "sid_mask_" + string(_m.sid_page);
            _m[$ _mask_key] = scr_music_sid_mask(_m, _m.sid_page) ^ _bit;
            if (!(_m[$ _mask_key] & _bit)) scr_sound_preview_free_channel(_mv);
            global.addresses_dirty=true;global.undo_dirty=true;
        }
    }
    // SMP: the digi track on/off — preview and compiled tune, like a voice.
    var _smp_lab = "SMP OFF";
    if (_m.digi_on == 1) {
        _smp_lab = "SMP ON";
    }
    if (scr_sfx_maker_button(_vx1 + 620 + 3 * 76, _transport_y, 90, _smp_lab, _mx, _my)) {
        _m.digi_on = 1 - _m.digi_on;
        if (_m.digi_on == 0) {
            scr_digi_stop(_m);
        }
        global.addresses_dirty = true;
        global.undo_dirty = true;
    }

    // ── SONG FILTER ── what the player writes when the song starts: mode
    // (LP/BP/HP, combinable), resonance, cutoff. Instruments with FILTER ON are
    // routed through it. CHIP picks the preview's SID model only — the real
    // machine decides what the compiled song sounds like.
    var _fl_x = _vx1 + 950;
    var _fl_y = _transport_y;
    draw_set_color(c_white);
    draw_text_l(_fl_x, _fl_y + 5, "FILTER:");
    var _fl_modes = ["LP", "BP", "HP"];
    for (var _fmi = 0; _fmi < 3; _fmi++) {
        var _fbit = 1 << _fmi;
        var _fbx = _fl_x + 62 + _fmi * 38;
        var _fon = ((_m.filt_mode & _fbit) != 0);
        var _fhov = point_in_rectangle(_mx, _my, _fbx, _fl_y, _fbx + 34, _fl_y + 24);
        if (_fon) {
            draw_set_color(make_color_rgb(40, 110, 170));
        } else if (_fhov) {
            draw_set_color(make_color_rgb(65, 80, 100));
        } else {
            draw_set_color(make_color_rgb(30, 38, 52));
        }
        draw_rectangle(_fbx, _fl_y, _fbx + 34, _fl_y + 24, false);
        draw_set_color(c_white);
        draw_text_l(_fbx + 8, _fl_y + 5, _fl_modes[_fmi]);
        if (_fhov && mouse_check_button_pressed(mb_left)) {
            _m.filt_mode = _m.filt_mode ^ _fbit;
            global.undo_dirty = true;
            global.addresses_dirty = true;
        }
    }
    // RES - n +   and   CUT - $xxx +  (Shift = fine / coarse)
    var _fl_steps = [
        { lbl: "RES", key: "filt_res", mx: 15,   fine: 1, coarse: 1,   hex: false, w: 20 },
        { lbl: "CUT", key: "filt_cut", mx: 2047, fine: 1, coarse: 32,  hex: true,  w: 36 }
    ];
    var _fsx = _fl_x + 184;
    for (var _fsi = 0; _fsi < 2; _fsi++) {
        var _fs = _fl_steps[_fsi];
        var _fval = _m[$ _fs.key];
        draw_set_color(make_color_rgb(150, 150, 180));
        draw_text_l(_fsx, _fl_y + 5, _fs.lbl);
        var _fdn = _fsx + 32;
        var _fup = _fdn + 18 + _fs.w + 6;
        var _fdn_h = point_in_rectangle(_mx, _my, _fdn, _fl_y + 2, _fdn + 14, _fl_y + 22);
        var _fup_h = point_in_rectangle(_mx, _my, _fup, _fl_y + 2, _fup + 14, _fl_y + 22);
        draw_set_color(make_color_rgb(100, 100, 100));
        if (_fdn_h) { draw_set_color(c_aqua); }
        draw_text_l(_fdn + 2, _fl_y + 5, "-");
        draw_set_color(make_color_rgb(100, 100, 100));
        if (_fup_h) { draw_set_color(c_aqua); }
        draw_text_l(_fup + 2, _fl_y + 5, "+");
        var _fstr = string(_fval);
        if (_fs.hex) {
            _fstr = string_upper(decimal_to_hex(_fval));
            while (string_length(_fstr) < 3) { _fstr = "0" + _fstr; }
            _fstr = "$" + _fstr;
        }
        draw_set_color(c_white);
        draw_text_l(_fdn + 18, _fl_y + 5, _fstr);
        var _fstep = _fs.coarse;
        if (keyboard_check(vk_shift)) {
            _fstep = _fs.fine;
        }
        if (_fdn_h && mouse_check_button_pressed(mb_left)) {
            _m[$ _fs.key] = max(0, _fval - _fstep);
            global.undo_dirty = true;
            global.addresses_dirty = true;
        }
        if (_fup_h && mouse_check_button_pressed(mb_left)) {
            _m[$ _fs.key] = min(_fs.mx, _fval + _fstep);
            global.undo_dirty = true;
            global.addresses_dirty = true;
        }
        _fsx = _fup + 26;
    }
    // Preview / export chip, saved with the song.
    if (global.sid64_ok) {
        var _chip_lbl = "CHIP: 6581";
        if (_m.chip_model == 1) {
            _chip_lbl = "CHIP: 8580";
        }
        if (scr_sfx_maker_button(_fsx + 10, _fl_y - 1, 96, _chip_lbl, _mx, _my)) {
            _m.chip_model = 1 - _m.chip_model;
            global.sid64_model = _m.chip_model;
            scr_sid64_reconfigure();
            _m.playing = false;
            _m.song_playing = false;
            global.undo_dirty = true;
        }
    }
    // Standalone .sid of this asset (the MACRO_SID_SONG player, assembled at a
    // chosen address, optional GoatTracker-style SFX entry at +6).
    if (scr_sfx_maker_button(_fsx + 122, _fl_y - 1, 110, "EXPORT SID", _mx, _my)) {
        scr_sound_editor_export_sid(_asset);
    }

    // In function-key order: F1 SONG, F2 HERE, F3 PAT, F4 STOP.
    var _transport_labels = ["PLAY SONG (F1)", "PLAY HERE (F2)", "PLAY PAT (F3)", "STOP (F4)"];
    var _transport_actions = ["SONG", "HERE", "PAT", "STOP"];
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);
    for (var _tb = 0; _tb < 4; _tb++) {
        var _tw = (_tb == 3) ? 80 : 124;
        var _tx = _transport_x + _tb * 132;
        var _thover = point_in_rectangle(_mx, _my, _tx, _transport_y, _tx + _tw, _transport_y + 24);
        draw_set_color(_thover ? make_color_rgb(65, 130, 155) : make_color_rgb(28, 60, 80));
        draw_rectangle(_tx, _transport_y, _tx + _tw, _transport_y + 24, false);
        var _t_lit = false;
        if (_transport_actions[_tb] == "PAT" && _m.playing) _t_lit = true;
        if ((_transport_actions[_tb] == "SONG" || _transport_actions[_tb] == "HERE") && _m.song_playing) _t_lit = true;
        if (_t_lit) {
            draw_set_color(c_lime);
        } else {
            draw_set_color(c_white);
        }
        draw_text_l(_tx + 10, _transport_y + 7, _transport_labels[_tb]);
        if (_thover && mouse_check_button_pressed(mb_left)) _transport_action = _transport_actions[_tb];
    }
    // Space in a text field belongs to that field, never to the transport.
    var _transport_typing = _m.edit_active || _m.instr_edit_active
                         || _m.instr_name_edit_active || _m.song_name_edit_active || _order_typing
                         || _m.instr_note_edit_active;
    // Function keys: F1 song from the start, F2 song from the cursor row (same
    // as PLAY HERE — carries on through the order list), F3 this pattern from
    // the top (looping), F4 stop.
    // They type nothing, so they also work while an instrument's text is open.
    var _fkeys_ok = !_m.edit_active && !_m.instr_name_edit_active && !_m.song_name_edit_active && !_order_typing
                 && !_m.instr_note_edit_active;
    if (_fkeys_ok) {
        if (keyboard_check_pressed(vk_f1)) {
            _transport_action = "SONG";
        } else if (keyboard_check_pressed(vk_f2)) {
            _transport_action = "HERE";
        } else if (keyboard_check_pressed(vk_f3)) {
            _transport_action = "PAT";
        } else if (keyboard_check_pressed(vk_f4)) {
            _transport_action = "STOP";
        }
    }
    // Space only ever auditions the selected instrument — C in the current
    // octave (plain pulse if no instrument is selected). Playback is F1-F4.
    // While an instrument's text is open, scr_sound_editor_draw_instruments
    // handles Space instead (it plays the text as typed).
    if (!_transport_typing && keyboard_check_pressed(vk_space)) {
        var _sp_note = "C-" + string(_m.cur_octave);
        if (_m.sel_instr >= 0 && _m.sel_instr < array_length(_m.instruments)) {
            scr_sound_instrument_preview_play(_m.instruments[_m.sel_instr], _sp_note, _m.sel_voice, -1, false, _m);
        } else {
            scr_sound_preview_play(_sp_note, "SQUARE", _m.sel_voice);
        }
    }
    if (_transport_action != "") {
        if (_transport_action != "STOP") {
            scr_sound_editor_commit_cell(_m, _se_push_undo, _se_snap, _col_pat);
            if (_m.instr_edit_active && _m.sel_instr >= 0 && _m.sel_instr < array_length(_m.instruments)) {
                scr_sound_editor_commit_instrument(_m, _m.instruments[_m.sel_instr]);
            }
        }
        scr_sound_editor_transport(_m, _cur_song, _transport_action);
    }
    var _preview_ready = true;
    var _preview_due = 0;
    var _streaming = global.sid64_stream.active;
    if (_streaming) {
        // reSID streaming: the player simulation drives position and audio; the
        // row-by-row loops below stay idle (_preview_due = 0).
        if (!scr_sid64_stream_update(_m)) {
            _m.playing = false;
            _m.song_playing = false;
        } else {
            if (_m.song_playing) {
                _m.song_order_row = _m.preview_display_order;
                _m.sel_order_row  = _m.preview_display_order;   // grid follows the song
            }
            var _st_row = _m.preview_display_step;
            if (_st_row < _m.list_scroll) {
                _m.list_scroll = _st_row;
            }
            if (_st_row >= _m.list_scroll + _vis) {
                _m.list_scroll = _st_row - _vis + 1;
            }
        }
    } else if (_m.playing || _m.song_playing) {
        _preview_ready = scr_sound_editor_preview_warm(_m);
        if (_preview_ready) _preview_due = scr_sound_editor_preview_due(_m, get_timer());
    }

    if (_m.playing) {
        var _pa_target = _se_row_target_len(_m, _order_row);
        for (var _pa_due = 0; _pa_due < _preview_due; _pa_due++) {
            _m.preview_display_order = _m.sel_order_row;
            _m.preview_display_step = _m.play_row;
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
                if (_p_step.empty || _p_step.note == "+++") {
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
            _m.play_row += 1;
            if (_m.play_row >= _pa_target) _m.play_row = 0;
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // PLAYBACK — FULL SONG (Ctrl+Space)
    // ═════════════════════════════════════════════════════════════════════
    if (_m.song_playing) {
        for (var _sp_due = 0; _sp_due < _preview_due && _m.song_playing; _sp_due++) {
        _m.song_order_row = clamp(_m.song_order_row, 0, array_length(_cur_song.order) - 1);
        _m.preview_display_order = _m.song_order_row;
        _m.preview_display_step = _m.song_master_row;
        var _sp_row    = _cur_song.order[_m.song_order_row];
        var _sp_target = _se_row_target_len(_m, _sp_row);
        var _sp_voices = [_sp_row.v1, _sp_row.v2, _sp_row.v3];

        {
            for (var _sv = 0; _sv < 3; _sv++) {
                var _sv_idx = _sp_voices[_sv];
                if (_sv_idx < 0 || _sv_idx >= array_length(_m.patterns)) {
                    continue;
                }
                var _sv_pat = _m.patterns[_sv_idx];
                _se_ensure_steps(_sv_pat);
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
                if (_sv_step.empty || _sv_step.note == "+++") {
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
            if (_m.song_master_row < _m.list_scroll) _m.list_scroll = _m.song_master_row;
            if (_m.song_master_row >= _m.list_scroll + _vis) _m.list_scroll = _m.song_master_row - _vis + 1;
            _m.song_master_row += 1;
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

    } // elapsed-time full-song row loop

    // Playback may have changed the selected order after the initial layout.
    // Refresh before drawing: never highlight a new row over the old patterns.
    _order_row = _cur_song.order[_m.sel_order_row];
    _grid_len = 16;
    for (var _refresh_v = 0; _refresh_v < 3; _refresh_v++) {
        var _refresh_p = scr_music_sid_pattern(_order_row, _voice_offset + _refresh_v);
        _col_pat_idx[_refresh_v] = _refresh_p;
        _col_pat[_refresh_v] = noone;
        if (_refresh_p >= 0 && _refresh_p < array_length(_m.patterns)) {
            _col_pat[_refresh_v] = _m.patterns[_refresh_p];
            _se_ensure_steps(_col_pat[_refresh_v]);
            _grid_len = max(_grid_len, _col_pat[_refresh_v].pattern_len);
        }
    }
    // TIMING: PER VOICE playback: each column shows the pattern its own voice
    // is on, with that voice's own row lit (they no longer move together).
    var _voice_hl = [-1, -1, -1];
    var _voice_pos = undefined;
    if (_m.playing || _m.song_playing) _voice_pos = scr_sound_editor_voice_positions(_m);
    if (is_array(_voice_pos)) {
        _grid_len = 16;
        for (var _fv = 0; _fv < 3; _fv++) {
            var _f_ord = clamp(_voice_pos[_fv][0], 0, array_length(_cur_song.order) - 1);
            var _f_p = scr_music_sid_pattern(_cur_song.order[_f_ord], _voice_offset + _fv);
            _col_pat_idx[_fv] = _f_p;
            _col_pat[_fv] = noone;
            if (_f_p >= 0 && _f_p < array_length(_m.patterns)) {
                _col_pat[_fv] = _m.patterns[_f_p];
                _se_ensure_steps(_col_pat[_fv]);
                _grid_len = max(_grid_len, _col_pat[_fv].pattern_len);
                _voice_hl[_fv] = _voice_pos[_fv][1];
            }
        }
    }
    // Digi track preview follows whichever position playback settled on.
    scr_digi_preview_tick(_m, _cur_song, _voice_pos);

    // ═════════════════════════════════════════════════════════════════════
    // HEADER ROWS
    // ═════════════════════════════════════════════════════════════════════
    var _rowy = _cy + 76;
    draw_set_font_l(fnt_c64_tiny);

    // ── STATUS LINE — pushed above everything else, bigger font so it isn't
    // lost among the header controls. ──
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(make_color_rgb(120, 140, 190));
    draw_text_l(_vx1 + 20, _cy,
        "CLICK A CELL, TYPE A NOTE (C-4, C#3, ---)   |   ENTER COMMITS + DROPS A ROW   |   BKSP CLEARS   |   DEL PULLS UP   |   INS PUSHES DOWN   |   UP/DOWN MOVES   |   TAB NOTE/CMD   |   - STOP  + KEY ON   |   F1 SONG   F2 SONG FROM HERE   F3 PAT   F4 STOP   |   SPACE HEAR INSTRUMENT");
   
    draw_set_font_l(fnt_c64_tiny);
    var _status_y = _cy + 50;
    if (!_preview_ready) {
        var _prep_total = array_length(_m.preview_jobs);
        var _prep_fraction = clamp(_m.preview_job_index / max(1, _prep_total), 0, 1);
        var _prep_text = "PREPARING AUDIO " + string(_m.preview_job_index) + "/" + string(_prep_total);
        draw_set_color(c_yellow);
        draw_text_l(_vx1 + 20, _status_y, _prep_text);
        var _bar_x = _vx1 + 20 + string_width_l(_prep_text) + 12;
        var _bar_w = max(40, min(220, _vx2 - _bar_x - 70));
        draw_set_color(make_color_rgb(20, 28, 40));
        draw_rectangle(_bar_x, _status_y - 1, _bar_x + _bar_w, _status_y + 14, false);
        draw_set_color(make_color_rgb(90, 195, 110));
        if (_prep_fraction > 0) draw_rectangle(_bar_x + 1, _status_y, _bar_x + 1 + (_bar_w - 2) * _prep_fraction, _status_y + 13, false);
        draw_set_color(make_color_rgb(130, 155, 180));
        draw_rectangle(_bar_x, _status_y - 1, _bar_x + _bar_w, _status_y + 14, true);
        draw_set_color(c_white);
        draw_text_l(_bar_x + _bar_w + 8, _status_y, string(floor(_prep_fraction * 100)) + "%");
    } else if (_m.playing || _m.song_playing) {
        draw_set_color(_m.playing ? c_lime : c_aqua);
        var _shown_order = variable_struct_exists(_m, "preview_display_order") ? _m.preview_display_order : _m.sel_order_row;
        var _shown_step = variable_struct_exists(_m, "preview_display_step") ? _m.preview_display_step : 0;
        draw_text_l(_vx1 + 20, _status_y, (_m.playing ? L("> LOOPING PAT") : L("> PLAYING SONG")) + " - ORDER " + string(_shown_order) + L("   STEP ") + string(_shown_step));
    } else {
        draw_set_color(make_color_rgb(130, 155, 180));
        draw_text_l(_vx1 + 20, _status_y, "HERE: ORDER " + string(_m.sel_order_row) + L("   STEP ") + string(_m.sel_step));
    }
    // ── Compiled size by section (all SID chips), refreshed after edits settle ──
    var _size = scr_music_size_cached(_asset);
    if (is_struct(_size) && _size.ok) {
        var _sz_parts = [["INSTR", _size.instr], ["TABLES", _size.tables], ["SHARED", _size.shared],
            ["PATTERNS", _size.patterns], ["ORDER", _size.order], ["NOTES", _size.notes],
            ["PLAYER", _size.player], ["VARS", _size.vars], ["DIGI", _size.digi]];
        var _sz_x = _vx1 + 460;
        draw_set_color(make_color_rgb(150, 170, 200));
        draw_text_l(_sz_x, _status_y, "BYTES:");
        _sz_x += string_width_l("BYTES: ") + 6;
        for (var _szi = 0; _szi < array_length(_sz_parts); _szi++) {
            var _sz_txt = _sz_parts[_szi][0] + " " + string(_sz_parts[_szi][1]);
            draw_set_color(make_color_rgb(120, 140, 170));
            draw_text_l(_sz_x, _status_y, _sz_txt);
            _sz_x += string_width_l(_sz_txt) + 14;
        }
        draw_set_color(c_yellow);
        draw_text_l(_sz_x, _status_y, "TOTAL " + string(_size.total));
    }
    draw_set_font_l(fnt_c64_tiny);

    // ── PATTERN BANK — create/delete patterns, independent of any voice ──
    draw_set_color(c_ltgray);
    draw_text_l(_vx1 + 20, _rowy + 4, "BANK:");

    var _bpx1 = _vx1 + 64;
    var _bpx2 = _bpx1 + 18;
    var _bp_hov = point_in_rectangle(_mx, _my, _bpx1, _rowy, _bpx2, _rowy + 18);
    draw_set_color(_bp_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_bpx1, _rowy, _bpx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_bpx1 + 9, _rowy + 4, "<");
    draw_set_halign(fa_left);
    if (_bp_hov && mouse_check_button_pressed(mb_left)) {
        _m.bank_sel_pattern = max(0, _m.bank_sel_pattern - 1);
    }

    draw_set_color(make_color_rgb(255, 200, 100));
    draw_set_halign(fa_center);
    var _bank_pat = _m.patterns[_m.bank_sel_pattern];
    draw_text_l(_bpx2 + 90, _rowy + 4, _bank_pat.name + "  (" + string(_m.bank_sel_pattern + 1) + "/" + string(array_length(_m.patterns)) + ")");
    draw_set_halign(fa_left);

    var _bnx1 = _bpx2 + 172;
    var _bnx2 = _bnx1 + 18;
    var _bn_hov = point_in_rectangle(_mx, _my, _bnx1, _rowy, _bnx2, _rowy + 18);
    draw_set_color(_bn_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_bnx1, _rowy, _bnx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_bnx1 + 9, _rowy + 4, ">");
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
    draw_text_l((_bax1 + _bax2) * 0.5, _rowy + 4, "+ NEW");
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
    for (var _song_i = 0; _song_i < array_length(_m.songs); _song_i++) {
        for (var _bri = 0; _bri < array_length(_m.songs[_song_i].order); _bri++) {
            var _br = _m.songs[_song_i].order[_bri];
            for (var _vref = 0; _vref < 24; _vref++) {
                if (scr_music_sid_pattern(_br, _vref) == _m.bank_sel_pattern) _bd_referenced = true;
            }
        }
    }
    var _bd_lock = (array_length(_m.patterns) <= 1) || _bd_referenced;
    var _bd_hov  = !_bd_lock && point_in_rectangle(_mx, _my, _bdx1, _rowy, _bdx2, _rowy + 18);
    draw_set_color(_bd_lock ? make_color_rgb(55, 40, 40) : (_bd_hov ? make_color_rgb(200, 60, 60) : make_color_rgb(100, 30, 30)));
    draw_rectangle(_bdx1, _rowy, _bdx2, _rowy + 18, false);
    draw_set_color(_bd_lock ? make_color_rgb(100, 80, 80) : c_white);
    draw_set_halign(fa_center);
    draw_text_l((_bdx1 + _bdx2) * 0.5, _rowy + 4, "DEL");
    draw_set_halign(fa_left);
    if (_bd_hov && mouse_check_button_pressed(mb_left)) {
        for (var _ds = 0; _ds < array_length(_m.songs); _ds++) {
            for (var _dr = 0; _dr < array_length(_m.songs[_ds].order); _dr++) {
                var _drow = _m.songs[_ds].order[_dr];
                for (var _dv = 0; _dv < 24; _dv++) {
                    var _dpi = scr_music_sid_pattern(_drow, _dv);
                    if (_dpi > _m.bank_sel_pattern) _drow[$ "v" + string(_dv + 1)] = _dpi - 1;
                }
            }
        }
        array_delete(_m.patterns, _m.bank_sel_pattern, 1);
        _m.bank_sel_pattern = clamp(_m.bank_sel_pattern, 0, array_length(_m.patterns) - 1);
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }
    if (_bd_referenced) {
        draw_set_font_l(fnt_c64_pico);
        draw_set_color(make_color_rgb(200, 140, 60));
        draw_text_l(_bdx2 + 12, _rowy + 6, "! IN USE - CAN'T DELETE");
        draw_set_font_l(fnt_c64_tiny);
    }

    // ── OCTAVE STEPPER ──
    var _ocx0 = _bdx2 + 200;
    draw_set_color(c_ltgray);
    draw_text_l(_ocx0, _rowy + 4, "OCTAVE:");

    var _opx1 = _ocx0 + 60;
    var _opx2 = _opx1 + 18;
    var _op_hov = point_in_rectangle(_mx, _my, _opx1, _rowy, _opx2, _rowy + 18);
    draw_set_color(_op_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_opx1, _rowy, _opx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_opx1 + 9, _rowy + 4, "<");
    draw_set_halign(fa_left);
    if (_op_hov && mouse_check_button_pressed(mb_left)) {
        _m.cur_octave = clamp(_m.cur_octave - 1, 1, 6);
    }

    draw_set_color(make_color_rgb(140, 220, 255));
    draw_set_halign(fa_center);
    draw_text_l(_opx2 + 16, _rowy + 4, string(_m.cur_octave));
    draw_set_halign(fa_left);

    var _onx1 = _opx2 + 32;
    var _onx2 = _onx1 + 18;
    var _on_hov = point_in_rectangle(_mx, _my, _onx1, _rowy, _onx2, _rowy + 18);
    draw_set_color(_on_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_onx1, _rowy, _onx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_onx1 + 9, _rowy + 4, ">");
    draw_set_halign(fa_left);
    if (_on_hov && mouse_check_button_pressed(mb_left)) {
        _m.cur_octave = clamp(_m.cur_octave + 1, 1, 6);
    }

    draw_set_font_l(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 90, 120));
    draw_text_l(_onx2 + 16, _rowy + 6, "Z-ROW=OCT-1  Q-ROW=OCT  I/O/P=OCT+1");
    draw_set_font_l(fnt_c64_tiny);

    // ── TEMPO ── frames per row, shared by every song in this asset. The
    // emitter bakes it in as the _S_TICK reload value, so changing it resizes
    // nothing but does change what the node emits.
    var _tpx0 = _onx2 + 320;
    draw_set_color(c_ltgray);
    draw_text_l(_tpx0, _rowy + 4, "TEMPO:");

    var _tp_dx1 = _tpx0 + 58;
    var _tp_dx2 = _tp_dx1 + 18;
    var _tp_d_hov = point_in_rectangle(_mx, _my, _tp_dx1, _rowy, _tp_dx2, _rowy + 18);
    draw_set_color(_tp_d_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_tp_dx1, _rowy, _tp_dx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_tp_dx1 + 9, _rowy + 4, "<");
    draw_set_halign(fa_left);
    if (_tp_d_hov && mouse_check_button_pressed(mb_left)) {
        _m.play_speed          = clamp(real(_m.play_speed) - 1, 1, 24);
        global.addresses_dirty = true;
        global.undo_dirty      = true;
    }

    draw_set_color(make_color_rgb(140, 220, 255));
    draw_set_halign(fa_center);
    draw_text_l(_tp_dx2 + 20, _rowy + 4, string(_m.play_speed));
    draw_set_halign(fa_left);

    var _tp_ux1 = _tp_dx2 + 40;
    var _tp_ux2 = _tp_ux1 + 18;
    var _tp_u_hov = point_in_rectangle(_mx, _my, _tp_ux1, _rowy, _tp_ux2, _rowy + 18);
    draw_set_color(_tp_u_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_tp_ux1, _rowy, _tp_ux2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_tp_ux1 + 9, _rowy + 4, ">");
    draw_set_halign(fa_left);
    if (_tp_u_hov && mouse_check_button_pressed(mb_left)) {
        _m.play_speed          = clamp(real(_m.play_speed) + 1, 1, 24);
        global.addresses_dirty = true;
        global.undo_dirty      = true;
    }

    // Rough BPM readout, assuming 4 rows to the beat on a 50Hz PAL raster.
    // Informational only — nothing downstream reads it.
    draw_set_font_l(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 90, 120));
    var _tp_bpm = round((50 * 60) / (real(_m.play_speed) * 4));
    var _tp_txt = L("FRAMES/ROW  (~") + string(_tp_bpm) + " BPM @ 4 ROWS/BEAT)";
    draw_text_l(_tp_ux2 + 12, _rowy + 6, _tp_txt);
    var _tm_x = _tp_ux2 + 12 + string_width_l(_tp_txt) + 18;
    draw_set_font_l(fnt_c64_tiny);

    // ── TIMING ── SHARED: one row clock for all voices (FXX sets it). PER
    // VOICE: each voice walks its own column of the order list at its own
    // speed (FXX sets that voice's speed from its row on), so voices can
    // change notes at different times — the GoatTracker / sequence model.
    var _tm_label = "TIMING: SHARED";
    if (_m.free_voices) _tm_label = "TIMING: PER VOICE";
    if (scr_sfx_maker_button(_tm_x, _rowy, 170, _tm_label, _mx, _my)) {
        scr_sound_editor_transport(_m, _cur_song, "STOP");
        _m.free_voices = !_m.free_voices;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
    }
    if (_m.free_voices) {
        draw_set_font_l(fnt_c64_pico);
        draw_set_color(make_color_rgb(90, 90, 120));
        draw_text_l(_tm_x + 180, _rowy + 6, "EACH VOICE: OWN ORDER COLUMN, OWN FXX SPEED, OWN PATTERN LENGTH");
        draw_set_font_l(fnt_c64_tiny);
    }

    _rowy += 26;
    var _sid_count = scr_music_sid_count(_m);
    if (scr_sfx_maker_button(_vx1 + 20, _rowy, 32, "-", _mx, _my) && _sid_count > 1) {
        scr_sound_editor_transport(_m, _cur_song, "STOP");
        scr_music_sid_page(_m, min(_m.sid_page, _sid_count - 2), _col_pat, _se_push_undo, _se_snap);
        _m.sid_count = _sid_count - 1;
        global.undo_dirty = true; global.addresses_dirty = true;
    }
    draw_text_l(_vx1 + 62, _rowy + 6, string(_sid_count) + " SIDS / " + string(_sid_count * 3) + " VOICES");
    if (scr_sfx_maker_button(_vx1 + 260, _rowy, 32, "+", _mx, _my) && _sid_count < 8) {
        scr_sound_editor_transport(_m, _cur_song, "STOP");
        _m.sid_count = _sid_count + 1;
        global.undo_dirty = true; global.addresses_dirty = true;
    }
    if (scr_sfx_maker_button(_vx1 + 310, _rowy, 38, "<<", _mx, _my))
        scr_music_sid_page(_m, _m.sid_page - 1, _col_pat, _se_push_undo, _se_snap);
    draw_text_l(_vx1 + 360, _rowy + 6, "SID " + string(_voice_offset div 3 + 1) + "  $" + string_upper(decimal_to_hex(0xD400 + (_voice_offset div 3) * 0x20)));
    if (scr_sfx_maker_button(_vx1 + 525, _rowy, 38, ">>", _mx, _my))
        scr_music_sid_page(_m, _m.sid_page + 1, _col_pat, _se_push_undo, _se_snap);
    if (scr_sfx_maker_button(_vx1 + 590, _rowy, 150, "GENERATE NODES", _mx, _my)) {
        scr_sound_editor_commit_cell(_m, _se_push_undo, _se_snap, _col_pat);
        if (_m.instr_edit_active && _m.sel_instr >= 0) scr_sound_editor_commit_instrument(_m, _m.instruments[_m.sel_instr]);
        scr_music_sid_generate(_asset);
    }
    draw_set_font_l(fnt_c64_pico);
    draw_text_l(_vx1 + 755, _rowy + 7, "ULTIMATE: MAP SIDS AT $D400 + $20 EACH. REDUCING COUNT KEEPS HIDDEN LANES.");
    draw_set_font_l(fnt_c64_tiny);
    _rowy += 28;

    // ═════════════════════════════════════════════════════════════════════
    // LEFT PANEL — PATTERN GRID (3 columns = whatever the selected order
    // row's v1/v2/v3 currently point at)
    // ═════════════════════════════════════════════════════════════════════
    var _gy0 = _rowy + 44;
    // Always 16 rows: the row height gives way (down to 22px) instead.
    _vis = 16;
    _row_h = clamp(floor((_vy2 - _gy0 - 80) / _vis), 22, 36);
    var _ty = max(2, floor((_row_h - 10 * _txt_scale) / 2));   // text y inside a row
    var _gx0 = _vx1 + 20;

    var _col_gutter_x = _gx0;
    var _col_x = [
        _gx0 + _gutter_w,
        _gx0 + _gutter_w + _lane_w + _lane_gap,
        _gx0 + _gutter_w + (_lane_w + _lane_gap) * 2
    ];
    var _grid_full_w = _gutter_w + (_lane_w * 3) + (_lane_gap * 2);
    // DIGI lane: a narrow 4th column right of voice 3.
    var _dg_w = _lane_w;   // note, slot, volume — same width as a voice lane
    var _dg_x = _gx0 + _gutter_w + (_lane_w + _lane_gap) * 3;
    _grid_full_w += _lane_gap + _dg_w;

    var _lane_colours = [make_color_rgb(120, 220, 255), make_color_rgb(255, 200, 120), make_color_rgb(180, 255, 150)];
		_txt_scale =1;
    for (var _lh = 0; _lh < 3; _lh++) {
        draw_set_color(_lane_colours[_lh]);
        draw_set_halign(fa_center);
		        var _lh_label = "V O I C E  " + string(_voice_offset + _lh + 1);
				
        draw_text_transformed_l(_col_x[_lh] + (_lane_w * 0.5), _gy0 - 20, _lh_label, _txt_scale, _txt_scale, 0);
        draw_set_halign(fa_left);
		
        // Which pattern + its own length, with a length stepper. Readout
        // only — WHICH pattern plays here is set via the order table, not here.
        draw_set_font_l(fnt_c64_pico);
        if (_col_pat[_lh] == noone) {
            draw_set_color(make_color_rgb(220, 120, 90));
            draw_text_l(_col_x[_lh], _gy0 - 34, "[ NO PATTERN ]");
        } else {
            draw_set_color(make_color_rgb(90, 90, 120));
            var _ph_idx = string(_col_pat_idx[_lh]);
            if (_col_pat_idx[_lh] < 10) {
                _ph_idx = "0" + _ph_idx;
            }
            draw_text_l(_col_x[_lh], _gy0 - 34, "PAT " + _ph_idx + L(" LEN:"));

            var _clx1 = _col_x[_lh] + 74;
            var _clx2 = _clx1 + 14;
            var _cl_hov = point_in_rectangle(_mx, _my, _clx1, _gy0 - 38, _clx2, _gy0 - 24);
            draw_set_color(_cl_hov ? c_aqua : make_color_rgb(60, 130, 150));
            draw_text_l(_clx1, _gy0 - 34, "<");
            if (_cl_hov && mouse_check_button_pressed(mb_left)) {
                _col_pat[_lh].pattern_len = clamp(_col_pat[_lh].pattern_len - 4, 4, 128);
                _se_ensure_steps(_col_pat[_lh]);
                global.addresses_dirty = true;
            }

            draw_set_color(c_white);
            draw_text_l(_clx2 + 4, _gy0 - 34, string(_col_pat[_lh].pattern_len));

            var _cnx1 = _clx2 + 26;
            var _cnx2 = _cnx1 + 14;
            var _cn_hov = point_in_rectangle(_mx, _my, _cnx1, _gy0 - 38, _cnx2, _gy0 - 24);
            draw_set_color(_cn_hov ? c_aqua : make_color_rgb(60, 130, 150));
            draw_text_l(_cnx1, _gy0 - 34, ">");
            if (_cn_hov && mouse_check_button_pressed(mb_left)) {
                _col_pat[_lh].pattern_len = clamp(_col_pat[_lh].pattern_len + 4, 4, 128);
                _se_ensure_steps(_col_pat[_lh]);
                global.addresses_dirty = true;
            }
        }
        draw_set_font_l(fnt_c64_tiny);
    }
	_txt_scale = 1.5;
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

    // ── 9XX RANGE CHECK ── walks the three patterns the way the player does
    // (instrument PW on a note, 8XX sets, 9XX adds XX per frame for one row's
    // worth of frames at the current tempo, FXX changes the tempo) and marks
    // any 9XX that drives the pulse width into $000 / $FFF, where the pulse
    // wave is silent. -1 = fine; otherwise the width it hit. Rows before the
    // first note in a pattern have an unknown width and aren't judged.
    var _pw_warn = [array_create(_grid_len, -1), array_create(_grid_len, -1), array_create(_grid_len, -1)];
    var _pw_now  = [-1, -1, -1];
    var _pw_spd  = clamp(real(_m.play_speed), 1, 255);
    // CXX: the one shared cutoff, from the song's FILTER setting.
    var _ct_warn = [array_create(_grid_len, -1), array_create(_grid_len, -1), array_create(_grid_len, -1)];
    var _ct_now  = clamp(real(_m.filt_cut), 0, 2047);
    for (var _pwr = 0; _pwr < _grid_len; _pwr++) {
        var _pw_next_spd = _pw_spd;
        for (var _pwv = 0; _pwv < 3; _pwv++) {
            var _pw_pat = _col_pat[_pwv];
            if (_pw_pat == noone || _pwr >= _pw_pat.pattern_len || _pwr >= array_length(_pw_pat.steps)) {
                continue;
            }
            var _pw_st = _pw_pat.steps[_pwr];
            var _pw_is_note = (!_pw_st.empty && _pw_st.note != "" && _pw_st.note != "---" && _pw_st.note != "+++");
            if (_pw_is_note && _pw_st.cmd != 3
            && _pw_st.instr_idx >= 0 && _pw_st.instr_idx < array_length(_m.instruments)) {
                _pw_now[_pwv] = floor(scr_sid64_instr_field(_m.instruments[_pw_st.instr_idx], "pulse_width", 0x800)) & 0xFFF;
            }
            if (_pw_st.cmd == 8) {
                _pw_now[_pwv] = (_pw_st.cmd_val << 4) & 0xFFF;
            }
            if (_pw_st.cmd == 0x0A) {
                _ct_now = (_pw_st.cmd_val << 3) & 0x7FF;
            }
            if (_pw_st.cmd == 0x0C) {
                var _ct_d = _pw_st.cmd_val;
                if (_ct_d >= 0x80) {
                    _ct_d -= 256;
                }
                var _ct_new = _ct_now + _ct_d * _pw_spd;
                if (_ct_new <= 0) {
                    _ct_warn[_pwv][_pwr] = 0;
                    _ct_new = 0;
                } else if (_ct_new >= 2047) {
                    _ct_warn[_pwv][_pwr] = 2047;
                    _ct_new = 2047;
                }
                _ct_now = _ct_new;
            }
            if (_pw_st.cmd == 0x0F && _pw_st.cmd_val > 0) {
                _pw_next_spd = _pw_st.cmd_val;   // takes effect from the next row
            }
            if (_pw_st.cmd == 9 && _pw_now[_pwv] >= 0) {
                var _pw_d = _pw_st.cmd_val;
                if (_pw_d >= 0x80) {
                    _pw_d -= 256;
                }
                var _pw_new = _pw_now[_pwv] + _pw_d * _pw_spd;
                if (_pw_new <= 0) {
                    _pw_warn[_pwv][_pwr] = 0x000;
                    _pw_new = 0;
                } else if (_pw_new >= 0xFFF) {
                    _pw_warn[_pwv][_pwr] = 0xFFF;
                    _pw_new = 0xFFF;
                }
                _pw_now[_pwv] = _pw_new;
            }
        }
        _pw_spd = _pw_next_spd;
    }
    var _pw_tip = "";   // sweep warning takes priority over command help

    // TIMING: PER VOICE playback: rows stay lined up with the row numbers,
    // but a column whose playing row would leave the view (a longer pattern,
    // or a voice ahead of the one being followed) scrolls just enough to keep
    // it in sight, like the grid itself does. Back to 0 when playback stops.
    var _col_off = global.music_col_scroll;
    for (var _cov = 0; _cov < 3; _cov++) {
        if (!is_array(_voice_pos) || _voice_hl[_cov] < 0) {
            _col_off[_cov] = 0;
            continue;
        }
        var _cfirst = _m.list_scroll + _col_off[_cov];
        if (_voice_hl[_cov] < _cfirst) {
            _col_off[_cov] = _voice_hl[_cov] - _m.list_scroll;
        } else if (_voice_hl[_cov] >= _cfirst + _vis) {
            _col_off[_cov] = _voice_hl[_cov] - _vis + 1 - _m.list_scroll;
        }
    }

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
        if (is_array(_voice_pos)) {
            // per-voice highlight is drawn in each cell below
        } else if (_m.playing) {
            _highlight_row = _m.preview_display_step;
        } else if (_m.song_playing && _m.preview_display_order == _m.sel_order_row) {
            _highlight_row = _order_row.repeat_short ? (_m.preview_display_step mod max(1, _grid_len)) : _m.preview_display_step;
        }
        if (_highlight_row == _row) {
            draw_set_color(make_color_rgb(40, 100, 60));
            draw_set_alpha(0.5);
            draw_rectangle(_col_gutter_x, _ry, _col_gutter_x + _grid_full_w, _ry + _row_h, false);
            draw_set_alpha(1.0);
        }

        draw_set_color((_row mod 16 == 0) ? make_color_rgb(220, 200, 120) : make_color_rgb(90, 90, 120));
        draw_text_transformed_l(_col_gutter_x + 8, _ry + _ty, string(_row), _txt_scale, _txt_scale, 0);

        var _row_base = _row;
        for (var _cv = 0; _cv < 3; _cv++) {
            _row = _row_base + _col_off[_cv];
            var _cx1 = _col_x[_cv];
            var _cx2 = _cx1 + _lane_w;
            var _has_pat = (_col_pat[_cv] != noone);
            var _in_range = _has_pat && (_row >= 0) && (_row < _col_pat[_cv].pattern_len);

            var _is_editing = (_m.edit_active && _m.edit_voice == _cv && _m.edit_step == _row);
            var _hov = _in_range && point_in_rectangle(_mx, _my, _cx1, _ry, _cx2, _ry + _row_h);
            var _is_cursor = (_in_range && !_m.edit_active && _m.sel_voice == _cv && _m.sel_step == _row);
            var _is_selected = (_in_range && _cv >= _sel_v_lo && _cv <= _sel_v_hi && _row >= _sel_s_lo && _row <= _sel_s_hi);

            if (!_has_pat) {
                draw_set_color(make_color_rgb(26, 22, 22));
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, false);
                draw_set_color(make_color_rgb(130, 100, 100));
                draw_text_transformed_l(_cx1 + 8, _ry + _ty, "----", _txt_scale, _txt_scale, 0);
                continue;
            }
            if (!_in_range) {
                draw_set_color(make_color_rgb(26, 26, 38));
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, false);
                draw_set_color(make_color_rgb(110, 110, 130));
                if (_row >= 0) draw_text_transformed_l(_cx1 + 8, _ry + _ty, "END", _txt_scale, _txt_scale, 0);
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

            if (_voice_hl[_cv] == _row) {
                draw_set_color(make_color_rgb(40, 100, 60));
                draw_set_alpha(0.5);
                draw_rectangle(_cx1, _ry, _cx2, _ry + _row_h, false);
                draw_set_alpha(1.0);
            }
            if (_col_off[_cv] != 0) {
                // this column has scrolled on its own: show its own row number
                draw_set_font_l(fnt_c64_pico);
                draw_set_color(make_color_rgb(110, 110, 140));
                draw_set_halign(fa_right);
                draw_text_l(_cx2 - 4, _ry + 2, string(_row));
                draw_set_halign(fa_left);
                draw_set_font_l(fnt_c64_tiny);
            }

            var _step = _col_pat[_cv].steps[_row];

            if (_is_editing) {
                var _blink = (current_time mod 600) < 300;
                var _disp  = _blink ? string_insert("|", _m.edit_buf, _m.edit_cursor + 1) : _m.edit_buf;
                draw_set_color(c_lime);
                draw_text_transformed_l(_cx1 + 8, _ry + _ty, _disp, _txt_scale, _txt_scale, 0);
            } else if (_step.empty) {
                draw_set_color(make_color_rgb(60, 60, 70));
                draw_text_transformed_l(_cx1 + 8, _ry + _ty, "...", _txt_scale, _txt_scale, 0);
            } else if (_step.note == "---" || _step.note == "") {
                draw_set_color(make_color_rgb(140, 90, 90));
                draw_text_transformed_l(_cx1 + 8, _ry + _ty, "---", _txt_scale, _txt_scale, 0);
            } else if (_step.note == "+++") {
                draw_set_color(make_color_rgb(90, 150, 90));
                draw_text_transformed_l(_cx1 + 8, _ry + _ty, "+++", _txt_scale, _txt_scale, 0);
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
                draw_text_transformed_l(_cx1 + 8, _ry + _ty, _cell_txt, _txt_scale, _txt_scale, 0);
                if (!_has_instr && !_missing && _row < array_length(_carry_ins[_cv])) {
                    // No instrument on this row: show the one still playing, dimmed
                    var _carried = _carry_ins[_cv][_row];
                    if (_carried >= 0) {
                        var _carry_str = string(_carried);
                        while (string_length(_carry_str) < 2) { _carry_str = "0" + _carry_str; }
                        draw_set_color(make_color_rgb(100, 100, 125));
                        draw_text_transformed_l(_cx1 + 8 + string_width_l(_cell_txt + " ") * _txt_scale, _ry + _ty, _carry_str, _txt_scale, _txt_scale, 0);
                    }
                }
                if (_missing) {
                    draw_set_font_l(fnt_c64_pico);
                    draw_set_color(c_red);
                    draw_text_l(_cx1 + 8, _ry + _row_h - 9, "INSTRUMENT MISSING");
                    draw_set_font_l(fnt_c64_tiny);
                }
            }

            // ── Command column (right of the note): "4 38", dim "..." when empty ──
            var _cmd_x = _cx1 + _cmd_off;
            var _st_cmd = _step.cmd;
            var _typing_here = (_m.cmd_entry_str != "" && _m.cmd_entry_voice == _cv && _m.cmd_entry_step == _row);
            // (No hover help on command cells: the GUIDE button lists them all.)
            if (_typing_here) {
                // Being typed: only the new digits, the rest blank.
                var _ty_str = _m.cmd_entry_str;
                while (string_length(_ty_str) < 3) {
                    _ty_str += "_";
                }
                draw_set_color(c_yellow);
                draw_text_transformed_l(_cmd_x, _ry + _ty, _ty_str, _txt_scale, _txt_scale, 0);
            } else if (_st_cmd >= 0) {
                var _cv_hex = string_upper(decimal_to_hex(_step.cmd_val));
                while (string_length(_cv_hex) < 2) { _cv_hex = "0" + _cv_hex; }
                draw_set_color(make_color_rgb(255, 170, 90));
                if (_row < _grid_len && _ct_warn[_cv][_row] >= 0) {
                    draw_set_color(c_red);
                    if (point_in_rectangle(_mx, _my, _cmd_x - 6, _ry, _cx2, _ry + _row_h)) {
                        if (_ct_warn[_cv][_row] > 0) {
                            _pw_tip = "THIS SWEEP RUNS THE FILTER CUTOFF TO ITS TOP (2047) AND STOPS THERE."
                                    + "\nUSE A SMALLER VALUE OR FEWER ROWS, SET IT WITH AXX,"
                                    + "\nOR SWEEP BACK DOWN WITH C80-CFF (CFF = -1, CF0 = -16 PER FRAME).";
                        } else {
                            _pw_tip = "THIS SWEEP RUNS THE FILTER CUTOFF TO ZERO AND STOPS THERE (LOW-PASS GOES QUIET)."
                                    + "\nUSE A SMALLER DROP OR FEWER ROWS, SET IT WITH AXX,"
                                    + "\nOR SWEEP BACK UP WITH C01-C7F (C01 = +1, C10 = +16 PER FRAME).";
                        }
                    }
                }
                if (_row < _grid_len && _pw_warn[_cv][_row] >= 0) {
                    draw_set_color(c_red);
                    if (point_in_rectangle(_mx, _my, _cmd_x - 6, _ry, _cx2, _ry + _row_h)) {
                        // 901-97F sweep up, 980-9FF sweep down (9FF = -1, 980 = -128 per frame).
                        if (_pw_warn[_cv][_row] > 0) {
                            _pw_tip = "SILENT: THIS SWEEP PUSHES THE PULSE WIDTH PAST ITS TOP ($FFF)."
                                    + "\nUSE A SMALLER VALUE OR FEWER ROWS, RESET IT WITH 8XX,"
                                    + "\nOR SWEEP BACK DOWN WITH 980-9FF (9FF = -1, 9F0 = -16 PER FRAME).";
                        } else {
                            _pw_tip = "SILENT: THIS SWEEP PUSHES THE PULSE WIDTH PAST ITS BOTTOM ($000)."
                                    + "\nUSE A SMALLER DROP OR FEWER ROWS, RESET IT WITH 8XX,"
                                    + "\nOR SWEEP BACK UP WITH 901-97F (901 = +1, 910 = +16 PER FRAME).";
                        }
                    }
                }
                draw_text_transformed_l(_cmd_x, _ry + _ty, string_char_at("0123456789ABCDEFGHIJ", _st_cmd + 1) + _cv_hex, _txt_scale, _txt_scale, 0);
            } else {
                draw_set_color(make_color_rgb(60, 60, 70));
                draw_text_transformed_l(_cmd_x, _ry + _ty, "...", _txt_scale, _txt_scale, 0);
            }

            if (_is_cursor) {
                draw_set_color(c_yellow);
                if (_m.sel_sub == 1) {
                    draw_rectangle(_cmd_x - 6, _ry, _cx2, _ry + _row_h, true);
                } else {
                    draw_rectangle(_cx1, _ry, _cmd_x - 8, _ry + _row_h, true);
                }
            }

            if (_hov && mouse_check_button_pressed(mb_left) && keyboard_check(vk_alt)) {
                // ALT+click: pick this note's instrument (or the one it carries)
                var _pick_ins = _step.instr_idx;
                if (_pick_ins < 0 && _row < array_length(_carry_ins[_cv])) {
                    _pick_ins = _carry_ins[_cv][_row];
                }
                if (_pick_ins >= 0 && _pick_ins < array_length(_m.instruments)) {
                    _m.sel_instr = _pick_ins;
                    global.mm_instr_center = _pick_ins;
                }
            } else if (_hov && mouse_check_button_pressed(mb_left)) {
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
                    _m.sel_sub          = 0;
                    if (_mx >= _cx1 + _cmd_off - 6) {
                        // Clicking the command also leaves a same-row note text edit.
                        if (_m.edit_active) {
                            scr_sound_editor_commit_cell(_m, _se_push_undo, _se_snap, _col_pat);
                        }
                        _m.sel_sub = 1;
                        _dbl = false;
                    }

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
                _step.cmd       = -1;
                _step.cmd_val   = 0;
                global.undo_dirty = true;
            }
        }
        _row = _row_base;   // per-voice column offsets (PER VOICE playback) end here
    }

    // ── DIGI LANE ──
    var _dg_hl = -1;
    if (is_array(_voice_pos)) {
        _dg_hl = _voice_hl[0];
    } else if (_m.playing) {
        _dg_hl = _m.preview_display_step;
    } else if (_m.song_playing && _m.preview_display_order == _m.sel_order_row) {
        _dg_hl = _m.preview_display_step;
    }
    if (scr_digi_lane(_m, _order_row, _dg_x, _gy0, _dg_w, _row_h, _vis, _grid_len, _txt_scale, _dg_hl, _mx, _my, _se_push_undo, _se_snap)) {
        if (_m.edit_active) {
            scr_sound_editor_commit_cell(_m, _se_push_undo, _se_snap, _col_pat);
        }
        _m.edit_active = false;
    }
    if (_m.dg_focus && !_m.edit_active && !_m.instr_edit_active && !_m.instr_name_edit_active
    && !_m.song_name_edit_active && !_order_typing && !_m.instr_note_edit_active) {
        scr_digi_keys(_m, _order_row, _grid_len, _vis, _se_push_undo, _se_snap, _se_undo_goto);
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
    } else if (!_m.instr_edit_active && !_m.instr_name_edit_active && !_m.song_name_edit_active && !_order_typing && !_m.dg_focus
            && !_m.instr_note_edit_active) {
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

        // GoatTracker transpose keys, scoped to selected notes (never text fields).
        if (_kb_ctrl && _m.sel_sub == 0) {
            var _transpose = 0;
            if (keyboard_check_pressed(ord("Q"))) _transpose = 1;
            else if (keyboard_check_pressed(ord("A"))) _transpose = -1;
            else if (keyboard_check_pressed(ord("W"))) _transpose = 12;
            else if (keyboard_check_pressed(ord("S"))) _transpose = -12;
            else if (keyboard_check_pressed(_vk_equals) || keyboard_check_pressed(vk_add)) {
                _transpose = keyboard_check(vk_shift) ? 12 : 1;
            } else if (keyboard_check_pressed(189) || keyboard_check_pressed(vk_subtract)) {
                _transpose = keyboard_check(vk_shift) ? -12 : -1;
            }
            if (_transpose != 0) {
                scr_sound_editor_transpose(_m, _col_pat, _col_pat_idx,
                    _sel_v_lo, _sel_v_hi, _sel_s_lo, _sel_s_hi,
                    _transpose, _se_push_undo, _se_snap);
            }
        }

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
                        array_push(_cp_cols, { note: _cp_src.note, instr_idx: _cp_src.instr_idx, empty: _cp_src.empty,
                                               cmd: _cp_src.cmd, cmd_val: _cp_src.cmd_val });
                    } else {
                        array_push(_cp_cols, { note: "", instr_idx: -1, empty: true, cmd: -1, cmd_val: 0 });
                    }
                }
                array_push(_cp_rows, _cp_cols);
            }
            global.se_clipboard = { w: _cp_w, h: _cp_h, rows: _cp_rows };
            _m.warn_msg   = "COPIED " + string(_cp_w) + "x" + string(_cp_h);
            _m.warn_timer = game_get_speed(gamespeed_fps) * 2;
        }

        // ── UNDO / REDO ── Ctrl+Z / Ctrl+Y (Ctrl+Shift+Z also redoes).
        // Every pattern edit already pushed a snapshot (notes, instruments per
        // cell, command column); this is the half that restores them.
        // The cursor jumps to where the undone / redone edit was made; the
        // opposite stack gets the same location so redo lands there too.
        if (_kb_ctrl && keyboard_check_pressed(ord("Z")) && !keyboard_check(vk_shift)) {
            if (array_length(_m.undo_stack) > 0) {
                var _un_top = array_length(_m.undo_stack) - 1;
                var _un = _m.undo_stack[_un_top];
                array_delete(_m.undo_stack, _un_top, 1);
                array_push(_m.redo_stack, { pats: _se_snap(_m), voice: _un.voice, step: _un.step, sub: _un.sub, ord: _un.ord, chip: variable_struct_exists(_un, "chip") ? _un.chip : 0,
                                            dgs: scr_digi_snapshot(_m), dgf: _un[$ "dgf"] == true, dgstep: _m.dg_sel_step });
                _m.patterns = _un.pats;
                _se_undo_goto(_m, _un, _vis);
                scr_digi_undo_apply(_m, _un);
                _m.bank_sel_pattern = clamp(_m.bank_sel_pattern, 0, array_length(_m.patterns) - 1);
                _m.warn_msg   = "UNDO";
                _m.warn_timer = game_get_speed(gamespeed_fps);
                global.undo_dirty      = true;
                global.addresses_dirty = true;
            }
        }
        var _redo_key = keyboard_check_pressed(ord("Y"));
        if (keyboard_check_pressed(ord("Z")) && keyboard_check(vk_shift)) {
            _redo_key = true;
        }
        if (_kb_ctrl && _redo_key) {
            if (array_length(_m.redo_stack) > 0) {
                var _re_top = array_length(_m.redo_stack) - 1;
                var _re = _m.redo_stack[_re_top];
                array_delete(_m.redo_stack, _re_top, 1);
                array_push(_m.undo_stack, { pats: _se_snap(_m), voice: _re.voice, step: _re.step, sub: _re.sub, ord: _re.ord, chip: variable_struct_exists(_re, "chip") ? _re.chip : 0,
                                            dgs: scr_digi_snapshot(_m), dgf: _re[$ "dgf"] == true, dgstep: _m.dg_sel_step });
                _m.patterns = _re.pats;
                _se_undo_goto(_m, _re, _vis);
                scr_digi_undo_apply(_m, _re);
                _m.bank_sel_pattern = clamp(_m.bank_sel_pattern, 0, array_length(_m.patterns) - 1);
                _m.warn_msg   = "REDO";
                _m.warn_timer = game_get_speed(gamespeed_fps);
                global.undo_dirty      = true;
                global.addresses_dirty = true;
            }
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
                    _dst_cell.cmd       = _src_cell.cmd;
                    _dst_cell.cmd_val   = _src_cell.cmd_val;
                    _pv_max = max(_pv_max, _pc);
                    _ps_max = max(_ps_max, _pr);
                }
            }
            // Cursor stays in its voice and drops to the row after the pasted
            // block (ready for the next paste), scrolling to keep it in view.
            _m.sel_step         = min(_grid_len - 1, _m.sel_step + _ps_max + 1);
            _m.sel_anchor_voice = _m.sel_voice;
            _m.sel_anchor_step  = _m.sel_step;
            if (_m.sel_step >= _m.list_scroll + _vis) {
                _m.list_scroll = _m.sel_step - _vis + 1;
            }
            global.undo_dirty      = true;
            global.addresses_dirty = true;
        }

        for (var _pki = 0; _pki < array_length(_pk_map) && !_kb_ctrl && (_cur_step != noone || global.music_jam) && _m.sel_sub == 0; _pki++) {
            var _pk = _pk_map[_pki];
            // Shift+'=' is '+' (key on), not the piano's F#.
            if (_pk[0] == _vk_equals && keyboard_check(vk_shift)) {
                continue;
            }
            if (keyboard_check_pressed(_pk[0])) {
                var _pk_oct  = clamp(_m.cur_octave + _pk[2], 0, 7);
                var _pk_name = _pk_names[_pk[1]];
                var _pk_note = (string_char_at(_pk_name, 2) == "#")
                             ? (_pk_name + string(_pk_oct))
                             : (string_char_at(_pk_name, 1) + "-" + string(_pk_oct));

                if (global.music_jam) {
                    // JAM: play the selected instrument, write nothing.
                    scr_sound_editor_jam_play(_m, _pk_note, _m.sel_voice, global.music_poly);
                    break;
                }

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

        // "-" (or "1") = --- note stop (gate off); "+" (Shift+= or keypad +) =
        // +++ key on (gate back on, same note). Plain "=" stays the piano's F#.
        // Both drop a row, like a typed note.
        var _key_rest = keyboard_check_pressed(ord("1")) || keyboard_check_pressed(189) || keyboard_check_pressed(vk_subtract);
        var _key_kon  = (keyboard_check_pressed(_vk_equals) && keyboard_check(vk_shift)) || keyboard_check_pressed(vk_add);
        if (_cur_step != noone && _m.sel_sub == 0 && !_kb_ctrl && _key_kon && !global.music_jam) {
            _se_push_undo(_m, _se_snap);
            _cur_step.note      = "+++";
            _cur_step.instr_idx = -1;
            _cur_step.empty     = false;
            global.undo_dirty      = true;
            global.addresses_dirty = true;
            if (_m.sel_step + 1 < _cur_pat.pattern_len) {
                _m.sel_step += 1;
            }
            if (_m.sel_step >= _m.list_scroll + _vis) {
                _m.list_scroll = _m.sel_step - _vis + 1;
            }
            _m.sel_anchor_voice = _m.sel_voice;
            _m.sel_anchor_step  = _m.sel_step;
        }
        if (_cur_step != noone && _m.sel_sub == 0 && !_kb_ctrl && _key_rest && !global.music_jam) {
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

        // BACKSPACE clears the note cell (GoatTracker layout). In the command
        // column Backspace is handled by the command entry below: it deletes a
        // typed digit, or clears the stored command.
        if (_cur_step != noone && _m.sel_sub == 0 && keyboard_check_pressed(vk_backspace)) {
            _se_push_undo(_m, _se_snap);
            _cur_step.note      = "";
            _cur_step.instr_idx = -1;
            _cur_step.empty     = true;
            global.undo_dirty   = true;
            global.addresses_dirty = true;
        }

        // ── COMMAND COLUMN ENTRY ── the first digit blanks the cell and the
        // command is typed fresh, left to right: 4, 3, 8 = 438. The third
        // digit stores it and drops a row; Enter stores what's typed so far
        // (missing digits are 0) and drops a row. Moving away discards it.
        if (_m.cmd_entry_str != "") {
            if (_m.sel_sub != 1 || _m.cmd_entry_voice != _m.sel_voice || _m.cmd_entry_step != _m.sel_step) {
                _m.cmd_entry_str = "";
            }
        }
        if (_cur_step != noone && _m.sel_sub == 1 && !_kb_ctrl) {
            // Command editing owns Backspace, even when the buffer is empty.
            // Never let a held key fall through to pattern-row deletion.
            if (keyboard_check_pressed(vk_backspace)) {
                if (_m.cmd_entry_str != "") {
                    _m.cmd_entry_str = string_delete(_m.cmd_entry_str, string_length(_m.cmd_entry_str), 1);
                } else if (_cur_step.cmd >= 0) {
                    _se_push_undo(_m, _se_snap);
                    _cur_step.cmd = -1;
                    _cur_step.cmd_val = 0;
                    global.undo_dirty = true;
                    global.addresses_dirty = true;
                }
            }
            if (keyboard_check_pressed(vk_escape)) _m.cmd_entry_str = "";
            var _cmd_commit = false;
            var _hex_keys = "0123456789ABCDEFGHIJ";
            for (var _hk = 1; _hk <= ((_m.cmd_entry_str == "") ? 20 : 16); _hk++) {
                if (keyboard_check_pressed(ord(string_char_at(_hex_keys, _hk)))) {
                    if (_m.cmd_entry_str == "") {
                        _m.cmd_entry_voice = _m.sel_voice;
                        _m.cmd_entry_step  = _m.sel_step;
                    }
                    _m.cmd_entry_str += string_char_at(_hex_keys, _hk);
                    if (string_length(_m.cmd_entry_str) >= 3) {
                        _cmd_commit = true;
                    }
                    break;
                }
            }
            var _cmd_down = false;
            if (keyboard_check_pressed(vk_enter)) {
                _cmd_down = true;
                if (_m.cmd_entry_str != "") {
                    _cmd_commit = true;
                }
            }
            if (_cmd_commit) {
                while (string_length(_m.cmd_entry_str) < 3) {
                    _m.cmd_entry_str += "0";
                }
                var _hv = 0;
                for (var _hci = 1; _hci <= 3; _hci++) {
                    _hv = (_hv << 4) | (string_pos(string_char_at(_m.cmd_entry_str, _hci), _hex_keys) - 1);
                }
                _se_push_undo(_m, _se_snap);
                _cur_step.cmd     = (_hv >> 8) & 0xFF;
                _cur_step.cmd_val = _hv & 0xFF;
                _m.cmd_entry_str  = "";
                global.undo_dirty      = true;
                global.addresses_dirty = true;
                _cmd_down = true;
            }
            if (_cmd_down) {
                if (_m.sel_step + 1 < _cur_pat.pattern_len) {
                    _m.sel_step += 1;
                }
                if (_m.sel_step >= _m.list_scroll + _vis) {
                    _m.list_scroll = _m.sel_step - _vis + 1;
                }
                _m.sel_anchor_voice = _m.sel_voice;
                _m.sel_anchor_step  = _m.sel_step;
            }
        }

        // DELETE pulls every row below the cursor up one (GoatTracker layout),
        // from either column; held, it repeats.
        if (_cur_step != noone && keyboard_check(vk_delete)) {
            var _do_bksp = false;
            if (keyboard_check_pressed(vk_delete)) {
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
                _m.cmd_entry_str = "";
                for (var _bsi = _m.sel_step; _bsi < _cur_pat.pattern_len - 1; _bsi++) {
                    var _bs_src = _cur_pat.steps[_bsi + 1];
                    var _bs_dst = _cur_pat.steps[_bsi];
                    _bs_dst.note      = _bs_src.note;
                    _bs_dst.instr_idx = _bs_src.instr_idx;
                    _bs_dst.empty     = _bs_src.empty;
                    _bs_dst.cmd       = _bs_src.cmd;
                    _bs_dst.cmd_val   = _bs_src.cmd_val;
                }
                var _bs_last = _cur_pat.steps[_cur_pat.pattern_len - 1];
                _bs_last.note      = "";
                _bs_last.instr_idx = -1;
                _bs_last.empty     = true;
                _bs_last.cmd       = -1;
                _bs_last.cmd_val   = 0;
                global.undo_dirty  = true;
                global.addresses_dirty = true;
            }
        } else {
            _m.bksp_timer = 0;
        }

        // ── INSERT ── mirror of delete: push every step from the cursor
        // DOWN one row, leaving the cursor row blank. The pattern's own length
        // is fixed, so the last step falls off the end and is discarded —
        // same trade-off delete makes at the top.
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
                    _is_dst.cmd       = _is_src.cmd;
                    _is_dst.cmd_val   = _is_src.cmd_val;
                }
                var _is_cur = _cur_pat.steps[_m.sel_step];
                _is_cur.note      = "";
                _is_cur.instr_idx = -1;
                _is_cur.empty     = true;
                _is_cur.cmd       = -1;
                _is_cur.cmd_val   = 0;
                global.undo_dirty = true;
            }
        } else {
            _m.ins_timer = 0;
        }

        var _nav_delay = round(game_get_speed(gamespeed_fps) * 0.33);
        var _kb_shift_col = keyboard_check(vk_shift);

        // Ctrl+Up (Cmd on Mac): top of the pattern. Ctrl+Down: on to the next
        // 16-row boundary (16, 32, 48 ...; held, it keeps stepping by 16).
        // Shift+Up/Down still extend the selection.
        var _kb_ctrl_nav = keyboard_check(vk_control) || scr_cmd_held();
        if (_kb_ctrl_nav) {
            var _jump = false;
            if (keyboard_check_pressed(vk_up)) {
                _m.sel_step = 0;
                _jump = true;
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
                        _m.nav_down_timer = 6;
                    }
                }
                if (_dn_go) {
                    _m.sel_step = min(_grid_len - 1, ((_m.sel_step div 16) + 1) * 16);
                    _jump = true;
                }
            } else {
                _m.nav_down_timer = 0;
            }
            if (_jump) {
                if (_m.sel_step < _m.list_scroll) {
                    _m.list_scroll = _m.sel_step;
                }
                if (_m.sel_step >= _m.list_scroll + _vis) {
                    _m.list_scroll = _m.sel_step - _vis + 1;
                }
                _m.sel_anchor_voice = _m.sel_voice;
                _m.sel_anchor_step  = _m.sel_step;
            }
        }

        if (keyboard_check(vk_up) && !_kb_ctrl_nav) {
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

        if (keyboard_check(vk_down) && !_kb_ctrl_nav) {
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
        } else if (!keyboard_check(vk_down)) {
            _m.nav_down_timer = 0;   // (Ctrl+Down's own repeat keeps it while held)
        }

        if (keyboard_check_pressed(vk_home)) {
            _m.sel_step = 0;
            if (_m.sel_step < _m.list_scroll) { _m.list_scroll = _m.sel_step; }
            _m.sel_anchor_voice = _m.sel_voice;
            _m.sel_anchor_step  = _m.sel_step;
        }

        // Plain Right/Tab walk note -> command -> next voice's note; Left
        // walks back. With Shift they extend the selection by whole voices.
        if (keyboard_check_pressed(vk_right) || (keyboard_check_pressed(vk_tab) && !_kb_shift_col)) {
            if (_kb_shift_col) {
                _m.sel_voice = min(2, _m.sel_voice + 1);
            } else if (_m.sel_sub == 0) {
                _m.sel_sub = 1;
            } else if (_m.sel_voice == 2) {
                // Past voice 3's command column: into the DIGI lane.
                scr_digi_focus_from_grid(_m);
            } else {
                _m.sel_sub = 0;
                _m.sel_voice = _m.sel_voice + 1;
            }
            if (!_kb_shift_col) { _m.sel_anchor_voice = _m.sel_voice; _m.sel_anchor_step = _m.sel_step; }
        }
        if (keyboard_check_pressed(vk_left) || (keyboard_check_pressed(vk_tab) && _kb_shift_col)) {
            if (_kb_shift_col && keyboard_check_pressed(vk_left)) {
                _m.sel_voice = max(0, _m.sel_voice - 1);
            } else if (_m.sel_sub == 1) {
                _m.sel_sub = 0;
            } else if (_m.sel_voice == 0) {
                // Left of voice 1's note wraps round to the DIGI lane.
                scr_digi_focus_from_grid(_m);
            } else {
                _m.sel_sub = 1;
                _m.sel_voice = _m.sel_voice - 1;
            }
            if (!_kb_shift_col) { _m.sel_anchor_voice = _m.sel_voice; _m.sel_anchor_step = _m.sel_step; }
        }

        if (_cur_step != noone && _m.sel_sub == 0 && keyboard_check_pressed(vk_enter)) {
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
            draw_text_l((_cl_x1 + _cl_x2) * 0.5, _clr_y + 5, "CLEAR");
        } else {
            var _cl_idx = string(_col_pat_idx[_cli]);
            if (_col_pat_idx[_cli] < 10) {
                _cl_idx = "0" + _cl_idx;
            }
            draw_text_l((_cl_x1 + _cl_x2) * 0.5, _clr_y + 5, L("CLEAR PAT ") + _cl_idx);
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
                    for (var _refv = 0; _refv < 24; _refv++) {
                        if (scr_music_sid_pattern(_cr_row, _refv) == _col_pat_idx[_cli]) _cl_refs += 1;
                    }
                }
            }

            for (var _cs = 0; _cs < array_length(_cl_pat.steps); _cs++) {
                var _cs_step = _cl_pat.steps[_cs];
                _cs_step.note      = "";
                _cs_step.instr_idx = -1;
                _cs_step.empty     = true;
                _cs_step.cmd       = -1;
                _cs_step.cmd_val   = 0;
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

    // ── Command legend ──
    draw_set_font_l(fnt_c64_pico);
    draw_set_color(make_color_rgb(150, 120, 90));
    draw_text_l(_col_gutter_x, _clr_y + 28,
        "CMD HELP: 1XX UP 2XX DOWN 3XX SLIDE 4XY VIBRATO | 5AD ATTACK/DECAY 6SR SUSTAIN/RELEASE");
    draw_text_l(_col_gutter_x, _clr_y + 40,
        "7XX WAVE 8XX PULSE WIDTH 9XX PULSE SWEEP | AXX CUTOFF (XX*8) BX0 RESONANCE CXX CUTOFF SWEEP");
    draw_text_l(_col_gutter_x, _clr_y + 52,
        "EXX FILTER MODE (1 LP 2 BP 4 HP 8 V3 OFF) DXX $D418 FXX TEMPO | GXX FINE HXX PITCH IXX PULSE J00 TIE | 1-4,9,C ONE ROW");
    draw_set_font_l(fnt_c64_tiny);
    // Small GUIDE button at the legend's right edge: opens the full command guide.
    draw_set_font_l(fnt_c64_pico);
    var _gb_w = string_width_l("GUIDE") + 14;
    var _gb_x = _col_gutter_x + _grid_full_w - _gb_w;
    var _gb_y = _clr_y + 27;
    var _gb_hot = point_in_rectangle(_mx, _my, _gb_x, _gb_y, _gb_x + _gb_w, _gb_y + 15);
    draw_set_color(_gb_hot ? make_color_rgb(65, 80, 100) : make_color_rgb(30, 38, 52));
    draw_rectangle(_gb_x, _gb_y, _gb_x + _gb_w, _gb_y + 15, false);
    draw_set_color(c_white);
    draw_text_l(_gb_x + 7, _gb_y + 2, "GUIDE");
    draw_set_font_l(fnt_c64_tiny);
    if (_gb_hot && mouse_check_button_pressed(mb_left)) {
        global.music_cmd_guide_open = true;
    }

    // ═════════════════════════════════════════════════════════════════════
    // RIGHT PANEL — SONG ORDER TABLE
    // ═════════════════════════════════════════════════════════════════════
    var _ox0 = _col_gutter_x + _grid_full_w + 24;
    // Right panel sits lower than the grid so the SONG selector strip has a
    // clear row of its own — at _gy0 it lands in the header band and collides
    // with the octave stepper.
    var _oy0 = _gy0 + 26;
    var _ord_row_h = 28;
    // As many rows as fit above the buttons + help line, inside the window.
    var _ord_vis   = clamp(floor((_vy2 - 52 - _oy0) / _ord_row_h), 8, 30);
    var _ord_col_w = [34, 62, 62, 62, 62, 52, 62];
    var _ord_x = [_ox0];
    for (var _oc = 0; _oc < array_length(_ord_col_w); _oc++) {
        array_push(_ord_x, _ord_x[_oc] + _ord_col_w[_oc]);
    }
    var _ord_full_w = _ord_x[array_length(_ord_x) - 1] - _ox0;

    draw_set_font_l(fnt_c64_tiny);

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
    draw_text_l(_sg_px1 + 9, _sgy + 4, "<");
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
        draw_text_l((_sg_nx1 + _sg_nx2) * 0.5, _sgy + 4, _sg_disp);
    } else {
        draw_set_color(_sg_n_hov ? c_aqua : make_color_rgb(255, 200, 100));
        draw_text_l((_sg_nx1 + _sg_nx2) * 0.5, _sgy + 4,
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
    draw_text_l(_sg_nnx1 + 9, _sgy + 4, ">");
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
    draw_text_l((_sg_ax1 + _sg_ax2) * 0.5, _sgy + 4, "+ SONG");
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
    draw_text_l((_sg_dx1 + _sg_dx2) * 0.5, _sgy + 4, "DEL SONG");
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
    draw_text_l(_ox0, _oy0 - 34, _m.order_pattern_edit_active ? "ENTER: SET / ESC: CANCEL" : "SONG ORDER");

    var _ord_hdr = ["#", "V" + string(_voice_offset + 1), "V" + string(_voice_offset + 2), "V" + string(_voice_offset + 3), "DG", "RPT", "SIZE"];
    for (var _ohi = 0; _ohi < array_length(_ord_hdr); _ohi++) {
        draw_set_color(make_color_rgb(120, 120, 160));
        draw_set_halign(fa_center);
        draw_text_l(_ord_x[_ohi] + (_ord_col_w[_ohi] * 0.5), _oy0 - 16, _ord_hdr[_ohi]);
        draw_set_halign(fa_left);
    }

    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_ox0 - 4, _oy0 - 2, _ox0 + _ord_full_w + 4, _oy0 + _ord_vis * _ord_row_h + 2, false);
    draw_set_color(make_color_rgb(100, 100, 140));
    draw_rectangle(_ox0 - 4, _oy0 - 2, _ox0 + _ord_full_w + 4, _oy0 + _ord_vis * _ord_row_h + 2, true);

    // Song playback follows the playing order row: it sits in the middle of the
    // table, and only near the start or end (where the clamp below stops the
    // scroll) does the marker move off-centre towards the top or bottom.
    if (_m.song_playing) {
        _m.order_scroll = _m.preview_display_order - floor(_ord_vis / 2);
    }
    _m.order_scroll = clamp(_m.order_scroll, 0, max(0, array_length(_cur_song.order) - _ord_vis));

    for (var _orv = 0; _orv < _ord_vis; _orv++) {
        var _ord_i = _orv + _m.order_scroll;
        if (_ord_i >= array_length(_cur_song.order)) {
            break;
        }
        var _orow = _cur_song.order[_ord_i];
        var _ory  = _oy0 + _orv * _ord_row_h;

        var _ord_active = (_m.song_playing && _ord_i == _m.preview_display_order);
        // TIMING: PER VOICE: voices sit on different order rows, so each
        // voice's own cell is lit below instead of the whole row.
        if (is_array(_voice_pos)) _ord_active = false;
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
        draw_text_l(_ord_x[0] + (_ord_col_w[0] * 0.5), _ory + 6, string(_ord_i));
        draw_set_halign(fa_left);

        var _voice_keys = _page_keys;
        var _voice_colours = [make_color_rgb(120, 220, 255), make_color_rgb(255, 200, 120), make_color_rgb(180, 255, 150)];
        for (var _ovi = 0; _ovi < 3; _ovi++) {
            var _ocx = _ord_x[1 + _ovi];
            var _ocw = _ord_col_w[1 + _ovi];
            if (is_array(_voice_pos) && _voice_pos[_ovi][0] == _ord_i) {
                draw_set_color(make_color_rgb(30, 90, 55));
                draw_rectangle(_ocx, _ory, _ocx + _ocw, _ory + _ord_row_h, false);
            }
            var _oc_val = scr_music_sid_pattern(_orow, _voice_offset + _ovi);
            var _minus = _mx >= _ocx && _mx < _ocx + 15 && _my >= _ory && _my < _ory + _ord_row_h;
            var _plus = _mx >= _ocx + _ocw - 15 && _mx < _ocx + _ocw && _my >= _ory && _my < _ory + _ord_row_h;
            var _number_hov = _mx >= _ocx + 15 && _mx < _ocx + _ocw - 15 && _my >= _ory && _my < _ory + _ord_row_h;
            var _editing = _m.order_pattern_edit_active && _m.order_pattern_edit_row == _orow && _m.order_pattern_edit_key == _voice_keys[_ovi];
            draw_set_color(make_color_rgb(65, 85, 120));
            if (_minus) draw_rectangle(_ocx + 1, _ory + 2, _ocx + 14, _ory + _ord_row_h - 2, false);
            if (_plus) draw_rectangle(_ocx + _ocw - 14, _ory + 2, _ocx + _ocw - 1, _ory + _ord_row_h - 2, false);
            draw_set_halign(fa_center);
            draw_set_color(_minus ? c_white : make_color_rgb(125, 135, 155));
            draw_text_l(_ocx + 7, _ory + 6, "-");
            draw_set_color(_plus ? c_white : make_color_rgb(125, 135, 155));
            draw_text_l(_ocx + _ocw - 7, _ory + 6, "+");
            var _oc_str = _oc_val < 0 ? "--" : string(_oc_val);
            while (string_length(_oc_str) < 2) _oc_str = "0" + _oc_str;
            if (_editing) {
                draw_set_color(make_color_rgb(255, 210, 90));
                draw_rectangle(_ocx + 15, _ory + 1, _ocx + _ocw - 15, _ory + _ord_row_h - 1, true);
                _oc_str = _m.order_pattern_edit_buf;
            }
            draw_set_color(_editing ? c_yellow : _voice_colours[_ovi]);
            draw_text_l(_ocx + _ocw * 0.5, _ory + 6, _oc_str);
            draw_set_halign(fa_left);
            if ((_minus || _plus) && mouse_check_button_pressed(mb_left)) {
                var _next = _oc_val + (_plus ? 1 : -1);
                if (_next >= array_length(_m.patterns)) _next = -1;
                if (_next < -1) _next = array_length(_m.patterns) - 1;
                _orow[$ _voice_keys[_ovi]] = _next;
                global.undo_dirty = true;
                global.addresses_dirty = true;
            }
            if (_number_hov && mouse_check_button_pressed(mb_left)) {
                if (_m.instr_edit_active && _m.sel_instr >= 0) scr_sound_editor_commit_instrument(_m, _m.instruments[_m.sel_instr]);
                _m.edit_active = false;
                _m.instr_edit_active = false;
                _m.instr_name_edit_active = false;
                _m.song_name_edit_active = false;
                _m.order_pattern_edit_active = true;
                _m.order_pattern_edit_song = _cur_song;
                _m.order_pattern_edit_page = _m.sid_page;
                _m.order_pattern_edit_row = _orow;
                _m.order_pattern_edit_key = _voice_keys[_ovi];
                _m.order_pattern_edit_buf = _oc_val < 0 ? "--" : string(_oc_val);
                _m.order_pattern_edit_replace = true;
                keyboard_string = "";
            }
        }

        // ── DG ── digi pattern for this row; - / + cycle -1..last (NEW in the
        // grid's DIGI header makes one).
        var _dgx = _ord_x[4];
        var _dgw = _ord_col_w[4];
        var _dg_minus = point_in_rectangle(_mx, _my, _dgx, _ory, _dgx + 14, _ory + _ord_row_h - 1);
        var _dg_plus  = point_in_rectangle(_mx, _my, _dgx + _dgw - 14, _ory, _dgx + _dgw, _ory + _ord_row_h - 1);
        draw_set_halign(fa_center);
        draw_set_color(make_color_rgb(125, 135, 155));
        if (_dg_minus) {
            draw_set_color(c_white);
        }
        draw_text_l(_dgx + 7, _ory + 6, "-");
        draw_set_color(make_color_rgb(125, 135, 155));
        if (_dg_plus) {
            draw_set_color(c_white);
        }
        draw_text_l(_dgx + _dgw - 7, _ory + 6, "+");
        var _dg_str = "--";
        if (_orow.dg >= 0) {
            _dg_str = string(_orow.dg);
            if (_orow.dg < 10) {
                _dg_str = "0" + _dg_str;
            }
        }
        draw_set_color(make_color_rgb(255, 130, 170));
        draw_text_l(_dgx + _dgw * 0.5, _ory + 6, _dg_str);
        draw_set_halign(fa_left);
        if ((_dg_minus || _dg_plus) && mouse_check_button_pressed(mb_left)) {
            scr_digi_push_undo(_m, _se_push_undo, _se_snap);
            var _dg_next = _orow.dg + 1;
            if (_dg_minus) {
                _dg_next = _orow.dg - 1;
            }
            if (_dg_next >= array_length(_m.digi_patterns)) {
                _dg_next = -1;
            }
            if (_dg_next < -1) {
                _dg_next = array_length(_m.digi_patterns) - 1;
            }
            _orow.dg = _dg_next;
            global.undo_dirty = true;
        }

        var _rsx = _ord_x[5];
        var _rsw = _ord_col_w[5];
        var _rs_hov = point_in_rectangle(_mx, _my, _rsx, _ory, _rsx + _rsw, _ory + _ord_row_h);
        draw_set_color(_orow.repeat_short ? c_lime : make_color_rgb(140, 90, 90));
        draw_set_halign(fa_center);
        if (_m.free_voices) {
            // no shared row count to repeat a short pattern into
            draw_set_color(make_color_rgb(80, 80, 100));
            draw_text_l(_rsx + (_rsw * 0.5), _ory + 6, "--");
            _rs_hov = false;
        } else {
            draw_text_l(_rsx + (_rsw * 0.5), _ory + 6, _orow.repeat_short ? "RPT" : L("NO"));
        }
        draw_set_halign(fa_left);
        if (_rs_hov && mouse_check_button_pressed(mb_left)) {
            _se_push_undo(_m, _se_snap);
            _orow.repeat_short = !_orow.repeat_short;
            global.undo_dirty  = true;
        }

        var _flx = _ord_x[6];
        var _flw = _ord_col_w[6];
        var _fl_dnx1 = _flx;
        var _fl_dnx2 = _flx + 16;
        var _fl_upx1 = _flx + _flw - 16;
        var _fl_upx2 = _flx + _flw;
        var _fl_hov_dn = point_in_rectangle(_mx, _my, _fl_dnx1, _ory, _fl_dnx2, _ory + _ord_row_h);
        var _fl_hov_up = point_in_rectangle(_mx, _my, _fl_upx1, _ory, _fl_upx2, _ory + _ord_row_h);

        if (!_m.free_voices) {
            draw_set_color(_fl_hov_dn ? c_aqua : make_color_rgb(100, 100, 100));
            draw_text_l(_fl_dnx1 + 4, _ory + 6, "-");
            draw_set_color(_fl_hov_up ? c_aqua : make_color_rgb(100, 100, 100));
            draw_text_l(_fl_upx1 + 4, _ory + 6, "+");
        }

        draw_set_color((_orow.force_len > 0) ? c_aqua : make_color_rgb(90, 90, 110));
        draw_set_halign(fa_center);
        if (_m.free_voices) {
            // TIMING: PER VOICE ignores SIZE: each pattern plays its own LEN.
            draw_set_color(make_color_rgb(80, 80, 100));
            draw_text_l(_flx + (_flw * 0.5), _ory + 6, "AUTO");
            _fl_hov_dn = false;
            _fl_hov_up = false;
        } else {
            draw_text_l(_flx + (_flw * 0.5), _ory + 6, (_orow.force_len > 0) ? string(_orow.force_len) : L("OFF"));
        }
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
        &&  !point_in_rectangle(_mx, _my, _ord_x[1], _ory, _ord_x[7], _ory + _ord_row_h)) {
            _m.sel_order_row = _ord_i;
        }
    }

    // ── COLUMN DIVIDERS — drawn after rows so they sit on top of each
    // row's background fill instead of being painted over by it. ──
    draw_set_color(make_color_rgb(100, 100, 140));
    for (var _odiv = 1; _odiv <= 6; _odiv++) {
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
    draw_text_l((_oax1 + _oax2) * 0.5, _oby + 4, "+ ADD ROW");
    draw_set_halign(fa_left);
    if (_oa_hov && mouse_check_button_pressed(mb_left)) {
        array_push(_cur_song.order, { v1: 0, v2: -1, v3: -1, dg: -1, repeat_short: false, force_len: 0 });
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
    draw_text_l((_llx1 + _llx2) * 0.5, _oby + 4, _cur_song.loop ? L("LOOP") : L("NO LOOP"));
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
    draw_text_l((_lpx1 + _lpx2) * 0.5, _oby + 4, L("SET LOOP @ ROW ") + string(_m.sel_order_row));
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
    draw_text_l((_odx1 + _odx2) * 0.5, _oby + 4, "DEL ROW");
    draw_set_halign(fa_left);
    if (_od_hov && mouse_check_button_pressed(mb_left)) {
        array_delete(_cur_song.order, _m.sel_order_row, 1);
        _m.sel_order_row = clamp(_m.sel_order_row, 0, array_length(_cur_song.order) - 1);
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    draw_set_font_l(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 110, 150));
    draw_text_l(_ox0, _oby + 24, "CLICK CELL/ROW: SELECT + NEXT PATTERN   |   RMB: PREV   |   CTRL+CLICK: NONE (--)");
    draw_set_font_l(fnt_c64_tiny);

    if (point_in_rectangle(_mx, _my, _ox0 - 4, _oy0 - 2, _ox0 + _ord_full_w + 4, _oy0 + _ord_vis * _ord_row_h + 2)) {
        if (mouse_wheel_up())   { _m.order_scroll = max(0, _m.order_scroll - 1); }
        if (mouse_wheel_down()) { _m.order_scroll = min(max(0, array_length(_cur_song.order) - _ord_vis), _m.order_scroll + 1); }
    }


    // ═════════════════════════════════════════════════════════════════════
    // FAR RIGHT PANEL — INSTRUMENTS
    // ═════════════════════════════════════════════════════════════════════
    // 50px clear of the order table: its button row runs ~30px past the table.
    var _ix0 = _ox0 + _ord_full_w + 50;
    scr_sound_editor_draw_instruments(_m, _ix0, _oy0, _mx, _my, _vx2 - 16, _vy2 - 12);

    // ── PIANO ── along the bottom, under a divider.
    draw_set_color(make_color_rgb(60, 70, 90));
    draw_line(_vx1 + 20, _vy2 + 4, _vx2 - 20, _vy2 + 4);
    scr_sound_editor_piano(_m, _vx1 + 20, _vy2 + 14, _vx2 - 20, _vy2_full - 12, _mx, _my,
                           _col_pat, _vis, _se_push_undo, _se_snap);

    // Transient messages: centred just above the piano, on a backing plate so
    // they never collide with the status line's BYTES readout.
    if (_m.warn_timer > 0) {
        draw_set_font_l(fnt_c64_tiny);
        var _wm_w = string_width_l(_m.warn_msg) + 24;
        var _wm_cx = (_vx1 + _vx2) * 0.5;
        var _wm_y = _vy2 - 20;
        draw_set_color(make_color_rgb(30, 26, 12));
        draw_rectangle(_wm_cx - _wm_w * 0.5, _wm_y - 3, _wm_cx + _wm_w * 0.5, _wm_y + 15, false);
        draw_set_color(make_color_rgb(150, 120, 50));
        draw_rectangle(_wm_cx - _wm_w * 0.5, _wm_y - 3, _wm_cx + _wm_w * 0.5, _wm_y + 15, true);
        draw_set_color(make_color_rgb(255, 200, 90));
        draw_set_halign(fa_center);
        draw_text_l(_wm_cx, _wm_y, _m.warn_msg);
        draw_set_halign(fa_left);
        _m.warn_timer -= 1;
    }

    // ── DIGI SAMPLES PANEL ── over everything except the tooltip; uses the
    // real mouse (the editor's copy is hidden while over the panel).
    var _dg_rect = scr_digi_slots_rect(_dg_x, _dg_w, _gy0);
    _m.dg_panel_rect = _dg_rect;
    if (_m.dg_slots_open && !_cg_open) {
        scr_digi_slots_panel(_m, _dg_rect, _dg_pmx, _dg_pmy);
    }

    // Draw help last, retaining the existing sweep warnings and their red border.
    var _tip_text = (_pw_tip != "") ? _pw_tip : _m.pattern_hover_tip;
    if (_tip_text != "") {
        draw_set_font_l(fnt_c64_pico);
        var _tt_w = min(string_width_l(_tip_text) + 16, max(32, _vx2 - _vx1 - 16));
        var _tt_h = string_height_ext_l(_tip_text, -1, _tt_w - 16) + 12;
        var _tt_x = max(_vx1 + 4, min(_mx + 14, _vx2 - _tt_w - 4));
        var _tt_y = max(_cy, min(_my + 18, _vy2_full - _tt_h - 4));
        draw_set_color((_pw_tip != "") ? make_color_rgb(40, 10, 10) : make_color_rgb(18, 26, 40));
        draw_rectangle(_tt_x, _tt_y, _tt_x + _tt_w, _tt_y + _tt_h, false);
        draw_set_color((_pw_tip != "") ? c_red : c_aqua);
        draw_rectangle(_tt_x, _tt_y, _tt_x + _tt_w, _tt_y + _tt_h, true);
        draw_set_color(c_white);
        draw_text_ext_l(_tt_x + 8, _tt_y + 6, _tip_text, -1, _tt_w - 16);
        draw_set_font_l(fnt_c64_tiny);
    }

    if (_cg_open) {
        scr_sound_editor_cmd_guide(_vx1, _vy1, _vx2, _vy2_full, _cg_mx, _cg_my, _cg_click, _cg_esc);
    }

    draw_set_alpha(1.0);
    draw_set_color(c_white);
    draw_set_halign(fa_left);
}

/// The pattern-command guide panel: every command in full, over the editor.
/// Closes with its CLOSE button or Escape (the editor gets no input meanwhile).
function scr_sound_editor_cmd_guide(_x1, _y1, _x2, _y2, _mx, _my, _click, _esc) {
    draw_set_alpha(0.75);
    draw_set_color(c_black);
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_alpha(1.0);
    var _pw = min(_x2 - _x1 - 40, 1500);
    var _ph = min(_y2 - _y1 - 40, 900);
    var _px = _x1 + floor((_x2 - _x1 - _pw) / 2);
    var _py = _y1 + floor((_y2 - _y1 - _ph) / 2);
    draw_set_color(make_color_rgb(14, 14, 24));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, false);
    draw_set_color(make_color_rgb(120, 120, 170));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, true);
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);
    draw_set_color(make_color_rgb(255, 200, 100));
    draw_text_l(_px + 16, _py + 12, "PATTERN COMMANDS  -  TYPE THE LETTER, THEN TWO HEX DIGITS (00-FF)");
    // How entry works (pattern cells and the digi lane), full width.
    draw_set_font_l(fnt_c64_pico);
    var _intro = scr_sound_editor_guide_intro();
    var _intro_w = _pw - 32;
    draw_set_color(make_color_rgb(170, 200, 230));
    draw_text_ext_l(_px + 16, _py + 36, _intro, -1, _intro_w);
    var _top = _py + 36 + string_height_ext_l(_intro, -1, _intro_w) + 14;
    draw_set_color(make_color_rgb(70, 70, 100));
    draw_line(_px + 16, _top - 7, _px + _pw - 16, _top - 7);
    // Every command in full, in three columns: one-row effects, settings,
    // then the persistent / special ones.
    var _order = [0, 1, 2, 3, 4, 9, 12, 5, 6, 7, 8, 10, 11, 13, 14, 15, 16, 17, 18, 19];
    var _col_of = [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2];
    var _letters = "0123456789ABCDEFGHIJ";
    var _colw = floor((_pw - 64) / 3);
    var _cx = [_px + 16, _px + 32 + _colw, _px + 48 + _colw * 2];
    var _cy = [_top, _top, _top];
    for (var _i = 0; _i < array_length(_order); _i++) {
        var _c = _order[_i];
        var _col = _col_of[_i];
        var _txt = scr_sound_editor_pattern_help(_c);
        var _h = string_height_ext_l(_txt, -1, _colw - 40) + 10;
        if (_cy[_col] + _h > _py + _ph - 44) continue;
        draw_set_color(make_color_rgb(255, 170, 90));
        draw_text_l(_cx[_col], _cy[_col], string_char_at(_letters, _c + 1) + "XX");
        draw_set_color(make_color_rgb(205, 205, 225));
        draw_text_ext_l(_cx[_col] + 40, _cy[_col], _txt, -1, _colw - 40);
        _cy[_col] += _h;
    }
    draw_set_color(make_color_rgb(150, 150, 180));
    draw_text_l(_px + 16, _py + _ph - 30, "1-4, 9 AND C LAST ONE ROW. G-J AND THE SETTINGS (5-8, A, B, D, E) STAY UNTIL CHANGED. ESC OR CLOSE TO RETURN.");
    draw_set_font_l(fnt_c64_tiny);
    // Own button: the editor's input was cleared for this frame, so the click
    // captured before that is what counts here.
    var _cbx = _px + _pw - 110;
    var _cby = _py + _ph - 34;
    var _cb_hot = point_in_rectangle(_mx, _my, _cbx, _cby, _cbx + 96, _cby + 26);
    draw_set_color(_cb_hot ? make_color_rgb(65, 80, 100) : make_color_rgb(30, 38, 52));
    draw_rectangle(_cbx, _cby, _cbx + 96, _cby + 26, false);
    draw_set_color(c_white);
    draw_text_l(_cbx + 8, _cby + 5, "CLOSE");
    if ((_cb_hot && _click) || _esc) {
        global.music_cmd_guide_open = false;
        keyboard_clear(vk_escape);
    }
}
/// Transpose each selected stored note once, even when lanes share a pattern.
/// Validate the whole operation first so boundary notes never squash intervals.
function scr_sound_editor_transpose(_m, _patterns, _indices, _v0, _v1, _s0, _s1, _delta, _push_undo, _snapshot) {
    var _seen = [];
    var _changes = [];
    var _names = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"];
    for (var _v = _v0; _v <= _v1; _v++) {
        var _pat = _patterns[_v];
        if (_pat == noone) continue;
        var _duplicate = false;
        for (var _i = 0; _i < array_length(_seen); _i++) {
            if (_seen[_i] == _indices[_v]) _duplicate = true;
        }
        if (_duplicate) continue;
        array_push(_seen, _indices[_v]);
        for (var _r = _s0; _r <= _s1 && _r < _pat.pattern_len; _r++) {
            var _step = _pat.steps[_r];
            if (_step.empty) continue;
            var _note = scr_sid_song_note_index(_step.note);
            if (_note < 0) continue; // Holds, key-off/on and invalid notes stay intact.
            var _next = _note + _delta;
            if (_next < 0 || _next > 95) {
                _m.warn_msg = "TRANSPOSE CANCELLED: NOTES MUST STAY BETWEEN C-0 AND B-7";
                _m.warn_timer = game_get_speed(gamespeed_fps) * 3;
                return 0;
            }
            array_push(_changes, { step: _step, note: _names[_next mod 12] + string(floor(_next / 12)) });
        }
    }
    if (array_length(_changes) == 0) return 0;
    _push_undo(_m, _snapshot);
    for (var _c = 0; _c < array_length(_changes); _c++) {
        _changes[_c].step.note = _changes[_c].note;
    }
    global.undo_dirty = true;
    global.addresses_dirty = true;
    _m.warn_msg = "TRANSPOSED " + string(array_length(_changes)) + " NOTES: "
        + ((_delta > 0) ? "+" : "") + string(_delta) + " SEMITONES";
    _m.warn_timer = game_get_speed(gamespeed_fps) * 2;
    return array_length(_changes);
}
