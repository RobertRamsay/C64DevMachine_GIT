function scr_load_workspace_dialog() {
    var path = get_open_filename("C64 Node Project|*.json", "");
    if (path == "" || !file_exists(path)) return;
    scr_load_workspace_from_path(path);
}