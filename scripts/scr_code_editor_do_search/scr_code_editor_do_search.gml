function scr_code_editor_do_search(_dir) {
    var _search = string_lower(string_trim(code_editor_find_text));
    if (_search == "") return;
    var _found = -1;
    var _txt   = string_lower(code_editor_text);
    var _slen  = string_length(_search);

    if (_dir == 1) {
        // Search from one character after the start of the current match (1-based)
        var _from = 1;
        if (code_editor_sel_start != -1 && code_editor_sel_end != -1) {
            _from = min(code_editor_sel_start, code_editor_sel_end) + 2; // +2: 0-to-1 base + skip 1 char
        } else {
            _from = code_editor_cursor + 1;
        }
        var _pos = string_pos_ext(_search, _txt, _from);
        if (_pos == 0) _pos = string_pos(_search, _txt); // wrap
        _found = _pos;
    } else {
        // PREV — find last match that starts strictly before current match start
        var _limit = 1;
        if (code_editor_sel_start != -1 && code_editor_sel_end != -1) {
            _limit = min(code_editor_sel_start, code_editor_sel_end) + 1; // convert 0-based to 1-based
        } else {
            _limit = code_editor_cursor + 1;
        }
        var _search_pos = 1;
        while (true) {
            var _p = string_pos_ext(_search, _txt, _search_pos);
            if (_p == 0 || _p >= _limit) break;
            _found = _p;
            _search_pos = _p + 1;
        }
        // Wrap to last occurrence in file
        if (_found == -1) {
            _search_pos = 1;
            while (true) {
                var _p = string_pos_ext(_search, _txt, _search_pos);
                if (_p == 0) break;
                _found = _p;
                _search_pos = _p + 1;
            }
        }
    }

    if (_found != -1) {
        code_editor_sel_start = _found - 1;
        code_editor_sel_end   = _found - 1 + _slen;
        code_editor_cursor    = code_editor_sel_end;
        code_editor_blink     = 0;
    }
}