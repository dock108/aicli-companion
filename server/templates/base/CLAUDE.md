# {{project_name}} - Development Guidelines

## Core Principles

### 1. Test-Driven Development (TDD)
- Write tests before implementation
- Tests drive the design
- Red → Green → Refactor cycle
- Aim for >80% code coverage

### 2. Clean Code
- Keep functions small and focused
- Use descriptive names
- Follow {{tech_stack}} best practices
- Refactor mercilessly

### 3. Documentation
- Update plan.md with implementation progress
- Document API contracts clearly
- Keep README.md current
- Add inline comments for complex logic

### 4. Security First
- Validate all inputs
- Use parameterized queries
- Implement proper authentication
- Never commit secrets

### 5. Performance
- Profile before optimizing
- Cache appropriately
- Minimize database queries
- Use async operations where beneficial

## Project Context
**Project**: {{project_name}}  
**Type**: {{project_type}}  
**Tech Stack**: {{tech_stack}}  
**Team Size**: {{team_size}}  

## Development Workflow
1. Check plan.md for next task
2. Write failing tests
3. Implement minimal code to pass
4. Refactor for clarity
5. Update documentation
6. Commit with descriptive message

## Code Style
- Follow existing patterns in the codebase
- Use linting tools configured in project
- Maintain consistent indentation
- Keep line length under 100 characters

## Testing Requirements
- Unit tests for all business logic
- Integration tests for API endpoints
- End-to-end tests for critical user paths
- Performance tests for bottlenecks

## Deployment Checklist
- [ ] All tests passing
- [ ] Code reviewed
- [ ] Documentation updated
- [ ] Security scan passed
- [ ] Performance benchmarks met
- [ ] Rollback plan prepared

---
**Version**: {{version}}  
**Author**: {{author}}  
**Last Updated**: {{date}}