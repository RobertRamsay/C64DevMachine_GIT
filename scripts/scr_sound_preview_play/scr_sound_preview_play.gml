/// @desc scr_sound_preview_play(_note_name, _waveform)
/// Synthesizes a short waveform cycle at the note's frequency and plays it
/// immediately — no sample assets, no files. Monophonic: a new call stops and
/// frees whatever preview is currently sounding, so rapid key-repeat typing
/// never piles up audio resources.
///
/// _waveform: "SQUARE" (default), "SAW", "TRIANGLE", "NOISE" — matches the
/// broad families the SID instrument bytecode's wave commands select, so this
/// can later be driven by the currently-selected instrument's waveform rather
/// than always defaulting to square.
///
/// A rest ("---" or "") or an unparseable note plays nothing and returns
/// quietly — this is a preview aid, not a validator (scr_note_name_to_freq
/// already owns validation at commit time).
function scr_sound_preview_play(_note_name, _waveform = "SQUARE", _channel = 0, _pulse_width = 2048) {
    if (_note_name == "" || _note_name == "---") {
        return;
    }
    var _hz = scr_note_name_to_hz(_note_name);
    if (_hz <= 0) {
        return;
    }

    // One preview instance PER CHANNEL (one per voice lane), so V1/V2/V3 can
    // sound together for chords rather than each new call cutting off the
    // last. _channel defaults to 0 for callers that don't care (single-key
    // entry from the cursor's own lane still passes its lane number below).
    if (!variable_global_exists("snd_preview_instance")) {
        global.snd_preview_instance = array_create(3, -1);
    }
    while (array_length(global.snd_preview_instance) <= _channel) {
        array_push(global.snd_preview_instance, -1);
    }

    // Stop the previous sound on THIS channel only — other channels keep
    // ringing undisturbed. Nothing is freed here: rendered sounds are owned
    // by the cache below and replayed rather than rebuilt.
    scr_sound_preview_free_channel(_channel);

    // ── CACHE LOOKUP ──
    // This is the fallback for steps with no instrument assigned, so the same
    // few (note, waveform, pw) triples recur constantly during row playback.
    // Rendering is only ~3.5k samples, but a buffer_create per keypress adds
    // up — and without a cache nothing reclaims them, since free_channel now
    // only stops playback.
    if (!variable_global_exists("snd_preview_cache")) {
        global.snd_preview_cache = ds_map_create();
    }
    var _ck = "P|" + string(_note_name) + "|" + string(_waveform) + "|" + string(round(_pulse_width));
    if (ds_map_exists(global.snd_preview_cache, _ck)) {
        var _hit = global.snd_preview_cache[? _ck];
        global.snd_preview_asset[_channel]    = _hit.snd;
        global.snd_preview_buffer[_channel]   = _hit.buf;
        global.snd_preview_instance[_channel] = audio_play_sound(_hit.snd, 1, false);
        return;
    }

    var _rate = 22050;
    var _dur  = 0.16;              // seconds — short and snappy for fast typing
    var _n    = round(_rate * _dur);
    var _buf  = buffer_create(_n * 2, buffer_fixed, 2);   // 16-bit mono

    var _phase      = 0;
    var _phase_step = _hz / _rate;
    var _attack_n    = max(1, round(_rate * 0.004));   // ~4ms — avoids a start click
    var _release_n   = max(1, round(_rate * 0.05));    // ~50ms fade-out
	// Convert 12-bit SID pulse width (0-4095) to a fractional phase threshold (0.0-1.0)
    // Clamped slightly away from 0.0 and 1.0 to prevent complete silence
    var _pw_thresh = clamp(_pulse_width / 4096.0, 0.01, 0.99);

    for (var _i = 0; _i < _n; _i++) {
        var _t = _phase - floor(_phase);   // 0..1 fractional cycle position
        var _s = 0;

        switch (_waveform) {
            case "SAW":
                _s = (_t * 2) - 1;
                break;
            case "TRIANGLE":
                _s = (_t < 0.5) ? (_t * 4 - 1) : (3 - _t * 4);
                break;
            case "NOISE":
                _s = random_range(-1, 1);
                break;
            case "SQUARE":
            default:
                _s = (_t < _pw_thresh) ? 1 : -1;
                break;
        }

        // Attack/release envelope so truncating an arbitrary waveform phase
        // at the start or end of the buffer never produces an audible click.
        var _env = 1;
        if (_i < _attack_n) {
            _env = _i / _attack_n;
        } else if (_i > _n - _release_n) {
            _env = (_n - _i) / _release_n;
        }

        var _amp = 0.30;   // headroom for repeated rapid triggers
        var _val = clamp(round(_s * _env * _amp * 32767), -32768, 32767);
        buffer_write(_buf, buffer_s16, _val);

        _phase += _phase_step;
    }

     var _snd = audio_create_buffer_sound(_buf, buffer_s16, _rate, 0, buffer_get_size(_buf), audio_mono);

    if (ds_map_size(global.snd_preview_cache) >= 128) {
        scr_sound_preview_cache_clear();
    }
    global.snd_preview_cache[? _ck] = { snd: _snd, buf: _buf };

    global.snd_preview_asset[_channel]    = _snd;
    global.snd_preview_buffer[_channel]   = _buf;
    global.snd_preview_instance[_channel] = audio_play_sound(_snd, 1, false);
}