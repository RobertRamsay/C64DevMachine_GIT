function scr_c64u_reu_send_payload() {
    var _image = buffer_load(global.reu_last_image);
    if (_image < 0) return scr_c64u_reu_fail("could not open generated image");

    var _total = min(buffer_get_size(_image), max(0x100, real(global.reu_last_used)));
    var _offset = 0;
    var _chunk_max = 8192;

    while (_offset < _total) {
        var _chunk = min(_chunk_max, _total - _offset);
        // Ultimate SocketDMA frame: command $FF07, 16-bit payload length,
        // 24-bit REU destination, then raw bytes.
        var _packet = buffer_create(7 + _chunk, buffer_fixed, 1);
        buffer_poke(_packet, 0, buffer_u8, 0x07);
        buffer_poke(_packet, 1, buffer_u8, 0xFF);
        buffer_poke(_packet, 2, buffer_u8, (_chunk + 3) & 0xFF);
        buffer_poke(_packet, 3, buffer_u8, ((_chunk + 3) >> 8) & 0xFF);
        buffer_poke(_packet, 4, buffer_u8, _offset & 0xFF);
        buffer_poke(_packet, 5, buffer_u8, (_offset >> 8) & 0xFF);
        buffer_poke(_packet, 6, buffer_u8, (_offset >> 16) & 0xFF);
        buffer_copy(_image, _offset, _chunk, _packet, 7);

        var _sent = network_send_raw(global.c64u_reu_socket, _packet, 7 + _chunk);
        buffer_delete(_packet);
        if (_sent != 7 + _chunk) {
            buffer_delete(_image);
            return scr_c64u_reu_fail("network write stopped at $" + string_upper(decimal_to_hex(_offset)));
        }
        _offset += _chunk;
    }

    buffer_delete(_image);
    global.c64u_reu_state    = "settle";
    global.c64u_reu_deadline = current_time + 250;
    global.c64u_status       = "C64U REU: uploaded " + string(_total) + " bytes";
    global.c64u_status_t     = 240;
    show_debug_message("C64U REU: uploaded " + string(_total) + " bytes from " + global.reu_last_image);
    return true;
}