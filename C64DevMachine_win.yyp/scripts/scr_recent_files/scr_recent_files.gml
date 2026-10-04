/// ====================================================================
/// RECENT FILES - the last 10 projects loaded or saved, newest first.
/// Kept in c64devmachine.ini, section [recent], keys r0..r9, and listed
/// under RECENTS in the PROJECT menu. Files inside the program's own
/// folder (bundled templates/ports, autosaves, the load-rollback snapshot)
/// are never listed - they are not the user's projects.
/// ====================================================================

#macro RECENT_FILES_MAX 10

function scr_recent_files_load() {
    global.recent_files = [];
    ini_open("c64devmachine.ini");
    for (var _i = 0; _i < RECENT_FILES_MAX; _i++) {
        var _p = ini_read_string("recent", "r" + string(_i), "");
        if (_p != "") {
            array_push(global.recent_files, _p);
        }
    }
    ini_close();
}

function scr_recent_files_save() {
    ini_open("c64devmachine.ini");
    for (var _i = 0; _i < RECENT_FILES_MAX; _i++) {
        var _p = "";
        if (_i < array_length(global.recent_files)) {
            _p = global.recent_files[_i];
        }
        ini_write_string("recent", "r" + string(_i), _p);
    }
    ini_close();
}

/// Same file? Case- and slash-insensitive (Windows paths).
function scr_recent_files_key(_path) {
    return string_lower(string_replace_all(_path, "\\", "/"));
}

/// Move _path to the top of the list (adding it if new).
function scr_recent_files_add(_path) {
    if (_path == "") return;
    var _key = scr_recent_files_key(_path);
    var _own = scr_recent_files_key(working_directory);
    if (_own != "" && string_pos(_own, _key) == 1) return;
    var _out = [_path];
    for (var _i = 0; _i < array_length(global.recent_files); _i++) {
        var _p = global.recent_files[_i];
        if (scr_recent_files_key(_p) != _key && array_length(_out) < RECENT_FILES_MAX) {
            array_push(_out, _p);
        }
    }
    global.recent_files = _out;
    scr_recent_files_save();
}

function scr_recent_files_remove(_path) {
    var _key = scr_recent_files_key(_path);
    var _out = [];
    for (var _i = 0; _i < array_length(global.recent_files); _i++) {
        if (scr_recent_files_key(global.recent_files[_i]) != _key) {
            array_push(_out, global.recent_files[_i]);
        }
    }
    global.recent_files = _out;
    scr_recent_files_save();
}

/// File name only, cut down with a ".." suffix until it fits _max_w
/// in the current font.
function scr_recent_files_label(_path, _max_w) {
    var _name = filename_name(_path);
    if (string_width_l(_name) <= _max_w) return _name;
    var _cut = _name;
    while (string_length(_cut) > 1 && string_width_l(_cut + "..") > _max_w) {
        _cut = string_copy(_cut, 1, string_length(_cut) - 1);
    }
    return _cut + "..";
}

/// Open a recent entry; a file that has gone is dropped from the list.
function scr_recent_files_open(_path) {
    if (!file_exists(_path)) {
        scr_recent_files_remove(_path);
        scr_show_message("Can't find " + filename_name(_path) + "\n\nIt has been moved or deleted, so it was removed from RECENTS.");
        return;
    }
    scr_load_workspace_from_path(_path);
}
