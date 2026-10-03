/// Music Maker piano, along the bottom of the window.
///   SPLIT (default) — three 2-octave keyboards, one per voice, starting at the
///                     current OCTAVE. A click writes into that voice.
///   FULL            — one 6-octave keyboard (C-1 to B-6). A click writes into
///                     the voice the marker is in.
/// Holding the right mouse button plays the selected instrument; sliding to
/// another key while held plays that one, and letting go stops it. A left
/// click writes the note at the marker row (with the selected instrument) and
/// drops a row, like typing it. While a song or pattern plays, the keys each
/// voice is sounding light up in that voice's colour (the SID chip on show).

/// Note index (0 = C-0 ... 95 = B-7) → the pattern's note text ("C-4", "C#4").
function scr_sound_editor_piano_name(_idx) {
    var _names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    var _nm = _names[_idx mod 12];
    var _oc = string(_idx div 12);
    if (string_length(_nm) == 2) {
        return _nm + _oc;
    }
    return _nm + "-" + _oc;
}

/// Draws one keyboard of _n_oct octaves from octave _oct0 inside the box, and
/// returns the note index under the mouse (-1 for none). _mark = a note index
/// to show as the marker cell's note (-1 for none). _lit = playing notes as
/// [note, colour] pairs.
function scr_sound_editor_piano_keys(_x0, _y0, _x1, _y1, _oct0, _n_oct, _mx, _my, _mark, _lit) {
    var _n_white = _n_oct * 7;
    var _ww = (_x1 - _x0) / _n_white;
    var _bw = _ww * 0.62;
    var _bh = (_y1 - _y0) * 0.6;
    var _white_semi = [0, 2, 4, 5, 7, 9, 11];
    var _black_after = [0, 1, 3, 4, 5];          // white index a black key follows
    var _black_semi  = [1, 3, 6, 8, 10];
    var _hover = -1;

    // A playing note in an octave this keyboard doesn't show still lights its
    // note letter, in the nearest shown octave, with its real octave written
    // on the key - so every voice's note is always visible during playback.
    var _lit_in = [];
    for (var _li = 0; _li < array_length(_lit); _li++) {
        var _ln = _lit[_li][0];
        var _lo = _ln div 12;
        var _fo = clamp(_lo, _oct0, _oct0 + _n_oct - 1);
        array_push(_lit_in, [_fo * 12 + (_ln mod 12), _lit[_li][1], _lo]);
    }
    _lit = _lit_in;

    // Black keys win the hover where they overlap the whites.
    for (var _o = 0; _o < _n_oct && _hover < 0; _o++) {
        for (var _b = 0; _b < 5; _b++) {
            var _bx = _x0 + (_o * 7 + _black_after[_b] + 1) * _ww - _bw * 0.5;
            if (point_in_rectangle(_mx, _my, _bx, _y0, _bx + _bw, _y0 + _bh)) {
                _hover = (_oct0 + _o) * 12 + _black_semi[_b];
                break;
            }
        }
    }
    if (_hover < 0 && point_in_rectangle(_mx, _my, _x0, _y0, _x1 - 1, _y1)) {
        var _wi = clamp(floor((_mx - _x0) / _ww), 0, _n_white - 1);
        _hover = (_oct0 + (_wi div 7)) * 12 + _white_semi[_wi mod 7];
    }

    // whites
    for (var _w = 0; _w < _n_white; _w++) {
        var _wx = _x0 + _w * _ww;
        var _wn = (_oct0 + (_w div 7)) * 12 + _white_semi[_w mod 7];
        var _wlit = scr_sound_editor_piano_lit(_lit, _wn);
        if (_wn == _hover) {
            draw_set_color(make_color_rgb(255, 230, 120));
        } else if (_wlit != -1) {
            draw_set_color(_wlit);
        } else if (_wn == _mark) {
            draw_set_color(make_color_rgb(150, 200, 255));
        } else {
            draw_set_color(make_color_rgb(215, 215, 225));
        }
        draw_rectangle(_wx, _y0, _wx + _ww - 1, _y1, false);
        draw_set_color(make_color_rgb(40, 40, 50));
        draw_rectangle(_wx, _y0, _wx + _ww - 1, _y1, true);
        var _wro = scr_sound_editor_piano_lit_oct(_lit, _wn);
        if (_wro != -1 && _wro != (_wn div 12)) {
            // folded in from another octave: show where it really is
            draw_set_color(c_black);
            draw_set_halign(fa_center);
            draw_text_l(_wx + _ww * 0.5, _y0 + _bh + 2, string(_wro));
            draw_set_halign(fa_left);
        }
        if ((_w mod 7) == 0) {
            draw_set_color(make_color_rgb(90, 90, 110));
            draw_text_l(_wx + 3, _y1 - 13, "C" + string(_oct0 + (_w div 7)));
        }
    }
    // blacks
    for (var _o2 = 0; _o2 < _n_oct; _o2++) {
        for (var _b2 = 0; _b2 < 5; _b2++) {
            var _bx2 = _x0 + (_o2 * 7 + _black_after[_b2] + 1) * _ww - _bw * 0.5;
            var _bn = (_oct0 + _o2) * 12 + _black_semi[_b2];
            var _blit = scr_sound_editor_piano_lit(_lit, _bn);
            if (_bn == _hover) {
                draw_set_color(make_color_rgb(230, 180, 60));
            } else if (_blit != -1) {
                draw_set_color(merge_color(_blit, c_black, 0.25));
            } else if (_bn == _mark) {
                draw_set_color(make_color_rgb(70, 120, 200));
            } else {
                draw_set_color(make_color_rgb(25, 25, 32));
            }
            draw_rectangle(_bx2, _y0, _bx2 + _bw, _y0 + _bh, false);
            var _bro = scr_sound_editor_piano_lit_oct(_lit, _bn);
            if (_bro != -1 && _bro != (_bn div 12)) {
                draw_set_color(c_white);
                draw_set_halign(fa_center);
                draw_text_l(_bx2 + _bw * 0.5, _y0 + _bh - 14, string(_bro));
                draw_set_halign(fa_left);
            }
        }
    }
    return _hover;
}

