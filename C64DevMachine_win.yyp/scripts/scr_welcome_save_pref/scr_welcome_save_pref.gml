function scr_welcome_save_pref(_hide) {
    ini_open("c64devmachine.ini");
    ini_write_real("Settings", "hide_welcome", _hide ? 1 : 0);
    ini_close();
}