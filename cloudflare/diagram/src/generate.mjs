// Draws the resources in ../terraform as a Mermaid flowchart with Cloudflare's
// product icons, and renders it to SVG.
//
//   terraform graph  ->  architecture.mmd  ->  architecture.svg
//
// The resources and the edges between them come from `terraform graph`, which
// needs `terraform init` but no credentials: it is built from the configuration
// alone. Edges are Terraform dependencies, drawn the same way round as in the
// graph: from the resource that refers to another to the one it refers to, so
// the custom domain points at the deployment it routes to, the deployment at
// the version it serves, and so on. What each resource looks like is decided
// in resources.mjs.
//
// The .mmd is committed as the readable source, but it cannot be rendered by
// GitHub: Mermaid resolves `cf:*` icons through an icon pack that has to be
// registered at render time. Hence the SVG, which the README embeds.
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { renderMermaid } from "@mermaid-js/mermaid-cli";
import puppeteer from "puppeteer";
import { extras, fallback, groups, resources } from "./resources.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const terraformDir = resolve(root, "..", "terraform");
const outputs = {
  mmd: resolve(root, "architecture.mmd"),
  svg: resolve(root, "architecture.svg"),
};

// --- terraform graph ---------------------------------------------------------

// Resource addresses look like `type.name` or `data.type.name`, possibly with
// an index. Everything else in the graph (variables, locals, outputs, the
// provider) is not drawn.
const isResource = (address) =>
  /^(data\.)?[a-z][a-z0-9_]*\.[A-Za-z0-9_-]+(\[.*\])?$/.test(address) &&
  !/^(var|local|module|output|provider)\./.test(address);

const withoutIndex = (address) => address.replace(/\[.*\]$/, "");

function readGraph() {
  const result = spawnSync("terraform", ["graph"], { cwd: terraformDir, encoding: "utf8" });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    process.stderr.write(result.stderr);
    throw new Error(`terraform graph exited with ${result.status} (is the directory initialized?)`);
  }

  const nodes = new Set();
  const edges = [];
  for (const line of result.stdout.split("\n")) {
    const edge = line.match(/^\s*"([^"]+)" -> "([^"]+)"/);
    if (edge) {
      const [, dependent, dependency] = edge.map(withoutIndex);
      if (isResource(dependent) && isResource(dependency)) {
        edges.push({ dependent, dependency });
      }
      continue;
    }
    const node = line.match(/^\s*"([^"]+)" \[/);
    if (node && isResource(withoutIndex(node[1]))) {
      nodes.add(withoutIndex(node[1]));
    }
  }
  return { nodes: [...nodes], edges };
}

// --- model -------------------------------------------------------------------

const nodeId = (address) => address.replace(/[^A-Za-z0-9_]/g, "_");

function buildModel({ nodes: addresses, edges: dependencies }) {
  const groupOf = new Map(groups.flatMap((g) => (g.represents ?? []).map((a) => [a, g])));

  // Address -> the drawn thing: either a node, or the group that stands in for it.
  const resolveAddress = (address) => {
    const group = groupOf.get(address);
    if (group) {
      return { kind: "group", id: group.id };
    }
    const spec = resources[address];
    if (!spec) {
      process.stderr.write(
        `[WARN] ${address} is not in resources.mjs; drawn with the fallback icon\n`,
      );
      return { kind: "node", id: nodeId(address), address, ...fallback, label: address };
    }
    return { kind: "node", id: nodeId(address), address, ...spec };
  };

  const known = Object.keys(resources);
  const order = (address) => {
    const index = known.indexOf(address);
    return index === -1 ? known.length : index;
  };
  const nodes = addresses
    .filter((address) => !groupOf.has(address))
    .sort((a, b) => order(a) - order(b) || a.localeCompare(b))
    .map(resolveAddress);

  for (const address of Object.keys(resources)) {
    if (!addresses.includes(address)) {
      process.stderr.write(`[WARN] ${address} is in resources.mjs but not in the graph\n`);
    }
  }

  const memberOf = new Map(nodes.map((n) => [n.id, n.group]));
  const rank = new Map(nodes.map((n, i) => [n.id, i]));
  const edges = new Map();
  for (const { dependent, dependency } of dependencies) {
    const from = resolveAddress(dependent);
    const to = resolveAddress(dependency);
    if (from.id === to.id) {
      continue;
    }
    // A group already contains its members; the dependency is the box.
    if (from.kind === "group" && memberOf.get(to.id) === from.id) {
      continue;
    }
    if (to.kind === "group" && memberOf.get(from.id) === to.id) {
      continue;
    }
    edges.set(`${from.id}-->${to.id}`, { from: from.id, to: to.id });
  }
  for (const extra of extras) {
    edges.set(`${extra.id}-->${nodeId(extra.to)}`, { from: extra.id, to: nodeId(extra.to) });
  }

  const at = (id) => rank.get(id) ?? -1;
  return {
    nodes,
    edges: [...edges.values()].sort((a, b) => at(a.from) - at(b.from) || at(a.to) - at(b.to)),
  };
}

