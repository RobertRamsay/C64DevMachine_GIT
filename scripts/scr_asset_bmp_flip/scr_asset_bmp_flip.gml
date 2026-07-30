/// @function scr_asset_bmp_flip(_asset, _flip_x, _flip_y)
/// @desc Flips the entire bitmap canvas horizontally and/or vertically.
///       Respects MC pixel pairs in Multicolour mode, or single pixels in HiRes.
///       HiRes also remaps hr_role_mask (per-pixel) and hr_cell_fg_col/
///       hr_cell_bg_col (per-cell) — without this the RAW PIXELS flip
///       correctly but the role model still thinks the pre-flip layout is
///       current, so the next repaint (any subsequent paint stroke, or
///       reopening the editor) would silently revert the flip.
function scr_asset_bmp_flip(_asset, _flip_x, _flip_y) {
    if (!variable_struct_exists(_asset.meta, "preview_surf") || !surface_exists(_asset.meta.preview_surf)) return;
    
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _step     = _is_hires ? 1 : 2;
    var _w = 320, _h = 200;
    
    // Read current surface into buffer
    var _buf = buffer_create(_w * _h * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _asset.meta.preview_surf, 0);
    
    // Create output buffer
    var _out = buffer_create(_w * _h * 4, buffer_fixed, 1);
    buffer_copy(_buf, 0, _w * _h * 4, _out, 0);
    
    // HiRes role-model remap: per-pixel role mask needs a fresh array (can't
    // flip in place — same source/dest aliasing problem the pixel buffer has,
    // which is why _out is separate from _buf above). Per-cell colours are
    // remapped from the mirrored source cell.
    var _new_role = -1, _new_fg = -1, _new_bg = -1;
    if (_is_hires) {
        _new_role = array_create(64000, 0);
        _new_fg   = array_create(1000, 0);
        _new_bg   = array_create(1000, 0);
        for (var _cy = 0; _cy < 25; _cy++) {
            for (var _cx = 0; _cx < 40; _cx++) {
                var _scx = _flip_x ? (39 - _cx) : _cx;
                var _scy = _flip_y ? (24 - _cy) : _cy;
                var _dst_cell = _cy * 40 + _cx;
                var _src_cell = _scy * 40 + _scx;
                _new_fg[_dst_cell] = _asset.meta.hr_cell_fg_col[_src_cell];
                _new_bg[_dst_cell] = _asset.meta.hr_cell_bg_col[_src_cell];
            }
        }
    }
    
    for (var _y = 0; _y < _h; _y++) {
        for (var _x = 0; _x < _w; _x += _step) { // MC pixel pairs, or single HiRes pixels
            
            // Source coordinates after flip
            var _sx = _flip_x ? (_w - _step - _x) : _x;
            var _sy = _flip_y ? (_h - 1 - _y) : _y;
            
            var _src  = (_sy * _w + _sx) * 4;
            var _dst  = (_y  * _w + _x)  * 4;
            
            buffer_poke(_out, _dst,     buffer_u8, buffer_peek(_buf, _src,     buffer_u8));
            buffer_poke(_out, _dst + 1, buffer_u8, buffer_peek(_buf, _src + 1, buffer_u8));
            buffer_poke(_out, _dst + 2, buffer_u8, buffer_peek(_buf, _src + 2, buffer_u8));
            buffer_poke(_out, _dst + 3, buffer_u8, buffer_peek(_buf, _src + 3, buffer_u8));
            _asset.meta.bg_mask[_y * _w + _x] = _asset.meta.bg_mask[_sy * _w + _sx];
            
            if (_is_hires) {
                _new_role[_y * _w + _x] = _asset.meta.hr_role_mask[_sy * _w + _sx];
            } else {
                var _src2 = (_sy * _w + _sx + 1) * 4;
                var _dst2 = (_y  * _w + _x  + 1) * 4;
                buffer_poke(_out, _dst2,     buffer_u8, buffer_peek(_buf, _src2,     buffer_u8));
                buffer_poke(_out, _dst2 + 1, buffer_u8, buffer_peek(_buf, _src2 + 1, buffer_u8));
                buffer_poke(_out, _dst2 + 2, buffer_u8, buffer_peek(_buf, _src2 + 2, buffer_u8));
                buffer_poke(_out, _dst2 + 3, buffer_u8, buffer_peek(_buf, _src2 + 3, buffer_u8));
                _asset.meta.bg_mask[_y * _w + _x + 1] = _asset.meta.bg_mask[_sy * _w + _sx + 1];
            }
        }
    }
    
    buffer_set_surface(_out, _asset.meta.preview_surf, 0);
    buffer_delete(_buf);
    buffer_delete(_out);
    
    if (_is_hires) {
        _asset.meta.hr_role_mask   = _new_role;
        _asset.meta.hr_cell_fg_col = _new_fg;
        _asset.meta.hr_cell_bg_col = _new_bg;
    }
    
    // Trigger clash rescan
    _asset.meta.needs_clash_check = true;
}