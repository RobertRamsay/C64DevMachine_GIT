/// @desc Helper: register one HW named location entry
/// Call only from scr_init_named_locations()
function scr_nloc_hw(_name, _addr, _chip, _note) {
    ds_map_set(global.named_loc_map, _name, _addr);
    array_push(global.named_loc_meta, {
        name:     _name,
        addr:     _addr,
        size:     1,
        type:     "HW",
        chip:     _chip,
        encoding: "byte",
        note:     _note,
        bytes:    "HW"
    });
}
