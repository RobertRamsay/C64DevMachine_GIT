/// scr_code_editor_push_undo()
/// Call BEFORE any operation that changes code_editor_text
function scr_code_editor_push_undo() {
    array_push(code_editor_undo_stack, {
        text:   code_editor_text,
        cursor: code_editor_cursor
    });
    code_editor_redo_stack = [];  // new edit invalidates redo history
    // Cap at 100 states
    if (array_length(code_editor_undo_stack) > 100)
        array_delete(code_editor_undo_stack, 0, 1);
}