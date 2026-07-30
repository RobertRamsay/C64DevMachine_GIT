/// @desc Helper: register one UV user-variable entry, advancing the cursor
/// _cursor must be passed in and the new value returned.
/// Call only from scr_init_named_locations()
function scr_nloc_uv(_name, _cursor, _size, _encoding, _note) {
    ds_map_set(global.named_loc_map, _name, _cursor);
    array_push(global.named_loc_meta, {
        name:     _name,
        addr:     _cursor,
        size:     _size,
        type:     "UV",
        chip:     "-",
        encoding: _encoding,
        note:     _note,
        bytes:    string(_size) + "B"
    });
    return _cursor + _size; // caller advances the cursor
}

