/// @desc Sync MACRO_CHR node instructions from linked CHAR_SET asset
/// @param {Id.Instance} _node
function scr_macro_chr_sync(_node) {
    var _asset_name = _node.instructions[0][1];
    var _mc_flag    = real(_node.instructions[0][2]); // node-local default; overridden by asset meta below
    var _chr_addr   = 0x3000; // fallback default
	
    // Look up the named CHAR_SET asset in the asset manager
    if (instance_exists(obj_asset_manager)) {
        with (obj_asset_manager) {
            for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
                var _a = ds_list_find_value(asset_list, _i);
                if (_a.type == "CHAR_SET" && _a.name == _asset_name) {
                    _chr_addr = _a.address;
                    break;
                }
            }
        }
    }

    // Calculate $D018 value
    // Screen RAM at $0400 = bits 7-4 = 0001 = $1 << 4
    // Charset offset = (chr_addr / $0800) & 0x07, shifted into bits 3-1
    // Bit 0 always 1 (VIC default)
    var _chr_offset = (_chr_addr / 0x0800) & 0x07;
    var _d018_val   = (0x01 << 4) | (_chr_offset << 1) | 0x01;
    
    // $D011 — standard or multicolour text mode
    // Standard:     $D011 = $1B, $D016 = $08
    // Multicolour:  $D011 = $1B, $D016 = $18 (bit 4 set)
    var _d016_val = _mc_flag ? 0x18 : 0x08;

// Read MC colours from asset (defaults if not present)
    var _mc_bg   = 0;
    var _mc_col1 = 1;
    var _mc_col2 = 2;
    if (instance_exists(obj_asset_manager)) {
        with (obj_asset_manager) {
            for (var _ci = 0; _ci < ds_list_size(asset_list); _ci++) {
                var _ca = ds_list_find_value(asset_list, _ci);
                if (_ca.type == "CHAR_SET" && _ca.name == _asset_name) {
                    if (variable_struct_exists(_ca.meta, "mc_bg"))   _mc_bg   = _ca.meta.mc_bg;
                    if (variable_struct_exists(_ca.meta, "mc_col1")) _mc_col1 = _ca.meta.mc_col1;
                    if (variable_struct_exists(_ca.meta, "mc_col2")) _mc_col2 = _ca.meta.mc_col2;
                    if (variable_struct_exists(_ca.meta, "mc_mode")) _mc_flag = _ca.meta.mc_mode;
                    break;
                }
            }
        }
    }
var _char_col = 1; // Default to White

    // COLOURS COME FROM ASSET META (set by the charset editor's BG/C1/C2 pickers).
    // _mc_bg / _mc_col1 / _mc_col2 were already read from _ca.meta above, so do NOT
    // overwrite them with the node's stale slot values — that was burying editor
    // colour changes under the previously-built (default 0) slot 7/9/11.
    // Preserve custom Character Colour
    if (array_length(_node.instructions) > 0 && array_length(_node.instructions[0]) > 3) {
        _char_col = _node.instructions[0][3];
    }

    // Rebuild instructions — slot 0 carries the resolved MC flag (from asset meta or node override)
    _node.instructions = [
        ["macro_chr",  _asset_name, _mc_flag, _char_col], // slot 0: params (not assembled)
        ["lda_imm",    0x1B],                    // $D011
        ["sta_abs",    0xD011],
        ["lda_imm",    _d016_val],               // $D016 - multicolour flag
        ["sta_abs",    0xD016],
        ["lda_imm",    _d018_val],               // $D018 - charset pointer
        ["sta_abs",    0xD018],
        ["lda_imm",    _mc_bg],                  // $D021 - background colour
        ["sta_abs",    0xD021],
        ["lda_imm",    _mc_col1],                // $D022 - MC colour 1
        ["sta_abs",    0xD022],
        ["lda_imm",    _mc_col2],                // $D023 - MC colour 2
        ["sta_abs",    0xD023],
    ];




    global.addresses_dirty = true;
    scr_c64_update_addresses();
}