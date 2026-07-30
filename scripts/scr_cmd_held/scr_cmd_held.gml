/// @function scr_cmd_held()
/// @description Returns true if either Cmd key is held on Mac. Maps to raw keycodes 91 (left) and 92 (right).
function scr_cmd_held()
{
    if (os_type != os_macosx)
    {
        return false;
    }
    if (keyboard_check(91))
    {
        return true;
    }
    if (keyboard_check(92))
    {
        return true;
    }
    return false;
}