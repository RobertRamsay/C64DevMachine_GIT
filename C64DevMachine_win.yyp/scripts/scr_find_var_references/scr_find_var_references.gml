/// @desc Returns array of nodes that reference a given VAR name.
/// @param _var_name  the variable name to search for
/// @param _exclude   an instance id to skip (the node being deleted), or noone
/// Scans only known VAR-consuming node types. Reference slots per type
/// mirror the VAR pickers and the compile chain (COND_IF cmp-var = slot 5;
/// METAMAP name relocates 6->7; SEEK/COLL_ADV multi-slot, etc).
/// Returns: [{ node, label }] — label is the referencing node's display title.
function scr_find_var_references(_var_name, _exclude) {
    var _refs = [];
    if (_var_name == "") return _refs;

    with (obj_c64_node) {
        if (id == _exclude) continue;
        if (array_length(instructions) == 0) continue;

        var _slots = [];
        switch (node_type) {
            case "GET_VAR":              _slots = [1, 6, 7];            break;
            case "SET_VAR":              _slots = [1, 6];               break;
            case "COPY_VAR":             _slots = [1, 2];               break;
            case "INC_VAR":              _slots = [1];                  break;
            case "DEC_VAR":              _slots = [1];                  break;
            case "COND_IF":              _slots = [1, 5];               break;
            case "COND_IF_WORD":         _slots = [1, 5];               break;
            case "MACRO_MOVE":           _slots = [8, 10];              break;
            case "MACRO_SEEK":           _slots = [11, 13, 15, 17];     break;
            case "MACRO_VWAIT":          _slots = [3];                  break;
            case "MACRO_WAIT":           _slots = [3];                  break;
            case "MACRO_VECTOR_PAGE":    _slots = [3];                  break;
            case "MACRO_METAMAP":        _slots = [6, 7];               break;
            case "MACRO_ANIM":           _slots = [35];                 break;
            case "MACRO_COLL_ADV":       _slots = [13, 14, 15, 16, 17]; break;
            case "MACRO_PRINT":          _slots = [15, 17];             break;
            case "MACRO_PLACE_CHAR":     _slots = [3, 6, 9, 13];        break;
            case "MACRO_MATH":           _slots = [2, 5, 6];            break;
            case "MACRO_GET_CHAR":       _slots = [3, 6, 7, 9];         break;
            case "MACRO_RANDOM":         _slots = [7];                 break;
            case "MACRO_SID_SOUND":      _slots = [3, 6, 9, 12, 15, 19, 24, 28]; break;
            case "MACRO_PRINT_EXT":      _slots = [6];                  break;
            case "MACRO_MOVE_BMP_BLOCK":  _slots = [9, 10, 11, 12, 18];  break;
            default:                     _slots = [];                   break;
        }

        if (array_length(_slots) == 0) continue;
        var _matched_slots = [];
        for (var _si = 0; _si < array_length(_slots); _si++) {
            var _sidx = _slots[_si];
            if (_sidx >= array_length(instructions[0])) continue;
            var _sval = instructions[0][_sidx];
            if (is_string(_sval) && _sval == _var_name) {
                array_push(_matched_slots, _sidx);
            }
        }
        if (array_length(_matched_slots) > 0) {
            var _lbl_title = node_title;
            if (custom_title != "") {
                _lbl_title = custom_title;
            }
            array_push(_refs, { node: id, label: string(_lbl_title), slots: _matched_slots });
        }
    }

    return _refs;
}