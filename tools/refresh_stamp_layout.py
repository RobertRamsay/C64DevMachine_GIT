from pathlib import Path

P = Path(__file__).resolve().parents[1] / 'C64DevMachine_win.yyp/objects/obj_asset_manager/Draw_64.gml'
t = P.read_text(encoding='utf-8')

def sub(old,new):
    global t
    assert old in t, old[:120]
    t = t.replace(old,new,1)

# Define the bank once before Store, so adding and painting use identical slots.
mark = 'var _bank_count = array_length(global.map_tile_bank);'
sub(mark,mark+'''
            var _bank_strip_x1 = _bank_ox + 42;
            var _bank_strip_x2 = _vx2 - 230;
            var _bank_strip_w = max(1, _bank_strip_x2 - _bank_strip_x1);
            var _bank_cols = max(1, floor((_bank_strip_w - 24) / 96));
            var _bank_cell_w = max(16, floor((_bank_strip_w - 24) / _bank_cols));
            var _bank_row_h = 100;
            var _bank_vis_rows = 3;
            var _bank_area_h = _bank_vis_rows * _bank_row_h;
            if (!variable_global_exists("map_tile_bank_scroll")) global.map_tile_bank_scroll = 0;
''')
start = t.index('        // Auto-scroll to the row containing the new slot')
end = t.index('    // Resolve chr ref once for all slots',start)
t = t[:start]+'''        // Keep the newly stored stamp visible using the same grid as Draw.
                var _new_row = global.map_tile_bank_sel div _bank_cols;
                if (_new_row < global.map_tile_bank_scroll) global.map_tile_bank_scroll = _new_row;
                if (_new_row >= global.map_tile_bank_scroll + _bank_vis_rows)
                    global.map_tile_bank_scroll = _new_row - _bank_vis_rows + 1;
            }

            '''+t[end:]
start = t.index('    // Bank strip layout',start)
end = t.index('    // Scissor the entire bank area',start)
t = t[:start]+'''    // Clamp before drawing or hit-testing, including after deletion/resizing.
            var _bank_total_rows = max(1, ceil(_bank_count / _bank_cols));
            var _bank_max_scroll = max(0, _bank_total_rows - _bank_vis_rows);
            global.map_tile_bank_scroll = clamp(global.map_tile_bank_scroll, 0, _bank_max_scroll);
            scr_editor_panel(_bank_strip_x1 - 4, _bank_oy - 4,
                _bank_strip_x2, _bank_oy + _bank_area_h, true);

            '''+t[end:]
sub('global.map_tile_bank_scroll += 1;', 'global.map_tile_bank_scroll = min(_bank_max_scroll, global.map_tile_bank_scroll + 1);')
start = t.index('    // First pass — compute row heights',start)
end = t.index('        for (var _si = 0; _si < array_length(_bslot.stamp_data); _si++) {',start)
t = t[:start]+'''    // Equal-size slots keep mixed stamp dimensions organised. The last
            // visible row is padded with empty wells, never phantom assets.
            var _bank_first = global.map_tile_bank_scroll * _bank_cols;
            var _bank_last = min(_bank_max, _bank_first + _bank_cols * _bank_vis_rows);
            for (var _bi = _bank_first; _bi < _bank_last; _bi++) {
                var _bx1 = _bank_strip_x1 + (_bi mod _bank_cols) * _bank_cell_w;
                var _by1 = _bank_oy + ((_bi div _bank_cols) - global.map_tile_bank_scroll) * _bank_row_h;
                var _bx2 = _bx1 + _bank_cell_w - 6;
                var _by2 = _by1 + _bank_row_h - 6;
                if (_bi >= _bank_count) {
                    scr_editor_empty_slot(_bx1, _by1, _bx2, _by2);
                    continue;
                }
                var _bslot = global.map_tile_bank[_bi];
                var _bw = clamp(_bslot.bnd_w, 1, 6);
                var _bh = clamp(_bslot.bnd_h, 1, 6);
                // Whole C64 pixels; reserve a separate label row below the art.
                var _tpx = max(8, min(16, floor(min((_bank_cell_w - 18) / _bw, 70 / _bh) / 8) * 8));
                var _sw = _bw * _tpx;
                var _sh = _bh * _tpx;
                var _art_x = floor((_bx1 + _bx2 - _sw) * 0.5);
                var _art_y = floor(_by1 + (76 - _sh) * 0.5);
                var _bsel = global.map_tile_bank_sel == _bi;
                var _bhov = _mouse_on_bank && point_in_rectangle(_mx, _my, _bx1, _by1, _bx2, _by2);
                scr_ui_info(_bhov, "STORED STAMP - LEFT CLICK TO PICK IT UP, RIGHT CLICK TO DELETE IT");
                scr_editor_panel(_bx1, _by1, _bx2, _by2, true);
                if (_bsel || _bhov) scr_editor_control(_bx1, _by1, _bx2, _by2, _bhov, _bsel);
                draw_set_font_l(fnt_c64_tiny);
                draw_set_color(_bsel ? make_color_rgb(137, 218, 225) : make_color_rgb(151, 170, 192));
                draw_text_l(_bx1 + 6, _by2 - 13, string(_bi + 1) + "  " + string(_bslot.bnd_w) + "x" + string(_bslot.bnd_h));

                '''+t[end:]
