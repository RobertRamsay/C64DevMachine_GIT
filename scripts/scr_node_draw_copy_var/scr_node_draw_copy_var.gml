/// @desc Draws the COPY_VAR node body (SRC -> DST)
function scr_node_draw_copy_var(_draw_x) {
   // var  = x + x_indent;

    var _src_raw = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
    var _dst_raw = (array_length(instructions[0]) > 2) ? string(instructions[0][2]) : "";
    var _src_name = (_src_raw != "") ? scr_nloc_display_name(_src_raw) : "(pick source)";
    var _dst_name = (_dst_raw != "") ? scr_nloc_display_name(_dst_raw) : "(pick dest)";

    draw_set_font(fnt_c64_tiny);

    // SRC row
    draw_set_color(make_color_rgb(120, 200, 140));
    draw_text(_draw_x + 8, y + 30, "FROM:");
    draw_set_color(c_yellow);
    draw_text(_draw_x + 48, y + 30, _src_name);

    // SRC lookup button
    var _sbx1 = _draw_x + width - 64;
    var _sbx2 = _draw_x + width - 4;
    var _sby1 = y + 30;
    var _sby2 = y + 44;
    var _shov = point_in_rectangle(mouse_x, mouse_y, _sbx1, _sby1, _sbx2, _sby2);
    draw_set_color(_shov ? make_color_rgb(60, 120, 80) : make_color_rgb(30, 60, 40));
    draw_rectangle(_sbx1, _sby1+2, _sbx2, _sby2, false);
    draw_set_color(_shov ? c_lime : make_color_rgb(80, 160, 80));

    draw_text(_sbx1 + 2, _sby1 , "PICK SRC");

    // DST row

    draw_set_color(make_color_rgb(220, 140, 100));
    draw_text(_draw_x + 8, y + 50, "TO:");
    draw_set_color(c_yellow);
    draw_text(_draw_x + 48, y + 50, _dst_name);

    // DST lookup button
    var _dbx1 = _draw_x + width - 64;
    var _dbx2 = _draw_x + width - 4;
    var _dby1 = y + 50;
    var _dby2 = y + 64;
    var _dhov = point_in_rectangle(mouse_x, mouse_y, _dbx1, _dby1, _dbx2, _dby2);
    draw_set_color(_dhov ? make_color_rgb(120, 80, 60) : make_color_rgb(60, 40, 30));
    draw_rectangle(_dbx1, _dby1+2, _dbx2, _dby2, false);
    draw_set_color(_dhov ? c_orange : make_color_rgb(200, 120, 80));

    draw_text(_dbx1 + 2, _dby1 , "PICK DST");

    // Size-mismatch info row
    var _msrc = scr_nloc_find_meta(_src_name);
    var _mdst = scr_nloc_find_meta(_dst_name);
    var _ssz = 1;
    var _dsz = 1;
    var _senc = "byte";
    var _denc = "byte";
    if (_msrc != undefined) {
        _ssz = _msrc.size;
        if (variable_struct_exists(_msrc, "encoding")) _senc = _msrc.encoding;
    }
    if (_mdst != undefined) {
        _dsz = _mdst.size;
        if (variable_struct_exists(_mdst, "encoding")) _denc = _mdst.encoding;
    }


    if (_senc != _denc) {
        draw_set_color(c_red);
        draw_text(_draw_x + 8, y + 74, "ENC MISMATCH: " + _senc + " -> " + _denc);
    } else if (_ssz != _dsz) {
        draw_set_color(c_orange);
        draw_text(_draw_x + 8, y + 74, "SIZE: " + string(_ssz) + " -> " + string(_dsz));
    } else {
        draw_set_color(make_color_rgb(120, 180, 120));
        draw_text(_draw_x + 8, y + 74, "COPY " + string(_ssz) + " BYTE" + ((_ssz > 1) ? "S" : "") + " (" + _senc + ")");
    }
}