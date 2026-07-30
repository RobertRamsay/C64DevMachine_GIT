/// @desc Alarm 0: Relaunch VICE (cross-platform via scr_launch_vice)
show_debug_message("FILE EXISTS: " + string(file_exists(full_save_path)));

if (global.vice_path_cache == "" || !file_exists(global.vice_path_cache)) {
    scr_show_message("VICE not found.\n\nChecked:\n" + global.vice_path_cache
        + "\n\nInstall VICE, drop it in the working directory under /vice/,"
        + "\nor set an override path in c64devmachine.ini under [vice] path=...");
} else {
    scr_launch_vice(global.vice_path_cache, full_save_path);
}