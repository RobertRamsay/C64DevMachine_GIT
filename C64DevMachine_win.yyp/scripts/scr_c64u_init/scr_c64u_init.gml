/// @function scr_c64u_init()
/// @description Initialises C64 Ultimate networking state. Call once in Create event.
function scr_c64u_init()
{
    // --- State globals (always initialised, no variable_struct_exists at runtime) ---
    global.c64u_ip          = "";        // Saved IP, blank = not configured
    global.c64u_busy        = false;     // True while an HTTP request is in flight
    global.c64u_request_id  = -1;        // Current http_request() id, -1 = none
    global.c64u_pending_reset = false;   // true = a D64 mount is in flight; reset the machine once it succeeds
    global.c64u_run_after_mount = "";    // path to a boot PRG to run_prg after a successful D64 mount
    global.c64u_buffer      = -1;        // PRG buffer kept alive during POST
    global.c64u_status      = "";        // Last status string for HUD display
    global.c64u_status_t    = 0;         // Status display timer (frames)

    // --- Raw SocketDMA REU upload state (Ultimate TCP port 64) ---
    global.c64u_reu_socket       = -1;
    global.c64u_reu_state        = "idle";
    global.c64u_reu_deadline     = 0;
    global.c64u_reu_after        = "";
    global.c64u_reu_path_a       = "";
    global.c64u_reu_path_b       = "";
    global.reu_last_image        = "";
    global.reu_last_used         = 0;
    global.reu_build_error       = "";

    // --- Overlay state ---
    global.c64u_overlay_active = false;
    global.c64u_overlay_text   = "";
    global.c64u_overlay_error  = "";
    global.c64u_overlay_after  = "";     // "send_prg" = build+send after IP entered, "" = save only

    // --- Ping state (used during IP validation before save) ---
    global.c64u_ping_id        = -1;     // http_request id of in-flight ping, -1 = none
    global.c64u_ping_candidate = "";     // IP being tested
    global.c64u_ping_after     = "";     // what to do if ping succeeds

    // --- Cancel button hit-rect (set during draw, read during step) ---
    global.c64u_cancel_x1 = 0;
    global.c64u_cancel_y1 = 0;
    global.c64u_cancel_x2 = 0;
    global.c64u_cancel_y2 = 0;
    global.c64u_save_x1   = 0;
    global.c64u_save_y1   = 0;
    global.c64u_save_x2   = 0;
    global.c64u_save_y2   = 0;

    // --- INI path (matches your existing convention) ---
    global.c64u_ini_path = "c64devmachine.ini";

    // --- Load saved IP from [C64U] section ---
    global.c64u_password = "";

    ini_open(global.c64u_ini_path);
    global.c64u_ip       = ini_read_string("C64U", "ip",       "");
    global.c64u_password = ini_read_string("C64U", "password", "");
    ini_close();
}

function scr_c64u_reu_fail(_message) {
    if (global.c64u_reu_socket >= 0) network_destroy(global.c64u_reu_socket);
    global.c64u_reu_socket   = -1;
    global.c64u_reu_state    = "idle";
    global.c64u_reu_after    = "";
    global.c64u_reu_path_a   = "";
    global.c64u_reu_path_b   = "";
    global.c64u_busy         = false;
    global.c64u_status       = "C64U REU: " + _message;
    global.c64u_status_t     = 360;
    show_debug_message("C64U REU upload failed: " + _message);
    return false;
}

function scr_c64u_reu_continue() {
    var _after  = global.c64u_reu_after;
    var _path_a = global.c64u_reu_path_a;
    var _path_b = global.c64u_reu_path_b;

    if (global.c64u_reu_socket >= 0) network_destroy(global.c64u_reu_socket);
    global.c64u_reu_socket = -1;
    global.c64u_reu_state  = "idle";
    global.c64u_reu_after  = "";
    global.c64u_reu_path_a = "";
    global.c64u_reu_path_b = "";
    global.c64u_busy       = false;

    if (_after == "PRG") return scr_c64u_send_file(_path_a);
    if (_after == "D64") return scr_c64u_send_d64_and_run(_path_a, _path_b);
    return false;
}

