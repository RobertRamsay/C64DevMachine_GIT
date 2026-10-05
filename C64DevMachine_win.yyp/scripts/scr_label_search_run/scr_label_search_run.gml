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
    // A pasted assembler definition normally includes its trailing colon.
    if (string_length(_q) > 0 && string_char_at(_q, string_length(_q)) == ":")
        _q = string_trim(string_delete(_q, string_length(_q), 1));
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
                    if (_multi || (node_type == "MACRO_CODE" && _ri == 0 && _rj == 1)) {
                        _ln = _li + 1;
                    }
                    array_push(_hits, { node: id, def: (_res == 1), line: _ln, row: _ri, slot: _rj, text: string_trim(_lines[_li]), ny: y });
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

    // Code results open the actual source, including inside collapsed ORGs.
    // Use the selected result, not the first match in the node: references
    // and repeated labels can have different source lines in the same block.
    var _index = _wm.label_search_index;
    if (_node.node_type == "MACRO_CODE" && _index >= 0 && _index < array_length(_wm.label_search_info)) {
        var _hit = _wm.label_search_info[_index];
        if (_hit.node == _node && _hit.line > 0 && _hit.row == 0 && _hit.slot == 1) {
            scr_label_search_open_code_line(_node, _hit.line);
            return;
        }
    }

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

/// Open and select the matching source line. Line numbers are one-based;
/// editor cursor/selection positions are zero-based character offsets.
function scr_label_search_open_code_line(_node, _line) {
    if (!instance_exists(_node) || _node.node_type != "MACRO_CODE") return false;
    var _wm = obj_workspace_manager;
    _wm.label_search_open = false;
    _wm.label_search_pending = noone;
    _wm.label_search_reflow = 0;
    scr_code_editor_open(_node);
    var _lines = string_split(_wm.code_editor_text, "\n");
    var _target = clamp(_line - 1, 0, array_length(_lines) - 1);
    _wm.code_editor_line_starts = array_create(array_length(_lines), 0);
    var _offset = 0;
    for (var _i = 0; _i < array_length(_lines); _i++) {
        _wm.code_editor_line_starts[_i] = _offset;
        _offset += string_length(_lines[_i]) + 1;
    }
    var _start = _wm.code_editor_line_starts[_target];
    var _length = string_length(string_replace_all(_lines[_target], "\r", ""));
    _wm.code_editor_cursor = _start;
    _wm.code_editor_sel_start = _start;
    _wm.code_editor_sel_end = _start + _length;
    _wm.code_editor_scroll_x = 0;
    _wm.code_editor_scroll_y = max(0, _target - 8);
    _wm.code_editor_center_line = _target;
    _wm.code_editor_last_cursor = -1;
    _wm.code_editor_cache_dirty = true;
    _wm.code_editor_symbol_cache_dirty = true;
    _wm.code_editor_blink = 0;
    mouse_clear(mb_left);
    scr_workspace_input_blocked();
    return true;
}

/// Refresh live results only after the query changes. Never navigates.
function scr_label_search_refresh(_force = false) {
    var _wm = obj_workspace_manager;
    if (!_force && variable_instance_exists(_wm,"label_search_scanned_query")
    && _wm.label_search_scanned_query == _wm.label_search_query) return;
    _wm.label_search_scanned_query = _wm.label_search_query;
    _wm.label_search_results = scr_label_search_run(_wm.label_search_query);
    _wm.label_search_index = array_length(_wm.label_search_results) > 0 ? 0 : -1;
    _wm.label_search_pending = noone;
    _wm.label_search_reflow = 0;
}

function scr_label_search_source(_node, _hit) {
    var _kind = _node.node_type == "MACRO_CODE" ? "CODE BLOCK" : string_replace_all(_node.node_type,"_"," ");
    var _text = _kind + " / " + (_hit.def ? "DEFINITION" : "REFERENCE");
    if (_hit.line > 0) _text += " / LINE " + string(_hit.line);
    return _text;
}

