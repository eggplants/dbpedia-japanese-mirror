// @cloudflare/component-icon ships its icons only as React components, so this
// renders each one to markup and repacks them as an Iconify icon set
// (https://iconify.design/docs/types/iconify-json.html), which is what Mermaid
// takes in registerIconPacks. Diagrams then refer to them as `cf:<name>`, with
// the names the package uses for its `type` prop ("workers-durable-objects").
import { createRequire } from "node:module";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server.js";

const require = createRequire(import.meta.url);
const components = require("@cloudflare/component-icon/lib/reactsvgs").default;

export const PREFIX = "cf";

export function iconSet() {
  const icons = {};
  for (const [name, Component] of Object.entries(components)) {
    const markup = renderToStaticMarkup(React.createElement(Component));
    const match = markup.match(/^<svg([^>]*)>(.*)<\/svg>$/s);
    if (!match) {
      throw new Error(`${name}: unexpected markup: ${markup.slice(0, 80)}`);
    }
    const [, attributes, body] = match;
    const viewBox = attributes.match(/viewBox="([^"]+)"/);
    if (!viewBox) {
      throw new Error(`${name}: no viewBox`);
    }
    const [left, top, width, height] = viewBox[1].split(/\s+/).map(Number);
    icons[name] = { body, width, height, ...(left || top ? { left, top } : {}) };
  }
  return { prefix: PREFIX, icons };
}
