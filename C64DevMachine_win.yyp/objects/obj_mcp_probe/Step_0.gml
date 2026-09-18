// The normal editor and all networking handlers remain untouched.
if (keyboard_check(vk_control) && keyboard_check(vk_shift)
    && keyboard_check_pressed(vk_f12)) {
    if (probe_state != "off") probe_stop("OFF - disconnected by user");
    else if (!probe_busy()) probe_start();
    else {
        probe_status = "OFF - close dialogs/editors and release the mouse first";
        probe_notice_until = current_time + 8000;
    }
    exit;
}
if (probe_state == "off") exit;
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
        probe_status = "CONNECTED - comments enabled; Ctrl+Shift+F12 disconnects";
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
