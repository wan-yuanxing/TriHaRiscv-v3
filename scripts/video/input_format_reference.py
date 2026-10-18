"""Ordering/layout references only; quantization belongs to the model owner."""


def _geometry(width, active_height, storage_height):
    if (any(type(v) is not int or not 1 <= v <= 2048
            for v in (width, active_height, storage_height))
            or storage_height < active_height):
        raise ValueError('Invalid tensor geometry')


def pad_bgr(rgb: bytes, width=160, active_height=120, storage_height=128) -> bytes:
    """Reverse RGB channel order, then append bottom raw-zero rows."""
    _geometry(width, active_height, storage_height)
    if not isinstance(rgb, bytes) or len(rgb) != width*active_height*3:
        raise ValueError('Expected one complete RGB888 active image')
    result = b''.join(rgb[i:i+3][::-1] for i in range(0, len(rgb), 3))
    return result+bytes(width*(storage_height-active_height)*3)


def pack_c8(quantized_bgr: bytes, width, active_height, storage_height, zero_point) -> bytes:
    """Expand external quantized BGR bytes to pixel-major C8; never quantize."""
    _geometry(width, active_height, storage_height)
    if type(zero_point) is not int or not 0 <= zero_point <= 255:
        raise ValueError('An explicit encoded quantized zero is required')
    if not isinstance(quantized_bgr, bytes) or len(quantized_bgr) != width*storage_height*3:
        raise ValueError('Expected a complete already quantized BGR image')
    if quantized_bgr[width*active_height*3:] != bytes((zero_point,))*width*(storage_height-active_height)*3:
        raise ValueError('Padded rows must encode quantized zero')
    return b''.join(quantized_bgr[i:i+3]+bytes((zero_point,))*5
                    for i in range(0, len(quantized_bgr), 3))
