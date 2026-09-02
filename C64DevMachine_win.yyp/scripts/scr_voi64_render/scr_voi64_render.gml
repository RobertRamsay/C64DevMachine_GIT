/// ====================================================================
/// VOI64 — SYNTHESIS AND PREVIEW
///
/// A parallel three-resonator formant synthesiser, plus a fourth
/// resonator carrying the frication noise. It renders a 16-bit mono
/// buffer and plays it through audio_create_buffer_sound, the same way
/// scr_sound_preview_play does for note previews.
///
/// WHY THIS EXISTS BEFORE ANY 6502
/// The formant table IS the project. The player is mechanical; the
/// numbers in scr_voi64_phonemes are what decide whether a listener
/// understands the word. Tuning those in VICE is a minute per attempt.
/// Tuning them here is instant, so this comes first and the SID player
/// inherits a table that has already been made to work.
///
/// HOW IT MAPS ONTO THE SID
/// Three resonators summed is three SID voices summed. Each formant's
/// centre becomes a voice frequency, each amplitude a sustain nibble
/// (which is why they are 0-15 in the table), and the noise resonator
/// becomes the noise waveform on whichever voice is free. Glottal pitch
/// is not an oscillator — the oscillators are AT the formant frequencies —
/// so on the C64 it becomes a gate/volume pulse at the pitch rate from
/// the timer IRQ. That is why the excitation below is an impulse train
/// rather than a tone: it is the thing the C64 can actually reproduce.
///
/// KNOBS
///   pitch   glottal frequency in Hz. ~90 low, ~120 nominal, ~180 high.
///   speed   0-255, 128 nominal. HIGHER IS FASTER, unlike SAM's inverted
///           convention — no reason to inherit a confusing one.
///   throat  0-255, 128 neutral. Scales F1: lower = deeper, chestier.
///   mouth   0-255, 128 neutral. Scales F2/F3: higher = brighter, more
///           forward. This is the knob that changes "who" is speaking.
/// ====================================================================

#macro VOI64_RATE       22050
#macro VOI64_FRAME_HZ     100      // parameter frame rate; the SID player's IRQ rate
#macro VOI64_TRANS_FRAC  0.35      // fraction of a phoneme spent gliding in from the last

/// @function scr_voi64_reso_coef(_f, _bw)
/// @desc Two-pole resonator coefficients (Klatt form) for centre _f and
///       bandwidth _bw at VOI64_RATE. Recomputed once per 100Hz frame,
///       never per sample — that is the whole reason this renders fast
///       enough to feel instant.
function scr_voi64_reso_coef(_f, _bw) {
    var _fs = VOI64_RATE;
    var _c  = -exp(-2 * pi * _bw / _fs);
    var _b  =  2 * exp(-pi * _bw / _fs) * cos(2 * pi * _f / _fs);
    var _a  =  1 - _b - _c;
    return { a: _a, b: _b, c: _c };
}

/// @function scr_voi64_frame_params(_ph, _blend_to, _t)
/// @desc The parameter set for one phoneme at glide position _t (0..1),
///       already blended toward its diphthong target where it has one.
function scr_voi64_frame_params(_ph, _blend_to, _t) {
    var _p = {
        f1: _ph.f1, f2: _ph.f2, f3: _ph.f3,
        b1: _ph.b1, b2: _ph.b2, b3: _ph.b3,
        a1: _ph.a1, a2: _ph.a2, a3: _ph.a3,
        vcd: _ph.vcd, nz: _ph.nz,
        nf: (_ph.nf > 0) ? _ph.nf : _ph.f2
    };
    if (is_undefined(_blend_to)) {
        return _p;
    }
    // Diphthong glide. Held at the first target, then swept — the sweep is
    // the cue, not the endpoints, so a linear ramp is enough.
    _p.f1 = lerp(_ph.f1, _blend_to.f1, _t);
    _p.f2 = lerp(_ph.f2, _blend_to.f2, _t);
    _p.f3 = lerp(_ph.f3, _blend_to.f3, _t);
    _p.a1 = lerp(_ph.a1, _blend_to.a1, _t);
    _p.a2 = lerp(_ph.a2, _blend_to.a2, _t);
    _p.a3 = lerp(_ph.a3, _blend_to.a3, _t);
    return _p;
}

