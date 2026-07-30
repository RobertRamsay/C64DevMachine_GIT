/// @desc Returns the multicolor flag (true/false) for a specific frame
///       index from a SPR64 node's JSON instruction blob.
///       Returns false if the node has no data or the frame isn't found.
///
/// @param {Id.Instance} _spr_node   The SPR64 node instance
/// @param {real}        _frame_idx  Frame index to query (0-63)

function scr_spr64_get_frame_mc(_spr_node, _frame_idx) {
    if (!instance_exists(_spr_node)) return false;
    if (_spr_node.node_type != "SPR64") return false;

    var _json = (array_length(_spr_node.instructions[0]) > 1)
              ? string(_spr_node.instructions[0][1])
              : "";
    if (_json == "" || _json == "0") return false;

    // Walk JSON objects to find the one at _frame_idx
    var _found   = 0;
    var _depth   = 0;
    var _obj_str = "";
    var _obj_start = -1;

    for (var _ci = 1; _ci <= string_length(_json); _ci++) {
        var _ch = string_char_at(_json, _ci);
        if (_ch == "{") {
            if (_depth == 0) _obj_start = _ci;
            _depth++;
        } else if (_ch == "}") {
            _depth--;
            if (_depth == 0 && _obj_start > 0) {
                if (_found == _frame_idx) {
                    _obj_str = string_copy(_json, _obj_start, _ci - _obj_start + 1);
                    break;
                }
                _found++;
                _obj_start = -1;
            }
        }
    }

    if (_obj_str == "") return false;

    var _mc_pos = string_pos("\"mc\":", _obj_str);
    if (_mc_pos > 0) return (string_char_at(_obj_str, _mc_pos + 5) == "1");

    return false;
}
