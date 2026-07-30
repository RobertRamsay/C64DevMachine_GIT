/// @function scr_show_question(_msg, [_callback_id], [_callback_action])
/// @description Spawns a non-blocking modal Yes/No dialog. Because GML
///              cannot pause execution mid-frame, this returns immediately
///              and the result must be picked up via global.question_result
///              next frame, or via a callback action string the caller
///              registers and watches for.
///
///              Typical use:
///                  scr_show_question_async("Save changes?", "save_quit");
///              Then in Step:
///                  if (global.question_result == "save_quit_yes") { ... }
///                  if (global.question_result == "save_quit_no")  { ... }
///                  global.question_result = ""; // consume
///
///              For drop-in compatibility with the old synchronous calls,
///              see scr_show_question_check() below.
///
/// @param {string} _msg     The question text
/// @param {string} _action  An identifier the caller will check for later

function scr_show_question(_msg, _action)
{
    if (is_undefined(_action)) _action = "default";

    show_debug_message("scr_show_question CALLED: action=" + _action + " msg=" + string_copy(_msg, 1, 40));

    // If a dialog is already open, ignore the new request - don't stack
    if (instance_exists(obj_question_box)) {
        show_debug_message("  -> blocked, dialog already open");
        return;
    }

    var _layer = "Instances";
    if (!layer_exists(_layer)) {
        _layer = layer_get_id_at_depth(0);
    }
    if (_layer == -1 || !layer_exists(_layer)) {
        // Last-resort fallback to native dialog (will look small on Mac)
        var _r = show_question(_msg);
        var _b = false;
        if (is_string(_r)) {
            _b = (string_lower(_r) == "yes");
        } else {
            _b = bool(_r);
        }
        global.question_result = _action + (_b ? "_yes" : "_no");
        return;
    }

    var _box = instance_create_layer(0, 0, _layer, obj_question_box);
    _box.message = _msg;
    _box.action  = _action;
    _box.result  = -1;

    show_debug_message("DIALOG SPAWN: action=" + _action + " layer=" + string(_layer) + " box=" + string(_box) + " exists=" + string(instance_exists(_box)));

    global.question_result = ""; // clear previous
}