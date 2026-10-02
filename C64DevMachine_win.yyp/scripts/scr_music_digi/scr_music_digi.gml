/// MUSIC MAKER DIGI TRACK — the "4th voice".
///
/// DATA (asset meta, seeded in scr_sound_editor_create):
///   digi_rate      playback rate for every digi in this asset, Hz. One rate
///                  means one CIA timer value for the whole tune.
///   digi_samples   16 slots of SAMPLE asset names ("" = empty). A digi step's
///                  sample number is a slot index.
///   digi_patterns  separate pool from patterns[], so voice pattern indices
///                  never shift. { name, pattern_len, steps[] }, each step
///                  { smp, vol }:
///                    smp  -1 empty (sample keeps playing), -2 OFF (cut),
///                         0-15 trigger that slot
///                    vol  0-3, 3 = full (0 = 1/4, 1 = 1/2, 2 = 3/4 amplitude)
///   order rows     dg = digi pattern index, -1 = none.
///
/// TIMING: the digi track follows the shared row clock (the compiled player
/// supports nothing else; the editor preview follows voice 1 under TIMING: PER
/// VOICE). It does not count towards an order row's length: a shorter digi
/// pattern simply ends (REPEAT does not wrap it), a longer one is cut at the
/// row's length.

#macro DIGI_SLOTS     16
#macro DIGI_SMP_EMPTY -1
#macro DIGI_SMP_OFF   -2

/// Brings every order row and digi pattern up to the current shape. Rows are
/// created in several places in the editor, so this runs every frame the
/// Music Maker is open — it is a handful of struct reads.
function scr_digi_ensure(_m) {
    while (array_length(_m.digi_samples) < DIGI_SLOTS) {
        array_push(_m.digi_samples, "");
    }
    for (var _si = 0; _si < array_length(_m.songs); _si++) {
        var _ord = _m.songs[_si].order;
        for (var _ri = 0; _ri < array_length(_ord); _ri++) {
            if (is_undefined(_ord[_ri][$ "dg"])) {
                _ord[_ri].dg = -1;
            }
            if (_ord[_ri].dg >= array_length(_m.digi_patterns)) {
                _ord[_ri].dg = -1;
            }
        }
    }
    for (var _pi = 0; _pi < array_length(_m.digi_patterns); _pi++) {
        scr_digi_ensure_steps(_m.digi_patterns[_pi]);
    }
}

/// Grows / truncates a digi pattern's steps to its length.
function scr_digi_ensure_steps(_pat) {
    _pat.pattern_len = clamp(real(_pat.pattern_len), 4, 128);
    while (array_length(_pat.steps) < _pat.pattern_len) {
        array_push(_pat.steps, { smp: DIGI_SMP_EMPTY, vol: 3 });
    }
    if (array_length(_pat.steps) > _pat.pattern_len) {
        array_resize(_pat.steps, _pat.pattern_len);
    }
}

/// Appends a new empty digi pattern; returns its index, or -1 if the pool is full.
function scr_digi_pattern_new(_m, _len) {
    if (array_length(_m.digi_patterns) >= 64) {
        return -1;
    }
    var _n = array_length(_m.digi_patterns);
    var _name = "DIGI " + string(_n);
    if (_n < 10) {
        _name = "DIGI 0" + string(_n);
    }
    var _pat = { name: _name, pattern_len: _len, steps: [] };
    scr_digi_ensure_steps(_pat);
    array_push(_m.digi_patterns, _pat);
    return _n;
}

/// SAMPLE asset by name, or undefined.
function scr_digi_find_sample(_name) {
    if (_name == "" || !instance_exists(obj_asset_manager)) {
        return undefined;
    }
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "SAMPLE" && _a.name == _name) {
            return _a;
        }
    }
    return undefined;
}

/// Names of every SAMPLE asset in the project.
function scr_digi_sample_names() {
    var _out = [];
    if (!instance_exists(obj_asset_manager)) {
        return _out;
    }
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "SAMPLE") {
            array_push(_out, _a.name);
        }
    }
    return _out;
}

