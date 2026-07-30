/// @function scr_kla_encode_surface(_surf, _bg, _tone_sorted, _is_hires)
/// @desc Quantises a 320x200 RGB surface into C64 Multicolour (4 colours/cell)
///       or HiRes (2 colours/cell) bitmap bytes.
///       Returns { bmp : [8000], scr : [1000], col : [1000] } — col is unused
///       and left zeroed for HiRes, since HiRes has no colour-RAM channel.
///
/// This is the encoder scr_asset_kla_save uses, lifted out so the
/// BITMAP_BUILDER preview can reason about the SAME bytes the runtime will
/// receive. The builder's MASK00 preview needs real bit pairs and real palette
/// slots — RGB alone cannot tell which slot a colour occupies, and the merge
/// rules are all expressed in slots.
///
/// Keeping one copy matters: if the quantiser here and the one in the save path
/// ever disagree, the preview stops predicting VICE and starts predicting
/// nothing in particular.
function scr_kla_encode_surface(_surf, _bg, _tone_sorted, _is_hires = false) {
    var _out = {
        bmp : array_create(8000, 0),
        scr : array_create(1000, 0),
        col : array_create(1000, 0)
    };
    if (!surface_exists(_surf)) {
        return _out;
    }

    var _color_hash = {};
    for (var _c = 0; _c < 16; _c++) {
        var _cc = scr_c64_pepto_colour(_c);
        var _hr = color_get_red(_cc);
        var _hg = color_get_green(_cc);
        var _hb = color_get_blue(_cc);
        _color_hash[$ (_hr << 16) | (_hg << 8) | _hb] = _c;
    }

    var _sb = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_sb, _surf, 0);

    for (var _gy = 0; _gy < 25; _gy++) {
        for (var _gx = 0; _gx < 40; _gx++) {
            var _cell_idx = _gy * 40 + _gx;

            if (!_is_hires) {
                // ── MULTICOLOUR CELL ENCODE (unchanged) ──
                var _unique = [];
                var _counts = array_create(16, 0);
                var _cell_pixels = array_create(32, 0);

                for (var _py = 0; _py < 8; _py++) {
                    for (var _px = 0; _px < 8; _px += 2) {
                        var _ax = clamp((_gx * 8) + _px, 0, 319);
                        var _ay = clamp((_gy * 8) + _py, 0, 199);
                        var _off = (_ay * 320 + _ax) * 4;
                        var _r = buffer_peek(_sb, _off,     buffer_u8);
                        var _g = buffer_peek(_sb, _off + 1, buffer_u8);
                        var _b = buffer_peek(_sb, _off + 2, buffer_u8);
                        var _idx = _color_hash[$ (_r << 16) | (_g << 8) | _b] ?? _bg;
                        _cell_pixels[_py * 4 + (_px div 2)] = _idx;
                        if (_idx != _bg) {
                            if (_counts[_idx] == 0) {
                                array_push(_unique, _idx);
                            }
                            _counts[_idx] += 1;
                        }
                    }
                }

                var _sorted = [];
                for (var _ui = 0; _ui < array_length(_unique); _ui++) {
                    array_push(_sorted, _unique[_ui]);
                }
                for (var _si = 1; _si < array_length(_sorted); _si++) {
                    var _key = _sorted[_si];
                    var _sj  = _si - 1;
                    while (_sj >= 0) {
                        var _swap = false;
                        if (_counts[_sorted[_sj]] < _counts[_key]) {
                            _swap = true;
                        } else if (_counts[_sorted[_sj]] == _counts[_key] && _sorted[_sj] > _key) {
                            _swap = true;
                        }
                        if (!_swap) {
                            break;
                        }
                        _sorted[_sj + 1] = _sorted[_sj];
                        _sj -= 1;
                    }
                    _sorted[_sj + 1] = _key;
                }

                var _uniq_n = array_length(_sorted);
                var _c1 = 0;
                var _c2 = 0;
                var _c3 = 0;

                if (_tone_sorted) {
                    var _win_a = -1;
                    var _win_b = -1;
                    var _win_c = -1;
                    var _cnt_a = 0;
                    var _cnt_b = 0;
                    var _cnt_c = 0;
                    for (var _ti = 0; _ti < _uniq_n; _ti++) {
                        var _tc = _sorted[_ti];
                        var _tg = scr_c64_tone_group(_tc);
                        if (_tg == 1) {
                            if (_counts[_tc] > _cnt_a) {
                                _cnt_a = _counts[_tc];
                                _win_a = _tc;
                            }
                        } else if (_tg == 2) {
                            if (_counts[_tc] > _cnt_b) {
                                _cnt_b = _counts[_tc];
                                _win_b = _tc;
                            }
                        } else {
                            if (_counts[_tc] > _cnt_c) {
                                _cnt_c = _counts[_tc];
                                _win_c = _tc;
                            }
                        }
                    }
                    var _fallback = 0;
                    if (_win_b >= 0) {
                        _fallback = _win_b;
                    } else if (_win_a >= 0) {
                        _fallback = _win_a;
                    } else if (_win_c >= 0) {
                        _fallback = _win_c;
                    }
                    _c1 = (_win_a >= 0) ? _win_a : _fallback;
                    _c2 = (_win_b >= 0) ? _win_b : _fallback;
                    _c3 = (_win_c >= 0) ? _win_c : _fallback;
                } else {
                    if (_uniq_n > 0) {
                        _c1 = _sorted[0];
                        _c2 = _c1;
                        _c3 = _c1;
                    }
                    if (_uniq_n > 1) {
                        _c2 = _sorted[1];
                        _c3 = _sorted[1];
                    }
                    if (_uniq_n > 2) {
                        _c3 = _sorted[2];
                    }
                }

                _out.scr[_cell_idx] = (_c1 << 4) | _c2;
                _out.col[_cell_idx] = _c3;

                for (var _py2 = 0; _py2 < 8; _py2++) {
                    var _byte = 0;
                    for (var _mp = 0; _mp < 4; _mp++) {
                        var _pc  = _cell_pixels[_py2 * 4 + _mp];
                        var _bit = 0;
                        if (_pc == _c1) {
                            _bit = 1;
                        } else if (_pc == _c2) {
                            _bit = 2;
                        } else if (_pc == _c3) {
                            _bit = 3;
                        }
                        _byte = _byte | (_bit << (6 - (_mp * 2)));
                    }
                    _out.bmp[_cell_idx * 8 + _py2] = _byte;
                }

            } else {
                // ── HIRES CELL ENCODE ──
                // Only 2 colours/cell: dominant colour -> BG, runner-up -> FG.
                // Screen RAM byte: high nibble = FG (bit=1), low nibble = BG (bit=0).
                var _unique = [];
                var _counts = array_create(16, 0);
                var _cell_pixels = array_create(64, 0);

                for (var _py = 0; _py < 8; _py++) {
                    for (var _px = 0; _px < 8; _px++) {
                        var _ax = clamp((_gx * 8) + _px, 0, 319);
                        var _ay = clamp((_gy * 8) + _py, 0, 199);
                        var _off = (_ay * 320 + _ax) * 4;
                        var _r = buffer_peek(_sb, _off,     buffer_u8);
                        var _g = buffer_peek(_sb, _off + 1, buffer_u8);
                        var _b = buffer_peek(_sb, _off + 2, buffer_u8);
                        var _idx = _color_hash[$ (_r << 16) | (_g << 8) | _b] ?? _bg;
                        _cell_pixels[_py * 8 + _px] = _idx;
                        if (_counts[_idx] == 0) {
                            array_push(_unique, _idx);
                        }
                        _counts[_idx] += 1;
                    }
                }

                var _sorted = [];
                for (var _ui = 0; _ui < array_length(_unique); _ui++) {
                    array_push(_sorted, _unique[_ui]);
                }
                for (var _si = 1; _si < array_length(_sorted); _si++) {
                    var _key = _sorted[_si];
                    var _sj  = _si - 1;
                    while (_sj >= 0) {
                        var _swap = false;
                        if (_counts[_sorted[_sj]] < _counts[_key]) {
                            _swap = true;
                        } else if (_counts[_sorted[_sj]] == _counts[_key] && _sorted[_sj] > _key) {
                            _swap = true;
                        }
                        if (!_swap) {
                            break;
                        }
                        _sorted[_sj + 1] = _sorted[_sj];
                        _sj -= 1;
                    }
                    _sorted[_sj + 1] = _key;
                }

                var _uniq_n = array_length(_sorted);
                var _c_bg = _bg;
                var _c_fg = _bg;
                if (_uniq_n > 0) {
                    _c_bg = _sorted[0];
                    _c_fg = _c_bg;
                }
                if (_uniq_n > 1) {
                    _c_fg = _sorted[1];
                }

                _out.scr[_cell_idx] = (_c_fg << 4) | _c_bg;

                for (var _py2 = 0; _py2 < 8; _py2++) {
                    var _byte = 0;
                    for (var _px2 = 0; _px2 < 8; _px2++) {
                        var _pc = _cell_pixels[_py2 * 8 + _px2];
                        if (_uniq_n > 1 && _pc == _c_fg) {
                            _byte = _byte | (0x80 >> _px2);
                        }
                    }
                    _out.bmp[_cell_idx * 8 + _py2] = _byte;
                }
            }
        }
    }

    buffer_delete(_sb);
    return _out;
}