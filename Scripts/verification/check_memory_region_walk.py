#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


SOURCE = Path(__file__).resolve().parents[2] / "Modules/Playback/Session/ProcessMemoryRegions.swift"
FIXTURE = r'''
import Darwin
import Foundation

let tag = UInt32(VM_MEMORY_APPLICATION_SPECIFIC_1)
var pageSize: vm_size_t = 0
guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { exit(2) }
let pageCount: vm_size_t = 3
var address: mach_vm_address_t = 0
let flags = Int32(bitPattern: tag << 24)
for candidate: mach_vm_address_t in [0x600000000000, 0x4000000000] {
    var requested = candidate
    if mach_vm_allocate(mach_task_self_, &requested, mach_vm_size_t(pageSize * pageCount), flags) == KERN_SUCCESS {
        address = requested
        break
    }
}
guard address != 0 else { exit(3) }
let bytes = UnsafeMutableRawPointer(bitPattern: UInt(address))!
for page in 0..<Int(pageCount) {
    bytes.advanced(by: page * Int(pageSize)).storeBytes(of: UInt8(page + 1), as: UInt8.self)
}
let start = ProcessInfo.processInfo.systemUptime
let summary = ProcessMemoryRegions.read()
let elapsed = ProcessInfo.processInfo.systemUptime - start
let expected = UInt64(pageSize * pageCount)
let actual = summary?.resident([tag]) ?? 0
let output: [String: Any] = [
    "regions": summary?.regionCount ?? 0,
    "elapsed": elapsed,
    "taggedExpectedBytes": expected,
    "taggedActualBytes": actual,
    "passed": actual == expected,
]
let data = try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
_ = mach_vm_deallocate(mach_task_self_, address, mach_vm_size_t(pageSize * pageCount))
'''


def run(directory: Path) -> int:
    fixture = directory / "main.swift"
    binary = directory / "memory-region-walk"
    fixture.write_text(FIXTURE)
    subprocess.run(
        ["xcrun", "swiftc", "-D", "DEBUG", str(SOURCE), str(fixture), "-o", str(binary)],
        check=True,
    )
    result = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
    output = json.loads(result.stdout)
    print(json.dumps(output, sort_keys=True))
    return 0 if output["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-directory", type=Path)
    args = parser.parse_args()
    if args.output_directory:
        args.output_directory.mkdir(parents=True, exist_ok=True)
        return run(args.output_directory)
    with tempfile.TemporaryDirectory(prefix="memory-region-walk-") as name:
        return run(Path(name))


if __name__ == "__main__":
    raise SystemExit(main())
