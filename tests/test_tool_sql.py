import importlib.util
import pathlib
import sqlite3
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "tool_sql", ROOT / "scripts" / "openwebui" / "tool_sql.py"
)
sql_tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sql_tool)


class SqlToolDescriptionTests(unittest.TestCase):
    def test_description_names_dialect_and_common_date_trap(self):
        description = sql_tool.Tools.query_database.__doc__

        self.assertIn("SQLite syntax", description)
        self.assertIn("zero-padded", description)
        self.assertIn("cast extracted date", description)
        self.assertIn("expected category is absent", description)
        self.assertIn("arithmetic manually", description)
        self.assertIn("volume, mix and realized price", description)


class SqlToolBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.db = tempfile.NamedTemporaryFile(suffix=".db")
        with sqlite3.connect(self.db.name) as conn:
            conn.execute("CREATE TABLE numbers (value INTEGER)")
            conn.executemany(
                "INSERT INTO numbers VALUES (?)", ((n,) for n in range(50))
            )
        self.original_db_path = sql_tool.DB_PATH
        sql_tool.DB_PATH = self.db.name

    def tearDown(self):
        sql_tool.DB_PATH = self.original_db_path
        self.db.close()

    def test_leading_line_and_block_comments_are_allowed(self):
        tool = sql_tool.Tools()

        line_result = tool.query_database("-- explain query\nSELECT COUNT(*) AS n FROM numbers")
        block_result = tool.query_database("/* explain query */ SELECT 1 AS n")

        self.assertIn("n\n50", line_result)
        self.assertIn("n\n1", block_result)

    def test_large_detailed_results_are_withheld(self):
        result = sql_tool.Tools().query_database(
            "SELECT value FROM numbers ORDER BY value"
        )

        self.assertIn("more than 40 rows matched", result)
        self.assertIn("Aggregate in SQLite", result)
        self.assertNotIn("\n39\n", result)

    def test_small_results_include_completeness_marker(self):
        result = sql_tool.Tools().query_database(
            "SELECT value FROM numbers WHERE value < 3 ORDER BY value"
        )

        self.assertEqual(result, "value\n0\n1\n2\n[3 rows]")


if __name__ == "__main__":
    unittest.main()
