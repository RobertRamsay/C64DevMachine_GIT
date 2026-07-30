/// @function scr_c64u_save_ip(ip_string)
/// @description Persists the Ultimate 64 IP to c64devmachine.ini under [C64U].
/// @param {String} ip_string  Dotted-quad IP, e.g. "192.168.1.64"
function scr_c64u_save_ip(ip_string)
{
    global.c64u_ip = ip_string;

    ini_open(global.c64u_ini_path);
    ini_write_string("C64U", "ip", ip_string);
    ini_close();
}