/// Real octave of the playing note lit on key _note (after folding), or -1.
function scr_sound_editor_piano_lit_oct(_lit, _note) {
    for (var _i = 0; _i < array_length(_lit); _i++) {
        if (_lit[_i][0] == _note && array_length(_lit[_i]) > 2) {
            return _lit[_i][2];
        }
    }
    return -1;
}

/// Colour of a playing note on the keyboard, or -1.
function scr_sound_editor_piano_lit(_lit, _note) {
    for (var _i = 0; _i < array_length(_lit); _i++) {
        if (_lit[_i][0] == _note) return _lit[_i][1];
    }
    return -1;
}

/// Notes the three shown voices are sounding right now (-1 = silent), read
/// from the same frame the pattern highlight shows. Muted voices stay dark.
function scr_sound_editor_piano_playing(_m) {
    var _out = [-1, -1, -1];
    var _st = global.sid64_stream;
    if (!_st.active || _st.sim.m != _m || _st.frames_rendered <= 0) return _out;
    var _frame = clamp(floor((get_timer() - _st.start_us) / SID64_FRAME_US), 0, _st.frames_rendered - 1);
    var _snap = _st.pos_notes[_frame mod SID64_POS_RING];
    if (!is_array(_snap)) return _out;
    var _mask = scr_music_sid_mask(_m, _m.sid_page);
    for (var _v = 0; _v < 3; _v++) {
        var _i = _m.sid_page * 3 + _v;
        if (_i < array_length(_snap) && (_mask & (1 << _v)) != 0) _out[_v] = _snap[_i];
    }
    return _out;
}

/// TIMING: PER VOICE playback: where each shown voice is, as [order row, row],
/// read from the frame being heard. undefined when not playing that way.
function scr_sound_editor_voice_positions(_m) {
    var _st = global.sid64_stream;
    if (!_m.free_voices || !_st.active || _st.sim.m != _m || _st.frames_rendered <= 0) return undefined;
    var _frame = clamp(floor((get_timer() - _st.start_us) / SID64_FRAME_US), 0, _st.frames_rendered - 1);
    var _snap = _st.pos_vpos[_frame mod SID64_POS_RING];
    if (!is_array(_snap)) return undefined;
    var _out = [];
    for (var _v = 0; _v < 3; _v++) {
        var _i = _m.sid_page * 3 + _v;
        if (_i < array_length(_snap)) {
            array_push(_out, _snap[_i]);
        } else {
            array_push(_out, [0, 0]);
        }
    }
    return _out;
}

/// JAM mode: play a note with the selected instrument, writing nothing.
/// Mono = on _voice, cutting whatever that voice was playing. Poly = on the
/// next voice in turn across every SID chip (3 per chip), so notes overlap.
function scr_sound_editor_jam_play(_m, _note_name, _voice, _poly) {
    var _ch = _voice;
    if (_poly) {
        var _n = scr_music_sid_count(_m) * 3;
        _ch = global.music_poly_next mod _n;
        global.music_poly_next = (_ch + 1) mod _n;
    }
    if (_m.sel_instr >= 0 && _m.sel_instr < array_length(_m.instruments)) {
        scr_sound_instrument_preview_play(_m.instruments[_m.sel_instr], _note_name, _ch, -1, false, _m);
    } else {
        scr_sound_preview_play(_note_name, "SQUARE", _ch);
    }
}

