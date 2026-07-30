/// @function scr_asset_bmp_hr_repaint_cell_gpu(_asset, _cell_idx)
/// @desc HiRes only. Repaints one 8x8 cell using plain draw_rectangle calls
///       against WHATEVER surface is currently the active render target.
///       Unlike scr_asset_bmp_hr_repaint_cell_in_buffer, this never touches a
///       buffer — safe to call from code that is already inside
///       surface_set_target(preview_surf), where reading that same surface
///       back via buffer_get_surface is unreliable (it can return stale/blank
///       data since the surface is mid-render).
function scr_asset_bmp_hr_repaint_cell_gpu(_asset, _cell_idx) {
    var _gx = _cell_idx mod 40;
    var _gy = _cell_idx div 40;
    var _fg_c = scr_c64_pepto_colour(_asset.meta.hr_cell_fg_col[_cell_idx]);
    var _bg_c = scr_c64_pepto_colour(_asset.meta.hr_cell_bg_col[_cell_idx]);
    
    for (var _py = 0; _py < 8; _py++) {
        var _abs_y = _gy * 8 + _py;
        for (var _px = 0; _px < 8; _px++) {
            var _abs_x = _gx * 8 + _px;
            draw_set_color((_asset.meta.hr_role_mask[_abs_y * 320 + _abs_x] == 1) ? _fg_c : _bg_c);
            draw_rectangle(_abs_x, _abs_y, _abs_x + 1, _abs_y + 1, false);
        }
    }
}