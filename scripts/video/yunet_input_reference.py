"""Fixed 800x600 RGB888 -> YuNet v1 UINT8 BGR NCHW reference.

Matches uint8 OpenCV 4.11 INTER_LINEAR at the fixed 5:2 ratio, including
its separate vertical truncations. This is not an INT8 quantizer or RTL.
"""


def preprocess_rgb800x600(rgb: bytes) -> bytes:
    """Return 320x320 B/G/R planes, with 40 zero rows above and below."""
    if not isinstance(rgb, bytes) or len(rgb) != 1440000:
        raise ValueError('Expected one complete 800x600 RGB888 bytes image')
    output = bytearray(307200)
    for y in range(240):
        sy = (10*y+3)//4
        wy = 3 if y % 2 == 0 else 1
        for x in range(320):
            sx = (10*x+3)//4
            wx = 3 if x % 2 == 0 else 1
            source = (sy*800+sx)*3
            destination = (y+40)*320+x
            for channel in range(3):
                index = source+2-channel
                h0 = (4-wx)*rgb[index] + wx*rgb[index+3]
                h1 = (4-wx)*rgb[index+2400] + wx*rgb[index+2403]
                value = ((4-wy)*h0//4 + wy*h1//4 + 2)//4
                output[channel*102400+destination] = value
    return bytes(output)
