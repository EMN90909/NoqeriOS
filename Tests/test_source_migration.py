#!/usr/bin/env python3
"""Regression tests for source migration without requiring the compiler."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "Tools/migrate_sources.py"
spec = importlib.util.spec_from_file_location("migrate_sources", SCRIPT)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class SourceMigrationTests(unittest.TestCase):
    def test_imports_and_source_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entry = root / "Kernel/main.nqr"
            entry.parent.mkdir(parents=True)
            original = 'module os.kernel\nimport "memory.nqr"\nlet name = "README.nqr"\n'
            entry.write_text(original, encoding="utf-8")
            (root / "Kernel/memory.nqr").write_text("module os.memory\n", encoding="utf-8")
            result = migration.migrate(root, root / "build/source")
            self.assertEqual(result, 2)
            migrated = (root / "build/source/Kernel/main.noqeri").read_text()
            self.assertIn('import "memory.noqeri"', migrated)
            self.assertIn('"README.nqr"', migrated)
            self.assertEqual(entry.read_text(), original)

    def test_missing_entry_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "helper.nqr").write_text("module helper\n")
            with self.assertRaises(ValueError):
                migration.migrate(root, root / "build/source")


if __name__ == "__main__":
    unittest.main()
