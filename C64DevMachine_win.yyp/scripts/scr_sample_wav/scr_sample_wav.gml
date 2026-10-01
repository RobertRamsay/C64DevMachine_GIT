/// @function scr_sample_wav_import(_asset)
/// @desc IMPORT WAV button. Replaces the asset's source PCM and resets the trim.
function scr_sample_wav_import(_asset) {
    var _path = get_open_filename("WAV Audio|*.wav", "");
    io_clear();
    if (_path == "") {
        return;
    }
    var _m = _asset.meta;
    var _r = scr_sample_wav_decode(_path);
    if (!_r.ok) {
        _m.warn_msg   = _r.msg;
        _m.warn_timer = 300;
        return;
    }

    scr_sample_preview_stop();
    if (buffer_exists(_asset.buffer)) {
        buffer_delete(_asset.buffer);
    }
    _asset.buffer = _r.buf;

    _m.src_rate   = _r.rate;
    _m.src_len    = _r.len;
    _m.src_name   = filename_name(_path);
    _m.trim_start = 0;
    _m.trim_end   = _r.len;
    _m.data_ver  += 1;
    _m.wf_src_key = "";
    _m.enc_dirty  = true;
    _m.warn_msg   = _r.msg;
    _m.warn_timer = 0;
    if (_r.msg != "") {
        _m.warn_timer = 300;
    }
    global.undo_dirty = true;
}

/// Four ASCII chars at _off.
function scr_sample_wav_tag(_b, _off) {
    var _s = "";
    for (var _i = 0; _i < 4; _i++) {
        _s += chr(buffer_peek(_b, _off + _i, buffer_u8));
    }
    return _s;
}

