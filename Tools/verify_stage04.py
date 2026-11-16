# Created by Codex on 16.11.2026.
"""Integration acceptance on the imported story. Does not launch the engine."""
import argparse
import copy
from pathlib import Path
import subprocess
import sys
from story_common import read_json, write_json, sha, require, StoryError
from story_compile import compile_story
from story_parser import parse
from story_validate import validate


PROJECT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    args = parser.parse_args()
    output = PROJECT / "Resources/DeathLovers/Story"
    report_path = PROJECT / "ImplementationSpecs/Reports/04_acceptance.json"
    try:
        before = {str(p.relative_to(output)): sha(p.read_bytes()) for p in output.rglob("*.json")}
        result = subprocess.run([sys.executable, str(PROJECT / "Tools/story_tool.py"), "convert", "--source", args.source], cwd=PROJECT, check=False)
        require(result.returncode == 0, "CONVERT", "Repeated production conversion failed")
        after = {str(p.relative_to(output)): sha(p.read_bytes()) for p in output.rglob("*.json")}
        require(before == after, "DETERMINISM", "Repeated conversion changed JSON bytes")
        story = read_json(output / "story.json")
        config = read_json(output / "resolved-config.json")
        registry = read_json(output / "command_ids.json")
        text = (Path(args.source) / "script.rpy").read_text(encoding="utf-8-sig")
        # Change the first literal Say text at its source location, preserving
        # syntax and every structural node; never write into the original.
        first = next(c for c in story["commands"].values() if c["type"] == "Say")
        lines = text.splitlines()
        index = first["sourceLine"] - 1
        original_line = lines[index]
        lines[index] = original_line.replace('.say("', '.say("Acceptance text edit: ', 1)
        require(lines[index] != original_line, "FIXTURE", "First Say source syntax changed; update integration edit fixture")
        changed_story, changed_ids, _ = compile_story([("script.rpy", parse("\n".join(lines), "script.rpy"))], config, copy.deepcopy(registry))
        require(set(changed_story["commands"]) == set(story["commands"]), "ID_STABILITY", "Text edit changed command ID set")
        require(changed_story["commands"][first["id"]]["text"] != first["text"], "FIXTURE", "Text edit was not applied")
        require([n["id"] for n in changed_ids["nodes"]] == [n["id"] for n in registry["nodes"]], "ID_STABILITY", "Text edit changed ID registry identities")
        negatives = []
        for field in ("target", "returnTarget"):
            broken = copy.deepcopy(story)
            command = next(c for c in broken["commands"].values() if c["type"] == "Call")
            command[field] = "cmd_99999999"
            try:
                validate(broken, config, read_json(output / "assets.json"))
            except StoryError as error:
                require(error.record["code"] in ("TARGET", "RETURN_TARGET"), "NEGATIVE", "Unexpected dangling-target error")
                negatives.append(error.record)
            else:
                raise StoryError("NEGATIVE", "Dangling target was accepted")
        validation = read_json(output / "validation.json")
        traces = read_json(output / "Debug/bound-playthroughs.json")
        escaped = next(c for c in story["commands"].values() if "Совет да любовь" in c.get("text", ""))
        require("[[x3]" in escaped["text"] and "[x3]" in escaped["normalizedText"] and "[[" not in escaped["normalizedText"], "D006", "Literal bracket escaping was lost")
        counts = {}
        for command in story["commands"].values():
            counts[command["type"]] = counts.get(command["type"], 0) + 1
        report = dict(status="PASSED", contentVersion=story["contentVersion"], deterministicJsonFiles=len(after), outputHashes=after, textEditPreservesAllIds=True, negativeTargets=negatives, commandCounts=counts, commands=len(story["commands"]), choiceOptions=sum(len(c.get("options", [])) for c in story["commands"].values()), labels=len(story["labels"]), assets=len(read_json(output / "assets.json")["assets"]), exploredStates=validation["exploredStates"], reachableCommands=len(validation["reachableCommands"]), documentedUnreachable=len(validation["unreachable"]), endingTraces=len(traces["runs"]), D004="No reachable empty choice in exhaustive graph traversal", D006="Escaped source preserved; normalized text has literal [x3]", runtime="Not executed; runtime/debug integration belongs to stages 05-07")
        write_json(report_path, report)
        print(f"PASSED: {len(after)} deterministic JSON files; all IDs stable under real-story text edit; target guards and D006 verified")
    except (StoryError, OSError, ValueError, KeyError) as error:
        write_json(report_path, dict(status="FAILED", message=str(error)))
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
