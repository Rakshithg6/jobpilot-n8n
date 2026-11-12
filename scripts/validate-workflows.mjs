#!/usr/bin/env node
// Structural validator for n8n workflow JSON.
// Catches the mistakes that make an import silently half-broken:
// duplicate node names, connections pointing at nodes that do not exist,
// nodes without a type/typeVersion/position, missing triggers.
//
//   node scripts/validate-workflows.mjs
//
// Exit code 1 on error, 0 when clean. Warnings never fail the build.

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const DIR = 'workflows';
const TRIGGER_TYPES = /Trigger$|^n8n-nodes-base\.manualTrigger$|^n8n-nodes-base\.errorTrigger$|^n8n-nodes-base\.webhook$/;

let errors = 0;
let warnings = 0;
const fail = (f, msg) => { errors++; console.log(`  ERROR   ${f}: ${msg}`); };
const warn = (f, msg) => { warnings++; console.log(`  warning ${f}: ${msg}`); };

const files = readdirSync(DIR).filter((f) => f.endsWith('.json')).sort();
if (!files.length) {
  console.error(`No workflow JSON found in ${DIR}/`);
  process.exit(1);
}

for (const file of files) {
  console.log(`\n${file}`);
  let wf;
  try {
    wf = JSON.parse(readFileSync(join(DIR, file), 'utf8'));
  } catch (e) {
    fail(file, `invalid JSON - ${e.message}`);
    continue;
  }

  if (!wf.name) fail(file, 'workflow has no name');
  if (!Array.isArray(wf.nodes) || !wf.nodes.length) {
    fail(file, 'workflow has no nodes');
    continue;
  }
  if (!wf.connections || typeof wf.connections !== 'object') fail(file, 'workflow has no connections object');

  const names = new Set();
  const ids = new Set();
  for (const n of wf.nodes) {
    if (!n.name) fail(file, 'a node has no name');
    else if (names.has(n.name)) fail(file, `duplicate node name "${n.name}"`);
    else names.add(n.name);

    if (!n.id) fail(file, `node "${n.name}" has no id`);
    else if (ids.has(n.id)) fail(file, `duplicate node id on "${n.name}"`);
    else ids.add(n.id);

    if (!n.type) fail(file, `node "${n.name}" has no type`);
    if (n.typeVersion === undefined) fail(file, `node "${n.name}" has no typeVersion`);
    if (!Array.isArray(n.position) || n.position.length !== 2) fail(file, `node "${n.name}" has no [x,y] position`);
    if (n.type === 'n8n-nodes-base.postgres' && !n.credentials?.postgres?.name) {
      warn(file, `node "${n.name}" has no named Postgres credential`);
    }
  }

  let triggers = 0;
  for (const n of wf.nodes) if (n.type && TRIGGER_TYPES.test(n.type)) triggers++;
  if (!triggers) fail(file, 'workflow has no trigger node');

  const connected = new Set();
  for (const [source, outputs] of Object.entries(wf.connections || {})) {
    if (!names.has(source)) fail(file, `connection from unknown node "${source}"`);
    connected.add(source);
    for (const branches of Object.values(outputs)) {
      if (!Array.isArray(branches)) { fail(file, `malformed connection from "${source}"`); continue; }
      for (const branch of branches) {
        if (!Array.isArray(branch)) { fail(file, `malformed branch from "${source}"`); continue; }
        for (const edge of branch) {
          if (!edge?.node) fail(file, `connection from "${source}" has no target`);
          else if (!names.has(edge.node)) fail(file, `connection from "${source}" points at missing node "${edge.node}"`);
          else connected.add(edge.node);
        }
      }
    }
  }

  for (const n of wf.nodes) {
    if (!connected.has(n.name)) warn(file, `node "${n.name}" is not connected to anything`);
  }

  console.log(`  ${wf.nodes.length} nodes, ${Object.keys(wf.connections || {}).length} sources, ${triggers} trigger(s)`);
}

console.log(`\n${files.length} workflows checked - ${errors} error(s), ${warnings} warning(s)`);
process.exit(errors ? 1 : 0);
