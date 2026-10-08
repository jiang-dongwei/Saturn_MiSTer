import argparse
import hashlib
import json
import struct
from pathlib import Path


class Program:
    def __init__(self):
        self.words = []
        self.labels = {}
        self.fixups = []
        self.literals = {}

    @property
    def pc(self):
        return 0x100 + 2 * len(self.words)

    def emit(self, word):
        self.words.append(word)

    def label(self, name):
        assert name not in self.labels
        self.labels[name] = self.pc

    def literal(self, register, value):
        self.literals.setdefault(value, None)
        self.fixups.append((len(self.words), 'literal', register, value))
        self.emit(0)

    def branch(self, name, condition=None):
        self.fixups.append((len(self.words), 'branch', condition, name))
        self.emit(0)
        if condition is None:
            self.emit(0x0009)

    def compare(self):
        self.emit(0x3400)  # CMP/EQ R0,R4
        name = f'valid_{len(self.words)}'
        self.branch(name, 'true')
        self.branch('fail')
        self.label(name)

    def finish(self):
        if self.pc % 4:
            self.emit(0x0009)
        pool_start = self.pc
        for value in self.literals:
            self.literals[value] = self.pc
            self.emit(value >> 16)
            self.emit(value & 0xFFFF)
        for index, kind, argument, target in self.fixups:
            pc = 0x100 + index * 2
            if kind == 'literal':
                offset = self.literals[target] - ((pc + 4) & ~3)
                assert offset % 4 == 0 and 0 <= offset // 4 <= 255
                self.words[index] = 0xD000 | argument << 8 | offset // 4
            else:
                offset = self.labels[target] - (pc + 4)
                assert offset % 2 == 0
                displacement = offset // 2
                if argument is None:
                    assert -2048 <= displacement <= 2047
                    self.words[index] = 0xA000 | (displacement & 0xFFF)
                else:
                    assert -128 <= displacement <= 127
                    self.words[index] = (0x8900 if argument == 'true' else 0x8B00) | (displacement & 0xFF)
        rom = bytearray(b'\xff' * 0x80000)
        for vector in range(0, 0x100, 4):
            struct.pack_into('>I', rom, vector, self.labels['fault'])
        struct.pack_into('>IIII', rom, 0, 0x100, 0x060FFFF0, 0x100, 0x060FFFF0)
        for index, word in enumerate(self.words):
            struct.pack_into('>H', rom, 0x100 + index * 2, word)
        return bytes(rom), pool_start


