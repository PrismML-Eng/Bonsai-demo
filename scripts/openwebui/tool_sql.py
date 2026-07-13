"""
title: Demo Sales Database
description: Read-only SQL access to a demo sales database (SQLite)
"""

import os
import re
import sqlite3

# Set by start_openwebui.sh for the open-webui process (tools run inside it).
DB_PATH = os.environ.get("BONSAI_DEMO_DB", os.path.expanduser("~/.bonsai/demo.db"))
MAX_DETAIL_ROWS = 40


def _without_leading_comments(sql: str) -> str:
    """Return SQL after whitespace and leading -- / /* */ comments."""
    pos = 0
    length = len(sql)
    while pos < length:
        while pos < length and sql[pos].isspace():
            pos += 1
        if sql.startswith("--", pos):
            newline = sql.find("\n", pos + 2)
            if newline < 0:
                return ""
            pos = newline + 1
            continue
        if sql.startswith("/*", pos):
            end = sql.find("*/", pos + 2)
            if end < 0:
                return sql[pos:]
            pos = end + 2
            continue
        break
    return sql[pos:]


class Tools:
    def query_database(self, sql: str) -> str:
        """
        Run a read-only SQL query against the PrismML demo sales database
        using SQLite syntax. The database contains customers, products, orders,
        order_items and support_tickets for a fictional B2B company
        (2024 through mid-2026). Explore the schema first with:
        SELECT name, sql FROM sqlite_master WHERE type='table'

        Send one SELECT or WITH statement per call. For multiple small checks,
        use scalar subqueries or UNION ALL. SQLite strftime() returns zero-padded
        text such as '01'; prefer explicit date ranges, or cast extracted date
        parts to INTEGER before numeric comparisons. Validate derived groupings
        and totals; if an expected category is absent, inspect the underlying or
        distinct derived values before drawing a conclusion.

        Calculate counts, sums, averages and ratios in SQLite rather than copying
        detailed rows and doing arithmetic manually. Results over 40 rows are
        withheld; aggregate, filter, or request a small LIMIT instead. Before the
        final answer, reconcile reported totals with an aggregate query. For
        financial change analysis, test volume, mix and realized price over time,
        quantify each supported driver, and do not stop at the first correlation.

        :param sql: A single read-only SQL query (SELECT / WITH).
        :return: A complete compact text table, or guidance to narrow a result
            that exceeds 40 rows.
        """
        # Enforce the documented contract: a single SELECT/WITH query. The
        # connection is already read-only (mode=ro + query_only); this just
        # trims surface (no PRAGMA/ATTACH/etc.) and gives a clear message.
        stripped = _without_leading_comments(sql).strip().rstrip(";").strip()
        if ";" in stripped:
            return "Only a single SQL statement is allowed."
        if not re.match(r"(?is)^(select|with)\b", stripped):
            return "Only read-only SELECT / WITH queries are allowed."
        try:
            with sqlite3.connect(
                f"file:{DB_PATH}?mode=ro", uri=True, timeout=10
            ) as conn:
                conn.execute("PRAGMA query_only = ON")
                cur = conn.execute(sql)
                cols = [d[0] for d in cur.description] if cur.description else []
                rows = cur.fetchmany(MAX_DETAIL_ROWS + 1)
        except Exception as e:
            return f"SQL error: {e}"

        if not cols:
            return "Query returned no result set."
        if len(rows) > MAX_DETAIL_ROWS:
            return (
                " | ".join(cols)
                + f"\n[more than {MAX_DETAIL_ROWS} rows matched; detailed rows "
                "withheld because manual counting or partial analysis is "
                "error-prone. Aggregate in SQLite with COUNT/SUM/AVG and GROUP "
                "BY, narrow the filters, or request a small LIMIT.]"
            )

        out = [" | ".join(cols)]
        for r in rows:
            out.append(" | ".join("" if v is None else str(v) for v in r))
        out.append(f"[{len(rows)} row{'s' if len(rows) != 1 else ''}]")
        return "\n".join(out)
