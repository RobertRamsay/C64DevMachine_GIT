/// Small push button for the sample editor. Returns true on click.
function scr_sample_button(_x1, _y1, _w, _h, _label, _on, _enabled, _mx, _my, _info = "") {
    var _hov = point_in_rectangle(_mx, _my, _x1, _y1, _x1 + _w, _y1 + _h);
    scr_ui_info(_hov, _info);
    var _bg = make_color_rgb(38, 38, 58);
    var _tx = c_white;
    if (!_enabled) {
        _bg = make_color_rgb(28, 28, 38);
        _tx = make_color_rgb(90, 90, 110);
    } else if (_on) {
        _bg = make_color_rgb(160, 80, 20);
        _tx = make_color_rgb(255, 160, 60);
    } else if (_hov) {
        _bg = make_color_rgb(66, 66, 98);
    }
    draw_set_color(_bg);
    draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, false);
    draw_set_color(_tx);
    draw_set_halign(fa_center);
    draw_text_l(_x1 + _w * 0.5, _y1 + 4, _label);
    draw_set_halign(fa_left);
    if (!_enabled) {
        return false;
    }
    return (_hov && mouse_check_button_pressed(mb_left));
}

/// Per-column [min, max] of the source PCM (0..255) across _w columns.
function scr_sample_wf_source(_asset, _w) {
    var _m = _asset.meta;
    var _key = string(_w) + ":" + string(_m.data_ver) + ":" + string(_m.src_len);
    if (_m.wf_src_key == _key) {
        return _m.wf_src;
    }
    var _cols = array_create(_w * 2, 128);
    var _len = _m.src_len;
    if (_len > 1 && buffer_exists(_asset.buffer)) {
        for (var _c = 0; _c < _w; _c++) {
            var _a = floor(_c * _len / _w);
            var _b = max(_a + 1, floor((_c + 1) * _len / _w));
            var _lo = 255;
            var _hi = 0;
            for (var _i = _a; _i < _b && _i < _len; _i++) {
                var _v = buffer_peek(_asset.buffer, _i, buffer_u8);
                _lo = min(_lo, _v);
                _hi = max(_hi, _v);
            }
            _cols[_c * 2]     = _lo;
            _cols[_c * 2 + 1] = _hi;
        }
    }
    _m.wf_src = _cols;
    _m.wf_src_key = _key;
    return _cols;
}

/// Per-column [min, max] of the encoded 4-bit levels across _w columns.
function scr_sample_wf_enc(_asset, _w) {
    var _m = _asset.meta;
    var _key = string(_w) + ":" + string(_m.enc_ver);
    if (_m.wf_enc_key == _key) {
        return _m.wf_enc;
    }
    var _cols = array_create(_w * 2, 8);
    var _n = _m.out_count;
    if (_n > 0) {
        for (var _c = 0; _c < _w; _c++) {
            var _a = floor(_c * _n / _w);
            var _b = max(_a + 1, floor((_c + 1) * _n / _w));
            var _lo = 15;
            var _hi = 0;
            for (var _i = _a; _i < _b && _i < _n; _i++) {
                var _v = _m.enc[_i];
                _lo = min(_lo, _v);
                _hi = max(_hi, _v);
            }
            _cols[_c * 2]     = _lo;
            _cols[_c * 2 + 1] = _hi;
        }
    }
    _m.wf_enc = _cols;
    _m.wf_enc_key = _key;
    return _cols;
}

/// "1.234 S"
function scr_sample_secs(_samples, _rate) {
    if (_rate <= 0) {
        return "0.000 S";
    }
    return string_format(_samples / _rate, 1, 3) + " S";
}

