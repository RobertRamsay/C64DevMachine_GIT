/// @desc Draw MACRO_MAP node
/// @param {real} draw_x   Node top-left X
/// @param {real} draw_y   Node top-left Y
/// @param {real} cam_x    Camera X (unused but consistent signature)
/// @param {real} cam_y    Camera Y (unused)
/// @param {real} cam_zoom Camera zoom (unused)
function scr_node_draw_macro_map(draw_x, draw_y, cam_x, cam_y, cam_zoom) {

    var _asset_name = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
    var _map_w      = (array_length(instructions[0]) > 2) ? real(instructions[0][2]) : 40;
    var _map_h      = (array_length(instructions[0]) > 3) ? real(instructions[0][3]) : 25; // with 
    var _has_asset  = (_asset_name != "");

    var header_h = 28;
    var line_h   = 18;
    var pad      = 8;
/*
    // Header
    var _hcol = _has_asset ? make_color_rgb(80, 200, 120) : make_color_rgb(40, 60, 80);
    draw_set_color(_hcol);
    draw_rectangle(draw_x, draw_y, draw_x + width, draw_y + header_h, false);
    draw_set_font(fnt_c64_code);
    draw_set_color(c_black);
    draw_set_halign(fa_center);
    draw_text(draw_x + width * 0.5, draw_y + 6, "MACRO MAP");
    draw_set_halign(fa_left);

    // Body background
    draw_set_color(make_color_rgb(18, 28, 22));
    draw_rectangle(draw_x, draw_y + header_h, draw_x + width, draw_y + height, false);
*/

    var _ly = draw_y + header_h + pad;

    // MAP PICKER BUTTON
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "MAP:");

    var _pb_x1 = draw_x + 44;
    var _pb_x2 = draw_x + width - 8;
    var _pb_y1 = _ly - 2;
    var _pb_y2 = _ly + 14;
    var _pb_hover = point_in_rectangle(mouse_x, mouse_y, _pb_x1, _pb_y1, _pb_x2, _pb_y2);
    draw_set_color(_pb_hover ? make_color_rgb(80, 200, 120) : make_color_rgb(30, 60, 40));
    draw_rectangle(_pb_x1, _pb_y1, _pb_x2, _pb_y2, false);
    draw_set_color(_has_asset ? c_lime : make_color_rgb(150, 150, 150));
    draw_set_halign(fa_center);
    draw_text(_pb_x1 + (_pb_x2 - _pb_x1) * 0.5, _ly,
              _has_asset ? _asset_name : "[ PICK MAP ]");
    draw_set_halign(fa_left);
    _ly += line_h + 2;

    // SIZE INFO (from instructions or asset)
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "SIZE:");
    draw_set_color(c_white);
    draw_text(draw_x + 50, _ly, string(_map_w) + " x " + string(_map_h)
              + "  (" + string(_map_w * _map_h) + " CELLS)");
    _ly += line_h;

    // SCREEN RAM / COLOUR RAM targets
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "CHAR  -> $0400");
    _ly += line_h;
    var _col_row_st = (array_length(instructions[0]) > 5) ? real(instructions[0][5]) : 0;
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "COLOR -> $D800");
    _ly += line_h;
    // Colour row start spinner
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "COLOR START ROW:");
    var _sp_x1 = draw_x + width - 52;
    var _sp_mid = draw_x + width - 32;
    var _sp_x2 = draw_x + width - 8;
    var _sp_y1 = _ly - 2;
    var _sp_y2 = _ly + 14;
    draw_set_color(make_color_rgb(30, 60, 80));
    draw_rectangle(_sp_x1, _sp_y1, _sp_x2, _sp_y2, false);
    draw_set_color(make_color_rgb(80, 80, 80));
    draw_rectangle(_sp_x1, _sp_y1, _sp_x2, _sp_y2, true);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_sp_x1 + 10, _ly, "-");
    draw_text(_sp_mid,      _ly, string(_col_row_st));
    draw_text(_sp_x2 - 10, _ly, "+");
    draw_set_halign(fa_left);
_ly += line_h + 4;

// ZP SOURCE POINTER FIELD
var _zp_base = (array_length(instructions[0]) > 6) ? real(instructions[0][6]) : 0x50;
var _zp_hex  = decimal_to_hex(_zp_base);
if (string_length(_zp_hex) < 2) { _zp_hex = "0" + _zp_hex; }
_zp_hex = string_upper(_zp_hex);
var _zp_end     = _zp_base + 3;
var _zp_end_hex = decimal_to_hex(_zp_end);
if (string_length(_zp_end_hex) < 2) { _zp_end_hex = "0" + _zp_end_hex; }
_zp_end_hex = string_upper(_zp_end_hex);
draw_set_font(fnt_c64_tiny);
draw_set_color(c_ltgray);
draw_text(draw_x + 8, _ly, "MAP SRC ZP:");
var _zp_x1    = draw_x + width - 52;
var _zp_x2    = draw_x + width - 8;
var _zp_y1    = _ly - 2;
var _zp_y2    = _ly + 14;
var _zp_hover = point_in_rectangle(mouse_x, mouse_y, _zp_x1, _zp_y1, _zp_x2, _zp_y2);
draw_set_color(_zp_hover ? make_color_rgb(80, 160, 200) : make_color_rgb(20, 40, 60));
draw_rectangle(_zp_x1, _zp_y1, _zp_x2, _zp_y2, false);
draw_set_color(make_color_rgb(80, 80, 80));
draw_rectangle(_zp_x1, _zp_y1, _zp_x2, _zp_y2, true);
draw_set_color(c_white);
draw_set_halign(fa_center);
draw_text(_zp_x1 + (_zp_x2 - _zp_x1) * 0.5, _ly, "$" + _zp_hex);
draw_set_halign(fa_left);
_ly += line_h;
draw_set_color(make_color_rgb(100, 100, 100));
draw_text(draw_x + 8, _ly, "USES $" + _zp_hex + "-$" + _zp_end_hex + " (4 BYTES)");
_ly += line_h + 4;

// HR / MIXED TOGGLE — read from asset meta (single source of truth)
var _map_mode = obj_workspace_manager.map_global_mixed;
    var _tog_x1     = draw_x + 8;
    var _tog_x2     = draw_x + width - 8;
    var _tog_y1     = _ly;
    var _tog_y2     = _ly + 16;
    // read-only indicator, no hover needed
draw_set_color(_map_mode == 1
        ? make_color_rgb(160, 70, 10)
        : make_color_rgb(10, 60, 100));
    draw_rectangle(_tog_x1, _tog_y1, _tog_x2, _tog_y2, false);
    draw_set_color(make_color_rgb(80, 80, 80));
    draw_rectangle(_tog_x1, _tog_y1, _tog_x2, _tog_y2, true);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(180, 180, 180));
    draw_set_halign(fa_center);
    draw_text(_tog_x1 + (_tog_x2 - _tog_x1) * 0.5, _ly ,
              _map_mode == 1 ? "MIXED (HR + MC)" : "HR (16 COLOUR)");
    draw_set_halign(fa_left);
    _ly += line_h + 4;
    // Border
  //  draw_set_color(_has_asset ? make_color_rgb(60, 160, 90) : make_color_rgb(40, 50, 60));
 //   draw_rectangle(draw_x, draw_y, draw_x + width, draw_y + height, true);
}
