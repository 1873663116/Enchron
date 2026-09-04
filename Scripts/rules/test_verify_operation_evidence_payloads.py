#!/usr/bin/env python3

from __future__ import annotations

import ast
from pathlib import Path
import sys
import unittest

RULES = Path(__file__).resolve().parent
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import verify_operation_evidence_payloads as checker


def function(source: str) -> ast.FunctionDef:
    return next(
        node for node in ast.walk(ast.parse(source)) if isinstance(node, ast.FunctionDef)
    )


class ProducedKeyTests(unittest.TestCase):
    def test_a_single_literal_return_reports_its_keys(self) -> None:
        keys = checker.produced_keys(function('''
def handler(self, arguments, context):
    return {"succeeded": True, "fields": plane, "response": document}
'''))

        self.assertEqual(keys, {"succeeded", "fields", "response"})

    def test_two_returns_report_only_what_both_provide(self) -> None:
        keys = checker.produced_keys(function('''
def handler(self, arguments, context):
    if early:
        return {"succeeded": True, "fields": plane, "response": document}
    return {"succeeded": False, "reason": "deadline"}
'''))

        self.assertEqual(keys, {"succeeded"})

    def test_a_key_nested_inside_a_returned_list_does_not_count(self) -> None:
        keys = checker.produced_keys(function('''
def handler(self, arguments, context):
    frames = [{"fields": plane, "response": document}]
    return {"succeeded": True, "frames": frames}
'''))

        self.assertEqual(keys, {"succeeded", "frames"})

    def test_a_return_of_an_assigned_dictionary_is_followed(self) -> None:
        keys = checker.produced_keys(function('''
def handler(self, arguments, context):
    result = {"succeeded": True, "fields": plane, "response": document}
    return result
'''))

        self.assertEqual(keys, {"succeeded", "fields", "response"})

    def test_a_return_of_a_nested_helper_is_not_attributed_to_this_handler(self) -> None:
        keys = checker.produced_keys(function('''
def handler(self, arguments, context):
    def inner():
        return {"fields": plane, "response": document}
    return {"succeeded": True}
'''))

        self.assertEqual(keys, {"succeeded"})

    def test_an_unreadable_return_is_reported_as_unknown(self) -> None:
        keys = checker.produced_keys(function('''
def handler(self, arguments, context):
    return self.delegate(arguments, context)
'''))

        self.assertIsNone(keys)


class RequiredKeyTests(unittest.TestCase):
    def test_the_control_plane_branch_demands_fields_and_response(self) -> None:
        demands = checker.required_keys()

        self.assertEqual(demands["window.control-plane"], {"fields", "response"})

    def test_every_live_evidence_type_has_a_validator_branch(self) -> None:
        verification = checker.REPOSITORY_ROOT / "Scripts/verification"
        if str(verification) not in sys.path:
            sys.path.insert(0, str(verification))
        import regression_operation_adapter as adapter

        demands = checker.required_keys()
        declared = {
            evidence_type
            for spec in adapter.SPECS.values()
            for evidence_type, _ in spec.outputs
        }

        self.assertEqual(sorted(declared - set(demands)), [])


class RepositoryTests(unittest.TestCase):
    def test_every_declared_pair_is_satisfiable_today(self) -> None:
        self.assertEqual(checker.failures(), [])


if __name__ == "__main__":
    unittest.main()


class ComparisonTests(unittest.TestCase):
    DEMANDS = {"window.control-plane": {"fields", "response"}}

    def compare(self, source: str, outputs=(("window.control-plane", "window-control-plane@1"),)):
        return checker.compare(
            {"operation:sample@1": outputs},
            {"operation:sample@1": "_sample_1"},
            {"_sample_1": function(source)},
            self.DEMANDS,
        )

    def test_a_handler_that_provides_every_required_key_passes(self) -> None:
        found = self.compare('''
def _sample_1(self, arguments, context):
    return {"succeeded": True, "fields": plane, "response": document}
''')

        self.assertEqual(found, [])

    def test_a_handler_missing_a_required_key_is_reported(self) -> None:
        found = self.compare('''
def _sample_1(self, arguments, context):
    return {"succeeded": True, "fields": plane}
''')

        self.assertEqual(len(found), 1)
        self.assertIn("returns no top-level response", found[0])

    def test_a_key_present_on_only_one_branch_is_reported(self) -> None:
        found = self.compare('''
def _sample_1(self, arguments, context):
    if early:
        return {"succeeded": True, "fields": plane, "response": document}
    return {"succeeded": False, "reason": "deadline"}
''')

        self.assertEqual(len(found), 1)
        self.assertIn("returns no top-level fields, response", found[0])

    def test_a_key_nested_in_a_returned_list_is_reported_as_missing(self) -> None:
        found = self.compare('''
def _sample_1(self, arguments, context):
    frames = [{"fields": plane, "response": document}]
    return {"succeeded": True, "frames": frames}
''')

        self.assertEqual(len(found), 1)
        self.assertIn("returns no top-level fields, response", found[0])

    def test_an_evidence_type_with_no_validator_branch_is_reported(self) -> None:
        found = self.compare(
            '''
def _sample_1(self, arguments, context):
    return {"succeeded": True, "fields": plane, "response": document}
''',
            outputs=(("invented.evidence", "invented@1"),),
        )

        self.assertEqual(len(found), 1)
        self.assertIn("validates in no branch", found[0])

    def test_an_absent_handler_is_reported(self) -> None:
        found = checker.compare(
            {"operation:sample@1": (("window.control-plane", "window-control-plane@1"),)},
            {"operation:sample@1": "_sample_1"},
            {},
            self.DEMANDS,
        )

        self.assertIn("is absent from", found[0])

    def test_an_unreadable_handler_is_reported(self) -> None:
        found = self.compare('''
def _sample_1(self, arguments, context):
    return self.delegate(arguments, context)
''')

        self.assertIn("cannot read", found[0])

    def test_an_operation_declaring_nothing_is_left_alone(self) -> None:
        found = self.compare('''
def _sample_1(self, arguments, context):
    return {"succeeded": True}
''', outputs=())

        self.assertEqual(found, [])
