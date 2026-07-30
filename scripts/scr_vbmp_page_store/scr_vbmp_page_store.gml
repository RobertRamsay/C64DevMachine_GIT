/// @function scr_vbmp_page_store(_asset)
/// Copy the top-level editor fields (commands/bg/col1/col2/col3) DOWN into
/// pages[active_page]. Call before switching away from the current page.
function scr_vbmp_page_store(_asset) {
    var _m = _asset.meta;
    if (!variable_struct_exists(_m, "pages")) return;
    var _ap = variable_struct_exists(_m, "active_page") ? _m.active_page : 0;
    if (_ap < 0 || _ap >= array_length(_m.pages)) return;
    var _pg = _m.pages[_ap];
    _pg.commands = variable_struct_exists(_m, "commands") ? _m.commands : [];
    _pg.bg       = variable_struct_exists(_m, "bg")   ? _m.bg   : 0;
    _pg.col1     = variable_struct_exists(_m, "col1") ? _m.col1 : 1;
    _pg.col2     = variable_struct_exists(_m, "col2") ? _m.col2 : 2;
    _pg.col3     = variable_struct_exists(_m, "col3") ? _m.col3 : 3;
}

