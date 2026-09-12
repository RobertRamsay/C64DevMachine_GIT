/// scr_undo_step(_direction)
/// _direction: -1 = undo, +1 = redo
function scr_undo_step(_direction) {
    var _undo_dir       = working_directory + "temp/undo/";
    var _manifest_path  = _undo_dir + "manifest.json";
    if (!file_exists(_manifest_path)) exit;

    var _f = file_text_open_read(_manifest_path);
    var _raw = "";
    while (!file_text_eof(_f)) { _raw += file_text_read_string(_f); file_text_readln(_f); }
    file_text_close(_f);
    var _m       = json_parse(_raw);
    var _states  = _m.states;
    var _current = _m.current;

    var _target = _current + _direction;
    if (_target < 0 || _target >= array_length(_states)) {
        show_debug_message("UNDO: nothing to " + (_direction < 0 ? "undo" : "redo"));
        exit;
    }

    // Before undoing, snapshot current state if we're at the tip
    // (so redo can come back here)
    // — snapshot already written on mouse release, so just move pointer
    _m.current = _target;
    var _mf = file_text_open_write(_manifest_path);
    file_text_write_string(_mf, json_stringify(_m));
    file_text_close(_mf);

    scr_undo_restore(_undo_dir + _states[_target]);
}