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
    var _text_w = _x2 - _text_x - _pad;
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

    // Split into lines
    var _lines = (_txt == "") ? [""] : string_split(_txt, "\n");
    var _total_lines = array_length(_lines);

    // Build line start offsets
    var _line_starts = array_create(_total_lines, 0);
    var _off = 0;
    for (var _li = 0; _li < _total_lines; _li++) {
        _line_starts[_li] = _off;
        _off += string_length(_lines[_li]) + 1;
    }

    // Find cursor line and col
    var _cur_line = 0;
    var _cur_col  = 0;
    for (var _li = 0; _li < _total_lines; _li++) {
        if (_li == _total_lines - 1 || _line_starts[_li + 1] > _cur) {
            _cur_line = _li;
            _cur_col  = _cur - _line_starts[_li];
            break;
        }
    }

    // Auto-scroll to keep cursor visible
    if (_cur_line < _scr_y) {
        _scr_y = _cur_line;
    }
    if (_cur_line >= _scr_y + _max_vis_lines) {
        _scr_y = _cur_line - _max_vis_lines + 1;
    }
    _scr_y = clamp(_scr_y, 0, max(0, _total_lines - _max_vis_lines));
    _asset.meta.inline_edit_scroll_y = _scr_y;

    // Selection state
    var _has_sel    = (_asset.meta.inline_edit_sel_start != -1
                    && _asset.meta.inline_edit_sel_start != _asset.meta.inline_edit_sel_end);
    var _sel_lo     = _has_sel ? min(_asset.meta.inline_edit_sel_start, _asset.meta.inline_edit_sel_end) : 0;
    var _sel_hi     = _has_sel ? max(_asset.meta.inline_edit_sel_start, _asset.meta.inline_edit_sel_end) : 0;

    // Scissor to text area
    var _sx_sc = window_get_width()  / global.gui_w;
    var _sy_sc = window_get_height() / display_get_gui_height();
    gpu_set_scissor(
        floor(_x1 * _sx_sc),
        floor((_y1 + 18) * _sy_sc),
        ceil((_x2 - _x1) * _sx_sc),
        ceil((_y2 - _y1 - 18) * _sy_sc)
    );

    // Calculate uniform scale based on the longest line to preserve columns
    draw_set_font(fnt_C64_Angled);
    var _linemaxwidth = 1000;
    var _full_w = string_width(_txt);
    var _xscale = (_full_w > _linemaxwidth) ? (_linemaxwidth / _full_w) : 1;

    draw_set_font(fnt_c64_code);
    for (var _li = 0; _li < _max_vis_lines; _li++) {
        var _lidx = _li + _scr_y;
        if (_lidx >= _total_lines) break;

        var _ly         = _y1 + 18 + _pad + _li * _line_h;
        var _line_txt   = _lines[_lidx];
        var _line_start = _line_starts[_lidx];

        // Gutter line number
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(60, 70, 90));
        draw_text(_x1 + 4, _ly, string(_lidx + 1));
        draw_set_font(fnt_C64_Angled	);

        // Selection highlight
        if (_has_sel) {
            var _line_end = _line_start + string_length(_line_txt);
            if (_sel_lo < _line_end + 1 && _sel_hi > _line_start) {
                var _hl_s = max(0, _sel_lo - _line_start);
                var _hl_e = min(string_length(_line_txt), _sel_hi - _line_start);
                var _hx1  = _text_x + (string_width(string_copy(_line_txt, 1, _hl_s)) * _xscale);
                var _hx2  = _text_x + (string_width(string_copy(_line_txt, 1, _hl_e)) * _xscale);
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
        draw_text_transformed(_text_x, _ly, _line_txt, _xscale, 1, 0);

        // Cursor
        if (_lidx == _cur_line && (_asset.meta.inline_edit_blink mod 40 < 25)) {
            var _cx = _text_x + (string_width(string_copy(_line_txt, 1, _cur_col)) * _xscale);
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
                    var _cx1 = _text_x + (string_width(string_copy(_line_txt, 1, _ci)) * _xscale);
                    var _cx2 = _text_x + (string_width(string_copy(_line_txt, 1, _ci + 1)) * _xscale);
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
    if (_total_lines > _max_vis_lines) {
        var _sb_x  = _x2 - 6;
        var _sb_y1 = _y1 + 18;
        var _sb_y2 = _y2;
        var _sb_h  = _sb_y2 - _sb_y1;
        var _th_h  = max(16, _sb_h * (_max_vis_lines / _total_lines));
        var _th_y  = _sb_y1 + (_sb_h - _th_h) * (_scr_y / max(1, _total_lines - _max_vis_lines));
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
            _asset.meta.inline_edit_scroll_y = min(max(0, _total_lines - _max_vis_lines), _scr_y + 2);
        }
    }

    _asset.meta.inline_edit_blink++;
}