/// @function scr_ctrl_held()
/// @description Returns true if the platform's "Ctrl-equivalent" modifier is
///              held: real Ctrl on Windows, Cmd (left or right) on Mac. Use
///              this in place of keyboard_check(vk_control) for any shortcut
///              that should work identically on both platforms (copy/paste,
///              multi-select, undo/redo, deselect, etc).
/// @return {Bool} true if Ctrl (Win) or Cmd (Mac) is held
function scr_ctrl_held()
{
    if (os_type == os_macosx)
    {
        return scr_cmd_held();
    }
    return keyboard_check(vk_control);
}
