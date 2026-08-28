function scr_sid64_import(_node_id) {
    var _path = get_open_filename("SID Music File|*.sid", "");
    // A native file dialog takes focus, so the key-up that ends the keypress is
    // delivered to the dialog and not to the game. GameMaker is left thinking the
    // key is still held, and keyboard_check_pressed() needs an up->down edge — so
    // ESC silently stops working until the input state is reset. This is why ESC
    // only failed after SOME asset operations: scr_asset_sid_import already did
    // this, every other importer did not.
    io_clear();
    if (_path == "" || !file_exists(_path)) exit;

    var _buf = buffer_load(_path);
    if (_buf < 0) exit;

    //  1. PARSE SID HEADER 
    var _version = (buffer_peek(_buf, 0x04, buffer_u8) << 8) | buffer_peek(_buf, 0x05, buffer_u8);
    var _header_size = (buffer_peek(_buf, 0x06, buffer_u8) << 8) | buffer_peek(_buf, 0x07, buffer_u8);
    if (_header_size != 0x76 && _header_size != 0x7C) _header_size = (_version <= 1) ? 0x76 : 0x7C;
	

    var _raw_load = (buffer_peek(_buf, 0x08, buffer_u8) << 8) | buffer_peek(_buf, 0x09, buffer_u8);
    var _load_addr, _data_start;
    if (_raw_load != 0) {
        _load_addr  = _raw_load;
        _data_start = _header_size;
    } else {
        _load_addr  = buffer_peek(_buf, _header_size, buffer_u8) | (buffer_peek(_buf, _header_size + 1, buffer_u8) << 8);
        _data_start = _header_size + 2;
    }
	
// Some SID files have incorrect load address in header
// If data_size would place data correctly at a lower address, adjust
var _true_load = _load_addr;
if (_raw_load != 0) {
    // Check if embedded address differs - trust the embedded one
    var _emb = buffer_peek(_buf, _header_size, buffer_u8) | 
               (buffer_peek(_buf, _header_size + 1, buffer_u8) << 8);
    if (_emb != 0 && _emb < _load_addr) {
        _true_load  = _emb;
        _data_start = _header_size + 2;
      var  _data_size  = buffer_get_size(_buf) - _data_start;
      
    }
}
_load_addr = _true_load;

var _init_addr = (buffer_peek(_buf, 0x0A, buffer_u8) << 8) | buffer_peek(_buf, 0x0B, buffer_u8);
var _play_addr = (buffer_peek(_buf, 0x0C, buffer_u8) << 8) | buffer_peek(_buf, 0x0D, buffer_u8);

//show_debug_message("RAW HEADER: init=$" + string_upper(decimal_to_hex(_init_addr)) + " play=$" + string_upper(decimal_to_hex(_play_addr)));

if (_init_addr == 0) _init_addr = _load_addr;
if (_play_addr == 0) _play_addr = _load_addr + 3;

if (_init_addr < 0x0800) _init_addr = _load_addr + _init_addr;
if (_play_addr < 0x0800) _play_addr = _load_addr + _play_addr;

//show_debug_message("FINAL: init=$" + string_upper(decimal_to_hex(_init_addr)) + " play=$" + string_upper(decimal_to_hex(_play_addr)));
    
    var _raw_hi = buffer_peek(_buf, 0x0E, buffer_u8);
    var _raw_lo = buffer_peek(_buf, 0x0F, buffer_u8);
    var _num_songs = ((_raw_hi << 8) | _raw_lo) & 0xFF; 
    if (_num_songs == 0) _num_songs = 1;

    var _start_song = ((buffer_peek(_buf, 0x10, buffer_u8) << 8) | buffer_peek(_buf, 0x11, buffer_u8)) - 1;
    _start_song = clamp(_start_song, 0, max(_num_songs - 1, 0));

    var _speed = 0;
    for (var _b = 0; _b < 4; _b++) _speed = (_speed << 8) | buffer_peek(_buf, 0x12 + _b, buffer_u8);
    var _uses_cia = ((_speed >> (_start_song & 31)) & 1) == 1;

    //  2. READ STRINGS 
    var _title = "";
    for (var _i = 0; _i < 32; _i++) {
        var _c = buffer_peek(_buf, 0x16 + _i, buffer_u8);
        if (_c == 0) break;
        _title += chr(_c);
    }
    if (_title == "") _title = "UNTITLED";

    var _author = "";
    for (var _i = 0; _i < 32; _i++) {
        var _c = buffer_peek(_buf, 0x36 + _i, buffer_u8);
        if (_c == 0) break;
        _author += chr(_c);
    }
    if (_author == "") _author = "UNKNOWN";

    //  3. BINARY BRIDGE (Logic for Memory Bar) 
    var _data_size = buffer_get_size(_buf) - _data_start;
    if (_data_size > 0) {
        if (variable_instance_exists(_node_id, "sprite_buffer")) {
            if (buffer_exists(_node_id.sprite_buffer)) buffer_delete(_node_id.sprite_buffer);
        }
        
        _node_id.sprite_buffer = buffer_create(_data_size, buffer_fixed, 1);
        buffer_copy(_buf, _data_start, _data_size, _node_id.sprite_buffer, 0);
        _node_id.total_node_size = _data_size; 

        // Generate Hex Blob for saving
        var _hex_blob = "";
        buffer_seek(_node_id.sprite_buffer, buffer_seek_start, 0);
        repeat(_data_size) {
            _hex_blob += decimal_to_hex(buffer_read(_node_id.sprite_buffer, buffer_u8));
        }
        _node_id.binary_blob = _hex_blob;
    }
	show_debug_message("SID IMPORT: load=$" + string_upper(decimal_to_hex(_load_addr)) 
    + " init=$" + string_upper(decimal_to_hex(_init_addr)) 
    + " play=$" + string_upper(decimal_to_hex(_play_addr)));
	
	show_debug_message("FILE SIZE: " + string(buffer_get_size(_buf)) + " DATA START: " + string(_data_start) + " DATA SIZE: " + string(_data_size));
	
	
    buffer_delete(_buf); // Cleanup temp buffer

    //  4. DATA SYNC (The Dashboard Fix) 
    _node_id.instructions[0][1] = "BIN_DATA_ACTIVE"; 
    _node_id.instructions[0][2] = _load_addr;
    _node_id.instructions[0][3] = _init_addr;
    _node_id.instructions[0][4] = _play_addr;
    _node_id.instructions[0][5] = _num_songs;
    _node_id.instructions[0][6] = _start_song;
    _node_id.instructions[0][7] = _title;

    _node_id.sid_title      = _title;
    _node_id.sid_author     = _author;
    _node_id.sid_songs      = _num_songs;
    _node_id.sid_load_addr  = _load_addr;
    _node_id.sid_init_addr  = _init_addr;
    _node_id.sid_play_addr  = _play_addr;
    _node_id.sid_start_song = _start_song;
    _node_id.sid_uses_cia   = _uses_cia;

    _node_id.pc_address = _load_addr;

    scr_c64_update_addresses();
}