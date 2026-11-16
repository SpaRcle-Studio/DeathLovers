# Created by Codex on 16.11.2026.
import ast
import re
from story_common import require, sha, encoded, StoryError
from story_parser import expression, statement


def compile_story(trees, config, registry=None, mapping=None):
    registry = registry or dict(schemaVersion=1, nextCommand=1, nextChoice=1, nodes=[])
    require(registry.get("schemaVersion") == 1, "MANIFEST_VERSION", "Unsupported command ID registry")
    mapping = mapping or {}
    old = {n["anchor"]: n for n in registry["nodes"] if not n.get("tombstone")}
    require(len(old) == len([n for n in registry["nodes"] if not n.get("tombstone")]), "ID_REGISTRY", "Duplicate active anchors")
    require(len({n["id"] for n in registry["nodes"]}) == len(registry["nodes"]), "ID_REGISTRY", "Duplicate ID including tombstones")
    for kind, counter in (("cmd", "nextCommand"), ("choice", "nextChoice")):
        values = [int(n["id"].split("_")[1]) for n in registry["nodes"] if n["id"].startswith(kind + "_")]
        require(type(registry[counter]) == int and registry[counter] > max(values, default=0), "ID_REGISTRY", "Counter must exceed every allocated ID including tombstones")
    pending = []
    variables = {}

    def walk(nodes, scope):
        current = scope
        for index, node in enumerate(nodes):
            text = node["text"]
            label = re.fullmatch(r"label (\w+):", text)
            if label:
                current = node["sourceFile"] + "/label:" + label[1]
                node["label"] = label[1]
                walk(node["children"], current)
                continue
            if text.startswith("default "):
                match = re.fullmatch(r"default (\w+) = (.+)", text)
                require(match and not node["children"], "DEFAULT", "Expected literal default", node)
                value = expression(match[2])
                require(value["op"] == "literal" and match[1] not in variables, "DEFAULT", "Duplicate or non-literal default", node)
                variables[match[1]] = dict(type={bool: "bool", int: "int", str: "string"}[type(value["value"])], initial=value["value"])
                continue
            anchor = f"{current}/{node['indent']}:{index}"
            node["anchor"] = anchor
            choice = text.startswith(('"', "'")) and text.endswith(":")
            if choice:
                # Python parses the quoted text separately, never executes it.
                match = re.fullmatch(r'((?:"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27))(?: if (.+?))?\s*:', text)
                require(match, "CHOICE", "Expected quoted option [if condition]:", node)
                node["option"] = dict(text=ast.literal_eval(match[1]))
                if match[2]:
                    node["option"]["condition"] = expression(match[2])
                shape = "ChoiceOption:" + (match[2] or "always")
            elif re.fullmatch(r"menu(?: \w+)?:", text):
                node["record"] = dict(type="Choice", options=[])
                shape = "Choice"
            elif text.startswith(("if ", "elif ")) and text.endswith(":"):
                condition = text.split(" ", 1)[1][:-1]
                node["record"] = dict(type="Branch", condition=expression(condition))
                shape = "Branch:" + condition
            elif text == "else:":
                walk(node["children"], anchor + "/else")
                continue
            else:
                require(not node["children"], "UNKNOWN_BLOCK", "Unsupported block", node)
                try:
                    node["record"] = statement(node, config)
                except (SyntaxError, ValueError) as error:
                    raise StoryError("SYNTAX", str(error), node["sourceFile"], node["sourceLine"]) from error
                except StoryError as error:
                    raise StoryError(error.record["code"], error.record["message"], node["sourceFile"], node["sourceLine"]) from error
                shape_record = {k: v for k, v in node["record"].items() if k not in ("text", "autoWait")}
                shape = sha(encoded(shape_record))
            node["shape"] = shape
            node["textFingerprint"] = sha((node.get("option", node.get("record", {})).get("text", "")).encode("utf-8"))
            node["scope"] = current
            node["kind"] = "choice" if choice else "cmd"
            pending.append(node)
            walk(node["children"], anchor + "/body")

    for file, nodes in trees:
        walk(nodes, file)

    # A same-shape sequence permits text-only edits. Structural edits in a
    # repeated run require explicit mappings rather than guessing identities.
    used = set()
    new_records = []
    old_scopes = {}
    new_scopes = {}
    for item in old.values():
        old_scopes.setdefault(item["scope"], []).append(item)
    for node in pending:
        new_scopes.setdefault(node["scope"], []).append(node)
    for node in pending:
        scope = node["scope"]
        nodes = new_scopes[scope]
        prior = old_scopes.get(scope, [])
        same = [n["shape"] for n in prior] == [n["shape"] for n in nodes]
        old_texts = [n.get("textFingerprint") for n in prior]
        new_texts = [n["textFingerprint"] for n in nodes]
        reordered = same and None not in old_texts and sorted(old_texts) == sorted(new_texts) and old_texts != new_texts
        index = nodes.index(node)
        candidate = None
        explicit = mapping.get(node["anchor"])
        if explicit:
            matches = [n for n in registry["nodes"] if n["id"] == explicit]
            require(len(matches) == 1, "MAPPING", f"Unknown mapped ID {explicit}", node)
            candidate = matches[0]
        elif same:
            require(not reordered or old_texts[index] == new_texts[index], "AMBIGUOUS_ID", f"Possible text-node move: explicitly map {node['anchor']}; text similarity is not identity", node)
            candidate = prior[index]
        else:
            matches = [n for n in prior if n["shape"] == node["shape"]]
            current_matches = [n for n in nodes if n["shape"] == node["shape"]]
            displaced = [n for n in old.values() if n["scope"] != scope and n["shape"] == node["shape"] and n["scope"] not in new_scopes]
            require(not displaced, "AMBIGUOUS_ID", f"Structural block moved: provide mapping for {node['anchor']}", node)
            require(not matches or len(matches) == len(current_matches) == 1, "AMBIGUOUS_ID", f"Provide anchor -> old ID mapping for {node['anchor']}; repeated structural anchor moved/inserted/deleted", node)
            candidate = matches[0] if matches else None
        if candidate:
            identifier = candidate["id"]
            require(identifier.startswith(node["kind"] + "_"), "MAPPING", "Command/choice ID kind mismatch", node)
        else:
            counter = "nextChoice" if node["kind"] == "choice" else "nextCommand"
            identifier = f"{node['kind']}_{registry[counter]:08d}"
            registry[counter] += 1
        require(identifier not in used, "MAPPING", f"ID reused twice: {identifier}", node)
        used.add(identifier)
        node["id"] = identifier
        new_records.append(dict(id=identifier, anchor=node["anchor"], scope=scope, shape=node["shape"], textFingerprint=node["textFingerprint"], previousShape=nodes[index - 1]["shape"] if index else None, nextShape=nodes[index + 1]["shape"] if index + 1 < len(nodes) else None, sourceFile=node["sourceFile"], sourceLine=node["sourceLine"], tombstone=False))

    commands = {}
    labels = {}
    coverage = []

    def block(nodes, following):
        entry = following
        index = len(nodes) - 1
        while index >= 0:
            node = nodes[index]
            text = node["text"]
            if "label" in node:
                entry = block(node["children"], entry)
                require(node["label"] not in labels, "LABEL", "Duplicate label", node)
                labels[node["label"]] = entry
            elif text.startswith("default "):
                pass
            elif text == "else:" or text.startswith("elif "):
                end = index
                while index >= 0 and not nodes[index]["text"].startswith("if "):
                    index -= 1
                require(index >= 0, "BRANCH", "elif/else without if", node)
                false_entry = entry
                for branch in reversed(nodes[index:end + 1]):
                    if branch["text"] == "else:":
                        false_entry = block(branch["children"], entry)
                    else:
                        add(branch, entry)
                        commands[branch["id"]].update(trueTarget=block(branch["children"], entry), falseTarget=false_entry)
                        false_entry = branch["id"]
                entry = false_entry
            elif "record" in node:
                add(node, entry)
                result = commands[node["id"]]
                if result["type"] == "Choice":
                    for child in node["children"]:
                        require("option" in child, "CHOICE", "Only option blocks are supported inside menu", child)
                        result["options"].append(dict(choiceId=child["id"], target=block(child["children"], entry), **child["option"]))
                        coverage.append(dict(sourceFile=child["sourceFile"], sourceLine=child["sourceLine"], choiceId=child["id"], commandId=node["id"]))
                elif result["type"] == "Branch":
                    result.update(trueTarget=block(node["children"], entry), falseTarget=entry)
                elif result["type"] == "Call":
                    result["returnTarget"] = entry
                    result["next"] = None
                elif result["type"] in ("Jump", "Return", "RestartToMenu"):
                    result["next"] = None
                entry = node["id"]
            index -= 1
        return entry

    def add(node, following):
        commands[node["id"]] = dict(node["record"], id=node["id"], sourceFile=node["sourceFile"], sourceLine=node["sourceLine"], next=following)
        coverage.append(dict(sourceFile=node["sourceFile"], sourceLine=node["sourceLine"], commandId=node["id"]))

    following = None
    for file, nodes in reversed(trees):
        following = block(nodes, following)
    for command in commands.values():
        if "targetLabel" in command:
            name = command.pop("targetLabel")
            require(name in labels, "TARGET", f"Missing label {name}", command)
            command["target"] = labels[name]
    require(config["entryLabel"] in labels, "ENTRY", "Missing entry label")
    mapped = [item.get("choiceId", item["commandId"]) for item in coverage]
    require(len(mapped) == len(set(mapped)) and set(mapped) == {node["id"] for node in pending}, "COVERAGE", "Every executable source node must map exactly once; review malformed option/branch blocks")
    tombstones = [dict(item, tombstone=True) for item in registry["nodes"] if item["id"] not in used]
    registry["nodes"] = sorted(new_records + tombstones, key=lambda x: x["id"])
    story = dict(schemaVersion=1, contentVersion="", entryCommandId=labels[config["entryLabel"]], labels=labels, commands=dict(sorted(commands.items())), variables=variables)
    return story, registry, sorted(coverage, key=lambda x: (x["sourceFile"], x["sourceLine"]))
