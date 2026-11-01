import struct
import unittest
from face_firmware import memory_images


def elf():
    data=bytearray(88);data[:7]=b'\x7fELF\x01\x01\x01'
    struct.pack_into('<HHIIIIIHHHHHH',data,16,2,243,1,0x10000,52,0,0,52,32,1,0,0,0)
    struct.pack_into('<8I',data,52,1,84,0x10000,0x10000,4,8,5,4)
    data[84:]=b'\x13\x00\x00\x00'
    return data


class FirmwareTests(unittest.TestCase):
    def test_boot_entry_and_zero_bss(self):
        images=memory_images(elf())
        self.assertEqual(images['rom.hex'].splitlines()[0],b'00028067000102b7')
        self.assertEqual(images['sram.hex'].splitlines()[0],b'0000000000000013')
        self.assertEqual(len(images['rom.hex'].splitlines()),1024)
        self.assertEqual(len(images['sram.hex'].splitlines()),4096)
    def test_reject_wrong_arch_entry_and_bounds(self):
        for offset,value in [(18,62),(24,0),(52+8,0x20000),(52+12,0xffff),(52+16,99),(52+20,32769),(52+24,4)]:
            with self.subTest(offset=offset):
                data=elf();struct.pack_into('<H' if offset==18 else '<I',data,offset,value)
                with self.assertRaises(ValueError):memory_images(data)
    def test_reject_truncated_headers(self):
        for n in (0,51,70,87):
            with self.assertRaises(ValueError):memory_images(elf()[:n])
    def test_reject_overlapping_segments(self):
        data=elf();data.extend(bytes(32));struct.pack_into('<H',data,44,2)
        struct.pack_into('<8I',data,84,1,116,0x10000,0x10000,4,4,5,4)
        struct.pack_into('<I',data,56,116)
        with self.assertRaisesRegex(ValueError,'overlapping'):memory_images(data)


if __name__=='__main__':unittest.main()
