/**
 * SPARQL gateway for the DBpedia Japanese mirror.
 *
 * The Worker is the only public surface. It serves the landing page, validates
 * queries, applies rate limits, answers from the edge cache, and forwards the
 * misses to an Oxigraph container running `serve-read-only` on port 7878.
 *
 * Everything the container exposes besides the query endpoint is hidden: a bare
 * `GET /store` on Oxigraph streams the whole dataset, which is not something a
 * public mirror wants to hand out on every request.
 */
import { Container, getContainer } from "@cloudflare/containers";

import landingPage from "./index.html";
import { rawPathOf } from "./http.js";
import {
  isFederated,
  isUpdate,
  looksExpensive,
  normalizeAccept,
  stripLiteralsAndComments,
} from "./sparql.js";

/** Oxigraph reads the store from /srv/db; see ../../container/Dockerfile. */
export class OxigraphContainer extends Container {
  defaultPort = 7878;
  sleepAfter = "20m";

  constructor(ctx, env) {
    super(ctx, env);
    if (env.CONTAINER_SLEEP_AFTER) {
      this.sleepAfter = env.CONTAINER_SLEEP_AFTER;
    }
  }

  onStart() {
    console.log("oxigraph: container started");
  }

  onStop({ exitCode, reason }) {
    console.log(`oxigraph: container stopped (exit=${exitCode}, reason=${reason})`);
  }

  onError(error) {
    console.error("oxigraph: container error", error);
    throw error;
  }
}

/**
 * Paths served to the public, matched against the raw request path. Everything
 * else is a 404 — including non-canonical spellings of these same paths; see
 * ./http.js for why that matters.
 */
const QUERY_PATHS = new Set(["/sparql", "/query"]);
const PAGE_PATHS = new Set(["/", "/index.html"]);

const DEFAULTS = {
  MAX_QUERY_BYTES: 8192,
  CACHE_TTL: 86400,
  BROWSER_TTL: 300,
  CONTAINER_POOL_SIZE: 1,
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = rawPathOf(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }
    if (path === "/health") {
      return json({ ok: true, dataset: env.DATASET_VERSION ?? null });
    }
    if (path === "/robots.txt") {
      return robotsTxt();
    }
    if (PAGE_PATHS.has(path)) {
      return renderLandingPage(url, env);
    }
    if (!QUERY_PATHS.has(path)) {
      return fail(404, "not_found", "This endpoint only serves SPARQL queries at /sparql.");
    }
    if (request.method !== "GET" && request.method !== "POST") {
      return fail(405, "method_not_allowed", "Use GET or POST.");
    }

    let parsed;
    try {
      parsed = await readProtocolRequest(request, url);
    } catch (error) {
      return fail(400, "bad_request", String(error.message ?? error));
    }
    if (!parsed.query) {
      return fail(400, "missing_query", "No 'query' parameter was given.");
    }

    const maxBytes = num(env.MAX_QUERY_BYTES, DEFAULTS.MAX_QUERY_BYTES);
    if (new TextEncoder().encode(parsed.query).length > maxBytes) {
      return fail(413, "query_too_long", `The query exceeds ${maxBytes} bytes.`);
    }

    const bare = stripLiteralsAndComments(parsed.query);
    if (isUpdate(bare)) {
      return fail(403, "read_only", "This endpoint is read-only; SPARQL Update is not accepted.");
    }
    if (isFederated(bare)) {
      return fail(403, "no_federation", "SERVICE (federated query) is not accepted.");
    }

    const accept = normalizeAccept(request.headers.get("accept"), parsed.format);
    const cacheKey = await buildCacheKey(url, env, parsed, accept);
    const cache = caches.default;

    // The cache lookup comes before the rate limits on purpose. A hit costs no
    // container time, so charging for it would punish exactly the traffic this
    // mirror wants — a client polling the same query, or the editor's metadata
    // queries on every page load. The zone-level rule in security.tf is what
    // caps a flood of cached requests.
    const hit = await cache.match(cacheKey);
    if (hit) {
      return decorate(hit, { "x-cache": "HIT" });
    }

    const clientIp = request.headers.get("cf-connecting-ip") ?? "unknown";
    const expensive = looksExpensive(bare);
    const limited = await applyRateLimits(env, clientIp, expensive);
    if (limited) {
      return fail(429, "rate_limited", limited, { "retry-after": "60" });
    }

    let upstream;
    try {
      upstream = await queryContainer(env, parsed, accept);
    } catch (error) {
      console.error("oxigraph: upstream failure", error);
      return fail(502, "upstream_error", "The store did not answer in time. Try again shortly.");
    }

    if (!upstream.ok) {
      // Oxigraph reports malformed queries as 400; do not cache those.
      const body = await upstream.text();
      return decorate(
        new Response(body, {
          status: upstream.status,
          headers: { "content-type": upstream.headers.get("content-type") ?? "text/plain" },
        }),
        { "x-cache": "BYPASS" },
      );
    }

    const edgeTtl = num(env.CACHE_TTL, DEFAULTS.CACHE_TTL);
    const browserTtl = num(env.BROWSER_TTL, DEFAULTS.BROWSER_TTL);
    const cacheable = new Response(upstream.body, upstream);
    cacheable.headers.set(
      "cache-control",
      `public, max-age=${browserTtl}, s-maxage=${edgeTtl}, stale-while-revalidate=${edgeTtl}`,
    );
    cacheable.headers.delete("set-cookie");

    const [toCache, toReturn] = [cacheable.clone(), cacheable];
    ctx.waitUntil(cache.put(cacheKey, toCache));
    return decorate(toReturn, { "x-cache": "MISS" });
  },
};

