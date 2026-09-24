

// --- MCP control buttons ---------------------------------------------------
// The old status line drawn along the bottom edge has been removed: it sat at
// gui_h-32..gui_h-7 and ran straight over the memory bar and the VIC BANK
// labels. All state is shown in the MCP-CON button instead.
//
// Bottom-right occupancy at this GUI size, measured from the drawing code:
//   asset panel     y 410 .. gui_h-100   (obj_asset_manager, _panel_bottom)
//   snapshot button y gui_h-50 .. gui_h-10 (40x40 around 1886,1050)
//   memory bar      y gui_h-40 .. gui_h-25 (scr_draw_memory_bar)
// The only clear band is gui_h-100 .. gui_h-50, so both buttons sit inside it
// with a 12px gap top and bottom. The right edge lines up with the snapshot
// button at gui_w-14.

// With the optional tools/cdm-mcp add-on absent there is nothing the buttons
// could do, so show no MCP interface at all. An editor that is already paired
// or connected keeps its buttons either way.
var _mcp_blocked = false;
if (setup_helper_path == "" && probe_state == "off" && probe_saved_key == "") _mcp_blocked = true;

// Never draw over a modal, the asset viewer, or a hidden UI.
if (!instance_exists(obj_workspace_manager)) _mcp_blocked = true;
else if (obj_workspace_manager.hideui) _mcp_blocked = true;
if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) _mcp_blocked = true;
if (instance_exists(obj_message_box) || instance_exists(obj_question_box)) _mcp_blocked = true;

if (_mcp_blocked) {
    // Keep both hit rectangles empty while the buttons are off screen.
    setup_btn_x1 = 0;
    setup_btn_y1 = 0;
    setup_btn_x2 = 0;
    setup_btn_y2 = 0;
    reset_btn_x1 = 0;
    reset_btn_y1 = 0;
    reset_btn_x2 = 0;
    reset_btn_y2 = 0;
    exit;
}

var _mcp_gui_w = display_get_gui_width();
var _mcp_gui_h = display_get_gui_height();
var _mcp_y1 = _mcp_gui_h - 88;
var _mcp_y2 = _mcp_gui_h - 62;
var _mcp_right = _mcp_gui_w - 14;

// --- MCP-CON label reflects the whole connection state ---------------------
var _con_label = "[ MCP-CON ]";
if (setup_state == "running") {
    _con_label = "MCP: " + setup_detail;
}
else if (setup_state == "failed") {
    _con_label = "[ MCP-CON ] " + setup_detail;
}
else if (probe_state == "ready") {
    _con_label = "MCP - awaiting instructions";
}
else if (probe_state == "connecting" || probe_state == "handshake") {
    _con_label = "MCP - connecting";
}
else if (setup_state == "done") {
    _con_label = "MCP - awaiting instructions";
}
else if (current_time <= probe_notice_until && probe_status != "") {
    _con_label = "[ MCP-CON ] " + string_copy(probe_status, 1, 70);
}

var _con_clickable = false;
if (probe_state == "off" && (setup_state == "idle" || setup_state == "failed")) _con_clickable = true;

var _reset_label = "[ RESET ]";
reset_enabled = false;
if (probe_state != "off" || probe_saved_key != "" || setup_state != "idle") reset_enabled = true;

// --- draw ------------------------------------------------------------------
var _m_font = draw_get_font();
var _m_alpha = draw_get_alpha();
var _m_colour = draw_get_colour();
var _m_ha = draw_get_halign();
var _m_va = draw_get_valign();
draw_set_font(-1);
draw_set_halign(fa_left);
draw_set_valign(fa_top);

// RESET sits on the right; MCP-CON grows leftwards from it as its label grows.
reset_btn_y1 = _mcp_y1;
reset_btn_y2 = _mcp_y2;
reset_btn_x2 = _mcp_right;
reset_btn_x1 = reset_btn_x2 - (string_width(_reset_label) + 20);

setup_btn_y1 = _mcp_y1;
setup_btn_y2 = _mcp_y2;
setup_btn_x2 = reset_btn_x1 - 8;
setup_btn_x1 = max(8, setup_btn_x2 - (string_width(_con_label) + 20));

// MCP-CON
draw_set_alpha(0.9);
draw_set_colour(c_black);
draw_rectangle(setup_btn_x1, setup_btn_y1, setup_btn_x2, setup_btn_y2, false);
draw_set_alpha(1);
if (_con_clickable && setup_hover) draw_set_colour(c_yellow);
else draw_set_colour(c_silver);
draw_rectangle(setup_btn_x1, setup_btn_y1, setup_btn_x2, setup_btn_y2, true);
if (setup_state == "failed") draw_set_colour(c_orange);
else if (probe_state == "ready") draw_set_colour(c_lime);
else if (setup_state == "done") draw_set_colour(c_lime);
else if (_con_clickable && setup_hover) draw_set_colour(c_yellow);
else draw_set_colour(c_white);
draw_text(setup_btn_x1 + 10, setup_btn_y1 + 4, _con_label);

// RESET
draw_set_alpha(0.9);
draw_set_colour(c_black);
draw_rectangle(reset_btn_x1, reset_btn_y1, reset_btn_x2, reset_btn_y2, false);
draw_set_alpha(1);
if (reset_enabled && reset_hover) draw_set_colour(c_yellow);
else draw_set_colour(c_silver);
draw_rectangle(reset_btn_x1, reset_btn_y1, reset_btn_x2, reset_btn_y2, true);
if (!reset_enabled) draw_set_colour(c_gray);
else if (reset_hover) draw_set_colour(c_yellow);
else draw_set_colour(c_white);
draw_text(reset_btn_x1 + 10, reset_btn_y1 + 4, _reset_label);

draw_set_font(_m_font);
draw_set_alpha(_m_alpha);
draw_set_colour(_m_colour);
draw_set_halign(_m_ha);
draw_set_valign(_m_va);
