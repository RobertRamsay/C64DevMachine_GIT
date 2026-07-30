/// @function scr_asset_bmp_is_hires(_asset)
/// @desc Returns true if this BITMAP asset is set to HiRes (2 colour/cell) mode.
///       Assets with no bmp_mode set yet default to Multicolour for backward compat.
function scr_asset_bmp_is_hires(_asset) {
    if (!variable_struct_exists(_asset.meta, "bmp_mode")) return false;
    return (_asset.meta.bmp_mode == "HIRES");
}