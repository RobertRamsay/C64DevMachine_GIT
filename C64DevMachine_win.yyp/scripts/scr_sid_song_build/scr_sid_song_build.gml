/// @function scr_sid_song_build(_list, _id, _se, _asset_name, _auto_init, _zp, _hr, _chip_base, _sfx)
/// @desc The MACRO_SID_SONG player + data for Music Maker asset _se, pushed
///       onto _list. Used by the MACRO_SID_SONG node (scr_compile_chain) and by
///       EXPORT SID (scr_sound_editor_export_sid), so both are the same player.
///       _id tags every row and supplies stable_uid for the label prefix.
///       _sfx adds GoatTracker-compatible sound-effect support (export only):
///       <key>sfxt is the trigger routine, see scr_sid_song_emit_sfx.
///       Returns false when the asset has nothing to play (nothing pushed).
function scr_sid_song_build(_list, _id, _se, _asset_name, _auto_init, _zp, _hr, _chip_base, _sfx, _prefix = "") {
    var _sm = _se.meta;
    if (_prefix == "" && scr_music_sid_count(_sm) > 1) {
        return scr_music_sid_build(_list, _id, _se, _asset_name, _auto_init, _zp, _hr, _chip_base);
    }
    var _voice_mask=variable_struct_exists(_sm,"voice_mask") ? (real(_sm.voice_mask)&7) : 7;

    var _instruments = (variable_struct_exists(_sm, "instruments") && is_array(_sm.instruments)) ? _sm.instruments : [];
    var _patterns    = (variable_struct_exists(_sm, "patterns")    && is_array(_sm.patterns))    ? _sm.patterns    : [];
    var _play_speed  = (variable_struct_exists(_sm, "play_speed")  && is_real(_sm.play_speed))   ? real(_sm.play_speed) : 6;

    // ── SONGS ── every song's order rows are CONCATENATED into one set of
    // order tables. _S_ORD stays a single absolute index into them, so the
    // per-voice trigger code is unchanged; a song is just a [start, end)
    // slice, resolved once at init/seek rather than looked up per row.
    //
    // A pre-songs[] asset that has never been opened in the editor still has
    // only the bare song_order — fold it into a single song here so the
    // build doesn't depend on the user having opened the editor first.
    var _songs = [];
    if (variable_struct_exists(_sm, "songs") && is_array(_sm.songs) && array_length(_sm.songs) > 0) {
        _songs = _sm.songs;
    } else {
        var _legacy_order = (variable_struct_exists(_sm, "song_order") && is_array(_sm.song_order)) ? _sm.song_order : [];
        var _legacy_loop = true;
        if (variable_struct_exists(_sm, "song_loop")) {
            _legacy_loop = _sm.song_loop;
        }
        var _legacy_loop_row = 0;
        if (variable_struct_exists(_sm, "song_loop_row")) {
            _legacy_loop_row = real(_sm.song_loop_row);
        }
        _songs = [ { name: "SONG 00", order: _legacy_order, loop: _legacy_loop, loop_row: _legacy_loop_row } ];
    }

    // Flatten: one order row list, plus per-song start/end/loop/flags.
    // Rows are clipped at 255 total because _S_ORD is one byte.
    var _song_order  = [];   // concatenated rows, in song order
    var _song_start  = [];   // first order-table index of song n
    var _song_end    = [];   // one past the last index of song n
    var _song_lp     = [];   // absolute order index to wrap back to
    var _song_fl     = [];   // bit 0 = loop on
    var _n_songs     = 0;

    for (var _si = 0; _si < array_length(_songs); _si++) {
        var _s_ent = _songs[_si];
        var _s_ord = [];
        if (variable_struct_exists(_s_ent, "order") && is_array(_s_ent.order)) {
            _s_ord = _s_ent.order;
        }
        if (array_length(_s_ord) == 0) {
            show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' song " + string(_si)
                + " has no order rows — skipped (not emitted, later songs shift down by one index).");
            continue;
        }
        if (array_length(_song_order) >= 255) {
            show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' order rows exceed 255 across all"
                + " songs; song " + string(_si) + " onward is dropped.");
            break;
        }

        var _s_start = array_length(_song_order);
        for (var _sri = 0; _sri < array_length(_s_ord); _sri++) {
            if (array_length(_song_order) >= 255) {
                show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' song " + string(_si)
                    + " truncated at 255 total order rows.");
                break;
            }
            array_push(_song_order, _s_ord[_sri]);
        }
        var _s_end = array_length(_song_order);

        var _s_loop = true;
        if (variable_struct_exists(_s_ent, "loop")) {
            _s_loop = _s_ent.loop;
        }
        var _s_loop_row = 0;
        if (variable_struct_exists(_s_ent, "loop_row")) {
            _s_loop_row = real(_s_ent.loop_row);
        }
        // loop_row is stored per-song (0-based within the song); the runtime
        // needs an absolute index into the concatenated table.
        _s_loop_row = clamp(_s_loop_row, 0, (_s_end - _s_start) - 1);

        array_push(_song_start, _s_start & 0xFF);
        array_push(_song_end,   _s_end   & 0xFF);
        array_push(_song_lp,   (_s_start + _s_loop_row) & 0xFF);
        array_push(_song_fl,   (_s_loop == true) ? 1 : 0);
        _n_songs += 1;
    }

    if (_n_songs > 255) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has " + string(_n_songs)
            + " songs; only the first 255 are addressable — the rest are dropped.");
        _n_songs = 255;
        array_resize(_song_start, 255);
        array_resize(_song_end,   255);
        array_resize(_song_lp,    255);
        array_resize(_song_fl,    255);
    }

    var _n_instr = array_length(_instruments);
    var _n_pat   = array_length(_patterns);
    var _n_ord   = array_length(_song_order);

    if (_n_pat == 0 || _n_ord == 0 || _n_songs == 0) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has no patterns, no order rows or no songs — skipping");
        return false;
    }
    if (_n_instr > 255) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has " + string(_n_instr)
            + " instruments; only the first 255 are addressable — the rest are dropped.");
        _n_instr = 255;
    }
    if (_n_pat > 255) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has " + string(_n_pat)
            + " patterns; only the first 255 are addressable — the rest are dropped.");
        _n_pat = 255;
    }
    if (_n_ord > 255) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has " + string(_n_ord)
            + " order rows; only the first 255 are addressable — the rest are dropped.");
        _n_ord = 255;
    }

    _play_speed = clamp(_play_speed, 1, 255);

    show_debug_message("SID_SONG: play_speed=" + string(_play_speed)
        + " n_songs=" + string(_n_songs) + " n_ord=" + string(_n_ord)
        + " n_pat=" + string(_n_pat));

    // Label prefix comes from stable_uid, NOT real(_id) — instance IDs are
    // reallocated on every load, so a JSR stored in another node would point at
    // a label that no longer exists after a save/reload cycle. stable_uid is
    // allocated once in Create and persisted by the workspace serialiser.
    var _key = (_prefix != "") ? _prefix : "sng" + string(_id.stable_uid) + "_";

    // ── ZP MAP — 7 bytes per voice, then 11 shared, then 3 HR bytes per
    //    voice, then 1 control-shadow byte per voice. 44 total. ──
    //   +0/+1  instrument stream pointer (walks the command stream)
    //   +2/+3  instrument stream BASE (fixed at trigger; $03 LOOP adds its
    //          absolute offset to this, since the walking pointer is by then
    //          somewhere in the middle of the stream)
    //   +4     hold counter — frames left on the current D
    //   +5     base note index — the row's note, before instrument offsets
    //   +6     active flag: 0 = idle, 1 = stepping an instrument
    var _V0 = _zp;
    var _V1 = _zp + 7;
    var _V2 = _zp + 14;
    var _S_ORD  = _zp + 21;   // current order row
    var _S_ROW  = _zp + 22;   // master row within the current order row
    var _S_TICK = _zp + 23;   // frames left before the next row advance
    var _S_TMP  = _zp + 24;   // scratch
    var _S_PTR  = _zp + 25;   // pattern-row pointer (2 bytes: +25/+26)
    var _S_LEN  = _zp + 27;   // table-length scratch — see the wrap logic for why
    // ── PER-SONG STATE ── resolved once at init/seek, then read by the wrap
    // logic instead of the compile-time immediates a single-song player used.
    var _S_SONG = _zp + 28;   // current song index
    var _S_END  = _zp + 29;   // one past this song's last order row (absolute)
    var _S_LOOP = _zp + 30;   // order row to wrap back to (absolute)
    var _S_FLAG = _zp + 31;   // bit 0 = loop on
    // ── PER-VOICE HARD-RESTART STATE ── 3 bytes each:
    //   +0  pending note index   (valid while the countdown is running)
    //   +1  pending instrument index
    //   +2  countdown, frames until the real trigger; 0 = idle
    var _H0 = _zp + 32;
    var _H1 = _zp + 35;
    var _H2 = _zp + 38;
    var _h_base = [_H0, _H1, _H2];
    // ── PER-VOICE CONTROL-BYTE SHADOW ── one byte each.
    //
    // SID registers are WRITE-ONLY: reading $D404 returns whatever was last on
    // the data bus, commonly another voice's control byte. So the player can
    // never read back a voice's own waveform. Anywhere it needs to change the
    // gate bit while preserving the waveform — or vice versa — it works from
    // this shadow instead and writes the whole byte.
    var _C0 = _zp + 41;
    var _C1 = _zp + 42;
    var _C2 = _zp + 43;
    var _c_base = [_C0, _C1, _C2];
    var _v_base = [_V0, _V1, _V2];

    // 44 bytes, contiguous. The KERNAL stays banked in (init writes $36, not
    // $35, so $0314/$0315 IRQ chaining keeps working), which rules out two
    // regions entirely:
    //   $A0-$A2  jiffy clock — the $EA31 IRQ tail writes it EVERY frame, so a
    //            pointer parked here is silently zeroed between instrument
    //            steps and the stepper falls through to END on every note.
    //   $90-$FF  KERNAL tape/serial/screen scratch.
    // With BASIC banked out, $03-$8F is free, so the block must start at $03
    // and end no later than $8F.
    var _zp_max = 0x8F - 43;
    if (_zp < 0x03 || _zp > _zp_max) {
        show_debug_message("MACRO_SID_SONG: ZP base $" + string_upper(decimal_to_hex(_zp))
            + " puts the 44-byte block outside the free $03-$8F window (KERNAL owns"
            + " $90-$FF and rewrites the $A0-$A2 jiffy clock every frame); using $03.");
        _zp = 0x03;
        _V0 = _zp;
        _V1 = _zp + 7;
        _V2 = _zp + 14;
        _S_ORD  = _zp + 21;
        _S_ROW  = _zp + 22;
        _S_TICK = _zp + 23;
        _S_TMP  = _zp + 24;
        _S_PTR  = _zp + 25;
        _S_LEN  = _zp + 27;
        _S_SONG = _zp + 28;
        _S_END  = _zp + 29;
        _S_LOOP = _zp + 30;
        _S_FLAG = _zp + 31;
        _H0 = _zp + 32;
        _H1 = _zp + 35;
        _H2 = _zp + 38;
        _h_base = [_H0, _H1, _H2];
        _C0 = _zp + 41;
        _C1 = _zp + 42;
        _C2 = _zp + 43;
        _c_base = [_C0, _C1, _C2];
        _v_base = [_V0, _V1, _V2];
    }

    // ════════════════════════════════════════════════════════════════
    // SHARED NOTE TABLE — 96 entries, emitted once per build.
    // Built via scr_note_name_to_freq so this and MACRO_SID_SOUND resolve
    // the same note name to the same 16-bit register value.
    // ════════════════════════════════════════════════════════════════
    if (!variable_global_exists("sidsong_notetab_emitted") || global.sidsong_notetab_emitted == false) {
        global.sidsong_notetab_emitted = true;

        var _nt_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
        var _nt_freq  = array_create(96, 0);
        for (var _nti = 0; _nti < 96; _nti++) {
            var _nt_oct  = _nti div 12;
            var _nt_step = _nti mod 12;
            var _nt_f    = scr_note_name_to_freq(_nt_names[_nt_step] + string(_nt_oct));
            if (_nt_f < 0) {
                _nt_f = 0;
            }
            _nt_freq[_nti] = _nt_f;
        }

        array_push(_list, ["jmp_abs", "SIDSONG_NT_SKIP", _id]);
        array_push(_list, ["label",   "SIDSONG_NOTELO"]);
        for (var _nti = 0; _nti < 96; _nti++) {
            array_push(_list, ["byte", _nt_freq[_nti] & 0xFF, _id]);
        }
        array_push(_list, ["label",   "SIDSONG_NOTEHI"]);
        for (var _nti = 0; _nti < 96; _nti++) {
            array_push(_list, ["byte", (_nt_freq[_nti] >> 8) & 0xFF, _id]);
        }
        array_push(_list, ["label",   "SIDSONG_NT_SKIP"]);
    }

    // ════════════════════════════════════════════════════════════════
    // DATA BLOCK — instruments, patterns, order tables. On the spine,
    // jumped over, tagged _id so Pass 1.5 sizes them onto this node.
    // ════════════════════════════════════════════════════════════════
    var _table_pack = scr_music_table_pack(_instruments);
    var _tables_used = array_length(_table_pack.tables) > 0;
    var _repeats_used = false;
    for (var _ri=0;_ri<array_length(_table_pack.streams);_ri++)
        for (var _rj=0;_rj<array_length(_table_pack.streams[_ri]);_rj++)
            if (_table_pack.streams[_ri][_rj].bytes[0] == 13) _repeats_used = true;
    var _lbl_dskip = _key + "dskip";
    // Per-voice effect state tables (see section 7).
    var _sng_state_tables = ["fql", "fqh", "fx", "fxv", "tgl", "tgh", "cvs", "cvd",
                             "ivdl", "ivs", "ivp", "vbc", "vdir", "vol", "voh", "pcmd", "pval",
                             "pwl", "pwh", "fvh", "isl", "ish", "ipl", "iph"];
    if (_repeats_used) array_push(_sng_state_tables,"reps");
    if (_tables_used) array_push(_sng_state_tables, "trl", "trh");
    array_push(_list, ["jmp_abs", _lbl_dskip, _id]);

    // True once any instrument has vibrato or any pattern has a command
    // column; when neither, the effect routines shrink to a bare pitch write.
    var _sng_any_vib = false;
    var _sng_extended_fx = false;
    // True once anything touches the filter: an instrument with FILTER ON, a
    // pattern A/B/C/E command, or a song filter mode. Only then does the
    // player carry filter code (init write, routing, commands).
    var _sng_filt_used = false;
    var _sng_filt_mode = 0;
    var _sng_filt_res  = 0;
    var _sng_filt_cut  = 0x400;
    if (variable_struct_exists(_sm, "filt_mode")) _sng_filt_mode = clamp(real(_sm.filt_mode), 0, 15);
    if (variable_struct_exists(_sm, "filt_res"))  _sng_filt_res  = clamp(real(_sm.filt_res), 0, 15);
    if (variable_struct_exists(_sm, "filt_cut"))  _sng_filt_cut  = clamp(real(_sm.filt_cut), 0, 2047);
    if ((_sng_filt_mode & 0x07) != 0) {
        _sng_filt_used = true;
    }

    // ── 1. INSTRUMENT BLOBS ──
    // 7 header bytes (AD, SR, PW lo, PW hi, VIB delay, VIB speed, VIB depth*4)
    // then the compiled command stream.
    // Re-parsed here rather than trusting instr.compiled, which is an
    // editor-side cache that may predate the last text edit.
    for (var _ii = 0; _ii < _n_instr; _ii++) {
        var _ins = _instruments[_ii];

        var _atk = 0;
        var _dec = 8;
        var _sus = 8;
        var _rel = 0;
        if (variable_struct_exists(_ins, "attack"))  _atk = clamp(real(_ins.attack),  0, 15);
        if (variable_struct_exists(_ins, "decay"))   _dec = clamp(real(_ins.decay),   0, 15);
        if (variable_struct_exists(_ins, "sustain")) _sus = clamp(real(_ins.sustain), 0, 15);
        if (variable_struct_exists(_ins, "release")) _rel = clamp(real(_ins.release), 0, 15);

        var _ins_pw = 0x0800;
        if (variable_struct_exists(_ins, "pulse_width")) {
            _ins_pw = real(_ins.pulse_width) & 0x0FFF;
        }

        var _ins_txt = "";
        if (variable_struct_exists(_ins, "text")) {
            _ins_txt = string(_ins.text);
        }
        var _ins_comp = scr_instrument_parse(_ins_txt);

        for (var _ei = 0; _ei < array_length(_ins_comp.errors); _ei++) {
            show_debug_message("MACRO_SID_SONG: instrument " + string(_ii) + " — " + string(_ins_comp.errors[_ei]));
        }

        if (variable_global_exists("sid_song_debug") && global.sid_song_debug) {
            var _dbg_b = "";
            for (var _dbi = 0; _dbi < array_length(_ins_comp.bytes); _dbi++) {
                _dbg_b += string_upper(decimal_to_hex(_ins_comp.bytes[_dbi])) + " ";
            }
            show_debug_message("INSTR " + string(_ii) + " TEXT=[" + _ins_txt + "]");
            show_debug_message("INSTR " + string(_ii) + " BYTES=" + _dbg_b
                + " (count=" + string(array_length(_ins_comp.bytes)) + ")");
        }

        array_push(_list, ["label", _key + "ins" + string(_ii)]);
        array_push(_list, ["byte", ((_atk << 4) | _dec) & 0xFF, _id]);   // AD
        array_push(_list, ["byte", ((_sus << 4) | _rel) & 0xFF, _id]);   // SR
        array_push(_list, ["byte", _ins_pw & 0xFF,              _id]);
        array_push(_list, ["byte", (_ins_pw >> 8) & 0x0F,       _id]);
        // Vibrato (phase 1): delay frames, speed (frames per half-cycle),
        // depth pre-multiplied by 4 so the player adds it straight on.
        var _ins_vdl = 0;
        var _ins_vsp = 0;
        var _ins_vdp = 0;
        if (variable_struct_exists(_ins, "vib_delay")) _ins_vdl = clamp(real(_ins.vib_delay), 0, 255);
        if (variable_struct_exists(_ins, "vib_speed")) _ins_vsp = clamp(real(_ins.vib_speed), 0, 15);
        if (variable_struct_exists(_ins, "vib_depth")) _ins_vdp = clamp(real(_ins.vib_depth), 0, 15);
        if (_ins_vsp > 0 && _ins_vdp > 0) {
            _sng_any_vib = true;
        }
        // FILTER ON: the voice is routed through the SID filter when this
        // instrument's note triggers. Carried in bit 7 of the depth byte
        // (depth * 4 never exceeds $3C).
        var _ins_filt = 0;
        if (variable_struct_exists(_ins, "filt") && real(_ins.filt) != 0) {
            _ins_filt = 1;
            _sng_filt_used = true;
        }
        array_push(_list, ["byte", _ins_vdl & 0xFF,             _id]);
        array_push(_list, ["byte", _ins_vsp & 0x0F,             _id]);
        array_push(_list, ["byte", ((_ins_vdp * 4) & 0x3F) | (_ins_comp.no_hr ? 0x40 : 0) | (_ins_filt << 7), _id]);
        scr_music_table_emit(_list, _id, _key, _table_pack.streams[_ii]);
    }

    for (var _ti = 0; _ti < array_length(_table_pack.tables); _ti++) {
        array_push(_list, ["label", _key + "table" + string(_ti)]);
        scr_music_table_emit(_list, _id, _key, _table_pack.tables[_ti]);
        array_push(_list, ["byte", 12, _id]); // Return; tables never call other tables.
    }

    // ── 2. INSTRUMENT POINTER TABLE ──
    // Always at least one entry, so a song with no instruments still has a
    // table the runtime can index without a special case.
    array_push(_list, ["label", _key + "inslo"]);
    if (_n_instr == 0) {
        array_push(_list, ["byte", 0x00, _id]);
    }
    for (var _ii = 0; _ii < _n_instr; _ii++) {
            array_push(_list, ["byte_lab_lo", _key + "ins" + string(_ii), _id]);
        }
    array_push(_list, ["label", _key + "inshi"]);
    if (_n_instr == 0) {
        array_push(_list, ["byte", 0x00, _id]);
    }
    for (var _ii = 0; _ii < _n_instr; _ii++) {
            array_push(_list, ["byte_lab_hi", _key + "ins" + string(_ii), _id]);
        }

    // ── 3. PATTERN BLOBS ── 2 bytes per row: note index, instrument index
    // (4 bytes — plus command, value — for patterns that use the command column).
    var _pattern_start = array_length(_list);
    var _pat_fx_flags = [];
    for (var _pi = 0; _pi < _n_pat; _pi++) {
        var _pat     = _patterns[_pi];
        var _pat_len = 64;
        if (variable_struct_exists(_pat, "pattern_len")) {
            _pat_len = clamp(real(_pat.pattern_len), 1, 255);
        }
        var _pat_steps = [];
        if (variable_struct_exists(_pat, "steps") && is_array(_pat.steps)) {
            _pat_steps = _pat.steps;
        }

        // A pattern with any command cell is emitted with 4-byte rows (note,
        // instrument, command, value); every other pattern keeps 2-byte rows,
        // so songs without commands compile to exactly the old size.
        var _pat_has_fx = false;
        for (var _fxi = 0; _fxi < array_length(_pat_steps); _fxi++) {
            var _fx_st = _pat_steps[_fxi];
            if (variable_struct_exists(_fx_st, "cmd") && real(_fx_st.cmd) >= 0) {
                _pat_has_fx = true;
                var _fx_c = real(_fx_st.cmd);
                if (_fx_c >= 16 && _fx_c <= 18) _sng_extended_fx = true;
                if (_fx_c == 0x0A || _fx_c == 0x0B || _fx_c == 0x0C || _fx_c == 0x0E) {
                    _sng_filt_used = true;
                }
            }
        }
        array_push(_pat_fx_flags, _pat_has_fx);

        array_push(_list, ["label", _key + "pat" + string(_pi)]);

        for (var _ri = 0; _ri < _pat_len; _ri++) {
            var _note_byte  = 0xFE;   // default: empty / hold
            var _instr_byte = 0xFF;   // default: no instrument

            if (_ri < array_length(_pat_steps)) {
                var _st = _pat_steps[_ri];

                var _st_empty = true;
                if (variable_struct_exists(_st, "empty")) {
                    _st_empty = _st.empty;
                }
                var _st_note = "";
                if (variable_struct_exists(_st, "note")) {
                    _st_note = string(_st.note);
                }
                var _st_instr = -1;
                if (variable_struct_exists(_st, "instr_idx")) {
                    _st_instr = real(_st.instr_idx);
                }

                if (_st_empty == true) {
                    _note_byte = 0xFE;
                } else if (_st_note == "+++") {
                    _note_byte = 0xFD;   // key on: gate back on, same note
                } else if (_st_note == "" || _st_note == "---") {
                    _note_byte = 0xFF;
                } else {
                    // Resolve the note name to a chromatic index. Both parsers
                    // use midi = 12*(oct+1)+base, so index = midi - 12 puts
                    // C-0 at 0 and B-7 at 95. Anything the parser rejects is
                    // warned about by name rather than silently going quiet.
                    var _st_idx = scr_sid_song_note_index(_st_note);
                    if (_st_idx < 0) {
                        show_debug_message("MACRO_SID_SONG: pattern " + string(_pi) + " row " + string(_ri)
                            + " — unrecognised note '" + _st_note + "', emitted as a rest.");
                        _note_byte = 0xFF;
                    } else {
                        _note_byte = _st_idx;
                    }
                }

                if (_st_instr >= 0 && _st_instr < _n_instr) {
                    _instr_byte = _st_instr;
                }
            }

            array_push(_list, ["byte", _note_byte  & 0xFF, _id]);
            array_push(_list, ["byte", _instr_byte & 0xFF, _id]);
            if (_pat_has_fx) {
                var _cmd_byte = 0xFF;   // $FF = no command on this row
                var _val_byte = 0x00;
                if (_ri < array_length(_pat_steps)) {
                    var _fx_row = _pat_steps[_ri];
                    if (variable_struct_exists(_fx_row, "cmd") && real(_fx_row.cmd) >= 0) {
                        _cmd_byte = real(_fx_row.cmd) & 0xFF;
                        if (variable_struct_exists(_fx_row, "cmd_val")) {
                            _val_byte = real(_fx_row.cmd_val) & 0xFF;
                        }
                    }
                }
                array_push(_list, ["byte", _cmd_byte, _id]);
                array_push(_list, ["byte", _val_byte, _id]);
            }
        }
    }

    // Export-only row dictionary. Editor patterns and their row numbers remain
    // intact; four parallel byte tables allow constant-time 6502 lookup.
    // Keep the legacy layout when the complete dictionary exceeds 256 entries
    // or when its data plus decoder would not save space.
    var _row_lookup = {}, _row_dict = [], _row_refs = [], _pr = -1;
    for (var _li = _pattern_start; _li < array_length(_list);) {
        if (_list[_li][0] == "label") {
            _pr++; array_push(_row_refs, []); _li++; continue;
        }
        var _stride = _pat_fx_flags[_pr] ? 4 : 2;
        var _row = [_list[_li][1], _list[_li+1][1], 255, 0];
        if (_stride == 4) { _row[2] = _list[_li+2][1]; _row[3] = _list[_li+3][1]; }
        var _rk = string(_row[0])+","+string(_row[1])+","+string(_row[2])+","+string(_row[3]);
        var _rid;
        if (variable_struct_exists(_row_lookup, _rk)) _rid = variable_struct_get(_row_lookup, _rk);
        else { _rid = array_length(_row_dict); variable_struct_set(_row_lookup, _rk, _rid); array_push(_row_dict, _row); }
        array_push(_row_refs[_pr], _rid);
        _li += _stride;
    }
    var _plain_pattern_bytes = array_length(_list) - _pattern_start - _n_pat;
    var _packed_pattern_bytes = array_length(_row_dict) * 4;
    for (var _pi=0;_pi<_n_pat;_pi++) _packed_pattern_bytes += array_length(_row_refs[_pi]);
    var _compact_patterns = array_length(_row_dict) <= 256 && _plain_pattern_bytes - _packed_pattern_bytes > 128;
    if (_compact_patterns) {
        array_resize(_list, _pattern_start);
        for (var _pi=0;_pi<_n_pat;_pi++) {
            array_push(_list, ["label", _key+"pat"+string(_pi)]);
            for (var _ri=0;_ri<array_length(_row_refs[_pi]);_ri++) array_push(_list,["byte",_row_refs[_pi][_ri],_id]);
        }
        var _cols = ["rownote","rowins","rowcmd","rowval"];
        for (var _col=0;_col<4;_col++) {
            array_push(_list,["label",_key+_cols[_col]]);
            for (var _ri=0;_ri<array_length(_row_dict);_ri++) array_push(_list,["byte",_row_dict[_ri][_col],_id]);
        }
        array_push(_list,["label",_key+"rins"],["byte",255,_id]);
    }

    // ── 4. PATTERN POINTER + LENGTH TABLES ──
    array_push(_list, ["label", _key + "patlo"]);
    for (var _pi = 0; _pi < _n_pat; _pi++) {
            array_push(_list, ["byte_lab_lo", _key + "pat" + string(_pi), _id]);
        }
    array_push(_list, ["label", _key + "pathi"]);
    for (var _pi = 0; _pi < _n_pat; _pi++) {
            array_push(_list, ["byte_lab_hi", _key + "pat" + string(_pi), _id]);
        }
    array_push(_list, ["label", _key + "patlen"]);
    for (var _pi = 0; _pi < _n_pat; _pi++) {
        var _pl = 64;
        if (variable_struct_exists(_patterns[_pi], "pattern_len")) {
            _pl = clamp(real(_patterns[_pi].pattern_len), 1, 255);
        }
        array_push(_list, ["byte", _pl & 0xFF, _id]);
    }
    array_push(_list, ["label", _key + "patfx"]);
    for (var _pi = 0; _pi < _n_pat; _pi++) {
        var _pfx = 0;
        if (_pat_fx_flags[_pi]) {
            _pfx = 1;
        }
        array_push(_list, ["byte", _pfx, _id]);
    }

    // ── 5. ORDER TABLES ──
    // repeat_short / force_len are flattened here: the runtime reads a plain
    // per-row target length and a per-row wrap flag. force_len is a HARD
    // length when set (it overrides, it is not a minimum) — matching
    // _se_row_target_len in the editor exactly.
    var _ord_v  = [[], [], []];
    var _ord_ln = [];
    var _ord_wr = [];

    for (var _oi = 0; _oi < _n_ord; _oi++) {
        var _orow  = _song_order[_oi];
        var _ovals = [-1, -1, -1];
        if (variable_struct_exists(_orow, "v1")) _ovals[0] = real(_orow.v1);
        if (variable_struct_exists(_orow, "v2")) _ovals[1] = real(_orow.v2);
        if (variable_struct_exists(_orow, "v3")) _ovals[2] = real(_orow.v3);

        var _o_target = 0;
        for (var _vi = 0; _vi < 3; _vi++) {
        if ((_voice_mask & (1 << _vi)) == 0) continue;
            var _pv = _ovals[_vi];
            if (_pv >= 0 && _pv < _n_pat) {
                array_push(_ord_v[_vi], _pv & 0xFF);
                var _pv_len = 64;
                if (variable_struct_exists(_patterns[_pv], "pattern_len")) {
                    _pv_len = clamp(real(_patterns[_pv].pattern_len), 1, 255);
                }
                if (_pv_len > _o_target) {
                    _o_target = _pv_len;
                }
            } else {
                array_push(_ord_v[_vi], 0xFF);
            }
        }

        var _o_force = 0;
        if (variable_struct_exists(_orow, "force_len")) {
            _o_force = real(_orow.force_len);
        }
        if (_o_force > 0) {
            _o_target = _o_force;
        }
        if (_o_target <= 0) {
            _o_target = 64;
        }
        array_push(_ord_ln, clamp(_o_target, 1, 255) & 0xFF);

        var _o_wrap = 0;
        if (variable_struct_exists(_orow, "repeat_short")) {
            if (_orow.repeat_short == true) {
                _o_wrap = 1;
            }
        }
        array_push(_ord_wr, _o_wrap);
    }

    var _ord_lbls = [_key + "ordv1", _key + "ordv2", _key + "ordv3"];
    for (var _vi = 0; _vi < 3; _vi++) {
        if ((_voice_mask & (1 << _vi)) == 0) continue;
        array_push(_list, ["label", _ord_lbls[_vi]]);
        for (var _oi = 0; _oi < _n_ord; _oi++) {
            array_push(_list, ["byte", _ord_v[_vi][_oi], _id]);
        }
    }
    array_push(_list, ["label", _key + "ordlen"]);
    for (var _oi = 0; _oi < _n_ord; _oi++) {
        array_push(_list, ["byte", _ord_ln[_oi], _id]);
    }
    array_push(_list, ["label", _key + "ordwrap"]);
    for (var _oi = 0; _oi < _n_ord; _oi++) {
        array_push(_list, ["byte", _ord_wr[_oi], _id]);
    }

    // ── 6. PER-SONG HEADER TABLES ──
    // Indexed by song number. init/seek copy the three relevant bytes into ZP
    // once, so the row-advance path costs the same as it did single-song.
    array_push(_list, ["label", _key + "songend"]);
    for (var _sgi2 = 0; _sgi2 < _n_songs; _sgi2++) {
        array_push(_list, ["byte", _song_end[_sgi2], _id]);
    }
    array_push(_list, ["label", _key + "songloop"]);
    for (var _sgi2 = 0; _sgi2 < _n_songs; _sgi2++) {
        array_push(_list, ["byte", _song_lp[_sgi2], _id]);
    }
    array_push(_list, ["label", _key + "songflag"]);
    for (var _sgi2 = 0; _sgi2 < _n_songs; _sgi2++) {
        array_push(_list, ["byte", _song_fl[_sgi2], _id]);
    }
    array_push(_list, ["label", _key + "songstart"]);
    for (var _sgi2 = 0; _sgi2 < _n_songs; _sgi2++) {
        array_push(_list, ["byte", _song_start[_sgi2], _id]);
    }

    // ── 7. EFFECT STATE (RAM, not ZP) ── 3 bytes per table, one per voice.
    // Every table is also labelled per voice (<table>_0/_1/_2) so the unrolled
    // per-voice code can address its own byte directly, while the shared
    // command/effect routines index the same table with X = voice.
    // The whole block is cleared by init/seek.
    array_push(_list, ["label", _key + "st"]);
    for (var _sti = 0; _sti < array_length(_sng_state_tables); _sti++) {
        array_push(_list, ["label", _key + _sng_state_tables[_sti]]);
        for (var _stv = 0; _stv < 3; _stv++) {
            array_push(_list, ["label", _key + _sng_state_tables[_sti] + "_" + string(_stv)]);
            array_push(_list, ["byte", 0, _id]);
        }
    }
    // Shared scratch: the row's command/value, vibrato speed/depth in use,
    // the HR-waiting flag handed to the effect routine, and the live tempo.
    // ... plus the filter shadows ($D415-$D418 can't be read back): cutoff as an
    // 11-bit value (fcl/fch), $D417 and $D418 copies, and a work byte.
    var _sng_scratch = ["rcmd", "rval", "vts", "vtd", "hrw", "spd", "fcl", "fch", "f17", "f18", "ftmp"];
    for (var _sci = 0; _sci < array_length(_sng_scratch); _sci++) {
        array_push(_list, ["label", _key + _sng_scratch[_sci]]);
        array_push(_list, ["byte", 0, _id]);
    }

    if (_sfx) {
        // Sound-effect state, GoatTracker-style: per voice a frame counter
        // (0 = no effect), and the effect data pointer. Laid out at a stride of
        // 7 so X = voice * 7 (the caller's channel offset) indexes it.
        array_push(_list, ["label", _key + "sfxc"]);
        array_push(_list, ["byte", 0, _id]);
        array_push(_list, ["label", _key + "sfxl"]);
        array_push(_list, ["byte", 0, _id]);
        array_push(_list, ["label", _key + "sfxh"]);
        for (var _sfb = 0; _sfb < 15; _sfb++) {
            array_push(_list, ["byte", 0, _id]);
        }
    }

    array_push(_list, ["label", _lbl_dskip]);

    // ════════════════════════════════════════════════════════════════
    // RUNTIME — <key>_init and <key>_play, both RTS.
    // Jumped over so nothing runs by falling through.
    // ════════════════════════════════════════════════════════════════
    var _L_skip   = _key + "rtskip";
    var _L_init   = _key + "init";
    var _L_seek   = _key + "seek";
    var _L_play   = _key + "play";
    var _L_rowadv = _key + "rowadv";
    var _L_instrs = _key + "instrs";

    array_push(_list, ["jmp_abs", _L_skip, _id]);

    // ── INIT ── A = song index (clamped), X ignored.
    // Banks BASIC out, sets full volume, then falls into SEEK with X = 0 so
    // the song starts at its own first order row.
    array_push(_list, ["label",   _L_init]);
    // Bank BASIC out, KERNAL stays in ($0314/$0315 IRQ chaining still works).
    // This is what frees $03-$8F for the player's state.
    array_push(_list, ["pha",     0,      _id]);
    array_push(_list, ["lda_imm", 0x36,   _id]);
    array_push(_list, ["sta_zp",  0x01,   _id]);
    if (_sng_filt_used) {
        // Song filter settings: mode + full volume, resonance (no voice routed
        // until an instrument with FILTER ON plays), cutoff.
        array_push(_list, ["lda_imm", ((_sng_filt_mode << 4) | 0x0F) & 0xFF, _id]);
        array_push(_list, ["sta_abs", _chip_base + 0x18, _id]);
        array_push(_list, ["sta_abs", _key + "f18", _id]);
        array_push(_list, ["lda_imm", (_sng_filt_res << 4) & 0xF0, _id]);
        array_push(_list, ["sta_abs", _chip_base + 0x17, _id]);
        array_push(_list, ["sta_abs", _key + "f17", _id]);
        array_push(_list, ["lda_imm", _sng_filt_cut & 0xFF, _id]);
        array_push(_list, ["sta_abs", _key + "fcl", _id]);
        array_push(_list, ["lda_imm", (_sng_filt_cut >> 8) & 0x07, _id]);
        array_push(_list, ["sta_abs", _key + "fch", _id]);
        array_push(_list, ["jsr",     _key + "fcut", _id]);
    } else {
        array_push(_list, ["lda_imm", 0x0F,   _id]);
        array_push(_list, ["sta_abs", _chip_base + 0x18, _id]);   // full volume, filter off
        array_push(_list, ["sta_abs", _key + "f18", _id]);        // DXX keeps this copy
    }
    array_push(_list, ["pla",     0,      _id]);
    array_push(_list, ["ldx_imm", 0x00,   _id]);   // start at the song's first row
    array_push(_list, ["jmp_abs", _L_seek, _id]);

    // ── SEEK ── A = song index, X = order row WITHIN that song (0 = start).
    // Does not touch $01 or $D418, so it's safe to call mid-tune from any
    // banking configuration the project has since set up.
    //
    // Voices are silenced and their instrument state cleared on every seek:
    // without it you drop into the new position with whatever was ringing
    // still ringing and each voice part-way through its old instrument —
    // the same class of stale-state bug as the loop-wrap fix.
    array_push(_list, ["label",   _L_seek]);

    // Clamp the song index. An out-of-range song would index past the header
    // tables into whatever data follows and set _S_END to garbage.
    array_push(_list, ["cmp_imm", _n_songs & 0xFF, _id]);
    array_push(_list, ["bcc",     _key + "skok",   _id]);
    array_push(_list, ["lda_imm", 0x00,            _id]);
    array_push(_list, ["label",   _key + "skok"]);
    array_push(_list, ["sta_zp",  _S_SONG, _id]);
    array_push(_list, ["stx_zp",  _S_TMP,  _id]);   // stash the requested row

    // Resolve this song's slice into ZP.
    array_push(_list, ["tax",     0,       _id]);   // X = song index
    array_push(_list, ["lda_abx", _key + "songend",  _id]);
    array_push(_list, ["sta_zp",  _S_END,  _id]);
    array_push(_list, ["lda_abx", _key + "songloop", _id]);
    array_push(_list, ["sta_zp",  _S_LOOP, _id]);
    array_push(_list, ["lda_abx", _key + "songflag", _id]);
    array_push(_list, ["sta_zp",  _S_FLAG, _id]);

    // Absolute order row = this song's start + the requested offset, clamped
    // to the song's own last row so a bad offset can't run into the next song.
    array_push(_list, ["lda_abx", _key + "songstart", _id]);
    array_push(_list, ["clc",     0,       _id]);
    array_push(_list, ["adc_zp",  _S_TMP,  _id]);
    array_push(_list, ["cmp_zp",  _S_END,  _id]);
    array_push(_list, ["bcc",     _key + "skrow",    _id]);
    array_push(_list, ["lda_zp",  _S_END,  _id]);
    array_push(_list, ["sec",     0,       _id]);
    array_push(_list, ["sbc_imm", 0x01,    _id]);
    array_push(_list, ["label",   _key + "skrow"]);
    array_push(_list, ["sta_zp",  _S_ORD,  _id]);

    array_push(_list, ["lda_imm", 0x00,    _id]);
    array_push(_list, ["sta_zp",  _S_ROW,  _id]);
    array_push(_list, ["lda_imm", 0x01,    _id]);
    array_push(_list, ["sta_zp",  _S_TICK, _id]);   // 1 = the next play call lands on the row
    for (var _vi = 0; _vi < 3; _vi++) {
        if ((_voice_mask & (1 << _vi)) == 0) continue;
        var _vb = _v_base[_vi];
        array_push(_list, ["lda_imm", 0x00,    _id]);
        array_push(_list, ["sta_zp",  _vb + 4, _id]);   // hold = 0
        array_push(_list, ["sta_zp",  _vb + 6, _id]);   // inactive
        array_push(_list, ["sta_abs", _chip_base + 0x04 + (_vi * 7), _id]);   // silence: gate off, no waveform
        // A seek mid-countdown would otherwise fire the old song's pending
        // note N frames into the new position.
        array_push(_list, ["sta_zp",  _h_base[_vi] + 2, _id]);   // countdown = idle
        array_push(_list, ["sta_zp",  _c_base[_vi],     _id]);   // shadow matches the register
    }
    // Clear every voice's effect state and restore the asset's tempo (an FXX
    // command changes it at runtime).
    array_push(_list, ["ldx_imm", (array_length(_sng_state_tables) * 3) - 1, _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["label",   _key + "stclr"]);
    array_push(_list, ["sta_abx", _key + "st", _id]);
    array_push(_list, ["dex",     0, _id]);
    array_push(_list, ["bpl",     _key + "stclr", _id]);
    array_push(_list, ["lda_imm", _play_speed & 0xFF, _id]);
    array_push(_list, ["sta_abs", _key + "spd", _id]);
    if (_sfx) {
        array_push(_list, ["lda_imm", 0x00, _id]);
        for (var _sfv = 0; _sfv < 3; _sfv++) {
            array_push(_list, ["ldx_imm", _sfv * 7, _id]);
            array_push(_list, ["sta_abx", _key + "sfxc", _id]);
        }
    }
    array_push(_list, ["rts",     0,      _id]);

    // ── PLAY ──
    array_push(_list, ["label",   _L_play]);
    array_push(_list, ["dec_zp",  _S_TICK,   _id]);
    array_push(_list, ["beq",     _L_rowadv, _id]);
    array_push(_list, ["jmp_abs", _L_instrs, _id]);

    array_push(_list, ["label",   _L_rowadv]);
    array_push(_list, ["lda_abs", _key + "spd", _id]);   // live tempo (FXX)
    array_push(_list, ["sta_zp",  _S_TICK, _id]);

    // Trigger each voice's row. Unrolled per voice — three copies beats the
    // ZP juggling a shared subroutine would need to index a voice's block.
    for (var _vi = 0; _vi < 3; _vi++) {
        if ((_voice_mask & (1 << _vi)) == 0) continue;
        var _vb      = _v_base[_vi];
        var _hb      = _h_base[_vi];
        var _cb      = _c_base[_vi];
        var _vp      = _key + "v" + string(_vi) + "_";
        var _L_vskip = _vp + "skip";
        var _D400    = _chip_base + (_vi * 7);

        if (_sfx) {
            // An effect owns this voice: the music's row is dropped.
            array_push(_list, ["ldx_imm", _vi * 7,          _id]);
            array_push(_list, ["lda_abx", _key + "sfxc",    _id]);
            array_push(_list, ["beq",     _vp + "nosfx",    _id]);
            array_push(_list, ["jmp_abs", _L_vskip,         _id]);
            array_push(_list, ["label",   _vp + "nosfx"]);
        }

        // No command unless this row's pattern carries one.
        array_push(_list, ["lda_imm", 0xFF,           _id]);
        array_push(_list, ["sta_abs", _key + "rcmd",  _id]);

        // X = this voice's pattern index for the current order row.
        array_push(_list, ["ldx_zp",  _S_ORD,         _id]);
        array_push(_list, ["lda_abx", _ord_lbls[_vi], _id]);
        array_push(_list, ["cmp_imm", 0xFF,           _id]);
        array_push(_list, ["bne",     _vp + "havepat", _id]);
        array_push(_list, ["jmp_abs", _L_vskip,       _id]);   // no pattern this voice
        array_push(_list, ["label",   _vp + "havepat"]);
        array_push(_list, ["tax",     0,              _id]);   // X = pattern idx

        // Local row: master row, wrapped or stopped by this order row's flag.
        // Patterns are short, so a repeated subtract beats a divide.
        //
        // NOTE: the assembler resolves label operands for lda_abx but NOT for
        // cmp_abx / sbc_abx, so this pattern's length is fetched once with
        // lda_abx into a ZP scratch byte and every compare/subtract works
        // against that copy. X is preserved throughout (it holds the pattern
        // index and nothing here reloads it).
        array_push(_list, ["lda_abx", _key + "patlen", _id]);
        array_push(_list, ["sta_zp",  _S_LEN,          _id]);   // $S_LEN = this pattern's length

        array_push(_list, ["lda_zp",  _S_ROW,          _id]);
        array_push(_list, ["cmp_zp",  _S_LEN,          _id]);
        array_push(_list, ["bcc",     _vp + "rowok",   _id]);   // row < len, use as-is
        array_push(_list, ["ldy_zp",  _S_ORD,          _id]);
        array_push(_list, ["sta_zp",  _S_TMP,          _id]);
        array_push(_list, ["lda_aby", _key + "ordwrap", _id]);
        array_push(_list, ["bne",     _vp + "dowrap",  _id]);
        array_push(_list, ["jmp_abs", _L_vskip,        _id]);   // NRs: silent past its own end
        array_push(_list, ["label",   _vp + "dowrap"]);
        array_push(_list, ["lda_zp",  _S_TMP,          _id]);
        array_push(_list, ["label",   _vp + "wraplp"]);
        array_push(_list, ["sec",     0,               _id]);
        array_push(_list, ["sbc_zp",  _S_LEN,          _id]);
        array_push(_list, ["cmp_zp",  _S_LEN,          _id]);
        array_push(_list, ["bcs",     _vp + "wraplp",  _id]);
        array_push(_list, ["label",   _vp + "rowok"]);
        array_push(_list, ["sta_zp",  _S_TMP,          _id]);   // $S_TMP = local row

        if (_compact_patterns) {
            array_push(_list,["lda_abx",_key+"patlo",_id],["sta_zp",_S_PTR,_id]);
            array_push(_list,["lda_abx",_key+"pathi",_id],["sta_zp",_S_PTR+1,_id]);
            array_push(_list,["ldy_zp",_S_TMP,_id],["lda_izy",_S_PTR,_id],["tax",0,_id]);
            array_push(_list,["lda_abx",_key+"rowins",_id],["sta_abs",_key+"rins",_id]);
            array_push(_list,["lda_abx",_key+"rowcmd",_id],["sta_abs",_key+"rcmd",_id]);
            array_push(_list,["lda_abx",_key+"rowval",_id],["sta_abs",_key+"rval",_id]);
            array_push(_list,["lda_abx",_key+"rownote",_id]);
        } else {
        // Row pointer = pattern base + local_row * 2.
        array_push(_list, ["lda_abx", _key + "patlo", _id]);
        array_push(_list, ["sta_zp",  _S_PTR,         _id]);
        array_push(_list, ["lda_abx", _key + "pathi", _id]);
        array_push(_list, ["sta_zp",  _S_PTR + 1,     _id]);
        // Row stride: 2 bytes, or 4 for a pattern with a command column.
        // row*4 can pass 255, so its top two bits go into the pointer's high byte.
        array_push(_list, ["lda_abx", _key + "patfx", _id]);
        array_push(_list, ["beq",     _vp + "str2",   _id]);
        array_push(_list, ["lda_zp",  _S_TMP,         _id]);
        array_push(_list, ["lsr_a",   0,              _id]);
        array_push(_list, ["lsr_a",   0,              _id]);
        array_push(_list, ["lsr_a",   0,              _id]);
        array_push(_list, ["lsr_a",   0,              _id]);
        array_push(_list, ["lsr_a",   0,              _id]);
        array_push(_list, ["lsr_a",   0,              _id]);
        array_push(_list, ["clc",     0,              _id]);
        array_push(_list, ["adc_zp",  _S_PTR + 1,     _id]);
        array_push(_list, ["sta_zp",  _S_PTR + 1,     _id]);
        array_push(_list, ["lda_zp",  _S_TMP,         _id]);
        array_push(_list, ["asl_a",   0,              _id]);
        array_push(_list, ["asl_a",   0,              _id]);
        array_push(_list, ["jmp_abs", _vp + "stradd", _id]);
        array_push(_list, ["label",   _vp + "str2"]);
        array_push(_list, ["lda_zp", _S_TMP, _id]);
        array_push(_list, ["bpl", _vp + "str2low", _id]);
        array_push(_list, ["inc_zp", _S_PTR+1, _id]);
        array_push(_list, ["label", _vp + "str2low"]);
        array_push(_list, ["lda_zp",  _S_TMP,         _id]);
        array_push(_list, ["asl_a",   0,              _id]);
        array_push(_list, ["label",   _vp + "stradd"]);
        array_push(_list, ["clc",     0,              _id]);
        array_push(_list, ["adc_zp",  _S_PTR,         _id]);
        array_push(_list, ["sta_zp",  _S_PTR,         _id]);
        array_push(_list, ["lda_zp",  _S_PTR + 1,     _id]);
        array_push(_list, ["adc_imm", 0x00,           _id]);
        array_push(_list, ["sta_zp",  _S_PTR + 1,     _id]);

        // Command column (4-byte rows only). X still holds the pattern index.
        array_push(_list, ["lda_abx", _key + "patfx", _id]);
        array_push(_list, ["beq",     _vp + "nocmd",  _id]);
        array_push(_list, ["ldy_imm", 0x02,   _id]);
        array_push(_list, ["lda_izy", _S_PTR, _id]);
        array_push(_list, ["sta_abs", _key + "rcmd", _id]);
        array_push(_list, ["iny",     0,      _id]);
        array_push(_list, ["lda_izy", _S_PTR, _id]);
        array_push(_list, ["sta_abs", _key + "rval", _id]);
        array_push(_list, ["label",   _vp + "nocmd"]);

        // Note byte.
        array_push(_list, ["ldy_imm", 0x00,   _id]);
        array_push(_list, ["lda_izy", _S_PTR, _id]);

        }

        // $FE = hold — leave the voice entirely alone.
        array_push(_list, ["cmp_imm", 0xFE,            _id]);
        array_push(_list, ["bne",     _vp + "nothold", _id]);
        array_push(_list, ["jmp_abs", _vp + "docmd",   _id]);   // held note: the command still applies
        array_push(_list, ["label",   _vp + "nothold"]);

        // $FF releases the envelope while instrument modulation continues.
        // Active state 2 prevents later instrument commands reopening the gate.
        // $FD = +++ key on: gate back on from the shadow — same note, same
        // instrument position, the envelope simply re-attacks.
        array_push(_list, ["cmp_imm", 0xFD,            _id]);
        array_push(_list, ["bne",     _vp + "notkon",  _id]);
        array_push(_list, ["lda_zp", _vb + 6, _id]);
        array_push(_list, ["beq", _vp + "konidle", _id]);
        array_push(_list, ["lda_imm", 1, _id]);
        array_push(_list, ["sta_zp", _vb + 6, _id]);
        array_push(_list, ["label", _vp + "konidle"]);
        array_push(_list, ["lda_zp",  _cb,             _id]);
        array_push(_list, ["ora_imm", 0x01,            _id]);
        array_push(_list, ["sta_zp",  _cb,             _id]);
        array_push(_list, ["sta_abs", _D400 + 4,       _id]);
        array_push(_list, ["jmp_abs", _vp + "docmd",   _id]);
        array_push(_list, ["label",   _vp + "notkon"]);
        array_push(_list, ["cmp_imm", 0xFF,            _id]);
        array_push(_list, ["bne",     _vp + "isnote",  _id]);
        // Gate off from the SHADOW, not a read of $D404 — the register is
        // write-only and reads back bus noise. Waveform bits are PRESERVED so
        // the release tail still has an oscillator; only bit 0 clears.
        array_push(_list, ["lda_zp",  _cb,             _id]);
        array_push(_list, ["and_imm", 0xFE,            _id]);
        array_push(_list, ["sta_zp",  _cb,             _id]);
        array_push(_list, ["sta_abs", _D400 + 4,       _id]);
        array_push(_list, ["lda_imm", 0x00,            _id]);
        array_push(_list, ["ldy_zp", _vb + 6, _id]);
        array_push(_list, ["beq", _vp + "releaseidle", _id]);
        array_push(_list, ["ldy_imm", 2, _id]);
        array_push(_list, ["sty_zp", _vb + 6, _id]);
        array_push(_list, ["label", _vp + "releaseidle"]);
        array_push(_list, ["sta_zp",  _hb + 2,         _id]);   // cancel any pending note
        array_push(_list, ["jmp_abs", _vp + "docmd",   _id]);
        array_push(_list, ["label",   _vp + "isnote"]);

        // 3XX on a note row = slide to it: set the target, no trigger.
        array_push(_list, ["ldy_abs", _key + "rcmd",   _id]);
        array_push(_list, ["cpy_imm", 0x03,            _id]);
        array_push(_list, ["bne",     _vp + "notp",    _id]);
        array_push(_list, ["tax",     0,               _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
        array_push(_list, ["sta_abs", _key + "tgl_" + string(_vi), _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
        array_push(_list, ["sta_abs", _key + "tgh_" + string(_vi), _id]);
        array_push(_list, ["jmp_abs", _vp + "docmd",   _id]);
        array_push(_list, ["label",   _vp + "notp"]);
        // Any other new note ends the voice's continuous effect (1-4).
        array_push(_list, ["ldy_imm", 0x00,            _id]);
        array_push(_list, ["sty_abs", _key + "fx_" + string(_vi), _id]);

        // Real note: stash the base index, then read the instrument byte.
        array_push(_list, ["sta_zp",  _vb + 5, _id]);
        if (_compact_patterns) array_push(_list,["lda_abs",_key+"rins",_id]);
        else {
        array_push(_list, ["ldy_imm", 0x01,    _id]);
        array_push(_list, ["lda_izy", _S_PTR,  _id]);
        }

        if (_hr > 0) {
            // H0 is stored in the unused bit 6 of the vibrato-depth header.
            // It preserves the live envelope and fires this instrument immediately.
            array_push(_list, ["sta_zp", _hb + 1, _id]);
            array_push(_list, ["cmp_imm", 255, _id]);
            array_push(_list, ["beq", _vp + "usehr", _id]);
            array_push(_list, ["tax", 0, _id]);
            array_push(_list, ["lda_abx", _key + "inslo", _id]);
            array_push(_list, ["sta_zp", _vb, _id]);
            array_push(_list, ["lda_abx", _key + "inshi", _id]);
            array_push(_list, ["sta_zp", _vb + 1, _id]);
            array_push(_list, ["ldy_imm", 6, _id]);
            array_push(_list, ["lda_izy", _vb, _id]);
            array_push(_list, ["and_imm", 64, _id]);
            array_push(_list, ["beq", _vp + "usehr", _id]);
            array_push(_list, ["lda_imm", 0, _id]);
            array_push(_list, ["sta_zp", _hb + 2, _id]);
            array_push(_list, ["lda_zp", _hb + 1, _id]);
            array_push(_list, ["jmp_abs", _vp + "immediate", _id]);
            array_push(_list, ["label", _vp + "usehr"]);
            array_push(_list, ["lda_zp", _hb + 1, _id]);
            // ── HARD RESTART, PHASE 1 ──
            // Don't sound the note now. Stash it, gate the voice off, and load
            // the dummy ADSR so the envelope counter is driven to a known
            // state. The stepper counts down and runs the real trigger (phase
            // 2) _hr frames from now.
            //
            // Note and instrument both go to the pending bytes: the row
            // pointer will have moved on by the time phase 2 runs, so nothing
            // can be re-read from the pattern then.
            array_push(_list, ["sta_zp",  _hb + 1, _id]);   // pending instrument
            array_push(_list, ["lda_zp",  _vb + 5, _id]);
            array_push(_list, ["sta_zp",  _hb + 0, _id]);   // pending note
            array_push(_list, ["lda_imm", _hr & 0xFF, _id]);
            array_push(_list, ["sta_zp",  _hb + 2, _id]);   // start the countdown

            // Silence and park the envelope. Clearing the active flag stops
            // the stepper walking the OLD instrument through the window —
            // without it the previous note keeps modulating over the restart.
            array_push(_list, ["lda_imm", 0x00,      _id]);
            array_push(_list, ["sta_abs", _D400 + 4, _id]);   // gate off, no waveform
            array_push(_list, ["sta_zp",  _cb,       _id]);   // shadow matches
            array_push(_list, ["sta_zp",  _vb + 6,   _id]);   // instrument idle
            array_push(_list, ["lda_imm", 0x0F,      _id]);
            array_push(_list, ["sta_abs", _D400 + 5, _id]);   // dummy AD
            array_push(_list, ["lda_imm", 0x00,      _id]);
            array_push(_list, ["sta_abs", _D400 + 6, _id]);   // dummy SR
            array_push(_list, ["jmp_abs", _vp + "docmd", _id]);
        }

        {
        array_push(_list, ["label", _vp + "immediate"]);

        array_push(_list, ["cmp_imm", 0xFF,           _id]);
        array_push(_list, ["bne",     _vp + "hasins", _id]);

        // No instrument: write the frequency and gate on with a plain pulse,
        // leaving AD/SR as whatever the voice last had.
        array_push(_list, ["ldx_zp",  _vb + 5,          _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
        array_push(_list, ["sta_abs", _key + "fql_" + string(_vi),        _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
        array_push(_list, ["sta_abs", _key + "fqh_" + string(_vi),        _id]);
        array_push(_list, ["lda_imm", 0, _id]);
        array_push(_list, ["sta_abs", _key + "isl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "ish_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "ipl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "iph_" + string(_vi), _id]);
        if (_repeats_used) array_push(_list,["sta_abs",_key+"reps_"+string(_vi),_id]);

        array_push(_list, ["lda_imm", 0x41,             _id]);   // pulse + gate
        array_push(_list, ["sta_abs", _D400 + 4,        _id]);
        array_push(_list, ["sta_zp",  _cb,              _id]);
        array_push(_list, ["lda_imm", 0x00,             _id]);
        array_push(_list, ["sta_zp",  _vb + 6,          _id]);   // no instrument to step
        array_push(_list, ["sta_abs", _key + "ivs_" + string(_vi),  _id]);   // no instrument vibrato
        array_push(_list, ["sta_abs", _key + "ivp_" + string(_vi),  _id]);
        array_push(_list, ["sta_abs", _key + "vol_" + string(_vi),  _id]);
        array_push(_list, ["sta_abs", _key + "voh_" + string(_vi),  _id]);
        array_push(_list, ["jmp_abs", _vp + "docmd",    _id]);
        array_push(_list, ["label",   _vp + "hasins"]);

        // Instrument: point the voice at its blob, write AD/SR/PW, gate on.
        array_push(_list, ["tax",     0,              _id]);   // X = instrument idx
        array_push(_list, ["lda_abx", _key + "inslo", _id]);
        array_push(_list, ["sta_zp",  _vb + 0,        _id]);
        array_push(_list, ["sta_zp",  _vb + 2,        _id]);   // stream base (for $03 LOOP)
        array_push(_list, ["lda_abx", _key + "inshi", _id]);
        array_push(_list, ["sta_zp",  _vb + 1,        _id]);
        array_push(_list, ["sta_zp",  _vb + 3,        _id]);

        // Header: +0 AD, +1 SR, +2 PW lo, +3 PW hi
        // Gate on BEFORE AD/SR. Writing SR first while the envelope is in
        // release lets its rate counter run past the new attack period, and the
        // SID then waits for the 15-bit counter to wrap (~33 ms) — the ADSR bug.
        array_push(_list, ["lda_imm", 0x41,      _id]);
        array_push(_list, ["sta_abs", _D400 + 4, _id]);
        array_push(_list, ["sta_zp",  _cb,       _id]);
        array_push(_list, ["ldy_imm", 0x00,      _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _D400 + 5, _id]);
        array_push(_list, ["iny",     0,         _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _D400 + 6, _id]);
        array_push(_list, ["iny",     0,         _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _D400 + 2, _id]);
        array_push(_list, ["sta_abs", _key + "pwl_" + string(_vi), _id]);   // pulse-width shadow (8XX / 9XX)
        array_push(_list, ["iny",     0,         _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _D400 + 3, _id]);
        array_push(_list, ["sta_abs", _key + "pwh_" + string(_vi), _id]);
        // Instrument vibrato: delay, speed, depth*4; restart the vibrato cycle.
        array_push(_list, ["iny",     0,         _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _key + "ivdl_" + string(_vi), _id]);
        array_push(_list, ["iny",     0,         _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _key + "ivs_" + string(_vi), _id]);
        array_push(_list, ["iny",     0,         _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["and_imm", 0x3F,      _id]);   // bit 7 is the filter flag
        array_push(_list, ["sta_abs", _key + "ivp_" + string(_vi), _id]);
        if (_sng_filt_used) {
            // Route this voice through the filter (FILTER ON) or around it.
            var _frl = _key + "fr" + string(array_length(_list));
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["bmi",     _frl + "on", _id]);
            array_push(_list, ["lda_abs", _key + "f17", _id]);
            array_push(_list, ["and_imm", (~(1 << _vi)) & 0xFF, _id]);
            array_push(_list, ["jmp_abs", _frl + "st", _id]);
            array_push(_list, ["label",   _frl + "on"]);
            array_push(_list, ["lda_abs", _key + "f17", _id]);
            array_push(_list, ["ora_imm", (1 << _vi) & 0xFF, _id]);
            array_push(_list, ["label",   _frl + "st"]);
            array_push(_list, ["sta_abs", _key + "f17", _id]);
            array_push(_list, ["sta_abs", _chip_base + 0x17, _id]);
        }
        array_push(_list, ["lda_imm", 0xFF,      _id]);
        array_push(_list, ["sta_abs", _key + "vbc_" + string(_vi), _id]);
        array_push(_list, ["lda_imm", 0x00,      _id]);
        array_push(_list, ["sta_abs", _key + "vol_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "voh_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "vdir_" + string(_vi), _id]);

        // Frequency from the base note.
        array_push(_list, ["ldx_zp",  _vb + 5,          _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
        array_push(_list, ["sta_abs", _key + "fql_" + string(_vi),        _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
        array_push(_list, ["sta_abs", _key + "fqh_" + string(_vi),        _id]);
        array_push(_list, ["lda_imm", 0, _id]);
        array_push(_list, ["sta_abs", _key + "isl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "ish_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "ipl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "iph_" + string(_vi), _id]);
        if (_repeats_used) array_push(_list,["sta_abs",_key+"reps_"+string(_vi),_id]);


        // Walking pointer moves past the 7 header bytes; the BASE stays put,
        // because $03 LOOP targets are offsets from the start of the command
        // stream, not from the blob.
        array_push(_list, ["clc",     0,       _id]);
        array_push(_list, ["lda_zp",  _vb + 0, _id]);
        array_push(_list, ["adc_imm", 0x07,    _id]);
        array_push(_list, ["sta_zp",  _vb + 0, _id]);
        array_push(_list, ["lda_zp",  _vb + 1, _id]);
        array_push(_list, ["adc_imm", 0x00,    _id]);
        array_push(_list, ["sta_zp",  _vb + 1, _id]);
        // Base points at the stream start too (blob + 7).
        array_push(_list, ["clc",     0,       _id]);
        array_push(_list, ["lda_zp",  _vb + 2, _id]);
        array_push(_list, ["adc_imm", 0x07,    _id]);
        array_push(_list, ["sta_zp",  _vb + 2, _id]);
        array_push(_list, ["lda_zp",  _vb + 3, _id]);
        array_push(_list, ["adc_imm", 0x00,    _id]);
        array_push(_list, ["sta_zp",  _vb + 3, _id]);

        // (Gate went on above, before AD/SR.) The instrument's first $00
        // overrides the default pulse waveform on this same frame.
        array_push(_list, ["lda_imm", 0x00,      _id]);
        array_push(_list, ["sta_zp",  _vb + 4,   _id]);   // hold = 0, step immediately
        array_push(_list, ["lda_imm", 0x01,      _id]);
        array_push(_list, ["sta_zp",  _vb + 6,   _id]);   // active

        }   // end if (_hr == 0) — with HR on, phase 1 above jumps to _L_vskip
            // and the whole immediate-trigger body is unreachable, so it isn't
            // emitted at all. Phase 2 in the stepper does the equivalent work.

        // ── Row command (shared routine, X = voice) ──
        array_push(_list, ["label",   _vp + "docmd"]);
        // Preserve existing pattern vibrato across blank release rows.
        array_push(_list, ["lda_zp", _vb + 6, _id]);
        array_push(_list, ["cmp_imm", 2, _id]);
        array_push(_list, ["bne", _vp + "releasecmd", _id]);
        array_push(_list, ["lda_abs", _key + "rcmd", _id]);
        array_push(_list, ["cmp_imm", 255, _id]);
        array_push(_list, ["bne", _vp + "releasecmd", _id]);
        array_push(_list, ["lda_abs", _key + "fx_" + string(_vi), _id]);
        array_push(_list, ["cmp_imm", 4, _id]);
        array_push(_list, ["beq", _L_vskip, _id]);
        array_push(_list, ["label", _vp + "releasecmd"]);
        array_push(_list, ["ldx_imm", _vi,              _id]);
        array_push(_list, ["jsr",     _key + "cmdr",    _id]);
        array_push(_list, ["label",   _L_vskip]);
    }
    // Advance the master row; roll into the next order row at the target.
    // Same label-operand restriction as the pattern length above — fetch via
    // lda_abx into scratch, then compare ZP-to-ZP.
    array_push(_list, ["inc_zp",  _S_ROW, _id]);
    array_push(_list, ["ldx_zp",  _S_ORD, _id]);
    array_push(_list, ["lda_abx", _key + "ordlen", _id]);
    array_push(_list, ["sta_zp",  _S_LEN,          _id]);
    array_push(_list, ["lda_zp",  _S_ROW,          _id]);
    array_push(_list, ["cmp_zp",  _S_LEN,          _id]);
    array_push(_list, ["bcs",     _key + "nextord", _id]);
    array_push(_list, ["jmp_abs", _L_instrs,        _id]);
    array_push(_list, ["label",   _key + "nextord"]);
    array_push(_list, ["lda_imm", 0x00,   _id]);
    array_push(_list, ["sta_zp",  _S_ROW, _id]);
    array_push(_list, ["inc_zp",  _S_ORD, _id]);
    // End-of-song is now the CURRENT song's end, held in ZP, not a compile-time
    // constant — that's the whole of what makes multi-song work at runtime.
    array_push(_list, ["lda_zp",  _S_ORD, _id]);
    array_push(_list, ["cmp_zp",  _S_END, _id]);
    array_push(_list, ["bcc",     _L_instrs, _id]);

    // Past the end. Loop or stop, per this song's flag byte.
    array_push(_list, ["lda_zp",  _S_FLAG,   _id]);
    array_push(_list, ["and_imm", 0x01,      _id]);
    array_push(_list, ["beq",     _key + "songstop", _id]);

    // LOOP — back to this song's loop row. Reset per-voice instrument state
    // on the wrap: without it each voice re-enters still stepping whatever
    // instrument it was part-way through when the pattern ended, with its own
    // leftover hold counter, so the three voices come back in at different
    // points in their streams and drift against each other. Only the second
    // and later loops are affected, which is what makes it look like a timing
    // bug rather than stale state.
    array_push(_list, ["lda_zp",  _S_LOOP, _id]);
    array_push(_list, ["sta_zp",  _S_ORD,  _id]);
    array_push(_list, ["lda_imm", 0x00,    _id]);
    for (var _vi = 0; _vi < 3; _vi++) {
        if ((_voice_mask & (1 << _vi)) == 0) continue;
        array_push(_list, ["sta_zp", _v_base[_vi] + 4, _id]);   // hold = 0
        array_push(_list, ["sta_zp", _v_base[_vi] + 6, _id]);   // inactive
        array_push(_list, ["sta_zp", _h_base[_vi] + 2, _id]);   // no pending note
        array_push(_list, ["sta_zp", _c_base[_vi],     _id]);   // shadow matches
    }
    array_push(_list, ["jmp_abs", _L_instrs, _id]);

    // STOP — park on this song's last row, silence everything, go inactive.
    array_push(_list, ["label",   _key + "songstop"]);
    array_push(_list, ["lda_zp",  _S_END, _id]);
    array_push(_list, ["sec",     0,      _id]);
    array_push(_list, ["sbc_imm", 0x01,   _id]);
    array_push(_list, ["sta_zp",  _S_ORD, _id]);
    array_push(_list, ["lda_imm", 0x00,   _id]);
    for (var _vi = 0; _vi < 3; _vi++) {
        if ((_voice_mask & (1 << _vi)) == 0) continue;
        array_push(_list, ["sta_abs", _chip_base + 0x04 + (_vi * 7), _id]);
        array_push(_list, ["sta_zp",  _v_base[_vi] + 6,   _id]);
        array_push(_list, ["sta_zp",  _h_base[_vi] + 2,   _id]);
        array_push(_list, ["sta_zp",  _c_base[_vi],       _id]);
    }

    // ── PER-FRAME INSTRUMENT STEPPING ──
    // Runs every call regardless of whether a row advanced, so D-holds are
    // measured in frames and fast arps work between rows.
    array_push(_list, ["label", _L_instrs]);

    for (var _vi = 0; _vi < 3; _vi++) {
        if ((_voice_mask & (1 << _vi)) == 0) continue;
        var _vb      = _v_base[_vi];
        var _hb      = _h_base[_vi];
        var _cb      = _c_base[_vi];
        var _ip      = _key + "i" + string(_vi) + "_";
        var _L_idone = _ip + "done";
        var _L_iloop = _ip + "loop";
        var _D400    = _chip_base + (_vi * 7);

        if (_sfx) {
            // An effect owns this voice: no music writes to it this frame.
            array_push(_list, ["ldx_imm", _vi * 7,          _id]);
            array_push(_list, ["lda_abx", _key + "sfxc",    _id]);
            array_push(_list, ["beq",     _ip + "nosfx",    _id]);
            array_push(_list, ["jmp_abs", _ip + "sfxskip",  _id]);
            array_push(_list, ["label",   _ip + "nosfx"]);
        }

        if (_hr > 0) {
            // ── HARD RESTART, PHASE 2 ──
            // Countdown running? Tick it. At zero, sound the pending note for
            // real: the envelope counter has been parked by the dummy ADSR for
            // _hr frames, so the attack starts immediately instead of waiting
            // for the counter to wrap.
            //
            // Runs BEFORE the stepper below and falls through into it, so a
            // note firing this frame gets its first instrument command on the
            // same frame — matching what the non-HR path did.
            array_push(_list, ["lda_zp",  _hb + 2,      _id]);
            array_push(_list, ["bne",     _ip + "hrgo", _id]);
            array_push(_list, ["jmp_abs", _ip + "hrno", _id]);
            array_push(_list, ["label",   _ip + "hrgo"]);
            array_push(_list, ["dec_zp",  _hb + 2,      _id]);
            array_push(_list, ["lda_zp",  _hb + 2,      _id]);
            array_push(_list, ["beq",     _ip + "hrfire", _id]);
            array_push(_list, ["jmp_abs", _L_idone,     _id]);   // still waiting, voice stays silent
            array_push(_list, ["label",   _ip + "hrfire"]);

            // Restore the base note the row asked for, then trigger.
            array_push(_list, ["lda_zp",  _hb + 0, _id]);
            array_push(_list, ["sta_zp",  _vb + 5, _id]);
            array_push(_list, ["lda_zp",  _hb + 1, _id]);
            array_push(_list, ["cmp_imm", 0xFF,           _id]);
            array_push(_list, ["bne",     _ip + "hrins",  _id]);

            // No instrument: frequency + plain pulse gate, AD/SR left as the
            // dummy values — matching the non-HR path's "whatever the voice
            // last had".
            array_push(_list, ["ldx_zp",  _vb + 5,          _id]);
            array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
            array_push(_list, ["sta_abs", _key + "fql_" + string(_vi),        _id]);
            array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
            array_push(_list, ["sta_abs", _key + "fqh_" + string(_vi),        _id]);
        array_push(_list, ["lda_imm", 0, _id]);
        array_push(_list, ["sta_abs", _key + "isl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "ish_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "ipl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "iph_" + string(_vi), _id]);
        if (_repeats_used) array_push(_list,["sta_abs",_key+"reps_"+string(_vi),_id]);

            array_push(_list, ["lda_imm", 0x41,             _id]);
            array_push(_list, ["sta_abs", _D400 + 4,        _id]);
            array_push(_list, ["sta_zp",  _cb,              _id]);
            array_push(_list, ["lda_imm", 0x00,             _id]);
            array_push(_list, ["sta_zp",  _vb + 6,          _id]);
            array_push(_list, ["sta_abs", _key + "ivs_" + string(_vi),  _id]);   // no instrument vibrato
            array_push(_list, ["sta_abs", _key + "ivp_" + string(_vi),  _id]);
            array_push(_list, ["sta_abs", _key + "vol_" + string(_vi),  _id]);
            array_push(_list, ["sta_abs", _key + "voh_" + string(_vi),  _id]);
            array_push(_list, ["jmp_abs", _L_idone,         _id]);
            array_push(_list, ["label",   _ip + "hrins"]);

            // Instrument: same sequence the row trigger uses.
            array_push(_list, ["tax",     0,              _id]);
            array_push(_list, ["lda_abx", _key + "inslo", _id]);
            array_push(_list, ["sta_zp",  _vb + 0,        _id]);
            array_push(_list, ["sta_zp",  _vb + 2,        _id]);
            array_push(_list, ["lda_abx", _key + "inshi", _id]);
            array_push(_list, ["sta_zp",  _vb + 1,        _id]);
            array_push(_list, ["sta_zp",  _vb + 3,        _id]);

            // Gate on BEFORE AD/SR. Writing SR first while the envelope is in
            // release lets its rate counter run past the new attack period, and the
            // SID then waits for the 15-bit counter to wrap (~33 ms) — the ADSR bug.
            array_push(_list, ["lda_imm", 0x41,      _id]);
            array_push(_list, ["sta_abs", _D400 + 4, _id]);
            array_push(_list, ["sta_zp",  _cb,       _id]);
            array_push(_list, ["ldy_imm", 0x00,      _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _D400 + 5, _id]);   // real AD
            array_push(_list, ["iny",     0,         _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _D400 + 6, _id]);   // real SR
            array_push(_list, ["iny",     0,         _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _D400 + 2, _id]);
            array_push(_list, ["sta_abs", _key + "pwl_" + string(_vi), _id]);   // pulse-width shadow (8XX / 9XX)
            array_push(_list, ["iny",     0,         _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _D400 + 3, _id]);
            array_push(_list, ["sta_abs", _key + "pwh_" + string(_vi), _id]);
            // Instrument vibrato: delay, speed, depth*4; restart the vibrato cycle.
            array_push(_list, ["iny",     0,         _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _key + "ivdl_" + string(_vi), _id]);
            array_push(_list, ["iny",     0,         _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _key + "ivs_" + string(_vi), _id]);
            array_push(_list, ["iny",     0,         _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["and_imm", 0x3F,      _id]);   // bit 7 is the filter flag
            array_push(_list, ["sta_abs", _key + "ivp_" + string(_vi), _id]);
            if (_sng_filt_used) {
                // Route this voice through the filter (FILTER ON) or around it.
                var _frl = _key + "fr" + string(array_length(_list));
                array_push(_list, ["lda_izy", _vb + 0,   _id]);
                array_push(_list, ["bmi",     _frl + "on", _id]);
                array_push(_list, ["lda_abs", _key + "f17", _id]);
                array_push(_list, ["and_imm", (~(1 << _vi)) & 0xFF, _id]);
                array_push(_list, ["jmp_abs", _frl + "st", _id]);
                array_push(_list, ["label",   _frl + "on"]);
                array_push(_list, ["lda_abs", _key + "f17", _id]);
                array_push(_list, ["ora_imm", (1 << _vi) & 0xFF, _id]);
                array_push(_list, ["label",   _frl + "st"]);
                array_push(_list, ["sta_abs", _key + "f17", _id]);
                array_push(_list, ["sta_abs", _chip_base + 0x17, _id]);
            }
            array_push(_list, ["lda_imm", 0xFF,      _id]);
            array_push(_list, ["sta_abs", _key + "vbc_" + string(_vi), _id]);
            array_push(_list, ["lda_imm", 0x00,      _id]);
            array_push(_list, ["sta_abs", _key + "vol_" + string(_vi), _id]);
            array_push(_list, ["sta_abs", _key + "voh_" + string(_vi), _id]);
            array_push(_list, ["sta_abs", _key + "vdir_" + string(_vi), _id]);

            array_push(_list, ["ldx_zp",  _vb + 5,          _id]);
            array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
            array_push(_list, ["sta_abs", _key + "fql_" + string(_vi),        _id]);
            array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
            array_push(_list, ["sta_abs", _key + "fqh_" + string(_vi),        _id]);
        array_push(_list, ["lda_imm", 0, _id]);
        array_push(_list, ["sta_abs", _key + "isl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "ish_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "ipl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "iph_" + string(_vi), _id]);
        if (_repeats_used) array_push(_list,["sta_abs",_key+"reps_"+string(_vi),_id]);


            array_push(_list, ["clc",     0,       _id]);
            array_push(_list, ["lda_zp",  _vb + 0, _id]);
            array_push(_list, ["adc_imm", 0x07,    _id]);
            array_push(_list, ["sta_zp",  _vb + 0, _id]);
            array_push(_list, ["lda_zp",  _vb + 1, _id]);
            array_push(_list, ["adc_imm", 0x00,    _id]);
            array_push(_list, ["sta_zp",  _vb + 1, _id]);
            array_push(_list, ["clc",     0,       _id]);
            array_push(_list, ["lda_zp",  _vb + 2, _id]);
            array_push(_list, ["adc_imm", 0x07,    _id]);
            array_push(_list, ["sta_zp",  _vb + 2, _id]);
            array_push(_list, ["lda_zp",  _vb + 3, _id]);
            array_push(_list, ["adc_imm", 0x00,    _id]);
            array_push(_list, ["sta_zp",  _vb + 3, _id]);

            array_push(_list, ["lda_imm", 0x00,      _id]);
            array_push(_list, ["sta_zp",  _vb + 4,   _id]);   // hold = 0
            array_push(_list, ["lda_imm", 0x01,      _id]);
            array_push(_list, ["sta_zp",  _vb + 6,   _id]);   // active
            // Falls through into the stepper below.
            array_push(_list, ["label",   _ip + "hrno"]);
        }

        if (_sng_extended_fx) {
        array_push(_list, ["lda_abs", _key + "pcmd_" + string(_vi), _id]);
        array_push(_list, ["cmp_imm", 16, _id]);
        array_push(_list, ["bcc", _ip + "extdone", _id]);
        array_push(_list, ["cmp_imm", 19, _id]);
        array_push(_list, ["bcs", _ip + "extdone", _id]);
        array_push(_list, ["lda_abs", _key + "pval_" + string(_vi), _id]);
        array_push(_list, ["cmp_imm", 128, _id]);
        array_push(_list, ["lda_imm", 0, _id]);
        array_push(_list, ["bcc", _ip + "extsign", _id]);
        array_push(_list, ["lda_imm", 255, _id]);
        array_push(_list, ["label", _ip + "extsign", _id]);
        array_push(_list, ["sta_zp", _S_TMP, _id]);
        array_push(_list, ["lda_abs", _key + "pcmd_" + string(_vi), _id]);
        array_push(_list, ["cmp_imm", 16, _id]);
        array_push(_list, ["bne", _ip + "extsweep", _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["lda_abs", _key + "fql_" + string(_vi), _id]);
        array_push(_list, ["adc_abs", _key + "pval_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "fql_" + string(_vi), _id]);
        array_push(_list, ["lda_abs", _key + "fqh_" + string(_vi), _id]);
        array_push(_list, ["adc_zp", _S_TMP, _id]);
        array_push(_list, ["sta_abs", _key + "fqh_" + string(_vi), _id]);
        array_push(_list, ["jmp_abs", _ip + "extclear", _id]);
        array_push(_list, ["label", _ip + "extsweep", _id]);
        array_push(_list, ["cmp_imm", 17, _id]);
        array_push(_list, ["bne", _ip + "extpulse", _id]);
        array_push(_list, ["lda_abs", _key + "pval_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "isl_" + string(_vi), _id]);
        array_push(_list, ["lda_zp", _S_TMP, _id]);
        array_push(_list, ["sta_abs", _key + "ish_" + string(_vi), _id]);
        array_push(_list, ["jmp_abs", _ip + "extclear", _id]);
        array_push(_list, ["label", _ip + "extpulse", _id]);
        array_push(_list, ["lda_abs", _key + "pval_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "ipl_" + string(_vi), _id]);
        array_push(_list, ["lda_zp", _S_TMP, _id]);
        array_push(_list, ["sta_abs", _key + "iph_" + string(_vi), _id]);
        array_push(_list, ["label", _ip + "extclear", _id]);
        array_push(_list, ["lda_imm", 0, _id]);
        array_push(_list, ["sta_abs", _key + "pcmd_" + string(_vi), _id]);
        array_push(_list, ["label", _ip + "extdone", _id]);
        }

        // Skip if this voice has no live instrument.
        array_push(_list, ["lda_zp",  _vb + 6,      _id]);
        array_push(_list, ["bne",     _ip + "live", _id]);
        array_push(_list, ["jmp_abs", _L_idone,     _id]);
        array_push(_list, ["label",   _ip + "live"]);

        // Holding? tick down and stop.
        array_push(_list, ["lda_zp",  _vb + 4,      _id]);
        array_push(_list, ["beq",     _ip + "step", _id]);
        array_push(_list, ["dec_zp",  _vb + 4,      _id]);
        array_push(_list, ["jmp_abs", _L_idone,     _id]);
        array_push(_list, ["label",   _ip + "step"]);

        // Execute commands until a HOLD parks us or the stream ends.
        array_push(_list, ["label",   _L_iloop]);
        array_push(_list, ["ldy_imm", 0x00,    _id]);
        array_push(_list, ["lda_izy", _vb + 0, _id]);

        // WAVE writes use the control shadow; a released voice stays gated off.
        array_push(_list, ["cmp_imm", 0x00,       _id]);
        array_push(_list, ["bne",     _ip + "n0", _id]);
        array_push(_list, ["ldy_imm", 0x01,       _id]);
        array_push(_list, ["lda_izy", _vb + 0,    _id]);
        array_push(_list, ["ora_imm", 0x01,       _id]);
        array_push(_list, ["ldy_zp", _vb + 6, _id]);
        array_push(_list, ["cpy_imm", 2, _id]);
        array_push(_list, ["bne", _ip + "wavegate", _id]);
        array_push(_list, ["and_imm", 254, _id]);
        array_push(_list, ["label", _ip + "wavegate"]);
        array_push(_list, ["sta_zp",  _cb,        _id]);
        array_push(_list, ["sta_abs", _D400 + 4,  _id]);
        array_push(_list, ["clc",     0,          _id]);
        array_push(_list, ["lda_zp",  _vb + 0,    _id]);
        array_push(_list, ["adc_imm", 0x02,       _id]);
        array_push(_list, ["sta_zp",  _vb + 0,    _id]);
        array_push(_list, ["lda_zp",  _vb + 1,    _id]);
        array_push(_list, ["adc_imm", 0x00,       _id]);
        array_push(_list, ["sta_zp",  _vb + 1,    _id]);
        array_push(_list, ["jmp_abs", _L_iloop,   _id]);
        array_push(_list, ["label",   _ip + "n0"]);

        // $01 = NOTE — base index + signed offset, clamped to the table.
        // The preview does base_hz * 2^(offset/12), a semitone shift; one
        // table entry per semitone makes that a single ADC here.
        array_push(_list, ["cmp_imm", 0x01,        _id]);
        array_push(_list, ["bne",     _ip + "n1",  _id]);
        array_push(_list, ["ldy_imm", 0x01,        _id]);
        array_push(_list, ["lda_izy", _vb + 0,     _id]);
        array_push(_list, ["clc",     0,           _id]);
        array_push(_list, ["adc_zp",  _vb + 5,     _id]);   // two's complement handles the sign
        array_push(_list, ["cmp_imm", 96,          _id]);
        array_push(_list, ["bcc",     _ip + "nok", _id]);
        array_push(_list, ["lda_imm", 95,          _id]);   // clamp rather than read past the table
        array_push(_list, ["label",   _ip + "nok"]);
        array_push(_list, ["tax",     0,                _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
        array_push(_list, ["sta_abs", _key + "fql_" + string(_vi),        _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
        array_push(_list, ["sta_abs", _key + "fqh_" + string(_vi),        _id]);
        array_push(_list, ["clc",     0,        _id]);
        array_push(_list, ["lda_zp",  _vb + 0,  _id]);
        array_push(_list, ["adc_imm", 0x02,     _id]);
        array_push(_list, ["sta_zp",  _vb + 0,  _id]);
        array_push(_list, ["lda_zp",  _vb + 1,  _id]);
        array_push(_list, ["adc_imm", 0x00,     _id]);
        array_push(_list, ["sta_zp",  _vb + 1,  _id]);
        array_push(_list, ["jmp_abs", _L_iloop, _id]);
        array_push(_list, ["label",   _ip + "n1"]);

        // $02 = HOLD — park for n frames. n-1, because this frame counts.
        array_push(_list, ["cmp_imm", 0x02,       _id]);
        array_push(_list, ["bne",     _ip + "n2", _id]);
        array_push(_list, ["ldy_imm", 0x01,       _id]);
        array_push(_list, ["lda_izy", _vb + 0,    _id]);
        array_push(_list, ["sec",     0,          _id]);
        array_push(_list, ["sbc_imm", 0x01,       _id]);
        array_push(_list, ["sta_zp",  _vb + 4,    _id]);
        array_push(_list, ["clc",     0,          _id]);
        array_push(_list, ["lda_zp",  _vb + 0,    _id]);
        array_push(_list, ["adc_imm", 0x02,       _id]);
        array_push(_list, ["sta_zp",  _vb + 0,    _id]);
        array_push(_list, ["lda_zp",  _vb + 1,    _id]);
        array_push(_list, ["adc_imm", 0x00,       _id]);
        array_push(_list, ["sta_zp",  _vb + 1,    _id]);
        array_push(_list, ["jmp_abs", _L_idone,   _id]);
        array_push(_list, ["label",   _ip + "n2"]);

        // $03 = LOOP — the argument is an absolute byte offset from the START
        // of the command stream, so it's added to the stored BASE, not to the
        // walking pointer (which is by now somewhere in the middle).
        array_push(_list, ["cmp_imm", 0x03,       _id]);
        array_push(_list, ["bne",     _ip + "n3", _id]);
        array_push(_list, ["ldy_imm", 0x01,       _id]);
        array_push(_list, ["lda_izy", _vb + 0,    _id]);
        array_push(_list, ["clc",     0,          _id]);
        array_push(_list, ["adc_zp",  _vb + 2,    _id]);
        array_push(_list, ["sta_zp",  _vb + 0,    _id]);
        array_push(_list, ["lda_zp",  _vb + 3,    _id]);
        array_push(_list, ["adc_imm", 0x00,       _id]);
        array_push(_list, ["sta_zp",  _vb + 1,    _id]);
        array_push(_list, ["jmp_abs", _L_iloop,   _id]);
        array_push(_list, ["label",   _ip + "n3"]);

        array_push(_list, ["cmp_imm", 5, _id]);
        array_push(_list, ["bne", _ip + "n5", _id]);
        array_push(_list,["label",_ip+"widejump"]);
        array_push(_list, ["ldy_imm", 2, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["sta_zp", _S_TMP, _id]);
        array_push(_list, ["dey", 0, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["adc_zp", _vb + 2, _id]);
        array_push(_list, ["pha", 0, _id]);
        array_push(_list, ["lda_zp", _vb + 3, _id]);
        array_push(_list, ["adc_zp", _S_TMP, _id]);
        array_push(_list, ["sta_zp", _vb + 1, _id]);
        array_push(_list, ["pla", 0, _id]);
        array_push(_list, ["sta_zp", _vb, _id]);
        array_push(_list, ["jmp_abs", _L_iloop, _id]);
        array_push(_list, ["label", _ip + "n5", _id]);
        array_push(_list, ["cmp_imm", 6, _id]);
        array_push(_list, ["bne", _ip + "n6", _id]);
        array_push(_list, ["ldy_imm", 1, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["adc_abs", _key + "fql_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "fql_" + string(_vi), _id]);
        array_push(_list, ["iny", 0, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["adc_abs", _key + "fqh_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "fqh_" + string(_vi), _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["lda_zp", _vb, _id]);
        array_push(_list, ["adc_imm", 3, _id]);
        array_push(_list, ["sta_zp", _vb, _id]);
        array_push(_list, ["lda_zp", _vb + 1, _id]);
        array_push(_list, ["adc_imm", 0, _id]);
        array_push(_list, ["sta_zp", _vb + 1, _id]);
        array_push(_list, ["jmp_abs", _L_iloop, _id]);
        array_push(_list, ["label", _ip + "n6", _id]);
        array_push(_list, ["cmp_imm", 7, _id]);
        array_push(_list, ["bne", _ip + "n7", _id]);
        array_push(_list, ["ldy_imm", 1, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["sta_abs", _D400 + 2, _id]);
        array_push(_list, ["sta_abs", _key + "pwl_" + string(_vi), _id]);
        array_push(_list, ["iny", 0, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["and_imm", 15, _id]);
        array_push(_list, ["sta_abs", _D400 + 3, _id]);
        array_push(_list, ["sta_abs", _key + "pwh_" + string(_vi), _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["lda_zp", _vb, _id]);
        array_push(_list, ["adc_imm", 3, _id]);
        array_push(_list, ["sta_zp", _vb, _id]);
        array_push(_list, ["lda_zp", _vb + 1, _id]);
        array_push(_list, ["adc_imm", 0, _id]);
        array_push(_list, ["sta_zp", _vb + 1, _id]);
        array_push(_list, ["jmp_abs", _L_iloop, _id]);
        array_push(_list, ["label", _ip + "n7", _id]);
        array_push(_list, ["cmp_imm", 8, _id]);
        array_push(_list, ["bne", _ip + "n8", _id]);
        array_push(_list, ["ldy_imm", 1, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["sta_abs", _key + "isl_" + string(_vi), _id]);
        array_push(_list, ["iny", 0, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["sta_abs", _key + "ish_" + string(_vi), _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["lda_zp", _vb, _id]);
        array_push(_list, ["adc_imm", 3, _id]);
        array_push(_list, ["sta_zp", _vb, _id]);
        array_push(_list, ["lda_zp", _vb + 1, _id]);
        array_push(_list, ["adc_imm", 0, _id]);
        array_push(_list, ["sta_zp", _vb + 1, _id]);
        array_push(_list, ["jmp_abs", _L_iloop, _id]);
        array_push(_list, ["label", _ip + "n8", _id]);
        array_push(_list, ["cmp_imm", 9, _id]);
        array_push(_list, ["bne", _ip + "n9", _id]);
        array_push(_list, ["ldy_imm", 1, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["sta_abs", _key + "ipl_" + string(_vi), _id]);
        array_push(_list, ["iny", 0, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["sta_abs", _key + "iph_" + string(_vi), _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["lda_zp", _vb, _id]);
        array_push(_list, ["adc_imm", 3, _id]);
        array_push(_list, ["sta_zp", _vb, _id]);
        array_push(_list, ["lda_zp", _vb + 1, _id]);
        array_push(_list, ["adc_imm", 0, _id]);
        array_push(_list, ["sta_zp", _vb + 1, _id]);
        array_push(_list, ["jmp_abs", _L_iloop, _id]);
        array_push(_list, ["label", _ip + "n9", _id]);
        array_push(_list, ["cmp_imm", 10, _id]);
        array_push(_list, ["bne", _ip + "n10", _id]);
        array_push(_list, ["ldy_imm", 1, _id]);
        array_push(_list, ["lda_izy", _vb, _id]);
        array_push(_list, ["ldy_zp", _vb + 6, _id]);
        array_push(_list, ["cpy_imm", 2, _id]);
        array_push(_list, ["bne", _ip + "rawgate", _id]);
        array_push(_list, ["and_imm", 254, _id]);
        array_push(_list, ["label", _ip + "rawgate"]);
        array_push(_list, ["sta_zp", _cb, _id]);
        array_push(_list, ["sta_abs", _D400 + 4, _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["lda_zp", _vb, _id]);
        array_push(_list, ["adc_imm", 2, _id]);
        array_push(_list, ["sta_zp", _vb, _id]);
        array_push(_list, ["lda_zp", _vb + 1, _id]);
        array_push(_list, ["adc_imm", 0, _id]);
        array_push(_list, ["sta_zp", _vb + 1, _id]);
        array_push(_list, ["jmp_abs", _L_iloop, _id]);
        array_push(_list, ["label", _ip + "n10", _id]);

        if (_repeats_used) {
            array_push(_list,["cmp_imm",13,_id],["bne",_ip+"notrepeat",_id]);
            array_push(_list,["lda_abs",_key+"reps_"+string(_vi),_id],["bne",_ip+"repeatdec",_id]);
            array_push(_list,["ldy_imm",3,_id],["lda_izy",_vb,_id],["clc",0,_id],["adc_imm",1,_id]);
            array_push(_list,["sta_abs",_key+"reps_"+string(_vi),_id]);
            array_push(_list,["label",_ip+"repeatdec"],["dec_abs",_key+"reps_"+string(_vi),_id]);
            array_push(_list,["beq",_ip+"repeatdone",_id],["jmp_abs",_ip+"widejump",_id]);
            array_push(_list,["label",_ip+"repeatdone"],["clc",0,_id]);
            array_push(_list,["lda_zp",_vb,_id],["adc_imm",4,_id],["sta_zp",_vb,_id]);
            array_push(_list,["lda_zp",_vb+1,_id],["adc_imm",0,_id],["sta_zp",_vb+1,_id]);
            array_push(_list,["jmp_abs",_L_iloop,_id],["label",_ip+"notrepeat"]);
        }

        if (_tables_used) {
            // Shared command tables: a single return address per voice. These
            // fragments contain no branches/calls and may hold across frames.
            array_push(_list, ["cmp_imm", 11, _id]);
            array_push(_list, ["bne", _ip + "notcall", _id]);
            array_push(_list, ["clc", 0, _id]);
            array_push(_list, ["lda_zp", _vb, _id]);
            array_push(_list, ["adc_imm", 3, _id]);
            array_push(_list, ["sta_abs", _key + "trl_" + string(_vi), _id]);
            array_push(_list, ["lda_zp", _vb + 1, _id]);
            array_push(_list, ["adc_imm", 0, _id]);
            array_push(_list, ["sta_abs", _key + "trh_" + string(_vi), _id]);
            array_push(_list, ["ldy_imm", 1, _id]);
            array_push(_list, ["lda_izy", _vb, _id]);
            array_push(_list, ["sta_zp", _S_TMP, _id]);
            array_push(_list, ["iny", 0, _id]);
            array_push(_list, ["lda_izy", _vb, _id]);
            array_push(_list, ["sta_zp", _vb + 1, _id]);
            array_push(_list, ["lda_zp", _S_TMP, _id]);
            array_push(_list, ["sta_zp", _vb, _id]);
            array_push(_list, ["jmp_abs", _L_iloop, _id]);
            array_push(_list, ["label", _ip + "notcall", _id]);
            array_push(_list, ["cmp_imm", 12, _id]);
            array_push(_list, ["bne", _ip + "notreturn", _id]);
            array_push(_list, ["lda_abs", _key + "trl_" + string(_vi), _id]);
            array_push(_list, ["sta_zp", _vb, _id]);
            array_push(_list, ["lda_abs", _key + "trh_" + string(_vi), _id]);
            array_push(_list, ["sta_zp", _vb + 1, _id]);
            array_push(_list, ["jmp_abs", _L_iloop, _id]);
            array_push(_list, ["label", _ip + "notreturn", _id]);
        }

        // $04, or anything unrecognised = END — gate off, mark inactive.
        //
        // Waveform bits are PRESERVED so the release phase still has an
        // oscillator to release; only bit 0 clears. Worked from the shadow
        // because $D404 can't be read back reliably.
        array_push(_list, ["lda_zp",  _cb,       _id]);
        array_push(_list, ["and_imm", 0xFE,      _id]);
        array_push(_list, ["sta_zp",  _cb,       _id]);
        array_push(_list, ["sta_abs", _D400 + 4, _id]);
        array_push(_list, ["lda_imm", 0x00,      _id]);
        array_push(_list, ["sta_zp",  _vb + 6,   _id]);

        array_push(_list, ["label",   _L_idone]);
        array_push(_list, ["lda_zp", _vb + 6, _id]);
        array_push(_list, ["beq", _ip + "sweepdone", _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["lda_abs", _key + "fql_" + string(_vi), _id]);
        array_push(_list, ["adc_abs", _key + "isl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "fql_" + string(_vi), _id]);
        array_push(_list, ["lda_abs", _key + "fqh_" + string(_vi), _id]);
        array_push(_list, ["adc_abs", _key + "ish_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "fqh_" + string(_vi), _id]);
        array_push(_list, ["lda_abs", _key + "ipl_" + string(_vi), _id]);
        array_push(_list, ["ora_abs", _key + "iph_" + string(_vi), _id]);
        array_push(_list, ["beq", _ip + "sweepdone", _id]);
        array_push(_list, ["clc", 0, _id]);
        array_push(_list, ["lda_abs", _key + "pwl_" + string(_vi), _id]);
        array_push(_list, ["adc_abs", _key + "ipl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _key + "pwl_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _D400 + 2, _id]);
        array_push(_list, ["lda_abs", _key + "pwh_" + string(_vi), _id]);
        array_push(_list, ["adc_abs", _key + "iph_" + string(_vi), _id]);
        array_push(_list, ["and_imm", 15, _id]);
        array_push(_list, ["sta_abs", _key + "pwh_" + string(_vi), _id]);
        array_push(_list, ["sta_abs", _D400 + 3, _id]);
        array_push(_list, ["label", _ip + "sweepdone", _id]);
        // ── Per-frame effects + frequency output (shared routine) ──
        // hrw tells the routine a hard restart is still counting down, so a
        // pending 5XX/6XX/7XX waits for the note's own AD/SR/wave first.
        if (_hr > 0) {
            array_push(_list, ["lda_zp",  _hb + 2, _id]);
        } else {
            array_push(_list, ["lda_imm", 0x00, _id]);
        }
        array_push(_list, ["sta_abs", _key + "hrw", _id]);
        array_push(_list, ["ldx_imm", _vi,       _id]);
        array_push(_list, ["ldy_imm", _vi * 7,   _id]);
        array_push(_list, ["jsr",     _key + "fxr", _id]);
        if (_sfx) {
            array_push(_list, ["label",   _ip + "sfxskip"]);
        }
    }

    if (_sfx) {
        // Effects run last, so they have the final say on their voices.
        for (var _sfe = 0; _sfe < 3; _sfe++) {
            array_push(_list, ["ldx_imm", _sfe * 7, _id]);
            array_push(_list, ["jsr",     _key + "sfxx", _id]);
        }
    }
    array_push(_list, ["rts", 0, _id]);

    var _sng_use_fx = _sng_any_vib;
    for (var _ufi = 0; _ufi < array_length(_pat_fx_flags); _ufi++) {
        if (_pat_fx_flags[_ufi]) {
            _sng_use_fx = true;
        }
    }
    scr_sid_song_emit_fx_routines(_list, _id, _key, _chip_base, _c_base[0], _sng_use_fx, _sng_filt_used, _sng_extended_fx);
    if (_sfx) {
        scr_sid_song_emit_sfx(_list, _id, _key, _chip_base, _S_PTR);
    }

    array_push(_list, ["label", _L_skip]);

    // Auto-init on the spine so the node is drop-and-go. The user then JSRs
    // <key>_play once per frame from their own loop or IRQ handler.
    if (_auto_init == 1) {
        // A is undefined wherever the node happens to sit on the spine, and
        // _init takes the song index in A — so load 0 explicitly. Drop-and-go
        // always starts the first song.
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["jsr", _L_init, _id]);
    }
    return true;
}

/// Build independent chip players behind the existing init/seek/play API.
/// All players share 44 scratch ZP bytes; persistent state is saved in RAM.
function scr_music_sid_build(_list, _id, _se, _name, _auto, _zp, _hr, _base) {
    var _count = scr_music_sid_count(_se.meta);
    var _key = "sng" + string(_id.stable_uid) + "_";
    _zp = clamp(_zp, 0x03, 0x8F - 43);
    array_push(_list, ["jmp_abs", _key + "multi_end", _id]);
    for (var _c = 0; _c < _count; _c++) {
        var _ck = _key + "chip" + string(_c) + "_";
        var _start = array_length(_list);
        var _view = { meta: scr_music_sid_project(_se.meta, _c) };
        scr_sid_song_build(_list, _id, _view, _name, 0, _zp, _hr, _base + _c * 0x20, false, _ck);
        // FXX is global. Latch the old tempo once per frame so a command on
        // an earlier chip cannot make later chips reload a different tick.
        for (var _i = _start; _i < array_length(_list); _i++) {
            var _op = _list[_i];
            if (array_length(_op) > 1 && _op[1] == _ck + "spd") {
                if (_op[0] == "lda_abs") _list[_i][1] = _key + "tempo_now";
                if (_op[0] == "sta_abs") _list[_i][1] = _key + "tempo_next";
            }
        }
        array_push(_list, ["label", _ck + "saved"]);
        for (var _b = 0; _b < 44; _b++) array_push(_list, ["byte", 0, _id]);
        array_push(_list, ["label", _ck + "load"]);
        array_push(_list, ["ldx_imm", 43, _id]);
        array_push(_list, ["label", _ck + "load_loop"]);
        array_push(_list, ["lda_abx", _ck + "saved", _id]);
        array_push(_list, ["sta_abx", _zp, _id]);
        array_push(_list, ["dex", 0, _id]);
        array_push(_list, ["bpl", _ck + "load_loop", _id]);
        array_push(_list, ["rts", 0, _id]);
        array_push(_list, ["label", _ck + "save"]);
        array_push(_list, ["ldx_imm", 43, _id]);
        array_push(_list, ["label", _ck + "save_loop"]);
        array_push(_list, ["lda_abx", _zp, _id]);
        array_push(_list, ["sta_abx", _ck + "saved", _id]);
        array_push(_list, ["dex", 0, _id]);
        array_push(_list, ["bpl", _ck + "save_loop", _id]);
        array_push(_list, ["rts", 0, _id]);
    }
    array_push(_list, ["label", _key + "tempo_now"]);
    array_push(_list, ["byte", _se.meta.play_speed, _id]);
    array_push(_list, ["label", _key + "tempo_next"]);
    array_push(_list, ["byte", _se.meta.play_speed, _id]);
    array_push(_list, ["label", _key + "song_arg"]);
    array_push(_list, ["byte", 0, _id]);
    array_push(_list, ["label", _key + "row_arg"]);
    array_push(_list, ["byte", 0, _id]);
    var _entries = ["init", "seek", "play"];
    for (var _e = 0; _e < 3; _e++) {
        array_push(_list, ["label", _key + _entries[_e]]);
        if (_e < 2) {
            array_push(_list, ["sta_abs", _key + "song_arg", _id]);
            array_push(_list, ["stx_abs", _key + "row_arg", _id]);
        } else {
            array_push(_list, ["lda_abs", _key + "tempo_next", _id]);
            array_push(_list, ["sta_abs", _key + "tempo_now", _id]);
        }
        for (var _c = 0; _c < _count; _c++) {
            var _ck = _key + "chip" + string(_c) + "_";
            if (_e > 0) array_push(_list, ["jsr", _ck + "load", _id]);
            if (_e < 2) {
                array_push(_list, ["lda_abs", _key + "song_arg", _id]);
                array_push(_list, ["ldx_abs", _key + "row_arg", _id]);
            }
            array_push(_list, ["jsr", _ck + _entries[_e], _id]);
            array_push(_list, ["jsr", _ck + "save", _id]);
        }
        array_push(_list, ["rts", 0, _id]);
    }
    array_push(_list, ["label", _key + "multi_end"]);
    if (_auto == 1) {
        array_push(_list, ["lda_imm", 0, _id]);
        array_push(_list, ["jsr", _key + "init", _id]);
    }
    return true;
}