/// @function scr_sample_wav_decode(_path)
/// @desc Reads a RIFF WAVE file into 8-bit unsigned mono at <= SAMPLE_SRC_MAX_RATE,
///       peak-normalised. Handles PCM 8/16/24/32, float 32/64, WAVE_FORMAT_EXTENSIBLE,
///       any channel count (averaged). Returns { ok, msg, buf, rate, len }.
function scr_sample_wav_decode(_path) {
    var _res = { ok: false, msg: "", buf: -1, rate: 0, len: 0 };

    var _b = buffer_load(_path);
    if (_b == -1) {
        _res.msg = "COULD NOT READ " + filename_name(_path);
        return _res;
    }
    var _size = buffer_get_size(_b);
    if (_size < 44) {
        buffer_delete(_b);
        _res.msg = "NOT A WAV FILE";
        return _res;
    }
    if (scr_sample_wav_tag(_b, 0) != "RIFF" || scr_sample_wav_tag(_b, 8) != "WAVE") {
        buffer_delete(_b);
        _res.msg = "NOT A WAV FILE";
        return _res;
    }

    // ── CHUNKS ──
    var _fmt = -1;
    var _ch = 0;
    var _rate = 0;
    var _align = 0;
    var _bits = 0;
    var _data_pos = -1;
    var _data_len = 0;
    var _pos = 12;
    while (_pos + 8 <= _size) {
        var _id   = scr_sample_wav_tag(_b, _pos);
        var _clen = buffer_peek(_b, _pos + 4, buffer_u32);
        var _body = _pos + 8;
        if (_id == "fmt " && _body + 16 <= _size) {
            _fmt   = buffer_peek(_b, _body,      buffer_u16);
            _ch    = buffer_peek(_b, _body + 2,  buffer_u16);
            _rate  = buffer_peek(_b, _body + 4,  buffer_u32);
            _align = buffer_peek(_b, _body + 12, buffer_u16);
            _bits  = buffer_peek(_b, _body + 14, buffer_u16);
            if (_fmt == 0xFFFE && _clen >= 26 && _body + 26 <= _size) {
                _fmt = buffer_peek(_b, _body + 24, buffer_u16);   // sub-format GUID, first word
            }
        } else if (_id == "data") {
            _data_pos = _body;
            _data_len = min(_clen, _size - _body);
        }
        _pos = _body + _clen + (_clen & 1);
    }

    var _supported = false;
    if (_fmt == 1) {
        if (_bits == 8 || _bits == 16 || _bits == 24 || _bits == 32) {
            _supported = true;
        }
    }
    if (_fmt == 3) {
        if (_bits == 32 || _bits == 64) {
            _supported = true;
        }
    }
    if (!_supported || _ch < 1 || _align < 1 || _data_pos < 0) {
        buffer_delete(_b);
        _res.msg = "UNSUPPORTED WAV (NEED PCM 8/16/24/32-BIT OR FLOAT)";
        return _res;
    }
    if (_rate < 2000) {
        buffer_delete(_b);
        _res.msg = "WAV RATE TOO LOW (" + string(_rate) + " HZ)";
        return _res;
    }

    var _frames = floor(_data_len / _align);
    var _max_frames = _rate * SAMPLE_MAX_SECONDS;
    var _truncated = false;
    if (_frames > _max_frames) {
        _frames = _max_frames;
        _truncated = true;
    }
    if (_frames < 2) {
        buffer_delete(_b);
        _res.msg = "WAV HAS NO AUDIO";
        return _res;
    }

    // ── READ + DOWNMIX ──
    var _bps  = _bits div 8;
    var _mono = array_create(_frames, 0);
    for (var _f = 0; _f < _frames; _f++) {
        var _base = _data_pos + _f * _align;
        var _acc = 0;
        for (var _c = 0; _c < _ch; _c++) {
            var _o = _base + _c * _bps;
            var _v = 0;
            if (_fmt == 3) {
                if (_bits == 32) {
                    _v = buffer_peek(_b, _o, buffer_f32);
                } else {
                    _v = buffer_peek(_b, _o, buffer_f64);
                }
            } else if (_bits == 8) {
                _v = (buffer_peek(_b, _o, buffer_u8) - 128) / 128;
            } else if (_bits == 16) {
                _v = buffer_peek(_b, _o, buffer_s16) / 32768;
            } else if (_bits == 24) {
                var _i24 = buffer_peek(_b, _o, buffer_u8)
                         | (buffer_peek(_b, _o + 1, buffer_u8) << 8)
                         | (buffer_peek(_b, _o + 2, buffer_u8) << 16);
                if (_i24 >= 0x800000) {
                    _i24 -= 0x1000000;
                }
                _v = _i24 / 8388608;
            } else {
                _v = buffer_peek(_b, _o, buffer_s32) / 2147483648;
            }
            _acc += _v;
        }
        _mono[_f] = _acc / _ch;
    }
    buffer_delete(_b);

    // ── RESAMPLE DOWN (box filter doubles as the anti-alias) ──
    var _out_rate = min(_rate, SAMPLE_SRC_MAX_RATE);
    var _out = _mono;
    var _n = _frames;
    if (_out_rate < _rate) {
        var _ratio = _rate / _out_rate;
        _n = floor(_frames / _ratio);
        _out = array_create(_n, 0);
        for (var _k = 0; _k < _n; _k++) {
            var _a0 = floor(_k * _ratio);
            var _a1 = floor((_k + 1) * _ratio);
            if (_a1 <= _a0) {
                _a1 = _a0 + 1;
            }
            if (_a1 > _frames) {
                _a1 = _frames;
            }
            var _sum = 0;
            for (var _j = _a0; _j < _a1; _j++) {
                _sum += _mono[_j];
            }
            _out[_k] = _sum / max(1, _a1 - _a0);
        }
    }

    // ── PEAK-NORMALISE + 8-BIT ──
    var _peak = 0;
    for (var _p = 0; _p < _n; _p++) {
        _peak = max(_peak, abs(_out[_p]));
    }
    var _scale = 0;
    if (_peak > 0) {
        _scale = 1 / _peak;
    }
    var _buf = buffer_create(max(1, _n), buffer_fixed, 1);
    for (var _w = 0; _w < _n; _w++) {
        var _u = clamp(round(_out[_w] * _scale * 127 + 128), 1, 255);
        buffer_poke(_buf, _w, buffer_u8, _u);
    }

    _res.ok   = true;
    _res.buf  = _buf;
    _res.rate = _out_rate;
    _res.len  = _n;
    if (_truncated) {
        _res.msg = "TRUNCATED TO " + string(SAMPLE_MAX_SECONDS) + " SECONDS";
    }
    if (_peak <= 0) {
        _res.msg = "WAV IS SILENT";
    }
    return _res;
}
