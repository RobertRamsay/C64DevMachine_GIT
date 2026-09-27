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
    for (var _s = 1; _s >= 0; _s--) {
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
    return { snd: _snd, buf: _buf };
}

// ═══════════════════════════ SONG STREAMING ═══════════════════════════

/// Starts streamed playback on slot 1.
/// _loop_row true = loop order row _ord (PLAY PAT / Space), false = play the song.
function scr_sid64_stream_start(_m, _song, _loop_row, _ord, _row) {
    scr_sid64_stream_stop();
    var _st = global.sid64_stream;
    _st.sim = scr_sid64_sim_create(_m, _song, _loop_row, _ord, _row);
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
}

/// Runs SID64_CHUNK_FRAMES frames of the sim, renders them and queues the audio.
function scr_sid64_stream_chunk() {
    var _st = global.sid64_stream;
    var _fb = global.sid64_frame_buf;
    for (var _i = 0; _i < SID64_CHUNK_FRAMES; _i++) {
        scr_sid64_sim_frame(_st.sim);
        scr_sid64_sim_put(_st.sim, _fb, _i);
        var _pi = (_st.frames_rendered + _i) mod SID64_POS_RING;
        _st.pos_ord[_pi] = _st.sim.shown_ord;
        _st.pos_row[_pi] = _st.sim.shown_row;
        if (_st.sim.finished && _st.finished_at < 0) {
            _st.finished_at = _st.frames_rendered + _i;
        }
    }
    var _buf = _st.ring[_st.ring_i];
    _st.ring_i = (_st.ring_i + 1) mod SID64_RING;
    sid64_select(1);
    var _got = sid64_render_log(buffer_get_address(_fb), SID64_CHUNK_FRAMES, buffer_get_address(_buf), _st.ring_samples);
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
    var _played = floor((get_timer() - _st.start_us) / 20000);
    var _guard = 0;
    while (_st.frames_rendered < _played + SID64_AHEAD_FRAMES && _guard < 16) {
        scr_sid64_stream_chunk();
        _guard += 1;
    }
    // Fell far behind (window dragged, breakpoint): resync the clock rather
    // than bursting a backlog into the queue.
    if (_st.frames_rendered < _played) {
        _st.start_us = get_timer() - (_st.frames_rendered - SID64_AHEAD_FRAMES) * 20000;
        _played = _st.frames_rendered - SID64_AHEAD_FRAMES;
    }
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