// ═══════════════════════════ PREVIEW AUDIO ═══════════════════════════

/// Buffer sound of _asset encoded at _rate, as the $D418 DAC outputs it.
/// Cached on the SAMPLE asset and rebuilt when any setting that changes the
/// bytes changes. Returns -1 when the sample has no audio.
function scr_digi_sample_sound(_asset, _rate) {
    var _sm = _asset.meta;
    var _key = string(_rate) + ":" + string(_sm.data_ver) + ":" + string(_sm.gain) + ":"
             + string(_sm.dither) + ":" + string(_sm.pack) + ":"
             + string(_sm.trim_start) + ":" + string(_sm.trim_end);
    if (_sm.pv_dg_key == _key) {
        return _sm.pv_dg_snd;
    }
    scr_digi_free_sample_sound(_asset);
    _sm.pv_dg_key = _key;

    var _r = scr_sample_encode_at(_asset, _rate, _sm.pack);
    var _cnt = array_length(_r.enc);
    if (_cnt <= 0) {
        return -1;
    }
    var _out_rate = SAMPLE_PV_RATE;
    var _n = floor(_cnt * _out_rate / _rate);
    if (_n <= 0) {
        return -1;
    }
    var _buf = buffer_create(_n * 2, buffer_fixed, 2);
    for (var _i = 0; _i < _n; _i++) {
        var _k = min(_cnt - 1, floor(_i * _rate / _out_rate));
        var _v = (_r.enc[_k] - 7.5) / 7.5;
        buffer_write(_buf, buffer_s16, round(_v * 24000));
    }
    _sm.pv_dg_buf = _buf;
    _sm.pv_dg_snd = audio_create_buffer_sound(_buf, buffer_s16, _out_rate, 0, _n * 2, audio_mono);
    return _sm.pv_dg_snd;
}

/// Releases a SAMPLE asset's cached digi sound (stopping any instance of it).
function scr_digi_free_sample_sound(_asset) {
    var _sm = _asset.meta;
    if (_sm.pv_dg_snd != -1) {
        audio_stop_sound(_sm.pv_dg_snd);
        audio_free_buffer_sound(_sm.pv_dg_snd);
    }
    if (_sm.pv_dg_buf != -1) {
        buffer_delete(_sm.pv_dg_buf);
    }
    _sm.pv_dg_snd = -1;
    _sm.pv_dg_buf = -1;
    _sm.pv_dg_key = "";
}

/// Cuts the digi channel.
function scr_digi_stop(_m) {
    if (_m.dg_inst != -1) {
        if (audio_is_playing(_m.dg_inst)) {
            audio_stop_sound(_m.dg_inst);
        }
    }
    _m.dg_inst = -1;
}

/// Acts on one digi step: trigger, cut, or nothing. Monophonic, like the
/// hardware: a new trigger cuts whatever was playing.
function scr_digi_play_step(_m, _st) {
    if (_st.smp == DIGI_SMP_OFF) {
        scr_digi_stop(_m);
        return;
    }
    if (_st.smp < 0 || _st.smp >= DIGI_SLOTS) {
        return;
    }
    var _a = scr_digi_find_sample(_m.digi_samples[_st.smp]);
    if (is_undefined(_a)) {
        return;
    }
    var _snd = scr_digi_sample_sound(_a, _m.digi_rate);
    if (_snd == -1) {
        return;
    }
    scr_digi_stop(_m);
    _m.dg_inst = audio_play_sound(_snd, 10, false);
    var _gains = [0.25, 0.5, 0.75, 1.0];
    audio_sound_gain(_m.dg_inst, _gains[clamp(_st.vol, 0, 3)], 0);
}

