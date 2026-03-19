import { defineConfig } from "@vscode/test-cli";

export default defineConfig([
  {
    label: "unitTests",
    files: "dist/test/**/*.test.js",
    version: "insiders",
    workspaceFolder: "./test-fixtures",
    mocha: {
      ui: "tdd",
      timeout: 20000,
    },
  },
]);
