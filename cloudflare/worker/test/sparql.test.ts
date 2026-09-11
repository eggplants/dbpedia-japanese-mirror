import assert from "node:assert/strict";
import { test } from "vite-plus/test";

import {
  isFederated,
  isUpdate,
  looksExpensive,
  normalizeAccept,
  stripLiteralsAndComments,
} from "../src/sparql.ts";

const bare = (q: string): string => stripLiteralsAndComments(q);

test("rejects the SPARQL Update forms", () => {
  for (const q of [
    "INSERT DATA { <a> <b> <c> }",
    "DELETE WHERE { ?s ?p ?o }",
    "LOAD <http://example.org/d>",
    "CLEAR GRAPH <http://ja.dbpedia.org>",
    "DROP GRAPH <http://ja.dbpedia.org>",
    "WITH <http://ja.dbpedia.org> DELETE { ?s ?p ?o } WHERE { ?s ?p ?o }",
    "  insert data { <a> <b> <c> }",
  ]) {
    assert.equal(isUpdate(bare(q)), true, q);
  }
});

test("does not trip on keywords inside literals, IRIs or comments", () => {
  const queries = [
    'SELECT ?s WHERE { ?s rdfs:label "DELETE from the queue"@ja } LIMIT 10',
    "SELECT ?s WHERE { ?s ?p <http://ja.dbpedia.org/resource/INSERT> } LIMIT 10",
    "# DELETE this comment\nSELECT ?s WHERE { ?s ?p ?o } LIMIT 1",
    `SELECT ?s WHERE { ?s rdfs:comment """multi
       line DROP GRAPH""" } LIMIT 5`,
    "SELECT ?s WHERE { ?s rdfs:label 'it\\'s a LOAD of text'@en } LIMIT 5",
  ];
  for (const q of queries) {
    assert.equal(isUpdate(bare(q)), false, q);
  }
});

test("blocks federation", () => {
  assert.equal(
    isFederated(bare("SELECT * WHERE { SERVICE <http://x/> { ?s ?p ?o } } LIMIT 1")),
    true,
  );
  assert.equal(isFederated(bare('SELECT * WHERE { ?s rdfs:label "SERVICE" } LIMIT 1')), false);
});

test("classifies expensive queries", () => {
  assert.equal(looksExpensive(bare("SELECT * WHERE { ?s ?p ?o }")), true, "no LIMIT");
  assert.equal(
    looksExpensive(bare("SELECT (COUNT(*) AS ?c) WHERE { ?s ?p ?o } LIMIT 1")),
    true,
    "aggregate",
  );
  assert.equal(
    looksExpensive(
      bare('SELECT ?s WHERE { ?s rdfs:label ?l FILTER(REGEX(?l, "^東京")) } LIMIT 10'),
    ),
    true,
    "regex",
  );
  assert.equal(
    looksExpensive(
      bare("SELECT ?o WHERE { <http://ja.dbpedia.org/resource/日本> rdfs:label ?o } LIMIT 20"),
    ),
    false,
    "bound subject with a LIMIT",
  );
});

test("normalizes the requested result format", () => {
  assert.equal(normalizeAccept(null, null), "application/sparql-results+json");
  assert.equal(normalizeAccept("*/*", null), "application/sparql-results+json");
  assert.equal(normalizeAccept(null, "xml"), "application/sparql-results+xml");
  assert.equal(normalizeAccept("text/csv, */*;q=0.1", null), "text/csv");
  assert.equal(normalizeAccept("application/sparql-results+json", "csv"), "text/csv");
});

test("an unterminated literal does not hang or leak the tail", () => {
  const q = 'SELECT ?s WHERE { ?s rdfs:label "unterminated DELETE';
  assert.equal(isUpdate(bare(q)), false);
});
