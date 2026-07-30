function scr_node_draw_macro_flip_x(_draw_x) {

    var _start = (array_length(instructions[0]) > 1 && is_real(instructions[0][1]))
               ? real(instructions[0][1]) : 0x2800;
    var _count = (array_length(instructions[0]) > 2 && is_real(instructions[0][2]))
               ? real(instructions[0][2]) : 1;

    // Auto-detect MC from asset
    // MC auto-detected at compile time — no display needed
	
	var _c_edit = make_color_rgb(120, 220, 120); // Light Green (Interactive)
    var _c_dim  = make_color_rgb(120, 120, 120); // Grey (Static)
    var _c_warn = make_color_rgb(200, 60, 60);   // Red (None/Missing)


    var _end = _start + (_count * 64);

    draw_set_font(fnt_c64_tiny);

    // Summary
    var _end_str = "$" + string_upper(decimal_to_hex(_end));

    // FROM label
    draw_set_color(_c_edit);
    draw_text(_draw_x + 6, y + 28, "FROM:                    ");
	draw_set_color(_c_dim);
	draw_text(_draw_x + 110, y + 28,"TO:  "+_end_str);
	
    var _hov_from = point_in_rectangle(mouse_x, mouse_y, _draw_x + 54, y + 26, _draw_x + 90, y + 44);
    draw_set_color(_hov_from ? make_color_rgb(255, 255, 255) : make_color_rgb(150, 150, 215));

    var _sh = "$" + string_upper(decimal_to_hex(_start));
    while (string_length(_sh) < 5) _sh = string_insert("0", _sh, 2);

    draw_set_halign(fa_center);
    draw_text(_draw_x + 70, y + 28, _sh  );
    draw_set_halign(fa_left);

    // COUNT label
    draw_set_color(_c_edit);
    draw_text(_draw_x + 6, y + 42, "COUNT:");
    var _hov_count = point_in_rectangle(mouse_x, mouse_y, _draw_x + 58, y + 43, _draw_x + 70, y + 64);
    draw_set_color(_hov_count ? make_color_rgb(255, 255, 255) : make_color_rgb(150, 150, 215));
    draw_set_halign(fa_left);
    draw_text(_draw_x + 60, y + 42, string(_count));
	draw_set_color(_c_dim);
	draw_text(_draw_x + 74, y + 42, "  SPRITE(S) FLIPPED");
	
    draw_set_halign(fa_left);

    // MC auto-detected from asset at compile time


}