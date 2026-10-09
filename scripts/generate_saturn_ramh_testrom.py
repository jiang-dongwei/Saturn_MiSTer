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


def build(video_only=False, cache_read=True, failure_bars=False, ram_words=262144, failure_rereads=0, failure_cache_read=False, first_seed=0xA55A8041, operation='both', target='ramh'):
    assert target in ('ramh', 'vdp1fb')
    framebuffer = target == 'vdp1fb'
    assert not framebuffer or (not video_only and not cache_read and operation == 'both' and not failure_cache_read and ram_words <= 65536)
    ram_base = 0x25C80000 if framebuffer else 0x26000000
    assert operation in ('both', 'write', 'read')
    assert operation == 'both' or (not video_only and not cache_read)
    assert operation != 'write' or not (failure_rereads or failure_cache_read)
    assert 1 <= ram_words <= 262144
    assert 0 <= failure_rereads <= 2
    assert not failure_rereads or (failure_bars and not video_only)
    assert not failure_cache_read or (failure_bars and not video_only)
    assert 0 <= first_seed <= 0xFFFFFFFF
    assert not video_only or first_seed == 0xA55A8041
    p = Program()
    dynamic_failure_address = ram_words != 1 and (failure_rereads or failure_cache_read)
    p.literal(1, 0xFFFFFE92)
    p.emit(0xE000)
    p.emit(0x2100)  # MOV.B R0,@R1: disable SH-2 cache
    p.literal(10, 0x25E00000)
    p.literal(0, 0x7C00)
    p.emit(0x2A01)  # MOV.W R0,@R10: blue background
    p.literal(1, 0x25F80000)
    p.literal(0, 0x8000)
    p.emit(0x2101)  # enable VDP2 display
    def flip_buffer(tag):
        p.literal(1, 0x25D00002)
        p.emit(0xE003)
        p.emit(0x2101)
        p.literal(13, 2000000)
        p.label(f'frame_wait_{tag}')
        p.emit(0x4D10)
        p.branch(f'frame_wait_{tag}', 'false')

    if framebuffer:
        for address, value in ((0x25D00000, 0), (0x25D00004, 0), (0x25D00008, 0), (0x25D0000A, 0), (0x25D00002, 2)):
            p.literal(1, address)
            p.emit(0xE000 | value)
            p.emit(0x2101)
        p.emit(0xE702)
        p.literal(6, 0x11223344)
        p.literal(14, 0x100)
        p.label('framebuffer_bank')
    if not video_only:
        p.literal(3, 0x01010101)
        seeds = (first_seed, 0x5AA57FBE, 0xFFFFFFFF, 0) if operation == 'both' else (first_seed,)
        for number, seed in enumerate(seeds):
            if operation != 'read':
                p.literal(1, ram_base)
                p.literal(2, ram_words)
                p.literal(0, seed)
                p.label(f'write_{number}')
                for word in (0x2102, 0x7104, 0x303C, 0x4210):
                    p.emit(word)
                p.branch(f'write_{number}', 'false')
            if operation == 'write':
                continue
            p.literal(1, ram_base)
            p.literal(2, ram_words)
            p.literal(0, seed)
            if failure_bars:
                if framebuffer:
                    p.emit(0x6CE3)
                    p.emit(0x7C00 | number)
                else:
                    p.literal(12, 0x100 + number)
            p.label(f'read_{number}')
            if dynamic_failure_address:
                p.emit(0x6513)  # preserve the address before post-increment
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
            if dynamic_failure_address:
                p.emit(0x6513)
            p.emit(0x6416)
            p.compare()
            p.emit(0x303C)
            p.emit(0x4210)
            p.branch('cached_read', 'false')
            p.literal(1, 0xFFFFFE92)
            p.emit(0xE000)
            p.emit(0x2100)
        masks = ([(lane, 1, 0xA5) for lane in range(4)] + [(lane, 2, 0x5AA5) for lane in (0, 2)]) if operation == 'both' else []
        for lane, width, value in masks:
            if failure_bars:
                p.literal(12, 0x300 + width * 16 + lane)
                if framebuffer:
                    p.emit(0x6DE3)
                    p.literal(8, 0xFFFFFF00)
                    p.emit(0x3D8C)
                    p.emit(0x3CDC)
            p.literal(1, ram_base)
            p.literal(0, 0x11223344)
            p.emit(0x2102)
            p.literal(1, ram_base + lane)
            p.literal(0, value)
            p.emit(0x2100 if width == 1 else 0x2101)
            p.literal(1, ram_base)
            if dynamic_failure_address:
                p.emit(0x6513)
            p.emit(0x6412)
            expected = bytearray.fromhex('11223344')
            expected[lane:lane + width] = value.to_bytes(width, 'big')
            p.literal(0, int.from_bytes(expected, 'big'))
            p.compare()
        if framebuffer:
            p.literal(12, 0x340)
            p.literal(1, ram_base)
            p.emit(0x2162)
            p.emit(0x6412)
            p.emit(0x6063)
            if dynamic_failure_address:
                p.emit(0x6513)
            p.compare()
            p.emit(0x4710)
            p.branch('framebuffer_banks_done', 'false')
            p.branch('framebuffer_markers')
            p.label('framebuffer_banks_done')
            flip_buffer(0)
            p.literal(6, 0x55667788)
            p.literal(14, 0x200)
            p.branch('framebuffer_bank')
            p.label('framebuffer_markers')
            for tag, marker in ((1, 0x11223344), (2, 0x55667788)):
                flip_buffer(tag)
                p.literal(12, 0x34F + tag)
                p.literal(1, ram_base)
                p.emit(0xE200)
                if dynamic_failure_address:
                    p.emit(0x6513)
                p.emit(0x6412)
                p.literal(0, marker)
                p.compare()
        p.literal(0, 0x03E0)
        p.emit(0x2A01)
    p.label('pass')
    p.branch('pass')
    p.label('fail')
    if failure_bars:
        for instruction in (0x6603, 0x6743, 0x6813, 0x6923, 0x6BC3):
            p.emit(instruction)
        if cache_read and (failure_rereads or failure_cache_read):
            p.literal(1, 0xFFFFFE92)
            p.emit(0xE000)
            p.emit(0x2100)
        if failure_cache_read:
            if dynamic_failure_address:
                p.emit(0x6153)
            else:
                p.literal(1, ram_base)
            p.emit(0x6212)
        for index in range(failure_rereads):
            if dynamic_failure_address:
                p.emit(0x6153)
                p.emit(0xE304)
                p.emit(0x213A)  # XOR R3,R1: choose a different valid RAMH word
            else:
                p.literal(1, ram_base + 4)
            p.emit(0x6412)
            if dynamic_failure_address:
                p.emit(0x6153)
            else:
                p.literal(1, ram_base)
            p.emit(0x6012 | (13 + index) << 8)
        p.literal(1, 0x25F800AC)
        p.literal(0, 0x8000)
        p.emit(0x2101)
        p.literal(1, 0x25F800AE)
        p.emit(0xE000)
        p.emit(0x2101)
        p.literal(10, 0x25E00000)
        for color in (0x7C1F, 0x03E0, 0x001F, 0x7800 if failure_cache_read else 0x7C00):
            p.literal(0, color)
            p.emit(0x2A01)
            p.emit(0x7A02)
        for register in (6, 7, 8, 9, 11) + ((2,) if failure_cache_read else ()) + tuple(range(13, 13 + failure_rereads)):
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
    parser.add_argument('--ram-words', type=int)
    parser.add_argument('--target', choices=('ramh', 'vdp1fb'), default='ramh')
    parser.add_argument('--failure-rereads', type=int, default=0, choices=(0, 1, 2))
    parser.add_argument('--failure-cache-read', action='store_true')
    parser.add_argument('--first-seed', type=lambda value: int(value, 0), default=0xA55A8041)
    parser.add_argument('--operation', choices=('both', 'write', 'read'), default='both')
    args = parser.parse_args()
    if args.ram_words is None:
        args.ram_words = 65536 if args.target == 'vdp1fb' else 262144
    program, image, pool_start = build(args.video_only, not args.uncached_only, args.failure_bars, args.ram_words, args.failure_rereads, args.failure_cache_read, args.first_seed, args.operation, args.target)
    args.output.write_bytes(image)
    metadata = {'bytes': len(image), 'sha256': hashlib.sha256(image).hexdigest(),
                'labels': program.labels, 'literal_pool': pool_start,
                'uncached_ram_start': '0x26000000', 'ram_bytes': 0 if args.video_only else 4 * args.ram_words,
                'operation': args.operation,
                'passes': 0 if args.video_only else (4 if args.operation == 'both' else 1),
                'first_seed': f'{args.first_seed:08X}' if not args.video_only else None,
                'partial_write_cases': 6 if not args.video_only and args.operation == 'both' else 0,
                'cached_read_words': 0 if args.video_only or args.uncached_only else args.ram_words,
                'colors': {'blue': 'startup/video-only', 'green': 'complete', 'red': 'compare failure', 'magenta': 'exception'},
                'verified_on_hardware': False}
    if args.operation != 'both':
        metadata['colors']['green'] = 'writes issued; data not verified' if args.operation == 'write' else 'existing data verified; no RAMH writes'
    if args.failure_bars:
        metadata['colors']['red'] = 'barcode header; comparison failure uses scanline barcode'
        metadata['failure_bars'] = {'header_rgb555': ['7c1f', '03e0', '001f', '7800' if args.failure_cache_read else '7c00'],
            'values': ['expected', 'actual', 'address_register', 'remaining_words', 'stage'] + (['adapter_cache_read'] if args.failure_cache_read else []) + [f'reread_{i + 1}' for i in range(args.failure_rereads)],
            'encoding': '8 scanlines per value, low nibble first, red-channel RGB555 bits[3:0]',
            'stages': '0x100..103 uncached passes; 0x200 cached pass; 0x310..313 byte writes; 0x320/322 half-word writes',
            'address_note': 'Subtract 4 from address_register for stage 0x100..103 and 0x200; partial reads do not post-increment.'}
        if args.failure_rereads:
            metadata['failure_bars']['rereads'] = 'Read failed-address XOR 4 to replace the adapter cache, then reread the failed address without writes; repeated as requested.'
        if args.failure_cache_read:
            metadata['failure_bars']['adapter_cache_read'] = 'Immediately reread the failed address before any other RAMH access; SH-2 cache is disabled, adapter one-word cache stays valid.'
        if not args.uncached_only and (args.failure_rereads or args.failure_cache_read):
            metadata['failure_bars']['cache_failure_probe'] = 'Preserve first failure, disable SH-2 cache, then probe the failed word without RAMH writes. Cached address and stage remain in the original failure bars.'
    if args.target == 'vdp1fb':
        metadata.update(target='vdp1fb', uncached_ram_start='0x25C80000', framebuffer_banks=2, passes=8, partial_write_cases=12, flip_requests=3)
        metadata['framebuffer_scope'] = 'CPU window in both selected buffers; distinct marker retention verifies switching. Frame timing requires hardware verification.'
        if args.failure_bars:
            metadata['failure_bars']['stages'] = '0x100..103 / 0x200..203 bank passes; 0x310..313,320,322 / 0x410..413,420,422 partial writes; 0x340 marker write; 0x350/351 retained markers'
            metadata['failure_bars']['address_note'] = 'Subtract 4 only for bank pass stages 0x100..103 and 0x200..203.'
    args.output.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(metadata))
