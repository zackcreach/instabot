#!/usr/bin/env python3
import argparse
import json
import pathlib
import sys


def findings(report):
    values = {}
    for result in report.get("results", []):
        for entry in result.get("packages", []):
            package = entry["package"]
            identity = f"{package['ecosystem']}:{package['name']}"
            for group in entry.get("groups", []):
                advisory = sorted(group.get("aliases") or group.get("ids") or ["unknown"])[0]
                severity = float(group.get("max_severity") or 0)
                values[f"{identity}:{advisory}"] = severity
    return dict(sorted(values.items()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report")
    parser.add_argument("baseline")
    parser.add_argument("--write-baseline", action="store_true")
    arguments = parser.parse_args()
    current = findings(json.loads(pathlib.Path(arguments.report).read_text(encoding="utf-8")))
    baseline_path = pathlib.Path(arguments.baseline)
    if arguments.write_baseline:
        baseline_path.write_text(json.dumps({"version": 1, "findings": current}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    accepted = baseline.get("findings", {})
    regressions = {advisory: severity for advisory, severity in current.items() if advisory not in accepted or severity > accepted[advisory]}
    if regressions:
        for advisory, severity in regressions.items():
            print(f"new or more severe advisory: {advisory} ({severity})", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
