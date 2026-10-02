/// sid64 — reSID-backed audio for the Music Maker and SFX Maker.
///
/// Two chips live in the extension ("slots"):
///   slot 0 — single-note auditions (key presses, instrument previews). Each is
///            rendered from a one-voice run of scr_sid64_sim and cached.
///   slot 1 — song / pattern playback, streamed: scr_sid64_sim runs the player
///            frame by frame and the rendered audio is fed to a GameMaker
///            play queue a few frames ahead of the speaker, so playback starts
///            at once and slides, vibrato and every cross-voice interaction are
///            heard exactly as the compiled player produces them.
///
/// global.sid64_ok is false when the extension isn't present on this platform;
/// callers then fall back to the old GML synth and row-by-row playback.

#macro SID64_PAL_CLOCK        985248
#macro SID64_RATE             44100
#macro SID64_CYCLES_PER_FRAME 19656
#macro SID64_MAX_FRAMES       300    // 6 s — hard cap on any one audition
#macro SID64_GATE_CAP         150    // 3 s — a looping instrument's gate drops here on a bare audition
#macro SID64_PLAIN_GATE       8      // no-instrument note: gate held 8 frames (0.16 s)
#macro SID64_FRAME_US         (1000000 * SID64_CYCLES_PER_FRAME / SID64_PAL_CLOCK)
#macro SID64_CHUNK_FRAMES     4      // streamed song audio is rendered 4 frames (80 ms) at a time
#macro SID64_AHEAD_FRAMES     12     // ... and kept this far ahead of what is playing
#macro SID64_RING             32     // streaming buffers, reused round-robin
#macro SID64_POS_RING         512    // frame -> song position history for the display

/// Called once from obj_workspace_manager Create, after the sid64 globals are set.
function scr_sid64_start() {
    // Shared chromatic table — same construction as SIDSONG_NOTELO/HI in
    // scr_compile_chain, so preview and compiled player use identical values.
    var _names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    for (var _i = 0; _i < 96; _i++) {
        var _f = scr_note_name_to_freq(_names[_i mod 12] + string(_i div 12));
        if (_f < 0) {
            _f = 0;
        }
        global.sid64_note_freq[_i] = _f;
    }

    global.sid64_ok = false;
    try {
        if (sid64_version() >= 2) {
            scr_sid64_init_slots();
            global.sid64_ok = true;
        } else {
            show_debug_message("sid64: extension is older than this build expects, previews use the GML synth");
        }
    } catch (_e) {
        show_debug_message("sid64: extension unavailable, previews use the GML synth (" + string(_e.message) + ")");
        global.sid64_ok = false;
    }
}

function scr_sid64_init_slots() {
    for (var _s = ((sid64_version() >= 3) ? 8 : 1); _s >= 0; _s--) {
        sid64_select(_s);
        sid64_init(SID64_PAL_CLOCK, SID64_RATE, global.sid64_model, global.sid64_engine);
        sid64_set_gain(0.6);
        sid64_set_cycles_per_frame(SID64_CYCLES_PER_FRAME);
    }
    // slot 0 stays selected: auditions are the default user
}

/// Re-initialise after changing global.sid64_model / global.sid64_engine.
/// Clears the preview cache because every cached sound was rendered with the old chip.
function scr_sid64_reconfigure() {
    if (!global.sid64_ok) {
        return;
    }
    scr_sid64_stream_stop();
    scr_sound_preview_cache_clear();
    scr_sid64_init_slots();
}

/// Cache-key prefix: anything that changes the rendered audio but isn't in the
/// instrument itself. Empty when the GML synth is in use.
function scr_sid64_key_prefix() {
    if (!global.sid64_ok) {
        return "";
    }
    return "S2R" + string(global.sid64_engine) + "M" + string(global.sid64_model)
         + "H" + string(global.sid64_hard_restart) + "|";
}

/// Reads an instrument field, or the player's default when the field is missing.
function scr_sid64_instr_field(_instr, _name, _default) {
    var _v = _instr[$ _name];
    if (is_undefined(_v)) {
        return _default;
    }
    return real(_v);
}