/// @function scr_sample_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my)
/// @desc Inline editor for SAMPLE assets (wide panel).
///
///   toolbar   IMPORT WAV · PLAY SOURCE · PLAY C64 · STOP · source name
///   SOURCE    full waveform; the trimmed span is lit, outside it dimmed.
///             Left-drag moves the nearer trim handle, right-click resets.
///   C64       the 4-bit levels exactly as the player will output them
///   controls  RATE · GAIN · DITHER · PACK · SID
///   stats     samples, seconds, bytes, CIA latch, clipping
function scr_sample_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _m = _asset.meta;
    if (_m.enc_dirty && _m.drag < 0) {
        scr_sample_encode(_asset);
    }
    scr_sample_preview_tick();

    var _c_lbl  = make_color_rgb(140, 150, 180);
    var _c_dim  = make_color_rgb(95, 95, 115);
    var _c_head = make_color_rgb(90, 220, 190);
    var _c_box  = make_color_rgb(14, 14, 22);
    var _c_edge = make_color_rgb(56, 56, 78);
    var _c_wave = make_color_rgb(90, 200, 240);
    var _c_c64  = make_color_rgb(200, 160, 255);
    var _c_warn = make_color_rgb(255, 160, 60);

    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);

    var _x0 = _vx1 + 14;
    var _x1 = _vx2 - 14;
    var _w  = floor(_x1 - _x0);
    var _have_src = (_m.src_len > 1);
    var _pv_pos   = scr_sample_preview_pos(_asset);
    var _pv_mode  = -1;
    if (_pv_pos >= 0) {
        _pv_mode = obj_asset_manager.sample_pv.mode;
    }

    // ===============================================================
    // TOOLBAR
    // ===============================================================
    var _ty = _cy;
    if (scr_sample_button(_x0, _ty, 100, 18, "IMPORT WAV", false, true, _mx, _my, "LOADS A WAV FILE (PCM OR FLOAT, ANY RATE, MONO/STEREO) AS THE SOURCE; RESETS THE TRIM")) {
        scr_sample_wav_import(_asset);
        _have_src = (_m.src_len > 1);
    }
    if (scr_sample_button(_x0 + 110, _ty, 110, 18, "PLAY SOURCE", (_pv_mode == 0), _have_src, _mx, _my, "PLAYS THE TRIMMED ORIGINAL SOURCE AUDIO")) {
        scr_sample_preview_play(_asset, 0);
    }
    if (scr_sample_button(_x0 + 230, _ty, 110, 18, "PLAY C64", (_pv_mode == 1), _have_src, _mx, _my, "PLAYS THE ENCODED 4-BIT C64 VERSION AS IT WILL SOUND")) {
        scr_sample_preview_play(_asset, 1);
    }
    if (scr_sample_button(_x0 + 350, _ty, 60, 18, "STOP", false, (_pv_pos >= 0), _mx, _my, "STOPS THE PREVIEW PLAYBACK")) {
        scr_sample_preview_stop();
    }
    if (_have_src) {
        draw_set_color(_c_lbl);
        draw_text_l(_x0 + 430, _ty + 4, "SOURCE: ");
        draw_set_color(c_white);
        draw_text_l(_x0 + 500, _ty + 4, _m.src_name + "   " + string(_m.src_rate) + " HZ   "
            + scr_sample_secs(_m.src_len, _m.src_rate) + "   " + string(_m.src_len) + " SAMPLES");
    } else {
        draw_set_color(_c_dim);
        draw_text_l(_x0 + 430, _ty + 4, "NO SOURCE - IMPORT A WAV FILE (PCM OR FLOAT, ANY RATE, MONO OR STEREO)");
    }

    // ===============================================================
    // SOURCE WAVEFORM + TRIM
    // ===============================================================
    var _sy1 = _ty + 40;
    var _sh  = 170;
    var _sy2 = _sy1 + _sh;
    draw_set_color(_c_head);
    draw_text_l(_x0, _sy1 - 13, "SOURCE");
    draw_set_color(_c_box);
    draw_rectangle(_x0, _sy1, _x1, _sy2, false);
    draw_set_color(_c_edge);
    draw_rectangle(_x0, _sy1, _x1, _sy2, true);
    draw_line(_x0, (_sy1 + _sy2) * 0.5, _x1, (_sy1 + _sy2) * 0.5);

    var _len = max(1, _m.src_len);
    var _tsx = _x0 + _m.trim_start / _len * _w;
    var _tex = _x0 + _m.trim_end / _len * _w;

    if (_have_src) {
        var _cols = scr_sample_wf_source(_asset, _w);
        for (var _c = 0; _c < _w; _c++) {
            var _px = _x0 + _c;
            var _yl = _sy2 - 2 - (_cols[_c * 2] / 255) * (_sh - 4);
            var _yh = _sy2 - 2 - (_cols[_c * 2 + 1] / 255) * (_sh - 4);
            if (_px < _tsx || _px > _tex) {
                draw_set_color(_c_dim);
            } else {
                draw_set_color(_c_wave);
            }
            draw_line(_px, _yl, _px, _yh - 1);
        }
        // Dim outside the trim
        draw_set_alpha(0.45);
        draw_set_color(c_black);
        if (_tsx > _x0) {
            draw_rectangle(_x0 + 1, _sy1 + 1, _tsx, _sy2 - 1, false);
        }
        if (_tex < _x1) {
            draw_rectangle(_tex, _sy1 + 1, _x1 - 1, _sy2 - 1, false);
        }
        draw_set_alpha(1);
        // Handles
        draw_set_color(c_yellow);
        draw_line_width(_tsx, _sy1, _tsx, _sy2, 2);
        draw_line_width(_tex, _sy1, _tex, _sy2, 2);
        draw_rectangle(_tsx, _sy1, _tsx + 6, _sy1 + 10, false);
        draw_rectangle(_tex - 6, _sy1, _tex, _sy1 + 10, false);

        // Playhead
        if (_pv_pos >= 0) {
            var _ph = _m.trim_start + _pv_pos * _m.src_rate;
            var _phx = _x0 + _ph / _len * _w;
            draw_set_color(c_white);
            draw_line(_phx, _sy1, _phx, _sy2);
        }

        // Trim mouse
        var _in_src = point_in_rectangle(_mx, _my, _x0, _sy1, _x1, _sy2);
        scr_ui_info(_in_src, "SOURCE WAVE: LEFT-DRAG MOVES THE NEARER TRIM HANDLE, RIGHT-CLICK RESETS THE TRIM TO ALL");
        if (_in_src && mouse_check_button_pressed(mb_left)) {
            if (abs(_mx - _tsx) <= abs(_mx - _tex)) {
                _m.drag = 0;
            } else {
                _m.drag = 1;
            }
        }
        if (_in_src && mouse_check_button_pressed(mb_right)) {
            _m.trim_start = 0;
            _m.trim_end   = _m.src_len;
            _m.enc_dirty  = true;
            global.undo_dirty = true;
        }
        if (_m.drag >= 0) {
            var _at = round(clamp((_mx - _x0) / _w, 0, 1) * _m.src_len);
            if (_m.drag == 0) {
                _m.trim_start = clamp(_at, 0, _m.trim_end - 1);
            } else {
                _m.trim_end = clamp(_at, _m.trim_start + 1, _m.src_len);
            }
            _m.enc_dirty = true;
            if (!mouse_check_button(mb_left)) {
                _m.drag = -1;
                global.undo_dirty = true;
            }
        }
    }

    // ===============================================================
    // C64 OUTPUT
    // ===============================================================
    var _ey1 = _sy2 + 30;
    var _eh  = 128;
    var _ey2 = _ey1 + _eh;
    var _pack_name = "4-BIT NIBBLES";
    if (_m.pack == 1) {
        _pack_name = "2-BIT DELTA";
    }
    draw_set_color(_c_head);
    draw_text_l(_x0, _ey1 - 13, "C64 OUTPUT   $D418 4-BIT   " + string(_m.rate) + " HZ   " + _pack_name);
    draw_set_color(_c_box);
    draw_rectangle(_x0, _ey1, _x1, _ey2, false);
    // 16 DAC levels
    draw_set_color(make_color_rgb(26, 26, 38));
    for (var _l = 0; _l < 16; _l++) {
        var _ly = _ey2 - 4 - _l * (_eh - 8) / 15;
        draw_line(_x0 + 1, _ly, _x1 - 1, _ly);
    }
    draw_set_color(_c_edge);
    draw_rectangle(_x0, _ey1, _x1, _ey2, true);
    if (_m.out_count > 0) {
        var _ecols = scr_sample_wf_enc(_asset, _w);
        draw_set_color(_c_c64);
        for (var _c = 0; _c < _w; _c++) {
            var _px = _x0 + _c;
            var _yl = _ey2 - 4 - _ecols[_c * 2] * (_eh - 8) / 15;
            var _yh = _ey2 - 4 - _ecols[_c * 2 + 1] * (_eh - 8) / 15;
            draw_line(_px, _yl + 1, _px, _yh);
        }
        if (_pv_pos >= 0) {
            var _dur = _m.out_count / max(1, _m.rate);
            var _ephx = _x0 + clamp(_pv_pos / max(0.001, _dur), 0, 1) * _w;
            draw_set_color(c_white);
            draw_line(_ephx, _ey1, _ephx, _ey2);
        }
    } else if (_m.drag >= 0) {
        draw_set_color(_c_dim);
        draw_text_l(_x0 + 10, _ey1 + 10, "RELEASE TO RE-ENCODE");
    }

    // ===============================================================
    // CONTROLS
    // ===============================================================
    var _ky = _ey2 + 16;
    var _kx = _x0;

    // RATE
    draw_set_color(_c_lbl);
    draw_text_l(_kx, _ky + 4, "RATE");
    var _rates = scr_sample_rate_presets();
    var _ri = 0;
    var _best = 1000000;
    for (var _i = 0; _i < array_length(_rates); _i++) {
        if (abs(_rates[_i] - _m.rate) < _best) {
            _best = abs(_rates[_i] - _m.rate);
            _ri = _i;
        }
    }
    if (scr_sample_button(_kx + 40, _ky, 18, 18, "<", false, (_ri > 0), _mx, _my, "LOWER PLAYBACK RATE PRESET: SMALLER DATA, LESS TREBLE")) {
        _m.rate = _rates[_ri - 1];
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_kx + 100, _ky + 4, string(_m.rate) + " HZ");
    draw_set_halign(fa_left);
    if (scr_sample_button(_kx + 142, _ky, 18, 18, ">", false, (_ri < array_length(_rates) - 1), _mx, _my, "HIGHER PLAYBACK RATE PRESET: CLEARER SOUND, MORE BYTES AND CPU")) {
        _m.rate = _rates[_ri + 1];
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }

    // GAIN
    _kx += 190;
    draw_set_color(_c_lbl);
    draw_text_l(_kx, _ky + 4, "GAIN");
    if (scr_sample_button(_kx + 40, _ky, 18, 18, "<", false, (_m.gain > 10), _mx, _my, "LOWERS THE GAIN BY 10% (MIN 10%)")) {
        _m.gain = max(10, _m.gain - 10);
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_kx + 90, _ky + 4, string(_m.gain) + "%");
    draw_set_halign(fa_left);
    if (scr_sample_button(_kx + 122, _ky, 18, 18, ">", false, (_m.gain < 400), _mx, _my, "RAISES THE GAIN BY 10% (MAX 400%); OVER 100% DRIVES IT HARDER AND CAN CLIP")) {
        _m.gain = min(400, _m.gain + 10);
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }

    // DITHER
    _kx += 170;
    draw_set_color(_c_lbl);
    draw_text_l(_kx, _ky + 4, "DITHER");
    var _dl = "OFF";
    if (_m.dither == 1) {
        _dl = "ON";
    }
    if (scr_sample_button(_kx + 56, _ky, 44, 18, _dl, (_m.dither == 1), true, _mx, _my, "TOGGLES DITHER: ADDS NOISE TO HIDE 4-BIT STEPPING ON QUIET SOUNDS")) {
        _m.dither = 1 - _m.dither;
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }

    // PACK
    _kx += 130;
    draw_set_color(_c_lbl);
    draw_text_l(_kx, _ky + 4, "PACK");
    if (scr_sample_button(_kx + 40, _ky, 70, 18, "4-BIT", (_m.pack == 0), true, _mx, _my, "PACKS TWO 4-BIT SAMPLES PER BYTE (BEST QUALITY)")) {
        _m.pack = 0;
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }
    if (scr_sample_button(_kx + 116, _ky, 110, 18, "2-BIT DELTA", (_m.pack == 1), true, _mx, _my, "PACKS 2-BIT DELTAS, FOUR PER BYTE: HALF THE SIZE, LOWER QUALITY")) {
        _m.pack = 1;
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }

    // SID
    _kx += 260;
    draw_set_color(_c_lbl);
    draw_text_l(_kx, _ky + 4, "SID");
    if (scr_sample_button(_kx + 32, _ky, 54, 18, "6581", (_m.sid_model == 0), true, _mx, _my, "TARGET THE 6581 SID: $D418 DIGIS ARE AUDIBLE ON THEIR OWN")) {
        _m.sid_model = 0;
        global.undo_dirty = true;
    }
    if (scr_sample_button(_kx + 92, _ky, 54, 18, "8580", (_m.sid_model == 1), true, _mx, _my, "TARGET THE 8580 SID: THE PLAYER ADDS THE DC BOOST DIGIS NEED")) {
        _m.sid_model = 1;
        global.undo_dirty = true;
    }

    // ── ROW 2: LOUDNESS ──
    var _ky2 = _ky + 26;
    _kx = _x0;
    draw_set_color(_c_lbl);
    draw_text_l(_kx, _ky2 + 4, "NORMALISE");
    var _nl = "OFF";
    if (_m.normalise == 1) {
        _nl = "ON";
    }
    if (scr_sample_button(_kx + 84, _ky2, 44, 18, _nl, (_m.normalise == 1), true, _mx, _my, "TOGGLES NORMALISE: SCALES THE TRIM TO FILL ALL 16 OUTPUT LEVELS")) {
        _m.normalise = 1 - _m.normalise;
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }
    _kx += 150;
    draw_set_color(_c_lbl);
    draw_text_l(_kx, _ky2 + 4, "COMPRESS");
    if (scr_sample_button(_kx + 76, _ky2, 18, 18, "<", false, (_m.compress > 0), _mx, _my, "LOWERS COMPRESSION BY 10% (LESS LIFT OF QUIET PARTS)")) {
        _m.compress = max(0, _m.compress - 10);
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_kx + 122, _ky2 + 4, string(_m.compress) + "%");
    draw_set_halign(fa_left);
    if (scr_sample_button(_kx + 150, _ky2, 18, 18, ">", false, (_m.compress < 100), _mx, _my, "RAISES COMPRESSION BY 10% (LIFTS QUIET PARTS MORE)")) {
        _m.compress = min(100, _m.compress + 10);
        _m.enc_dirty = true;
        global.undo_dirty = true;
    }
    draw_set_color(_c_dim);
    draw_text_l(_kx + 190, _ky2 + 4, "NORMALISE FILLS ALL 16 LEVELS FROM THE TRIM.  COMPRESS LIFTS THE QUIET PARTS.  GAIN > 100% DRIVES IT HARDER (CLIPS).");

    // ===============================================================
    // STATS
    // ===============================================================
    var _st = _ky2 + 34;
    var _latch = scr_sample_cia_latch(_m.rate);
    var _lhex = string_upper(decimal_to_hex(_latch));
    while (string_length(_lhex) < 4) {
        _lhex = "0" + _lhex;
    }
    var _actual = SAMPLE_PAL_CLOCK / (_latch + 1);

    draw_set_color(_c_lbl);
    draw_text_l(_x0, _st, "OUTPUT");
    draw_set_color(c_white);
    draw_text_l(_x0 + 80, _st, string(_m.out_count) + " SAMPLES   "
        + scr_sample_secs(_m.out_count, _m.rate) + "   " + string(_m.out_bytes) + " BYTES");
    draw_set_color(_c_lbl);
    draw_text_l(_x0 + 460, _st, "CIA LATCH");
    draw_set_color(c_white);
    draw_text_l(_x0 + 550, _st, "$" + _lhex + "   " + string_format(_actual, 1, 1) + " HZ ON PAL");

    _st += 18;
    draw_set_color(_c_lbl);
    draw_text_l(_x0, _st, "TRIM");
    draw_set_color(c_white);
    var _trim_txt = "--";
    if (_have_src) {
        _trim_txt = scr_sample_secs(_m.trim_start, _m.src_rate) + "  TO  " + scr_sample_secs(_m.trim_end, _m.src_rate);
    }
    draw_text_l(_x0 + 80, _st, _trim_txt);
    if (_m.out_count > 0 && _m.clip_count > 0) {
        var _pct = 100 * _m.clip_count / _m.out_count;
        draw_set_color(_c_warn);
        draw_text_l(_x0 + 460, _st, "CLIPPING " + string_format(_pct, 1, 1) + "% OF SAMPLES - LOWER THE GAIN");
    }

    _st += 18;
    draw_set_color(_c_dim);
    var _sid_note = "6581: $D418 DIGIS ARE AUDIBLE ON THEIR OWN; THE TUNE'S DIGI BOOST MAKES THEM LOUDER.";
    if (_m.sid_model == 1) {
        _sid_note = "8580: $D418 DIGIS NEED THE TUNE'S DIGI BOOST (MUSIC MAKER > SAMPLES PANEL > BOOST).";
    }
    draw_text_l(_x0, _st, _sid_note);
    _st += 14;
    draw_text_l(_x0, _st, "LEFT-DRAG IN SOURCE MOVES THE NEARER TRIM HANDLE   RIGHT-CLICK RESETS THE TRIM");

    // ===============================================================
    // WARNING LINE
    // ===============================================================
    if (_m.warn_timer > 0) {
        _m.warn_timer -= 1;
        draw_set_color(_c_warn);
        draw_text_l(_x0, _st + 22, _m.warn_msg);
    }
}
