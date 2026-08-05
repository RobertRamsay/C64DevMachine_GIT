function scr_c64u_async_network() {
    if (global.c64u_reu_state == "idle") return false;
    if (async_load[? "id"] != global.c64u_reu_socket) return false;
    var _type = async_load[? "type"];

    if (_type == network_type_non_blocking_connect) {
        if (async_load[? "succeeded"] != 1) return scr_c64u_reu_fail("enable Ultimate DMA Service (TCP port 64)");
        if (global.c64u_password != "") return scr_c64u_reu_send_auth();
        return scr_c64u_reu_send_payload();
    }

    if (_type == network_type_data && global.c64u_reu_state == "auth") {
        var _buf = async_load[? "buffer"];
        var _size = async_load[? "size"];
        if (_size < 1 || buffer_peek(_buf, 0, buffer_u8) != 1) return scr_c64u_reu_fail("DMA password rejected");
        return scr_c64u_reu_send_payload();
    }

    if (_type == network_type_disconnect) return scr_c64u_reu_fail("DMA service disconnected");
    return true;
}