/**
 * The landing page: the SPARQL editor plus the notice that this is an
 * unofficial mirror. The endpoint URL is filled in from the request rather than
 * configured, so the page is correct on whatever hostname it is served from.
 */
function renderLandingPage(url, env) {
  const html = landingPage
    .replaceAll("__ENDPOINT__", `${url.origin}/sparql`)
    .replaceAll("__DATASET_VERSION__", env.DATASET_VERSION ?? "unknown")
    .replaceAll("__SOURCE_REPOSITORY__", env.SOURCE_REPOSITORY ?? "");

  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      // Short, so the notice and the dataset version can be corrected quickly.
      "cache-control": "public, max-age=300, s-maxage=3600",
      "x-content-type-options": "nosniff",
      "referrer-policy": "strict-origin-when-cross-origin",
    },
  });
}

/**
 * Crawlers are welcome on the page and not on the endpoint: a crawler walking
 * query URLs would spend container time on results nobody reads.
 */
function robotsTxt() {
  const body = ["User-agent: *", "Allow: /$", "Disallow: /sparql", "Disallow: /query", ""].join("\n");
  return new Response(body, {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "public, max-age=86400",
    },
  });
}

/**
 * Reads a query out of the three shapes the SPARQL 1.1 protocol allows.
 */
async function readProtocolRequest(request, url) {
  if (request.method === "GET") {
    return {
      query: url.searchParams.get("query"),
      format: url.searchParams.get("format"),
      defaultGraphUri: url.searchParams.getAll("default-graph-uri"),
      namedGraphUri: url.searchParams.getAll("named-graph-uri"),
    };
  }

  const contentType = (request.headers.get("content-type") ?? "").split(";")[0].trim();
  if (contentType === "application/sparql-query") {
    return {
      query: await request.text(),
      format: url.searchParams.get("format"),
      defaultGraphUri: url.searchParams.getAll("default-graph-uri"),
      namedGraphUri: url.searchParams.getAll("named-graph-uri"),
    };
  }
  if (contentType === "application/x-www-form-urlencoded") {
    const form = new URLSearchParams(await request.text());
    if (form.has("update")) {
      throw new Error("This endpoint is read-only; SPARQL Update is not accepted.");
    }
    return {
      query: form.get("query"),
      format: form.get("format") ?? url.searchParams.get("format"),
      defaultGraphUri: form.getAll("default-graph-uri"),
      namedGraphUri: form.getAll("named-graph-uri"),
    };
  }
  throw new Error(`Unsupported Content-Type: ${contentType || "(none)"}`);
}

