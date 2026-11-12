#!/usr/bin/env node
// Offline evaluation of the ranking policy against your hand labels.
//
//   1. psql export:   ./scripts/export-scores.ps1
//   2. hand label:    eval/labels.csv   (fingerprint,label)
//   3. run:           node eval/evaluate.mjs
//
// Produces precision@k and recall@k, which is the number you put in the README.
// Without this, "the AI ranks jobs" is a claim. With it, it is a measurement.

import { readFileSync, existsSync } from 'node:fs';

const parse = (text) =>
  text
    .split(/\r?\n/)
    .filter((l) => l.trim() && !l.trim().startsWith('#'))
    .map((l) => l.split(',').map((c) => c.trim()));

const readCsv = (path) => {
  if (!existsSync(path)) {
    console.error(`Missing ${path}`);
    process.exit(1);
  }
  const [header, ...rows] = parse(readFileSync(path, 'utf8'));
  return rows.map((r) => Object.fromEntries(header.map((h, i) => [h, r[i]])));
};

const labels = readCsv('eval/labels.csv');
const scores = readCsv('eval/scores.csv');

const truth = new Map(labels.map((r) => [r.fingerprint, Number(r.label) === 1]));

const ranked = scores
  .filter((r) => truth.has(r.fingerprint))
  .map((r) => ({ ...r, score: Number(r.score), position: Number(r.position) }))
  .sort((a, b) => a.position - b.position);

if (!ranked.length) {
  console.error('No overlap between labels.csv and scores.csv. Re-run the export after ingesting.');
  process.exit(1);
}

const positives = ranked.filter((r) => truth.get(r.fingerprint)).length;
const pad = (s, n) => String(s).padEnd(n);

console.log(`\nLabeled jobs in ranking: ${ranked.length}   relevant: ${positives}\n`);
console.log(pad('k', 5) + pad('precision@k', 14) + 'recall@k');
for (const k of [5, 10, 20]) {
  const top = ranked.slice(0, k);
  const hits = top.filter((r) => truth.get(r.fingerprint)).length;
  console.log(pad(k, 5) + pad(`${hits}/${top.length} = ${top.length ? (hits / top.length).toFixed(2) : '0.00'}  `.slice(0, 13), 14) + (positives ? (hits / positives).toFixed(2) : '0.00'));
}

console.log('\nThreshold sweep (score >= t):');
console.log(pad('t', 5) + pad('flagged', 10) + pad('precision', 12) + 'recall');
for (const t of [50, 60, 70, 80, 90]) {
  const flagged = ranked.filter((r) => r.score >= t);
  const hits = flagged.filter((r) => truth.get(r.fingerprint)).length;
  console.log(
    pad(t, 5) +
      pad(flagged.length, 10) +
      pad(flagged.length ? (hits / flagged.length).toFixed(2) : '0.00', 12) +
      (positives ? (hits / positives).toFixed(2) : '0.00')
  );
}

console.log('\nPick the threshold whose precision you can defend in an interview.\n');
