if (global.lite != 0) exit;

// --- MCP-CON one-click setup button ---------------------------------------
// Bottom-right occupancy at this GUI size, measured from the drawing code:
//   asset panel     y 410 .. gui_h-100   (obj_asset_manager, _panel_bottom)
//   snapshot button y gui_h-50 .. gui_h-10 (40x40 around 1886,1050)
//   memory bar      y gui_h-40 .. gui_h-25 (scr_draw_memory_bar)
//   MCP badge       y gui_h-32 .. gui_h-7  (below)
// The only clear band is gui_h-100 .. gui_h-50, so the button sits inside it
// with a 12px gap top and bottom. Right edge stops at gui_w-30, inside the
// asset panel's own right edge, so nothing is ever covered.
var _setup_gui_w = display_get_gui_width();
var _setup_gui_h = display_get_gui_height();
setup_btn_y1 = _setup_gui_h - 88;
setup_btn_y2 = _setup_gui_h - 62;
setup_btn_x2 = _setup_gui_w - 30;

var _setup_label = "";
var _setup_clickable = false;
if (probe_state == "off" && setup_state == "idle") {
    _setup_label = "[ MCP-CON ]";
    _setup_clickable = true;
}
else if (probe_state == "off" && setup_state == "failed") {
    _setup_label = "[ MCP-CON ] " + setup_detail;
    _setup_clickable = true;
}
else if (setup_state == "running") {
    _setup_label = "MCP: " + setup_detail;
}
else if (setup_state == "done" && probe_state != "ready") {
    _setup_label = "MCP - awaiting instructions";
}

// Never draw over a modal, the asset viewer, or a hidden UI.
var _setup_blocked = false;
if (!instance_exists(obj_workspace_manager)) _setup_blocked = true;
else if (obj_workspace_manager.hideui) _setup_blocked = true;
if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) _setup_blocked = true;
if (instance_exists(obj_message_box) || instance_exists(obj_question_box)) _setup_blocked = true;

if (_setup_label != "" && !_setup_blocked) {
    var _s_font = draw_get_font();
    var _s_alpha = draw_get_alpha();
    var _s_colour = draw_get_colour();
    var _s_ha = draw_get_halign();
    var _s_va = draw_get_valign();
    draw_set_font(-1);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    var _s_w = string_width(_setup_label) + 20;
    setup_btn_x1 = max(8, setup_btn_x2 - _s_w);
    draw_set_alpha(0.9);
    draw_set_colour(c_black);
    draw_rectangle(setup_btn_x1, setup_btn_y1, setup_btn_x2, setup_btn_y2, false);
    draw_set_alpha(1);
    if (_setup_clickable && setup_hover) draw_set_colour(c_yellow);
    else draw_set_colour(c_silver);
    draw_rectangle(setup_btn_x1, setup_btn_y1, setup_btn_x2, setup_btn_y2, true);
    if (setup_state == "failed") draw_set_colour(c_orange);
    else if (setup_state == "done") draw_set_colour(c_lime);
    else if (_setup_clickable && setup_hover) draw_set_colour(c_yellow);
    else draw_set_colour(c_white);
    draw_text(setup_btn_x1 + 10, setup_btn_y1 + 4, _setup_label);
    draw_set_font(_s_font);
    draw_set_alpha(_s_alpha);
    draw_set_colour(_s_colour);
    draw_set_halign(_s_ha);
    draw_set_valign(_s_va);
}
else {
    // Keep the hit rectangle empty whenever the button is not on screen.
    setup_btn_x1 = 0;
    setup_btn_y1 = 0;
    setup_btn_x2 = 0;
    setup_btn_y2 = 0;
}

if (probe_state == "off" && current_time > probe_notice_until) exit;
// Save/restore draw state so this optional badge cannot affect editor drawing.
var _font = draw_get_font();
var _alpha = draw_get_alpha();
var _colour = draw_get_colour();
var _ha = draw_get_halign();
var _va = draw_get_valign();
draw_set_font(-1);
draw_set_halign(fa_left);
draw_set_valign(fa_top);
var _text = "MCP: " + probe_status;
var _w = string_width(_text) + 20;
var _x = max(8, display_get_gui_width() - _w - 12);
var _y = display_get_gui_height() - 32;
draw_set_alpha(0.9);
draw_set_colour(c_black);
draw_rectangle(_x, _y, _x + _w, _y + 25, false);
draw_set_alpha(1);
draw_set_colour(probe_state == "ready" ? c_lime : c_white);
draw_text(_x + 10, _y + 4, _text);
draw_set_font(_font);
draw_set_alpha(_alpha);
draw_set_colour(_colour);
draw_set_halign(_ha);
draw_set_valign(_va);
