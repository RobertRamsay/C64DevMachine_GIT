
/// @function scr_c64u_overlay_try_confirm()
/// @description Validates the typed IP format, then fires a ping. The async
///              handler will save the IP and proceed if the ping returns 2xx.
function scr_c64u_overlay_try_confirm()
{
    var _candidate = string_trim(global.c64u_overlay_text);

    if (scr_c64u_validate_ip(_candidate) == false)
    {
        global.c64u_overlay_error = "Invalid format (e.g. 192.168.1.64)";
        return;
    }

    // Don't fire a new ping while one is already in flight
    if (global.c64u_busy == true)
    {
        global.c64u_overlay_error = "Already pinging, please wait...";
        return;
    }

    scr_c64u_ping(_candidate, global.c64u_overlay_after);
}

