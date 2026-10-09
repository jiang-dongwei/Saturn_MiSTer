import argparse
import hashlib
import json
from pathlib import Path

from generate_saturn_ramh_testrom import Program

STATS_BASE = 0x25E01000
MAGIC = 0x53544154
HEADER = (0x03FF, 0x03E0, 0x7C1F, 0x7FE0)
FIELDS = ('magic', 'version', 'stage', 'seed', 'words', 'error_words',
          'first_address', 'last_address', 'first_expected', 'first_actual',
          'xor_or', 'rising_or', 'falling_or',
          *(f'dq{bit}_error_words' for bit in range(8)), 'checksum')


def build(ram_words=262144, seed=0xA55A8041, scan='uncached', operation='both'):
    assert 1 <= ram_words <= 262144
    assert 0 <= seed <= 0xFFFFFFFF
    assert scan in ('uncached', 'cached') and operation in ('both', 'read')
    p = Program()

    def store(index, register):
        p.literal(10, STATS_BASE + index * 4)
        p.emit(0x2A02 | register << 4)

    def constant(index, value):
        p.literal(7, value)
        store(index, 7)

    def accumulate(index, register):
        p.literal(10, STATS_BASE + index * 4)
        p.emit(0x68A2)
        p.emit(0x280B | register << 4)
        p.emit(0x2A82)

    p.literal(1, 0xFFFFFE92)
    p.emit(0xE000)
    p.emit(0x2100)
    p.literal(10, 0x25E00000)
    p.literal(0, 0x7C00)
    p.emit(0x2A01)
    p.literal(1, 0x25F80000)
    p.literal(0, 0x8000)
    p.emit(0x2101)
    p.literal(10, STATS_BASE)
    p.emit(0xE000)
    p.emit(0xE200 | len(FIELDS))
    p.label('clear_stats')
    p.emit(0x2A02)
    p.emit(0x7A04)
    p.emit(0x4210)
    p.branch('clear_stats', 'false')
    constant(1, 1)
    constant(2, 0x501 if scan == 'uncached' else 0x502)
    constant(3, seed)
    constant(4, ram_words)
    p.literal(3, 0x01010101)
    if operation == 'both':
        p.literal(1, 0x26000000)
        p.literal(2, ram_words)
        p.literal(0, seed)
        p.label('write_pattern')
        for word in (0x2102, 0x7104, 0x303C, 0x4210):
            p.emit(word)
        p.branch('write_pattern', 'false')
    if scan == 'cached':
        p.literal(1, 0xFFFFFE92)
        p.emit(0xE011)
        p.emit(0x2100)
    p.literal(1, 0x26000000 if scan == 'uncached' else 0x06000000)
    p.literal(2, ram_words)
    p.literal(0, seed)
    p.label('scan_word')
    p.emit(0x6416)
    p.emit(0x3400)
    p.branch('next_word', 'true')
    p.emit(0x6543)
    p.emit(0x250A)
    p.emit(0x6613)
    p.emit(0x76FC)
    p.literal(10, STATS_BASE + 5 * 4)
    p.emit(0x68A2)
    p.emit(0x2888)
    p.emit(0x7801)
    p.emit(0x2A82)
    p.branch('not_first', 'false')
    store(6, 6)
    store(8, 0)
    store(9, 4)
    p.label('not_first')
    store(7, 6)
    accumulate(10, 5)
    p.emit(0x6743)
    p.emit(0x2759)
    accumulate(11, 7)
    p.emit(0x6703)
    p.emit(0x2759)
    accumulate(12, 7)
    p.literal(10, STATS_BASE + 13 * 4)
    p.literal(9, 0x01010101)
    p.emit(0xEB08)
    p.label('count_dq')
    p.emit(0x6753)
    p.emit(0x2799)
    p.emit(0x2778)
    p.branch('dq_clean', 'true')
    p.emit(0x68A2)
    p.emit(0x7801)
    p.emit(0x2A82)
    p.label('dq_clean')
    p.emit(0x7A04)
    p.emit(0x4900)
    p.emit(0x4B10)
    p.branch('count_dq', 'false')
    p.label('next_word')
    p.emit(0x303C)
    p.emit(0x4210)
    p.branch('scan_word', 'false')
    constant(0, MAGIC)
    p.literal(10, STATS_BASE)
    p.emit(0xE700)
    p.emit(0xE200 | (len(FIELDS) - 1))
    p.label('checksum')
    p.emit(0x68A6)
    p.emit(0x278A)
    p.emit(0x4210)
    p.branch('checksum', 'false')
    p.emit(0x2A72)
    p.literal(1, 0xFFFFFE92)
    p.emit(0xE000)
    p.emit(0x2100)
    p.literal(1, 0x25F800AC)
    p.literal(0, 0x8000)
    p.emit(0x2101)
    p.literal(1, 0x25F800AE)
    p.emit(0xE000)
    p.emit(0x2101)
    p.literal(10, 0x25E00000)
    for color in HEADER:
        p.literal(0, color)
        p.emit(0x2A01)
        p.emit(0x7A02)
    p.literal(11, STATS_BASE)
    p.emit(0xEC00 | len(FIELDS))
    p.label('report_field')
    p.emit(0x65B6)
    p.emit(0xE608)
    p.label('report_nibble')
    for word in (0x6053, 0xC90F, 0x2A01, 0x7A02, 0x4509, 0x4509, 0x4610):
        p.emit(word)
    p.branch('report_nibble', 'false')
    p.emit(0x4C10)
    p.branch('report_field', 'false')
    p.label('report_halt')
    p.branch('report_halt')
    p.label('fault')
    p.literal(10, 0x25E00000)
    p.literal(0, 0x7C1F)
    p.emit(0x2A01)
    p.branch('fault')
    return p, *p.finish()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--ram-words', type=int, default=262144)
    parser.add_argument('--seed', type=lambda value: int(value, 0), default=0xA55A8041)
    parser.add_argument('--scan', choices=('uncached', 'cached'), default='uncached')
    parser.add_argument('--operation', choices=('both', 'read'), default='both')
    args = parser.parse_args()
    program, rom, pool = build(args.ram_words, args.seed, args.scan, args.operation)
    args.output.write_bytes(rom)
    args.output.with_suffix('.json').write_text(json.dumps({
        'purpose': 'Continue after data mismatches and count all scanned words',
        'sha256': hashlib.sha256(rom).hexdigest(), 'bytes': len(rom),
        'ram_words': args.ram_words, 'seed': args.seed, 'scan': args.scan,
        'operation': args.operation, 'stats_base': hex(STATS_BASE),
        'fields': FIELDS, 'pool_start': pool,
        'limitations': 'Single pattern; no partial-write coverage; error accounting changes access cadence; never substitutes for the default full ROM',
    }, indent=2) + '\n', encoding='utf-8')
    print(args.output, hashlib.sha256(rom).hexdigest())
