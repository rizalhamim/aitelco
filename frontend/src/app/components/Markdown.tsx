"use client";
/* Minimal, dependency-free markdown renderer covering what the LLM emits:
 * - # / ## / ### headings
 * - paragraphs
 * - **bold**, *italic*, `code`
 * - bullet lists (-) and numbered lists
 * - markdown tables (| ... |)
 * Safe: no raw HTML pass-through.
 */
import React from "react";

function inline(text: string): React.ReactNode[] {
  const nodes: React.ReactNode[] = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`|\*[^*]+\*)/g;
  let last = 0;
  let m: RegExpExecArray | null;
  let key = 0;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) nodes.push(text.slice(last, m.index));
    const tok = m[0];
    if (tok.startsWith("**")) nodes.push(<strong key={key++}>{tok.slice(2, -2)}</strong>);
    else if (tok.startsWith("`")) nodes.push(<code key={key++}>{tok.slice(1, -1)}</code>);
    else if (tok.startsWith("*")) nodes.push(<span key={key++} style={{ fontWeight: 500 }}>{tok.slice(1, -1)}</span>);
    last = m.index + tok.length;
  }
  if (last < text.length) nodes.push(text.slice(last));
  return nodes;
}

export default function Markdown({ text }: { text: string }) {
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  const out: React.ReactNode[] = [];
  let i = 0;
  let key = 0;

  while (i < lines.length) {
    const ln = lines[i];

    // blank
    if (!ln.trim()) { i++; continue; }

    // table block
    if (ln.trim().startsWith("|") && i + 1 < lines.length && /^\s*\|?\s*[-:|\s]+\|/.test(lines[i + 1])) {
      const headerCells = ln.split("|").map((c) => c.trim()).filter(Boolean);
      i += 2;
      const bodyRows: string[][] = [];
      while (i < lines.length && lines[i].trim().startsWith("|")) {
        bodyRows.push(lines[i].split("|").map((c) => c.trim()).filter((_, idx, arr) => idx > 0 && idx < arr.length - 1 || (arr[0] !== "" || arr[arr.length - 1] !== "")).slice(0, headerCells.length));
        i++;
      }
      out.push(
        <table key={key++} className="tnum">
          <thead><tr>{headerCells.map((h, k) => <th key={k}>{inline(h)}</th>)}</tr></thead>
          <tbody>
            {bodyRows.map((row, ri) => (
              <tr key={ri}>{row.map((c, ci) => <td key={ci}>{inline(c)}</td>)}</tr>
            ))}
          </tbody>
        </table>,
      );
      continue;
    }

    // heading
    const h = /^(#{1,3})\s+(.*)$/.exec(ln);
    if (h) {
      const level = h[1].length;
      const text = h[2];
      if (level === 1) out.push(<h1 key={key++}>{inline(text)}</h1>);
      else if (level === 2) out.push(<h2 key={key++}>{inline(text)}</h2>);
      else out.push(<h3 key={key++}>{inline(text)}</h3>);
      i++; continue;
    }

    // unordered list
    if (/^\s*[-•]\s+/.test(ln)) {
      const items: string[] = [];
      while (i < lines.length && /^\s*[-•]\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*[-•]\s+/, ""));
        i++;
      }
      out.push(<ul key={key++}>{items.map((it, ii) => <li key={ii}>{inline(it)}</li>)}</ul>);
      continue;
    }

    // ordered list
    if (/^\s*\d+\.\s+/.test(ln)) {
      const items: string[] = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*\d+\.\s+/, ""));
        i++;
      }
      out.push(<ol key={key++}>{items.map((it, ii) => <li key={ii}>{inline(it)}</li>)}</ol>);
      continue;
    }

    // paragraph (collect until blank)
    const paraLines: string[] = [ln];
    i++;
    while (i < lines.length && lines[i].trim() && !/^(#{1,3}\s|\s*[-•\d]+\.?\s|\|)/.test(lines[i])) {
      paraLines.push(lines[i]);
      i++;
    }
    out.push(<p key={key++}>{inline(paraLines.join(" "))}</p>);
  }

  return <div className="answer">{out}</div>;
}