/// @function scr_voi64_build_frames(_phonemes, _speed)
/// @desc Turn a phoneme string into 100Hz parameter frames, with diphthong
///       glides and coarticulation already applied.
///
///       SHARED, and that is the point. The preview renders these frames to
///       audio; scr_voi64_sid converts the SAME frames to SID writes. One code
///       path means tuning the phoneme table moves the C64 and the preview
///       together. If these ever fork, the preview stops predicting the
///       hardware and is worth nothing.
function scr_voi64_build_frames(_phonemes, _speed = 128) {
    var _names = string_split(string_upper(string(_phonemes)), " ", true);
    if (array_length(_names) == 0) { return []; }
    var _speed_mul = 0.5 + (clamp(_speed, 0, 255) / 255);
    // ── build the frame list ──────────────────────────────────
    // Frames are resolved before any audio is generated so the buffer can
    // be allocated once at the right size. buffer_grow on tens of
    // thousands of samples is the slow way to do this.
    var _frames = [];
    var _prev   = undefined;

    for (var _i = 0; _i < array_length(_names); _i++) {
        var _ph = scr_voi64_phoneme(_names[_i]);

        // Stop closure: real silence before the burst. The ear identifies a
        // stop by the GAP, not by the click, so cutting this to save frames
        // is how P, T and K turn into nothing.
        var _sil_n = round(_ph.sil / _speed_mul);
        for (var _s = 0; _s < _sil_n; _s++) {
            array_push(_frames, { f1: 400, f2: 1200, f3: 2400, b1: 90, b2: 110, b3: 170,
                                  a1: 0, a2: 0, a3: 0, vcd: 0, nz: 0, nf: 1200 });
        }

        var _glide = undefined;
        if (_ph.gl != "") {
            _glide = scr_voi64_phoneme(_ph.gl);
        }

        var _n     = max(1, round(_ph.dur / _speed_mul));
        var _trans = max(1, round(_n * VOI64_TRANS_FRAC));

        for (var _f = 0; _f < _n; _f++) {
            // Diphthong sweep occupies the back half.
            var _gt = 0;
            if (!is_undefined(_glide)) {
                _gt = clamp((_f - _n * 0.4) / max(1, _n * 0.6), 0, 1);
            }
            var _tgt = scr_voi64_frame_params(_ph, _glide, _gt);

            // Coarticulation: glide in from wherever the last phoneme
            // ended rather than jumping. This is the single biggest
            // intelligibility win in the whole renderer — without it the
            // output is a row of isolated sounds and the ear refuses to
            // assemble them into words.
            var _cur = _tgt;
            if (!is_undefined(_prev) && _f < _trans) {
                var _bt = (_f + 1) / _trans;
                _cur = {
                    f1: lerp(_prev.f1, _tgt.f1, _bt),
                    f2: lerp(_prev.f2, _tgt.f2, _bt),
                    f3: lerp(_prev.f3, _tgt.f3, _bt),
                    b1: _tgt.b1, b2: _tgt.b2, b3: _tgt.b3,
                    a1: lerp(_prev.a1, _tgt.a1, _bt),
                    a2: lerp(_prev.a2, _tgt.a2, _bt),
                    a3: lerp(_prev.a3, _tgt.a3, _bt),
                    vcd: lerp(_prev.vcd, _tgt.vcd, _bt),
                    nz:  lerp(_prev.nz,  _tgt.nz,  _bt),
                    nf:  lerp(_prev.nf,  _tgt.nf,  _bt)
                };
            }
            array_push(_frames, _cur);
            _prev = _cur;
        }
    }

    return _frames;
}

