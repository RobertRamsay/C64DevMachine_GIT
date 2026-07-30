/// array_copy_shallow(src)
/// Returns a shallow copy of a 1D array
function array_copy_shallow(src) {
    var _len = array_length(src);
    var _dst = array_create(_len, 0);
    array_copy(_dst, 0, src, 0, _len);
    return _dst;
}