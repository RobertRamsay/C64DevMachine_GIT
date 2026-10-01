/// @function scr_sample_cia_latch(_rate)
/// @desc CIA timer latch for an NMI every 1/_rate s on PAL (period = latch + 1 cycles).
function scr_sample_cia_latch(_rate) {
    return max(1, round(SAMPLE_PAL_CLOCK / max(1, _rate)) - 1);
}

/// Source sample at fractional position _pos, as -1..1 (linear interpolation).
function scr_sample_src_at(_buf, _len, _pos) {
    var _i0 = floor(_pos);
    if (_i0 >= _len - 1) {
        return (buffer_peek(_buf, _len - 1, buffer_u8) - 128) / 127;
    }
    var _t  = _pos - _i0;
    var _s0 = buffer_peek(_buf, _i0, buffer_u8);
    var _s1 = buffer_peek(_buf, _i0 + 1, buffer_u8);
    return (_s0 + (_s1 - _s0) * _t - 128) / 127;
}

/// @function scr_sample_encode(_asset)
/// @desc Rebuilds meta.enc / meta.packed at the asset's own rate (the editor view).
function scr_sample_encode(_asset) {
    var _m = _asset.meta;
    var _r = scr_sample_encode_at(_asset, _m.rate, _m.pack);
    _m.enc        = _r.enc;
    _m.packed     = _r.packed;
    _m.out_count  = array_length(_r.enc);
    _m.out_bytes  = array_length(_r.packed);
    _m.clip_count = _r.clip;
    _m.enc_dirty  = false;
    _m.enc_ver   += 1;
}

/// @function scr_sample_encode_at(_asset, _rate, _pack)
/// @desc Encodes the asset's trimmed source at any playback rate, leaving the
///       asset untouched. Returns { enc, packed, clip }:
///         enc     the 4-bit levels the C64 outputs, after packing round-trips
///         packed  the bytes a player reads
///         clip    how many samples the gain pushed past full scale
///       The Music Maker digi track calls this at the song's digi rate.
///
///   pack 0  4-bit nibbles, two samples per byte, FIRST sample in the LOW nibble.
///   pack 1  2-bit delta, four samples per byte, first in bits 0-1. Each code
///           adds DELTA[code] = -3,-1,+1,+3 to a level that starts at 8. The
///           encoder only picks codes that keep the level inside 0-15, so the
///           decoder never needs to clamp.
function scr_sample_encode_at(_asset, _rate, _pack) {
    var _m = _asset.meta;
    var _res = { enc: [], packed: [], clip: 0 };
    if (_m.src_len <= 1 || _m.src_rate <= 0 || !buffer_exists(_asset.buffer)) {
        return _res;
    }
    var _buf  = _asset.buffer;
    var _len  = _m.src_len;
    var _ts   = clamp(_m.trim_start, 0, _len);
    var _te   = clamp(_m.trim_end, _ts, _len);
    var _step = _m.src_rate / max(1, _rate);
    var _n    = floor((_te - _ts) / _step);
    if (_n <= 0) {
        return _res;
    }
    var _gain = _m.gain / 100;

    // ── RESAMPLE + GAIN + QUANTISE → target levels (real 0..15) ──
    var _lev  = array_create(_n, 0);
    var _clip = 0;
    var _seed = 12345;
    for (var _k = 0; _k < _n; _k++) {
        var _a = _ts + _k * _step;
        var _v = 0;
        if (_step > 1) {
            var _i0 = floor(_a);
            var _i1 = floor(_a + _step);
            if (_i1 <= _i0) {
                _i1 = _i0 + 1;
            }
            if (_i1 > _te) {
                _i1 = _te;
            }
            var _sum = 0;
            for (var _j = _i0; _j < _i1; _j++) {
                _sum += buffer_peek(_buf, _j, buffer_u8);
            }
            _v = (_sum / max(1, _i1 - _i0) - 128) / 127;
        } else {
            _v = scr_sample_src_at(_buf, _len, _a);
        }
        _v *= _gain;
        if (_v > 1 || _v < -1) {
            _clip += 1;
            _v = clamp(_v, -1, 1);
        }
        var _q = (_v + 1) * 7.5;
        if (_m.dither == 1) {
            // Deterministic TPDF, so the same settings always give the same bytes.
            _seed = (_seed * 69069 + 1) & 0xFFFFFFFF;
            var _r1 = (_seed >> 16) / 65536;
            _seed = (_seed * 69069 + 1) & 0xFFFFFFFF;
            var _r2 = (_seed >> 16) / 65536;
            _q += _r1 - _r2;
        }
        _lev[_k] = clamp(_q, 0, 15);
    }

    var _enc    = array_create(_n, 0);
    var _packed = [];
    if (_pack == 1) {
        // ── 2-BIT DELTA ──
        var _delta = [-3, -1, 1, 3];
        var _level = 8;
        var _byte  = 0;
        for (var _k = 0; _k < _n; _k++) {
            var _best_c = 0;
            var _best_e = 1000;
            for (var _c = 0; _c < 4; _c++) {
                var _nl = _level + _delta[_c];
                if (_nl < 0 || _nl > 15) {
                    continue;
                }
                var _e = abs(_nl - _lev[_k]);
                if (_e < _best_e) {
                    _best_e = _e;
                    _best_c = _c;
                }
            }
            _level += _delta[_best_c];
            _enc[_k] = _level;
            _byte |= (_best_c << ((_k & 3) * 2));
            if ((_k & 3) == 3) {
                array_push(_packed, _byte);
                _byte = 0;
            }
        }
        if ((_n & 3) != 0) {
            array_push(_packed, _byte);
        }
    } else {
        // ── 4-BIT NIBBLES ──
        for (var _k = 0; _k < _n; _k++) {
            _enc[_k] = clamp(round(_lev[_k]), 0, 15);
        }
        for (var _k = 0; _k < _n; _k += 2) {
            var _lo = _enc[_k];
            var _hi = _lo;
            if (_k + 1 < _n) {
                _hi = _enc[_k + 1];
            }
            array_push(_packed, _lo | (_hi << 4));
        }
    }

    _res.enc    = _enc;
    _res.packed = _packed;
    _res.clip   = _clip;
    return _res;
}

