"""Regression tests for rootless physical UEFI removable-media image packaging."""
import importlib.util
from pathlib import Path
import struct
import unittest
import zlib

MODULE = Path(__file__).resolve().parents[1] / "Bootloader" / "uefi" / "make_usb.py"
spec = importlib.util.spec_from_file_location("noqerios_uefi_usb", MODULE)
usb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usb)


class GptImageTests(unittest.TestCase):
    def test_protective_mbr_and_primary_backup_headers(self):
        fat = bytes(1024 * 1024)
        image = usb.create_usb_image(fat)
        total = len(image) // 512
        self.assertEqual(len(image) % 512, 0)
        self.assertEqual(image[510:512], b"\x55\xaa")
        self.assertEqual(image[450], 0xEE)
        for lba, other in ((1, total - 1), (total - 1, 1)):
            head = bytearray(image[lba*512:(lba+1)*512])
            self.assertEqual(head[:8], b"EFI PART")
            self.assertEqual(struct.unpack_from("<Q", head, 24)[0], lba)
            self.assertEqual(struct.unpack_from("<Q", head, 32)[0], other)
            self.assertEqual(struct.unpack_from("<I", head, 12)[0], 92)
            saved_crc = struct.unpack_from("<I", head, 16)[0]
            struct.pack_into("<I", head, 16, 0)
            self.assertEqual(zlib.crc32(head[:92]), saved_crc)
            table_lba = struct.unpack_from("<Q", head, 72)[0]
            entries = image[table_lba*512:table_lba*512+16384]
            self.assertEqual(zlib.crc32(entries), struct.unpack_from("<I", head, 88)[0])
        first_entry = image[2*512:2*512+128]
        self.assertEqual(first_entry[:16], usb.ESP_TYPE.bytes_le)
        self.assertEqual(struct.unpack_from("<Q", first_entry, 32)[0], 2048)
        self.assertEqual(struct.unpack_from("<Q", first_entry, 40)[0], 2048+len(fat)//512-1)
        self.assertEqual(image[2048*512:2048*512+len(fat)], fat)

    def test_invalid_fat_input_is_rejected(self):
        with self.assertRaises(ValueError):
            usb.create_usb_image(bytes(3000))
        with self.assertRaises(ValueError):
            usb.create_usb_image(bytes(512 * 100))


if __name__ == "__main__":
    unittest.main()
