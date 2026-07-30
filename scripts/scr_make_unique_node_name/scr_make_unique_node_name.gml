/// @function scr_make_unique_node_name(_base_name, _exclude_inst)
/// @desc Returns a unique LABEL name across all obj_c64_node LABEL instances.
///       Appends _01, _02, ... until no collision is found.
///       _exclude_inst is the newly-cloned instance to skip during the check.
function scr_make_unique_node_name(_base_name, _exclude_inst) {

    var _candidate = string(_base_name);
    var _suffix    = 1;
    var _collision = true;

    // If the base already ends in _NN, strip it so we don't get _01_01
    var _len = string_length(_candidate);
    if (_len >= 3) {
        var _last3 = string_copy(_candidate, _len - 2, 3);
        if (string_char_at(_last3, 1) == "_") {
            var _d1 = string_char_at(_last3, 2);
            var _d2 = string_char_at(_last3, 3);
            if (string_digits(_d1) == _d1 && string_digits(_d2) == _d2) {
                _candidate = string_copy(_candidate, 1, _len - 3);
            }
        }
    }

    var _root = _candidate;

    while (_collision) {
        _collision = false;
        with (obj_c64_node) {
            if (id == _exclude_inst) continue;
            if (node_type != "LABEL") continue;
            if (array_length(instructions) == 0) continue;
            if (array_length(instructions[0]) < 2) continue;
            if (string(instructions[0][1]) == _candidate) {
                _collision = true;
                break;
            }
        }
        if (_collision) {
            var _s = string(_suffix);
            if (string_length(_s) < 2) _s = "0" + _s;
            _candidate = _root + "_" + _s;
            _suffix++;
            if (_suffix > 999) break; // safety
        }
    }

    return _candidate;
}