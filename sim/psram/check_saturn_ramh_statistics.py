import importlib.util
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from generate_saturn_ramh_statistics import build, FIELDS, HEADER, MAGIC, STATS_BASE


def check(words=262144, seed=0xA55A8041, scan='uncached', operation='both', faults=None, read_gap=0, write_gap=0, increment=0x01010101):
    faults = faults or {}
    program, rom, _ = build(words, seed, scan, operation, read_gap, write_gap, increment)
    reference = [((seed + i * increment) & 0xFFFFFFFF) for i in range(words)]
    memory = reference.copy() if operation == 'read' else [0] * words
    vram = {}
    regs = [0] * 16
    pc = 0x100
    t = False
    reads = writes = 0
    visited = []
    ccr = 0

    def read(address):
        nonlocal reads
        if 0x26000000 <= address < 0x26000000 + words * 4 or 0x06000000 <= address < 0x06000000 + words * 4:
            index = (address & 0x0FFFFFFF) - 0x06000000
            assert index % 4 == 0
            index //= 4
            assert bool(ccr & 1) == (scan == 'cached')
            reads += 1
            visited.append(index)
            return memory[index] ^ faults.get(index, 0)
        if STATS_BASE <= address < STATS_BASE + len(FIELDS) * 4:
            return int.from_bytes(bytes(vram[address + i] for i in range(4)), 'big')
        assert address + 4 <= len(rom), hex(address)
        return int.from_bytes(rom[address:address + 4], 'big')

    def write(address, value, width):
        nonlocal writes, ccr
        if 0x26000000 <= address < 0x26000000 + words * 4:
            assert width == 4 and ccr == 0
            memory[(address - 0x26000000) // 4] = value
            writes += 1
        elif 0x25E00000 <= address < 0x25E02000:
            for i, byte in enumerate((value & ((1 << (8 * width)) - 1)).to_bytes(width, 'big')):
                vram[address + i] = byte
        elif address == 0xFFFFFE92:
            assert width == 1
            ccr = value & 255
        else:
            assert address in (0x25F80000, 0x25F800AC, 0x25F800AE) and width == 2

    def signed(value, bits):
        return value - (1 << bits) if value & (1 << (bits - 1)) else value

    for steps in range(40000000+4*words*(read_gap+write_gap)):
        if pc == program.labels['report_halt']:
            break
        assert pc != program.labels['fault'], 'Program took exception path'
        instruction = int.from_bytes(rom[pc:pc + 2], 'big')
        n = instruction >> 8 & 15
        m = instruction >> 4 & 15
        following = pc + 2
        key = instruction & 0xF00F
        if instruction >> 12 == 13:
            regs[n] = read(((pc + 4) & ~3) + 4 * (instruction & 255))
        elif instruction >> 12 == 14:
            regs[n] = signed(instruction & 255, 8) & 0xFFFFFFFF
        elif key in (0x2000, 0x2001, 0x2002):
            write(regs[n], regs[m], 1 << (instruction & 3))
        elif key in (0x6002, 0x6006):
            regs[n] = read(regs[m])
            if key == 0x6006:
                regs[m] = (regs[m] + 4) & 0xFFFFFFFF
        elif key == 0x6003:
            regs[n] = regs[m]
        elif key == 0x2008:
            t = (regs[n] & regs[m]) == 0
        elif key == 0x2009:
            regs[n] &= regs[m]
        elif key == 0x200A:
            regs[n] ^= regs[m]
        elif key == 0x200B:
            regs[n] |= regs[m]
        elif instruction & 0xF0FF == 0x4000:
            t = bool(regs[n] & 0x80000000)
            regs[n] = (regs[n] << 1) & 0xFFFFFFFF
        elif instruction & 0xF0FF == 0x4009:
            regs[n] >>= 2
        elif instruction >> 8 == 0xC9:
            regs[0] &= instruction & 255
        elif instruction >> 12 == 7:
            regs[n] = (regs[n] + signed(instruction & 255, 8)) & 0xFFFFFFFF
        elif key == 0x300C:
            regs[n] = (regs[n] + regs[m]) & 0xFFFFFFFF
        elif key == 0x3000:
            t = regs[n] == regs[m]
        elif instruction & 0xF0FF == 0x4010:
            regs[n] = (regs[n] - 1) & 0xFFFFFFFF
            t = regs[n] == 0
        elif instruction >> 8 in (0x89, 0x8B):
            if t == (instruction >> 8 == 0x89):
                following = pc + 4 + 2 * signed(instruction & 255, 8)
        elif instruction >> 12 == 10:
            assert int.from_bytes(rom[pc + 2:pc + 4], 'big') == 9
            following = pc + 4 + 2 * signed(instruction & 0xFFF, 12)
        elif instruction != 9:
            raise AssertionError(f'Unsupported opcode {instruction:04X} at {pc:X}')
        pc = following
    else:
        raise AssertionError('Statistics program did not complete')
    assert reads == words and visited == list(range(words))
    assert writes == (words if operation == 'both' else 0)
    assert memory == reference and ccr == 0
    expected = [MAGIC, 1, 0x501 if scan == 'uncached' else 0x502, seed, words, 0,
                0, 0, 0, 0, 0, 0, 0, *([0] * 8)]
    base = 0x26000000 if scan == 'uncached' else 0x06000000
    for index, mask in sorted(faults.items()):
        assert 0 <= index < words and 0 < mask <= 0xFFFFFFFF
        value = reference[index] ^ mask
        if expected[5] == 0:
            expected[6], expected[8], expected[9] = base + index * 4, reference[index], value
        expected[5] += 1
        expected[7] = base + index * 4
        expected[10] |= mask
        expected[11] |= mask & value
        expected[12] |= mask & reference[index]
        for bit in range(8):
            if mask & (0x01010101 << bit):
                expected[13 + bit] += 1
    checksum = 0
    for value in expected:
        checksum ^= value
    expected.append(checksum)
    reported = [int.from_bytes(bytes(vram[STATS_BASE + i * 4 + j] for j in range(4)), 'big') for i in range(len(FIELDS))]
    assert reported == expected, (reported, expected)
    colors = [int.from_bytes(bytes(vram[0x25E00000 + i * 2 + j] for j in range(2)), 'big') for i in range(4 + len(FIELDS) * 8)]
    assert colors[:4] == list(HEADER)
    barcode = [sum(colors[4 + i * 8 + j] << (j * 4) for j in range(8)) for i in range(len(FIELDS))]
    assert barcode == reported, (barcode, reported)
    return {'result': 'PASS', 'words': words, 'error_words': expected[5],
            'dq_error_words': expected[13:21], 'instructions': steps,
            'reads32': reads, 'writes32': writes, 'scan': scan, 'operation': operation}


if __name__ == '__main__':
    for seed in (0xA55A8041, 0x5AA57FBE, 0xFFFFFFFF, 0):
        print('Full1MiB clean:', check(seed=seed))
    print('Full1MiB sparse mixed DQ faults:', check(faults={i: (0x80 if i % 2 else 0x80808080) | (1 if i % 3 == 0 else 0) for i in range(0, 262144, 4093)}))
    print('First/last address and multiple byte lanes:', check(words=128, faults={0: 0x80808080, 31: 0x00800001, 127: 0x01010101}))
    print('All words fail and both directions:', check(words=128, faults={i: 0xFFFFFFFF for i in range(128)}))
    print('Read only preserves writes:', check(operation='read', faults={0: 0x80, 262143: 0x80000000}))
    print('Cached complete:', check(seed=0, scan='cached'))
    print('Cached failure continues:', check(words=128, seed=0, scan='cached', faults={124: 0x80000000, 127: 0x01}))
    for read_gap, write_gap in ((4,0),(16,0),(64,0),(0,16),(16,16)):
        print('Gap instructions preserve scan:',check(words=128,read_gap=read_gap,write_gap=write_gap,faults={0:0x01,127:0x80808080}))
    print('Full1MiB read-gap complete:',check(seed=0,read_gap=4))
    print('Full1MiB original cached constant pattern:',check(seed=0x7C7C7C7C,increment=0,scan='cached',faults={124:0x80000000,262143:0x80808080}))
    import hashlib
    assert hashlib.sha256(build()[1]).hexdigest()=='30660476aba67e2ae0b4ace8c8c1fde15989a739fbece4eb8fc879d4ad28590e'
    print('Default statistics ROM unchanged')
    print('Generated SH-2 program semantics only; cached returns are abstracted, not SH-2 cache RTL or board timing.')