/**
 * Three buckets: a burst window, a sustained window, and a much smaller one that
 * only the expensive queries draw from. Bindings that are not configured are
 * skipped, so the Worker still runs with rate limiting turned off.
 */
async function applyRateLimits(env, clientIp, expensive) {
  const buckets = [
    [env.RL_BURST, `burst:${clientIp}`, "Too many requests in a short window."],
    [env.RL_SUSTAINED, `sustained:${clientIp}`, "Sustained request rate exceeded."],
  ];
  if (expensive) {
    buckets.push([
      env.RL_HEAVY,
      `heavy:${clientIp}`,
      "Too many expensive queries. Add a LIMIT clause or bind more of the pattern.",
    ]);
  }

  for (const [limiter, key, message] of buckets) {
    if (!limiter) continue;
    const { success } = await limiter.limit({ key });
    if (!success) return message;
  }
  return null;
}

/**
 * The dataset is immutable for a given DUMP_VERSION, so the query text is the
 * whole cache key. The key stays on the request's own hostname: the Cache API
 * refuses to store a response under a host the zone does not own.
 */
async function buildCacheKey(url, env, parsed, accept) {
  const canonical = JSON.stringify({
    q: parsed.query.replace(/\s+/g, " ").trim(),
    d: [...parsed.defaultGraphUri].sort(),
    n: [...parsed.namedGraphUri].sort(),
    a: accept,
  });
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");

  const key = new URL(url.toString());
  key.pathname = "/__sparql_cache";
  key.search = `?v=${encodeURIComponent(env.DATASET_VERSION ?? "0")}&h=${hex}`;
  return new Request(key.toString(), { method: "GET" });
}

/**
 * Forwards to the container. Short queries go as GET so that a container-side
 * proxy or log stays readable; long ones go as a POST body to stay clear of URL
 * length limits.
 */
async function queryContainer(env, parsed, accept) {
  const target = new URL("http://oxigraph/query");
  for (const value of parsed.defaultGraphUri) target.searchParams.append("default-graph-uri", value);
  for (const value of parsed.namedGraphUri) target.searchParams.append("named-graph-uri", value);

  const headers = { accept };
  const encoded = encodeURIComponent(parsed.query);

  let init;
  if (encoded.length <= 4000) {
    target.searchParams.set("query", parsed.query);
    init = { method: "GET", headers };
  } else {
    init = {
      method: "POST",
      headers: { ...headers, "content-type": "application/sparql-query" },
      body: parsed.query,
    };
  }

  const container = getContainer(env.OXIGRAPH, pickInstance(env));
  return container.fetch(new Request(target.toString(), init));
}

/**
 * Every instance holds the same read-only store, so any of them can answer.
 * A pool of 1 keeps a single instance warm, which is what low traffic wants;
 * raise CONTAINER_POOL_SIZE to spread load once the endpoint is busy enough
 * that the instances stay warm anyway.
 */
function pickInstance(env) {
  const size = Math.max(1, num(env.CONTAINER_POOL_SIZE, DEFAULTS.CONTAINER_POOL_SIZE));
  if (size === 1) return "oxigraph-0";
  return `oxigraph-${Math.floor(Math.random() * size)}`;
}

function corsHeaders() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "accept, content-type",
    "access-control-max-age": "86400",
  };
}

function decorate(response, extra) {
  const out = new Response(response.body, response);
  for (const [k, v] of Object.entries({ ...corsHeaders(), ...extra })) {
    out.headers.set(k, v);
  }
  return out;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders() },
  });
}

function fail(status, code, message, extra = {}) {
  return new Response(JSON.stringify({ error: code, message }), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      ...corsHeaders(),
      ...extra,
    },
  });
}

function num(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
