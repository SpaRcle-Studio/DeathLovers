# Created by Codex on 16.11.2026.
"""Indentation parser and allowlisted Python-expression AST translation."""
import ast
import io
import re
import tokenize
from story_common import StoryError, require


def clean(line):
    try:
        tokens = tokenize.generate_tokens(io.StringIO(line).readline)
        for token in tokens:
            if token.type == tokenize.COMMENT:
                return line[:token.start[1]].rstrip()
        return line.rstrip()
    except (tokenize.TokenError, IndentationError) as error:
        raise StoryError("LEX", str(error)) from error


def parse(text, file):
    root = []
    stack = [(-1, root)]
    previous = None
    for line_no, raw in enumerate(text.splitlines(), 1):
        require("\t" not in raw[:len(raw) - len(raw.lstrip())], "INDENT", "Use spaces", dict(sourceFile=file, sourceLine=line_no))
        statement = clean(raw.lstrip())
        if not statement:
            continue
        indent = len(raw) - len(raw.lstrip())
        while indent <= stack[-1][0]:
            stack.pop()
        if previous and indent > previous["indent"]:
            require(previous["text"].endswith(":"), "INDENT", "Unexpected indented statement", previous)
            stack.append((previous["indent"], previous["children"]))
        node = dict(text=statement, sourceFile=file, sourceLine=line_no, indent=indent, children=[])
        stack[-1][1].append(node)
        previous = node
    return root


def literal(node):
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub) and isinstance(node.operand, ast.Constant) and type(node.operand.value) in (int, float):
        value = -node.operand.value
        require(type(value) != int or -(2**31) <= value < 2**31, "INT32", "Integer exceeds signed 32-bit range")
        return value
    require(isinstance(node, ast.Constant) and type(node.value) in (str, bool, int, float), "LITERAL", "Expected primitive literal")
    if type(node.value) == int:
        require(-(2**31) <= node.value < 2**31, "INT32", "Integer exceeds signed 32-bit range")
    return node.value


def expression(source):
    try:
        return translate(ast.parse(source, mode="eval").body)
    except SyntaxError as error:
        raise StoryError("EXPRESSION", str(error)) from error


def translate(node):
    if isinstance(node, ast.Constant) or isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        value = literal(node)
        require(type(value) in (bool, int, str), "AST_TYPE", "Conditions use bool/int/string")
        return dict(op="literal", value=value)
    if isinstance(node, ast.Name):
        return dict(op="variable", variableId=node.id)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
        return dict(op="not", operand=translate(node.operand))
    if isinstance(node, ast.BoolOp):
        return dict(op="and" if isinstance(node.op, ast.And) else "or", operands=[translate(x) for x in node.values])
    if isinstance(node, ast.Compare) and len(node.ops) == 1:
        names = {ast.Eq: "eq", ast.NotEq: "ne", ast.Lt: "lt", ast.LtE: "le", ast.Gt: "gt", ast.GtE: "ge"}
        require(type(node.ops[0]) in names, "AST_OP", "Unsupported comparison")
        return dict(op=names[type(node.ops[0])], left=translate(node.left), right=translate(node.comparators[0]))
    raise StoryError("AST_OP", "Unsupported expression; function calls and arbitrary host code are forbidden")


def call(source):
    node = ast.parse(source, mode="eval").body
    require(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name), "CALL", "Expected allowlisted object.method call")
    require(all(k.arg is not None for k in node.keywords), "CALL", "**kwargs are forbidden")
    return node.func.value.id, node.func.attr, node.args, {k.arg: k.value for k in node.keywords}


def transition(node):
    if isinstance(node, ast.Name) and node.id in ("dissolve", "fade", "vpunch"):
        return dict(kind=node.id)
    require(isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "Dissolve" and len(node.args) == 1 and not node.keywords, "TRANSITION", "Expected Dissolve(seconds)")
    value = literal(node.args[0])
    require(type(value) in (int, float) and value >= 0, "TRANSITION", "Invalid duration")
    return dict(kind="dissolve", seconds=value)


