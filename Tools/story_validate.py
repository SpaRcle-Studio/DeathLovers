# Created by Codex on 16.11.2026.
"""Strict document checks plus bounded exact reachable-state exploration."""
import math
import re
from story_common import require, StoryError, exact_file, sha


def value_type(value):
    return {bool: "bool", int: "int", str: "string"}.get(type(value))


def ast_type(tree, variables):
    require(type(tree) == dict and "op" in tree, "AST", "Expected condition AST object")
    op = tree["op"]
    fields = {"literal": {"op", "value"}, "variable": {"op", "variableId"}, "not": {"op", "operand"}, "and": {"op", "operands"}, "or": {"op", "operands"}}
    expected = fields.get(op, {"op", "left", "right"})
    require(set(tree) == expected, "AST", "Unexpected/missing AST fields")
    if op == "literal":
        result = value_type(tree.get("value"))
        require(result is not None, "AST_TYPE", "Invalid literal")
        if result == "int":
            require(-(2**31) <= tree["value"] < 2**31, "INT32", "Integer overflow")
        return result
    if op == "variable":
        require(tree.get("variableId") in variables, "VARIABLE", "Unknown variable in condition")
        return variables[tree["variableId"]]["type"]
    if op == "not":
        require(ast_type(tree.get("operand"), variables) == "bool", "AST_TYPE", "not requires bool")
    elif op in ("and", "or"):
        require(type(tree.get("operands")) == list and len(tree["operands"]) >= 2, "AST", "and/or require two or more operands")
        require(all(ast_type(x, variables) == "bool" for x in tree["operands"]), "AST_TYPE", "Logical operands must be bool")
    elif op in ("eq", "ne", "lt", "le", "gt", "ge"):
        left, right = ast_type(tree.get("left"), variables), ast_type(tree.get("right"), variables)
        require(left == right and (op in ("eq", "ne") or left == "int"), "AST_TYPE", "Comparison types differ or ordered comparison is not int")
    else:
        raise StoryError("AST_OP", f"Unknown operator {op}")
    return "bool"


def evaluate(tree, values):
    op = tree["op"]
    if op == "literal":
        return tree["value"]
    if op == "variable":
        return values[tree["variableId"]]
    if op == "not":
        return not evaluate(tree["operand"], values)
    if op == "and":
        return all(evaluate(x, values) for x in tree["operands"])
    if op == "or":
        return any(evaluate(x, values) for x in tree["operands"])
    left, right = evaluate(tree["left"], values), evaluate(tree["right"], values)
    return {"eq": lambda: left == right, "ne": lambda: left != right, "lt": lambda: left < right, "le": lambda: left <= right, "gt": lambda: left > right, "ge": lambda: left >= right}[op]()


def markup(text):
    require(type(text) == str, "TEXT", "Text must be string")
    stack, output, diagnostics = [], [], []
    position = 0
    visual = {"b", "i", "u", "s", "size", "color", "alpha", "shader", "cps"}
    for match in re.finditer(r"\{([^{}]+)\}", text):
        output.append(text[position:match.start()])
        token = match[1]
        closing = token.startswith("/")
        name = token.lstrip("/").split("=", 1)[0]
        require(name in visual | {"w", "nw", "fast"}, "TEXT_TAG", f"Unsupported tag {token}")
        if closing:
            require("=" not in token and name in visual, "TEXT_TAG", f"Invalid closing tag {token}")
            if name not in stack:
                diagnostics.append("ignored extra " + token)
            else:
                # Crossed ranges are legal; close only the matching range.
                stack.remove(name)
                output.append(match[0])
        else:
            parameter = token.partition("=")[2]
            if name in ("size", "alpha", "cps", "w") and parameter:
                require(re.fullmatch(r"[+*\-]?[0-9]+(?:\.[0-9]+)?", parameter), "TEXT_TAG", f"Invalid numeric parameter {token}")
            if name in ("size", "color", "alpha", "shader", "cps"):
                require(parameter, "TEXT_TAG", f"Missing parameter {token}")
            if name == "color":
                require(re.fullmatch(r"#[0-9a-fA-F]{3,8}", parameter), "TEXT_TAG", "Invalid color")
            if name == "shader":
                require(re.fullmatch(r"(?:wave|shake)(?::u__\w+=-?[0-9.]+)*", parameter), "TEXT_TAG", f"Unsupported shader parameters {token}")
            if name in visual:
                stack.append(name)
            output.append(match[0])
        position = match.end()
    output.append(text[position:])
    for name in reversed(stack):
        output.append("{/" + name + "}")
        diagnostics.append("closed " + name)
    return "".join(output).replace("[[", "["), diagnostics


