/// Optional MCP proof of concept. No socket exists until the user opts in.
/// Ctrl+Shift+F12 reads a pairing key from the clipboard, or disconnects.
probe_socket = -1;
probe_state = "off";
probe_token = "";
probe_rx = -1;
probe_rx_len = 0;
probe_queue = [];
probe_last_rx = 0;
probe_last_id = 0;
probe_last_wire = "";
probe_last_reply = "";
probe_status = "OFF - Ctrl+Shift+F12 to pair";
probe_notice_until = current_time + 6000;
probe_max_line = 16384;

probe_stop = function(_reason) {
    if (probe_socket >= 0) network_destroy(probe_socket);
    probe_socket = -1;
    if (probe_rx >= 0 && buffer_exists(probe_rx)) buffer_delete(probe_rx);
    probe_rx = -1;
    probe_rx_len = 0;
    probe_queue = [];
    probe_token = "";
    probe_state = "off";
    probe_last_wire = "";
    probe_last_reply = "";
    probe_status = _reason;
    probe_notice_until = current_time + 10000;
};

probe_send = function(_text) {
    if (probe_socket < 0) return false;
    // buffer_tell counts UTF-8 bytes, not characters. No trailing NUL is sent.
    var _buf = buffer_create(1024, buffer_grow, 1);
    buffer_write(_buf, buffer_text, _text + "\n");
    var _size = buffer_tell(_buf);
    if (_size > 65536) {
        buffer_delete(_buf);
        probe_stop("OFF - reply exceeded limit");
        return false;
    }
    var _sent = network_send_raw(probe_socket, _buf, _size);
    buffer_delete(_buf);
    // Fail closed on partial sends. Never resend a mutation automatically.
    if (_sent != _size) {
        probe_stop("OFF - send failed; check the project before retrying");
        return false;
    }
    return true;
};

probe_workspace_key = function() {
    // Instance identity changes on load/undo; count also detects additions.
    // This is a conservative context guard, not a general project revision.
    return string(instance_find(obj_c64_node, 0)) + ":"
        + string(instance_number(obj_c64_node));
};

probe_busy = function() {
    if (!instance_exists(obj_workspace_manager)) return true;
    if (instance_exists(obj_question_box)) return true;
    if (mouse_check_button(mb_any)) return true;
    if (variable_global_exists("is_any_text_active") && global.is_any_text_active) return true;
    if (variable_global_exists("canEditNode") && !global.canEditNode) return true;
    var _wm = instance_find(obj_workspace_manager, 0);
    var _flags = ["welcome_open", "is_entering_text", "code_editor_open",
                  "box_popup_open", "is_panning", "editor_release_pending",
                  "editor_layout_refresh_requested", "flow_overlay_build_pending"];
    for (var _i = 0; _i < array_length(_flags); _i++) {
        if (variable_instance_exists(_wm, _flags[_i])
            && variable_instance_get(_wm, _flags[_i])) return true;
    }
    var _dragging = false;
    with (obj_c64_node) {
        if (is_dragging) { _dragging = true; break; }
    }
    return _dragging;
};

probe_node_info = function(_node) {
    var _result = {
        uid: scr_get_node_uid(_node),
        type: _node.node_type,
        title: string_copy(string(_node.node_title), 1, 100),
        x: _node.x, y: _node.y,
        connected: _node.is_connected
    };
    if (_node.node_type == "COMMENT") {
        _result.text = string_copy(string(_node.instructions[0][1]), 1, 256);
    }
    return _result;
};

