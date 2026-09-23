/// @desc Draw GUI End: help above every object's regular GUI, including assets.
var _info_visible = !hideui && !welcome_open && instance_exists(node_tooltip_node);
if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) _info_visible = false;
if (!_info_visible) {
    node_info_page = 0;
    node_info_active_type = "";
    exit;
}
if (is_undefined(scr_node_tooltip_text(node_tooltip_node.node_type))) exit;

var _info_alpha = draw_get_alpha();
var _info_color = draw_get_color();
var _info_gw = display_get_gui_width();
var _info_gh = display_get_gui_height();
// Asset editors can use a scissor region; the overlay covers the entire window.
gpu_set_scissor(0, 0, window_get_width(), window_get_height());
draw_set_color(c_black);
draw_set_alpha(0.6);
draw_rectangle(0, 0, _info_gw, _info_gh, false);
draw_set_alpha(1);
scr_node_info_panel_draw(node_tooltip_node.node_type, _info_gw, _info_gh);
draw_set_alpha(_info_alpha);
draw_set_color(_info_color);
