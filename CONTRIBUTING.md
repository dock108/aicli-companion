# Contributing to Claude Companion

Thank you for your interest in contributing to Claude Companion! This guide will help you get started.

## Code of Conduct

Please note that this project is released with a [Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project you agree to abide by its terms.

## How to Contribute

### Reporting Issues

- Check if the issue already exists in our [issue tracker](https://github.com/your-repo/claude-companion/issues)
- Use the appropriate issue template
- Provide as much detail as possible
- Include steps to reproduce for bugs

### Suggesting Features

- Open a discussion in [GitHub Discussions](https://github.com/your-repo/claude-companion/discussions)
- Explain the use case and benefits
- Consider implementation complexity

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`npm test`)
5. Commit with conventional commits (see below)
6. Push to your fork
7. Open a Pull Request

## Development Setup

See our [Development Setup Guide](./docs/development/setup.md) for detailed instructions.

## Commit Guidelines

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation changes
- `style:` Code style changes (formatting, etc)
- `refactor:` Code refactoring
- `test:` Test additions or fixes
- `chore:` Maintenance tasks

Examples:
```
feat(ios): add dark mode support
fix(server): handle WebSocket reconnection properly
docs: update installation guide
```

## Testing

- Write tests for new features
- Ensure all tests pass before submitting PR
- Aim for good test coverage
- See [Testing Guide](./docs/development/testing.md)

## Code Style

### JavaScript/Node.js
- ESLint configuration is provided
- Run `npm run lint` to check
- Run `npm run format` to auto-fix

### Swift/iOS
- SwiftLint is configured
- Follow Apple's Swift API Design Guidelines
- Use meaningful variable names

## Documentation

- Update documentation for new features
- Keep README.md current
- Add JSDoc/Swift documentation comments
- Update API docs if endpoints change

## Review Process

1. Automated checks must pass
2. Code review by maintainers
3. Address feedback
4. Merge when approved

## Questions?

- Open a discussion for general questions
- Join our community chat (if available)
- Check existing documentation

Thank you for contributing! 🎉