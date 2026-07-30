/// @function scr_show_message(_msg)
/// @description Custom cross-platform modal info dialog. Drop-in
///              replacement for scr_show_message() that uses the IDE's own
///              font and styling. Non-blocking - spawns an obj_message_box
///              instance that the user dismisses with OK / Enter / Esc.
///              Safe to call from any event including Draw.
/// @param {string} _msg  The message text to display

function scr_show_message(_msg)
{
    // If a message box is already open, replace its content rather than
    // stacking - prevents a flood of overlapping dialogs from rapid clicks
    if (instance_exists(obj_message_box)) {
        var _existing = obj_message_box;
        with (_existing) {
            message     = _msg;
            input_armed = false;
        }
        return;
    }

    var _layer = "Instances";
    if (!layer_exists(_layer)) {
        _layer = layer_get_id_at_depth(0);
    }
    if (_layer == -1 || !layer_exists(_layer)) {
        // Last-resort fallback to native dialog
        scr_show_message(_msg);
        return;
    }

    var _box = instance_create_layer(0, 0, _layer, obj_message_box);
    _box.message = _msg;
}