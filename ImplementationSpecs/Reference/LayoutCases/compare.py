#!/usr/bin/env python3
# Created by Codex on 15.11.2026.
"""Compare measured Unity/SREngine layout, and source-derived scaler expectations."""
import argparse
import json
import math
from pathlib import Path


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))["Root"]


def compare(expected, actual, path, errors):
    if isinstance(expected, dict):
        if not isinstance(actual, dict) or set(expected) != set(actual):
            errors.append(f"{path}: field mismatch")
            return
        for key, value in expected.items():
            compare(value, actual[key], f"{path}.{key}", errors)
    elif isinstance(expected, list):
        if not isinstance(actual, list) or len(expected) != len(actual):
            errors.append(f"{path}: array length mismatch")
            return
        for i, (left, right) in enumerate(zip(expected, actual)):
            compare(left, right, f"{path}[{i}]", errors)
    elif isinstance(expected, (int, float)) and not isinstance(expected, bool):
        tolerance = 0.00001 if ".scale" in path else 0.001
        if (not isinstance(actual, (int, float)) or isinstance(actual, bool)
                or not math.isfinite(expected) or not math.isfinite(actual)
                or abs(expected - actual) > tolerance):
            errors.append(f"{path}: expected {expected}, got {actual}, tolerance {tolerance}")
    elif expected != actual:
        errors.append(f"{path}: expected {expected!r}, got {actual!r}")


def indexed(items):
    result = {item["id"]: item for item in items}
    if len(result) != len(items):
        raise ValueError("Duplicate case IDs")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("cases")
    parser.add_argument("unity")
    parser.add_argument("srengine")
    parser.add_argument("--scalers", required=True)
    parser.add_argument("--engine-scalers", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    fixtures, unity, engine, scalers = map(read, (args.cases, args.unity, args.srengine, args.scalers))
    expected_ids = set(indexed(fixtures["cases"]))
    left, right = indexed(unity["cases"]), indexed(engine["cases"])
    errors = []
    if not expected_ids or set(left) != expected_ids or set(right) != expected_ids:
        errors.append("Missing/unexpected layout cases; empty exports never pass")
    for case_id in sorted(expected_ids & set(left) & set(right)):
        expected_nodes = len(indexed(fixtures["cases"])[case_id]["nodes"])
        for label, value in (("unity", left[case_id]), ("srengine", right[case_id])):
            if len(value["states"]) != 3 or any(len(s["nodes"]) != expected_nodes for s in value["states"]):
                errors.append(f"{case_id}: invalid state/node count in {label}")
            else:
                compare(value["states"][1], value["states"][2], f"{case_id}.{label}.drift100", errors)
        compare(left[case_id], right[case_id], case_id, errors)
    expected_scalers = indexed(scalers["scalers"])
    actual_scalers = indexed(read(args.engine_scalers)["scalers"])
    if set(expected_scalers) != set(actual_scalers) or not expected_scalers:
        errors.append("Missing/unexpected scaler cases")
    for case_id in sorted(set(expected_scalers) & set(actual_scalers)):
        compare(expected_scalers[case_id], actual_scalers[case_id], case_id, errors)
    report = {"status": "FAIL" if errors else "PASS", "layoutCases": len(expected_ids),
              "scalerCases": len(expected_scalers), "scalerOracle": "source-derived, not Unity runtime measurements",
              "errors": errors}
    Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(report["status"], len(errors), "differences")
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
