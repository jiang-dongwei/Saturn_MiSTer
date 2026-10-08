import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('testrom', Path(__file__).resolve().parents[2] / 'scripts/generate_saturn_ramh_testrom.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
build = generator.build


def check(video_only=False, inject_error=False, cache_read=True, failure_bars=False, ram_words=262144):
    program, rom, _ = build(video_only, cache_read, failure_bars, ram_words)
    ram = bytearray(1048576)
    registers = [0] * 16
    pc = int.from_bytes(rom[:4], 'big')
    condition = False
    colors = []
    reads = writes = partial = 0
    vram = {}

    def read(address, width):
        nonlocal reads
        if 0x26000000 <= address < 0x26100000 or 0x06000000 <= address < 0x06100000:
            offset = (address & ~0x20000000) - 0x06000000
            value = int.from_bytes(ram[offset:offset + width], 'big')
            reads += 1
            if inject_error and offset == 0xC0E4:
                value ^= 0x00800000
            return value
        assert address + width <= len(rom), hex(address)
        return int.from_bytes(rom[address:address + width], 'big')

    def write(address, value, width):
        nonlocal writes, partial
        if 0x26000000 <= address < 0x26100000:
            offset = address - 0x26000000
            ram[offset:offset + width] = (value & ((1 << (width * 8)) - 1)).to_bytes(width, 'big')
            writes += width == 4
            partial += width != 4
        elif 0x25E00000 <= address < 0x25E00100:
            assert width == 2
            vram[address] = value & 0xFFFF
            if address == 0x25E00000:
                colors.append(value & 0x7FFF)
        else:
            assert address in (0x25F80000, 0x25F800AC, 0x25F800AE, 0xFFFFFE92), hex(address)

    def signed(value, bits):
        return value - (1 << bits) if value & (1 << (bits - 1)) else value

    for step in range(16000000):
        if failure_bars and pc == program.labels['fail_halt']:
            assert inject_error
            words = [vram[0x25E00000 + 2 * i] for i in range(44)]
            assert words[:4] == [0x7C1F, 0x03E0, 0x001F, 0x7C00]
            values = [sum(words[4 + 8 * i + j] << (4 * j) for j in range(8)) for i in range(5)]
            index = 0xC0E4 // 4
            expected = (0xA55A8041 + index * 0x01010101) & 0xFFFFFFFF
            assert values == [expected, expected ^ 0x00800000, 0x2600C0E8, 0x40000 - index, 0x100], values
            return {'result': 'EXPECTED_FAILURE_BARS', 'values': [hex(v) for v in values], 'instructions': step}
        if pc == program.labels['pass']:
            if video_only:
                assert colors == [0x7C00] and reads == writes == partial == 0
            else:
                assert colors == [0x7C00, 0x03E0]
                assert reads == 4 * ram_words + 6 + (ram_words if cache_read else 0) and writes == 4 * ram_words + 6 and partial == 6
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


print('Video:', check(video_only=True))
print('RAMH:', check())
print('RAMH uncached only:', check(cache_read=False))
print('Injected DQ7 error:', check(inject_error=True))
print('Injected DQ7 failure bars:', check(inject_error=True, failure_bars=True))
print('One-word immediate verification:', check(cache_read=False, failure_bars=True, ram_words=1))
print('This checks generated SH-2 program semantics, not FPGA timing or HDL simulation.')