def statement(node, config):
    text = node["text"]
    if text == "nvl clear":
        return dict(type="NvlClear")
    if text == "return":
        return dict(type="Return")
    match = re.fullmatch(r"(jump|call) (\w+)(?: from \w+)?", text)
    if match:
        return dict(type="Jump" if match[1] == "jump" else "Call", targetLabel=match[2])
    if text.startswith("scene "):
        parts = text[6:].split(" with ")
        require(len(parts) <= 2 and parts[0] in config["scenes"], "SCENE", f"Register scene {parts[0]}", node)
        return dict(type="Scene", resourceId=config["scenes"][parts[0]], transition=transition(ast.Name(id=parts[1])) if len(parts) == 2 else dict(kind="none"), clearLayers=["master"])
    match = re.fullmatch(r'(play|stop) (music|sound)(?: "([^"\n]+)")?( loop)?(?: (fadein|fadeout) ([0-9.]+))?', text)
    if match:
        require((match[1] == "play") == (match[3] is not None), "AUDIO", "play requires resource; stop forbids resource", node)
        result = dict(type="Audio", bus="Music" if match[2] == "music" else "Sfx", action=match[1], loop=bool(match[4]), fadeSeconds=float(match[6] or 0))
        if match[3]:
            result["resourceId"] = "audio/" + match[3]
        return result
    if text.startswith("pause"):
        match = re.fullmatch(r"pause(?: ([0-9.]+))?", text)
        require(match, "WAIT", "Expected pause [seconds]", node)
        return dict(type="Wait", **(dict(seconds=float(match[1])) if match[1] else dict(waitForInput=True)))
    if text.startswith("$ "):
        source = text[2:]
        parsed = ast.parse(source, mode="exec")
        require(len(parsed.body) == 1, "STATEMENT", "Only one statement is allowed", node)
        item = parsed.body[0]
        if isinstance(item, (ast.Assign, ast.AugAssign)):
            target = item.targets[0] if isinstance(item, ast.Assign) and len(item.targets) == 1 else getattr(item, "target", None)
            require(isinstance(target, ast.Name), "ASSIGN", "Expected variable assignment", node)
            require(isinstance(item, ast.Assign) or isinstance(item.op, ast.Add), "ASSIGN", "Only set/add supported", node)
            return dict(type="Assign", variableId=target.id, operation="set" if isinstance(item, ast.Assign) else "add", value=literal(item.value))
        obj, method, args, keywords = call(source)
        if obj == "renpy":
            if method == "block_rollback" and not args and not keywords:
                return dict(type="RollbackBarrier")
            if method == "full_restart" and len(args) == 1 and not keywords and ast.unparse(args[0]) == "config.game_main_transition":
                return dict(type="RestartToMenu")
        require(obj in config["characters"], "CHARACTER", f"Register speaker/controller {obj}", node)
        if method == "say":
            require(len(args) == 1 and set(keywords) <= {"auto_wait"}, "SAY", "Expected say(text, auto_wait=bool)", node)
            text_value = literal(args[0])
            auto = literal(keywords["auto_wait"]) if "auto_wait" in keywords else True
            require(type(text_value) == str and type(auto) == bool, "SAY", "Invalid say arguments", node)
            return dict(type="Say", speakerId=obj, mode="NVL" if obj == "nvl_narrator" else "ADV", text=text_value, autoWait=auto)
        if method == "set_state":
            require(len(args) == 1 and set(keywords) <= {"transition"}, "CHARACTER", "Expected set_state(state, transition=...)", node)
            result = dict(type="Character", characterId=obj, action="set_state", state=literal(args[0]), transition=dict(kind="none"))
            if "transition" in keywords:
                result["transition"] = transition(keywords["transition"])
            return result
    raise StoryError("UNKNOWN_STATEMENT", f"Add explicit support or documented exclusion: {text}", node["sourceFile"], node["sourceLine"])