// ═══════════════════════════ PREVIEW ═══════════════════════════
// Monophonic: one preview at a time across all SAMPLE assets. State lives in
// obj_asset_manager.sample_pv (initialised in its Create event).

/// @function scr_sample_preview_stop()
function scr_sample_preview_stop() {
    with (obj_asset_manager) {
        if (sample_pv.active) {
            if (audio_is_playing(sample_pv.inst)) {
                audio_stop_sound(sample_pv.inst);
            }
            audio_free_buffer_sound(sample_pv.snd);
            buffer_delete(sample_pv.buf);
        }
        sample_pv.active = false;
        sample_pv.snd    = -1;
        sample_pv.buf    = -1;
        sample_pv.inst   = -1;
        sample_pv.asset  = undefined;
        sample_pv.mode   = 0;
    }
}

/// @function scr_sample_preview_play(_asset, _mode)
/// @desc _mode 0 = SOURCE (trimmed, with gain), 1 = C64 (the 4-bit levels, held
///       for one C64 sample period each — the stepped sound the $D418 DAC makes).
function scr_sample_preview_play(_asset, _mode) {
    scr_sample_preview_stop();
    var _m = _asset.meta;
    if (_m.src_len <= 1 || !buffer_exists(_asset.buffer)) {
        return;
    }
    if (_m.enc_dirty) {
        scr_sample_encode(_asset);
    }

    var _rate = SAMPLE_PV_RATE;
    var _n = 0;
    var _buf = -1;
    if (_mode == 0) {
        var _ts = clamp(_m.trim_start, 0, _m.src_len);
        var _te = clamp(_m.trim_end, _ts, _m.src_len);
        _n = floor((_te - _ts) * _rate / _m.src_rate);
        if (_n <= 0) {
            return;
        }
        var _gain = _m.gain / 100;
        _buf = buffer_create(_n * 2, buffer_fixed, 2);
        for (var _i = 0; _i < _n; _i++) {
            var _v = scr_sample_src_at(_asset.buffer, _m.src_len, _ts + _i * _m.src_rate / _rate);
            _v = clamp(_v * _gain, -1, 1);
            buffer_write(_buf, buffer_s16, round(_v * 24000));
        }
    } else {
        var _cnt = _m.out_count;
        if (_cnt <= 0) {
            return;
        }
        _n = floor(_cnt * _rate / _m.rate);
        if (_n <= 0) {
            return;
        }
        _buf = buffer_create(_n * 2, buffer_fixed, 2);
        for (var _i = 0; _i < _n; _i++) {
            var _k = min(_cnt - 1, floor(_i * _m.rate / _rate));
            var _v = (_m.enc[_k] - 7.5) / 7.5;
            buffer_write(_buf, buffer_s16, round(_v * 24000));
        }
    }

    var _snd  = audio_create_buffer_sound(_buf, buffer_s16, _rate, 0, _n * 2, audio_mono);
    var _inst = audio_play_sound(_snd, 10, false);
    with (obj_asset_manager) {
        sample_pv.active = true;
        sample_pv.snd    = _snd;
        sample_pv.buf    = _buf;
        sample_pv.inst   = _inst;
        sample_pv.asset  = _asset;
        sample_pv.mode   = _mode;
    }
}

/// @function scr_sample_preview_tick()
/// @desc Frees the preview once it has finished. Called by the editor each frame.
function scr_sample_preview_tick() {
    var _done = false;
    with (obj_asset_manager) {
        if (sample_pv.active && !audio_is_playing(sample_pv.inst)) {
            _done = true;
        }
    }
    if (_done) {
        scr_sample_preview_stop();
    }
}

/// @function scr_sample_preview_pos(_asset)
/// @desc Seconds into the preview of _asset, or -1 if it isn't the one playing.
function scr_sample_preview_pos(_asset) {
    var _pos = -1;
    with (obj_asset_manager) {
        if (sample_pv.active && sample_pv.asset == _asset) {
            _pos = audio_sound_get_track_position(sample_pv.inst);
        }
    }
    return _pos;
}
