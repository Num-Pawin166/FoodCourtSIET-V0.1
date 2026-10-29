"""สรุป coverage จาก lcov.info และล้มเหลวถ้าต่ำกว่าเกณฑ์

ใช้: python scripts/check_coverage.py mobile/coverage/lcov.info 70
"""
import sys
from collections import OrderedDict


def main(path: str, minimum: float) -> int:
    files: "OrderedDict[str, list[int]]" = OrderedDict()
    current = None
    with open(path, encoding="utf8") as f:
        for line in f:
            if line.startswith("SF:"):
                current = line[3:].strip().replace("\\", "/")
                files[current] = [0, 0]
            elif line.startswith("DA:") and current:
                hits = int(line.split(",")[1])
                files[current][1] += 1
                files[current][0] += hits > 0
    hit = sum(h for h, _ in files.values())
    total = sum(t for _, t in files.values())
    for name, (h, t) in files.items():
        print(f"{100 * h / t:6.1f}%  {h:4}/{t:<4}  {name}")
    pct = 100 * hit / total if total else 0
    print(f"\nTOTAL line coverage: {pct:.1f}% ({hit}/{total})  minimum: {minimum}%")
    if pct < minimum:
        print("FAILED: coverage below minimum")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 70))