/// @function scr_voi64_render_buffer(_phonemes, _pitch, _speed, _throat, _mouth)
/// @desc Render a space-separated phoneme string to a 16-bit mono buffer.
/// @return {struct} { buf, snd, samples } or undefined if there is nothing to say
function scr_voi64_render_buffer(_phonemes, _pitch = 120, _speed = 128, _throat = 128, _mouth = 128) {
    // Knob mapping. Throat and mouth are multipliers around 1.0 at 128,
    // deliberately gentle — a formant moved more than about 40% stops
    // sounding like a different voice and starts sounding like a
    // different vowel, which makes the speech wrong rather than characterful.
    var _throat_mul = 0.6 + (clamp(_throat, 0, 255) / 255) * 0.8;
    var _mouth_mul  = 0.6 + (clamp(_mouth,  0, 255) / 255) * 0.8;
    var _speed_mul  = 0.5 + (clamp(_speed,  0, 255) / 255) * 1.5;   // 128 -> ~1.25
    var _pitch_hz   = clamp(_pitch, 50, 400);

    // floor, not the raw quotient: 22050/100 is 220.5, and a fractional loop
    // bound writes 221 samples per frame while the buffer was sized on 220.5.
    // That overruns a buffer_fixed. One integer, used for both.
    var _spf = floor(VOI64_RATE / VOI64_FRAME_HZ);

    var _frames = scr_voi64_build_frames(_phonemes, _speed);

    var _nframes = array_length(_frames);
    if (_nframes == 0) {
        return undefined;
    }

    // A short tail so the last formant can ring out instead of being cut.
    var _tail = 6;
    var _total = (_nframes + _tail) * _spf;
    var _buf   = buffer_create(_total * 2, buffer_fixed, 2);

    // ── Pass 2: synthesise ────────────────────────────────────────────
    var _g1 = 0, _g2 = 0;      // resonator 1 history
    var _h1 = 0, _h2 = 0;      // resonator 2
    var _i1 = 0, _i2 = 0;      // resonator 3
    var _n1 = 0, _n2 = 0;      // noise resonator
    var _gphase = 0;
    var _gstep  = _pitch_hz / VOI64_RATE;
    var _written = 0;

    for (var _fi = 0; _fi < _nframes; _fi++) {
        var _p = _frames[_fi];

        var _c1 = scr_voi64_reso_coef(clamp(_p.f1 * _throat_mul, 120, 1200), _p.b1);
        var _c2 = scr_voi64_reso_coef(clamp(_p.f2 * _mouth_mul,  400, 3400), _p.b2);
        var _c3 = scr_voi64_reso_coef(clamp(_p.f3 * _mouth_mul,  900, 4200), _p.b3);
        var _cn = scr_voi64_reso_coef(clamp(_p.nf * _mouth_mul,  600, 8000), 900);

        var _av1 = _p.a1 / 15;
        var _av2 = _p.a2 / 15;
        var _av3 = _p.a3 / 15;
        var _avc = _p.vcd / 15;
        var _anz = _p.nz  / 15;

        for (var _s = 0; _s < _spf; _s++) {
            // Glottal excitation: an impulse train, not a tone. On the C64
            // this is the volume/gate pulse from the IRQ, so modelling it
            // any richer here would flatter a voice the target cannot make.
            var _glot = 0;
            _gphase += _gstep;
            if (_gphase >= 1) {
                _gphase -= 1;
                _glot = _avc;
            }

            var _noise = 0;
            if (_anz > 0) {
                _noise = random_range(-1, 1) * _anz;
            }

            var _y1 = _c1.a * _glot + _c1.b * _g1 + _c1.c * _g2;  _g2 = _g1; _g1 = _y1;
            var _y2 = _c2.a * _glot + _c2.b * _h1 + _c2.c * _h2;  _h2 = _h1; _h1 = _y2;
            var _y3 = _c3.a * _glot + _c3.b * _i1 + _c3.c * _i2;  _i2 = _i1; _i1 = _y3;
            var _yn = _cn.a * _noise + _cn.b * _n1 + _cn.c * _n2; _n2 = _n1; _n1 = _yn;

            // Gain staging, measured rather than guessed. A narrow F1 with a
            // 90Hz bandwidth resonates hard, and the fricatives are hotter
            // still — at a flat 6.0/1.6 the front vowels clipped a couple of
            // percent of samples and S clipped seventeen. Lower gains plus a
            // soft saturator keeps the loudness without ever squaring off a
            // peak, and leaves S as the loudest phoneme, which is correct.
            var _out = (_y1 * _av1 + _y2 * _av2 + _y3 * _av3) * 4.0 + _yn * 0.55;
            _out = _out / (1.0 + abs(_out) * 0.6);
            var _val = clamp(round(_out * 0.45 * 32767), -32768, 32767);
            buffer_write(_buf, buffer_s16, _val);
            _written += 1;
        }
    }

    // Tail: let the resonators decay with no excitation, then a short fade
    // so the buffer never ends on a non-zero sample and clicks.
    var _tail_n = _total - _written;
    var _c1t = scr_voi64_reso_coef(500, 90);
    for (var _s = 0; _s < _tail_n; _s++) {
        var _y1t = _c1t.b * _g1 + _c1t.c * _g2;  _g2 = _g1; _g1 = _y1t;
        var _env = 1 - (_s / max(1, _tail_n));
        var _valt = clamp(round(_y1t * _env * 0.30 * 32767), -32768, 32767);
        buffer_write(_buf, buffer_s16, _valt);
    }

    var _snd = audio_create_buffer_sound(_buf, buffer_s16, VOI64_RATE, 0,
                                         buffer_get_size(_buf), audio_mono);
    return { buf: _buf, snd: _snd, samples: _total };
}

