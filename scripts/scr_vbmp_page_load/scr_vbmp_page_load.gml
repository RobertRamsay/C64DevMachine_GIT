/// @function scr_vbmp_page_load(_asset, _index)
/// Make page _index active: copy its fields UP into the top-level editor
/// fields and mark the preview dirty. Call after storing the previous page.
function scr_vbmp_page_load(_asset, _index) {
    var _m = _asset.meta;
    if (!variable_struct_exists(_m, "pages")) return;
    if (_index < 0 || _index >= array_length(_m.pages)) return;
    var _pg = _m.pages[_index];
    _m.active_page = _index;
    _m.commands = variable_struct_exists(_pg, "commands") ? _pg.commands : [];
    _m.bg       = variable_struct_exists(_pg, "bg")   ? _pg.bg   : 0;
    _m.col1     = variable_struct_exists(_pg, "col1") ? _pg.col1 : 1;
    _m.col2     = variable_struct_exists(_pg, "col2") ? _pg.col2 : 2;
    _m.col3     = variable_struct_exists(_pg, "col3") ? _pg.col3 : 3;
    _m.last_emitted_col = -1; // force SETCOL re-emit on next commit
    _m.vbmp_dirty = true;
}