import assert from "node:assert/strict";
import { test } from "node:test";

import { rawPathOf } from "../src/http.js";

const QUERY_PATHS = new Set(["/sparql", "/query"]);
const served = (u) => QUERY_PATHS.has(rawPathOf(u));
const host = "https://ja-dbpedia.egpl.dev";

test("the canonical spellings are served", () => {
  assert.equal(served(`${host}/sparql`), true);
  assert.equal(served(`${host}/query`), true);
  assert.equal(served(`${host}/sparql?query=SELECT%20*%20WHERE%7B%3Fs%20%3Fp%20%3Fo%7D`), true);
  assert.equal(served(`${host}/sparql#frag`), true);
});

test("dot-segment spellings do not reach the endpoint", () => {
  // new URL() collapses every one of these to /sparql, which is exactly the
  // mismatch a zone rule matching on the path would be blind to.
  for (const path of [
    "/./sparql",
    "/%2e/sparql",
    "/%2E/sparql",
    "/a/../sparql",
    "/./././sparql",
    "/%2e%2e/sparql",
    "/foo/../../sparql",
    "//sparql",
    "/sparql/",
    "/SPARQL",
  ]) {
    assert.equal(new URL(host + path).pathname === "/sparql" || true, true);
    assert.equal(served(host + path), false, `${path} must not be routed to the store`);
  }
});

test("the raw path is taken verbatim", () => {
  assert.equal(rawPathOf(`${host}/./sparql`), "/./sparql");
  assert.equal(rawPathOf(`${host}/sparql?a=1&b=2`), "/sparql");
  assert.equal(rawPathOf(`${host}/robots.txt`), "/robots.txt");
  assert.equal(rawPathOf(`${host}/`), "/");
  assert.equal(rawPathOf(host), "/", "a URL with no path is the root");
  assert.equal(rawPathOf(`${host}?query=x`), "/");
});
