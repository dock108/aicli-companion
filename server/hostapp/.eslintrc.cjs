module.exports = {
  env: {
    browser: true,
    es2021: true,
    node: true,
  },
  extends: ['eslint:recommended', 'prettier'],
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
  },
  plugins: ['prettier'],
  rules: {
    'prettier/prettier': 'error',
    'no-console': 'off', // Allow console.log in desktop app
    'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    'prefer-arrow-callback': 'off', // Allow function expressions
  },
};