/// Renders one note through reSID (slot 0) by running the player simulation on
/// a single voice.
/// _instr     instrument struct, or undefined for the player's no-instrument path
/// _max_sec   cap the rendered length, or -1 for the full tail
/// _plain_pw  pulse width assumed for a no-instrument note
/// Returns { snd, buf } (caller stores it in the preview cache) or undefined.
function scr_sid64_render_note(_instr, _note_name, _max_sec, _plain_pw = 0x0800) {
    if (!global.sid64_ok) {
        return undefined;
    }
    var _base = scr_sid_song_note_index(_note_name);
    if (_base < 0) {
        return undefined;
    }
    var _has_instr = is_struct(_instr);

    var _rel = 0;
    if (_has_instr) {
        _rel = clamp(scr_sid64_instr_field(_instr, "release", 0), 0, 15);
    }
    // Release table (ms, full scale) — only used to size the tail after gate-off.
    var _rel_ms = [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000];

    var _limit = SID64_MAX_FRAMES;
    if (_max_sec > 0) {
        _limit = clamp(ceil(_max_sec * 50), 1, SID64_MAX_FRAMES);
    }

    var _sim = scr_sid64_sim_create(undefined, undefined, false, 0, 0);
    // A no-instrument note keeps whatever PW the voice had; give it a usable one.
    scr_sid64_sim_write(_sim, 2, _plain_pw & 0xFF);
    scr_sid64_sim_write(_sim, 3, (_plain_pw >> 8) & 0x0F);

    var _vc = _sim.voices[0];
    var _fb = global.sid64_frame_buf;
    var _follow = [];
    var _nf = 0;
    var _end = _limit;
    var _fired_at = -1;
    var _gate_off_at = -1;

    while (_nf < _end) {
        if (_nf == 0) {
            scr_sid64_sim_row(_sim, 0, _base, _instr, 255, 0);
        }
        scr_sid64_sim_frame(_sim);
        if (_fired_at < 0 && (_vc.cb & 0x01) == 1) {
            _fired_at = _nf;
        }

        // Bare audition: drop the gate on a plain note / a looping instrument.
        if (_max_sec <= 0 && _fired_at >= 0 && (_vc.cb & 0x01) == 1) {
            var _cap = SID64_GATE_CAP;
            if (!_has_instr) {
                _cap = SID64_PLAIN_GATE;
            }
            if (_nf - _fired_at >= _cap) {
                _vc.cb = _vc.cb & 0xFE;
                _vc.active = false;
                scr_sid64_sim_write(_sim, 4, _vc.cb);
            }
        }
        // Once the gate is off, render just the release tail.
        if (_max_sec <= 0 && _fired_at >= 0 && _gate_off_at < 0 && (_vc.cb & 0x01) == 0) {
            _gate_off_at = _nf;
            _end = min(_limit, _nf + 1 + ceil(_rel_ms[_rel] / 20) + 3);
        }

        array_push(_follow, scr_sid64_voice_display(_vc));
        scr_sid64_sim_put(_sim, _fb, _nf);
        _nf += 1;
    }

    sid64_select(0);
    sid64_reset();
    sid64_settle(0x0F, 100);

    var _cap_samples = ceil(_nf * SID64_CYCLES_PER_FRAME * SID64_RATE / SID64_PAL_CLOCK) + 64;
    var _buf = buffer_create(_cap_samples * 2, buffer_fixed, 2);
    var _got = sid64_render_log(buffer_get_address(_fb), _nf, buffer_get_address(_buf), _cap_samples);
    if (_got <= 0) {
        buffer_delete(_buf);
        return undefined;
    }
    // The DLL wrote through the raw address, so GameMaker still thinks the
    // buffer is empty — audio_create_buffer_sound refuses an "empty" buffer.
    buffer_set_used_size(_buf, _got * 2);
    var _snd = audio_create_buffer_sound(_buf, buffer_s16, SID64_RATE, 0, _got * 2, audio_mono);
    return { snd: _snd, buf: _buf, follow: _follow };
}

// ═══════════════════════════ SONG STREAMING ═══════════════════════════

