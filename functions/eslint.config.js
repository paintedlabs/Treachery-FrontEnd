// ESLint flat config (ESLint 9 removed .eslintrc support from the default
// resolution order; ESLint 10 removed it entirely). This is a like-for-like
// port of the previous .eslintrc.js — same parser options, same globals, same
// rule set, same ignores — so the migration changes the config format only.
//
// The old `root: true` has no flat-config equivalent because it is the only
// behaviour flat config has: lookup stops at the first eslint.config.js and
// never cascades into parent directories. Nothing above functions/ is picked
// up, which is what `root: true` was there to guarantee.
//
// `sourceType: "module"` is carried over verbatim from the old config even
// though every file here is CommonJS (`require` / `module.exports`). It is
// arguably the wrong label, but it is what the old config used and it changes
// nothing that is actually reported: `env: node` / `globals.node` supplies
// `require`, `module` and `exports`, and no rule in this set distinguishes
// ESM from CJS parsing for these files. Changing it to "commonjs" here would
// be a silent behaviour change bundled into a dependency bump, so it stays.

const js = require("@eslint/js");
const globals = require("globals");

module.exports = [
  // was: ignorePatterns: ["node_modules/"]
  { ignores: ["node_modules/"] },

  // was: extends: ["eslint:recommended"]
  js.configs.recommended,

  {
    // was: the `--ext .js` in the lint script
    files: ["**/*.js"],
    languageOptions: {
      // was: parserOptions.ecmaVersion / parserOptions.sourceType
      ecmaVersion: 2022,
      sourceType: "module",
      // was: env: { node: true, es2022: true }
      globals: {
        ...globals.node,
        ...globals.es2022,
      },
    },
    rules: {
      "no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
    },
  },
];
