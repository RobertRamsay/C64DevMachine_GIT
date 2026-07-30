/// @desc Initialise a META_TILESET asset meta struct
/// @param {struct} _asset  The asset struct to initialise
function scr_asset_meta_tileset_create(_asset) {
    _asset.meta.stamp_w        = 2;
    _asset.meta.stamp_h        = 2;
    _asset.meta.stamp_count    = 0;
    _asset.meta.stamp_data     = [];
    _asset.meta.stamp_mc       = [];   // DORMANT: legacy per-stamp HR/MC flag, kept for old-file round-trip; mode now lives in char_lut
    _asset.meta.char_lut       = array_create(256, 1);   // per-char (mode<<4 | colour): bit4 = MC, bits0-3 = colour
    _asset.meta.char_lut_len   = 0;                       // meaningful extent = linked charset char_count
    _asset.meta.stamp_override = [];                       // per whole stamp colour override; 0-15 = force colour, $80 = none
    _asset.meta.active_stamp   = -1;
    _asset.meta.edit_stamp     = -1;
    _asset.meta.chr_asset      = "";
    _asset.meta.map_mc_bg      = -1;   // -1 = inherit BG0 from linked CHAR_SET (matches MAP_DATA convention)
    _asset.meta.map_mc_col1    = 1;
    _asset.meta.map_mc_col2    = 2;
    _asset.meta.paint_mc       = 0;
    _asset.meta.active_char    = 0;
    _asset.meta.active_colour  = 1;
    _asset.meta.active_mode    = 0;    // retired per-node paint mode (mode now lives in char_lut); kept zeroed so Draw needn't retrofit it
    _asset.meta.is_dirty               = false;
    _asset.meta.stamp_list_scroll      = 0;
    _asset.meta.active_stamp_grid_char = array_create(4, 0);
    // col/ov grids retired: cell colour now comes from char_lut[char]. Kept as
    // empty stubs so any lingering reference fails soft rather than crashing.
    _asset.meta.active_stamp_grid_col  = array_create(4, 0);
    _asset.meta.active_stamp_grid_ov   = array_create(4, 0);
    _asset.meta.char_strip_offset      = 0;
    _asset.meta.char_strip_scroll_row  = 0;
    _asset.meta.zoom                   = 0;
    _asset.meta.test_zoom              = 1;
    _asset.meta.maps                   = [];   // real maps (rooms); each is a grid of metatile indices, -1 = empty
    _asset.meta.map_count              = 0;    // number of real maps
    _asset.meta.active_map             = -1;   // -1 = test map; 0+ = real map index
    _asset.meta.map_bytes              = [];   // cached byte count per real map (filled by counter phase)
    _asset.meta.map_w                  = [];   // per-map width  in metatiles (parallel to maps[])
    _asset.meta.map_h                  = [];   // per-map height in metatiles (parallel to maps[])
    _asset.meta.view_w                 = 40;   // C64 view window width  in char cells (changeable, default screen)
    _asset.meta.view_h                 = 25;   // C64 view window height in char cells (changeable, default screen)
    _asset.meta.offset_x               = 0;    // view window origin X in char cells (top-left of the visible frame)
    _asset.meta.offset_y               = 0;    // view window origin Y in char cells
    _asset.meta.map_size_key           = "";   // stamp-size signature; grid wipes when this changes
    _asset.meta.edit_view_mode         = 0;    // 0 = MAP (whole map + window), 1 = VIEW (zoomed to window)
    _asset.meta.show_types_overlay     = false;// T toggles the per-cell tile-type badge overlay
    _asset.meta.pan_anchor_x           = -1;   // mouse char-cell position where the current grab began (-1 = not panning)
    _asset.meta.pan_anchor_y           = -1;
    _asset.meta.pan_start_ox           = 0;    // offset_x at the moment the grab began
    _asset.meta.pan_start_oy           = 0;    // offset_y at the moment the grab began
    _asset.meta.stamp_clip             = [];   // copied metatile cells (char indices) for Ctrl+C / Ctrl+V
    _asset.meta.stamp_clip_valid       = false;// true once a stamp has been copied
    _asset.address                     = 0x8000;
}