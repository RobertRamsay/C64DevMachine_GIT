

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
else if (probe_auto_pair && probe_saved_key != "") {
    _con_label = "MCP - waiting for your assistant";
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

// --- Hover help: what to do next, for the state the connection is in -------
var _tip_mx = device_mouse_x_to_gui(0);
var _tip_my = device_mouse_y_to_gui(0);
var _tip = "";
if (point_in_rectangle(_tip_mx, _tip_my, setup_btn_x1, setup_btn_y1, setup_btn_x2, setup_btn_y2)) {
    // Reading these steps arms pairing from the clipboard on return (Step).
    if (probe_state == "off") clip_armed_until = current_time + 900000;
    if (probe_state == "ready") {
        _tip = "CONNECTED\n"
             + "Ask your AI assistant to look at or change this project, e.g. \"use c64-dev-machine to add a comment\".\n"
             + "Every MCP edit can be undone with Ctrl+Z. Ctrl+Shift+F12 disconnects. RESET forgets the pairing.";
    }
    else if (probe_state == "connecting" || probe_state == "handshake") {
        _tip = "CONNECTING\nTalking to the bridge your assistant started. This takes a second or two.";
    }
    else if (setup_state == "running") {
        _tip = "SETTING UP: " + setup_detail + "\n"
             + "If Windows asks to install Node.js, allow it. Leave this editor open: it picks up the pairing key by itself when setup finishes.";
    }
    else if (setup_state == "failed") {
        var _fix = "Click MCP-CON to try again, or RESET to start over. Details: mcp-setup-log.txt in " + game_save_id;
        if (setup_status == "NODE_MISSING" || setup_status == "NODE_INSTALL_FAIL"
            || setup_status == "NODE_TOO_OLD" || setup_status == "NO_WINGET") {
            _fix = "Install Node.js 22 or newer from nodejs.org, then click MCP-CON again.";
        }
        else if (setup_status == "NO_HOST") {
            _fix = "Node.js and the pairing key are ready, but no Claude Code or Codex command line was found.\n"
                 + "Install one, then click MCP-CON again to register the bridge with it. This editor keeps retrying and connects by itself once the assistant runs the bridge.";
        }
        else if (setup_status == "BRIDGE_MISSING") {
            _fix = "tools/cdm-mcp/bridge.mjs is missing. Reinstall the tools folder next to the editor, then click MCP-CON again.";
        }
        _tip = "SETUP STOPPED: " + setup_detail + "\n" + _fix;
    }
    else if (probe_saved_key != "" && probe_auto_pair) {
        _tip = "PAIRED - WAITING FOR YOUR ASSISTANT\n"
             + "1. Open (or restart) Claude Code or Codex. Its MCP connection starts the bridge.\n"
             + "2. Come back here. The editor retries every 5 seconds and turns green when it connects.";
    }
    else if (probe_saved_key != "") {
        _tip = "DISCONNECTED\nPress Ctrl+Shift+F12 to reconnect with the saved key, or RESET to forget it.";
    }
    else {
        _tip = "CONNECT AN AI ASSISTANT (PRO)\n"
             + "Lets Claude Code or Codex inspect, edit and build this project for you.\n"
             + "1. Click MCP-CON. It checks Node.js 22+, registers the bridge with your assistant and pairs this editor. No key to copy.\n"
             + "2. Open (or restart) your assistant and ask it to use c64-dev-machine.\n"
             + "3. Come back here. It connects by itself and the button turns green.\n"
             + "MANUAL: run  node tools/cdm-mcp/bridge.mjs --pair | Set-Clipboard  then come back to this window. "
             + "The key is picked up from the clipboard automatically (or press Ctrl+Shift+F12).";
    }
}
else if (reset_enabled && point_in_rectangle(_tip_mx, _tip_my, reset_btn_x1, reset_btn_y1, reset_btn_x2, reset_btn_y2)) {
    _tip = "RESET\nDisconnects, forgets the saved pairing key and puts MCP-CON back to first-run setup.";
}
if (_tip != "") {
    var _tip_w   = 520;
    var _tip_sep = 18;
    var _tip_h   = string_height_ext(_tip, _tip_sep, _tip_w - 20) + 16;
    var _tip_x2  = _mcp_right;
    var _tip_x1  = max(8, _tip_x2 - _tip_w);
    var _tip_y2  = _mcp_y1 - 6;
    var _tip_y1  = _tip_y2 - _tip_h;
    draw_set_alpha(0.94);
    draw_set_colour(make_colour_rgb(16, 16, 28));
    draw_rectangle(_tip_x1, _tip_y1, _tip_x2, _tip_y2, false);
    draw_set_alpha(1);
    draw_set_colour(c_yellow);
    draw_rectangle(_tip_x1, _tip_y1, _tip_x2, _tip_y2, true);
    draw_set_colour(c_white);
    draw_text_ext(_tip_x1 + 10, _tip_y1 + 8, _tip, _tip_sep, _tip_w - 20);
}

draw_set_font(_m_font);
draw_set_alpha(_m_alpha);
draw_set_colour(_m_colour);
draw_set_halign(_m_ha);
draw_set_valign(_m_va);