/// Starts streamed playback on slot 1.
/// _loop_row true = loop order row _ord (PLAY PAT / Space), false = play the song.
function scr_sid64_stream_start(_m, _song, _loop_row, _ord, _row) {
    with (obj_asset_manager) scr_sid_asset_stop();
    scr_sid64_stream_stop();
    var _st = global.sid64_stream;
    var _count = scr_music_sid_count(_m);
    if (_count > 1 && sid64_version() < 3) {
        _m.playing = false;
        _m.song_playing = false;
        _m.warn_msg = "MULTI-SID PREVIEW NEEDS THE UPDATED SID64 EXTENSION";
        _m.warn_timer = game_get_speed(gamespeed_fps) * 5;
        return;
    }
    _st.sims = [];
    _st.shared_clock = { next: _m.play_speed };
    for (var _c = 0; _c < _count; _c++) {
        var _sim = scr_sid64_sim_create(_m, _song, _loop_row, _ord, _row);
        _sim.chip = _c;
        _sim.shared_clock = _st.shared_clock;
        array_push(_st.sims, _sim);
        sid64_select(_c + 1);
        sid64_reset();
        sid64_settle(0x0F, 100);
    }
    _st.sim = _st.sims[0];
    _st.mix_buf = -1;
    if (_count > 1) _st.mix_buf = buffer_create(_st.ring_samples * 2, buffer_fixed, 1);
    _st.logs = [];
    for (var _c = 0; _c < _count; _c++) array_push(_st.logs, buffer_create(SID64_CHUNK_FRAMES * 32, buffer_fixed, 1));
    _st.pos_instruments = array_create(SID64_POS_RING, undefined);
    _st.frames_rendered = 0;
    _st.finished_at = -1;
    _st.ring_i = 0;

    sid64_select(1);
    sid64_reset();
    sid64_settle(0x0F, 100);
    sid64_select(0);

    _st.queue = audio_create_play_queue(buffer_s16, SID64_RATE, audio_mono);
    // Prime the queue before starting it so the first buffer is already there.
    while (_st.frames_rendered < SID64_AHEAD_FRAMES) {
        scr_sid64_stream_chunk();
    }
    _st.inst = audio_play_sound(_st.queue, 1, false);
    _st.start_us = get_timer();
    _st.last_update_us = _st.start_us;
    _st.max_update_gap_us = 0;
    _st.max_render_us = 0;
    _st.underruns = 0;
    _st.active = true;
}

function scr_sid64_stream_stop() {
    var _st = global.sid64_stream;
    if (_st.inst != -1) {
        audio_stop_sound(_st.inst);
        _st.inst = -1;
    }
    if (_st.queue != -1) {
        audio_free_play_queue(_st.queue);
        _st.queue = -1;
    }
    _st.active = false;
    _st.sim = undefined;
    if (variable_struct_exists(_st, "mix_buf") && buffer_exists(_st.mix_buf)) buffer_delete(_st.mix_buf);
    _st.mix_buf = -1;
    _st.sims = [];
    if (variable_struct_exists(_st, "logs")) {
        for (var _i = 0; _i < array_length(_st.logs); _i++) {
            if (buffer_exists(_st.logs[_i])) buffer_delete(_st.logs[_i]);
        }
    }
    _st.logs = [];
}

