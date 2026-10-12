import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { test } from "vite-plus/test";

const html = readFileSync(path.join(import.meta.dirname, "../src/suspended.html"), "utf8");
const worker = readFileSync(path.join(import.meta.dirname, "../src/index.ts"), "utf8");

/** Placeholders the Worker knows how to fill in. */
const substituted = [...worker.matchAll(/replaceAll\("(__[A-Z_]+__)"/g)].map((m) => m[1] ?? "");

test("every placeholder in the suspended page is filled in", () => {
  for (const name of new Set(html.match(/__[A-Z_]+__/g) ?? [])) {
    assert.ok(substituted.includes(name), `${name} appears in the page but is never filled in`);
  }
});

test("the suspended page points at the official endpoint in both languages", () => {
  assert.match(html, /停止中です/);
  assert.match(html, /suspended/i);
  assert.match(html, /href="https:\/\/ja\.dbpedia\.org\/sparql"/);
});

test("the suspended page loads nothing from elsewhere", () => {
  assert.doesNotMatch(html, /<script/);
  assert.doesNotMatch(html, /<link[^>]*rel="stylesheet"/);
});

test("the suspended branch comes before anything that reaches the container", () => {
  const branch = worker.indexOf('env.MIRROR_SUSPENDED === "true") {\n      return suspended(');
  assert.ok(branch > 0, "the fetch handler should check MIRROR_SUSPENDED");
  assert.ok(branch < worker.indexOf("queryContainer(env, query, accept)"));
});
