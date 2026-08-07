/// @function scr_draw_reu_memory_bar(_x1, _x2, _y, _asset)
/// @desc Draws a horizontal usage bar for a LOAD_REU manifest's REU image,
/// spanning the manifest's full target size with each linked asset shown as
/// a coloured segment at its packed REU address. Deliberately self-contained
/// and much simpler than scr_draw_memory_bar (the main 64KB C64 map) — this
/// only needs segments, a red flag for packing conflicts, and tick marks;
/// it has no conflict-popup or danger-zone machinery of its own.
function scr_draw_reu_memory_bar(_x1, _x2, _y, _asset) {
    var _map_w  = _x2 - _x1;
    var _map_h  = 15;
    var _target = variable_struct_exists(_asset, "reu_size") ? real(_asset.reu_size) : 0x1000000;
    _target = clamp(_target, 0x20000, 0x1000000);

    // Base bar
    draw_set_color(make_color_rgb(30, 35, 45));
    draw_rectangle(_x1, _y, _x2, _y + _map_h, false);

    // Segments — one per linked asset, positioned at its packed REU address.
    var _links = variable_struct_exists(_asset, "linked_assets") ? _asset.linked_assets : [];
    var _hover_tip = "";
    var _hover_col = c_white;
    for (var _li = 0; _li < array_length(_links); _li++) {
        var _lk = _links[_li];
        var _la = scr_reu_find_asset(_lk.asset_name);
        var _pl = scr_reu_asset_payload(_la);
        var _sz = max(1, _pl.size);
        if (buffer_exists(_pl.buffer)) buffer_delete(_pl.buffer);

        var _addr = real(_lk.reu_address);
        var _sx1 = _x1 + (_addr / _target) * _map_w;
        var _sx2 = _x1 + ((_addr + _sz) / _target) * _map_w;
        if (_sx2 - _sx1 < 2) _sx2 = _sx1 + 2;

        var _conflict = variable_struct_exists(_lk, "reu_conflict") ? _lk.reu_conflict : false;
        var _is_bmp   = !is_undefined(_la) && (_la.type == "BITMAP" || _la.type == "BITMAP_KLA");
        var _col      = _conflict ? c_red : (_is_bmp ? make_color_rgb(60, 160, 220) : make_color_rgb(140, 130, 60));

        draw_set_color(_col);
        draw_rectangle(_sx1, _y, _sx2, _y + _map_h, false);

        if (point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y, _sx1, _y, _sx2, _y + _map_h)) {
            var _ah = string_upper(decimal_to_hex(_addr));
            while (string_length(_ah) < 6) _ah = "0" + _ah;
            _hover_tip = _lk.asset_name + " @ $" + _ah + " (" + string(_sz) + " bytes)";
            _hover_col = _col;
        }
    }

    // Outline
    draw_set_color(make_color_rgb(70, 80, 100));
    draw_rectangle(_x1, _y, _x2, _y + _map_h, true);

    // Tick marks every 4MB (falls back to a single end tick for odd target sizes)
    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_center);
    var _tick_step = 4 * 1024 * 1024;
    var _tick_addr = 0;
    while (_tick_addr <= _target) {
        var _tx = _x1 + (_tick_addr / _target) * _map_w;
        draw_set_color(make_color_rgb(90, 100, 120));
        draw_line(_tx, _y, _tx, _y + _map_h + 4);
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_text(_tx, _y + _map_h + 6, string(_tick_addr div (1024 * 1024)) + "MB");
        _tick_addr += _tick_step;
    }
    draw_set_halign(fa_left);

    // Hover tooltip, drawn last so it sits above every segment
    if (_hover_tip != "") {
        draw_set_color(_hover_col);
        draw_text(_x1, _y - string_height(_hover_tip) - 2, _hover_tip);
    }
}