/// Runs SID64_CHUNK_FRAMES frames of the sim, renders them and queues the audio.
function scr_sid64_stream_chunk() {
    var _st = global.sid64_stream;
    var _fb = global.sid64_frame_buf;
    var _buf = _st.ring[_st.ring_i];
    _st.ring_i = (_st.ring_i + 1) mod SID64_RING;

    var _count = array_length(_st.sims);
    // Advance ALL chips before rendering the next frame: FXX shares one clock.
    var _logs = _st.logs;
    if (_count > 1) buffer_fill(_buf, 0, buffer_s16, 0, _st.ring_samples * 2);
    for (var _i = 0; _i < SID64_CHUNK_FRAMES; _i++) {
        var _tempo = _st.shared_clock.next;
        for (var _c = 0; _c < _count; _c++) {
            _st.sims[_c].spd = _tempo;
            scr_sid64_sim_frame(_st.sims[_c]);
            scr_sid64_sim_put(_st.sims[_c], _logs[_c], _i);
        }
        var _pi = (_st.frames_rendered + _i) mod SID64_POS_RING;
        _st.pos_ord[_pi] = _st.sim.shown_ord;
        _st.pos_row[_pi] = _st.sim.shown_row;
        var _voices = [];
        for (var _dc = 0; _dc < _count; _dc++) for (var _dv = 0; _dv < 3; _dv++) {
            array_push(_voices, scr_sid64_voice_display(_st.sims[_dc].voices[_dv]));
        }
        _st.pos_instruments[_pi] = _voices;
        var _notes = [];
        for (var _nc = 0; _nc < _count; _nc++) for (var _nv = 0; _nv < 3; _nv++) {
            array_push(_notes, scr_sid64_voice_note(_st.sims[_nc], _st.sims[_nc].voices[_nv]));
        }
        _st.pos_notes[_pi] = _notes;
        var _vpos = [];
        for (var _pc = 0; _pc < _count; _pc++) for (var _pv = 0; _pv < 3; _pv++) {
            var _pvc = _st.sims[_pc].voices[_pv];
            array_push(_vpos, [_pvc.shown_ord, _pvc.shown_row]);
        }
        _st.pos_vpos[_pi] = _vpos;
        if (_st.sim.finished && _st.finished_at < 0) _st.finished_at = _st.frames_rendered + _i;
    }
    var _got = 0;
    for (var _c = 0; _c < _count; _c++) {
        sid64_select(_c + 1);
        var _samples = sid64_render_log(buffer_get_address(_logs[_c]), SID64_CHUNK_FRAMES,
                                       buffer_get_address(_count == 1 ? _buf : _st.mix_buf), _st.ring_samples);
        if (_c == 0) _got = _samples;
        else _got = min(_got, _samples);
        if (_count > 1) for (var _p = 0; _p < _samples; _p++) {
            var _sum = buffer_peek(_buf, _p * 2, buffer_s16)
                + round(buffer_peek(_st.mix_buf, _p * 2, buffer_s16) / _count);
            buffer_poke(_buf, _p * 2, buffer_s16, clamp(_sum, -32768, 32767));
        }

    }
    sid64_select(0);
    _st.frames_rendered += SID64_CHUNK_FRAMES;
    if (_got > 0) {
        buffer_set_used_size(_buf, _got * 2);
        audio_queue_sound(_st.queue, _buf, 0, _got * 2);
    }
}

/// Call every editor frame while streaming. Keeps the queue topped up and
/// reports what is sounding now in _m.preview_display_order / _step.
/// Returns false once a non-looping song has finished playing out.
function scr_sid64_stream_update(_m) {
    var _st = global.sid64_stream;
    if (!_st.active) {
        return false;
    }
    var _now = get_timer();
    _st.max_update_gap_us = max(_st.max_update_gap_us, _now - _st.last_update_us);
    _st.last_update_us = _now;
    var _played = floor((_now - _st.start_us) / SID64_FRAME_US);
    // A drained queue cannot have played frames that were never rendered.
    // Rebase BEFORE filling: do not synthesize a wall-clock backlog in Draw.
    if (_played > _st.frames_rendered) {
        _st.underruns += 1;
        if (_st.underruns == 1) {
            show_debug_message("sid64: audio queue ran dry; editor gap "
                + string(round(_st.max_update_gap_us / 1000)) + " ms, longest refill "
                + string(round(_st.max_render_us / 1000)) + " ms");
        }
        _played = _st.frames_rendered;
        _st.start_us = _now - _played * SID64_FRAME_US;
    }
    var _render_start = get_timer();
    var _guard = 0;
    var _max_chunks = ceil(SID64_AHEAD_FRAMES / SID64_CHUNK_FRAMES);
    while (_st.frames_rendered < _played + SID64_AHEAD_FRAMES && _guard < _max_chunks) {
        scr_sid64_stream_chunk();
        _guard += 1;
    }
    _st.max_render_us = max(_st.max_render_us, get_timer() - _render_start);
    var _shown = clamp(_played, 0, _st.frames_rendered - 1);
    var _pi = _shown mod SID64_POS_RING;
    _m.preview_display_order = _st.pos_ord[_pi];
    _m.preview_display_step  = _st.pos_row[_pi];

    if (_st.finished_at >= 0 && _played > _st.finished_at + 25) {
        scr_sid64_stream_stop();
        return false;
    }
    return true;
}

