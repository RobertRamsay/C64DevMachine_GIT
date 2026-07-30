/// scr_chr_undo_push(_asset)
/// Snapshots the current buffer state onto the undo stack.
/// Call this BEFORE any pixel edit is committed.
function scr_chr_undo_push(_asset) {
    if (!buffer_exists(_asset.buffer)) exit;
    if (!variable_struct_exists(_asset.meta, "undo_stack")) {
        _asset.meta.undo_stack = [];
    }
    if (!variable_struct_exists(_asset.meta, "redo_stack")) {
        _asset.meta.redo_stack = [];
    }
    var _sz    = buffer_get_size(_asset.buffer);
    var _snap  = buffer_create(_sz, buffer_fixed, 1);
    buffer_copy(_asset.buffer, 0, _sz, _snap, 0);
    var _entry = {
        buf        : _snap,
        rows       : variable_struct_exists(_asset.meta, "rows") ? _asset.meta.rows : (buffer_exists(_asset.buffer) ? (buffer_get_size(_asset.buffer) div 128) : 1),
        char_count : _asset.meta.char_count
    };
    array_push(_asset.meta.undo_stack, _entry);
    if (array_length(_asset.meta.undo_stack) > 30) {
        buffer_delete(_asset.meta.undo_stack[0].buf);
        array_delete(_asset.meta.undo_stack, 0, 1);
    }
    // Clear redo on new edit
    for (var _i = 0; _i < array_length(_asset.meta.redo_stack); _i++) {
        buffer_delete(_asset.meta.redo_stack[_i].buf);
    }
    _asset.meta.redo_stack = [];
}