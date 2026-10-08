function scr_c64u_reu_continue() {
    var _after  = global.c64u_reu_after;
    var _path_a = global.c64u_reu_path_a;
    var _path_b = global.c64u_reu_path_b;

    // A PRG goes in over the same SocketDMA connection: DMA RUN ($FF02)
    // resets, loads it straight into memory and runs it. The REST runner
    // (run_prg) types LOAD"",8,1 from a temp file instead, and right after a
    // big REU upload that load has been seen to fail (BASIC then runs
    // garbage: ?FORMULA TOO COMPLEX ERROR IN 43690) before it retries.
    if (_after == "PRG" && global.c64u_reu_socket >= 0 && scr_c64u_socket_dma_run(global.c64u_reu_socket, _path_a)) {
        global.c64u_reu_after  = "";
        global.c64u_reu_path_a = "";
        global.c64u_reu_path_b = "";
        global.c64u_reu_state  = "closing";      // scr_c64u_reu_step closes it
        global.c64u_reu_deadline = current_time + 2000;
        global.c64u_status   = "C64U: sent & running";
        global.c64u_status_t = 240;
        return true;
    }

    if (global.c64u_reu_socket >= 0) network_destroy(global.c64u_reu_socket);
    global.c64u_reu_socket = -1;
    global.c64u_reu_state  = "idle";
    global.c64u_reu_after  = "";
    global.c64u_reu_path_a = "";
    global.c64u_reu_path_b = "";
    global.c64u_busy       = false;

    if (_after == "PRG") return scr_c64u_send_file(_path_a);
    if (_after == "D64") return scr_c64u_send_d64_and_run(_path_a, _path_b);
    return false;
}

/// @function scr_c64u_socket_dma_run(socket, prg_path)
/// @description Sends a PRG (with its load address, at most 65535 bytes) as
///              SocketDMA DMA RUN: $02 $FF <length lo> <length hi> <bytes>.
///              Returns false when it cannot (no file, too big, short send).
function scr_c64u_socket_dma_run(_socket, _prg_path) {
    if (_prg_path == "" || !file_exists(_prg_path)) return false;
    var _prg = buffer_load(_prg_path);
    if (_prg < 0) return false;
    var _size = buffer_get_size(_prg);
    if (_size < 3 || _size > 0xFFFF) { buffer_delete(_prg); return false; }
    var _packet = buffer_create(4 + _size, buffer_fixed, 1);
    buffer_poke(_packet, 0, buffer_u8, 0x02);
    buffer_poke(_packet, 1, buffer_u8, 0xFF);
    buffer_poke(_packet, 2, buffer_u8, _size & 0xFF);
    buffer_poke(_packet, 3, buffer_u8, (_size >> 8) & 0xFF);
    buffer_copy(_prg, 0, _size, _packet, 4);
    buffer_delete(_prg);
    // as the REU upload does: offer the tail until the Ultimate takes it
    var _total = 4 + _size, _sent = 0, _wait_until = current_time + 10000;
    while (_sent < _total) {
        var _remain = _total - _sent;
        var _out = buffer_create(_remain, buffer_fixed, 1);
        buffer_copy(_packet, _sent, _remain, _out, 0);
        var _pushed = network_send_raw(_socket, _out, _remain);
        buffer_delete(_out);
        if (_pushed > 0) { _sent += _pushed; _wait_until = current_time + 10000; }
        else if (current_time > _wait_until) break;
    }
    buffer_delete(_packet);
    show_debug_message("C64U: DMA RUN sent " + string(_sent) + " of " + string(_total) + " bytes");
    return _sent == _total;
}