// Imported SID audition. Reuses the relocator's bounded 6502 interpreter and
// the installed reSID DLL; all state is transient and separate from asset data.
function scr_sid_asset_stop() {
    if (!variable_instance_exists(id, "sid_asset_preview")) return;
    var _p = sid_asset_preview;
    if (!is_struct(_p)) return;
    if (_p.inst != -1) audio_stop_sound(_p.inst);
    if (_p.queue != -1) audio_free_play_queue(_p.queue);
    for (var _i = 0; _i < array_length(_p.ring); _i++) {
        if (buffer_exists(_p.ring[_i])) buffer_delete(_p.ring[_i]);
    }
    if (buffer_exists(_p.fb)) buffer_delete(_p.fb);
    sid_asset_preview = undefined;
    // Slot 1 is shared with Music Maker. Restore its usual configuration.
    if (global.sid64_ok) {
        sid64_select(1);
        sid64_init(SID64_PAL_CLOCK, SID64_RATE, global.sid64_model, global.sid64_engine);
        sid64_set_gain(0.6);
        sid64_set_cycles_per_frame(SID64_CYCLES_PER_FRAME);
        sid64_select(0);
    }
}

function scr_sid_asset_start(_asset, _song) {
    scr_sid_asset_stop();
    sid_asset_message = "";
    sid_asset_name = _asset.name;
    sid_asset_song = _song;
    if (!global.sid64_ok) { sid_asset_message = "SID playback DLL unavailable."; return false; }
    var _b = _asset.buffer;
    if (!buffer_exists(_b) || buffer_get_size(_b) < 124) {
        sid_asset_message = "No complete SID file loaded."; return false;
    }
    // IRQ/ROM-dependent RSID and multi-SID tunes need a full C64 emulator.
    if (buffer_peek(_b, 0, buffer_u8) != 80 || buffer_peek(_b, 1, buffer_u8) != 83
    || buffer_peek(_b, 2, buffer_u8) != 73 || buffer_peek(_b, 3, buffer_u8) != 68) {
        sid_asset_message = "Preview supports PSID tunes with a PLAY routine."; return false;
    }
    var _version = buffer_peek(_b, 5, buffer_u8);
    var _hdr = (buffer_peek(_b, 6, buffer_u8) << 8) | buffer_peek(_b, 7, buffer_u8);
    if ((_hdr != 118 && _hdr != 124) || buffer_get_size(_b) < _hdr + 2
    || (_version >= 3 && (buffer_peek(_b, 122, buffer_u8) != 0 || buffer_peek(_b, 123, buffer_u8) != 0))) {
        sid_asset_message = "Unsupported SID header or multiple SID chips."; return false;
    }
    var _inf = scr_srel_sid_info(_asset);
    if (is_string(_inf)) { sid_asset_message = _inf; return false; }
    if (_inf.load + _inf.len > 65520 || _inf.load < 512) {
        sid_asset_message = "SID load range cannot be previewed."; return false;
    }
    var _flags = _version >= 2 ? (buffer_peek(_b, 118, buffer_u8) << 8) | buffer_peek(_b, 119, buffer_u8) : 0;
    if ((_flags & 3) != 0) { sid_asset_message = "MUS / PlaySID-specific tunes need an external player."; return false; }
    var _ntsc = ((_flags >> 2) & 3) == 2;
    var _clock = _ntsc ? 1022727 : SID64_PAL_CLOCK;
    var _model = ((_flags >> 4) & 3);
    _model = _model == 1 ? 0 : (_model == 2 ? 1 : global.sid64_model);
    var _emu = scr_srel_emu_new(_inf.img, _inf.load, false, -1, -1);
    _emu.x = _ntsc ? 1 : 0;
    _emu.m[1] = 0x37;
    if (scr_srel_call(_emu, _inf.init, _song, 100000) < 0) {
        sid_asset_message = "Cannot preview: " + _emu.err; return false;
    }
    var _speed = 0;
    for (var _i = 18; _i < 22; _i++) _speed = (_speed << 8) | buffer_peek(_b, _i, buffer_u8);
    var _cycles = _ntsc ? 17095 : SID64_CYCLES_PER_FRAME;
    if (((_speed >> min(_song, 31)) & 1) != 0) {
        _cycles = _emu.m[0xDC04] | (_emu.m[0xDC05] << 8);
        if (_cycles == 0) _cycles = round(_clock / 60);
    }
    if (_cycles < 1000) { sid_asset_message = "High-rate / sample tunes need an external player."; return false; }
    scr_sid64_stream_stop();
    var _cap = ceil(4 * _cycles * SID64_RATE / _clock) + 128;
    var _p = {asset:_asset, owner:ds_list_find_value(asset_list, viewer_asset), song:_song,
        emu:_emu, play:_inf.play, cycles:_cycles, clock:_clock, rendered:0, start:0,
        ring:[], ring_i:0, cap:_cap, fb:buffer_create(128, buffer_fixed, 1), queue:-1, inst:-1};
    buffer_fill(_p.fb, 0, buffer_u8, 0, 128);
    for (var _i = 0; _i < 32; _i++) array_push(_p.ring, buffer_create(_cap * 2, buffer_fixed, 2));
    sid_asset_preview = _p;
    sid64_select(1);
    sid64_init(_clock, SID64_RATE, _model, global.sid64_engine);
    sid64_set_gain(0.6);
    sid64_set_cycles_per_frame(_cycles);
    sid64_settle(_emu.m[0xD418], 100);
    sid64_select(0);
    _p.queue = audio_create_play_queue(buffer_s16, SID64_RATE, audio_mono);
    for (var _i = 0; _i < 3; _i++) if (!scr_sid_asset_chunk()) return false;
    _p.inst = audio_play_sound(_p.queue, 1, false);
    _p.start = get_timer();
    return true;
}

