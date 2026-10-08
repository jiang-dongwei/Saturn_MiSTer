import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def decode(path):
    with Image.open(path) as original:
        image = original.convert('RGB')
    assert image.size == (320, 224), 'Expected unscaled 320x224 core screenshot'
    rows = []
    for y in range(44):
        row = {image.getpixel((x, y)) for x in range(image.width)}
        assert len(row) == 1, f'Nonuniform barcode row {y}'
        rows.append(row.pop())
    assert rows[:4] == [(248, 0, 248), (0, 248, 0), (248, 0, 0), (0, 0, 248)], 'Missing barcode header'
    nibbles = []
    for red, green, blue in rows[4:]:
        assert green == blue == 0 and red % 8 == 0 and red <= 120, 'Invalid nibble color'
        nibbles.append(red // 8)
    values = [sum(nibbles[8 * i + j] << (4 * j) for j in range(8)) for i in range(5)]
    expected, actual, address_register, remaining, stage = values
    assert stage in (0x100, 0x101, 0x102, 0x103, 0x200, 0x310, 0x311, 0x312, 0x313, 0x320, 0x322), 'Unknown stage'
    assert actual != expected, 'Barcode does not describe a comparison failure'
    address = address_register - 4 if stage <= 0x200 else address_register
    assert 0x26000000 <= address < 0x26100000 or 0x06000000 <= address < 0x06100000, 'Invalid RAMH address'
    difference = expected ^ actual
    return {
        'result': 'COMPARE_FAIL', 'stage': f'{stage:08X}',
        'address': f'{address:08X}', 'address_register': f'{address_register:08X}',
        'expected': f'{expected:08X}', 'actual': f'{actual:08X}',
        'xor': f'{difference:08X}', 'differing_word_bits': [bit for bit in range(32) if difference & (1 << bit)],
        'remaining_words': remaining,
        'image_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('image', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = json.dumps(decode(args.image), indent=2) + '\n'
    if args.output:
        args.output.write_text(result, encoding='utf-8')
    print(result, end='')
