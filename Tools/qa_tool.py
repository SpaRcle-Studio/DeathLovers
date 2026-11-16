# Created by Codex on 16.11.2026.
"""Prepare checkpoint/replay data and check screenshot/geometry artifacts."""
import argparse
import math
from pathlib import Path
import re
import sys
from story_common import read_json, write_json, require, StoryError, exact_file
from story_validate import evaluate


ROOT = Path(__file__).resolve().parent


def prepare(story, manifest):
    commands = story["commands"]
    output = dict(schemaVersion=1, contentVersion=story["contentVersion"], status="OFFLINE_TRACE_ONLY", runs=[])
    flags = {"label_offices": "var_offices_visited", "label_landfill": "var_landfill_visited", "label_canteen": "var_canteen_visited"}
    for run in manifest["runs"]:
        selectors = dict(pair for package in run["packages"] for pair in manifest["packages"][package])
        values = {key: value["initial"] for key, value in story["variables"].items()}
        current, stack, choices = story["entryCommandId"], [], []
        reached_ending = False
        for step in range(20000):
            require(current in commands, "REPLAY_TARGET", "Replay terminated without reaching ending")
            if current == story["labels"][run["label"]]:
                reached_ending = True
                break
            command = commands[current]
            kind = command["type"]
            next_id = command["next"]
            if kind == "Assign":
                name = command["variableId"]
                values[name] = command["value"] if command["operation"] == "set" else values[name] + command["value"]
            elif kind == "Branch":
                next_id = command["trueTarget"] if evaluate(command["condition"], values) else command["falseTarget"]
            elif kind == "Call":
                stack.append(command["returnTarget"])
                next_id = command["target"]
            elif kind == "Return":
                next_id = stack.pop() if stack else None
            elif kind == "Jump":
                next_id = command["target"]
            elif kind == "RestartToMenu":
                break
            elif kind == "Choice":
                options = command["options"]
                if command["sourceLine"] in selectors:
                    ordinal = selectors[command["sourceLine"]]
                    require(1 <= ordinal <= len(options), "REPLAY_CHOICE", "Option index out of range", command)
                    selected = options[ordinal - 1]
                else:
                    location = next((label for label in manifest["visitOrder"] if not values[flags[label]]), None)
                    require(location, "REPLAY_CHOICE", "Unexpected menu without a selector", command)
                    candidates = [o for o in options if o.get("condition") == dict(op="not", operand=dict(op="variable", variableId=flags[location]))]
                    require(len(candidates) == 1, "REPLAY_NAVIGATION", "Navigation option must match unvisited flag uniquely", command)
                    selected = candidates[0]
                require("condition" not in selected or evaluate(selected["condition"], values), "REPLAY_CHOICE", "Selected option is unavailable", command)
                choices.append(dict(commandId=current, choiceId=selected["choiceId"]))
                next_id = selected["target"]
            current = next_id
        scores = [values[n] for n in ("var_plague_score", "var_war_score", "var_hunger_score")]
        require(reached_ending and scores == run["scoresPWH"], "REPLAY_ENDING", f"{run['id']}: expected {run['label']} {run['scoresPWH']}, got {scores}")
        output["runs"].append(dict(id=run["id"], choices=choices, expectedLabel=run["label"], scoresPWH=scores, screenshot=run["screenshot"]))
    state = dict(schemaVersion=1, contentVersion=story["contentVersion"], currentCommandId=story["entryCommandId"], phase="Ready", callStack=[], variables={k: v["initial"] for k, v in story["variables"].items()}, presentation=dict(background="builtin:black", characters=[], mode="ADV", speakerId="", text="", visibleIndex=0, remainingPause=0, choices=[], transition=dict(kind="none")), audio=[], history=[], rollbackBoundaryId="", rollbackCheckpoints=[], playTimeSeconds=0, activeEndingId="")
    return output, dict(new_game=state)


