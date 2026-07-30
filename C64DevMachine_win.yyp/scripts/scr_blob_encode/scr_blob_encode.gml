function scr_blob_encode(_buf) {
    // Returns a base64 string with a "b64:" marker for HYBRID/BINARY saves.
    // Empty / missing buffers return "".
    if (_buf == noone) return "";
    if (!buffer_exists(_buf)) return "";
    var _sz = buffer_get_size(_buf);
    if (_sz <= 0) return "";
    return "b64:" + buffer_base64_encode(_buf, 0, _sz);
}