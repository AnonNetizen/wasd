#!/usr/bin/env python3
"""Regression tests for controlled content contract registration."""

from __future__ import annotations

import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sync_contracts


class ContractMutationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = sync_contracts.CONTRACT_DOC.read_text(encoding="utf-8")

    def test_register_and_unregister_roundtrip(self) -> None:
        registered = sync_contracts.mutate_contract_document(
            self.source,
            "register",
            "skill_ids",
            "skill_contract_test",
            "契约工具测试技能",
        )
        self.assertIn("skill_contract_test", sync_contracts.extract_contracts(registered)["skill_ids"])
        artifact = sync_contracts.build_artifacts(registered)[
            sync_contracts.CONTRACTS_DIR / "skill_ids.gd"
        ]
        self.assertIn('const SKILL_CONTRACT_TEST: String = "skill_contract_test"', artifact)
        unregistered = sync_contracts.mutate_contract_document(
            registered,
            "unregister",
            "skill_ids",
            "skill_contract_test",
        )
        self.assertEqual(unregistered, self.source)

    def test_duplicate_id_is_rejected(self) -> None:
        with self.assertRaisesRegex(sync_contracts.ContractError, "already registered"):
            sync_contracts.mutate_contract_document(
                self.source,
                "register",
                "skill_ids",
                "skill_aoe_slow",
                "重复技能",
            )

    def test_illegal_key_and_prefix_are_rejected(self) -> None:
        with self.assertRaisesRegex(sync_contracts.ContractError, "not content-registerable"):
            sync_contracts.mutate_contract_document(
                self.source,
                "register",
                "skill_effects",
                "skill_effect_new",
                "不得登记代码原语",
            )
        with self.assertRaisesRegex(sync_contracts.ContractError, "expected prefix"):
            sync_contracts.mutate_contract_document(
                self.source,
                "register",
                "skill_ids",
                "ability_wrong_prefix",
                "错误前缀",
            )

    def test_all_allowlisted_content_keys_accept_their_prefix(self) -> None:
        for contract_key, prefix in sync_contracts.CONTENT_REGISTRATION_PREFIXES.items():
            candidate = f"{prefix}contract_test"
            mutated = sync_contracts.mutate_contract_document(
                self.source,
                "register",
                contract_key,
                candidate,
                "受控登记测试",
            )
            self.assertIn(candidate, sync_contracts.extract_contracts(mutated)[contract_key])

    def test_dry_run_does_not_change_project_files(self) -> None:
        before = sync_contracts.CONTRACT_DOC.read_bytes()
        output = io.StringIO()
        with mock.patch(
            "sys.argv",
            [
                "sync_contracts.py",
                "--register",
                "skill_ids",
                "skill_contract_dry_run",
                "--meaning",
                "dry run",
                "--dry-run",
            ],
        ), contextlib.redirect_stdout(output):
            self.assertEqual(sync_contracts.main(), 0)
        self.assertIn("dry-run", output.getvalue())
        self.assertEqual(sync_contracts.CONTRACT_DOC.read_bytes(), before)

    def test_atomic_writer_rolls_back_after_partial_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            first = root / "first.txt"
            second = root / "second.txt"
            first.write_text("first-before\n", encoding="utf-8")
            second.write_text("second-before\n", encoding="utf-8")
            real_replace = os.replace
            replace_count = 0

            def fail_second_promotion(source: str | Path, target: str | Path) -> None:
                nonlocal replace_count
                replace_count += 1
                if replace_count == 2:
                    raise OSError("intentional promotion failure")
                real_replace(source, target)

            with mock.patch.object(sync_contracts, "CONTRACTS_DIR", root / "contracts"), mock.patch.object(
                sync_contracts.os,
                "replace",
                side_effect=fail_second_promotion,
            ):
                with self.assertRaisesRegex(sync_contracts.ContractError, "transaction"):
                    sync_contracts._write_artifacts(
                        {first: "first-after\n", second: "second-after\n"}
                    )
            self.assertEqual(first.read_text(encoding="utf-8"), "first-before\n")
            self.assertEqual(second.read_text(encoding="utf-8"), "second-before\n")


if __name__ == "__main__":
    unittest.main()
