/**
 * Path handling for the gateway.
 *
 * Routing uses the path exactly as it arrived, not `new URL(...).pathname`.
 * The WHATWG URL parser collapses dot segments — `/./sparql`, `/%2e/sparql`,
 * `/a/../sparql` and `/foo/../../sparql` all parse to `/sparql` — so routing on
 * `pathname` would serve the endpoint under spellings that a zone rule matching
 * on `http.request.uri.path` might not recognise.
 *
 * Cloudflare's "Normalize incoming URLs" setting removes those dot segments
 * before the WAF, rate limiting rules and the Worker ever see them, and it
 * defaults to on (terraform/security.tf pins it). This module exists so that the
 * Worker is right regardless: one exact spelling per route, whatever the zone
 * setting happens to be.
 */

/**
 * The path as written in the request line, with no normalization applied.
 * Returns "/" when the URL carries no path at all.
 */
export function rawPathOf(requestUrl: string): string {
  // Strip scheme and authority, then anything from the first ? or #.
  const afterAuthority = requestUrl.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^/?#]*/, "");
  const path = afterAuthority.split(/[?#]/, 1)[0] ?? "";
  return path === "" ? "/" : path;
}

/**
 * True when the path is one exact, canonical spelling. Anything else — a dot
 * segment, a percent-encoded dot, a doubled slash, a trailing slash, a different
 * case — is not this route.
 */
export function isCanonicalPath(rawPath: string, allowed: ReadonlySet<string>): boolean {
  return allowed.has(rawPath);
}
