// DRAW GUI BEGIN - event 74. (Draw_72 is Draw BEGIN, room space: the 8 Sep
// move landed there by mistake, so this overlay drew in the wrong space and
// was effectively invisible.) Was Draw GUI. This object sits at a nearer depth than
// obj_workspace_manager, so as a plain Draw GUI event its overlay was painted
// AFTER the menus, menu bar and code panel - on top of them. Draw GUI Begin
// runs for every instance before any Draw GUI event, so the manager's GUI
// (and the asset panel / message boxes) now always paints over this.
var _cam_zoom = obj_workspace_manager.cam_zoom;
var _alpha = clamp((_cam_zoom - 2.5) / 0.5, 0, 1);
if (_alpha <= 0) exit;

var _cam_x = obj_workspace_manager.cam_x;
var _cam_y = obj_workspace_manager.cam_y;

// Convert box centre-top to screen space
var _wx = x + (box_w * 0.5);
var _wy = y - 18; // top of the room-space tab
var _sx = (_wx - _cam_x) / _cam_zoom;
var _sy = (_wy - _cam_y) / _cam_zoom - 4; // screen-space gap above the tab

// Keep overview labels inside their own box, even at the furthest zoom.
draw_set_font_l(fnt_c64_tiny);
var _label_width = max(1, box_w / _cam_zoom - 8);
var _label_scale = min(1, _label_width / max(1, string_width_l(box_name)));
draw_set_halign(fa_center);
draw_set_valign(fa_bottom);

// Shadow
draw_set_alpha(_alpha * 0.6);
draw_set_color(c_black);
draw_text_transformed_l(_sx + 1, _sy + 1, box_name, _label_scale, _label_scale, 0);

// Label
draw_set_alpha(_alpha);
draw_set_color(box_colours[box_col_idx]);
draw_text_transformed_l(_sx, _sy, box_name, _label_scale, _label_scale, 0);

draw_set_alpha(1.0);
draw_set_halign(fa_left);
draw_set_valign(fa_top);