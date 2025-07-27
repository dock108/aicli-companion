# Contributing to Claude Companion

Thank you for your interest in contributing to Claude Companion! This guide will help you get started.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct:
- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on constructive criticism
- Respect differing viewpoints and experiences

## How to Contribute

### Reporting Issues

1. **Check existing issues** first to avoid duplicates
2. **Use issue templates** when available
3. **Provide details**:
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details
   - Screenshots/logs if applicable

### Suggesting Features

1. **Open a discussion** first for major features
2. **Explain the use case** clearly
3. **Consider alternatives** you've explored
4. **Be patient** - features take time to implement

### Contributing Code

1. **Fork the repository**
2. **Create a feature branch**
3. **Make your changes**
4. **Write/update tests**
5. **Update documentation**
6. **Submit a pull request**

## Development Process

### 1. Setting Up Your Fork

```bash
# Fork via GitHub UI first, then:
git clone https://github.com/YOUR_USERNAME/claude-companion.git
cd claude-companion

# Add upstream remote
git remote add upstream https://github.com/original/claude-companion.git

# Keep your fork updated
git fetch upstream
git checkout main
git merge upstream/main
```

### 2. Creating a Branch

```bash
# Feature branch
git checkout -b feature/your-feature-name

# Bug fix branch
git checkout -b fix/issue-number-description

# Documentation branch
git checkout -b docs/what-you-are-documenting
```

### 3. Making Changes

Follow these guidelines:
- **One feature per PR** - Keep changes focused
- **Small commits** - Make atomic, logical commits
- **Clear messages** - Write descriptive commit messages
- **Test as you go** - Run tests frequently

### 4. Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code changes that neither fix bugs nor add features
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples**:
```bash
feat(ios): add offline message queue
fix(server): resolve memory leak in session manager
docs(api): update WebSocket protocol examples
test(server): add integration tests for auth flow
```

### 5. Code Style

#### JavaScript/TypeScript
- ESLint rules are enforced
- Use Prettier for formatting
- Follow existing patterns

```javascript
// Good
export function processMessage(message) {
  if (!message?.content) {
    throw new Error('Message content required');
  }
  
  return {
    ...message,
    processedAt: new Date().toISOString()
  };
}

// Bad
export function processMessage(msg) {
  if(!msg.content) throw new Error("no content");
  return {...msg,processedAt:new Date().toISOString()};
}
```

#### Swift
- Follow Swift API Design Guidelines
- Use meaningful names
- Document public APIs

```swift
// Good
public func sendMessage(_ content: String) async throws -> Message {
    guard !content.isEmpty else {
        throw MessageError.emptyContent
    }
    
    let message = Message(content: content)
    return try await webSocketService.send(message)
}

// Bad
func send(_ s: String) -> Message? {
    if s == "" { return nil }
    let m = Message(content: s)
    return webSocketService.send(m)
}
```

#### Rust
- Follow Rust conventions
- Use `cargo fmt` and `cargo clippy`
- Handle errors properly

```rust
// Good
pub fn start_server(config: ServerConfig) -> Result<ServerHandle, Error> {
    let port = config.port.unwrap_or(DEFAULT_PORT);
    
    match TcpListener::bind(("0.0.0.0", port)) {
        Ok(listener) => Ok(ServerHandle::new(listener)),
        Err(e) => Err(Error::BindFailed(e)),
    }
}

// Bad
pub fn start_server(config: ServerConfig) -> ServerHandle {
    let listener = TcpListener::bind(("0.0.0.0", config.port.unwrap())).unwrap();
    ServerHandle::new(listener)
}
```

### 6. Testing Requirements

All contributions must include appropriate tests:

- **New features**: Unit and integration tests
- **Bug fixes**: Test that reproduces and verifies the fix
- **Refactoring**: Ensure existing tests still pass
- **Coverage**: Maintain or improve test coverage

### 7. Documentation

Update documentation for:
- New features or APIs
- Changed behavior
- New configuration options
- Installation/setup changes

## Pull Request Process

### 1. Before Submitting

- [ ] Tests pass locally
- [ ] Code follows style guidelines
- [ ] Documentation is updated
- [ ] Commit messages follow conventions
- [ ] Branch is up to date with main

### 2. PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
```

### 3. Review Process

1. **Automated checks** run first
2. **Code review** by maintainers
3. **Address feedback** promptly
4. **Approval** from at least one maintainer
5. **Merge** when all checks pass

### 4. After Merge

- Delete your feature branch
- Pull latest changes to your fork
- Celebrate your contribution! 🎉

## Types of Contributions

### Code Contributions
- Bug fixes
- New features
- Performance improvements
- Refactoring

### Non-Code Contributions
- Documentation improvements
- Bug reports
- Feature suggestions
- Translations
- Design assets

### Community Contributions
- Answering questions
- Reviewing PRs
- Triaging issues
- Writing tutorials

## Getting Help

### Resources
- [Development Setup](./setup.md)
- [Architecture Overview](../architecture/overview.md)
- [API Documentation](../api/rest-api.md)
- Project Discord/Slack (if available)

### Asking Questions
- Check documentation first
- Search existing issues
- Ask in discussions
- Be specific and provide context

## Recognition

Contributors are recognized in:
- Release notes
- Contributors file
- Project website
- Annual contributor spotlight

## Security

### Reporting Security Issues

**DO NOT** open public issues for security vulnerabilities.

Instead:
1. Email security@claude-companion.com
2. Include detailed description
3. Wait for response before disclosure
4. Work with maintainers on fix

### Security Best Practices
- Never commit secrets or keys
- Validate all inputs
- Use secure coding practices
- Keep dependencies updated

## License

By contributing, you agree that your contributions will be licensed under the project's MIT License.

## Thank You!

Your contributions make Claude Companion better for everyone. Whether it's code, documentation, or community support, every contribution matters.

Welcome to the team! 🚀

---

**Last Updated**: 2025-07-27