/// @function scr_desugar_multi_labels(_text)
/// @description Rewrites Kick-style multi-labels into unique synthetic named labels.
///              Anonymous (!:, !+, !-) and named (!loop:, !loop+, !loop-) with
///              chaining (!--, !++). MUST run AFTER repeat-expansion so each unrolled
///              iteration gets its own labels.
function scr_desugar_multi_labels(_text) {
    var _lines = string_split(_text, "\n");
    var _n     = array_length(_lines);

    var _decls    = ds_map_create();   // channel -> ds_list of declaration line indices
    var _syn_map  = ds_map_create();   // channel -> ds_list of synthetic names
    var _counters = ds_map_create();   // channel -> int

    // ── Pass 1: declarations "!:" or "!name:" ──
    for (var _i = 0; _i < _n; _i++) {
        var _t = string_trim(_lines[_i]);
        if (string_char_at(_t, 1) == "!") {
            var _ci = string_pos(":", _t);
            if (_ci >= 2) {
                // channel = text between '!' and ':' ("" for anonymous)
                var _channel = string_copy(_t, 2, _ci - 2);
                var _ch_ok   = true;
                if (_channel != "") {
                    for (var _vi = 1; _vi <= string_length(_channel); _vi++) {
                        var _vc = string_char_at(_channel, _vi);
                        var _is_alnum = ((_vc >= "0" && _vc <= "9")
                                      || (_vc >= "a" && _vc <= "z")
                                      || (_vc >= "A" && _vc <= "Z")
                                      || _vc == "_");
                        if (!_is_alnum) { _ch_ok = false; break; }
                    }
                }
                if (_ch_ok) {
                    var _cid = 0;
                    if (ds_map_exists(_counters, _channel)) {
                        _cid = ds_map_find_value(_counters, _channel);
                    }
                    ds_map_set(_counters, _channel, _cid + 1);

                    var _chname = (_channel == "") ? "anon" : _channel;
                    var _syn    = "__ml_" + _chname + "_" + string(_cid);

                    if (!ds_map_exists(_decls, _channel)) {
                        ds_map_set(_decls, _channel, ds_list_create());
                        ds_map_set(_syn_map, _channel, ds_list_create());
                    }
                    ds_list_add(ds_map_find_value(_decls, _channel), _i);
                    ds_list_add(ds_map_find_value(_syn_map, _channel), _syn);

                    var _rest   = string_trim(string_delete(_t, 1, _ci));
                    var _indent = string_copy(_lines[_i], 1,
                                  string_length(_lines[_i]) - string_length(string_trim_start(_lines[_i])));
                    if (_rest == "") {
                        _lines[_i] = _indent + _syn + ":";
                    } else {
                        _lines[_i] = _indent + _syn + ": " + _rest;
                    }
                }
            }
        }
    }

    // ── Pass 2: references !+ / !- / !name+ / !name- ──
    for (var _i = 0; _i < _n; _i++) {
        var _line  = _lines[_i];
        var _guard = 0;
        var _bang  = string_pos("!", _line);
        while (_bang > 0 && _guard < 64) {
            _guard++;
            // read channel chars after '!'
            var _j  = _bang + 1;
            var _jc = string_char_at(_line, _j);
            while (_j <= string_length(_line)
                && ((_jc >= "0" && _jc <= "9")
                 || (_jc >= "a" && _jc <= "z")
                 || (_jc >= "A" && _jc <= "Z")
                 || _jc == "_")) {
                _j++;
                _jc = string_char_at(_line, _j);
            }
            var _channel = string_copy(_line, _bang + 1, _j - _bang - 1);
            var _signch  = string_char_at(_line, _j);

            if (_signch == "+" || _signch == "-") {
                var _dir   = (_signch == "+") ? 1 : -1;
                var _count = 0;
                var _k     = _j;
                while (string_char_at(_line, _k) == _signch) {
                    _count++;
                    _k++;
                }
                var _tok_len = _k - _bang;

                var _target = "";
                if (ds_map_exists(_decls, _channel)) {
                    var _dl   = ds_map_find_value(_decls, _channel);
                    var _sl   = ds_map_find_value(_syn_map, _channel);
                    var _seen = 0;
                    if (_dir == 1) {
                        // forward: declarations strictly AFTER this line
                        for (var _d = 0; _d < ds_list_size(_dl); _d++) {
                            if (ds_list_find_value(_dl, _d) > _i) {
                                _seen++;
                                if (_seen == _count) { _target = ds_list_find_value(_sl, _d); break; }
                            }
                        }
                    } else {
                        // backward: declarations on/before this line, counting from end
                        for (var _d = ds_list_size(_dl) - 1; _d >= 0; _d--) {
                            if (ds_list_find_value(_dl, _d) <= _i) {
                                _seen++;
                                if (_seen == _count) { _target = ds_list_find_value(_sl, _d); break; }
                            }
                        }
                    }
                }

                if (_target == "") _target = "__ml_UNRESOLVED";

                _line = string_copy(_line, 1, _bang - 1)
                      + _target
                      + string_delete(_line, 1, _bang + _tok_len - 1);
                _lines[_i] = _line;
                _bang = string_pos("!", _line);
            } else {
                // '!' not followed by +/- : skip to next '!'
                var _after = string_delete(_line, 1, _bang);
                var _np    = string_pos("!", _after);
                if (_np > 0) {
                    _bang = _bang + _np;
                } else {
                    _bang = 0;
                }
            }
        }
    }

    // ── Cleanup ds structures ──
    var _ck = ds_map_find_first(_decls);
    while (!is_undefined(_ck)) {
        ds_list_destroy(ds_map_find_value(_decls, _ck));
        ds_list_destroy(ds_map_find_value(_syn_map, _ck));
        _ck = ds_map_find_next(_decls, _ck);
    }
    ds_map_destroy(_decls);
    ds_map_destroy(_syn_map);
    ds_map_destroy(_counters);

    return string_join_ext("\n", _lines);
}