/// Follows playback and fires digi steps as their rows come up. Called once a
/// frame after the editor's playback block has settled the position.
function scr_digi_preview_tick(_m, _cur_song, _voice_pos) {
    var _active = (_m.playing || _m.song_playing);
    if (!_active) {
        if (_m.dg_last_key != -1) {
            scr_digi_stop(_m);
            _m.dg_last_key = -1;
        }
        return;
    }
    var _ord  = _m.preview_display_order;
    var _step = _m.preview_display_step;
    if (is_array(_voice_pos)) {
        _ord  = _voice_pos[0][0];
        _step = _voice_pos[0][1];
    }
    if (_ord < 0 || _ord >= array_length(_cur_song.order) || _step < 0) {
        return;
    }
    var _key = _ord * 1000 + _step;
    if (_key == _m.dg_last_key) {
        return;
    }
    _m.dg_last_key = _key;

    var _row = _cur_song.order[_ord];
    if (_row.dg < 0 || _row.dg >= array_length(_m.digi_patterns)) {
        return;
    }
    var _pat = _m.digi_patterns[_row.dg];
    // Like the C64 player: past the digi pattern's own length there is nothing
    // (REPEAT does not wrap the digi track).
    if (_step >= _pat.pattern_len) {
        return;
    }
    scr_digi_play_step(_m, _pat.steps[_step]);
}

// ═══════════════════════════ GRID LANE ═══════════════════════════

