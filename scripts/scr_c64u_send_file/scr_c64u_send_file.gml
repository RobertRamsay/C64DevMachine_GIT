/// @function scr_c64u_send_file(prg_path)
/// @description Loads PRG from disk and POSTs it to the C64 Ultimate REST API
///              at http://<ip>/v1/runners:run_prg. Does NOT compile — the caller
///              must have already produced the file at prg_path.
/// @param {String} prg_path  Absolute path to the .prg file on disk
function scr_c64u_send_file(prg_path)
{
    // --- Guards ---
    if (global.c64u_busy == true)
    {
        global.c64u_status   = "C64U: busy, please wait...";
        global.c64u_status_t = 120;
        return false;
    }

    if (global.c64u_ip == "")
    {
        global.c64u_status   = "C64U: no IP configured";
        global.c64u_status_t = 240;
        return false;
    }

    if (prg_path == "" || file_exists(prg_path) == false)
    {
        global.c64u_status   = "C64U: PRG file missing";
        global.c64u_status_t = 240;
        show_debug_message("C64U send: PRG not found at " + string(prg_path));
        return false;
    }

    // --- Load PRG into buffer ---
    var _buf = buffer_load(prg_path);
    if (_buf < 0)
    {
        global.c64u_status   = "C64U: could not read PRG";
        global.c64u_status_t = 240;
        return false;
    }

    // --- Build URL and headers ---
    var _url     = "http://" + global.c64u_ip + "/v1/runners:run_prg";
    var _headers = ds_map_create();
    ds_map_add(_headers, "Content-Type", "application/octet-stream");
    if (global.c64u_password != "")
    {
        ds_map_add(_headers, "X-Password", global.c64u_password);
    }
    var _req_id = http_request(_url, "POST", _headers, _buf);
    ds_map_destroy(_headers);

    if (_req_id < 0)
    {
        buffer_delete(_buf);
        global.c64u_status   = "C64U: http_request failed";
        global.c64u_status_t = 240;
        return false;
    }

    // --- Stash state for async handler ---
    global.c64u_busy            = true;
    global.c64u_request_id      = _req_id;
    global.c64u_buffer          = _buf;
    global.c64u_pending_reset   = false; // this is a plain PRG send, not a D64 mount chain
    global.c64u_run_after_mount = "";
    global.c64u_status          = "C64U: sending to " + global.c64u_ip + "...";
    global.c64u_status_t        = 600;

    show_debug_message("C64U: POST " + _url + " (" + string(buffer_get_size(_buf)) + " bytes)");
    return true;
}