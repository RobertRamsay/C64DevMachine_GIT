function scr_json_pretty(_json) {
    var _out   = "";
    var _depth = 0;
    var _in_str = false;
    var _len   = string_length(_json);
    var _indent = "    "; // 4 spaces

    for (var _i = 1; _i <= _len; _i++) {
        var _c  = string_char_at(_json, _i);
        var _nc = (_i < _len) ? string_char_at(_json, _i + 1) : "";

        // Track string context so we don't format inside strings
        if (_c == "\"" && (_i == 1 || string_char_at(_json, _i - 1) != "\\")) {
            _in_str = !_in_str;
        }

        if (_in_str) {
            _out += _c;
            continue;
        }

        switch (_c) {
            case "{":
            case "[":
                _depth++;
                _out += _c;
                if (_nc != "}" && _nc != "]") {
                    _out += "\n";
                    repeat (_depth) _out += _indent;
                }
                break;
            case "}":
            case "]":
                _depth--;
                if (string_char_at(_json, _i - 1) != "{" && string_char_at(_json, _i - 1) != "[") {
                    _out += "\n";
                    repeat (_depth) _out += _indent;
                }
                _out += _c;
                break;
            case ",":
                _out += _c + "\n";
                repeat (_depth) _out += _indent;
                break;
            case ":":
                _out += _c + " ";
                break;
            default:
                _out += _c;
                break;
        }
    }
    return _out;
}