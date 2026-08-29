/// @function scr_asset_inline_editor_draw(asset, x1, y1, x2, y2, mx, my, accent_col, label)
function scr_asset_inline_editor_draw(_asset, _x1, _y1, _x2, _y2, _mx, _my, _accent, _label) {

    var _txt    = _asset.meta.inline_edit_text;
    var _cur    = _asset.meta.inline_edit_cursor;
    var _scr_y  = _asset.meta.inline_edit_scroll_y;

    draw_set_font(fnt_C64_Angled);
    var _line_h = string_height("A") + 3;
    var _pad    = 6;
    var _gutter = 50;
    var _text_x = _x1 + _gutter + _pad;
    var _text_y = _y1 + _pad;
    // Keep clear of the scrollbar track (6px at _x2) so the last character of
    // a full row is never drawn underneath it.
    var _text_w = _x2 - _text_x - _pad - 10;
    var _text_h = _y2 - _y1 - _pad * 2;
    var _max_vis_lines = floor(_text_h / _line_h);

    // Panel background
    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_color(_accent);
    draw_rectangle(_x1-1, _y1-1, _x2+1, _y2+1, true);

    // Gutter background
    draw_set_color(make_color_rgb(20, 20, 32));
    draw_rectangle(_x1, _y1, _x1 + _gutter, _y2, false);

    // Label strip at top
    draw_set_color(make_color_rgb(30, 30, 48));
    draw_rectangle(_x1, _y1, _x2, _y1 + 18, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_accent);
    draw_text(_x1 + _gutter + _pad, _y1 + 3, _label + "  |  CTRL+A SELECT ALL  |  CTRL+C/V  |  ENTER NEW LINE");

    // ── Lay the text out as VISUAL rows ───────────────────────────────────
    // This replaces the old uniform horizontal squash. That scaled every line
    // against a hardcoded 1000px budget rather than the real box width, so
    // text both compressed to an unreadable smear AND still ran past the panel
    // edge once it was long enough. Rows are measured in the font they are
    // actually drawn in (fnt_C64_Angled), break on spaces where they can, and
    // are contiguous in offset terms — which is what lets the caret, the
    // selection and click-to-place all keep working per row exactly as they
    // used to per line.
    //
    // Cached because the layout only changes when the text or the box width
    // does, and a large BYTE_DATA string is hundreds of rows — re-measuring
    // all of them every frame for the dozen that are visible would cost real
    // frame time. Only one inline editor is ever open at a time, so a single
    // static slot is enough; the asset is part of the key so switching assets
    // cannot show a stale layout.
    draw_set_font(fnt_C64_Angled);

    static _wc_name = "";
    static _wc_txt  = "";
    static _wc_w    = -1;
    static _wc_rows = [];

    // Keyed on the asset NAME rather than the struct so this never depends on
    // how GML compares struct references.
    var _wc_key = string(_asset.name);

    if (_wc_name != _wc_key || _wc_txt != _txt || _wc_w != _text_w) {
        _wc_name = _wc_key;
        _wc_txt  = _txt;
        _wc_w    = _text_w;
        _wc_rows = scr_text_wrap_rows(_txt, _text_w);
    }

    var _rows       = _wc_rows;
    var _total_rows = array_length(_rows);

    // Find cursor row and column
    var _cur_row = 0;
    var _cur_col = 0;
    for (var _ri = 0; _ri < _total_rows; _ri++) {
        if (_ri == _total_rows - 1 || _rows[_ri + 1].off > _cur) {
            _cur_row = _ri;
            _cur_col = _cur - _rows[_ri].off;
            break;
        }
    }

    // Auto-scroll to keep cursor visible
    if (_cur_row < _scr_y) {
        _scr_y = _cur_row;
    }
    if (_cur_row >= _scr_y + _max_vis_lines) {
        _scr_y = _cur_row - _max_vis_lines + 1;
    }
    _scr_y = clamp(_scr_y, 0, max(0, _total_rows - _max_vis_lines));
    _asset.meta.inline_edit_scroll_y = _scr_y;

    // Selection state
    var _has_sel = (_asset.meta.inline_edit_sel_start != -1
                 && _asset.meta.inline_edit_sel_start != _asset.meta.inline_edit_sel_end);
    var _sel_lo  = 0;
    var _sel_hi  = 0;
    if (_has_sel) {
        _sel_lo = min(_asset.meta.inline_edit_sel_start, _asset.meta.inline_edit_sel_end);
        _sel_hi = max(_asset.meta.inline_edit_sel_start, _asset.meta.inline_edit_sel_end);
    }

    // Scissor to text area
    var _sx_sc = window_get_width()  / global.gui_w;
    var _sy_sc = window_get_height() / display_get_gui_height();
    gpu_set_scissor(
        floor(_x1 * _sx_sc),
        floor((_y1 + 18) * _sy_sc),
        ceil((_x2 - _x1) * _sx_sc),
        ceil((_y2 - _y1 - 18) * _sy_sc)
    );

    for (var _li = 0; _li < _max_vis_lines; _li++) {
        var _ridx = _li + _scr_y;
        if (_ridx >= _total_rows) break;

        var _row        = _rows[_ridx];
        var _ly         = _y1 + 18 + _pad + _li * _line_h;
        var _line_txt   = _row.text;
        var _line_start = _row.off;

        // Gutter line number — only on the first row of a logical line. A
        // blank gutter is the signal that a row is a soft-wrap continuation,
        // so the numbers still count real lines.
        if (!_row.iscont) {
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(60, 70, 90));
            draw_text(_x1 + 4, _ly, string(_row.lnum + 1));
        }
        draw_set_font(fnt_C64_Angled);

        // Selection highlight
        if (_has_sel) {
            var _line_end = _line_start + string_length(_line_txt);
            if (_sel_lo < _line_end + 1 && _sel_hi > _line_start) {
                var _hl_s = max(0, _sel_lo - _line_start);
                var _hl_e = min(string_length(_line_txt), _sel_hi - _line_start);
                var _hx1  = _text_x + string_width(string_copy(_line_txt, 1, _hl_s));
                var _hx2  = _text_x + string_width(string_copy(_line_txt, 1, _hl_e));
                draw_set_alpha(0.5);
                draw_set_color(make_color_rgb(80, 230, 255));
                draw_rectangle(_hx1, _ly, _hx2, _ly + _line_h, false);
                draw_set_alpha(1.0);
                draw_set_color(c_white);
                draw_rectangle(_hx1, _ly, _hx2, _ly + _line_h, true);
            }
        }

        // Line text
        draw_set_color(c_white);
        draw_text(_text_x, _ly, _line_txt);

        // Cursor
        if (_ridx == _cur_row && (_asset.meta.inline_edit_blink mod 40 < 25)) {
            var _cx = _text_x + string_width(string_copy(_line_txt, 1, _cur_col));
            draw_set_color(c_white);
            draw_line_width(_cx, _ly, _cx, _ly + _line_h, 2);
        }

        // Mouse click to place cursor
        if (_my >= _ly && _my < _ly + _line_h
            && _mx >= _x1 && _mx < _x2) {
            var _hit_col = string_length(_line_txt);
            if (_mx <= _text_x) {
                _hit_col = 0;
           } else {
                for (var _ci = 0; _ci < string_length(_line_txt); _ci++) {
                    var _cx1 = _text_x + string_width(string_copy(_line_txt, 1, _ci));
                    var _cx2 = _text_x + string_width(string_copy(_line_txt, 1, _ci + 1));
                    if (_mx < (_cx1 + _cx2) * 0.5) {
                        _hit_col = _ci;
                        break;
                    }
                }
            }
            var _hit_cur = _line_start + _hit_col;
            if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
                _asset.meta.inline_edit_cursor    = _hit_cur;
                _asset.meta.inline_edit_sel_start = _hit_cur;
                _asset.meta.inline_edit_sel_end   = _hit_cur;
            }
        }
    }

    gpu_set_scissor(0, 0, window_get_width(), window_get_height());

    // Scrollbar
    if (_total_rows > _max_vis_lines) {
        var _sb_x  = _x2 - 6;
        var _sb_y1 = _y1 + 18;
        var _sb_y2 = _y2;
        var _sb_h  = _sb_y2 - _sb_y1;
        var _th_h  = max(16, _sb_h * (_max_vis_lines / _total_rows));
        var _th_y  = _sb_y1 + (_sb_h - _th_h) * (_scr_y / max(1, _total_rows - _max_vis_lines));
        draw_set_color(make_color_rgb(25, 25, 40));
        draw_rectangle(_sb_x, _sb_y1, _sb_x + 6, _sb_y2, false);
        draw_set_color(make_color_rgb(80, 100, 140));
        draw_rectangle(_sb_x, _th_y, _sb_x + 6, _th_y + _th_h, false);
    }

    // Mouse wheel scroll
    if (point_in_rectangle(_mx, _my, _x1, _y1, _x2, _y2)) {
        if (mouse_wheel_up()) {
            _asset.meta.inline_edit_scroll_y = max(0, _scr_y - 2);
        }
        if (mouse_wheel_down()) {
            _asset.meta.inline_edit_scroll_y = min(max(0, _total_rows - _max_vis_lines), _scr_y + 2);
        }
    }

    _asset.meta.inline_edit_blink++;
}
