#!/usr/bin/env python3
"""Decode Plan A UART A5/A6 binary captures without accessing the board.

Pages describe different snapshot times. Only the two addresses on pages 2--5
share the page-2 source-clock freeze; neither address is a retired CPU PC.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


FRAME_SIZE = 11
BSC_STATES = (
    "T0", "T1", "T2", "TW", "TRAS", "TWCAS", "TRCAS", "TRD",
    "TWNOP", "TRFS1", "TRFS2", "TV1", "TV2",
)
SCU_CBUS_STATES = (
    "CBUS_IDLE", "CBUS_REQUEST", "CBUS_INIT", "CBUS_START", "CBUS_IND_READ",
    "CBUS_READ", "CBUS_READ_END", "CBUS_WRITE", "CBUS_WRITE_WAIT",
    "CBUS_WRITE_END", "CBUS_REFRESH", "CBUS_RELEASE", "CBUS_END",
)
SCU_DMA_STATES = (
    "DMA_IDLE", "DMA_SELECT", "DMA_IND_START", "DMA_IND_READ_BBUS",
    "DMA_IND_READ_CBUS", "DMA_IND_END", "DMA_START", "DMA_ABUS_BBUS",
    "DMA_ABUS_CBUS", "DMA_BBUS_CBUS", "DMA_CBUS_ABUS", "DMA_CBUS_BBUS",
    "DMA_ABUS_DSP", "DMA_BBUS_DSP", "DMA_CBUS_DSP", "DMA_DSP_BBUS",
    "DMA_DSP_CBUS", "DMA_DSP_INIT", "DMA_DSP_START", "DMA_STOP",
)
CACHE_FLAGS = (
    "CCR_CE", "HIT", "CACHE_AREA", "NOCACHE_AREA", "IBUS_BURST",
    "IBUS_PREREQ", "CBUS_REQ", "CBUS_ID", "CBUS_WR", "CBUS_BUSY",
    "IBREQ", "IBUS_WAIT", "IBUS_READ", "IBUS_READARRAY", "IBUS_READ_PEND",
    "IBUS_WRITE_PEND",
)
BSC_FLAGS = (
    "BUS_RLS", "BGR", "CBUSY", "CBUSY2", "DBUS_ACTIVE", "VBUS_ACTIVE",
    "REFRESH_ACTIVE", "CBUS_EXT_REQ", "CBUS_PER_REQ", "CBUS_ACTIVE",
    "BUS_END", "CBUS_REQ",
)
SCU_FLAGS = (
    "CBRLS", "CBREQ_N", "CBACK_N", "ECWAIT_N_FF", "CBUS_REQ",
    "CBUS_REL", "CBUS_WAIT",
)


def xor_bytes(data):
    result = 0
    for byte in data:
        result ^= byte
    return result


def unpack_flags(word, names):
    return {name: bool(word & (1 << (len(names) - 1 - index)))
            for index, name in enumerate(names)}


def state_name(value, names):
    return names[value] if value < len(names) else f"UNKNOWN_{value}"


def cpu_state(word):
    low = word & 255
    return {
        "fetch_count": word >> 8,
        "cpu_state": low,
        "RES_SYNC_N": bool(low & 128),
        "CBUS_REQ": bool(low & 64),
        "CBUS_ID": bool(low & 32),
        "CACHE_BUSY": bool(low & 16),
        "MULT_BUSY": bool(low & 8),
        "CBUS_A_26_24": low & 7,
    }


def decode_page(page, word, protocol="A6"):
    if protocol == "A7" and page == 0:
        state = cpu_state(word & 255)
        state.pop("fetch_count")
        names = ("SSH_BREQ_N", "SSH_BACK_N", "MSH_BRLS_N", "MSH_BGR_N",
                 "DCC_SSH_ACTIVE", "DCC_SCU_ACTIVE", "slave_activity", "vblank_event")
        return {"kind": "arbitration_and_master_state", **state, **unpack_flags(word >> 8, names)}
    if page == 0:
        return {"kind": "cpu_activity", **cpu_state(word)}
    if page == 1:
        return {"kind": "cache_flags", **unpack_flags(word, CACHE_FLAGS)}
    if protocol == "A7" and page in (2,3,4,5):
        return {"kind": "first_illegal_fault_word", "word_index": page-2, "value": word}
    if page in (2, 3, 4, 5):
        return {
            "kind": "address_half",
            "address_bus": "CBUS_A" if page < 4 else "IBUS_A",
            "half": "low" if page % 2 == 0 else "high",
            "value": word,
        }
    if page == 6:
        state = word >> 12
        return {"kind": "slave_bsc_flags" if protocol == "A7" else "bsc_flags", "BUS_STATE": state,
                "BUS_STATE_name": state_name(state, BSC_STATES),
                **unpack_flags(word, BSC_FLAGS)}
    cbus, dma = word >> 12, (word >> 7) & 31
    return {
        "kind": "scu_flags", "CBUS_ST": cbus,
        "CBUS_ST_name": state_name(cbus, SCU_CBUS_STATES),
        "DMA_ST": dma, "DMA_ST_name": state_name(dma, SCU_DMA_STATES),
        **unpack_flags(word, SCU_FLAGS),
    }


def sequence_info(previous, current):
    if previous is None:
        return {"status": "first", "delta_mod256": None}
    delta = (current - previous) & 255
    if delta == 1:
        return {"status": "continuous", "delta_mod256": 1}
    if delta == 0:
        return {"status": "duplicate", "delta_mod256": 0}
    if delta < 128:
        return {"status": "forward_gap", "delta_mod256": delta,
                "apparent_missing_frames": delta - 1}
    return {"status": "out_of_order_or_large_gap", "delta_mod256": delta}


def decode_frame(data, offset, previous_sequence, discarded_before):
    ram = data[4] | data[5] << 8
    word = data[7] | data[8] << 8
    source = data[9]
    paged = data[0] in (0xA6, 0xA7)
    page = ((source >> 6) & 3) | (((source >> 3) & 1) << 2)
    valid_raw = data[3]
    frame = {
        "offset": offset, "protocol": f"{data[0]:02X}",
        "raw_hex": data.hex(), "sequence": data[2],
        "sequence_continuity": sequence_info(previous_sequence, data[2]),
        "discarded_bytes_before": discarded_before,
        "valid": valid_raw & 7, "valid_raw": valid_raw,
        "reserved_valid_bits": valid_raw & 0xF8,
        "ram_valid": bool(valid_raw & 1),
        "engine_valid": bool(valid_raw & 2),
        "sys_valid": bool(valid_raw & 4),
        "ram": ram, "stage": data[6], "cpu_payload": word,
        "source_tag": source,
        "system_reset_released": bool(source & 32),
        "master_reset_released": bool(source & 16),
        "start_seen": bool(source & 2), "start_current": bool(source & 1),
        "mode": (ram >> 14) & 3, "speed": (ram >> 12) & 3,
        "ramh_read": bool(ram & 2048), "ramh_busy": bool(ram & 1024),
        "pll_locked": bool(ram & 512), "bios_download": bool(ram & 256),
        "download": bool(ram & 128), "rst_ram": bool(ram & 64),
        "reset": bool(ram & 32), "rst_sys": bool(ram & 16),
        "ready": bool(ram & 8), "adapter_error": bool(ram & 4),
        "init_error": bool(ram & 2), "init_done": bool(ram & 1),
    }
    if paged:
        frame.update({"page": page, "fetch_progress": bool(source & 4),
                      "page_data": decode_page(page, word, frame["protocol"])})
    else:
        frame.update(cpu_state(word))
        frame["reserved_source_bits"] = source & 0xCC
    return frame


def address_mapping(address):
    segment = address >> 29
    external = address >> 27 in (0, 4)
    low27 = address & 0x07FFFFFF
    ramh = external and ((low27 >> 25) & 3) == 3
    result = {
        "hex": f"0x{address:08X}", "value": address,
        "segment_31_29": segment,
        "cache_space": ("cached", "uncached", "purge", "cache_address",
                        "cache_data", "unmapped", "cache_data", "internal_io")[segment],
        "bsc_external_address_pattern": external,
        "low27_hex": f"0x{low27:08X}", "ramh_alias": ramh,
    }
    if ramh:
        result["ramh_offset_hex"] = f"0x{address & 0xFFFFF:05X}"
    return result


def assemble_addresses(frames, protocols=("A6",)):
    groups, discarded = [], []
    active = []
    for frame in frames:
        reason = None
        usable = (frame["protocol"] in protocols and frame["valid_raw"] == 7
                  and frame["master_reset_released"]
                  and frame["system_reset_released"]
                  and not frame["reset"] and not frame["rst_sys"])
        if active:
            if frame["protocol"] not in protocols or frame["protocol"] != active[0]["protocol"]:
                reason = "protocol_change"
            elif frame["valid_raw"] != 7:
                reason = "invalid_domain_mask"
            elif not usable:
                reason = "reset_not_released"
            elif frame["sequence_continuity"]["status"] != "continuous":
                reason = "sequence_discontinuity"
            elif frame["discarded_bytes_before"]:
                reason = "discarded_stream_bytes"
            elif frame["page"] != 2 + len(active):
                reason = "duplicate_or_out_of_order_page"
            if reason:
                discarded.append({"reason": reason, "at_offset": frame["offset"],
                                  "sequences": [item["sequence"] for item in active],
                                  "pages": [item["page"] for item in active]})
                active = []
                continue
            active.append(frame)
            if len(active) == 4:
                cbus = active[0]["cpu_payload"] | active[1]["cpu_payload"] << 16
                ibus = active[2]["cpu_payload"] | active[3]["cpu_payload"] << 16
                groups.append({"start_offset": active[0]["offset"],
                               "sequences": [item["sequence"] for item in active],
                               "pages": [2, 3, 4, 5],
                               "CBUS_A": address_mapping(cbus),
                               "IBUS_A": address_mapping(ibus)})
                active = []
        elif usable and frame["page"] == 2:
            active = [frame]
    if active:
        discarded.append({"reason": "incomplete_group_at_end", "at_offset": None,
                          "sequences": [item["sequence"] for item in active],
                          "pages": [item["page"] for item in active]})
    return groups, discarded


def assemble_faults(frames):
    raw_groups, dropped = assemble_addresses(frames, ("A7",))
    confirmed, previous = [], None
    for group in raw_groups:
        value = group["CBUS_A"]["value"] | group["IBUS_A"]["value"] << 32
        span = [f for f in frames if previous is not None and
                previous["offset"] <= f["offset"] <= group["start_offset"] + 33]
        uninterrupted = bool(span) and all(f["valid_raw"] == 7 and
            f["master_reset_released"] and f["system_reset_released"] and
            not f["reset"] and not f["rst_sys"] and f["protocol"] == "A7" and
            not f["discarded_bytes_before"] and
            (i == 0 or f["sequence_continuity"]["status"] == "continuous")
            for i,f in enumerate(span))
        if value >> 63 and previous is not None and value == previous["value"] and uninterrupted:
            flags = value >> 48
            confirmed.append({"offset": group["start_offset"], "record_hex": f"{value:016X}",
                "PC": f"0x{value & 0xFFFFFFFF:08X}", "IR": f"0x{(value >> 32) & 0xFFFF:04X}",
                "vector": flags & 255, "slave": bool(flags & 1024),
                "delay_slot": bool(flags & 16384), "IFID_STALL": bool(flags & 8192),
                "MA_ACTIVE": bool(flags & 4096), "IF_ACTIVE": bool(flags & 2048),
                "state_low2": (flags >> 8) & 3})
        previous = {"value": value, "offset": group["start_offset"]}
    return confirmed, dropped


def decode_capture(raw):
    frames = []
    index = last_end = bad_crc = truncated = 0
    previous = None
    while index < len(raw):
        if raw[index:index + 2] not in (b"\xA5\x5A", b"\xA6\x5A", b"\xA7\x5A"):
            index += 1
            continue
        if index + FRAME_SIZE > len(raw):
            truncated += 1
            index += 1
            continue
        candidate = raw[index:index + FRAME_SIZE]
        if xor_bytes(candidate) != 0:
            bad_crc += 1
            index += 1
            continue
        frame = decode_frame(candidate, index, previous, index - last_end)
        frames.append(frame)
        previous = frame["sequence"]
        index += FRAME_SIZE
        last_end = index
    groups, dropped = assemble_addresses(frames)
    faults, fault_dropped = assemble_faults(frames)
    continuity = Counter(frame["sequence_continuity"]["status"] for frame in frames)
    protocols = Counter(frame["protocol"] for frame in frames)
    pages = Counter(str(frame["page"]) for frame in frames
                    if frame["protocol"] in ("A6", "A7") and frame["sys_valid"])
    progress_frames = [frame for frame in frames
                       if frame["protocol"] in ("A6", "A7") and frame["valid_raw"] == 7
                       and frame["master_reset_released"] and frame["system_reset_released"]
                       and not frame["reset"] and not frame["rst_sys"]]
    stats = {
        "frames": len(frames), "protocols": dict(protocols), "pages": dict(pages),
        "valid_masks": dict(Counter(str(frame["valid_raw"]) for frame in frames)),
        "sequence_continuity": dict(continuity),
        "apparent_missing_frames": sum(frame["sequence_continuity"].get("apparent_missing_frames", 0)
                                       for frame in frames),
        "discarded_bytes": len(raw) - FRAME_SIZE * len(frames),
        "trailing_discarded_bytes": len(raw) - last_end,
        "bad_checksum_candidates": bad_crc, "truncated_header_candidates": truncated,
        "address_groups": len(groups), "discarded_address_groups": len(dropped),
        "confirmed_fault_records": len(faults),
        "progress_observations_released": len(progress_frames),
        "progress_true_released": sum(frame["fetch_progress"] for frame in progress_frames),
        "progress_false_released": sum(not frame["fetch_progress"] for frame in progress_frames),
    }
    return {
        "schema_version": 2, "bytes": len(raw), "raw_sha256": hashlib.sha256(raw).hexdigest(),
        "scope": "Read-only UART decoding; snapshots are not instruction-retirement or game acceptance evidence.",
        "page_timing": "Different pages are different snapshots; only pages 2/3/4/5 addresses share the page-2 freeze.",
        "sequence_note": "8-bit sequence wrap is accepted; backward order and forward gaps of at least 128 cannot be distinguished.",
        "stage_note": "Stage is the last engine stage code, not proof of an active transaction.",
        "scu_wait_note": "SCU CBUS_WAIT is the CPU A/B bus wait state, not PSRAM busy or a generic DMA wait.",
        "stats": stats, "frames": frames, "address_groups": groups,
        "confirmed_first_illegal_faults": faults, "discarded_fault_groups": fault_dropped,
        "discarded_address_groups": dropped,
    }


def test_frame(sequence, page=0, word=0, valid=7, released=True,
               progress=False, protocol=0xA6, ram=0x8209):
    source = (0x30 if released else 0) | 2
    if protocol in (0xA6, 0xA7):
        source |= (page & 3) << 6 | ((page >> 2) & 1) << 3 | int(progress) << 2
    data = bytes([protocol, 0x5A, sequence & 255, valid, ram & 255, ram >> 8,
                  0x20, word & 255, word >> 8, source])
    return data + bytes([xor_bytes(data)])


def run_self_tests():
    cases = 0

    def group(start=10):
        return [test_frame(start + index, index + 2, word)
                for index, word in enumerate((0x5678, 0x0700, 0xABCD, 0x2700))]

    result = decode_capture(b"".join(group()))
    assert len(result["address_groups"]) == 1
    assert result["address_groups"][0]["CBUS_A"]["value"] == 0x07005678
    assert result["address_groups"][0]["IBUS_A"]["value"] == 0x2700ABCD
    assert result["address_groups"][0]["CBUS_A"]["ramh_alias"]
    cases += 1

    result = decode_capture(b"".join(group(254)))
    assert result["address_groups"][0]["sequences"] == [254, 255, 0, 1]
    cases += 1

    for changed, reason in (
        (test_frame(12, 3, 0x0700), "sequence_discontinuity"),
        (test_frame(10, 3, 0x0700), "sequence_discontinuity"),
        (test_frame(9, 3, 0x0700), "sequence_discontinuity"),
        (test_frame(11, 2, 0x5678), "duplicate_or_out_of_order_page"),
        (test_frame(11, 4, 0xABCD), "duplicate_or_out_of_order_page"),
        (test_frame(11, 3, 0x0700, valid=3), "invalid_domain_mask"),
        (test_frame(11, 3, 0x0700, valid=15), "invalid_domain_mask"),
        (test_frame(11, 3, 0x0700, released=False), "reset_not_released"),
        (test_frame(11, 3, 0x0700, ram=0x8219), "reset_not_released"),
    ):
        data = group()
        data[1] = changed
        result = decode_capture(b"".join(data))
        assert not result["address_groups"]
        assert result["discarded_address_groups"][0]["reason"] == reason
        cases += 1

    data = group()
    damaged = data[1][:-1] + bytes([data[1][-1] ^ 1])
    result = decode_capture(data[0] + damaged + data[2] + data[3])
    assert not result["address_groups"]
    assert result["stats"]["bad_checksum_candidates"] == 1
    assert result["stats"]["discarded_bytes"] == 11
    cases += 1

    result = decode_capture(group()[0] + b"noise" + b"".join(group()[1:]))
    assert not result["address_groups"]
    assert result["stats"]["discarded_bytes"] == 5
    assert result["discarded_address_groups"][0]["reason"] == "discarded_stream_bytes"
    cases += 1

    result = decode_capture(b"noise" + b"".join(group()) + b"\xA6\x5A\x01")
    assert len(result["address_groups"]) == 1
    assert result["stats"]["discarded_bytes"] == 8
    assert result["stats"]["truncated_header_candidates"] == 1
    cases += 1

    result = decode_capture(test_frame(255, word=0xE3F7, protocol=0xA5)
                            + test_frame(0, 1, 0xA55A, progress=True))
    assert result["frames"][0]["fetch_count"] == 227
    assert result["frames"][0]["cpu_state"] == 247
    assert result["frames"][1]["sequence_continuity"]["status"] == "continuous"
    assert result["frames"][1]["page_data"]["CCR_CE"]
    assert result["stats"]["progress_true_released"] == 1
    cases += 1

    result = decode_capture(test_frame(1, 6, 0x0C10) + test_frame(2, 7, (8 << 12) | (19 << 7)))
    assert result["frames"][0]["page_data"]["BUS_STATE_name"] == "T0"
    assert result["frames"][0]["page_data"]["BUS_RLS"]
    assert result["frames"][1]["page_data"]["CBUS_ST_name"] == "CBUS_WRITE_WAIT"
    assert result["frames"][1]["page_data"]["DMA_ST_name"] == "DMA_STOP"
    assert address_mapping(0xFFFFFE92)["cache_space"] == "internal_io"
    assert not address_mapping(0xFFFFFE92)["ramh_alias"]
    cases += 1

    result = decode_capture(b"".join(group()[:3]))
    assert not result["address_groups"]
    assert result["discarded_address_groups"][0]["reason"] == "incomplete_group_at_end"
    cases += 1

    result = decode_capture(b"".join(group()[:2]) + test_frame(12, protocol=0xA5)
                            + b"".join(group(20)))
    assert len(result["address_groups"]) == 1
    assert result["discarded_address_groups"][0]["reason"] == "protocol_change"
    cases += 1
    result = decode_capture(test_frame(1, 0, 0xF3F7, protocol=0xA7))
    flags = result["frames"][0]["page_data"]
    assert flags["SSH_BREQ_N"] and flags["slave_activity"] and flags["vblank_event"]
    assert not flags["DCC_SSH_ACTIVE"] and "fetch_count" not in flags
    cases += 1
    result = decode_capture(test_frame(1, 6, 0x0C13, protocol=0xA7))
    assert result["frames"][0]["page_data"]["kind"] == "slave_bsc_flags"
    cases += 1
    result = decode_capture(b"".join(test_frame(i+10, i+2, v, protocol=0xA7)
                                   for i,v in enumerate((0x5678,0x0700,0xABCD,0x2700))))
    assert not result["address_groups"]
    cases += 1
    result = decode_capture(test_frame(10, 2, 0x5678) + test_frame(11, 3, 0x0700, protocol=0xA7))
    assert not result["address_groups"]
    assert result["discarded_address_groups"][0]["reason"] == "protocol_change"
    cases += 1
    def fault_cycle(seq, pc=0x06004020, flags=0x8004):
        words = (pc & 65535, pc >> 16, 0xFFFF, flags)
        return b"".join(test_frame(seq+i, i+2, word, protocol=0xA7) for i,word in enumerate(words))
    result = decode_capture(fault_cycle(1, pc=0) + fault_cycle(5) + fault_cycle(9))
    assert len(result["confirmed_first_illegal_faults"]) == 1
    assert result["confirmed_first_illegal_faults"][0]["PC"] == "0x06004020"
    assert not result["address_groups"]
    cases += 1
    result = decode_capture(fault_cycle(1) + test_frame(5, protocol=0xA7, released=False) + fault_cycle(6))
    assert not result["confirmed_first_illegal_faults"]
    cases += 1
    print(f"PASS: {cases} protocol positive/negative cases; no board or HDL execution")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path, help="Raw UART .bin capture")
    parser.add_argument("--out", type=Path, help="Independent JSON output")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        run_self_tests()
        if args.input is None:
            return
    if args.input is None:
        parser.error("Specify an input capture or --self-test")
    destination = args.out or args.input.with_suffix(".v2decoded.json")
    if destination.resolve() == args.input.resolve():
        parser.error("Output must not replace the input capture")
    result = decode_capture(args.input.read_bytes())
    result["input_path"] = str(args.input.resolve())
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(destination.resolve()), **result["stats"]},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
