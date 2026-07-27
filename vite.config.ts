import { defineConfig } from 'vite-plus';

export default defineConfig({
  fmt: {
    // Go text/template sources with mustache placeholders — not parseable TS.
    ignorePatterns: ['**/*.tmpl.ts'],
  },
  lint: {"options":{"typeAware":true,"typeCheck":true}},
  test: {
    // .direnv and .worktrees hold vendored/checked-out copies of this repo;
    // .submodules and .patch-work hold other projects' checkouts. Without the
    // exclusions vitest discovers their suites (hundreds of files) and they
    // fail outside their own toolchains.
    exclude: [
      '**/.direnv/**',
      '**/.worktrees/**',
      '**/.submodules/**',
      '**/.patch-work/**',
      '**/node_modules/**',
    ],
  },
});
