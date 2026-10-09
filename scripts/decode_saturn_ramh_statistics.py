import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

from generate_saturn_ramh_statistics import FIELDS, MAGIC

HEADER_RGB = ((248, 248, 0), (0, 248, 0), (248, 0, 248), (0, 248, 248))


def decode(path):
    with Image.open(path) as original:
        image = original.convert('RGB')
    assert image.size in ((320, 224), (320, 240)), 'Unscaled core screenshot required'
    colors = []
    for y in range(4 + len(FIELDS) * 8):
        row = {image.getpixel((x, y)) for x in range(320)}
        assert len(row) == 1, f'Nonuniform statistics row {y}'
        colors.append(row.pop())
    assert tuple(colors[:4]) == HEADER_RGB, 'Missing completed statistics header'
    nibbles = []
    for red, green, blue in colors[4:]:
        assert green == blue == 0 and 0 <= red <= 120 and red % 8 == 0
        nibbles.append(red // 8)
    values = [sum(nibbles[i * 8 + j] << (j * 4) for j in range(8)) for i in range(len(FIELDS))]
    report = dict(zip(FIELDS, values))
    checksum = 0
    for value in values[:-1]:
        checksum ^= value
    assert checksum == report['checksum'], 'Statistics checksum mismatch'
    assert report['magic'] == MAGIC and report['version'] == 1
    assert report['stage'] in (0x501, 0x502)
    assert 1 <= report['words'] <= 262144
    assert 0 <= report['error_words'] <= report['words']
    counts = [report[f'dq{bit}_error_words'] for bit in range(8)]
    assert all(0 <= count <= report['error_words'] for count in counts)
    assert report['error_words'] <= sum(counts) <= 8 * report['error_words']
    assert report['rising_or'] | report['falling_or'] == report['xor_or']
    for bit, count in enumerate(counts):
        assert bool(count) == bool(report['xor_or'] & (0x01010101 << bit))
    if report['error_words']:
        base = 0x26000000 if report['stage'] == 0x501 else 0x06000000
        assert base <= report['first_address'] <= report['last_address'] < base + report['words'] * 4
        assert report['first_address'] % 4 == report['last_address'] % 4 == 0
        assert report['first_actual'] != report['first_expected']
        assert (report['first_expected'] ^ report['first_actual']) & ~report['xor_or'] == 0
    else:
        assert not any(values[5:21])
    report.update(result='STATISTICS_COMPLETE_WITH_ERRORS' if report['error_words'] else 'STATISTICS_COMPLETE_NO_ERRORS',
                  dq_error_words=counts,
                  word_error_fraction=report['error_words'] / report['words'],
                  scan='uncached' if report['stage'] == 0x501 else 'cached',
                  image_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                  limitation='Single-pattern diagnostic with changed access cadence; not default-ROM, partial-write, game or PVT acceptance')
    return report


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('image', type=Path)
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    text = json.dumps(decode(a.image), indent=2) + '\n'
    if a.output:
        a.output.write_text(text, encoding='utf-8')
    print(text, end='')