function scr_c64u_reu_send_payload() {
    var _image = buffer_load(global.reu_last_image);
    if (_image < 0) return scr_c64u_reu_fail("could not open generated image");

    var _total = min(buffer_get_size(_image), max(0x100, real(global.reu_last_used)));
    var _offset = 0;
    var _chunk_max = 8192;

    while (_offset < _total) {
        var _chunk = min(_chunk_max, _total - _offset);
        // Ultimate SocketDMA frame: command $FF07, 16-bit payload length,
        // 24-bit REU destination, then raw bytes.
        var _packet = buffer_create(7 + _chunk, buffer_fixed, 1);
        buffer_poke(_packet, 0, buffer_u8, 0x07);
        buffer_poke(_packet, 1, buffer_u8, 0xFF);
        buffer_poke(_packet, 2, buffer_u8, (_chunk + 3) & 0xFF);
        buffer_poke(_packet, 3, buffer_u8, ((_chunk + 3) >> 8) & 0xFF);
        buffer_poke(_packet, 4, buffer_u8, _offset & 0xFF);
        buffer_poke(_packet, 5, buffer_u8, (_offset >> 8) & 0xFF);
        buffer_poke(_packet, 6, buffer_u8, (_offset >> 16) & 0xFF);
        buffer_copy(_image, _offset, _chunk, _packet, 7);

        var _sent = network_send_raw(global.c64u_reu_socket, _packet, 7 + _chunk);
        buffer_delete(_packet);
        if (_sent != 7 + _chunk) {
            buffer_delete(_image);
            return scr_c64u_reu_fail("network write stopped at $" + string_upper(decimal_to_hex(_offset)));
        }
        _offset += _chunk;
    }

    buffer_delete(_image);
    global.c64u_reu_state    = "settle";
    global.c64u_reu_deadline = current_time + 250;
    global.c64u_status       = "C64U REU: uploaded " + string(_total) + " bytes";
    global.c64u_status_t     = 240;
    show_debug_message("C64U REU: uploaded " + string(_total) + " bytes from " + global.reu_last_image);
    return true;
}

function scr_c64u_reu_send_auth() {
    var _password = global.c64u_password;
    var _len = string_length(_password);
    var _packet = buffer_create(4 + _len, buffer_fixed, 1);
    buffer_poke(_packet, 0, buffer_u8, 0x1F);
    buffer_poke(_packet, 1, buffer_u8, 0xFF);
    buffer_poke(_packet, 2, buffer_u8, _len & 0xFF);
    buffer_poke(_packet, 3, buffer_u8, (_len >> 8) & 0xFF);
    for (var _i = 0; _i < _len; _i++) {
        buffer_poke(_packet, 4 + _i, buffer_u8, ord(string_char_at(_password, _i + 1)) & 0xFF);
    }
    var _sent = network_send_raw(global.c64u_reu_socket, _packet, 4 + _len);
    buffer_delete(_packet);
    if (_sent != 4 + _len) return scr_c64u_reu_fail("password send failed");
    global.c64u_reu_state    = "auth";
    global.c64u_reu_deadline = current_time + 5000;
    return true;
}

function scr_c64u_reu_begin(_after, _path_a, _path_b) {
    if (global.reu_last_image == "" || !file_exists(global.reu_last_image)) {
        if (_after == "PRG") return scr_c64u_send_file(_path_a);
        if (_after == "D64") return scr_c64u_send_d64_and_run(_path_a, _path_b);
        return false;
    }
    if (global.c64u_busy) {
        global.c64u_status = "C64U: busy, please wait...";
        global.c64u_status_t = 120;
        return false;
    }

    var _socket = network_create_socket(network_socket_tcp);
    if (_socket < 0) return scr_c64u_reu_fail("could not create TCP socket");

    global.c64u_reu_socket   = _socket;
    global.c64u_reu_state    = "connecting";
    global.c64u_reu_deadline = current_time + 5000;
    global.c64u_reu_after    = _after;
    global.c64u_reu_path_a   = _path_a;
    global.c64u_reu_path_b   = _path_b;
    global.c64u_busy         = true;
    global.c64u_status       = "C64U REU: connecting to DMA service...";
    global.c64u_status_t     = 600;

    var _result = network_connect_raw_async(_socket, global.c64u_ip, 64);
    if (_result < 0) return scr_c64u_reu_fail("DMA service connection failed");
    return true;
}

function scr_c64u_async_network() {
    if (global.c64u_reu_state == "idle") return false;
    if (async_load[? "id"] != global.c64u_reu_socket) return false;
    var _type = async_load[? "type"];

    if (_type == network_type_non_blocking_connect) {
        if (async_load[? "succeeded"] != 1) return scr_c64u_reu_fail("enable Ultimate DMA Service (TCP port 64)");
        if (global.c64u_password != "") return scr_c64u_reu_send_auth();
        return scr_c64u_reu_send_payload();
    }

    if (_type == network_type_data && global.c64u_reu_state == "auth") {
        var _buf = async_load[? "buffer"];
        var _size = async_load[? "size"];
        if (_size < 1 || buffer_peek(_buf, 0, buffer_u8) != 1) return scr_c64u_reu_fail("DMA password rejected");
        return scr_c64u_reu_send_payload();
    }

    if (_type == network_type_disconnect) return scr_c64u_reu_fail("DMA service disconnected");
    return true;
}

function scr_c64u_reu_step() {
    if (global.c64u_reu_state == "idle") return;
    if (current_time < global.c64u_reu_deadline) return;
    if (global.c64u_reu_state == "settle") {
        scr_c64u_reu_continue();
    } else {
        scr_c64u_reu_fail("DMA service timed out");
    }
}
