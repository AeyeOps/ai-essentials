import { defineConfig } from '@vscode/test-cli';

export default defineConfig([
  {
    label: 'unit',
    files: 'out/test/unit/**/*.test.js',
    mocha: {
      ui: 'tdd',
      timeout: 10000
    }
  },
  {
    label: 'integration',
    files: 'out/test/integration/**/*.test.js',
    workspaceFolder: './test-fixtures',
    mocha: {
      ui: 'tdd',
      timeout: 30000
    }
  }
]);
