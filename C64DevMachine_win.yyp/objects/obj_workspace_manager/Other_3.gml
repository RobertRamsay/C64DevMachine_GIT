ini_open("c64devmachine.ini");
ini_write_real("window", "x", window_get_x());
ini_write_real("window", "y", window_get_y());
ini_write_real("window", "w", window_get_width());
ini_write_real("window", "h", window_get_height());
ini_write_real("editor", "font_index", code_editor_font_index);
ini_write_real("Settings", "bkgImg", bkgImg);
ini_write_real("Settings", "showGrid", showGrid);
ini_write_real("Settings", "paletteStyle", paletteStyle);
ini_write_real("Settings", "niceSliceFrm", niceSliceFrm);
ini_close();

if (!global.manual_saved) {
    if (scr_show_question("You have unsaved changes.\nSave before closing?")) {
        scr_save_workspace_as();
    }
}