function scr_sid_asset_chunk() {
    var _p = sid_asset_preview;
    for (var _f = 0; _f < 4; _f++) {
        if (scr_srel_call(_p.emu, _p.play, 0, 30000) < 0) {
            sid_asset_message = "Playback stopped: " + _p.emu.err;
            scr_sid_asset_stop(); return false;
        }
        for (var _r = 0; _r < 25; _r++) buffer_poke(_p.fb, _f * 32 + _r, buffer_u8, _p.emu.m[0xD400 + _r]);
    }
    var _buf = _p.ring[_p.ring_i];
    _p.ring_i = (_p.ring_i + 1) mod 32;
    sid64_select(1);
    var _got = sid64_render_log(buffer_get_address(_p.fb), 4, buffer_get_address(_buf), _p.cap);
    sid64_select(0);
    if (_got <= 0) { sid_asset_message = "SID DLL produced no audio."; scr_sid_asset_stop(); return false; }
    buffer_set_used_size(_buf, _got * 2);
    audio_queue_sound(_p.queue, _buf, 0, _got * 2);
    _p.rendered += 4;
    return true;
}

function scr_sid_asset_update() {
    var _p = sid_asset_preview;
    if (!is_struct(_p)) return;
    if (!viewer_open || viewer_asset < 0 || viewer_asset >= ds_list_size(asset_list)
    || ds_list_find_value(asset_list, viewer_asset) != _p.owner
    || scr_reu_find_asset(_p.asset.name) != _p.asset) { scr_sid_asset_stop(); return; }
    var _period = _p.cycles * 1000000 / _p.clock;
    var _played = floor((get_timer() - _p.start) / _period);
    var _deadline = get_timer() + 6000;
    while (_p.rendered < _played + 12) {
        if (!scr_sid_asset_chunk()) return;
        if (get_timer() > _deadline) break;
    }
    if (_p.rendered < _played) _p.start = get_timer() - max(0, _p.rendered - 12) * _period;
}