sub('var _tx  = _bx1 + _sd.dx * _tpx;', 'var _tx  = _art_x + _sd.dx * _tpx;')
sub('var _ty  = _by1 + _sd.dy * _tpx;', 'var _ty  = _art_y + _sd.dy * _tpx;')
# Deleting an earlier slot should keep the same selected asset, not select its neighbour.
sub('array_delete(global.map_tile_bank, _bi, 1);', '''array_delete(global.map_tile_bank, _bi, 1);
                    if (global.map_tile_bank_sel >= _bi) global.map_tile_bank_sel--;
                    global.map_tile_bank_scroll = min(global.map_tile_bank_scroll,
                        max(0, ceil(array_length(global.map_tile_bank) / _bank_cols) - _bank_vis_rows));''')
sub('global.map_tile_bank_scroll += 1;', 'global.map_tile_bank_scroll = min(_bank_max_scroll, global.map_tile_bank_scroll + 1);')
sub('scr_editor_control(_stbx1, _bank_oy, _stbx2, _bank_oy + _bank_sh, _stbhov, false);',
    'scr_editor_control(_stbx1, _bank_oy, _stbx2, _bank_oy + _bank_sh, _stbhov, false, _has_stamp);')
sub('scr_editor_control(_arr_x, _arr_y, _arr_x + 18, _arr_y + 14, _up_hov, false);',
    'scr_editor_control(_arr_x, _arr_y, _arr_x + 18, _arr_y + 14, _up_hov, false, global.map_tile_bank_scroll > 0);')
sub('scr_editor_control(_arr_x, _arr_y + 16, _arr_x + 18, _arr_y + 30, _dn_hov, false);',
    'scr_editor_control(_arr_x, _arr_y + 16, _arr_x + 18, _arr_y + 30, _dn_hov, false, global.map_tile_bank_scroll < _bank_max_scroll);')

# Metatile stamp list: comfortably-sized wells, bounded scroll, centred art,
# and clipping-aware hover tests (scissor alone does not clip mouse input).
sub('var _slot_h      = _m.stamp_h * 24 + 4;', 'var _slot_h      = max(64, _m.stamp_h * 24 + 24);')
sub('var _scroll = _m.stamp_list_scroll;', 'var _scroll = _m.stamp_list_scroll;')
mark = 'var _max_scroll3 = max(0, _total_rows3 - _vis_slots);'
sub(mark,mark+'''
    _m.stamp_list_scroll = clamp(_m.stamp_list_scroll, 0, _max_scroll3);
    _scroll = _m.stamp_list_scroll;
    var _list_hover = point_in_rectangle(_mx, _my, _list_x1, _cy, _list_x2, _cy + _list_area_h);
''')
sub('var _g_hov = point_in_rectangle(_mx, _my, _sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2);',
    'var _g_hov = _list_hover && point_in_rectangle(_mx, _my, _sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2);')
sub('var _shov = point_in_rectangle(_mx, _my, _sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2);',
    'var _shov = _list_hover && point_in_rectangle(_mx, _my, _sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2);')
sub('var _px         = _sx2 + 4 + _col * _slot_tpx;',
    'var _px         = floor(_sx2 + (_slot_w3 - 2 - _foot_w) * 0.5) + _col * _slot_tpx;')
sub('var _py         = _sy2 + 4 + _row * _slot_tpx;',
    'var _py         = _sy2 + 18 + _row * _slot_tpx;')
# Empty list padding is decorative; [+] remains the only creation target.
mark = '    scr_mts_glyph_begin();\n    for (var _si = 0; _si <= _m.stamp_count; _si++) {'
sub(mark,'''    for (var _empty = _m.stamp_count + 1; _empty < (_scroll + _vis_slots) * _cols3; _empty++) {
        var _ex = _list_x1 + (_empty mod _cols3) * _slot_w3;
        var _ey = _cy + ((_empty div _cols3) - _scroll) * _slot_h;
        if (_ey >= _cy) scr_editor_empty_slot(_ex, _ey, _ex + _slot_w3 - 2, _ey + _slot_h - 2);
    }
''' + mark)

with P.open('w', encoding='utf-8', newline='') as f:
    f.write(t.replace('\n','\r\n'))
