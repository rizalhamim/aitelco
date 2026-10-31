"""The column-population profiler must find real numeric columns from the KB.

It exists because a column present in the schema can still be empty in practice, which
makes the SQL writer rank on nothing and return a permanently empty result.
"""
from __future__ import annotations

import pytest

import tools_column_population as tcp


def test_numeric_columns_are_discovered_for_a_known_table():
    cols = tcp.numeric_columns("rham_fwa_site_wise_daily")
    assert cols, "no numeric columns found for a table that certainly has them"
    assert "fwa_net_add_subs" in cols


def test_known_empty_columns_are_still_listed_as_columns():
    # The tool must SHOW sparsely-populated columns, not filter them out: reporting
    # that they are empty is the entire point.
    cols = tcp.numeric_columns("rham_fwa_site_wise_daily")
    assert "fwa_net_add_acq" in cols
    assert "fwa_net_churn90" in cols


def test_string_columns_are_excluded():
    cols = tcp.numeric_columns("rham_fwa_site_wise_daily")
    assert "site_id" not in cols
    assert "kabkota_nm" not in cols


def test_unknown_table_fails_loudly():
    with pytest.raises(SystemExit):
        tcp.numeric_columns("definitely_not_a_table")
