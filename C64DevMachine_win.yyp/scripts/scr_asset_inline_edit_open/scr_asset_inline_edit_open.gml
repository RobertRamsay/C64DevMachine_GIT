/// @function scr_asset_inline_edit_open(_asset)
/// @desc Open the inline text editor on an asset, loading its working text
///       from whichever field that asset type keeps it in.
///
/// WHY THIS IS A FUNCTION
/// The EDIT button and the content preview both open the editor, and the
/// "load the working text" step differs per type — TEXT_DATA keeps it in
/// meta.text, BYTE_DATA in meta.byte_string with a rebuild-from-buffer
/// fallback, LINE_COLL in meta.line_string. Duplicating that at two call
/// sites is how one of them quietly stops matching the other.
function scr_asset_inline_edit_open(_asset) {
    var _src = "";

    switch (_asset.type) {
        case "TEXT_DATA":
            if (variable_struct_exists(_asset.meta, "text")) {
                _src = string(_asset.meta.text);
            }
            break;

        case "BYTE_DATA":
            // byte_string preserves the user's own formatting, so it wins.
            // The buffer rebuild is for an asset imported as raw bytes that
            // has never been through the editor.
            if (variable_struct_exists(_asset.meta, "byte_string")
             && string_length(string(_asset.meta.byte_string)) > 0) {
                _src = string(_asset.meta.byte_string);
            } else if (buffer_exists(_asset.buffer)) {
                var _bsz = buffer_get_size(_asset.buffer);
                for (var _bi = 0; _bi < _bsz; _bi++) {
                    var _bval = buffer_peek(_asset.buffer, _bi, buffer_u8);
                    var _hex  = string_upper(decimal_to_hex(_bval));
                    if (string_length(_hex) < 2) { _hex = "0" + _hex; }
                    _src += "$" + _hex;
                    if (_bi < _bsz - 1) { _src += ", "; }
                }
            }
            break;

        case "LINE_COLL":
            if (variable_struct_exists(_asset.meta, "line_string")) {
                _src = string(_asset.meta.line_string);
            }
            break;
    }

    _asset.meta.inline_edit_open      = true;
    global.is_any_text_active         = true;
    _asset.meta.inline_edit_text      = _src;
    _asset.meta.inline_edit_cursor    = string_length(_src);
    _asset.meta.inline_edit_scroll_y  = 0;
    _asset.meta.inline_edit_sel_start = -1;
    _asset.meta.inline_edit_sel_end   = -1;
    _asset.meta.inline_edit_blink     = 0;
    _asset.meta.inline_edit_key_timer = 0;
}
