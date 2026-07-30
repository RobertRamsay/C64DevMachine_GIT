function scr_node_edge_distance(_node_a, _node_b) {
    // Returns the shortest distance between the edges of two nodes (AABB to AABB)
    // Returns 0 if they overlap
    
    var _ax1 = _node_a.x;
    var _ay1 = _node_a.y;
    var _ax2 = _node_a.x + _node_a.width;
    var _ay2 = _node_a.y + _node_a.height;
    
    var _bx1 = _node_b.x;
    var _by1 = _node_b.y;
    var _bx2 = _node_b.x + _node_b.width;
    var _by2 = _node_b.y + _node_b.height;
    
    // Gap on each axis (negative means overlap on that axis)
    var _gap_x = max(0, max(_ax1 - _bx2, _bx1 - _ax2));
    var _gap_y = max(0, max(_ay1 - _by2, _by1 - _ay2));
    
    // True edge-to-edge distance is the hypotenuse of the axis gaps
    return point_distance(0, 0, _gap_x, _gap_y);
}