def geometry(expected, actual, path="$", errors=None):
    errors = [] if errors is None else errors
    if type(expected) == dict:
        if type(actual) != dict or set(expected) != set(actual):
            errors.append(path + ": object keys differ")
        else:
            for key in expected:
                geometry(expected[key], actual[key], path + "." + key, errors)
    elif type(expected) == list:
        if type(actual) != list or len(expected) != len(actual):
            errors.append(path + ": array sizes differ")
        else:
            for index, (left, right) in enumerate(zip(expected, actual)):
                geometry(left, right, f"{path}[{index}]", errors)
    elif type(expected) in (int, float) and type(actual) in (int, float):
        tolerance = 0.00001 if ".scale" in path else 0.001
        if not math.isfinite(expected) or not math.isfinite(actual) or abs(expected - actual) > tolerance:
            errors.append(f"{path}: {expected} != {actual}, tolerance={tolerance}")
    elif type(expected) != type(actual) or expected != actual:
        errors.append(path + ": value differs")
    return errors


def geometry_exports(left, right):
    errors = []
    for group in ("cases", "scalers"):
        expected = left["Root"].get(group, [])
        actual = right["Root"].get(group, [])
        require(type(expected) == type(actual) == list, "GEOMETRY_SCHEMA", "Expected arrays of cases/scalers")
        if not expected and not actual:
            continue
        indexed_left = {item["id"]: item for item in expected}
        indexed_right = {item["id"]: item for item in actual}
        require(len(indexed_left) == len(expected) and len(indexed_right) == len(actual), "GEOMETRY_ID", "Duplicate geometry ID")
        geometry(indexed_left, indexed_right, "$.Root." + group, errors)
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    prep = sub.add_parser("prepare")
    prep.add_argument("--story", required=True)
    prep.add_argument("--manifest", default=str(ROOT / "playthroughs.json"))
    prep.add_argument("--output", required=True)
    geo = sub.add_parser("geometry")
    geo.add_argument("--expected", required=True)
    geo.add_argument("--actual", required=True)
    geo.add_argument("--report", required=True)
    shots = sub.add_parser("screenshots")
    shots.add_argument("--directory", required=True)
    shots.add_argument("--report", required=True)
    args = parser.parse_args()
    try:
        if args.action == "prepare":
            traces, checkpoints = prepare(read_json(args.story), read_json(args.manifest))
            write_json(Path(args.output) / "bound-playthroughs.json", traces)
            write_json(Path(args.output) / "checkpoints.json", checkpoints)
        elif args.action == "geometry":
            left, right = read_json(args.expected), read_json(args.actual)
            require(left.get("Root", {}).get("cases") or left.get("Root", {}).get("scalers"), "GEOMETRY_EMPTY", "Expected measured fixture data")
            errors = geometry_exports(left, right)
            write_json(args.report, dict(status="FAILED" if errors else "PASSED", errors=errors, expected=args.expected, actual=args.actual))
            require(not errors, "GEOMETRY", f"{len(errors)} differences; see {args.report}")
        else:
            text = (ROOT.parent / "ImplementationSpecs/Reference/BASELINE_CHECKLIST.md").read_text(encoding="utf-8")
            names = sorted(set(re.findall(r"\b[a-z][a-z0-9_]+_1920x1080\.png", text)) | {f"ending_{i:02d}_1920x1080.png" for i in range(1, 9)})
            missing = []
            for name in names:
                try:
                    file = exact_file(args.directory, name)
                    header = file.read_bytes()[:24]
                    require(header[:8] == b"\x89PNG\r\n\x1a\n" and int.from_bytes(header[16:20], "big") == 1920 and int.from_bytes(header[20:24], "big") == 1080, "SCREENSHOT", "Expected real 1920x1080 PNG")
                except (StoryError, OSError):
                    missing.append(name)
            write_json(args.report, dict(status="FAILED" if missing else "PASSED", missingOrInvalid=missing, names=names, note="Checks names/PNG header only, never visual parity"))
            require(not missing, "SCREENSHOT", f"{len(missing)} missing/invalid images")
    except (StoryError, ValueError, OSError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
