/// @function scr_code_editor_open(_node)
/// @description Opens the code editor modal for a MACRO_CODE node.
function scr_code_editor_open(_node) {
	
//	show_debug_message("OPEN: node=" + string(_node) + " instr type=" + string(typeof(_node.instructions)) + " [0] type=" + string(typeof(_node.instructions[0])) + " [0][1]=" + string(_node.instructions[0][1]));
    with (obj_workspace_manager) {
        code_editor_open      = true;
        code_editor_node      = _node;
        code_editor_text      = string(_node.instructions[0][1]);
        code_editor_cursor    = string_length(code_editor_text);
        code_editor_sel_start = -1;
        code_editor_sel_end   = -1;
        code_editor_scroll_y  = 0;
        code_editor_blink     = 0;
        code_editor_key_timer = 0;
keyboard_string              = "";
        code_editor_mouse_selecting  = false;
        code_editor_scrollbar_dragging   = false;
        code_editor_hscrollbar_dragging  = false;
        code_editor_undo_stack       = [];
        code_editor_redo_stack       = [];
        keyboard_clear(vk_anykey);
    }
}