/// Draws the digi lane header (above the grid) and its cells, and handles the
/// mouse. Returns true when a digi cell was clicked this frame (the caller
/// commits any open voice-cell edit).
///   _hl_row  row to light as playing, or -1
function scr_digi_lane(_m, _order_row, _x, _gy0, _w, _row_h, _vis, _grid_len, _txt_scale, _hl_row, _mx, _my) {
    var _clicked = false;
    var _pat = noone;
    if (_order_row.dg >= 0 && _order_row.dg < array_length(_m.digi_patterns)) {
        _pat = _m.digi_patterns[_order_row.dg];
    }
    var _c_lane = make_color_rgb(255, 130, 170);
    var _c_btn  = make_color_rgb(60, 130, 150);

    // ── HEADER ── row 1: length stepper (or NEW) + "DIGI"; row 2: SAMPLES button.
    draw_set_font_l(fnt_c64_tiny);
    var _by1 = _gy0 - 22;
    var _by2 = _gy0 - 5;
    var _bhov = point_in_rectangle(_mx, _my, _x, _by1, _x + _w, _by2);
    var _bcol = make_color_rgb(120, 40, 80);
    if (_bhov || _m.dg_slots_open) {
        _bcol = make_color_rgb(190, 70, 120);
    }
    draw_set_color(_bcol);
    draw_rectangle(_x, _by1, _x + _w, _by2, false);
    draw_set_color(_c_lane);
    draw_rectangle(_x, _by1, _x + _w, _by2, true);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_x + _w * 0.5, _by1 + 4, "SAMPLES");
    draw_set_halign(fa_left);
    if (_bhov && mouse_check_button_pressed(mb_left)) {
        _m.dg_slots_open = !_m.dg_slots_open;
    }

    draw_set_font_l(fnt_c64_pico);
    var _hy = _gy0 - 34;
    if (_pat != noone) {
        var _lx = _x;
        var _lhov = point_in_rectangle(_mx, _my, _lx, _hy - 4, _lx + 12, _hy + 10);
        draw_set_color(_c_btn);
        if (_lhov) {
            draw_set_color(c_aqua);
        }
        draw_text_l(_lx, _hy, "<");
        if (_lhov && mouse_check_button_pressed(mb_left)) {
            _pat.pattern_len = clamp(_pat.pattern_len - 4, 4, 128);
            scr_digi_ensure_steps(_pat);
            global.undo_dirty = true;
        }
        draw_set_color(c_white);
        draw_text_l(_lx + 12, _hy, string(_pat.pattern_len));
        var _rx = _lx + 34;
        var _rhov = point_in_rectangle(_mx, _my, _rx, _hy - 4, _rx + 12, _hy + 10);
        draw_set_color(_c_btn);
        if (_rhov) {
            draw_set_color(c_aqua);
        }
        draw_text_l(_rx, _hy, ">");
        if (_rhov && mouse_check_button_pressed(mb_left)) {
            _pat.pattern_len = clamp(_pat.pattern_len + 4, 4, 128);
            scr_digi_ensure_steps(_pat);
            global.undo_dirty = true;
        }
    } else {
        // NEW: make a digi pattern and put it on the selected order row.
        var _nx = _x;
        var _nhov = point_in_rectangle(_mx, _my, _nx, _hy - 4, _nx + 34, _hy + 10);
        draw_set_color(_c_btn);
        if (_nhov) {
            draw_set_color(c_aqua);
        }
        draw_text_l(_nx, _hy, "NEW");
        if (_nhov && mouse_check_button_pressed(mb_left)) {
            var _np = scr_digi_pattern_new(_m, max(4, min(128, _grid_len)));
            if (_np >= 0) {
                _order_row.dg = _np;
                global.undo_dirty = true;
            }
        }
    }
    draw_set_color(_c_lane);
    draw_set_halign(fa_right);
    draw_text_l(_x + _w, _hy, "DIGI");
    draw_set_halign(fa_left);
    draw_set_font_l(fnt_c64_tiny);

    // ── CELLS ──
    var _press = mouse_check_button_pressed(mb_left);
    var _in_lane = false;
    for (var _r = 0; _r < _vis; _r++) {
        var _row = _r + _m.list_scroll;
        if (_row >= _grid_len) {
            break;
        }
        var _ry = _gy0 + _r * _row_h;
        var _x2 = _x + _w;
        var _hov = point_in_rectangle(_mx, _my, _x, _ry, _x2, _ry + _row_h);
        if (_hov) {
            _in_lane = true;
        }

        if (_pat == noone) {
            draw_set_color(make_color_rgb(26, 22, 26));
            draw_rectangle(_x, _ry, _x2, _ry + _row_h, false);
            draw_set_color(make_color_rgb(110, 90, 100));
            draw_text_transformed_l(_x + 8, _ry + 8, "--", _txt_scale, _txt_scale, 0);
        } else if (_row >= _pat.pattern_len) {
            draw_set_color(make_color_rgb(18, 18, 24));
            draw_rectangle(_x, _ry, _x2, _ry + _row_h, false);
        } else {
            var _st = _pat.steps[_row];
            if (_hl_row == _row) {
                draw_set_color(make_color_rgb(40, 100, 60));
                draw_set_alpha(0.5);
                draw_rectangle(_x, _ry, _x2, _ry + _row_h, false);
                draw_set_alpha(1.0);
            }
            if (_st.smp >= 0) {
                var _s_str = string(_st.smp);
                if (_st.smp < 10) {
                    _s_str = "0" + _s_str;
                }
                var _name = _m.digi_samples[_st.smp];
                draw_set_color(_c_lane);
                if (is_undefined(scr_digi_find_sample(_name))) {
                    draw_set_color(make_color_rgb(200, 90, 70));   // empty / missing slot
                }
                draw_text_transformed_l(_x + 8, _ry + 6, _s_str, _txt_scale, _txt_scale, 0);
                draw_set_color(make_color_rgb(150, 120, 150));
                draw_text_transformed_l(_x + 64, _ry + 6, string(_st.vol), _txt_scale, _txt_scale, 0);
            } else if (_st.smp == DIGI_SMP_OFF) {
                draw_set_color(make_color_rgb(230, 120, 90));
                draw_text_transformed_l(_x + 8, _ry + 6, "OFF", _txt_scale, _txt_scale, 0);
            } else {
                draw_set_color(make_color_rgb(70, 60, 80));
                draw_text_transformed_l(_x + 8, _ry + 6, "..", _txt_scale, _txt_scale, 0);
            }
            if (_hov && mouse_check_button_pressed(mb_right)) {
                _st.smp = DIGI_SMP_EMPTY;
                _st.vol = 3;
                global.undo_dirty = true;
            }
        }
        if (_m.dg_focus && _m.dg_sel_step == _row) {
            draw_set_color(c_white);
            draw_rectangle(_x, _ry, _x2, _ry + _row_h, true);
        }
        if (_hov && _press) {
            _m.dg_focus    = true;
            _m.dg_sel_step = _row;
            _m.dg_type_step = -1;
            _clicked = true;
        }
    }
    // Any other click takes focus away from the lane. Clicks inside the slots
    // panel never reach here (the editor hides the mouse from everything
    // under it).
    if (_press && !_in_lane) {
        _m.dg_focus = false;
    }
    _m.dg_sel_step = clamp(_m.dg_sel_step, 0, max(0, _grid_len - 1));
    return _clicked;
}

