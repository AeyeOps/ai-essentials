# tsc-to-esbuild Migration Guide

## What Changed

This migration replaces the default `yo code` tsc-based build with an esbuild bundler,
adds `@vscode/test-cli` testing infrastructure, and prepares the project for marketplace
publishing.

## Files Added or Replaced

- `esbuild.js` -- Build script that bundles `src/extension.ts` into `dist/extension.js`
- `package.json` -- Updated `main` entry to `./dist/extension`, replaced scripts, added devDependencies
- `tsconfig.json` -- Updated for esbuild workflow (`outDir: out` for type-checking, esbuild writes to `dist/`)
- `.vscode-test.mjs` -- Test runner config with unit and integration test labels
- `.vscodeignore` -- Excludes source, configs, and node_modules from the .vsix package
- `.vscode/launch.json` -- Extension Host debug configs pointing to `dist/` output
- `.vscode/tasks.json` -- Watch and compile tasks with esbuild + tsc problem matchers
- `.github/workflows/ci.yml` -- GitHub Actions CI with `xvfb-run` for headless test execution
- `src/extension.ts` -- Minimal activate/deactivate entry point
- `src/test/integration/extension.test.ts` -- Sample integration tests using Mocha TDD
- `test-fixtures/` -- Workspace directory for integration test context

## Step-by-Step Migration

### 1. Remove old build artifacts

```bash
rm -rf out/
```

Delete `out/` since esbuild now outputs to `dist/`. The `out/` directory is only used by
tsc for type-checking and test compilation (never shipped).

### 2. Install dependencies

```bash
npm install --save-dev esbuild @vscode/test-cli @vscode/test-electron @vscode/vsce npm-run-all
```

### 3. Replace files

Copy the output files over your existing project, replacing `package.json`, `tsconfig.json`,
and adding the new config files. Merge your existing `contributes` and metadata into the
new `package.json` structure.

### 4. Update package.json main entry

Ensure `"main"` points to `"./dist/extension"` (not `"./out/extension"`).

### 5. Verify the build

```bash
npm run compile
```

This runs `tsc --noEmit` (type checking only) followed by `node esbuild.js` (bundling).
The output lands in `dist/extension.js`.

### 6. Run tests

```bash
npm test
```

Or run a specific test config:

```bash
npx vscode-test --label unit
npx vscode-test --label integration
```

### 7. Package for local testing

```bash
npx vsce package
code-insiders --install-extension my-extension-0.1.0.vsix
```

### 8. Development workflow

Press F5 in code-insiders to launch the Extension Development Host, or run the watch task:

```bash
npm run watch
```

This runs esbuild (sub-second rebuilds) and tsc (type checking) in parallel.

### 9. Publish

```bash
npx vsce login my-publisher-id
npx vsce publish
```

Or with version bump:

```bash
npx vsce publish minor
```

## Key Differences from tsc Build

- **Output directory**: `dist/` (esbuild bundle) instead of `out/` (tsc compilation)
- **Single file**: esbuild produces one `dist/extension.js` instead of mirroring the src tree
- **No runtime node_modules**: All dependencies are bundled (except `vscode` which is external)
- **Faster builds**: esbuild is 10-100x faster than tsc for bundling
- **Type checking**: Still runs via `tsc --noEmit` -- esbuild skips type checking by design
- **Smaller .vsix**: The bundled output + `.vscodeignore` exclusions keep the package small
