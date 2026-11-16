# Created by Codex on 16.11.2026.
"""User-run offline pipeline. Python 3.11+, standard library only."""
import argparse
from pathlib import Path
import shutil
import sys
from story_common import read_json, write_json, rows, sha, encoded, inside, exact_file, require, StoryError, check_import_conflicts
from story_parser import parse
from story_compile import compile_story
from story_validate import validate, markup


PROJECT = Path(__file__).resolve().parent.parent


def build(args):
    config = read_json(args.config)
    reference = Path(args.reference)
    source = Path(args.source)
    output = Path(args.output)
    require(not output.resolve().is_relative_to(source.resolve()), "OUTPUT", "Output must be outside original game")
    source_rows = rows(reference / "SOURCE_FILES.tsv")
    declared = config["sourceFiles"] + list(config["excludedSourceFiles"])
    require(set(declared) == {r["file"] for r in source_rows} and len(declared) == len(set(declared)), "SOURCE_COVERAGE", "Every baseline source must be compiled or explicitly classified once")
    normalized = []
    for entry in source_rows:
        path = exact_file(source, entry["file"])
        data = path.read_bytes()
        require(args.allow_source_changes or sha(data).lower() == entry["sha256"].lower(), "BASELINE_CHANGED", f"Review source changes: {entry['file']}; use --allow-source-changes only after review")
        normalized.append([entry["file"], data.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")])
    assets = []
    resource_usage = []
    aliases = rows(reference / "FILE_ALIASES.tsv")
    alias_paths = {a["source"]: a["physical"] for a in aliases}
    for asset in rows(reference / "ASSET_MANIFEST.tsv"):
        physical = alias_paths.get(asset["source"], asset["source"])
        path = exact_file(source, physical)
        target = asset["target"]
        inside(PROJECT, target)
        assets.append(dict(id=physical, source=physical, target=target, sha256=sha(path.read_bytes()), names=asset["id"].split(";")))
        resource_usage.append(dict(resourceId=physical, usage=asset["usage"], references=asset["directReferences"], unusedCandidate="unused candidate" in asset["usage"] or "excluded from v1" in asset["usage"]))
    asset_doc = dict(schemaVersion=1, assets=assets)
    image_sources = {row["id"]: alias_paths.get(row["source"], row["source"]) for row in rows(reference / "IMAGE_DEFINITIONS.tsv")}
    for controller, tag, position, scale in (("ch_p", "plague", [250, 0], [0.3, 0.3]), ("ch_w", "war", [250, -50], [0.32, 0.32]), ("ch_h", "hunger", [360, -50], [0.32, 0.32])):
        actor = config["characters"][controller]
        actor.update(layer="character_" + tag, position=position, scale=scale, flip=[False, False], animation=None, order=0, coordinateSpace="RenPy1920x1080")
        actor["stateResources"] = {}
        for state in actor["states"]:
            image = tag + " " + state
            if tag == "plague" and state.endswith(" sig"):
                image = tag + " " + state.replace(" sig", "sig")
            resource = "images/empty.png" if state == "hidden" else image_sources.get(image)
            require(resource in {a["id"] for a in assets}, "CHARACTER_RESOURCE", f"Unknown state image: {controller}/{state}")
            actor["stateResources"][state] = resource
    scene_rows = rows(reference / "SCENE_REFERENCES.tsv")
    for row in scene_rows:
        if row["id"] == "black":
            config["scenes"]["black"] = "builtin:black"
            continue
        require(row["status"] == "resolved", "SCENE", f"Unresolved Reference scene: {row}")
        candidates = row["candidates"].split(";")
        require(len(candidates) == 1, "SCENE", "Ambiguous Reference scene")
        candidate = alias_paths.get(candidates[0], candidates[0])
        matches = [a["id"] for a in assets if a["source"] == candidate]
        require(len(matches) == 1, "SCENE", f"Scene must resolve uniquely: {row['id']}")
        config["scenes"][row["id"]] = matches[0]
    registry_path = output / "command_ids.json"
    registry = read_json(registry_path) if registry_path.exists() else None
    mapping = read_json(args.mapping) if args.mapping else {}
    trees = [(name, parse(exact_file(source, name).read_text(encoding="utf-8-sig"), name)) for name in config["sourceFiles"]]
    story, registry, coverage = compile_story(trees, config, registry, mapping)
    text_audit = []
    for command in story["commands"].values():
        text_nodes = [command] if command["type"] == "Say" else command.get("options", [])
        for text_node in text_nodes:
            normalized_text, diagnostics = markup(text_node["text"])
            text_node["normalizedText"] = normalized_text
            text_audit.append(dict(commandId=command["id"], choiceId=text_node.get("choiceId"), originalText=text_node["text"], normalizedText=normalized_text, diagnostics=diagnostics))
    manifests = [[name, (reference / name).read_text(encoding="utf-8-sig").replace("\r\n", "\n")] for name in config["referenceFiles"]]
    # Identity registry and asset hashes are part of content identity, not diagnostic timestamps.
    story["contentVersion"] = sha(encoded(dict(sources=normalized, reference=manifests, config=config, registry=registry, assets=asset_doc)))
    write_json(output / "candidate.story.json", story)
    write_json(output / "coverage.json", dict(schemaVersion=1, executableNodes=coverage, classifiedSources=config["excludedSourceFiles"]))
    write_json(output / "candidate.command_ids.json", registry)
    write_json(output / "candidate.assets.json", asset_doc)
    write_json(output / "aliases.json", dict(schemaVersion=1, aliases=aliases))
    write_json(output / "resolved-config.json", config)
    write_json(output / "characters.json", dict(schemaVersion=1, characters=config["characters"]))
    write_json(output / "text-audit.json", text_audit)
    write_json(output / "resource-usage.json", dict(schemaVersion=1, resources=resource_usage, policy="Report Reference classifications only; dynamic candidates are not proven unused and are never deleted"))
    try:
        report = validate(story, config, asset_doc, state_limit=args.state_limit)
    except StoryError as error:
        write_json(output / "validation.json", dict(status="FAILED", errors=[error.record]))
        raise
    report["status"] = "PASSED"
    write_json(output / "validation.json", report)
    # Preflight every destination before copying any file. The last import manifest
    # is the baseline; a first import only adopts an already identical file.
    old_assets = read_json(output / "asset_import_baseline.json") if (output / "asset_import_baseline.json").exists() else dict(assets=[])
    if args.copy_assets:
        check_import_conflicts(PROJECT, assets, old_assets)
        for asset in assets:
            destination = inside(PROJECT, asset["target"])
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(exact_file(source, asset["source"]), destination)
        write_json(output / "asset_import_baseline.json", asset_doc)
    write_json(output / "story.json", story)
    write_json(output / "command_ids.json", registry)
    write_json(output / "assets.json", asset_doc)
    print(f"PASSED: {len(story['commands'])} commands, {len(coverage)} coverage records. Assets copied: {args.copy_assets}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    convert = sub.add_parser("convert")
    convert.add_argument("--source", required=True)
    convert.add_argument("--reference", default=str(PROJECT / "ImplementationSpecs/Reference"))
    convert.add_argument("--config", default=str(PROJECT / "Tools/pipeline.json"))
    convert.add_argument("--output", default=str(PROJECT / "Resources/DeathLovers/Story"))
    convert.add_argument("--mapping")
    convert.add_argument("--allow-source-changes", action="store_true")
    convert.add_argument("--copy-assets", action="store_true")
    convert.add_argument("--state-limit", type=int, default=3000000)
    check = sub.add_parser("validate")
    check.add_argument("--story", required=True)
    check.add_argument("--config", required=True)
    check.add_argument("--assets", required=True)
    check.add_argument("--project", help="Also check installed resource paths and hashes")
    check.add_argument("--report", required=True)
    check.add_argument("--state-limit", type=int, default=3000000)
    args = parser.parse_args()
    try:
        if args.action == "convert":
            build(args)
        else:
            result = validate(read_json(args.story), read_json(args.config), read_json(args.assets), args.project, args.state_limit)
            result["status"] = "PASSED"
            write_json(args.report, result)
            print("PASSED")
    except (StoryError, ValueError, OSError, SyntaxError) as error:
        record = error.record if isinstance(error, StoryError) else dict(code="INPUT", message=str(error), sourceFile="", sourceLine=0)
        report_path = args.report if args.action == "validate" else Path(args.output) / "validation.json"
        write_json(report_path, dict(status="FAILED", errors=[record]))
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
