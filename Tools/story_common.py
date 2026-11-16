# Created by Codex on 16.11.2026.
"""Offline Story v1 utilities; never imported by the game."""
import csv
import hashlib
import json
from pathlib import Path


class StoryError(Exception):
    def __init__(self, code, message, file="", line=0):
        self.record = dict(code=code, message=message, sourceFile=file, sourceLine=line)
        super().__init__(f"{code} {file}:{line}: {message}")


def require(ok, code, message, node=None):
    if not ok:
        node = node or {}
        raise StoryError(code, message, node.get("sourceFile", ""), node.get("sourceLine", 0))


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "DUPLICATE_KEY", f"Duplicate JSON key {key}: {path}")
            result[key] = value
        return result
    return json.loads(Path(path).read_text(encoding="utf-8-sig"), object_pairs_hook=unique)


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encoded(value))


def rows(path):
    with Path(path).open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inside(root, relative):
    root = Path(root).resolve()
    target = (root / relative).resolve()
    require(target.is_relative_to(root) and target != root, "PATH_ESCAPE", str(relative))
    return target


def exact_file(root, relative):
    current = Path(root)
    for part in Path(relative).parts:
        require(part in [p.name for p in current.iterdir()], "PATH_CASE", f"Missing exact-case path: {relative}")
        current /= part
    require(current.is_file(), "RESOURCE", f"Not a file: {relative}")
    return current


def check_import_conflicts(project, assets, baseline):
    previous = {asset["target"]: asset["sha256"] for asset in baseline["assets"]}
    for asset in assets:
        destination = inside(project, asset["target"])
        if destination.exists():
            actual = sha(destination.read_bytes())
            require(actual == previous.get(asset["target"], asset["sha256"]), "ASSET_CONFLICT", f"User-modified asset; reconcile manually: {asset['target']}")
