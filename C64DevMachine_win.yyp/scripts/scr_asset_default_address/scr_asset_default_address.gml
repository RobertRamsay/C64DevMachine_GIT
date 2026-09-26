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
        case "VECTOR_BITMAP": return 0x4000; // bitmap base — must match MACRO_VIC/MACRO_BMP
        // BITMAP_BUILDER is an AUTHORING asset — it emits a BYTE_DATA table and
        // occupies no C64 memory itself. Address is cosmetic only.
		case "SFX_MAKER":
		case "MUSIC_MAKER": return 0x0000;
        // HUD is an AUTHORING asset too — MACRO_HUD emits its chars and
        // colours inline on the spine, so it owns no address of its own.
        case "HUD":         return 0x0000;
        case "ROOM_MAP":    return 0x0000;
        case "SPRITE_MASK": return 0x0000;
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
