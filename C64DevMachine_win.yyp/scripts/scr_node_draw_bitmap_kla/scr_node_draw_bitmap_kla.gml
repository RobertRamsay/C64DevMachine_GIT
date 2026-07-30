function scr_node_draw_bitmap_kla(_draw_x, _y) {
    var _header_h = 24;
    var _line_h   = 12;

    var _label    = string(instructions[0][1]);
    var _bg_col   = real(instructions[0][2]);
    var _has_file = (variable_instance_exists(id, "kla_buffer") && kla_buffer != -1 && buffer_exists(kla_buffer));

    // Define colors locally to match the style
    var _c_edit = make_color_rgb(120, 220, 120); // Light Green (Interactive)
    var _c_dim  = make_color_rgb(120, 120, 120); // Grey (Static)
    var _c_warn = make_color_rgb(200, 60, 60);   // Red (None/Missing)

    draw_set_font(fnt_c64_code);
    var _ly = _y + _header_h + 4;

    // Row 0: LABEL (Assuming editable via separate input logic)
    draw_set_color(_c_edit); 
    draw_text(_draw_x + 10, _ly, "LABEL:");
    draw_set_color(_label == "" ? _c_warn : c_white);
    draw_text(_draw_x + 72, _ly, _label == "" ? "NONE" : _label);
    _ly += _line_h;

    // Row 1: FILE (Your STEP function uses this row to trigger Address Input)
    draw_set_color(_c_edit); 
    draw_text(_draw_x + 10, _ly, "FILE:");
    draw_set_color(_has_file ? make_color_rgb(80, 200, 80) : _c_warn);
    draw_text(_draw_x + 60, _ly, _has_file ? kla_filename : "NO FILE");
    _ly += _line_h;

    // Row 2: Address range (Purely informational/computed)
    var _sta_h = string_upper(decimal_to_hex(pc_address));
    var _end_h = string_upper(decimal_to_hex(pc_address + 10001));
    while (string_length(_sta_h) < 4) _sta_h = "0" + _sta_h;
    while (string_length(_end_h) < 4) _end_h = "0" + _end_h;
    draw_set_color(make_color_rgb(80, 80, 80)); // Deep grey for secondary info
    draw_text(_draw_x + 10, _ly, "10001 BYTES  $" + _sta_h + "-$" + _end_h);
    _ly += _line_h;

    // Row 3: BG Swatch (Interactive cycling)
    draw_set_color(_c_edit); 
    draw_text(_draw_x + 10, _ly, "BG:");
    draw_set_color(scr_c64_pepto_colour(_bg_col));
    draw_rectangle(_draw_x + 46, _ly + 1, _draw_x + 62, _ly + _line_h - 2, false);
    draw_set_color(c_white);
    draw_text(_draw_x + 68, _ly, string(_bg_col));
    _ly += _line_h + 4;

    // KLA preview thumbnail
    var _thumb_w = 160;
    var _thumb_h = 80;

    if (_has_file) {
        if (!surface_exists(preview_surf)) {
            preview_surf = surface_create(160, 200);
            surface_set_target(preview_surf);
            draw_clear(c_black);

            var _bg = real(instructions[0][2]);
            for (var _py = 0; _py < 200; _py++) {
                var _char_row  = _py div 8;
                var _pixel_row = _py mod 8;
                for (var _cx = 0; _cx < 40; _cx++) {
                    var _cell     = _char_row * 40 + _cx;
                    var _bmp_byte = buffer_peek(kla_buffer, 2 + _cell * 8 + _pixel_row, buffer_u8);
                    var _scr      = buffer_peek(kla_buffer, 8002 + _cell, buffer_u8);
                    var _col_byte = buffer_peek(kla_buffer, 9002 + _cell, buffer_u8) & 0xF;
                    var _c1       = _scr >> 4;
                    var _c2       = _scr & 0xF;
                    for (var _bp = 0; _bp < 4; _bp++) {
                        var _val = (_bmp_byte >> (6 - _bp * 2)) & 0x3;
                        var _ci  = (_val == 0) ? _bg : ((_val == 1) ? _c1 : ((_val == 2) ? _c2 : _col_byte));
                        draw_set_color(scr_c64_pepto_colour(_ci));
                        draw_point(_cx * 4 + _bp, _py);
                    }
                }
            }
            surface_reset_target();
        }

        draw_set_color(c_white);
        draw_surface_stretched(preview_surf, _draw_x + 10, _ly, _thumb_w, _thumb_h);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_rectangle(_draw_x + 10, _ly, _draw_x + 10 + _thumb_w, _ly + _thumb_h, true);
        _ly += _thumb_h + 6;

    } else {
        // Empty preview state
        draw_set_color(make_color_rgb(40, 40, 40));
        draw_rectangle(_draw_x + 10, _ly, _draw_x + 10 + _thumb_w, _ly + _thumb_h, false);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_rectangle(_draw_x + 10, _ly, _draw_x + 10 + _thumb_w, _ly + _thumb_h, true);
        draw_set_color(make_color_rgb(100, 100, 100));
        draw_set_halign(fa_center);
        draw_text(_draw_x + 10 + _thumb_w / 2, _ly + _thumb_h / 2 - 6, "NO IMAGE");
        draw_set_halign(fa_left);
        _ly += _thumb_h + 6;
    }

    // LOAD button
    var _btn_x1    = _draw_x + 10;
    var _btn_x2    = _draw_x + 170;
    var _btn_y1    = _ly;
    var _btn_y2    = _ly + 18;
    var _btn_hover = point_in_rectangle(mouse_x, mouse_y, _btn_x1, _btn_y1, _btn_x2, _btn_y2);
    
    draw_set_color(_btn_hover ? make_color_rgb(100, 180, 255) : make_color_rgb(60, 120, 180));
    draw_rectangle(_btn_x1, _btn_y1, _btn_x2, _btn_y2, false);
    draw_set_color(c_white);
    draw_text(_btn_x1 + 6, _btn_y1 + 2, "LOAD .KLA FILE");
    _ly += 24;



    node_height = _ly - _y + 4;

	
}