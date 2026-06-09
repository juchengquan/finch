import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // Vendored static assets (e.g. the sqlite-wasm ESM build).
    "public/**",
  ]),
  // Per the post-refactor (PR 1-6) DB layout, lib/db/domain/<x>/ is the
  // unit of layering. Cross-domain direct imports go through
  // domain/_shared/, domain/_app/, or a _deps.ts re-export; external
  // consumers (app/, lib/, components/) use the wire-level
  // @/lib/db/mutate.applyMutation instead of importing per-domain
  // mutations. See frontend/db-architecture.md for the full rules.
  {
    // Files INSIDE lib/db/domain/<x>/ (excluding _shared, _app):
    //   - May import from same-domain (any layer).
    //   - May import from _shared/, _app/, _args.ts, core/.
    //   - May NOT import from sibling domain/<y>/<non-standard-file> —
    //     i.e. any file that is not one of the 4 standard layers
    //     (types/errors/mutations/queries). The 3 known cross-domain
    //     deps flagged in the PR 4 review (transactions→attachments,
    //     rules→counterparties, scheduled→counterparties) all target
    //     a `queries` import, which the negations below re-include.
    //
    // Limitation: ESLint's no-restricted-imports pattern matcher
    // matches the literal import string and doesn't resolve aliases,
    // so this rule only catches aliased imports of non-standard
    // domain files. Relative-path cross-domain imports (the common
    // case in the current codebase) are not caught here; that
    // cross-domain rule is enforced by code review. See
    // frontend/db-architecture.md.
    files: ["lib/db/domain/**/!(_shared|_app)/*.ts"],
    rules: {
      "no-restricted-imports": ["error", {
        patterns: [
          {
            group: [
              "@/lib/db/domain/*/*",
              "!@/lib/db/domain/*/types",
              "!@/lib/db/domain/*/errors",
              "!@/lib/db/domain/*/mutations",
              "!@/lib/db/domain/*/queries",
            ],
            message: "Cross-domain imports of non-standard files are banned. Use domain/_shared/, domain/_app/, or a _deps.ts re-export.",
          },
        ],
      }],
    },
  },
  {
    // Files OUTSIDE lib/db/ (i.e. the route layer, the lib/ helpers, the
    // components): they may import types from lib/db/domain/<x>/types and
    // read queries from lib/db/domain/<x>/queries, but they may NOT
    // import from lib/db/domain/<x>/mutations (the internal surface).
    // The wire-level @/lib/db/mutate.applyMutation is the public entry
    // point for mutations.
    //
    // lib/db/ is excluded so the dispatcher (lib/db/mutate.ts) can
    // import the per-domain handlers maps and core/ files can import
    // type-only row shapes.
    files: ["app/**/*.{ts,tsx}", "lib/**/*.ts", "components/**/*.{ts,tsx}"],
    ignores: ["lib/db/**"],
    rules: {
      "no-restricted-imports": ["error", {
        patterns: [
          {
            group: ["@/lib/db/domain/*/mutations"],
            message: "External code cannot import from per-domain mutations. Use the wire-level @/lib/db/mutate.applyMutation or import types from ./types.",
          },
        ],
      }],
    },
  },
]);

export default eslintConfig;