def validate(story, config, assets=None, project=None, state_limit=500000):
    require(story.get("schemaVersion") == config.get("schemaVersion") == 1, "SCHEMA_VERSION", "Expected Story/config schemaVersion=1")
    require(re.fullmatch(r"[0-9a-f]{64}", story.get("contentVersion", "")), "CONTENT_VERSION", "Expected SHA-256")
    commands, variables = story.get("commands"), story.get("variables")
    require(type(commands) == dict and commands and type(variables) == dict, "SCHEMA", "commands/variables must be objects")
    for name, entry in variables.items():
        require(entry.get("type") == value_type(entry.get("initial")), "VARIABLE", f"Invalid initial value: {name}")
        require(entry["type"] != "int" or -(2**31) <= entry["initial"] < 2**31, "INT32", "Invalid initial integer")
    require(story.get("entryCommandId") in commands and story.get("labels", {}).get(config["entryLabel"]) == story["entryCommandId"], "ENTRY", "Invalid entry label/command")
    for target in story["labels"].values():
        require(target in commands, "TARGET", "Invalid label target")
    resources = {a["id"]: a for a in (assets or {}).get("assets", [])}
    if assets is not None:
        require(assets.get("schemaVersion") == 1, "MANIFEST_VERSION", "Invalid assets version")
        require(len(resources) == len(assets["assets"]), "RESOURCE_ID", "Duplicate asset ID")
    choices = set()
    types = {"Say", "NvlClear", "Scene", "Character", "Audio", "Assign", "Branch", "Choice", "Jump", "Call", "Return", "Wait", "RollbackBarrier", "RestartToMenu"}
    audit = []
    for identifier, command in commands.items():
        try:
            require(command.get("id") == identifier and re.fullmatch(r"cmd_[0-9]{8}", identifier), "COMMAND_ID", "Invalid command ID")
            require(type(command.get("sourceFile")) == str and type(command.get("sourceLine")) == int and command["sourceLine"] > 0, "SOURCE", "Missing source location")
            kind = command.get("type")
            require(kind in types and "next" in command, "COMMAND_TYPE", "Unknown command or missing next")
            fields = {
                "Say": {"speakerId", "mode", "text", "normalizedText", "autoWait"},
                "NvlClear": set(), "Scene": {"resourceId", "transition", "clearLayers"},
                "Character": {"characterId", "action", "state", "transition"},
                "Audio": {"bus", "action", "resourceId", "loop", "fadeSeconds"},
                "Assign": {"variableId", "operation", "value"},
                "Branch": {"condition", "trueTarget", "falseTarget"},
                "Choice": {"options"}, "Jump": {"target"}, "Call": {"target", "returnTarget"},
                "Return": set(), "Wait": {"seconds", "waitForInput"},
                "RollbackBarrier": set(), "RestartToMenu": set()
            }
            require(set(command) <= fields[kind] | {"id", "type", "sourceFile", "sourceLine", "next"}, "SCHEMA", "Unexpected command fields; executable host source forbidden")
            targets = [command["next"]]
            if kind in ("Jump", "Call"):
                targets.append(command["target"])
            if kind == "Call":
                require(command.get("returnTarget") in commands, "RETURN_TARGET", "Call requires a valid continuation")
                targets.append(command["returnTarget"])
            if kind == "Branch":
                require(ast_type(command["condition"], variables) == "bool", "AST_TYPE", "Branch requires bool")
                targets.extend([command["trueTarget"], command["falseTarget"]])
            if kind == "Choice":
                require(type(command["options"]) == list and command["options"], "CHOICE", "Empty choice")
                for option in command["options"]:
                    require(set(option) <= {"choiceId", "text", "normalizedText", "condition", "target"}, "SCHEMA", "Unexpected option fields")
                    cid = option["choiceId"]
                    require(re.fullmatch(r"choice_[0-9]{8}", cid) and cid not in choices, "CHOICE_ID", "Duplicate/invalid choice ID")
                    choices.add(cid)
                    require(type(option["text"]) == str and option["target"] in commands, "CHOICE", "Invalid choice text/target")
                    if "condition" in option:
                        require(ast_type(option["condition"], variables) == "bool", "AST_TYPE", "Choice requires bool")
                    normalized_option, _ = markup(option["text"])
                    require("normalizedText" not in option or option["normalizedText"] == normalized_option, "TEXT_NORMALIZATION", "Normalized option differs from contract")
                    targets.append(option["target"])
            require(all(t is None or t in commands for t in targets), "TARGET", "Dangling target")
            if kind == "Assign":
                name = command["variableId"]
                require(name in variables and variables[name]["type"] == value_type(command["value"]), "ASSIGN_TYPE", "Unknown variable/type mismatch")
                require(command["operation"] in ("set", "add") and (command["operation"] != "add" or variables[name]["type"] == "int"), "ASSIGN", "Invalid operation")
            if kind == "Say":
                require(command["speakerId"] in config["characters"] and command["mode"] in ("ADV", "NVL") and type(command["autoWait"]) == bool, "SAY", "Invalid speaker/mode/autoWait")
                normalized, notes = markup(command["text"])
                require("normalizedText" not in command or command["normalizedText"] == normalized, "TEXT_NORMALIZATION", "Normalized text differs from contract")
                audit.append(dict(commandId=identifier, originalText=command["text"], normalizedText=normalized, diagnostics=notes))
            if kind == "Character":
                actor = config["characters"].get(command["characterId"])
                require(actor and command["action"] == "set_state" and command["state"] in actor["states"], "CHARACTER_STATE", "Unknown state/action")
            if kind in ("Scene", "Character"):
                transition = command["transition"]
                require(transition["kind"] in ("none", "fade", "dissolve", "vpunch"), "TRANSITION", "Unknown transition")
                if "seconds" in transition:
                    require(type(transition["seconds"]) in (int, float) and math.isfinite(transition["seconds"]) and transition["seconds"] >= 0, "TRANSITION", "Invalid duration")
            if kind == "Scene":
                require(command["clearLayers"] == ["master"], "SCENE_LAYERS", "scene clears master only; preserve custom character layers")
            if kind in ("Call", "Jump", "Return", "RestartToMenu"):
                require(command["next"] is None, "CONTROL_FLOW", "Control-flow command must have null next")
            if kind == "Audio":
                require(command["bus"] in ("Music", "Sfx", "Voice") and command["action"] in ("play", "stop") and type(command["loop"]) == bool, "AUDIO", "Invalid audio fields")
                require(type(command["fadeSeconds"]) in (int, float) and math.isfinite(command["fadeSeconds"]) and command["fadeSeconds"] >= 0, "AUDIO", "Invalid fade")
            if kind == "Wait":
                require(("seconds" in command) != ("waitForInput" in command), "WAIT", "Expected one wait mode")
                require(command.get("waitForInput") is True or type(command.get("seconds")) in (int, float) and math.isfinite(command["seconds"]) and command["seconds"] >= 0, "WAIT", "Invalid wait")
            if kind == "Scene" or kind == "Audio" and command["action"] == "play":
                resource = command["resourceId"]
                require(resource in resources or resource in config.get("builtins", []), "RESOURCE", f"Unregistered resource {resource}")
        except StoryError as error:
            raise StoryError(error.record["code"], error.record["message"], command.get("sourceFile", ""), command.get("sourceLine", 0)) from error
        except (KeyError, TypeError) as error:
            raise StoryError("SCHEMA", f"Missing/invalid field: {error}", command.get("sourceFile", ""), command.get("sourceLine", 0)) from error
    if project:
        for asset in resources.values():
            path = exact_file(project, asset["target"])
            require(sha(path.read_bytes()) == asset["sha256"], "ASSET_HASH", f"Modified resource: {asset['target']}")
    names = sorted(variables)
    initial = tuple(variables[n]["initial"] for n in names)
    pending = [(story["entryCommandId"], (), initial)]
    seen, reached = set(), set()
    while pending:
        current, stack, values = pending.pop()
        if current is None:
            continue
        state = (current, stack, values)
        if state in seen:
            continue
        seen.add(state)
        require(len(seen) <= state_limit and len(stack) <= 128, "STATE_LIMIT", f"Exploration incomplete: states={len(seen)}, stackDepth={len(stack)}, command={current}; raise limit/review recursion, never treat this as a pass", commands[current])
        reached.add(current)
        command = commands[current]
        data = dict(zip(names, values))
        kind = command["type"]
        next_ids = [command["next"]]
        if kind == "Assign":
            name = command["variableId"]
            data[name] = command["value"] if command["operation"] == "set" else data[name] + command["value"]
            require(type(data[name]) != int or -(2**31) <= data[name] < 2**31, "INT32", "Reachable integer overflow", command)
            values = tuple(data[n] for n in names)
        elif kind == "Branch":
            next_ids = [command["trueTarget"] if evaluate(command["condition"], data) else command["falseTarget"]]
        elif kind == "Choice":
            next_ids = [o["target"] for o in command["options"] if "condition" not in o or evaluate(o["condition"], data)]
            require(next_ids, "EMPTY_REACHABLE_CHOICE", "No visible choice in reachable state " + repr(data), command)
        elif kind == "Call":
            stack = stack + (command["returnTarget"],)
            next_ids = [command["target"]]
        elif kind == "Jump":
            next_ids = [command["target"]]
        elif kind == "Return":
            next_ids = [stack[-1]] if stack else []
            stack = stack[:-1]
        elif kind == "RestartToMenu":
            next_ids = []
        pending.extend((target, stack, values) for target in next_ids)
    unreachable = set(commands) - reached
    exemptions = config.get("unreachable", {})
    require(all(identifier in exemptions and exemptions[identifier] for identifier in unreachable), "UNREACHABLE", "Document reason for unreachable commands: " + ", ".join(sorted(unreachable)))
    return dict(schemaVersion=1, reachableCommands=sorted(reached), exploredStates=len(seen), unreachable={i: exemptions[i] for i in sorted(unreachable)}, textAudit=audit)
