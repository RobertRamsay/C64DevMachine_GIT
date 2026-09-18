/// @function scr_show_integer(_default_w, _default_h, _action)
/// @description Spawns a non-blocking modal two-field (W x H) integer dialog.
///              Returns immediately; the result is published to
///              global.integer_result next frame as a struct:
///                  { w, h, action, cancelled }
///              Consume it in Step, e.g.:
///                  if (is_struct(global.integer_result)) { ... }
///                  global.integer_result = ""; // consume
///
/// @param {real}   _default_w  Starting W value shown in the field
/// @param {real}   _default_h  Starting H value shown in the field
/// @param {string} _action     Identifier the caller matches on later
function scr_show_integer(_default_w, _default_h, _action)
{
    if (is_undefined(_action)) _action = "default";

    // If a dialog is already open, ignore the new request - don't stack
    if (instance_exists(obj_integer_box)) {
        return;
    }

    var _layer = "Instances";
    if (!layer_exists(_layer)) {
        _layer = layer_get_id_at_depth(0);
    }
    if (_layer == -1 || !layer_exists(_layer)) {
        return;
    }

    var _box = instance_create_layer(0, 0, _layer, obj_integer_box);
    _box.field_w    = string(_default_w);
    _box.field_h    = string(_default_h);
    _box.action     = _action;

    global.integer_result = ""; // clear previous
}
/// @param {String} _message
/// @param {String} _default
/// @param {Function} _callback Receives (text, context); cancellation supplies an empty string.
/// @param {Struct} _context Explicit state, never a closure over caller locals.
function scr_prompt_text(_message, _default, _callback, _context) {
    if (variable_global_exists("text_prompt") && is_struct(global.text_prompt)) return false;
    global.text_prompt = {request:get_string_async(L(_message),_default), callback:_callback, context:_context, owner:id};
    return true;
}

function scr_prompt_dimensions(_text, _default_w, _default_h) {
    var _parts = string_split(string_replace_all(string_lower(string_trim(_text)), "x", ","), ",");
    var _w = _default_w;
    var _h = _default_h;
    if (array_length(_parts) >= 2) {
        var _wd = string_digits(_parts[0]);
        var _hd = string_digits(_parts[1]);
        if (_wd != "" && string_pos("-", _parts[0]) == 0 && real(_wd) > 0) _w = real(_wd);
        if (_hd != "" && string_pos("-", _parts[1]) == 0 && real(_hd) > 0) _h = real(_hd);
    }
    return {w:_w,h:_h};
}
