/// @function scr_c64u_async_http()
/// @description Handles HTTP responses for C64U. Distinguishes between an
///              in-flight ping (validating an IP before save), a PRG send,
///              a D64 mount, and a chained boot-PRG run after a mount.
///              Call from obj_workspace_manager Async - HTTP event.
function scr_c64u_async_http()
{
    var _id = async_load[? "id"];

    // Is this our ping?
    var _is_ping = (_id == global.c64u_ping_id && global.c64u_ping_id != -1);
    var _is_send = (_id == global.c64u_request_id && global.c64u_request_id != -1 && _is_ping == false);

    if (_is_ping == false && _is_send == false)
    {
        return false; // Not ours
    }

    var _status = async_load[? "status"];

    if (_status == 1)
    {
        return true; // Still in flight
    }

    // --- Always clear busy and request-id state on terminal response ---
    var _http_status = async_load[? "http_status"];

    if (_is_ping == true)
    {
        // Ping result — DO NOT clean up c64u_buffer here (ping has no buffer)
        var _candidate = global.c64u_ping_candidate;
        var _after     = global.c64u_ping_after;

        global.c64u_ping_id        = -1;
        global.c64u_ping_candidate = "";
        global.c64u_ping_after     = "";
        global.c64u_busy           = false;
        global.c64u_request_id     = -1;

        if (_status == 0 && _http_status >= 200 && _http_status < 300)
        {
            // PING SUCCESS — save IP, close overlay, optionally kick off build
            scr_c64u_save_ip(_candidate);

            global.c64u_overlay_active = false;
			obj_workspace_manager.alarm[6]=20; // reset the use of nodes
            global.c64u_overlay_text   = "";
            global.c64u_overlay_error  = "";
            global.c64u_overlay_after  = "";

            global.c64u_status   = "C64U found at " + _candidate;
            global.c64u_status_t = 180;

            if (_after == "send_prg")
            {
                trigger_c64u  = true;
                trigger_build = true;
            }

            show_debug_message("C64U ping OK: " + _candidate + " (HTTP " + string(_http_status) + ")");
        }
        else
        {
            // PING FAILED — keep overlay open, show error, do NOT save IP
            if (_status != 0)
            {
                global.c64u_overlay_error = "No reply - check IP & network";
            }
            else
            {
                if (_http_status == 403)
                {
                    // 403 = network password is set on the device.
                    // Prompt for it, save to ini, and retry the ping with X-Password header.
                    var _entered = get_string("403 - Enter network password (leave blank to cancel):", global.c64u_password);

                    if (_entered != "" && _entered != "string_cancel")
                    {
                        // Save password to global + ini
                        global.c64u_password = _entered;
                        ini_open(global.c64u_ini_path);
                        ini_write_string("C64U", "password", _entered);
                        ini_close();

                        // Fire the retry ping directly with X-Password header
                        var _url     = "http://" + _candidate + "/v1/version";
                        var _headers = ds_map_create();
                        ds_map_add(_headers, "X-Password", _entered);
                        var _req_id  = http_request(_url, "GET", _headers, -1);
                        ds_map_destroy(_headers);

                        if (_req_id >= 0)
                        {
                            global.c64u_busy           = true;
                            global.c64u_request_id     = _req_id;
                            global.c64u_ping_id        = _req_id;
                            global.c64u_ping_candidate = _candidate;
                            global.c64u_ping_password  = _entered;
                            global.c64u_ping_after     = _after;
                            global.c64u_overlay_error  = "Retrying with password...";
                        }
                        else
                        {
                            global.c64u_overlay_error = "Could not start retry request";
                        }
                    }
                    else
                    {
                        global.c64u_overlay_error = "403 - password needed to connect";
                    }
                }
                else
                {
                    global.c64u_overlay_error = "Got HTTP " + string(_http_status) + " - not an Ultimate?";
                }
            }
            show_debug_message("C64U ping FAILED: status=" + string(_status) + " http=" + string(_http_status));
        }
        return true;
    }

    // --- Send / mount / run result ---
    if (global.c64u_buffer >= 0)
    {
        buffer_delete(global.c64u_buffer);
        global.c64u_buffer = -1;
    }

    global.c64u_busy       = false;
    global.c64u_request_id = -1;

    if (_status == 0)
    {
        if (_http_status >= 200 && _http_status < 300)
        {
            // A D64 mount just succeeded and a boot PRG is queued — DMA-run it.
            // The disk stays mounted so MACRO_LOADER can pull assets at runtime.
            if (global.c64u_pending_reset == true && global.c64u_run_after_mount != "")
            {
                global.c64u_pending_reset = false;
                var _run_path = global.c64u_run_after_mount;
                global.c64u_run_after_mount = "";

                var _run_ok = false;

                if (file_exists(_run_path) == true)
                {
                    var _run_buf = buffer_load(_run_path);
                    if (_run_buf >= 0)
                    {
                        var _run_url     = "http://" + global.c64u_ip + "/v1/runners:run_prg";
                        var _run_headers = ds_map_create();
                        ds_map_add(_run_headers, "Content-Type", "application/octet-stream");
                        if (global.c64u_password != "")
                        {
                            ds_map_add(_run_headers, "X-Password", global.c64u_password);
                        }
                        var _run_id = http_request(_run_url, "POST", _run_headers, _run_buf);
                        ds_map_destroy(_run_headers);

                        if (_run_id >= 0)
                        {
                            global.c64u_busy       = true;
                            global.c64u_request_id = _run_id;
                            global.c64u_buffer     = _run_buf;
                            global.c64u_status     = "C64U: D64 mounted, running boot...";
                            global.c64u_status_t   = 240;
                            show_debug_message("C64U: mount OK, running boot PRG");
                            _run_ok = true;
                        }
                        else
                        {
                            buffer_delete(_run_buf);
                        }
                    }
                }

                if (_run_ok == true)
                {
                    return true; // keep busy until the run_prg response arrives
                }

                global.c64u_status   = "C64U: mounted, but boot run failed";
                global.c64u_status_t = 360;
            }
            else
            {
                // Plain PRG send, or the chained boot-PRG run itself, completed.
                global.c64u_status   = "C64U: sent & running";
                global.c64u_status_t = 240;
                show_debug_message("C64U send OK (HTTP " + string(_http_status) + ")");
            }
        }
        else
        {
            global.c64u_pending_reset   = false;
            global.c64u_run_after_mount = "";
            global.c64u_status   = "C64U: HTTP " + string(_http_status) + " (check device)";
            global.c64u_status_t = 360;
            show_debug_message("C64U send: HTTP error " + string(_http_status));
        }
    }
    else
    {
        global.c64u_pending_reset   = false;
        global.c64u_run_after_mount = "";
        global.c64u_status   = "C64U: network error (check IP / cable)";
        global.c64u_status_t = 360;
        show_debug_message("C64U send: network error, status=" + string(_status));
    }

    return true;
}