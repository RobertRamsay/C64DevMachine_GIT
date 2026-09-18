// Route only our socket. Never consume or modify C64U's networking state.
if (probe_socket < 0 || async_load[? "id"] != probe_socket) exit;
var _type = async_load[? "type"];
if (_type == network_type_non_blocking_connect) {
    if (async_load[? "succeeded"] != 1) {
        probe_stop("OFF - bridge not listening or connection refused"); exit;
    }
    probe_state = "handshake";
    probe_last_rx = current_time;
    probe_send(json_stringify({event: "hello", protocol: 1, token: probe_token}));
    exit;
}
if (_type == network_type_disconnect) {
    probe_stop("OFF - bridge disconnected"); exit;
}
if (_type != network_type_data) exit;
var _buf = async_load[? "buffer"];
var _size = async_load[? "size"];
if (_size < 0 || _size > probe_max_line) {
    probe_stop("OFF - incoming packet exceeded prototype limit"); exit;
}
// Accumulate BYTES until LF, then decode a complete UTF-8 string. The event's
// temporary buffer is never retained. Both partial and coalesced frames work.
for (var _i = 0; _i < _size; _i++) {
    var _byte = buffer_peek(_buf, _i, buffer_u8);
    if (_byte == 0) { probe_stop("OFF - NUL in command stream"); exit; }
    if (_byte == 10) {
        if (probe_rx_len > 0) {
            if (array_length(probe_queue) >= 8) {
                probe_stop("OFF - command queue full"); exit;
            }
            buffer_poke(probe_rx, probe_rx_len, buffer_u8, 0);
            array_push(probe_queue, buffer_peek(probe_rx, 0, buffer_string));
            probe_rx_len = 0;
        }
    } else {
        if (probe_rx_len >= probe_max_line) {
            probe_stop("OFF - command exceeded prototype limit"); exit;
        }
        buffer_poke(probe_rx, probe_rx_len, buffer_u8, _byte);
        probe_rx_len++;
    }
}