/// Keyboard for the focused digi cell.
///   0-9           sample slot (two digits typed quickly = 10-15)
///   O             OFF        Del / Backspace / .  clear
///   [ ]           volume -/+ Up / Down  move      Esc  leave the lane
/// Typing into an order row with no digi pattern makes one first.
function scr_digi_keys(_m, _order_row, _grid_len, _vis) {
    keyboard_string = "";
    if (keyboard_check_pressed(vk_escape)) {
        _m.dg_focus = false;
        return;
    }
    if (keyboard_check_pressed(vk_up)) {
        _m.dg_sel_step = max(0, _m.dg_sel_step - 1);
        _m.dg_type_step = -1;
    }
    if (keyboard_check_pressed(vk_down)) {
        _m.dg_sel_step = min(_grid_len - 1, _m.dg_sel_step + 1);
        _m.dg_type_step = -1;
    }
    if (_m.dg_sel_step < _m.list_scroll) {
        _m.list_scroll = _m.dg_sel_step;
    }
    if (_m.dg_sel_step >= _m.list_scroll + _vis) {
        _m.list_scroll = _m.dg_sel_step - _vis + 1;
    }

    var _digit = -1;
    for (var _d = 0; _d <= 9; _d++) {
        if (keyboard_check_pressed(ord(string(_d))) || keyboard_check_pressed(vk_numpad0 + _d)) {
            _digit = _d;
        }
    }
    var _want_off   = keyboard_check_pressed(ord("O"));
    var _want_clear = keyboard_check_pressed(vk_delete) || keyboard_check_pressed(vk_backspace)
                   || keyboard_check_pressed(vk_decimal) || keyboard_check_pressed(0xBE);
    var _vol_dn = keyboard_check_pressed(0xDB);   // '['
    var _vol_up = keyboard_check_pressed(0xDD);   // ']'
    if (_digit < 0 && !_want_off && !_want_clear && !_vol_dn && !_vol_up) {
        return;
    }

    if (_order_row.dg < 0 || _order_row.dg >= array_length(_m.digi_patterns)) {
        if (_digit < 0 && !_want_off) {
            return;
        }
        var _np = scr_digi_pattern_new(_m, max(4, min(128, _grid_len)));
        if (_np < 0) {
            return;
        }
        _order_row.dg = _np;
    }
    var _pat = _m.digi_patterns[_order_row.dg];
    if (_m.dg_sel_step >= _pat.pattern_len) {
        return;
    }
    var _st = _pat.steps[_m.dg_sel_step];

    if (_digit >= 0) {
        var _two = (_m.dg_type_step == _m.dg_sel_step && (current_time - _m.dg_type_time) < 800
                 && _st.smp == 1);
        if (_two && _digit <= 5) {
            _st.smp = 10 + _digit;
            _m.dg_type_step = -1;
        } else {
            _st.smp = _digit;
            _m.dg_type_step = _m.dg_sel_step;
            _m.dg_type_time = current_time;
        }
    }
    if (_want_off) {
        _st.smp = DIGI_SMP_OFF;
    }
    if (_want_clear) {
        _st.smp = DIGI_SMP_EMPTY;
        _st.vol = 3;
    }
    if (_vol_dn) {
        _st.vol = max(0, _st.vol - 1);
    }
    if (_vol_up) {
        _st.vol = min(3, _st.vol + 1);
    }
    if (_digit >= 0 || _want_off) {
        // Audition what was typed, as a tracker does.
        scr_digi_play_step(_m, _st);
    }
    global.undo_dirty = true;
}

