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