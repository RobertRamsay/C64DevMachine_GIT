/// @desc scr_asset_default_address(type)
/// Returns the default C64 memory address for a given asset type.
///
/// VIC-II BANK LAYOUT:
///   Bank 0: $0000-$3FFF  (CIA2 bits: %11)  - default KERNAL bank, avoid for graphics
///   Bank 1: $4000-$7FFF  (CIA2 bits: %10)  - RECOMMENDED: bitmap + sprites together
///   Bank 2: $8000-$BFFF  (CIA2 bits: %01)  - char ROM shadow at $8800, avoid for chars
///   Bank 3: $C000-$FFFF  (CIA2 bits: %00)  - KERNAL/BASIC ROM conflict, avoid
///
/// BANK 1 LAYOUT (default configuration):
///   $4000-$5F3F  : Bitmap data       (8000 bytes)
///   $5F40-$5FFF  : Padding           (192 bytes, aligns screen to $6000)
///   $6000-$63E7  : Screen RAM        (1000 bytes, KLA screen data)
///   $63E8-$67CF  : Colour source     (1000 bytes, copied to $D800 at runtime)
///   $6800-$6FFF  : Free
///   $7000-$7FFF  : Sprite data       (64 bytes/frame, 64 frames max = 4096 bytes)
///
/// NOTE: Sprites MUST be in the same VIC bank as the bitmap.
///       SID music lives outside VIC banks - anywhere $1000+ is fine.
///       Char/font sets at $3000 stay in bank 0, clear of bitmap bank.

function scr_asset_default_address(_type) {
    switch (_type) {
		case "SID_MUSIC":  return 0x1000; // Above PRG area, free RAM, VIC bank irrelevant for SID
        case "SPRITE_SET": return 0x2800; // Bank 1, clear of bitmap/screen/colour data
        case "BITMAP":     return 0x4000; // Bank 1 base - bitmap at start of bank
        case "CHAR_SET":   return 0x2000; // Bank 0, VIC sees custom chars here safely
		case "MAP_DATA":      return 0x8000;
		case "META_TILESET":  return 0x8000;
		case "META_MAP":      return 0xB000;
		case "TEXT_DATA":  return 0x2600; 
		case "BYTE_DATA":  return 0xC100;
		case "LINE_COLL":  return 0xC300;
		case "PICKUP_TABLE": return 0xC400;
        case "VECTOR_BITMAP": return 0x4000; // bitmap base — must match MACRO_VIC/MACRO_BMP
        // BITMAP_BUILDER is an AUTHORING asset — it emits a BYTE_DATA table and
        // occupies no C64 memory itself. Address is cosmetic only.
		case "SFX_MAKER":
		case "MUSIC_MAKER": return 0x0000;
        // HUD is an AUTHORING asset too — MACRO_HUD emits its chars and
        // colours inline on the spine, so it owns no address of its own.
        case "HUD":         return 0x0000;
        // SAMPLE is emitted by whatever plays it — no address of its own.
        case "SAMPLE":      return 0x0000;
        case "ROOM_MAP":    return 0x0000;
        case "SPRITE_MASK": return 0x0000;
        case "BMP_OBJECTS": return 0x2000;
        case "BITMAP_BUILDER": return 0x0000;
        case "LOAD_ORG":   return 0x0000;
        default:           return 0x2400;
    }
}

/// First page-aligned address at or above _start where _size bytes fit without
/// overlapping another BYTE_DATA asset. Used when a tool creates BYTE_DATA
/// assets for you (Bitmap Builder table + tag grid), so two made back to back
/// don't both land on the $C100 default: the second goes to $C200 (or the next
/// free page if the first is longer than 256 bytes).
function scr_asset_free_address(_start, _size, _self) {
    if (!instance_exists(obj_asset_manager)) return _start;
    var _am   = obj_asset_manager;
    var _cand = _start;
    var _moved = true;
    var _guard = 0;
    while (_moved && _guard < 256) {
        _moved = false;
        _guard += 1;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a == _self || _a.type != "BYTE_DATA") continue;
            if (!buffer_exists(_a.buffer)) continue;
            var _a0 = real(_a.address);
            var _a1 = _a0 + buffer_get_size(_a.buffer);
            if (_cand < _a1 && _a0 < _cand + _size) {
                _cand = ceil(_a1 / 256) * 256;
                _moved = true;
            }
        }
    }
    return _cand;
}