function scr_sid_asset_controls(_asset, _x, _y, _w) {
    if (sid_asset_name != _asset.name) {
        scr_sid_asset_stop();
        sid_asset_name = _asset.name; sid_asset_song = 0; sid_asset_message = "";
        if (buffer_exists(_asset.buffer) && buffer_get_size(_asset.buffer) >= 18)
            sid_asset_song = max(0, ((buffer_peek(_asset.buffer, 16, buffer_u8) << 8) | buffer_peek(_asset.buffer, 17, buffer_u8)) - 1);
    }
    var _songs = 1;
    if (buffer_exists(_asset.buffer) && buffer_get_size(_asset.buffer) >= 18)
        _songs = max(1, (buffer_peek(_asset.buffer, 14, buffer_u8) << 8) | buffer_peek(_asset.buffer, 15, buffer_u8));
    sid_asset_song = clamp(sid_asset_song, 0, min(256, _songs) - 1);
    draw_set_color(c_white);
    draw_text_l(_x, _y, "SUBTUNE " + string(sid_asset_song + 1) + " / " + string(_songs));
    var _labels = ["<", ">", is_struct(sid_asset_preview) ? "RESTART" : "PLAY", "STOP"];
    var _widths = [28, 28, 76, 54];
    var _bx = _x;
    for (var _i = 0; _i < 4; _i++) {
        var _hover = point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y, _bx, _y+20, _bx+_widths[_i]-3, _y+44);
        draw_set_color(_hover ? make_color_rgb(65,110,125) : make_color_rgb(35,65,78));
        draw_rectangle(_bx, _y+20, _bx+_widths[_i]-3, _y+44, false);
        draw_set_color(c_white); draw_text_l(_bx+5, _y+26, _labels[_i]);
        if (_hover && mouse_check_button_pressed(mb_left) && !global.any_picker_open) {
            if (_i < 2) {
                var _was = is_struct(sid_asset_preview);
                scr_sid_asset_stop(); sid_asset_message = "";
                sid_asset_song = (sid_asset_song + (_i == 0 ? -1 : 1) + min(256,_songs)) mod min(256,_songs);
                if (_was) scr_sid_asset_start(_asset, sid_asset_song);
            } else if (_i == 2) scr_sid_asset_start(_asset, sid_asset_song);
            else scr_sid_asset_stop();
            mouse_clear(mb_left);
        }
        _bx += _widths[_i];
    }
    draw_set_color(c_ltgray);
    var _status = is_struct(sid_asset_preview) ? "PLAYING  " + string(floor((get_timer()-sid_asset_preview.start)/1000000)) + " s" : "Press PLAY to listen";
    if (sid_asset_message != "") _status = sid_asset_message;
    draw_text_ext_l(_x, _y+54, _status, 14, _w);
}

/// Start an audition display only after the actual sound starts (also on cache hits).
function scr_sound_instrument_follow_start(_instr, _channel, _trace, _period) {
    if (!variable_global_exists("instrument_follow")) global.instrument_follow = [];
    global.instrument_follow[_channel] = { instr: variable_struct_exists(_instr, "follow_owner") ? _instr.follow_owner : _instr,
        compiled: scr_instrument_ensure_compiled(_instr), trace: _trace,
        period: _period, start_us: get_timer(), instance: global.snd_preview_instance[_channel] };
}

/// Read the same historical frame as the pattern highlight; auditions use their own clocks.
function scr_sound_instrument_follow_read(_m) {
    var _out = [];
    var _st = global.sid64_stream;
    if (_st.active && _st.sim.m == _m && variable_struct_exists(_st, "pos_instruments")) {
        var _frame = clamp(floor((get_timer() - _st.start_us) / SID64_FRAME_US), 0, _st.frames_rendered - 1);
        var _snap = _st.pos_instruments[_frame mod SID64_POS_RING];
        if (is_array(_snap)) for (var _si = 0; _si < array_length(_snap); _si++) array_push(_out, _snap[_si]);
    }
    if (variable_global_exists("instrument_follow")) {
        for (var _ch = 0; _ch < array_length(global.instrument_follow); _ch++) {
            var _f = global.instrument_follow[_ch];
            if (!is_struct(_f)) continue;
            if (!audio_is_playing(_f.instance)) { global.instrument_follow[_ch] = undefined; continue; }
            var _fi = floor((get_timer() - _f.start_us) / _f.period);
            if (_fi >= 0 && _fi < array_length(_f.trace)) {
                var _v = _f.trace[_fi];
                if (is_struct(_v)) {
                    // reSID auditions record the running tables' positions too
                    // (scr_sid64_voice_display); the GML fallback has none.
                    var _vt = _v[$ "tpcs"];
                    if (!is_array(_vt)) {
                        _vt = [];
                    }
                    array_push(_out, { instr: _f.instr, compiled: _f.compiled, pcs: _v.pcs, tpcs: _vt });
                }
            }
        }
    }
    return _out;
}
