/**
 * Query inspection used by the gateway.
 *
 * These are deliberately lexical, not a parser: the store already runs
 * `serve-read-only`, so the checks here exist to reject a request before it
 * costs container time, not to be the only thing standing between the public
 * and a write. Keeping them in one module makes them testable (see
 * ../test/sparql.test.ts).
 */

/** Whole-token matches, applied only after literals and comments are blanked. */
const UPDATE_TOKENS = /\b(?:INSERT|DELETE|LOAD|CLEAR|DROP|CREATE|ADD|MOVE|COPY|WITH)\b/i;
const SERVICE_TOKEN = /\bSERVICE\b/i;

/**
 * Blanks out comments, IRIs and string literals so that keyword matching cannot
 * be fooled by a token that merely appears inside a literal or a URI.
 * `?s rdfs:label "DELETE from the list"` must stay a legal query.
 */
export function stripLiteralsAndComments(query: string): string {
  let out = "";
  let i = 0;
  while (i < query.length) {
    const c = query[i] ?? "";

    if (c === "#") {
      while (i < query.length && query[i] !== "\n") i++;
      out += " ";
      continue;
    }

    if (c === "<") {
      // An IRIREF cannot contain whitespace or any of <>"{}|^`\
      let j = i + 1;
      while (j < query.length && !/[\s<>"{}|^`\\]/.test(query[j] ?? "")) j++;
      if (query[j] === ">") {
        out += " ";
        i = j + 1;
        continue;
      }
      out += c;
      i++;
      continue;
    }

    if (c === '"' || c === "'") {
      const delim = query.slice(i, i + 3) === c.repeat(3) ? c.repeat(3) : c;
      let j = i + delim.length;
      while (j < query.length) {
        if (query[j] === "\\") {
          j += 2;
          continue;
        }
        if (query.slice(j, j + delim.length) === delim) {
          j += delim.length;
          break;
        }
        j++;
      }
      out += " ";
      i = j;
      continue;
    }

    out += c;
    i++;
  }
  return out;
}

export function isUpdate(bare: string): boolean {
  return UPDATE_TOKENS.test(bare);
}

export function isFederated(bare: string): boolean {
  return SERVICE_TOKEN.test(bare);
}

/**
 * A cheap stand-in for query planning. Anything that can walk the whole graph
 * gets charged against the stricter rate limit bucket.
 */
export function looksExpensive(bare: string): boolean {
  const hasLimit = /\bLIMIT\s+\d+/i.test(bare);
  const hasAggregate = /\b(?:COUNT|SUM|AVG|MIN|MAX|GROUP_CONCAT|SAMPLE)\s*\(/i.test(bare);
  const hasTextScan = /\b(?:REGEX|CONTAINS|STRSTARTS|STRENDS)\s*\(/i.test(bare);
  return !hasLimit || hasAggregate || hasTextScan;
}

/**
 * Collapses the SPARQL protocol's several ways of asking for a result format
 * into the single media type forwarded to Oxigraph and folded into the cache key.
 */
export function normalizeAccept(accept: string | null, format: string | null): string {
  if (format === "json") return "application/sparql-results+json";
  if (format === "xml") return "application/sparql-results+xml";
  if (format === "csv") return "text/csv";
  if (format === "tsv") return "text/tab-separated-values";
  if (!accept || accept.trim() === "" || accept.trim() === "*/*") {
    return "application/sparql-results+json";
  }
  return (accept.split(",")[0] ?? "").trim();
}
