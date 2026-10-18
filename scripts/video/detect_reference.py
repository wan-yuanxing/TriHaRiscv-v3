"""v0.6 geometry-only RGB888 5x5 mean reference; no model quantization."""


def downscale_rgb(data: bytes, width: int = 800, height: int = 600) -> bytes:
    """Return RGB888 rounded block means in raster order, without padding."""
    if any(type(n) is not int or not 5 <= n <= 2045 or n % 5 for n in (width, height)):
        raise ValueError('Dimensions must be multiples of five in 5..2045')
    if not isinstance(data, bytes) or len(data) != width * height * 3:
        raise ValueError('Expected exactly width*height*3 RGB888 bytes')
    output = bytearray()
    for top in range(0, height, 5):
        for left in range(0, width, 5):
            for channel in range(3):
                total = sum(data[((top + dy) * width + left + dx) * 3 + channel]
                            for dy in range(5) for dx in range(5))
                output.append((total + 12) // 25)
    return bytes(output)
