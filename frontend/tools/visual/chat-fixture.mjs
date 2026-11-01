// The Tanya Agent answer of mockup 02 as a /api/chat/stream event stream.
const okt = [], sep = [];
for (let d = 1; d <= 31; d++) {
  const wk = Math.sin(((d + 2) / 7) * 2 * Math.PI);
  okt.push(+(13.3 + 1.1 * wk + 0.35 * Math.sin(d * 1.7) - (d > 12 && d < 20 ? 0.9 : 0)).toFixed(2));
  if (d <= 30) sep.push(+(14.1 + 1.0 * Math.sin(((d + 1) / 7) * 2 * Math.PI) + 0.3 * Math.cos(d * 1.3)).toFixed(2));
}
const rows = [];
for (let d = 1; d <= 31; d++) {
  rows.push({ hari: d, bulan: "2026-10", revenue: okt[d - 1] * 1e9 });
  if (d <= 30) rows.push({ hari: d, bulan: "2026-09", revenue: sep[d - 1] * 1e9 });
}

export const QUESTION = "Bagaimana performa revenue West Java bulan ini dibanding bulan lalu? Kabupaten mana yang paling turun?";

const TEXT = "Revenue West Java Oktober 2026 **Rp 412,6 M**, turun 2,4% dari September (Rp 422,7 M). Penurunan terbesar di **Garut (−7,9%)** dan **Cianjur (−6,2%)**, sejalan dengan turunnya payload data dan **37 site** yang availability-nya di bawah target 99,5%.";

const ev = (event, data) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;

export function chatStream() {
  return [
    ev("step_start", { step: "router", label: "Orchestrator" }),
    ev("route", { domain: "revenue", reason: "revenue" }),
    ev("step_start", { step: "analyst", label: "Analyst" }),
    ev("analyst", { status: "ok" }),
    ev("sql", { sql: "SELECT hari, bulan, revenue FROM revenue_daily", explanation: "" }),
    ev("result", {
      columns: ["hari", "bulan", "revenue"], rows, row_count: rows.length, sql: "SELECT 1", bytes_processed: 0,
      chart: { type: "line", x: "hari", y: ["revenue"], y2: [], series_by: "bulan", label: null, formats: { revenue: "currency" },
        sort: null, top_n: null, map_key: "kabupaten", alternatives: ["bar"], title: "Revenue harian, Okt vs Sep 2026" },
      kpis: [
        { column: "revenue", label: "Revenue", value: 412.6e9, format: "currency", prev: 422.7e9, delta: -2.39, delta_unit: "%", vs: "2026-09", spark: [412, 418, 425, 431, 422.7, 412.6] },
        { column: "payload_data_pb", label: "Payload data", value: 18.9, format: "number", prev: 19.1, delta: -1.05, delta_unit: "%", vs: "2026-09", spark: [17.6, 18.1, 18.7, 19.3, 19.1, 18.9] },
        { column: "site_di_bawah_target", label: "Site di bawah target", value: 37, format: "number", prev: 28, delta: 32.1, delta_unit: "%", vs: "2026-09", spark: [22, 25, 24, 26, 28, 37] },
      ],
      source: "Dump Performance 1 Nov 05.00",
    }),
    ev("token", { t: TEXT }),
    ev("done", { domain: "revenue", elapsed_ms: 8200 }),
  ].join("");
}
