// esbuild bundles the landing page with `--loader:.html=text`; see package.json.
declare module "*.html" {
  const html: string;
  export default html;
}
