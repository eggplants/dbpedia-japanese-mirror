import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const html = readFileSync(new URL("../src/index.html", import.meta.url), "utf8");
const worker = readFileSync(new URL("../src/index.js", import.meta.url), "utf8");

/** Placeholders the Worker knows how to fill in. */
const substituted = [...worker.matchAll(/replaceAll\("(__[A-Z_]+__)"/g)].map((m) => m[1]);

test("the page and the Worker agree on the placeholder names", () => {
  const inPage = new Set(html.match(/__[A-Z_]+__/g) ?? []);
  assert.ok(inPage.size > 0, "the page should have placeholders");
  for (const name of inPage) {
    assert.ok(substituted.includes(name), `${name} appears in the page but the Worker never fills it in`);
  }
  for (const name of substituted) {
    assert.ok(inPage.has(name), `the Worker fills in ${name} but the page never uses it`);
  }
});

test("nothing is left unsubstituted", () => {
  let out = html;
  for (const name of substituted) out = out.replaceAll(name, "x");
  assert.equal(out.match(/__[A-Z_]+__/g), null);
});

test("the page points the editor at this deployment's endpoint", () => {
  assert.match(html, /<sparql-editor[^>]*endpoint="__ENDPOINT__"/);
  // add-limit keeps the editor from sending unbounded queries, which would land
  // in the strict rate limit bucket on every run.
  assert.match(html, /<sparql-editor[^>]*add-limit="\d+"/);
});

test("the unofficial-mirror notice is present in both languages", () => {
  assert.match(html, /非公式ミラー/);
  assert.match(html, /Unofficial mirror/i);
  assert.match(html, /ja\.dbpedia\.org/);
});

test("the editor is pinned to an exact version", () => {
  assert.match(html, /esm\.sh\/@sib-swiss\/sparql-editor@\d+\.\d+\.\d+"/);
});