/// @function scr_voi64_stop()
/// @desc Stop and free whatever Voi64 is currently saying. Safe to call
///       when nothing is playing.
function scr_voi64_stop() {
    if (!variable_global_exists("voi64_play")) {
        global.voi64_play = undefined;
        return;
    }
    if (is_undefined(global.voi64_play)) {
        return;
    }
    var _p = global.voi64_play;
    if (audio_is_playing(_p.inst)) {
        audio_stop_sound(_p.inst);
    }
    audio_free_buffer_sound(_p.snd);
    buffer_delete(_p.buf);
    global.voi64_play = undefined;
}

/// @function scr_voi64_say_phonemes(_phonemes, _pitch, _speed, _throat, _mouth)
/// @desc Speak a phoneme string. Monophonic on purpose — a second call
///       cuts the first, which is what MACRO_VOI64_SAY will do on the C64
///       and what makes rapid preview clicks behave.
function scr_voi64_say_phonemes(_phonemes, _pitch = 120, _speed = 128, _throat = 128, _mouth = 128) {
    scr_voi64_stop();
    var _r = scr_voi64_render_buffer(_phonemes, _pitch, _speed, _throat, _mouth);
    if (is_undefined(_r)) {
        return false;
    }
    global.voi64_play = { snd: _r.snd, buf: _r.buf, inst: audio_play_sound(_r.snd, 1, false) };
    return true;
}

/// @function scr_voi64_say(_text, _pitch, _speed, _throat, _mouth)
/// @desc Speak English text. Runs the letter-to-sound pass first, so this
///       is the call that proves the whole chain end to end.
function scr_voi64_say(_text, _pitch = 120, _speed = 128, _throat = 128, _mouth = 128) {
    var _ph = scr_voi64_text_to_phonemes(_text);
    show_debug_message("VOI64: \"" + string(_text) + "\"  ->  " + _ph);
    return scr_voi64_say_phonemes(_ph, _pitch, _speed, _throat, _mouth);
}