/// @desc Enter on a JSR/JMP node: centre the camera on the LABEL (or
/// NAMED_LOC) node it names. A label in a folded ORG unfolds it first and the
/// camera move waits for the layout. A label defined only inside a code block
/// opens that block at the definition line instead.
function scr_label_jump_goto(_name) {
    var _wm = obj_workspace_manager;
    var _target = noone;
    var _target_y = 0;
    with (obj_c64_node) {
        if (node_type != "LABEL" && node_type != "NAMED_LOC") continue;
        if (array_length(instructions) == 0) continue;
        if (array_length(instructions[0]) < 2) continue;
        if (string(instructions[0][1]) != _name) continue;
        // Topmost first if a name is somehow defined twice
        if (_target == noone || y < _target_y) {
            _target = id;
            _target_y = y;
        }
    }

    if (_target == noone) {
        var _hits = scr_label_search_run(_name);
        if (array_length(_hits) > 0) {
            var _hit = _wm.label_search_info[0];
            if (_hit.def && _hit.node.node_type == "MACRO_CODE" && _hit.line > 0 && _hit.row == 0 && _hit.slot == 1) {
                scr_label_search_open_code_line(_hit.node, _hit.line);
            }
        }
        return;
    }

    scr_node_jump_goto(_target);
}

/// @desc Centre the camera on a node at default zoom and play the arrival
/// pulse. A node in a folded ORG (or folded INIT spine) unfolds it first and
/// the camera move waits for the layout. Used by Enter on JSR/JMP/branches
/// and by the Creator GO TO arrows.
function scr_node_jump_goto(_target) {
    if (!instance_exists(_target)) {
        return;
    }
    var _wm = obj_workspace_manager;
    if (scr_node_is_hidden(_target)) {
        var _owner = _target;
        if (instance_exists(_target.macro_owner)) {
            _owner = _target.macro_owner;
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
        _wm.label_jump_pending = _target;
        _wm.label_jump_reflow  = 4;
        return;
    }

    scr_focus_camera_on_node(_target);
    camera_set_view_pos(_wm.cam_view, _wm.cam_x, _wm.cam_y);
    _wm.label_jump_fx_node = _target;
    _wm.label_jump_fx_t    = 0;
}

/// @desc Arrival pulse for a JSR/JMP jump: three borders expand out from the
/// LABEL node, fading white to grey over one second. Draw End, world space.
function scr_label_jump_fx_draw() {
    var _wm = obj_workspace_manager;
    if (_wm.label_jump_fx_t >= 1) return;
    if (!instance_exists(_wm.label_jump_fx_node)) {
        _wm.label_jump_fx_t = 1;
        return;
    }

    _wm.label_jump_fx_t = min(1, _wm.label_jump_fx_t + (delta_time / 1000000));

    var _n   = _wm.label_jump_fx_node;
    var _x1  = _n.x + _n.x_indent;
    var _y1  = _n.y;
    var _x2  = _x1 + _n.width;
    var _y2  = _y1 + _n.height;
    var _old_col   = draw_get_colour();
    var _old_alpha = draw_get_alpha();

    // Each ring starts 0.2s after the last and lives 0.6s
    for (var _r = 0; _r < 3; _r++) {
        var _p = (_wm.label_jump_fx_t - (_r * 0.2)) / 0.6;
        if (_p <= 0 || _p >= 1) continue;
        var _grow = 4 + (_p * 40);
        draw_set_colour(merge_colour(c_white, c_gray, _p));
        draw_set_alpha(1 - _p);
        draw_rectangle(_x1 - _grow, _y1 - _grow, _x2 + _grow, _y2 + _grow, true);
        draw_rectangle(_x1 - _grow - 1, _y1 - _grow - 1, _x2 + _grow + 1, _y2 + _grow + 1, true);
    }

    draw_set_colour(_old_col);
    draw_set_alpha(_old_alpha);
}