// --- mermaid -----------------------------------------------------------------

const shape = ({ id, icon, label, form = "rounded", sublabel }) => {
  const text = sublabel ? `${label}<br/>${sublabel}` : label;
  return `${id}@{ icon: "cf:${icon}", form: "${form}", label: "${text}", pos: "b", h: 48 }`;
};

function toMermaid({ nodes, edges }) {
  const lines = [
    "flowchart LR",
    `    %% Generated by ${relative(root, fileURLToPath(import.meta.url))} from \`terraform graph\`; do not edit.`,
    "",
  ];
  for (const extra of extras) {
    lines.push(`    ${shape(extra)}`);
  }
  lines.push("");
  for (const group of groups) {
    lines.push(`    subgraph ${group.id}["${group.label}"]`, "        direction TB");
    for (const node of nodes.filter((n) => n.group === group.id)) {
      lines.push(`        ${shape({ ...node, sublabel: node.address })}`);
    }
    lines.push("    end", "");
  }
  const ungrouped = nodes.filter((n) => !n.group);
  for (const node of ungrouped) {
    lines.push(`    ${shape({ ...node, sublabel: node.address })}`);
  }
  if (ungrouped.length > 0) {
    lines.push("");
  }
  for (const { from, to } of edges) {
    lines.push(`    ${from} --> ${to}`);
  }
  return lines.join("\n") + "\n";
}

async function render(definition) {
  // React (the icon components) warns about a few attribute spellings unless it
  // thinks it is in production; it is loaded lazily so this takes effect first.
  process.env.NODE_ENV ??= "production";
  const { iconSet, PREFIX } = await import("./icons.mjs");
  const pack = Buffer.from(JSON.stringify(iconSet())).toString("base64");

  const browser = await puppeteer.launch({ headless: "shell" });
  try {
    const { data } = await renderMermaid(browser, definition, "svg", {
      backgroundColor: "white",
      // The icon shapes are outlined with rough.js, which is seeded from
      // handDrawnSeed; a fixed seed makes the SVG reproducible so that
      // re-running with no change to the configuration leaves no diff.
      mermaidConfig: { handDrawnSeed: 1, flowchart: { htmlLabels: false } },
      // mermaid-cli fetches icon packs by URL; a data: URL keeps it offline.
      iconPacksNamesAndUrls: [`${PREFIX}#data:application/json;base64,${pack}`],
    });
    return stabilizeIds(Buffer.from(data).toString("utf8"));
  } finally {
    await browser.close();
  }
}

// Iconify gives every id inside an icon body (a clipPath, say) a fresh random
// name on each render. Renumber them in order of appearance so that the SVG
// only changes when the diagram does.
function stabilizeIds(svg) {
  const ids = new Map();
  return svg.replace(/IconifyId[0-9a-f]+/g, (id) => {
    if (!ids.has(id)) {
      ids.set(id, `cf-icon-${ids.size + 1}`);
    }
    return ids.get(id);
  });
}

const definition = toMermaid(buildModel(readGraph()));
writeFileSync(outputs.mmd, definition);
console.log(`[INFO] wrote ${relative(process.cwd(), outputs.mmd)}`);
writeFileSync(outputs.svg, await render(definition));
console.log(`[INFO] wrote ${relative(process.cwd(), outputs.svg)}`);