probe_dispatch = function(_method, _args) {
    if (_method == "ping") {
        return {pong: true, application: "C64 Dev Machine", prototype: "0.1.0",
                workspace_key: probe_workspace_key(), busy: probe_busy()};
    }
    if (probe_busy()) throw "Editor busy: close dialogs/editors and release the mouse, then retry.";
    if (_method == "project_summary") {
        var _offset = variable_struct_exists(_args, "offset") ? _args.offset : 0;
        var _limit = variable_struct_exists(_args, "limit") ? _args.limit : 50;
        if (!is_real(_offset) || _offset < 0 || _offset != floor(_offset)
            || _offset > 1000000 || !is_real(_limit) || _limit != floor(_limit)
            || _limit < 1 || _limit > 100) throw "Invalid page; limit must be 1..100.";
        var _count = instance_number(obj_c64_node);
        var _nodes = [];
        var _bytes = 0;
        for (var _i = _offset; _i < min(_count, _offset + _limit); _i++) {
            var _node = instance_find(obj_c64_node, _i);
            if (instance_exists(_node)) {
                var _info = probe_node_info(_node);
                var _cost = string_byte_length(json_stringify(_info)) + 1;
                // Leave room for JSON-RPC text wrapping in the MCP bridge.
                if (_bytes + _cost > 24000) break;
                _bytes += _cost;
                array_push(_nodes, _info);
            }
        }
        var _name = "Untitled";
        if (variable_global_exists("workspace_path") && global.workspace_path != "") {
            _name = string_copy(filename_name(global.workspace_path), 1, 100);
        }
        return {project: _name, workspace_key: probe_workspace_key(), node_count: _count,
                offset: _offset, limit: _limit, next_offset: _offset + array_length(_nodes),
                has_more: _offset + array_length(_nodes) < _count,
                nodes: _nodes};
    }
    if (!variable_struct_exists(_args, "expected_workspace")
        || !is_string(_args.expected_workspace)
        || _args.expected_workspace != probe_workspace_key()) {
        throw "Workspace changed. Read project_summary again before acting.";
    }
    if (_method == "focus_node") {
        if (!variable_struct_exists(_args, "uid") || !is_real(_args.uid)
            || _args.uid < 0 || _args.uid != floor(_args.uid)) throw "Invalid node UID.";
        var _found = noone;
        var _uid = _args.uid;
        with (obj_c64_node) {
            if (stable_uid == _uid) { _found = id; break; }
        }
        if (!instance_exists(_found)) throw "Node not found. Read project_summary again.";
        scr_focus_camera_on_node(_found);
        return {focused_uid: _uid};
    }
    if (_method != "add_comment") throw "Unknown command; this prototype only supports comments.";
    if (!variable_struct_exists(_args, "text") || !is_string(_args.text)) throw "Text is required.";
    var _text = _args.text;
    if (string_length(_text) < 1 || string_length(_text) > 256) throw "Text must be 1..256 characters.";
    // Deliberately narrow first test: one line of printable ASCII, no markup.
    for (var _i = 1; _i <= string_length(_text); _i++) {
        var _ch = ord(string_char_at(_text, _i));
        if (_ch < 32 || _ch > 126) throw "Prototype comments accept printable ASCII only.";
    }
    // Bound the demo's disk-backed snapshot cost; use a small scratch workspace.
    if (instance_number(obj_c64_node) > 200) throw "Use a scratch project with at most 200 nodes for this test.";
    var _wm = instance_find(obj_workspace_manager, 0);
    var _xx = _wm.cam_x + 1000 * _wm.cam_zoom;
    var _yy = _wm.cam_y + 400 * _wm.cam_zoom;
    if (variable_struct_exists(_args, "x")) _xx = _args.x;
    if (variable_struct_exists(_args, "y")) _yy = _args.y;
    if (!is_real(_xx) || !is_real(_yy) || is_nan(_xx) || is_nan(_yy)
        || abs(_xx) > 1000000 || abs(_yy) > 1000000) throw "Invalid comment coordinates.";
    if (!variable_global_exists("undo_states") || global.undo_states < 2) {
        throw "Enable at least two undo states before running the comment test.";
    }
    var _new = noone;
    // Capture a pre-edit state even if a previous keyboard edit was unsnapped.
    scr_undo_snapshot();
    try {
        _new = scr_spawn_comment_node(_xx, _yy);
        _new.instructions = [["Comment", _text]];
        scr_comment_sync_layout(_new);
        _new.height_dirty = true;
        scr_undo_snapshot();
    } catch (_error) {
        if (instance_exists(_new)) instance_destroy(_new);
        throw _error;
    }
    global.undo_dirty = false;
    global.manual_saved = false;
    global.autosave_dirty = true;
    if (global.autosave_mode != 3) {
        _wm.alarm[4] = max(_wm.alarm[4], game_get_speed(gamespeed_fps) * 5);
    }
    scr_focus_camera_on_node(_new);
    probe_status = "CONNECTED - comment added; Ctrl+Z to undo";
    return {created: probe_node_info(_new), workspace_key: probe_workspace_key(),
            undo: "Use the normal Ctrl+Z in Dev Machine.", saved: false};
};

probe_start = function() {
    // Explicit shortcut opt-in is the ONLY clipboard access in this object.
    var _key = string_trim(clipboard_get_text());
    var _parts = string_split(_key, ":");
    if (array_length(_parts) != 3 || _parts[0] != "cdm1") {
        probe_stop("OFF - copy the pairing key first (see tools/cdm-mcp/README.md)");
        return;
    }
    var _port_text = _parts[1];
    var _token = string_lower(_parts[2]);
    if (string_length(_port_text) < 1 || string_length(_port_text) > 5
        || string_digits(_port_text) != _port_text || string_length(_token) != 64) {
        probe_stop("OFF - invalid pairing key"); return;
    }
    for (var _i = 1; _i <= 64; _i++) {
        if (string_pos(string_char_at(_token, _i), "0123456789abcdef") == 0) {
            probe_stop("OFF - invalid pairing key"); return;
        }
    }
    var _port = real(_port_text);
    if (_port < 1024 || _port > 65535) { probe_stop("OFF - invalid port"); return; }
    probe_token = _token;
    probe_rx = buffer_create(probe_max_line + 1, buffer_fixed, 1);
    probe_rx_len = 0;
    probe_queue = [];
    probe_last_id = 0;
    probe_last_wire = "";
    probe_last_reply = "";
    probe_last_rx = current_time;
    probe_state = "connecting";
    probe_status = "CONNECTING - Ctrl+Shift+F12 to disconnect";
    probe_socket = network_create_socket(network_socket_tcp);
    if (probe_socket < 0
        || network_connect_raw_async(probe_socket, "127.0.0.1", _port) < 0) {
        probe_stop("OFF - connection failed; start the local bridge first");
    }
};
