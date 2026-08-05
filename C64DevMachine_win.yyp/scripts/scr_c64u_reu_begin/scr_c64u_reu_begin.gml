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