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