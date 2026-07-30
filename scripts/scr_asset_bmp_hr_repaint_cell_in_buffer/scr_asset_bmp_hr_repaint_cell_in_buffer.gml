/// @function scr_asset_bmp_hr_repaint_cell_in_buffer(_asset, _buf, _cell_idx)
/// @desc HiRes only. Repaints every pixel of one 8x8 cell directly into _buf,
///       using that cell's stored hr_cell_fg_col/hr_cell_bg_col and each
///       pixel's hr_role_mask (0=bg,1=fg). Called immediately after ANY paint
///       touches a cell, so the whole cell's matching role updates in one
///       step — no deferred cleanup/resolve pass needed at all.
function scr_asset_bmp_hr_repaint_cell_in_buffer(_asset, _buf, _cell_idx) {
    var _gx = _cell_idx mod 40;
    var _gy = _cell_idx div 40;
    var _fg_c = scr_c64_pepto_colour(_asset.meta.hr_cell_fg_col[_cell_idx]);
    var _bg_c = scr_c64_pepto_colour(_asset.meta.hr_cell_bg_col[_cell_idx]);
    var _fr = color_get_red(_fg_c), _fgc = color_get_green(_fg_c), _fb = color_get_blue(_fg_c);
    var _br = color_get_red(_bg_c), _bgc = color_get_green(_bg_c), _bb = color_get_blue(_bg_c);
    
    for (var _py = 0; _py < 8; _py++) {
        var _abs_y = _gy * 8 + _py;
        for (var _px = 0; _px < 8; _px++) {
            var _abs_x = _gx * 8 + _px;
            var _off   = (_abs_y * 320 + _abs_x) * 4;
            if (_asset.meta.hr_role_mask[_abs_y * 320 + _abs_x] == 1) {
                buffer_poke(_buf, _off,     buffer_u8, _fr);
                buffer_poke(_buf, _off + 1, buffer_u8, _fgc);
                buffer_poke(_buf, _off + 2, buffer_u8, _fb);
            } else {
                buffer_poke(_buf, _off,     buffer_u8, _br);
                buffer_poke(_buf, _off + 1, buffer_u8, _bgc);
                buffer_poke(_buf, _off + 2, buffer_u8, _bb);
            }
            buffer_poke(_buf, _off + 3, buffer_u8, 255);
        }
    }
}