function scr_c64u_reu_fail(_message) {
    if (global.c64u_reu_socket >= 0) network_destroy(global.c64u_reu_socket);
    global.c64u_reu_socket   = -1;
    global.c64u_reu_state    = "idle";
    global.c64u_reu_after    = "";
    global.c64u_reu_path_a   = "";
    global.c64u_reu_path_b   = "";
    global.c64u_busy         = false;
    var _detail = "";

    if (global.c64u_reu_trace != "")
    {
        _detail = " [" + global.c64u_reu_trace + "]";
    }

    global.c64u_status       = "C64U REU: " + _message + _detail;
    global.c64u_status_t     = 600;
    show_debug_message("C64U REU upload failed: " + _message + _detail);
    return false;
}