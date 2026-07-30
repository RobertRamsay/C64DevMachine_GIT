/// @desc Scan all LABEL nodes for a name matching the query.
/// Supports: exact "name", starts-with "name*", ends-with "*name", contains "*name*".
/// Returns an array of node ids sorted top-to-bottom (by y).
function scr_label_search_run(_query) {
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
    _qlen = string_length(_q);

    var _results = [];
    with (obj_c64_node) {
        if (node_type != "LABEL") continue;
        if (array_length(instructions) == 0 || array_length(instructions[0]) < 2) continue;

        var _name = string_upper(string(instructions[0][1]));
        var _nlen = string_length(_name);
        var _match = false;

        switch (_mode) {
            case 0: _match = (_name == _q); break;
            case 1: _match = (string_pos(_q, _name) == 1); break;
            case 2: _match = (_qlen <= _nlen) && (string_copy(_name, _nlen - _qlen + 1, _qlen) == _q); break;
            case 3: _match = (string_pos(_q, _name) > 0); break;
        }

        if (_match) array_push(_results, id);
    }

    array_sort(_results, function(_a, _b) {
        var _ay = instance_exists(_a) ? _a.y : 999999;
        var _by = instance_exists(_b) ? _b.y : 999999;
        return _ay - _by;
    });

    return _results;
}