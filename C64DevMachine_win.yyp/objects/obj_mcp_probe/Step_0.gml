// Stop immediately if the running editor changes edition.

// --- MCP-CON one-click setup button ---------------------------------------
// Look for the optional add-on every couple of seconds, so it can be installed
// without restarting the editor. Draw_64 hides both buttons while it is absent.
if (current_time >= setup_helper_check_at) {
    setup_helper_check_at = current_time + 2000;
    setup_helper_path = setup_script_path();
}
// Poll the helper's status file while it runs. Cheap: twice a second.
if (setup_state == "running") {
    if (current_time >= setup_poll_at) {
        setup_poll_at = current_time + 500;
        setup_poll();
    }
    if (setup_state == "running" && current_time > setup_deadline) {
        setup_state  = "failed";
        setup_status = "TIMEOUT";
        setup_detail = "setup did not finish; see mcp-setup-log.txt";
        probe_notice_until = current_time + 12000;
    }
}
// Draw_64 recalculates both rectangles every frame; hit-test against them here.
setup_hover = false;
reset_hover = false;
var _mcp_mx = device_mouse_x_to_gui(0);
var _mcp_my = device_mouse_y_to_gui(0);
var _mcp_can_click = (!global.ui_click_consumed && !global.any_picker_open
                      && mouse_check_button_pressed(mb_left));

if (setup_btn_x2 > 0
    && probe_state == "off" && (setup_state == "idle" || setup_state == "failed")) {
    if (point_in_rectangle(_mcp_mx, _mcp_my,
                           setup_btn_x1, setup_btn_y1,
                           setup_btn_x2, setup_btn_y2)) {
        setup_hover = true;
        if (_mcp_can_click) {
            global.ui_click_consumed = true;
            setup_run();
            exit;
        }
    }
}

if (reset_btn_x2 > 0 && reset_enabled) {
    if (point_in_rectangle(_mcp_mx, _mcp_my,
                           reset_btn_x1, reset_btn_y1,
                           reset_btn_x2, reset_btn_y2)) {
        reset_hover = true;
        if (_mcp_can_click) {
            global.ui_click_consumed = true;
            reset_run();
            exit;
        }
    }
}

// The normal editor and all networking handlers remain untouched.
if (keyboard_check(vk_control) && keyboard_check(vk_shift)
    && keyboard_check_pressed(vk_f12)) {
    if (probe_state != "off" && !keyboard_check(vk_alt)) {
        probe_auto_pair = false;
        ini_open("cdm-mcp-pairing.ini"); ini_write_real("pairing","enabled",0); ini_close();
        probe_stop("OFF - disconnected by user");
    } else if (!probe_busy()) {
        probe_stop("CONNECTING");
        probe_auto_pair = true;
        probe_start(keyboard_check(vk_alt));
    }
    else {
        probe_status = "OFF - close dialogs/editors and release the mouse first";
        probe_notice_until = current_time + 8000;
    }
    exit;
}
if (probe_restart_pending) { game_restart(); exit; }
if (probe_state == "off") {
    if (probe_auto_pair && probe_saved_key != "" && current_time >= probe_retry_at && !probe_busy()) {
        probe_retry_at = current_time + 5000;
        probe_start(false);
    }
    exit;
}
// Raw TCP clients may not receive a disconnect event. Require heartbeats.
if (current_time - probe_last_rx > 15000) {
    probe_stop("OFF - connection timed out; check the project before retrying");
    exit;
}
if (array_length(probe_queue) == 0) exit;
// One small command per frame; NOT a background compiler or an async edit.
var _wire = probe_queue[0];
array_delete(probe_queue, 0, 1);
var _msg;
try { _msg = json_parse(_wire); }
catch (_parse_error) { probe_stop("OFF - invalid JSON from bridge"); exit; }
if (!is_struct(_msg) || !variable_struct_exists(_msg, "token")
    || !is_string(_msg.token) || _msg.token != probe_token) {
    probe_stop("OFF - pairing key mismatch"); exit;
}
probe_last_rx = current_time;
if (variable_struct_exists(_msg, "event")) {
    if (_msg.event == "ready" && probe_state == "handshake"
        && variable_struct_exists(_msg, "protocol") && _msg.protocol == 1) {
        probe_state = "ready";
        probe_status = "CONNECTED - project tools enabled; Ctrl+Shift+F12 disconnects";
        ini_open("cdm-mcp-pairing.ini");
        ini_write_string("pairing","key",probe_saved_key);
        ini_write_real("pairing","enabled",1);
        ini_close();
    } else if (_msg.event == "heartbeat" && probe_state == "ready") {
        probe_send(json_stringify({event: "heartbeat"}));
    } else { probe_stop("OFF - unexpected bridge event"); }
    exit;
}
if (probe_state != "ready") { probe_stop("OFF - command before pairing"); exit; }
if (!variable_struct_exists(_msg, "id") || !is_real(_msg.id)
    || _msg.id < 1 || _msg.id > 1000000000 || _msg.id != floor(_msg.id)
    || !variable_struct_exists(_msg, "method") || !is_string(_msg.method)
    || !variable_struct_exists(_msg, "args") || !is_struct(_msg.args)) {
    probe_stop("OFF - invalid command envelope"); exit;
}
// Retransmission cannot add a second comment. IDs must increase per connection.
if (_msg.id <= probe_last_id) {
    if (_msg.id == probe_last_id && _wire == probe_last_wire) probe_send(probe_last_reply);
    else probe_stop("OFF - stale or reused request ID");
    exit;
}
var _reply;
try {
    var _result = probe_dispatch(_msg.method, _msg.args);
    _reply = {id: _msg.id, ok: true, result: _result};
} catch (_error) {
    var _message = is_struct(_error) && variable_struct_exists(_error, "message")
        ? string(_error.message) : string(_error);
    _reply = {id: _msg.id, ok: false, error: string_copy(_message, 1, 300)};
}
probe_last_id = _msg.id;
probe_last_wire = _wire;
probe_last_reply = json_stringify(_reply);
probe_send(probe_last_reply);
