/// @function scr_c64u_send_d64(d64_path)
/// @description Uploads a D64 to the C64 Ultimate and mounts it on drive A via
///              the REST API (multipart/form-data). Caller must have produced
///              the file at d64_path. Follow with a machine reset to boot it.
/// @param {String} d64_path  Absolute path to the .d64 file on disk
function scr_c64u_send_d64(d64_path)
{
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
    if (d64_path == "" || file_exists(d64_path) == false)
    {
        global.c64u_status   = "C64U: D64 file missing";
        global.c64u_status_t = 240;
        show_debug_message("C64U send: D64 not found at " + string(d64_path));
        return false;
    }

    // Load the D64 into a buffer
    var _d64 = buffer_load(d64_path);
    if (_d64 < 0)
    {
        global.c64u_status   = "C64U: could not read D64";
        global.c64u_status_t = 240;
        return false;
    }
    var _d64_sz = buffer_get_size(_d64);

    // Build multipart/form-data body manually.
    // Fields: file (the D64 bytes), mode=readwrite, type=d64
    var _boundary = "----C64DMBoundary7MA4YWxkTrZu0gW";
    var _crlf     = chr(13) + chr(10);

    var _body = buffer_create(_d64_sz + 1024, buffer_grow, 1);

    // --- file part header ---
    var _pre = "--" + _boundary + _crlf
             + "Content-Disposition: form-data; name=\"file\"; filename=\"program.d64\"" + _crlf
             + "Content-Type: application/octet-stream" + _crlf + _crlf;
    buffer_write(_body, buffer_text, _pre);

    // --- file bytes ---
    buffer_copy(_d64, 0, _d64_sz, _body, buffer_tell(_body));
    buffer_seek(_body, buffer_seek_relative, _d64_sz);
    buffer_delete(_d64);

    // --- mode part ---
    var _mode = _crlf + "--" + _boundary + _crlf
              + "Content-Disposition: form-data; name=\"mode\"" + _crlf + _crlf
              + "readwrite";
    buffer_write(_body, buffer_text, _mode);

    // --- type part ---
    var _type = _crlf + "--" + _boundary + _crlf
              + "Content-Disposition: form-data; name=\"type\"" + _crlf + _crlf
              + "d64";
    buffer_write(_body, buffer_text, _type);

    // --- closing boundary ---
    var _end = _crlf + "--" + _boundary + "--" + _crlf;
    buffer_write(_body, buffer_text, _end);

    var _url     = "http://" + global.c64u_ip + "/v1/drives/a:mount";
    var _headers = ds_map_create();
    ds_map_add(_headers, "Content-Type", "multipart/form-data; boundary=" + _boundary);
    if (global.c64u_password != "")
    {
        ds_map_add(_headers, "X-Password", global.c64u_password);
    }

    var _req_id = http_request(_url, "POST", _headers, _body);
    ds_map_destroy(_headers);

    if (_req_id < 0)
    {
        buffer_delete(_body);
        global.c64u_status   = "C64U: http_request failed";
        global.c64u_status_t = 240;
        return false;
    }

    global.c64u_busy          = true;
    global.c64u_request_id    = _req_id;
    global.c64u_buffer        = _body;
    global.c64u_pending_reset = true; // boot the disk once the mount POST returns OK
    global.c64u_status        = "C64U: mounting D64 on " + global.c64u_ip + "...";
    global.c64u_status_t      = 600;
    show_debug_message("C64U: POST " + _url + " (mount D64, " + string(_d64_sz) + " bytes)");
    return true;
}