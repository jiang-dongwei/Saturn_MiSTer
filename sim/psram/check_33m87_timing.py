"""Reject incomplete or failing 33M87 TimeQuest reports before release naming."""
import argparse
import json
import math
from pathlib import Path
import re

SUMMARIES = ("Setup Summary", "Hold Summary", "Recovery Summary",
             "Removal Summary", "Minimum Pulse Width Summary")


def check_report(report):
    tables = {name: [] for name in (*SUMMARIES, "Clocks")}
    current = None
    for line in report.splitlines():
        columns = [column.strip() for column in line.split(";")[1:-1]]
        if len(columns) == 1:
            current = columns[0] if columns[0] in tables else None
        elif current and len(columns) > 1:
            tables[current].append(columns)

    errors = []
    minima = {}
    violations = []
    for name in SUMMARIES:
        rows = []
        for columns in tables[name]:
            try:
                slack = float(columns[1])
            except ValueError:
                continue
            if not math.isfinite(slack):
                errors.append(f"Invalid slack in {name}: {columns[1]}")
                continue
            rows.append((columns[0], slack))
            if slack < 0:
                violations.append({"check": name, "clock": columns[0], "slack_ns": slack})
        if not rows:
            errors.append(f"Missing numeric {name}")
            continue
        minima[name] = min(slack for _, slack in rows)
        if name in ("Setup Summary", "Hold Summary"):
            for clock in ("PSRAM_33M87_CLK_EXT", "|psram_speed_pll|"):
                if not any(clock in label for label, _ in rows):
                    errors.append(f"Missing {clock} in {name}")

    for label, expected in (("PSRAM_33M87_CLK_EXT", 33.8688),
                            ("|psram_speed_pll|", 67.7376)):
        matches = [columns for columns in tables["Clocks"] if label in columns[0]
                   and (label == "PSRAM_33M87_CLK_EXT" or columns[0].endswith("|divclk"))]
        if len(matches) != 1:
            errors.append(f"Expected one active clock matching {label}, got {len(matches)}")
            continue
        frequency = re.fullmatch(r"([0-9.]+) MHz", matches[0][3]) if len(matches[0]) > 3 else None
        if not frequency or abs(float(frequency[1]) - expected) > 0.02:
            errors.append(f"Wrong or absent clock frequency for {label}")

    for line in report.splitlines():
        if re.search(r"Ignored .*Saturn_PSRAM_33M87\.sdc", line):
            errors.append(line.strip())
        if re.search(r"PSRAM_DQ.*No input delay|PSRAM_(?:CE_N|DQ).*No output delay", line):
            errors.append(line.strip())
    return {"passed": not errors and not violations, "errors": errors,
            "minimum_slack_ns": minima, "violations": violations}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = check_report(args.report.read_text(encoding="utf-8", errors="replace"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
