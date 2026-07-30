/// @function scr_c64u_ping(ip_string, after_action)
/// @description Fires a GET to http://<ip>/v1/version to verify the device is
///              reachable BEFORE committing the IP to disk. The async handler
///              will save the IP and (optionally) kick off the build on success.
/// @param {String} ip_string     Candidate IP to test
/// @param {String} after_action  "send_prg" to trigger build+send on success, "" to just save
function scr_c64u_ping(ip_string, after_action)
{
    if (global.c64u_busy == true)
    {
        global.c64u_overlay_error = "Busy with previous request...";
        return;
    }

    var _url     = "http://" + ip_string + "/v1/version";
    var _headers = ds_map_create();
    if (global.c64u_password != "")
    {
        ds_map_add(_headers, "X-Password", global.c64u_password);
    }
    var _req_id = http_request(_url, "GET", _headers, -1);
    ds_map_destroy(_headers);

    if (_req_id < 0)
    {
        global.c64u_overlay_error = "Could not start request";
        return;
    }
    global.c64u_busy           = true;
    global.c64u_request_id     = _req_id;
    global.c64u_ping_id        = _req_id;        // marks this as a ping, not a PRG send
    global.c64u_ping_candidate = ip_string;
    global.c64u_ping_password  = global.c64u_password;
    global.c64u_ping_after     = after_action;
    global.c64u_overlay_error  = "Pinging " + ip_string + "...";
    show_debug_message("C64U ping: GET " + _url);
}