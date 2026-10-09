# DQ7 sample comparison

This experimental Saturn build adds independent first-byte and second-byte DQ7
selectors. Both default to Auto. Each also offers Early, Mid, Center, and Late
from the existing completed receive snapshots. DQS capture, the other seven
data lines, writes, and transaction lengths retain their existing behavior.

The override applies to normal high-speed memory reads. Register reads, memory
training, 8MHz reads, and slow diagnostic retries use the original selection.
Changing a selector restarts the memory interface, as changing its clock does.
The adapter captures both settings during engine reset and holds them afterward.

| Setting | Value | CFG status bits |
| --- | --- | --- |
| First byte | 0 Auto / 1 Early / 2 Mid / 3 Center / 4 Late | 86:84 |
| Second byte | Same values | 89:87 |

The first-byte selector controls word bits 31 and 15. The second-byte selector
controls word bits 23 and 7. All four correspond to physical DQ7 in a 32-bit
RAMH access. Reserved values 5 through 7 use Auto.

For board comparison, retain the same RBF, ROM, PSRAM connection and resistance.
Record an Auto control, vary the second-byte selector first, and retain every
failure or incomplete run. Repeated complete ROM passes are required before
calling a setting successful. A later first failure address alone does not
establish an improvement. Check 8MHz separately and preserve its failures.

Runner tests cover 16,384 registered capture cases: independent byte controls,
reserved values, unaffected DQ0 through DQ6, bypass cases, and reset-held
configuration. The normal RAMH regression exercises feature-enabled Auto.
These RTL tests do not model analog ringing, measured PCB delays or post-fit
timing, and do not establish a working board setting.