/// The whole piano panel. _col_pat = the three voices' patterns (noone when a
/// voice has none), _vis = visible grid rows (for scrolling after a click).
/// _undo_push / _snap are the editor's undo helpers.
function scr_sound_editor_piano(_m, _x0, _y0, _x1, _y1, _mx, _my, _col_pat, _vis, _undo_push, _snap) {
    draw_set_font_l(fnt_c64_pico);

    // header: title + mode toggle
    draw_set_color(make_color_rgb(255, 200, 100));
    draw_text_l(_x0, _y0, "PIANO");
    var _split = (_m.pno_mode == "SPLIT");
    var _mb_x = _x0 + 50;
    for (var _mi = 0; _mi < 2; _mi++) {
        var _mlbl = "SPLIT";
        if (_mi == 1) {
            _mlbl = "FULL";
        }
        var _mbx = _mb_x + _mi * 52;
        var _mon = ((_mi == 0) == _split);
        var _mhov = point_in_rectangle(_mx, _my, _mbx, _y0 - 2, _mbx + 48, _y0 + 12);
        if (_mon) {
            draw_set_color(make_color_rgb(40, 110, 170));
        } else if (_mhov) {
            draw_set_color(make_color_rgb(65, 80, 100));
        } else {
            draw_set_color(make_color_rgb(30, 38, 52));
        }
        draw_rectangle(_mbx, _y0 - 2, _mbx + 48, _y0 + 12, false);
        draw_set_color(c_white);
        draw_text_l(_mbx + 8, _y0, _mlbl);
        if (_mhov && mouse_check_button_pressed(mb_left)) {
            _m.pno_mode = _mlbl;
            _m.pno_hover = -1;
        }
    }
    draw_set_color(make_color_rgb(120, 120, 150));
    var _hint_jam  = "JAM: LEFT CLICK OR HOLD RIGHT MOUSE ON THE KEYS TO PLAY - NOTHING IS WRITTEN";
    var _hint_edit = "HOLD RIGHT MOUSE ON THE KEYS TO HEAR THE SELECTED INSTRUMENT, LEFT CLICK TO WRITE THE NOTE AT THE MARKER";
    if (global.music_jam) {
        draw_text_l(_mb_x + 116, _y0, _hint_jam);
    } else {
        draw_text_l(_mb_x + 116, _y0, _hint_edit);
    }

    // [EDIT MODE] / [JAM MODE]: JAM plays note keys and piano clicks without
    // writing anything. [MONOPHONY] / [POLYPHONY]: in JAM, each new note
    // either cuts the last one on the same voice, or moves on to the next
    // voice (all voices of every SID chip) so notes ring together.
    var _tg_x = _mb_x + 116 + max(string_width_l(_hint_jam), string_width_l(_hint_edit)) + 16;
    var _tg_w = max(string_width_l("EDIT MODE"), string_width_l("JAM MODE")) + 16;
    var _tg_w2 = max(string_width_l("MONOPHONY"), string_width_l("POLYPHONY")) + 16;
    var _tg_labels = ["EDIT MODE", "MONOPHONY"];
    if (global.music_jam) _tg_labels[0] = "JAM MODE";
    if (global.music_poly) _tg_labels[1] = "POLYPHONY";
    for (var _tgi = 0; _tgi < 2; _tgi++) {
        var _tw = _tg_w;
        if (_tgi == 1) _tw = _tg_w2;
        var _thov = point_in_rectangle(_mx, _my, _tg_x, _y0 - 2, _tg_x + _tw, _y0 + 12);
        var _ton = global.music_jam;
        if (_tgi == 1) _ton = global.music_poly;
        if (_ton) {
            draw_set_color(_thov ? make_color_rgb(200, 120, 60) : make_color_rgb(150, 80, 30));
        } else if (_thov) {
            draw_set_color(make_color_rgb(65, 80, 100));
        } else {
            draw_set_color(make_color_rgb(30, 38, 52));
        }
        draw_rectangle(_tg_x, _y0 - 2, _tg_x + _tw, _y0 + 12, false);
        draw_set_color(c_white);
        draw_text_l(_tg_x + 8, _y0, _tg_labels[_tgi]);
        if (_thov && mouse_check_button_pressed(mb_left)) {
            if (_tgi == 0) {
                global.music_jam = !global.music_jam;
            } else {
                global.music_poly = !global.music_poly;
                global.music_poly_next = 0;
            }
        }
        _tg_x += _tw + 6;
    }

    // Keys each shown voice is sounding, in the voice colours.
    var _voice_cols = [make_color_rgb(90, 190, 255), make_color_rgb(255, 150, 70), make_color_rgb(120, 225, 120)];
    var _playing = scr_sound_editor_piano_playing(_m);
    var _lit_all = [];
    for (var _lv = 0; _lv < 3; _lv++) {
        if (_playing[_lv] >= 0) array_push(_lit_all, [_playing[_lv], _voice_cols[_lv]]);
    }

    var _ky0 = _y0 + 16;
    var _hover = -1;
    var _hover_v = _m.sel_voice;

    // marker cell's note, shown on the keyboard it belongs to
    var _mark = -1;
    var _mk_pat = _col_pat[_m.sel_voice];
    if (_mk_pat != noone && _m.sel_step < array_length(_mk_pat.steps)) {
        var _mk_st = _mk_pat.steps[_m.sel_step];
        if (!_mk_st.empty) {
            _mark = scr_sid_song_note_index(_mk_st.note);
        }
    }

    if (_split) {
        var _oct0 = clamp(_m.cur_octave, 0, 6);
        var _gap = 16;
        var _sw = ((_x1 - _x0) - _gap * 2) / 3;
        for (var _v = 0; _v < 3; _v++) {
            var _sx0 = _x0 + _v * (_sw + _gap);
            draw_set_color(_voice_cols[_v]);
            draw_text_l(_sx0, _ky0 - 1, "VOICE " + string(_v + 1));
            var _vmark = -1;
            if (_v == _m.sel_voice) {
                _vmark = _mark;
            }
            var _vlit = [];
            if (_playing[_v] >= 0) array_push(_vlit, [_playing[_v], _voice_cols[_v]]);
            var _h = scr_sound_editor_piano_keys(_sx0, _ky0 + 12, _sx0 + _sw, _y1, _oct0, 2, _mx, _my, _vmark, _vlit);
            if (_h >= 0) {
                _hover = _h;
                _hover_v = _v;
            }
        }
    } else {
        _hover = scr_sound_editor_piano_keys(_x0, _ky0 + 12, _x1, _y1, 1, 6, _mx, _my, _mark, _lit_all);
    }
    draw_set_font_l(fnt_c64_tiny);

    // ── right mouse held: play the key when pressed, and each new key slid onto ──
    var _rmb_play = false;
    if (_hover >= 0 && mouse_check_button(mb_right)) {
        if (mouse_check_button_pressed(mb_right) || _hover != _m.pno_hover || _hover_v != _m.pno_hover_v) {
            _rmb_play = true;
        }
    }
    if (mouse_check_button_released(mb_right)) {
        scr_sound_preview_free_channel(_m.pno_hover_v);
    }
    if (_rmb_play) {
        if (_hover_v != _m.pno_hover_v) scr_sound_preview_free_channel(_m.pno_hover_v);
        var _nm = scr_sound_editor_piano_name(_hover);
        if (_m.sel_instr >= 0 && _m.sel_instr < array_length(_m.instruments)) {
            scr_sound_instrument_preview_play(_m.instruments[_m.sel_instr], _nm, _hover_v, -1, false, _m);
        } else {
            scr_sound_preview_play(_nm, "SQUARE", _hover_v);
        }
    }
    _m.pno_hover   = _hover;
    _m.pno_hover_v = _hover_v;

    // ── click: JAM plays the key; EDIT writes the note at the marker row ──
    if (_hover >= 0 && mouse_check_button_pressed(mb_left) && global.music_jam) {
        // FULL piano follows MONOPHONY / POLYPHONY; each SPLIT keyboard is its own voice.
        scr_sound_editor_jam_play(_m, scr_sound_editor_piano_name(_hover), _hover_v, global.music_poly && !_split);
    }
    if (_hover >= 0 && mouse_check_button_pressed(mb_left) && !global.music_jam) {
        var _pat = _col_pat[_hover_v];
        if (_pat != noone && _m.sel_step < array_length(_pat.steps)) {
            _undo_push(_m, _snap);
            var _st = _pat.steps[_m.sel_step];
            _st.note      = scr_sound_editor_piano_name(_hover);
            _st.instr_idx = _m.sel_instr;
            _st.empty     = false;
            global.undo_dirty      = true;
            global.addresses_dirty = true;
            _m.sel_voice = _hover_v;
            _m.sel_sub   = 0;
            if (_m.sel_step + 1 < _pat.pattern_len) {
                _m.sel_step += 1;
            }
            if (_m.sel_step >= _m.list_scroll + _vis) {
                _m.list_scroll = _m.sel_step - _vis + 1;
            }
            _m.sel_anchor_voice = _m.sel_voice;
            _m.sel_anchor_step  = _m.sel_step;
        }
    }
}
