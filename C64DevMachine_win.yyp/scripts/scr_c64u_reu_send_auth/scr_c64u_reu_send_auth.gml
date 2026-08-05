function scr_c64u_reu_send_auth() {
    var _password = global.c64u_password;
    var _len = string_length(_password);
    var _packet = buffer_create(4 + _len, buffer_fixed, 1);
    buffer_poke(_packet, 0, buffer_u8, 0x1F);
    buffer_poke(_packet, 1, buffer_u8, 0xFF);
    buffer_poke(_packet, 2, buffer_u8, _len & 0xFF);
    buffer_poke(_packet, 3, buffer_u8, (_len >> 8) & 0xFF);
    for (var _i = 0; _i < _len; _i++) {
        buffer_poke(_packet, 4 + _i, buffer_u8, ord(string_char_at(_password, _i + 1)) & 0xFF);
    }
    var _sent = network_send_raw(global.c64u_reu_socket, _packet, 4 + _len);
    buffer_delete(_packet);
    if (_sent != 4 + _len) return scr_c64u_reu_fail("password send failed");
    global.c64u_reu_state    = "auth";
    global.c64u_reu_deadline = current_time + 5000;
    return true;
}