/// @desc Mapping Box Draw

var _cam_x    = obj_workspace_manager.cam_x;
var _cam_y    = obj_workspace_manager.cam_y;
var _cam_zoom = obj_workspace_manager.cam_zoom;
var _col      = box_colours[box_col_idx];

// Main filled box
draw_set_alpha(0.15);
draw_set_color(_col);
draw_rectangle(x, y, x + box_w, y + box_h, false);

// Border
draw_set_alpha(0.7);
draw_set_color(_col);
draw_rectangle(x, y, x + box_w, y + box_h, true);
draw_set_alpha(1.0);

// Tab label (top left, above box)
var _tab_pad = 8;
draw_set_font(fnt_c64_code);
var _tw = string_width(box_name) + (_tab_pad * 2);
var _th = 18;
draw_set_color(_col);
draw_rectangle(x, y - _th, x + _tw, y, false);
draw_set_color(c_black);
draw_text(x + _tab_pad, y - _th + 2, box_name);

// Resize handle triangle (bottom right)
draw_set_color(_col);
draw_set_alpha(0.8);
draw_triangle(x + box_w,      y + box_h,
              x + box_w - 16, y + box_h,
              x + box_w,      y + box_h - 16, false);
draw_set_alpha(1.0);

// Delete button (top right, above box)
draw_set_color(make_color_rgb(180, 40, 40));
draw_rectangle(x + box_w - 18, y - 18, x + box_w, y, false);
draw_set_color(c_white);
draw_set_halign(fa_center);
draw_text(x + box_w - 9, y - 16, "X");
draw_set_halign(fa_left);