/// Build a new, empty asset of _type exactly as the ADD ASSET menu does (not yet
/// added to the asset list). Shared by the asset panel and the MCP bridge.
function scr_asset_new(_type, _proposed) {
			var _new_buffer = buffer_create(1, buffer_fixed, 1);
			var _new_meta = {};

			if (_type == "CHAR_SET") {
			    // Start with 4 rows of 16 tiles = 64 tiles (64 * 8 bytes = 512 bytes)
			    buffer_delete(_new_buffer);
			    _new_buffer = buffer_create(512, buffer_fixed, 1);
			    buffer_fill(_new_buffer, 0, buffer_u8, 0, 512);
			    _new_meta = {
			        format      : "binary",
			        char_count  : 64,
			        total_size  : 512,
			        preview_surf: -1,
			        mc_mode     : 0,
			        mc_fg       : 1,
			        mc_bg       : 0,
			        mc_col1     : 1,
			        mc_col2     : 2,
			        undo_stack  : [],
			        redo_stack  : []
			    };
			}

			if (_type == "BITMAP") {
			    // Editable KLA/bitmap paint asset. Seed the full editor meta here so
			    // the Draw-event paint routines never read an uninitialised field
			    // (undo_stack in particular is read by the F11 surface-restore block
			    // on the very first frame).
			    _new_meta = {
			        format        : "koala",
			        preview_surf  : -1,
			        pixel_backup  : -1,
			        pixels_dirty  : false,
			        bg_col        : 0,
			        bg_mask       : array_create(64000, 0),
			        clash_grid    : array_create(1000, false),
			        coll_types     : array_create(1000, 0),
			        auto_clean    : true,
			        is_editing    : false,
			        needs_mask_init : false,
			        active_color  : 1,
			        active_tool   : "DRAW",
			        dither_mode   : "NONE",
			        dither_invert : false,
			        brush_size    : 0,
			        bmp_pan_x     : 0,
			        bmp_pan_y     : 0,
			        last_px       : undefined,
			        last_py       : undefined,
			        undo_stack    : [],
			        redo_stack    : [],
			        undo_pending  : false,
			        tone_sorted   : false
			    };
			}

			var _new_asset = {
			    type          : _type,
			    name          : _proposed,
			    file          : "",
			    address       : scr_asset_default_address(_type),
			    buffer        : _new_buffer,
			    meta          : _new_meta,
			    load_later    : false,
			    d64_filename  : (_type == "LOAD_ORG") ? string_upper(_proposed) : "",
			    reu_filename  : (_type == "LOAD_REU") ? _proposed + ".reu" : "",
			    reu_size      : (_type == "LOAD_REU") ? 0x1000000 : 0,
			    reu_used      : (_type == "LOAD_REU") ? 0x100 : 0,
			    linked_assets : (_type == "LOAD_ORG" || _type == "LOAD_REU") ? [] : [],
			};
			if (_type == "ANIMATION") scr_anim_asset_ensure(_new_asset);
			if (_type == "SPRITE_SET") {
			    // Fresh sprite asset starts with a single blank sprite.
			    // 64 bytes = one C64 sprite block, zeroed. Arrays sized to 1;
			    // the "+" cell in the picker grows this up to 64.
			    if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
			    _new_asset.buffer = buffer_create(64, buffer_fixed, 1);
			    buffer_fill(_new_asset.buffer, 0, buffer_u8, 0, 64);
			    _new_asset.meta = {
			        format      : "binary",
			        has_colour  : true,
			        bg_col      : 0,
			        mc1_col     : 1,
			        mc2_col     : 2,
			        sprite_mcs  : array_create(1, 0),
			        sprite_ucs  : array_create(1, 1),
			        spr_sprites : array_create(1, -1),
			        found_count : 1,
			        used_count  : 1,
			        total_size  : 64
			    };
			    scr_asset_spr_cache_sprites(_new_asset, true);

			    var _bmp_connected = false;
			    with (obj_c64_node) {
			        if (node_type == "MACRO_BMP" && is_connected) {
			            _bmp_connected = true;
			        }
			    }
			    if (_bmp_connected) {
			        _new_asset.address = 0x6800;
			    }
			}
			if (_type == "TEXT_DATA") {
                _new_asset.meta.text              = "HELLO WORLD ";
				_new_asset.meta.inline_edit_open      = false;
				_new_asset.meta.inline_edit_text      = _new_asset.meta.text;
				_new_asset.meta.inline_edit_cursor    = 0;
				_new_asset.meta.inline_edit_scroll_y  = 0;
				_new_asset.meta.inline_edit_sel_start = -1;
				_new_asset.meta.inline_edit_sel_end   = -1;
				_new_asset.meta.inline_edit_blink     = 0;
				_new_asset.meta.inline_edit_key_timer = 0;
                scr_asset_text_flush(_new_asset);
            }
           if (_type == "BYTE_DATA") {
                _new_asset.meta.byte_string           = "$00, $01, $02";
				_new_asset.meta.inline_edit_open      = false;
				_new_asset.meta.inline_edit_text      = _new_asset.meta.byte_string;
				_new_asset.meta.inline_edit_cursor    = 0;
				_new_asset.meta.inline_edit_scroll_y  = 0;
				_new_asset.meta.inline_edit_sel_start = -1;
				_new_asset.meta.inline_edit_sel_end   = -1;
				_new_asset.meta.inline_edit_blink     = 0;
				_new_asset.meta.inline_edit_key_timer = 0;
				_new_asset.meta.is_save_file           = false;
				_new_asset.meta.save_file_size          = 256;
                scr_asset_byte_data_flush(_new_asset);
            }
           if (_type == "PICKUP_TABLE") {
                // Pickup lists built from a room map (scr_pickup_*)
                _new_asset.meta.pick      = scr_pickup_default();
                _new_asset.meta.pick_undo = [];
            }
           if (_type == "LINE_COLL") {
                _new_asset.meta.line_string           = "";
                _new_asset.meta.wide_x                = false;
                _new_asset.meta.undo                  = [];
                _new_asset.meta.redo                  = [];
                _new_asset.meta.edit_mode             = false;
                _new_asset.meta.drag_line             = -1;
                _new_asset.meta.drag_end              = 0;
                _new_asset.meta.active_type           = 1;
                _new_asset.meta.draw_x1               = -1;
                _new_asset.meta.draw_y1               = -1;
                _new_asset.meta.ref_enabled           = false;
                _new_asset.meta.ref_asset_name        = "";
                _new_asset.meta.ref_offset_x          = 0;
                _new_asset.meta.ref_offset_y          = 0;
                _new_asset.meta.line_scroll           = 0;
                _new_asset.meta.ref_picker_open       = false;
				_new_asset.meta.lines                 = [];
				_new_asset.meta.inline_edit_open      = false;
				_new_asset.meta.inline_edit_text      = _new_asset.meta.line_string;
				_new_asset.meta.inline_edit_cursor    = 0;
				_new_asset.meta.inline_edit_scroll_y  = 0;
				_new_asset.meta.inline_edit_sel_start = -1;
				_new_asset.meta.inline_edit_sel_end   = -1;
				_new_asset.meta.inline_edit_blink     = 0;
				_new_asset.meta.inline_edit_key_timer = 0;
                scr_line_coll_flush(_new_asset);
            }
        if (_type == "MAP_DATA") {
            _new_asset.meta = {
                map_w             : 40,
                map_h             : 25,
                grid_w            : 40,
                grid_h            : 25,
                char_grid         : array_create(40 * 25, 0),
                colour_grid       : array_create(40 * 25, 1),
                override_grid     : array_create(40 * 25, 0),
                chr_asset         : "",
                scroll_x          : 0,
                scroll_y          : 0,
                zoom              : 2,
                active_char       : 0,
                active_colour     : 1,
                tool              : "CHAR",
                char_strip_offset : 0,
                preview_surf      : -1,
                mc_mode           : 2,
                paint_mc          : 0,
                map_mc_bg         : -1,
                map_mc_col1       : -1,
                map_mc_col2       : -1,
                raw_chars         : 0,
                stream_flag_colour: -1,
                room_view         : [],
                view_y2           : false,
                erase_char        : 0,
                stamp_data        : [],
                stamp_active      : false,
                sel_grid          : array_create(40 * 25, 0),
                map_undo_stack    : [],
                map_redo_stack    : []
            };
        }
        if (_type == "META_TILESET") {
            scr_asset_meta_tileset_create(_new_asset);
        }
        if (_type == "BITMAP_BUILDER") {
            // Authoring asset — no C64 payload of its own.
            if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
            _new_asset.buffer = buffer_create(1, buffer_fixed, 1);
            scr_bitmap_builder_create(_new_asset);
        }
        if (_type == "HUD") {
            // Authoring asset: the buffer is only there so the workspace saver
            // has something to blob out — MACRO_HUD reads the grids in meta.
            if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
            _new_asset.buffer = buffer_create(1, buffer_fixed, 1);
            scr_hud_create(_new_asset);
        }
        if (_type == "SAMPLE") {
            // The buffer becomes the imported source PCM; until then it is
            // the 1-byte placeholder every authoring asset carries.
            if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
            _new_asset.buffer = buffer_create(1, buffer_fixed, 1);
            scr_sample_create(_new_asset);
        }
        if (_type == "ROOM_MAP") {
            // Authoring asset: rooms, exits and arrival points. MACRO_ROOMS
            // turns it into tables; it owns no C64 memory of its own.
            if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
            _new_asset.buffer = buffer_create(1, buffer_fixed, 1);
            scr_room_map_create(_new_asset);
        }
        if (_type == "SPRITE_MASK") {
            // Painted foreground layer; its buffer is the compiled mask blob,
            // which is what a LOAD_REU link packs.
            scr_sprmask_create(_new_asset);
        }
        if (_type == "BMP_OBJECTS") {
            // Software sprites: the buffer is the C64 payload as-is, the meta
            // lists where each object's graphics and mask sit inside it.
            scr_bmpobj_create(_new_asset);
        }
        if ((_type == "MUSIC_MAKER" || _type == "SFX_MAKER")) {
            // Authoring asset — no C64 payload of its own, same family as
            // BITMAP_BUILDER. GENERATE emits the real BYTE_DATA/TEXT_DATA
            // assets (instruments + per-voice patterns) that SEQ VOICE nodes
            // consume.
            if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
            _new_asset.buffer = buffer_create(1, buffer_fixed, 1);
            if (_type == "SFX_MAKER") scr_sfx_maker_create(_new_asset); else scr_sound_editor_create(_new_asset);
        }
        if (_type == "META_MAP") {
            scr_asset_meta_map_create(_new_asset);
        }
        if (_type == "VECTOR_BITMAP") {
            // No buffer — the picture is a replayable command list, not pixels.
            // commands[] is an ordered array of primitive structs (see compile case).
            // Coords are hi-res pixel space (x 0-319, y 0-199) regardless of mode;
            // the C64 plot routine folds x for MC. SETCOL values are MC source
            // selectors 0-3 (00 bg / 01 scr-hi / 10 scr-lo / 11 col-RAM).
            if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
            _new_asset.buffer = -1; // no binary payload; bytes emitted by MACRO_VECTOR_BMP via org
            _new_asset.meta = {
                mode          : 1,        // 0 = HR, 1 = MC (default MC)
                bg            : 0,        // selector 0 → $D021 background colour
                col1          : 1,        // selector 1 → screen-RAM upper nibble (white)
                col2          : 2,        // selector 2 → screen-RAM lower nibble (red)
                col3          : 3,        // selector 3 → colour RAM (cyan)
                fill_stack    : 0xC000,   // flood-fill RAM stack base on C64
                stream_addr   : 0xC800,   // where the command byte-stream lands in the PRG (safe RAM)
                commands      : [],       // ordered primitive structs (PAGE 0's list — mirror of pages[0].commands)
                // ── MULTI-PAGE ── pages[] is the source of truth. Page 0's
                // commands/bg/col1/col2/col3 are ALSO kept in the top-level
                // fields above for backward-compat with single-page code paths.
                // The editor edits pages[active_page]; on switch it syncs the
                // active page's fields up to top-level. See scr_vbmp_page_*.
                pages         : [ { commands: [], bg: 0, col1: 1, col2: 2, col3: 3 } ],
                active_page   : 0,        // which page the inline editor is editing
                // editor preview state (built lazily by the editor, never serialised as pixels)
                preview_surf  : -1,
                active_col    : 1,        // current selector for new ops
                active_pat    : 0,        // current dither pattern index
                tool          : "LINE",   // editor active tool
                draw_x1       : -1,
                draw_y1       : -1,
                zoom          : 2,
                vbmp_undo_stack : [],
                vbmp_redo_stack : [],
                // KLA-compat fields so the shared scr_asset_bmp_draw_* routines
                // run against this asset without crashing. Editor-only, not serialised.
                bg_mask       : array_create(64000, 0),
                dither_mode   : "NONE",
                dither_invert : false,
                brush_size    : 0
            };
        }
    return _new_asset;
}