// ═══════════════════════════ SAMPLE SLOTS PANEL ═══════════════════════════

/// Panel rect for this frame, computed from the lane position. The editor
/// uses last frame's rect to hide the mouse from controls under the panel.
function scr_digi_slots_rect(_lane_x, _lane_w, _gy0) {
    var _w = 330;
    var _h = 48 + DIGI_SLOTS * 20 + 58;
    var _x1 = _lane_x + _lane_w - _w;
    var _y1 = _gy0 - 2;    // just under the SAMPLES button
    return [_x1, _y1, _x1 + _w, _y1 + _h];
}

/// Slot assignments + digi rate. Left-click a slot cycles through the
/// project's SAMPLE assets, right-click empties it, the play button auditions.
function scr_digi_slots_panel(_m, _rect, _mx, _my) {
    var _x1 = _rect[0];
    var _y1 = _rect[1];
    var _x2 = _rect[2];
    var _y2 = _rect[3];
    draw_set_color(make_color_rgb(16, 14, 24));
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_color(make_color_rgb(255, 130, 170));
    draw_rectangle(_x1, _y1, _x2, _y2, true);
    draw_set_font_l(fnt_c64_tiny);

    draw_text_l(_x1 + 10, _y1 + 8, "DIGI SAMPLES");
    var _cx = _x2 - 22;
    var _chov = point_in_rectangle(_mx, _my, _cx, _y1 + 4, _cx + 16, _y1 + 20);
    draw_set_color(c_ltgray);
    if (_chov) {
        draw_set_color(c_white);
    }
    draw_text_l(_cx + 3, _y1 + 8, "X");
    if (_chov && mouse_check_button_pressed(mb_left)) {
        _m.dg_slots_open = false;
    }

    // RATE
    var _ry = _y1 + 26;
    draw_set_color(make_color_rgb(140, 150, 180));
    draw_text_l(_x1 + 10, _ry, "RATE");
    var _rates = scr_sample_rate_presets();
    var _ri = 0;
    var _best = 1000000;
    for (var _i = 0; _i < array_length(_rates); _i++) {
        if (abs(_rates[_i] - _m.digi_rate) < _best) {
            _best = abs(_rates[_i] - _m.digi_rate);
            _ri = _i;
        }
    }
    if (scr_sample_button(_x1 + 60, _ry - 4, 18, 16, "<", false, (_ri > 0), _mx, _my)) {
        _m.digi_rate = _rates[_ri - 1];
        global.undo_dirty = true;
    }
    draw_set_color(c_white);
    draw_text_l(_x1 + 86, _ry, string(_m.digi_rate) + " HZ");
    if (scr_sample_button(_x1 + 160, _ry - 4, 18, 16, ">", false, (_ri < array_length(_rates) - 1), _mx, _my)) {
        _m.digi_rate = _rates[_ri + 1];
        global.undo_dirty = true;
    }
    draw_set_color(make_color_rgb(95, 95, 115));
    draw_text_l(_x1 + 190, _ry, "ONE RATE PER TUNE");

    // SLOTS
    var _names = scr_digi_sample_names();
    for (var _s = 0; _s < DIGI_SLOTS; _s++) {
        var _sy = _y1 + 48 + _s * 20;
        var _num = string(_s);
        if (_s < 10) {
            _num = "0" + _num;
        }
        draw_set_color(make_color_rgb(255, 130, 170));
        draw_text_l(_x1 + 10, _sy + 3, _num);

        var _bx1 = _x1 + 36;
        var _bx2 = _x2 - 40;
        var _hov = point_in_rectangle(_mx, _my, _bx1, _sy, _bx2, _sy + 17);
        draw_set_color(make_color_rgb(30, 28, 44));
        if (_hov) {
            draw_set_color(make_color_rgb(56, 50, 80));
        }
        draw_rectangle(_bx1, _sy, _bx2, _sy + 17, false);
        var _nm = _m.digi_samples[_s];
        var _a = scr_digi_find_sample(_nm);
        if (_nm == "") {
            draw_set_color(make_color_rgb(90, 90, 110));
            draw_text_l(_bx1 + 6, _sy + 3, "-- EMPTY --");
        } else if (is_undefined(_a)) {
            draw_set_color(make_color_rgb(220, 100, 80));
            draw_text_l(_bx1 + 6, _sy + 3, _nm + "  (MISSING)");
        } else {
            draw_set_color(c_white);
            var _cnt = scr_digi_sample_count(_a, _m.digi_rate);
            var _bytes = ceil(_cnt / 2);
            if (_a.meta.pack == 1) {
                _bytes = ceil(_cnt / 4);
            }
            var _info = _nm + "   " + scr_sample_secs(_cnt, _m.digi_rate) + "   " + string(_bytes) + " B";
            draw_text_l(_bx1 + 6, _sy + 3, _info);
        }
        if (_hov && mouse_check_button_pressed(mb_left)) {
            // Cycle: empty -> first sample -> ... -> last -> empty
            var _next = "";
            if (array_length(_names) > 0) {
                var _at = -1;
                for (var _ni = 0; _ni < array_length(_names); _ni++) {
                    if (_names[_ni] == _nm) {
                        _at = _ni;
                    }
                }
                if (_at + 1 < array_length(_names)) {
                    _next = _names[_at + 1];
                }
            }
            _m.digi_samples[_s] = _next;
            global.undo_dirty = true;
        }
        if (_hov && mouse_check_button_pressed(mb_right)) {
            _m.digi_samples[_s] = "";
            global.undo_dirty = true;
        }
        if (!is_undefined(_a)) {
            if (scr_sample_button(_x2 - 34, _sy, 24, 17, ">", false, true, _mx, _my)) {
                scr_digi_play_step(_m, { smp: _s, vol: 3 });
            }
        }
    }
    draw_set_color(make_color_rgb(95, 95, 115));
    draw_text_l(_x1 + 10, _y2 - 50, "CLICK: NEXT SAMPLE   RIGHT-CLICK: EMPTY");
    // Each sample costs one NMI; the estimate is for while a digi plays.
    var _cpu = round(_m.digi_rate * DIGI_NMI_CYCLES / SAMPLE_PAL_CLOCK * 100);
    draw_set_color(make_color_rgb(140, 150, 180));
    if (_cpu > 45) {
        draw_set_color(make_color_rgb(255, 160, 60));
    }
    draw_text_l(_x1 + 10, _y2 - 34, "CPU WHILE A DIGI PLAYS: ~" + string(_cpu) + "%  (NMI, CIA2 TIMER A)");
    if (_m.free_voices) {
        draw_set_color(make_color_rgb(255, 120, 90));
        draw_text_l(_x1 + 10, _y2 - 18, "TIMING: PER VOICE - DIGI TRACK NOT COMPILED");
    }
}

/// How many C64 samples _asset becomes at _rate (no encode needed).
function scr_digi_sample_count(_asset, _rate) {
    var _sm = _asset.meta;
    if (_sm.src_len <= 1 || _sm.src_rate <= 0) {
        return 0;
    }
    return max(0, floor((_sm.trim_end - _sm.trim_start) * _rate / _sm.src_rate));
}
