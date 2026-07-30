function array_copy_deep(_arr) {
    var _out = array_create(array_length(_arr));
    for (var _i = 0; _i < array_length(_arr); _i++) {
        if (is_array(_arr[_i])) {
            _out[_i] = array_copy_deep(_arr[_i]);
        } else {
            _out[_i] = _arr[_i];
        }
    }
    return _out;
}