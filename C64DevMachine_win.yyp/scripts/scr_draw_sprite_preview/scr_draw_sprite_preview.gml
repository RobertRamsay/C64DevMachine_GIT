function scr_draw_sprite_preview(_byte_str, _is_mc, _uc, _bg, _mc1, _mc2, _dx, _dy, _psize) {
    // Accept either string or pre-split array
    var _sb = is_array(_byte_str) ? _byte_str : string_split(_byte_str, ",");
    // Validate
    if (array_length(_sb) < 63) exit;

    // Fill background (skip if _bg == -1)
    if (_bg >= 0) {
        draw_set_color(scr_c64_pepto_colour(_bg));
        draw_rectangle(_dx, _dy, _dx + (24 * _psize), _dy + (21 * _psize), false);
    }

    for (var _row = 0; _row < 21; _row++) {
        for (var _col = 0; _col < 3; _col++) {
            var _bidx = (_row * 3) + _col;
            var _byte = real(string_trim(_sb[_bidx]));
            if (_is_mc) {
                for (var _pair = 3; _pair >= 0; _pair--) {
                    var _bits = (_byte >> (_pair * 2)) & 3;
                    if (_bits == 0) continue;
                    var _bx = (_dx + ((_col * 4) + (3 - _pair)) * (_psize * 2));
                    var _by = (_dy + _row * _psize);
                    switch (_bits) {
                        case 1: draw_set_color(scr_c64_pepto_colour(_mc1)); break;
                        case 2: draw_set_color(scr_c64_pepto_colour(_uc));  break;
                        case 3: draw_set_color(scr_c64_pepto_colour(_mc2)); break;
                    }
                    draw_rectangle(_bx, _by, _bx + (_psize * 2), _by + _psize, false);
                }
            } else {
                for (var _bit = 7; _bit >= 0; _bit--) {
                    if (!((_byte >> _bit) & 1)) continue;
                    var _bx = (_dx + ((_col * 8) + (7 - _bit)) * _psize);
                    var _by = (_dy + _row * _psize);
                    draw_set_color(scr_c64_pepto_colour(_uc));
                    draw_rectangle(_bx, _by, _bx + _psize, _by + _psize, false);
                }
            }
        }
    }
}