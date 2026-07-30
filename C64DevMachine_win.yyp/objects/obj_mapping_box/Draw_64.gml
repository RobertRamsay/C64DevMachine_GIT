var _cam_zoom = obj_workspace_manager.cam_zoom;
var _alpha = clamp((_cam_zoom - 2.5) / 0.5, 0, 1);
if (_alpha <= 0) exit;

var _cam_x = obj_workspace_manager.cam_x;
var _cam_y = obj_workspace_manager.cam_y;

// Convert box centre-top to screen space
var _wx = x + (box_w * 0.5);
var _wy = y - 9; // vertically centred in the tab
var _sx = (_wx - _cam_x) / _cam_zoom;
var _sy = (_wy - _cam_y) / _cam_zoom;

draw_set_font(fnt_c64_code);
draw_set_halign(fa_center);
draw_set_valign(fa_middle);

// Shadow
draw_set_alpha(_alpha * 0.6);
draw_set_color(c_black);
draw_text(_sx + 1, _sy + 1, box_name);

// Label
draw_set_alpha(_alpha);
draw_set_color(box_colours[box_col_idx]);
draw_text(_sx, _sy, box_name);

draw_set_alpha(1.0);
draw_set_halign(fa_left);
draw_set_valign(fa_top);