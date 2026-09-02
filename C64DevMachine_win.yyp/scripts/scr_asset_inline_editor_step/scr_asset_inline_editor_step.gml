/// @function scr_asset_inline_editor_step(asset, mx, my, x1, y1, x2, y2)
function scr_asset_inline_editor_step(_asset, _mx, _my, _x1, _y1, _x2, _y2) {

    // Editor accepts keyboard input as long as it's open — mouse position
    // is irrelevant for typing, just like every native OS text field.
    // (Hover is still available via _hover below for any future mouse-driven
    // interactions like click-to-position-cursor or drag-to-select.)
    var _hover = point_in_rectangle(_mx, _my, _x1, _y1, _x2, _y2);

    var _txt  = _asset.meta.inline_edit_text;
    var _cur  = _asset.meta.inline_edit_cursor;
    var _len  = string_length(_txt);
    var _ctrl = keyboard_check(vk_control);
    var _shift = keyboard_check(vk_shift);

    var _has_sel    = (_asset.meta.inline_edit_sel_start != -1
                    && _asset.meta.inline_edit_sel_start != _asset.meta.inline_edit_sel_end);
    var _sel_lo     = _has_sel ? min(_asset.meta.inline_edit_sel_start, _asset.meta.inline_edit_sel_end) : _cur;
    var _sel_hi     = _has_sel ? max(_asset.meta.inline_edit_sel_start, _asset.meta.inline_edit_sel_end) : _cur;

    // ── Ctrl+A Select All ─────────────────────────────────────────────────
    if (_ctrl && keyboard_check_pressed(ord("A"))) {
        _asset.meta.inline_edit_sel_start = 0;
        _asset.meta.inline_edit_sel_end   = _len;
        _asset.meta.inline_edit_cursor    = _len;
        keyboard_string = "";
        return;
    }

    // ── Ctrl+C Copy ───────────────────────────────────────────────────────
    if (_ctrl && keyboard_check_pressed(ord("C"))) {
        if (_has_sel) {
            clipboard_set_text(string_copy(_txt, _sel_lo + 1, _sel_hi - _sel_lo));
        }
        keyboard_string = "";
        return;
    }

    // ── Ctrl+V Paste ──────────────────────────────────────────────────────
    if (_ctrl && keyboard_check_pressed(ord("V"))) {
        var _paste = clipboard_get_text();
        _paste = string_replace_all(_paste, "\r\n", "\n");
        _paste = string_replace_all(_paste, "\r", "\n");
        if (_paste != "") {
            if (_has_sel) {
                _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
                _cur = _sel_lo;
                _asset.meta.inline_edit_sel_start = -1;
                _asset.meta.inline_edit_sel_end   = -1;
            }
            _txt = string_insert(_paste, _txt, _cur + 1);
            _cur += string_length(_paste);
        }
        _asset.meta.inline_edit_text   = _txt;
        _asset.meta.inline_edit_cursor = _cur;
        keyboard_string = "";
        return;
    }

    // ── Enter: new line ───────────────────────────────────────────────────
    if (keyboard_check_pressed(vk_enter)) {
        if (_has_sel) {
            _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
            _cur = _sel_lo;
            _asset.meta.inline_edit_sel_start = -1;
            _asset.meta.inline_edit_sel_end   = -1;
        }
        _txt = string_insert("\n", _txt, _cur + 1);
        _cur++;
        _asset.meta.inline_edit_text   = _txt;
        _asset.meta.inline_edit_cursor = _cur;
        _asset.meta.inline_edit_blink  = 0;
        keyboard_string = "";
        keyboard_clear(vk_enter);
        return;
    }

    // ── Key repeat system ─────────────────────────────────────────────────
    var _do_action = false;
    var _any_nav   = keyboard_check(vk_left) || keyboard_check(vk_right)
                  || keyboard_check(vk_up)   || keyboard_check(vk_down)
                  || keyboard_check(vk_backspace) || keyboard_check(vk_delete);

    if (_any_nav) {
        if (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right)
            || keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_down)
            || keyboard_check_pressed(vk_backspace) || keyboard_check_pressed(vk_delete)) {
            _do_action = true;
            _asset.meta.inline_edit_key_timer = 20;
        } else {
            _asset.meta.inline_edit_key_timer--;
            if (_asset.meta.inline_edit_key_timer <= 0) {
                _do_action = true;
                _asset.meta.inline_edit_key_timer = 2;
            }
        }
    } else {
        _asset.meta.inline_edit_key_timer = 0;
    }

    if (_do_action) {

        // ── Left ──────────────────────────────────────────────────────────
        if (keyboard_check(vk_left)) {
            if (_shift) {
                if (_asset.meta.inline_edit_sel_start == -1) {
                    _asset.meta.inline_edit_sel_start = _cur;
                }
            } else {
                _asset.meta.inline_edit_sel_start = -1;
                _asset.meta.inline_edit_sel_end   = -1;
            }
            if (_has_sel && !_shift) {
                _cur = _sel_lo;
            } else if (_cur > 0) {
                _cur--;
            }
            _asset.meta.inline_edit_cursor = _cur;
            if (_shift) _asset.meta.inline_edit_sel_end = _cur;
            _asset.meta.inline_edit_blink = 0;
        }

        // ── Right ─────────────────────────────────────────────────────────
        if (keyboard_check(vk_right)) {
            if (_shift) {
                if (_asset.meta.inline_edit_sel_start == -1) {
                    _asset.meta.inline_edit_sel_start = _cur;
                }
            } else {
                _asset.meta.inline_edit_sel_start = -1;
                _asset.meta.inline_edit_sel_end   = -1;
            }
            if (_has_sel && !_shift) {
                _cur = _sel_hi;
            } else if (_cur < _len) {
                _cur++;
            }
            _asset.meta.inline_edit_cursor = _cur;
            if (_shift) _asset.meta.inline_edit_sel_end = _cur;
            _asset.meta.inline_edit_blink = 0;
        }

        // ── Up ────────────────────────────────────────────────────────────
        if (keyboard_check(vk_up)) {
            if (_shift) {
                if (_asset.meta.inline_edit_sel_start == -1) {
                    _asset.meta.inline_edit_sel_start = _cur;
                }
            } else {
                _asset.meta.inline_edit_sel_start = -1;
                _asset.meta.inline_edit_sel_end   = -1;
            }
            var _lines_u  = string_split(_txt, "\n");
            var _count_u  = 0;
            var _cur_l    = 0;
            var _cur_c    = 0;
            for (var _li = 0; _li < array_length(_lines_u); _li++) {
                var _ll = string_length(_lines_u[_li]) + 1;
                if (_count_u + _ll > _cur) {
                    _cur_l = _li;
                    _cur_c = _cur - _count_u;
                    break;
                }
                _count_u += _ll;
            }
            if (_cur_l > 0) {
                var _prev_len = string_length(_lines_u[_cur_l - 1]);
                var _new_col  = min(_cur_c, _prev_len);
                _cur = _count_u - _prev_len - 1 + _new_col;
                if (_cur < 0) _cur = 0;
            } else {
                _cur = 0;
            }
            _asset.meta.inline_edit_cursor = _cur;
            if (_shift) _asset.meta.inline_edit_sel_end = _cur;
            _asset.meta.inline_edit_blink = 0;
        }

        // ── Down ──────────────────────────────────────────────────────────
        if (keyboard_check(vk_down)) {
            if (_shift) {
                if (_asset.meta.inline_edit_sel_start == -1) {
                    _asset.meta.inline_edit_sel_start = _cur;
                }
            } else {
                _asset.meta.inline_edit_sel_start = -1;
                _asset.meta.inline_edit_sel_end   = -1;
            }
            var _lines_d = string_split(_txt, "\n");
            var _count_d = 0;
            var _cur_ld  = 0;
            var _cur_cd  = 0;
            for (var _li = 0; _li < array_length(_lines_d); _li++) {
                var _ll = string_length(_lines_d[_li]) + 1;
                if (_count_d + _ll > _cur) {
                    _cur_ld = _li;
                    _cur_cd = _cur - _count_d;
                    break;
                }
                _count_d += _ll;
            }
            if (_cur_ld < array_length(_lines_d) - 1) {
                var _next_start = _count_d + string_length(_lines_d[_cur_ld]) + 1;
                var _next_len   = string_length(_lines_d[_cur_ld + 1]);
                _cur = _next_start + min(_cur_cd, _next_len);
            } else {
                _cur = _len;
            }
            _asset.meta.inline_edit_cursor = _cur;
            if (_shift) _asset.meta.inline_edit_sel_end = _cur;
            _asset.meta.inline_edit_blink = 0;
        }

        // ── CTRL+BACKSPACE — clear the lot ────────────────────────────────
        // Ahead of the plain backspace below and returning early, so the
        // same keypress cannot also delete a character out of the now-empty
        // string. keyboard_check_pressed, not keyboard_check: held down it
        // would fire every frame, and there is nothing left to clear after
        // the first one anyway.
        if (_ctrl && keyboard_check_pressed(vk_backspace)) {
            _asset.meta.inline_edit_text      = "";
            _asset.meta.inline_edit_cursor    = 0;
            _asset.meta.inline_edit_sel_start = -1;
            _asset.meta.inline_edit_sel_end   = -1;
            _asset.meta.inline_edit_scroll_y  = 0;
            _asset.meta.inline_edit_blink     = 0;
            keyboard_string = "";
            exit;
        }

        // ── Backspace ─────────────────────────────────────────────────────
        if (keyboard_check(vk_backspace) && !_ctrl) {
            if (_has_sel) {
                _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
                _cur = _sel_lo;
                _asset.meta.inline_edit_sel_start = -1;
                _asset.meta.inline_edit_sel_end   = -1;
            } else if (_cur > 0) {
                _txt = string_delete(_txt, _cur, 1);
                _cur--;
            }
            _asset.meta.inline_edit_text   = _txt;
            _asset.meta.inline_edit_cursor = _cur;
            _asset.meta.inline_edit_blink  = 0;
        }

        // ── Delete ────────────────────────────────────────────────────────
        if (keyboard_check(vk_delete)) {
            if (_has_sel) {
                _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
                _cur = _sel_lo;
                _asset.meta.inline_edit_sel_start = -1;
                _asset.meta.inline_edit_sel_end   = -1;
            } else if (_cur < _len) {
                _txt = string_delete(_txt, _cur + 1, 1);
            }
            _asset.meta.inline_edit_text   = _txt;
            _asset.meta.inline_edit_cursor = _cur;
            _asset.meta.inline_edit_blink  = 0;
        }
    }

    // ── Home / End ────────────────────────────────────────────────────────
    if (keyboard_check_pressed(vk_home)) {
        var _lines_h = string_split(_txt, "\n");
        var _count_h = 0;
        for (var _li = 0; _li < array_length(_lines_h); _li++) {
            var _ll = string_length(_lines_h[_li]) + 1;
            if (_count_h + _ll > _cur) { _cur = _count_h; break; }
            _count_h += _ll;
        }
        _asset.meta.inline_edit_cursor    = _cur;
        _asset.meta.inline_edit_sel_start = -1;
        _asset.meta.inline_edit_sel_end   = -1;
    }

    if (keyboard_check_pressed(vk_end)) {
        var _lines_e = string_split(_txt, "\n");
        var _count_e = 0;
        for (var _li = 0; _li < array_length(_lines_e); _li++) {
            var _ll = string_length(_lines_e[_li]) + 1;
            if (_count_e + _ll > _cur) {
                _cur = _count_e + string_length(_lines_e[_li]);
                break;
            }
            _count_e += _ll;
        }
        _asset.meta.inline_edit_cursor    = _cur;
        _asset.meta.inline_edit_sel_start = -1;
        _asset.meta.inline_edit_sel_end   = -1;
    }

    // ── Character input ───────────────────────────────────────────────────
    if (keyboard_string != "" && !_ctrl) {
        var _added = keyboard_string;
        if (_has_sel) {
            _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
            _cur = _sel_lo;
            _asset.meta.inline_edit_sel_start = -1;
            _asset.meta.inline_edit_sel_end   = -1;
        }
        _txt = string_insert(_added, _txt, _cur + 1);
        _cur += string_length(_added);
        _asset.meta.inline_edit_text   = _txt;
        _asset.meta.inline_edit_cursor = _cur;
        _asset.meta.inline_edit_blink  = 0;
        keyboard_string = "";
    }

    keyboard_string = "";
}