"""End-to-end timing test."""
import time, sys
sys.path.insert(0, "/home/ubuntu/telco-ai/backend")
from app import orchestrator, knowledge, llm, config

q = sys.argv[1] if len(sys.argv) > 1 else "Top 5 kecamatan dengan revenue data tertinggi 30 hari terakhir"
print(f"Q: {q}\n")

t0 = time.time()
r = orchestrator.route(q)
t1 = time.time()
print(f"[{t1-t0:5.1f}s] ROUTE -> domain={r.get('domain')}  lang={r.get('language')}")
print(f"         rephrased: {r.get('rephrased','')[:120]}")

domain = r.get("domain")
kb = knowledge.load_kb()
if domain == "none" or domain not in kb["domains"]:
    print("(no data domain; general reply path)"); sys.exit(0)

sch = knowledge.schema_for_domain(domain)
print(f"         schema text size: {len(sch):,} chars")

t2 = time.time()
gen = orchestrator.write_sql(domain, r.get("rephrased") or q)
t3 = time.time()
print(f"[{t3-t2:5.1f}s] WRITE_SQL")
sql = gen.get("sql","")
print(f"  SQL: {sql[:400]}{'...' if len(sql)>400 else ''}")

from app.bigquery_tool import run_query
t4 = time.time()
try:
    res = run_query(sql)
    t5 = time.time()
    print(f"[{t5-t4:5.1f}s] EXECUTE rows={res['row_count']} bytes={res['bytes_processed']:,}")
except Exception as e:
    t5 = time.time()
    print(f"[{t5-t4:5.1f}s] EXEC ERROR: {str(e)[:200]}")
    sys.exit(1)

t6 = time.time()
final = orchestrator.synthesize(q, res, r.get("language","id"), gen.get("explanation",""))
t7 = time.time()
print(f"[{t7-t6:5.1f}s] SYNTH")
print(f"\nTOTAL: {t7-t0:.1f}s\n")
print("--- ANSWER ---")
print(final[:1200])
