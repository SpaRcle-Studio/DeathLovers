# Created by Codex on 16.11.2026.
"""User-run acceptance tests. No engine, Ren'Py, or third-party packages."""
import copy
from pathlib import Path
import unittest
import tempfile
from story_common import read_json, encoded, sha, rows, StoryError, check_import_conflicts, exact_file
from qa_tool import geometry_exports
from story_parser import parse, expression
from story_compile import compile_story
from story_validate import validate, ast_type, evaluate, markup


ROOT = Path(__file__).resolve().parent


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.config = read_json(ROOT / "pipeline.json")
        self.config["scenes"] = {"black": "builtin:black"}

    def compile(self, text, registry=None, mapping=None):
        story, ids, coverage = compile_story([("fixture.rpy", parse(text, "fixture.rpy"))], self.config, copy.deepcopy(registry), mapping)
        story["contentVersion"] = sha(encoded(dict(text=text, ids=ids)))
        return story, ids, coverage

    def test_repeat_and_text_edit(self):
        text = (ROOT / "fixtures/positive.rpy").read_text(encoding="utf-8")
        first, ids, coverage = self.compile(text)
        again, again_ids, again_coverage = self.compile(text, ids)
        self.assertEqual(encoded(first), encoded(again))
        self.assertEqual(encoded(ids), encoded(again_ids))
        self.assertEqual(coverage, again_coverage)
        changed, changed_ids, _ = self.compile(text.replace("Нулевая ветка", "Исправленная реплика"), ids)
        self.assertEqual(set(first["commands"]), set(changed["commands"]))
        self.assertEqual([x["id"] for x in ids["nodes"]], [x["id"] for x in changed_ids["nodes"]])
        self.assertNotEqual(first["contentVersion"], changed["contentVersion"])
        # This fixture intentionally has statically unreachable branches/options.
        # Explicit reasons exercise exclusion handling without hiding production issues.
        self.config["unreachable"] = {i: "Fixture branch intentionally impossible after nested call" for i in first["commands"]}
        result = validate(first, self.config, dict(schemaVersion=1, assets=[]))
        self.assertGreater(result["exploredStates"], 0)
        call = next(c for c in first["commands"].values() if c["type"] == "Call")
        self.assertIn(call["returnTarget"], first["commands"])
        self.assertTrue(any("это строка" in c.get("text", "") for c in first["commands"].values()))

    def test_ambiguous_insert(self):
        text = 'label start:\n    $ ch_death.say("A")\n    $ ch_death.say("B")\n    return\n'
        _, ids, _ = self.compile(text)
        with self.assertRaisesRegex(StoryError, "AMBIGUOUS_ID"):
            self.compile(text.replace('    return', '    $ ch_death.say("C")\n    return'), ids)
        with self.assertRaisesRegex(StoryError, "AMBIGUOUS_ID"):
            self.compile(text.replace('say("A")', 'say("TEMP")').replace('say("B")', 'say("A")').replace('say("TEMP")', 'say("B")'), ids)

    def test_unknown(self):
        with self.assertRaisesRegex(StoryError, "UNKNOWN_BLOCK|UNKNOWN_STATEMENT"):
            self.compile((ROOT / "fixtures/unknown.rpy").read_text())

    def test_bad_resource(self):
        story, _, _ = self.compile((ROOT / "fixtures/bad-resource.rpy").read_text())
        with self.assertRaisesRegex(StoryError, "RESOURCE"):
            validate(story, self.config, dict(schemaVersion=1, assets=[]))

    def test_empty_reachable_choice(self):
        story, _, _ = self.compile((ROOT / "fixtures/empty-choice.rpy").read_text(encoding="utf-8"))
        with self.assertRaisesRegex(StoryError, "EMPTY_REACHABLE_CHOICE"):
            validate(story, self.config, dict(schemaVersion=1, assets=[]))

    def test_ast_is_typed_and_not_executable(self):
        with self.assertRaisesRegex(StoryError, "AST_OP"):
            expression('__import__("os")')
        with self.assertRaisesRegex(StoryError, "AST_TYPE"):
            ast_type(expression('True == 1'), {})
        tree = dict(op="or", operands=[dict(op="literal", value=True), dict(op="variable", variableId="not_read")])
        self.assertTrue(evaluate(tree, {}))

    def test_markup_audit(self):
        self.assertEqual(markup("{b}слово")[0], "{b}слово{/b}")
        self.assertEqual(markup("слово{/b}")[0], "слово")
        self.assertEqual(markup("Совет да любовь [[x3]")[0], "Совет да любовь [x3]")
        with self.assertRaisesRegex(StoryError, "TEXT_TAG"):
            markup("{unknown}text")

    def test_source_inventory_classification(self):
        inventory = rows(ROOT.parent / "ImplementationSpecs/Reference/SOURCE_FILES.tsv")
        declared = self.config["sourceFiles"] + list(self.config["excludedSourceFiles"])
        self.assertEqual(len(declared), len(set(declared)))
        self.assertEqual(set(declared), {entry["file"] for entry in inventory})
        story, _, _ = self.compile('label start:\n    menu:\n        "Пробел перед двоеточием" :\n            return\n')
        self.assertTrue(any(c["type"] == "Choice" for c in story["commands"].values()))

    def test_geometry_and_asset_conflicts(self):
        case = dict(id="case", states=[])
        self.assertEqual(geometry_exports(dict(Root=dict(cases=[case], scalers=[])), dict(Root=dict(cases=[case]))), [])
        with self.assertRaisesRegex(StoryError, "GEOMETRY_ID"):
            geometry_exports(dict(Root=dict(cases=[case, case])), dict(Root=dict(cases=[case])))
        with tempfile.TemporaryDirectory() as directory:
            resource = Path(directory) / "Image.png"
            resource.write_bytes(b"baseline")
            asset = dict(target="Image.png", sha256=sha(b"baseline"))
            baseline = dict(assets=[asset])
            check_import_conflicts(directory, [asset], dict(assets=[]))
            check_import_conflicts(directory, [dict(asset, sha256=sha(b"new source"))], baseline)
            with self.assertRaisesRegex(StoryError, "PATH_CASE"):
                exact_file(directory, "image.png")
            resource.write_bytes(b"user edit")
            with self.assertRaisesRegex(StoryError, "ASSET_CONFLICT"):
                check_import_conflicts(directory, [asset], baseline)

    def test_tombstone_and_no_reuse(self):
        text = 'label start:\n    pause 1\n    return\n'
        _, ids, _ = self.compile(text)
        _, deleted, _ = self.compile('label start:\n    return\n', ids)
        self.assertTrue(any(n["tombstone"] for n in deleted["nodes"]))
        _, added, _ = self.compile('label start:\n    pause 2\n    return\n', deleted)
        self.assertGreater(added["nextCommand"], ids["nextCommand"])
        # A nested label's body and following sibling share a label scope but
        # must never collide in the anchor registry (the real main_choice form).
        nested = 'label start:\n    label inner:\n        pause 1\n        pause 2\n        pause 3\n    pause 4\n    return\n'
        one, nested_ids, _ = self.compile(nested)
        two, _, _ = self.compile(nested, nested_ids)
        self.assertEqual(encoded(one), encoded(two))


if __name__ == "__main__":
    unittest.main()
