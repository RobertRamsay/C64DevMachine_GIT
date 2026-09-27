/// @desc Scan LABEL nodes, NAMED_LOC nodes and the text of every code/macro
/// node for a label matching the query.
/// Supports: exact "name", starts-with "name*", ends-with "*name", contains "*name*".
/// Returns an array of node ids. Definitions come first, then references,
/// each top-to-bottom. A node appears once per matching line.
/// Per-result detail (line number, line text, def/ref) is written to
/// obj_workspace_manager.label_search_info, parallel to the returned array.
function scr_label_search_run(_query) {
    obj_workspace_manager.label_search_info = [];

    var _q = string_upper(string_trim(_query));
    if (_q == "") return [];

    var _mode = 0; // 0 exact, 1 startswith, 2 endswith, 3 contains
    var _qlen = string_length(_q);

    if (_qlen >= 2 && string_char_at(_q, 1) == "*" && string_char_at(_q, _qlen) == "*") {
        _mode = 3;
        _q    = string_copy(_q, 2, _qlen - 2);
    } else if (_qlen >= 1 && string_char_at(_q, _qlen) == "*") {
        _mode = 1;
        _q    = string_copy(_q, 1, _qlen - 1);
    } else if (_qlen >= 1 && string_char_at(_q, 1) == "*") {
        _mode = 2;
        _q    = string_copy(_q, 2, _qlen - 1);
    }
    if (_q == "") return [];

    var _hits = [];
    with (obj_c64_node) {
        if (array_length(instructions) == 0) continue;

        // LABEL / NAMED_LOC — the name itself is a definition
        if (node_type == "LABEL" || node_type == "NAMED_LOC") {
            if (array_length(instructions[0]) < 2) continue;
            var _name = string(instructions[0][1]);
            if (scr_label_search_match(string_upper(_name), _q, _mode)) {
                array_push(_hits, { node: id, def: true, line: 0, text: _name, ny: y });
            }
            continue;
        }

        // Every other node — scan string slots (slot 0 is the opcode / macro tag)
        for (var _ri = 0; _ri < array_length(instructions); _ri++) {
            var _row = instructions[_ri];
            for (var _rj = 1; _rj < array_length(_row); _rj++) {
                if (!is_string(_row[_rj])) continue;
                var _txt = string_replace_all(_row[_rj], "\r", "");
                if (_txt == "") continue;
                var _lines = string_split(_txt, "\n");
                var _multi = (array_length(_lines) > 1);
                for (var _li = 0; _li < array_length(_lines); _li++) {
                    var _res = scr_label_search_scan_line(_lines[_li], _q, _mode);
                    if (_res < 0) continue;
                    var _ln = 0;
                    if (_multi) {
                        _ln = _li + 1;
                    }
                    array_push(_hits, { node: id, def: (_res == 1), line: _ln, text: string_trim(_lines[_li]), ny: y });
                }
            }
        }
    }

    array_sort(_hits, function(_a, _b) {
        if (_a.def != _b.def) {
            if (_a.def) {
                return -1;
            }
            return 1;
        }
        if (_a.ny != _b.ny) return _a.ny - _b.ny;
        return _a.line - _b.line;
    });

    var _results = [];
    var _info    = [];
    for (var _hi = 0; _hi < array_length(_hits); _hi++) {
        array_push(_results, _hits[_hi].node);
        array_push(_info, _hits[_hi]);
    }
    obj_workspace_manager.label_search_info = _info;
    return _results;
}

/// @desc Does an upper-cased name match the query in the given mode?
function scr_label_search_match(_name, _q, _mode) {
    var _qlen = string_length(_q);
    var _nlen = string_length(_name);
    switch (_mode) {
        case 0: return (_name == _q);
        case 1: return (string_pos(_q, _name) == 1);
        case 2:
            if (_qlen > _nlen) return false;
            return (string_copy(_name, _nlen - _qlen + 1, _qlen) == _q);
        case 3: return (string_pos(_q, _name) > 0);
    }
    return false;
}

/// @desc Tokenise one code line (comment after ';' ignored).
/// Returns -1 no match, 0 reference, 1 definition ("name:" as the first token).
function scr_label_search_scan_line(_line, _q, _mode) {
    var _semi = string_pos(";", _line);
    if (_semi > 0) {
        _line = string_copy(_line, 1, _semi - 1);
    }
    var _len    = string_length(_line);
    var _tok    = "";
    var _first  = true;
    var _found  = -1;
    for (var _ci = 1; _ci <= _len + 1; _ci++) {
        var _ch = "";
        if (_ci <= _len) {
            _ch = string_char_at(_line, _ci);
        }
        var _is_id = false;
        if (_ch != "") {
            var _o = ord(_ch);
            if ((_o >= 48 && _o <= 57) || (_o >= 65 && _o <= 90) || (_o >= 97 && _o <= 122) || _ch == "_" || _ch == ".") {
                _is_id = true;
            }
        }
        if (_is_id) {
            _tok += _ch;
            continue;
        }
        if (_tok != "") {
            if (scr_label_search_match(string_upper(_tok), _q, _mode)) {
                if (_first && _ch == ":") {
                    return 1;
                }
                _found = 0;
            }
            _tok   = "";
            _first = false;
        }
    }
    return _found;
}

/// @desc Jump the camera to a search result. A node inside a folded ORG (or a
/// folded INIT spine) unfolds its block first; the camera move is then
/// deferred a few frames so the node layout can reflow to its real position.
function scr_label_search_goto(_node, _frac) {
    if (!instance_exists(_node)) return;
    var _wm = obj_workspace_manager;

    if (scr_node_is_hidden(_node)) {
        var _owner = _node;
        if (instance_exists(_node.macro_owner)) {
            _owner = _node.macro_owner;
        }
        if (instance_exists(_owner.org_parent)) {
            if (_owner.org_parent.collapsed) {
                scr_org_set_collapsed(_owner.org_parent, false);
            }
        } else if (global.init_collapsed) {
            var _init = scr_init_anchor();
            if (instance_exists(_init)) {
                scr_org_set_collapsed(_init, false);
            }
        }
        _wm.label_search_pending      = _node;
        _wm.label_search_pending_frac = _frac;
        _wm.label_search_reflow       = 4;
        return;
    }

    scr_focus_camera_on_node_offset(_node, _frac);
    camera_set_view_pos(_wm.cam_view, _wm.cam_x, _wm.cam_y);
}
