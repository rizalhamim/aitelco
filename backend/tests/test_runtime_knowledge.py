from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from app import config, knowledge, memory, orchestrator
from app.bigquery_tool import QueryError, validate_sql
from app.result_profiler import profile_result


class RuntimeKnowledgeTests(unittest.TestCase):
    def test_governance_covers_live_inventory(self):
        # Asserting a fixed object count made every legitimate table addition a
        # test edit, and still proved nothing about coverage. Assert the
        # invariants instead: the saved catalog and the governance registry have
        # to describe the same dataset.
        governance = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())
        catalog = json.loads(config.TABLE_CATALOG_PATH.read_text())
        governed = governance["objects"]
        self.assertTrue(all(
            record["lifecycle"] in {
                "approved", "candidate", "quarantined", "rejected", "superseded"
            }
            for record in governed.values()
        ))
        for name in (item["name"] for item in catalog["tables"]):
            self.assertIn(name, governed,
                          f"live object {name} has no governance decision")

    def test_every_governance_lifecycle_uses_its_required_policy(self):
        governed = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())["objects"]
        required = {
            "approved": "runtime_allowed",
            "candidate": "not_runtime_allowed",
            "quarantined": "hard_block",
            "rejected": "hard_block",
            "superseded": "hard_block",
        }
        for name, record in governed.items():
            self.assertEqual(required[record["lifecycle"]], record["policy"],
                             f"{name} has a policy its lifecycle forbids")

    def test_every_kb_table_is_approved_and_owned_by_exactly_one_domain(self):
        governed = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())["objects"]
        kb = knowledge.load_kb()
        owners: dict[str, list[str]] = {}
        for domain_key, domain in kb["domains"].items():
            for name in domain.get("tables", {}):
                owners.setdefault(name, []).append(domain_key)
        for name, domains in owners.items():
            self.assertEqual(1, len(domains), f"{name} is owned by {domains}")
            self.assertIn(name, governed, f"{name} has no governance decision")
            self.assertEqual("approved", governed[name]["lifecycle"], name)
            self.assertEqual(governed[name]["domain"], domains[0], name)

    def test_no_blocked_object_reaches_the_runtime_kb(self):
        governed = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())["objects"]
        approved = knowledge.approved_table_names()
        for name, record in governed.items():
            if record["lifecycle"] != "approved":
                self.assertNotIn(name, approved,
                                 f"{record['lifecycle']} table {name} is queryable")

    def test_a_superseded_object_names_its_replacement(self):
        governed = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())["objects"]
        for name, record in governed.items():
            if record["lifecycle"] == "superseded":
                self.assertTrue(record.get("replacement_table"),
                                f"{name} is superseded but names no replacement")

    def test_deleted_bigquery_tables_are_not_offered_to_the_agent(self):
        # These three were still in the runtime KB after being dropped from
        # BigQuery, so the agent was shown the schema of tables that no longer
        # existed and every query against them failed at execution.
        approved = knowledge.approved_table_names()
        for name in ("rham_subs_traffic_agg_geo_mtd_lmtd",
                     "rham_subs_traffic_agg_segment_mtd_lmtd",
                     "rham_subs_traffic_agg_migration_matrix_monthly"):
            self.assertNotIn(name, approved)

    def test_legacy_kpi_sources_are_replaced(self):
        approved = knowledge.approved_table_names()
        governed = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())["objects"]
        replacements = {
            "rham_kpi_highlevel_dly": "rham_mkt_kpi_highlevel_dly",
            "rham_kpi_highlevel_mtd": "rham_mkt_highlevel_mtd",
            "rham_kpi_highlevel_mth": "rham_mkt_highlevel_mth",
        }
        for legacy, replacement in replacements.items():
            self.assertNotIn(legacy, approved)
            self.assertIn(replacement, approved)
            self.assertEqual("superseded", governed[legacy]["lifecycle"])
            self.assertEqual("hard_block", governed[legacy]["policy"])
            self.assertEqual(replacement, governed[legacy]["replacement_table"])
            sql = f"SELECT 1 FROM `{config.BQ_PROJECT}.{config.BQ_DATASET}.{legacy}`"
            with self.assertRaises(QueryError):
                validate_sql(sql)

    def test_rejected_tables_are_not_approved(self):
        approved = knowledge.approved_table_names()
        blocked = knowledge.blocked_table_names()
        self.assertIn("rham_fb_ms_kecamatan_v2", blocked)
        self.assertNotIn("rham_fb_ms_kecamatan_v2", approved)
        self.assertNotIn("rham_site_wise_daily_raw", approved)

    def test_question_retrieval_is_bounded(self):
        selection = knowledge.selection_for_question(
            "competitive", "market share IOH per kecamatan bulan terbaru"
        )
        self.assertLessEqual(len(selection["tables"]), config.KNOWLEDGE_TABLE_LIMIT)
        self.assertIn("rham_report_fb_ms_kecamatan", selection["tables"])

    def test_competitive_schema_is_compact(self):
        schema, _ = knowledge.schema_for_question(
            "competitive", "market share IOH per kecamatan bulan terbaru"
        )
        self.assertLess(len(schema), 50000)
        self.assertNotIn("rham_fb_ms_kecamatan_v2", schema)

    def test_query_guard_accepts_approved_table(self):
        sql = (
            "SELECT MAX(month_id) FROM "
            "`data-java-prd-97b9.java_precalc.rham_report_fb_ms_kecamatan`"
        )
        self.assertTrue(validate_sql(sql).startswith("SELECT"))

    def test_query_guard_rejects_banned_table(self):
        sql = (
            "SELECT * FROM "
            "`data-java-prd-97b9.java_precalc.rham_fb_ms_kecamatan_v2`"
        )
        with self.assertRaises(QueryError):
            validate_sql(sql)

    def test_query_guard_rejects_unselected_table(self):
        sql = (
            "SELECT MAX(month_id) FROM "
            "`data-java-prd-97b9.java_precalc.rham_report_fb_ms_kecamatan`"
        )
        with self.assertRaises(QueryError):
            validate_sql(sql, allowed_tables={"rham_report_fb_ms_kabkota"})

    def test_graph_artifact_matches_kb(self):
        health = knowledge.graph_health()
        self.assertEqual("ok", health["status"])
        self.assertGreater(health["nodes"], 1000)

    def test_result_profile_prevents_unverified_ranking(self):
        result = {
            "sql": "SELECT value FROM `data-java-prd-97b9.java_precalc.rham_game_mtd`",
            "columns": ["value"],
            "rows": [{"value": 1}, {"value": 2}],
            "row_count": 2,
            "truncated": True,
        }
        profile = profile_result(result)
        self.assertFalse(profile["profile"]["ranking_verified"])
        self.assertEqual("warning", profile["qa"]["status"])

    def test_routing_edge_needs_three_unique_successes(self):
        original_db = memory.DB_PATH
        with tempfile.TemporaryDirectory() as temp_dir:
            memory.DB_PATH = Path(temp_dir) / "sessions.db"
            try:
                memory.init()
                base_sql = (
                    "SELECT MAX(month_id) FROM "
                    "`data-java-prd-97b9.java_precalc.rham_report_fb_ms_kecamatan`"
                )
                for index in range(3):
                    memory._record_knowledge_evidence(
                        "market share per kecamatan",
                        "competitive",
                        base_sql + f" LIMIT {index + 1}",
                    )
                rows = memory.get_knowledge_routing()
                self.assertTrue(rows)
                self.assertTrue(any(row["state"] == "active" for row in rows))
            finally:
                memory.DB_PATH = original_db

    def test_deterministic_fallback_keeps_result_reachable(self):
        result = {
            "sql": "SELECT 1 AS value",
            "columns": ["value"],
            "rows": [{"value": 1}],
            "row_count": 1,
            "truncated": False,
        }
        answer = orchestrator.deterministic_fallback_answer(result, "id")
        self.assertIn("Hasil terverifikasi", answer)
        self.assertIn("| 1 |", answer)


if __name__ == "__main__":
    unittest.main()
