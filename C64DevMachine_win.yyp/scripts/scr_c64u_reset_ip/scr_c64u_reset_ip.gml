/// @function scr_c64u_reset_ip()
/// @description Clears the saved IP so user is prompted again next F6.
function scr_c64u_reset_ip()
{
    global.c64u_ip       = "";
    global.c64u_password = "";

    ini_open(global.c64u_ini_path);
    ini_write_string("C64U", "ip",       "");
    ini_write_string("C64U", "password", "");
    ini_close();

    global.c64u_status   = "C64U IP & password cleared";
    global.c64u_status_t = 180;
}