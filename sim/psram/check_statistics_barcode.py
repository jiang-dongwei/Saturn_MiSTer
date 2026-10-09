import sys
import tempfile
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from decode_saturn_ramh_statistics import decode


def encode(values, path):
    image = Image.new('RGB', (320, 224))
    colors = [(248, 248, 0), (0, 248, 0), (248, 0, 248), (0, 248, 248)]
    for value in values:
        colors.extend((((value >> (4 * bit)) & 15) * 8, 0, 0) for bit in range(8))
    for y, color in enumerate(colors):
        for x in range(320):
            image.putpixel((x, y), color)
    image.save(path)


def trailer(values):
    checksum = 0
    for value in values:
        checksum ^= value
    return values + [checksum]


def reject(path):
    try:
        decode(path)
    except AssertionError:
        return
    raise AssertionError('Malformed statistics report was accepted')


with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'report.png'
    clean = [0x53544154, 1, 0x501, 0xA55A8041, 262144, *([0] * 16)]
    encode(trailer(clean), path)
    assert decode(path)['result'] == 'STATISTICS_COMPLETE_NO_ERRORS'
    bad = [0x53544154, 1, 0x501, 0xA55A8041, 128, 2, 0x26000000, 0x260001FC,
           0xA55A8041, 0xA5DA8041, 0x00800001, 0x00800000, 1,
           1, 0, 0, 0, 0, 0, 0, 1]
    encode(trailer(bad), path)
    result = decode(path)
    assert result['error_words'] == 2 and result['dq_error_words'] == [1, 0, 0, 0, 0, 0, 0, 1]
    image = Image.open(path).convert('RGB')
    color = image.getpixel((0, 172))
    for x in range(320):
        image.putpixel((x, 172), (color[0] ^ 8, 0, 0))
    image.save(path)
    reject(path)
    inconsistent = bad.copy()
    inconsistent[20] = 0
    encode(trailer(inconsistent), path)
    reject(path)
    Image.new('RGB', (320, 224), (0, 0, 248)).save(path)
    reject(path)
    print('Statistics barcode PASS: clean/error reports, checksum corruption, inconsistent DQ counts and incomplete frames')
