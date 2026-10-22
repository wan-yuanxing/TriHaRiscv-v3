"""A private-DDR payload must fit, start at the intended entry and copy exactly."""
import struct
import unittest
import ddr_coremark_firmware


def elf(address=0x80000000, entry=0x80000000, memory_size=8):
    data = bytearray(0x108)
    data[:7] = b'\x7fELF\x01\x01\x01'
    struct.pack_into('<H', data, 18, 243)
    struct.pack_into('<II', data, 24, entry, 52)
    struct.pack_into('<HH', data, 42, 32, 1)
    struct.pack_into('<8I', data, 52, 1, 0x100, address, address, 8, memory_size, 5, 4)
    data[0x100:] = b'\x13\x00\x00\x00\x67\x80\x00\x00'
    return bytes(data)


class PayloadTests(unittest.TestCase):
    def test_exact_loadable_bytes(self):
        self.assertEqual(ddr_coremark_firmware.payload_image(elf()), elf()[0x100:])

    def test_entry_and_private_ddr_bounds(self):
        for data in (elf(entry=0x10000), elf(address=0x82000000), elf(memory_size=131073)):
            with self.subTest(data=data[24:28]), self.assertRaises(ValueError):
                ddr_coremark_firmware.payload_image(data)

    def test_shared_payload_is_explicit_and_bounded(self):
        data = elf(address=0x82000000, entry=0x82000000)
        self.assertEqual(ddr_coremark_firmware.payload_image(data, base=0x82000000), data[0x100:])
        with self.assertRaises(ValueError):
            ddr_coremark_firmware.payload_image(data, base=0x83000000)


if __name__ == '__main__':
    unittest.main()