def build(video_only=False, cache_read=True, failure_bars=False, ram_words=262144):
    assert 1 <= ram_words <= 262144
    p = Program()
    p.literal(1, 0xFFFFFE92)
    p.emit(0xE000)
    p.emit(0x2100)  # MOV.B R0,@R1: disable SH-2 cache
    p.literal(10, 0x25E00000)
    p.literal(0, 0x7C00)
    p.emit(0x2A01)  # MOV.W R0,@R10: blue background
    p.literal(1, 0x25F80000)
    p.literal(0, 0x8000)
    p.emit(0x2101)  # enable VDP2 display
    if not video_only:
        p.literal(3, 0x01010101)
        for number, seed in enumerate((0xA55A8041, 0x5AA57FBE, 0xFFFFFFFF, 0)):
            p.literal(1, 0x26000000)
            p.literal(2, ram_words)
            p.literal(0, seed)
            p.label(f'write_{number}')
            for word in (0x2102, 0x7104, 0x303C, 0x4210):
                p.emit(word)
            p.branch(f'write_{number}', 'false')
            p.literal(1, 0x26000000)
            p.literal(2, ram_words)
            p.literal(0, seed)
            if failure_bars:
                p.literal(12, 0x100 + number)
            p.label(f'read_{number}')
            p.emit(0x6416)  # MOV.L @R1+,R4
            p.compare()
            p.emit(0x303C)
            p.emit(0x4210)
            p.branch(f'read_{number}', 'false')
        if cache_read:
            p.literal(1, 0xFFFFFE92)
            p.emit(0xE011)
            p.emit(0x2100)  # purge and enable cache
            p.literal(1, 0x06000000)
            p.literal(2, ram_words)
            p.emit(0xE000)
            if failure_bars:
                p.literal(12, 0x200)
            p.label('cached_read')
            p.emit(0x6416)
            p.compare()
            p.emit(0x303C)
            p.emit(0x4210)
            p.branch('cached_read', 'false')
            p.literal(1, 0xFFFFFE92)
            p.emit(0xE000)
            p.emit(0x2100)
        masks = [(lane, 1, 0xA5) for lane in range(4)] + [(lane, 2, 0x5AA5) for lane in (0, 2)]
        for lane, width, value in masks:
            if failure_bars:
                p.literal(12, 0x300 + width * 16 + lane)
            p.literal(1, 0x26000000)
            p.literal(0, 0x11223344)
            p.emit(0x2102)
            p.literal(1, 0x26000000 + lane)
            p.literal(0, value)
            p.emit(0x2100 if width == 1 else 0x2101)
            p.literal(1, 0x26000000)
            p.emit(0x6412)
            expected = bytearray.fromhex('11223344')
            expected[lane:lane + width] = value.to_bytes(width, 'big')
            p.literal(0, int.from_bytes(expected, 'big'))
            p.compare()
        p.literal(0, 0x03E0)
        p.emit(0x2A01)
    p.label('pass')
    p.branch('pass')
    p.label('fail')
    if failure_bars:
        for instruction in (0x6603, 0x6743, 0x6813, 0x6923, 0x6BC3):
            p.emit(instruction)
        p.literal(1, 0x25F800AC)
        p.literal(0, 0x8000)
        p.emit(0x2101)
        p.literal(1, 0x25F800AE)
        p.emit(0xE000)
        p.emit(0x2101)
        p.literal(10, 0x25E00000)
        for color in (0x7C1F, 0x03E0, 0x001F, 0x7C00):
            p.literal(0, color)
            p.emit(0x2A01)
            p.emit(0x7A02)
        for register in (6, 7, 8, 9, 11):
            p.emit(0x6503 | register << 4)
            p.emit(0xE308)
            p.label(f'bar_{register}')
            for instruction in (0x6053, 0xC90F, 0x2A01, 0x7A02, 0x4509, 0x4509, 0x4310):
                p.emit(instruction)
            p.branch(f'bar_{register}', 'false')
        p.label('fail_halt')
        p.branch('fail_halt')
    else:
        p.literal(0, 0x001F)
        p.emit(0x2A01)
        p.branch('fail')
    p.label('fault')
    p.literal(10, 0x25E00000)
    p.literal(0, 0x7C1F)
    p.emit(0x2A01)
    p.branch('fault')
    return p, *p.finish()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--video-only', action='store_true')
    parser.add_argument('--uncached-only', action='store_true')
    parser.add_argument('--failure-bars', action='store_true')
    parser.add_argument('--ram-words', type=int, default=262144)
    args = parser.parse_args()
    program, image, pool_start = build(args.video_only, not args.uncached_only, args.failure_bars, args.ram_words)
    args.output.write_bytes(image)
    metadata = {'bytes': len(image), 'sha256': hashlib.sha256(image).hexdigest(),
                'labels': program.labels, 'literal_pool': pool_start,
                'uncached_ram_start': '0x26000000', 'ram_bytes': 0 if args.video_only else 4 * args.ram_words,
                'passes': 0 if args.video_only else 4,
                'partial_write_cases': 0 if args.video_only else 6,
                'cached_read_words': 0 if args.video_only or args.uncached_only else args.ram_words,
                'colors': {'blue': 'startup/video-only', 'green': 'complete', 'red': 'compare failure', 'magenta': 'exception'},
                'verified_on_hardware': False}
    if args.failure_bars:
        metadata['colors']['red'] = 'barcode header; comparison failure uses scanline barcode'
        metadata['failure_bars'] = {'header_rgb555': ['7c1f', '03e0', '001f', '7c00'],
            'values': ['expected', 'actual', 'address_register', 'remaining_words', 'stage'],
            'encoding': '8 scanlines per value, low nibble first, red-channel RGB555 bits[3:0]',
            'stages': '0x100..103 uncached passes; 0x200 cached pass; 0x310..313 byte writes; 0x320/322 half-word writes',
            'address_note': 'Subtract 4 from address_register for stage 0x100..103 and 0x200; partial reads do not post-increment.'}
    args.output.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(metadata))
