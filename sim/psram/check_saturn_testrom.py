import importlib.util
import hashlib
from pathlib import Path

spec = importlib.util.spec_from_file_location('testrom', Path(__file__).resolve().parents[2] / 'scripts/generate_saturn_ramh_testrom.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
build = generator.build


def check(video_only=False, inject_error=False, cache_read=True, failure_bars=False, ram_words=262144, failure_rereads=0, failure_cache_read=False, first_seed=0xA55A8041, inject_offset=None, error_read_limit=None, error_stage=None, operation='both', target='ramh', collapse_framebuffer_banks=False, cache_error_only=False):
    program, rom, _ = build(video_only, cache_read, failure_bars, ram_words, failure_rereads, failure_cache_read, first_seed, operation, target)
    framebuffer = target == 'vdp1fb'
    assert not collapse_framebuffer_banks or framebuffer
    ram_base = 0x25C80000 if framebuffer else 0x26000000
    assert not inject_error or operation != 'write'
    assert not cache_error_only or (inject_error and cache_read and error_stage == 0x200)
    error_offset = min(0xC0E4, 4 * (ram_words - 1)) if inject_offset is None else inject_offset
    if collapse_framebuffer_banks:
        error_offset = 0
    assert error_offset % 4 == 0 and 0 <= error_offset < 4 * ram_words
    assert error_read_limit is None or error_read_limit >= 1
    ram = bytearray(1048576)
    banks = [bytearray(262144), bytearray(262144)]
    selected_bank = flips = 0
    expected_pattern = b''.join(((first_seed + i * 0x01010101) & 0xFFFFFFFF).to_bytes(4, 'big') for i in range(ram_words))
    if operation == 'read':
        ram[:4 * ram_words] = expected_pattern
    registers = [0] * 16
    pc = int.from_bytes(rom[:4], 'big')
    condition = False
    colors = []
    reads = writes = partial = 0
    vram = {}
    read_offsets = []
    error_reads = 0
    adapter_cache = None
    cache_control = 0
    writes_at_failure = None

    def read(address, width):
        nonlocal reads, error_reads, adapter_cache
        if (framebuffer and ram_base <= address < ram_base + 262144) or (not framebuffer and (0x26000000 <= address < 0x26100000 or 0x06000000 <= address < 0x06100000)):
            offset = address - ram_base if framebuffer else (address & ~0x20000000) - 0x06000000
            storage = banks[selected_bank] if framebuffer else ram
            value = int.from_bytes(storage[offset:offset + width], 'big')
            reads += 1
            read_offsets.append(offset)
            if cache_read and (failure_rereads or failure_cache_read) and pc >= program.labels['fail']:
                assert cache_control & 1 == 0, 'Physical failure probes must disable SH-2 cache first'
                assert writes == writes_at_failure, 'Failure probes must not rewrite RAMH'
            if cache_error_only:
                if failure_cache_read:
                    adapter_cache = (offset, value)
                if offset == error_offset and registers[12] == 0x200 and cache_control & 1:
                    value ^= 0x00800000
                return value
            if failure_cache_read and adapter_cache is not None and adapter_cache[0] == offset:
                return adapter_cache[1]
            if inject_error and offset == error_offset and (error_stage is None or registers[12] == error_stage):
                error_reads += 1
                if error_read_limit is None or error_reads <= error_read_limit:
                    value ^= 0x00800000
            if failure_cache_read:
                adapter_cache = (offset, value)
            return value
        assert address + width <= len(rom), hex(address)
        return int.from_bytes(rom[address:address + width], 'big')

    def write(address, value, width):
        nonlocal writes, partial, adapter_cache, selected_bank, flips, cache_control
        if ram_base <= address < ram_base + (262144 if framebuffer else 1048576):
            offset = address - ram_base
            storage = banks[selected_bank] if framebuffer else ram
            storage[offset:offset + width] = (value & ((1 << (width * 8)) - 1)).to_bytes(width, 'big')
            if adapter_cache is not None and offset // 4 == adapter_cache[0] // 4:
                adapter_cache = None
            writes += width == 4
            partial += width != 4
        elif framebuffer and address in (0x25D00000, 0x25D00002, 0x25D00004, 0x25D00008, 0x25D0000A):
            assert width == 2
            if address == 0x25D00002 and value == 3:
                flips += 1
                if not collapse_framebuffer_banks:
                    selected_bank ^= 1
        elif 0x25E00000 <= address < 0x25E00100:
            assert width == 2
            vram[address] = value & 0xFFFF
            if address == 0x25E00000:
                colors.append(value & 0x7FFF)
        else:
            assert address in (0x25F80000, 0x25F800AC, 0x25F800AE, 0xFFFFFE92), hex(address)
            if address == 0xFFFFFE92:
                assert width == 1
                cache_control = value & 0xFF

    def signed(value, bits):
        return value - (1 << bits) if value & (1 << (bits - 1)) else value

    for step in range(32000000 if framebuffer else 16000000):
        if pc == program.labels['fail']:
            writes_at_failure = writes
        if failure_bars and pc == program.labels['fail_halt']:
            assert inject_error or collapse_framebuffer_banks
            extra_values = failure_rereads + int(failure_cache_read)
            words = [vram[0x25E00000 + 2 * i] for i in range(44 + 8 * extra_values)]
            assert words[:4] == [0x7C1F, 0x03E0, 0x001F, 0x7800 if failure_cache_read else 0x7C00]
            values = [sum(words[4 + 8 * i + j] << (4 * j) for j in range(8)) for i in range(5 + extra_values)]
            index = error_offset // 4
            if collapse_framebuffer_banks:
                expected = 0x11223344
                expected_base = [expected, 0x55667788, ram_base, 0, 0x350]
            elif error_stage == 0x200 and not framebuffer:
                assert cache_read
                expected = (index * 0x01010101) & 0xFFFFFFFF
                expected_base = [expected, expected ^ 0x00800000, 0x06000000 + error_offset + 4, ram_words - index, 0x200]
            elif error_stage is None or error_stage == 0x100 or (framebuffer and error_stage == 0x200):
                expected = (first_seed + index * 0x01010101) & 0xFFFFFFFF
                expected_base = [expected, expected ^ 0x00800000, ram_base + error_offset + 4, ram_words - index, error_stage or 0x100]
            else:
                assert error_offset == 0 and error_stage in (*range(0x310, 0x314), 0x320, 0x322)
                expected_bytes = bytearray.fromhex('11223344')
                width = 1 if error_stage < 0x320 else 2
                lane = error_stage & 15
                expected_bytes[lane:lane + width] = (0xA5 if width == 1 else 0x5AA5).to_bytes(width, 'big')
                expected = int.from_bytes(expected_bytes, 'big')
                expected_base = [expected, expected ^ 0x00800000, ram_base, 0, error_stage]
            expected_extra = [expected if cache_error_only else expected ^ 0x00800000] if failure_cache_read else []
            expected_offsets = [error_offset] if failure_cache_read else []
            for reread in range(failure_rereads):
                expected_extra.append(0x55667788 if collapse_framebuffer_banks else expected ^ (0x00800000 if not cache_error_only and (error_read_limit is None or reread + 2 <= error_read_limit) else 0))
                expected_offsets += [error_offset ^ 4, error_offset]
            assert values == expected_base + expected_extra, values
            if expected_offsets:
                assert read_offsets[-len(expected_offsets):] == expected_offsets, read_offsets[-len(expected_offsets):]
            return {'result': 'EXPECTED_FAILURE_BARS', 'values': [hex(v) for v in values], 'instructions': step}
        if pc == program.labels['pass']:
            if video_only:
                assert colors == [0x7C00] and reads == writes == partial == 0
            else:
                assert colors == [0x7C00, 0x03E0]
                if framebuffer:
                    assert reads == 8 * ram_words + 16 and writes == 8 * ram_words + 14 and partial == 12, (reads, writes, partial)
                    assert flips == 3
                    assert banks[0][:4] == bytes.fromhex('11223344') and banks[1][:4] == bytes.fromhex('55667788')
                elif operation == 'both':
                    assert reads == 4 * ram_words + 6 + (ram_words if cache_read else 0) and writes == 4 * ram_words + 6 and partial == 6
                else:
                    assert reads == (ram_words if operation == 'read' else 0)
                    assert writes == (ram_words if operation == 'write' else 0) and partial == 0
                    assert ram[:4 * ram_words] == expected_pattern
                    assert ram[4 * ram_words:] == bytes(1048576 - 4 * ram_words)
            return {'result': 'PASS', 'instructions': step, 'reads32': reads, 'writes32': writes, 'partial_writes': partial}
        instruction = int.from_bytes(rom[pc:pc + 2], 'big')
        n = instruction >> 8 & 15
        m = instruction >> 4 & 15
        following = pc + 2
        if instruction >> 12 == 13:
            registers[n] = read(((pc + 4) & ~3) + 4 * (instruction & 255), 4)
        elif instruction >> 12 == 14:
            registers[n] = signed(instruction & 255, 8) & 0xFFFFFFFF
        elif instruction >> 12 == 2 and instruction & 15 <= 2:
            write(registers[n], registers[m], 1 << (instruction & 3))
            if not failure_bars and colors[-1:] == [0x001F]:
                assert inject_error
                return {'result': 'EXPECTED_RED', 'instructions': step, 'reads32': reads}
        elif instruction & 0xF00F == 0x200A:
            registers[n] ^= registers[m]
        elif instruction & 0xF00F in (0x6002, 0x6006):
            registers[n] = read(registers[m], 4)
            if instruction & 15 == 6:
                registers[m] = (registers[m] + 4) & 0xFFFFFFFF
        elif instruction & 0xF00F == 0x6003:
            registers[n] = registers[m]
        elif instruction & 0xF0FF == 0x4009:
            registers[n] >>= 2
        elif instruction >> 8 == 0xC9:
            registers[0] &= instruction & 255
        elif instruction >> 12 == 7:
            registers[n] = (registers[n] + signed(instruction & 255, 8)) & 0xFFFFFFFF
        elif instruction & 0xF00F == 0x300C:
            registers[n] = (registers[n] + registers[m]) & 0xFFFFFFFF
        elif instruction & 0xF00F == 0x3000:
            condition = registers[n] == registers[m]
        elif instruction & 0xF0FF == 0x4010:
            registers[n] = (registers[n] - 1) & 0xFFFFFFFF
            condition = registers[n] == 0
        elif instruction >> 8 in (0x89, 0x8B):
            if condition == (instruction >> 8 == 0x89):
                following = pc + 4 + 2 * signed(instruction & 255, 8)
        elif instruction >> 12 == 10:
            assert int.from_bytes(rom[pc + 2:pc + 4], 'big') == 9
            following = pc + 4 + 2 * signed(instruction & 0xFFF, 12)
        elif instruction != 9:
            raise AssertionError(f'Unsupported opcode {instruction:04x} at {pc:x}')
        pc = following
    raise AssertionError('ROM did not reach a verdict')


if __name__ == '__main__':
    assert hashlib.sha256(build(failure_bars=True)[1]).hexdigest() == '56aa111b2ed97d1d780ba4f139734501b0567c3e8641b1c1beb597bb8c640382'
    print('Default full1MiB ROM identity unchanged')
    print('Video:', check(video_only=True))
    print('RAMH:', check())
    print('RAMH uncached only:', check(cache_read=False))
    print('Injected DQ7 error:', check(inject_error=True))
    print('Injected DQ7 failure bars:', check(inject_error=True, failure_bars=True))
    print('One-word immediate verification:', check(cache_read=False, failure_bars=True, ram_words=1))
    print('Injected error with cache-displacing rereads:', check(cache_read=False, failure_bars=True, ram_words=1, failure_rereads=2, inject_error=True))
    print('Injected error with adapter-cache and physical rereads:', check(cache_read=False, failure_bars=True, ram_words=1, failure_rereads=2, failure_cache_read=True, inject_error=True))
    for seed in (0x5AA57FBE, 0, 0xFFFFFFFF):
        print(f'First seed {seed:08X}:', check(ram_words=1, first_seed=seed))
        print(f'Injected first seed {seed:08X}:', check(cache_read=False, failure_bars=True, ram_words=1,
              failure_rereads=2, failure_cache_read=True, first_seed=seed, inject_error=True))
    print('64KiB failed-address probe:', check(cache_read=False, failure_bars=True, ram_words=16384,
          failure_rereads=2, failure_cache_read=True))
    for offset, limit in ((0x5F88, None), (0x5788, 1), (0xFFFC, 1)):
        print(f'64KiB injected at {offset:04X}, limit={limit}:', check(cache_read=False, failure_bars=True,
              ram_words=16384, failure_rereads=2, failure_cache_read=True, inject_error=True,
              inject_offset=offset, error_read_limit=limit))
    print('Partial-write failed-address probe:', check(cache_read=False, failure_bars=True, ram_words=16,
          failure_rereads=2, failure_cache_read=True, inject_error=True, inject_offset=0,
          error_read_limit=1, error_stage=0x311))
    print('Cached-phase probe completes full1MiB:', check(cache_read=True, failure_bars=True,
          failure_rereads=2, failure_cache_read=True))
    for cache_only, limit in ((False, None), (False, 1), (True, None)):
        print(f'Cached-phase injected at1F0 cache_only={cache_only} limit={limit}:',
              check(cache_read=True, failure_bars=True, ram_words=128, failure_rereads=2,
                    failure_cache_read=True, inject_error=True, inject_offset=0x1F0,
                    error_stage=0x200, error_read_limit=limit, cache_error_only=cache_only))
    print('CPU cache faults are abstracted here; this checks probe order and saved values, not SH-2 cache RTL.')
    print('This checks generated SH-2 program semantics, not FPGA timing or HDL simulation.')
    for operation in ('write', 'read'):
        print(f'64KiB {operation} only:', check(cache_read=False, failure_bars=True, ram_words=16384, operation=operation))
    print('Read-only injected transient:', check(cache_read=False, failure_bars=True, ram_words=16384,
          failure_rereads=2, failure_cache_read=True, operation='read', inject_error=True,
          inject_offset=0x5B84, error_read_limit=1))
    print('Full1MiB write only:', check(cache_read=False, failure_bars=True, operation='write'))
    print('Full1MiB read only:', check(cache_read=False, failure_bars=True, operation='read',
          failure_rereads=2, failure_cache_read=True))
    print('Full1MiB last-word transient:', check(cache_read=False, failure_bars=True, operation='read',
          failure_rereads=2, failure_cache_read=True, inject_error=True,
          inject_offset=0xFFFFC, error_read_limit=1))
    print('Two full VDP1 framebuffer windows:', check(target='vdp1fb', ram_words=65536,
          cache_read=False, failure_bars=True, failure_rereads=2))
    print('VDP1 final word transient:', check(target='vdp1fb', ram_words=65536, cache_read=False,
          failure_bars=True, failure_rereads=2, inject_error=True, inject_offset=0x3FFFC, error_read_limit=1))
    print('VDP1 bank alias rejected:', check(target='vdp1fb', ram_words=16, cache_read=False,
          failure_bars=True, failure_rereads=2, collapse_framebuffer_banks=True))
    print('VDP1 flip completion is abstracted here; actual frame events require hardware marker verification.')
