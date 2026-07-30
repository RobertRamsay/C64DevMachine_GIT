/// @desc Initialise a META_MAP asset meta struct
/// @param {struct} _asset  The asset struct to initialise
function scr_asset_meta_map_create(_asset) {
    _asset.meta.map_w          = 40;
    _asset.meta.map_h          = 25;
    _asset.meta.tileset_name   = "";
    _asset.meta.index_data     = [];
    _asset.meta.scroll_x       = 0;
    _asset.meta.scroll_y       = 0;
    _asset.meta.zoom           = 2;
    _asset.meta.show_grid      = true;
    _asset.meta.active_stamp   = 0;
    _asset.meta.stamp_scroll   = 0;
    _asset.meta.is_dirty       = false;
    _asset.address             = 0xB000;
}