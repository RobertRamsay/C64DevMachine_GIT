function scr_load_workspace_dialog() {
    var path = get_open_filename("C64 Node Project|*.json", "");
    // A native file dialog takes focus, so the key-up that ends the keypress is
    // delivered to the dialog and not to the game. GameMaker is left thinking the
    // key is still held, and keyboard_check_pressed() needs an up->down edge — so
    // ESC silently stops working until the input state is reset. This is why ESC
    // only failed after SOME asset operations: scr_asset_sid_import already did
    // this, every other importer did not.
    io_clear();
    if (path == "" || !file_exists(path)) return;
    scr_load_workspace_from_path(path);
}