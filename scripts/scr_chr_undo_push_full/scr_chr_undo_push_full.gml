/// scr_chr_undo_push_full(_asset)
/// Pushes a full snapshot (buffer + rows + char_count) onto the undo stack.
/// Used by structural operations: add row, remove row, copy ROM.
function scr_chr_undo_push_full(_asset) {
    var _sz   = buffer_get_size(_asset.buffer);
    var _snap = buffer_create(_sz, buffer_fixed, 1);
    buffer_copy(_asset.buffer, 0, _sz, _snap, 0);

    var _entry = {
        buf        : _snap,
        rows       : _asset.meta.rows,
        char_count : _asset.meta.char_count
    };

    array_push(_asset.meta.undo_stack, _entry);

    // Clear redo stack on new action
    var _rlen = array_length(_asset.meta.redo_stack);
    for (var _i = 0; _i < _rlen; _i++) {
        var _re = _asset.meta.redo_stack[_i];
        if (is_struct(_re)) {
            buffer_delete(_re.buf);
        } else {
            buffer_delete(_re);
        }
    }
    _asset.meta.redo_stack = [];
}