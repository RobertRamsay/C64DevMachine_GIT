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

/// Modal editor boundary. Query at Begin Step and again at every workspace
/// input site, so an editor opened/closed mid-frame cannot leak the click.
function scr_workspace_input_blocked() {
    if (!variable_global_exists("workspace_editor_seen")) {
        global.workspace_editor_seen = false;
        global.workspace_input_until = 0;
        global.workspace_wait_release = false;
        global.workspace_release_frame = -1;
    }
    var _active = false;
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        _active = _am.viewer_open || _am.spred64_v2.active;
    }
    if (instance_exists(obj_workspace_manager))
        _active = _active || obj_workspace_manager.code_editor_open || obj_workspace_manager.box_popup_open;
    _active = _active || instance_exists(obj_integer_box) || instance_exists(obj_ui_color_picker);
    if (_active) {
        if (!global.workspace_editor_seen) {
            // Cancel suspended workspace gestures instead of resuming them
            // at a different cursor position when the editor closes.
            with (obj_mapping_box) { is_dragging = false; is_resizing = false; }
            with (obj_c64_node) { is_dragging = false; }
            with (obj_workspace_manager) {
                is_panning = false;
                hideui = false;
                box_select_active = false;
                box_drag_live = false;
                gui_menu_drag_active = false;
                gui_menu_open = -1;
            }
            with (obj_asset_manager) {
                asset_drag_idx = -1;
                asset_drag_armed = false;
            }
            global.group_drag_active = false;
            global.active_drag_node = noone;
            global.box_drag_active = false;
            global.wire_drag_node = noone;
        }
        global.workspace_editor_seen = true;
        return true;
    }
    if (global.workspace_editor_seen) {
        global.workspace_editor_seen = false;
        global.workspace_input_until = current_time + 500;
        global.workspace_wait_release = true;
    }
    if (global.workspace_wait_release) {
        if (mouse_check_button(mb_any) || keyboard_check(vk_anykey)) return true;
        global.workspace_wait_release = false;
        global.workspace_release_frame = global.frame_tick;
    }
    return current_time < global.workspace_input_until
        || global.workspace_release_frame == global.frame_tick;
}

function scr_workspace_mouse_check_button_pressed(_key) {
    return !scr_workspace_input_blocked() && mouse_check_button_pressed(_key);
}

function scr_workspace_mouse_check_button_released(_key) {
    return !scr_workspace_input_blocked() && mouse_check_button_released(_key);
}

function scr_workspace_mouse_check_button(_key) {
    return !scr_workspace_input_blocked() && mouse_check_button(_key);
}

function scr_workspace_mouse_wheel_up() {
    return !scr_workspace_input_blocked() && mouse_wheel_up();
}

function scr_workspace_mouse_wheel_down() {
    return !scr_workspace_input_blocked() && mouse_wheel_down();
}

function scr_workspace_keyboard_check_pressed(_key) {
    return !scr_workspace_input_blocked() && keyboard_check_pressed(_key);
}

function scr_workspace_keyboard_check_released(_key) {
    return !scr_workspace_input_blocked() && keyboard_check_released(_key);
}

function scr_workspace_keyboard_check(_key) {
    return !scr_workspace_input_blocked() && keyboard_check(_key);
}
