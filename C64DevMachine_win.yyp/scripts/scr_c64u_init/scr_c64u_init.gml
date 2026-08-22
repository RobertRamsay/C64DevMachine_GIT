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
	global.c64u_reu_attempt      = 0;
	global.c64u_reu_max_attempts = 3;
    global.reu_last_image        = "";
    global.reu_last_used         = 0;
    global.reu_build_error       = "";

    // --- Upload diagnostics (surfaced in the HUD on failure) ---
    global.c64u_reu_trace        = "";
    global.c64u_reu_sent         = 0;
    global.c64u_reu_packets      = 0;
    global.c64u_reu_total        = 0;

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














