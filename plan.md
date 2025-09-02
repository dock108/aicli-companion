# AICLI Companion Server Refactoring Plan

## Overview
This plan addresses refactoring all server files exceeding 500 lines to improve maintainability, testability, and code organization.

## Current State Analysis

### Files Exceeding 500 Lines (excluding tests)

| File | Lines | Primary Concerns | Priority |
|------|-------|------------------|----------|
| `services/aicli.js` | 1436 | Monolithic service with mixed responsibilities | HIGH |
| `services/aicli-process-runner.js` | 1384 | Process management + monitoring + permissions | HIGH |
| `services/aicli-session-manager.js` | 1066 | Session lifecycle + buffer management + telemetry | HIGH |
| `services/push-notification.js` | 895 | Multiple notification types in single file | MEDIUM |
| `services/aicli-utils.js` | 759 | Mixed utility functions | MEDIUM |
| `index.js` | 716 | Server initialization + config + middleware | MEDIUM |
| `services/command-security.js` | 707 | Security validation + permission management | LOW |
| `services/aicli-message-handler.js` | 633 | Message processing logic | LOW |
| `routes/files.js` | 628 | File operations endpoint | LOW |
| `services/activity-monitor.js` | 565 | Activity tracking | LOW |
| `services/message-queue.js` | 552 | Queue management | LOW |

## Refactoring Strategy

### Phase 1: Critical Service Decomposition (Week 1)

#### 1.1 Refactor `services/aicli.js` (1436 → ~400 lines each)
**Target Structure:**
```
services/
├── aicli/
│   ├── index.js (main service ~400 lines)
│   ├── message-classifier.js (~250 lines)
│   ├── permission-handler.js (~300 lines)
│   ├── attachment-processor.js (~200 lines)
│   └── response-emitter.js (~300 lines)
```

**Extraction Plan:**
- Move message classification methods to `message-classifier.js`
- Extract permission handling to `permission-handler.js`
- Move attachment processing to `attachment-processor.js`
- Extract response emission logic to `response-emitter.js`
- Keep core prompt sending and session coordination in main file

#### 1.2 Refactor `services/aicli-process-runner.js` (1384 → ~400 lines each)
**Target Structure:**
```
services/
├── aicli-process/
│   ├── index.js (main runner ~400 lines)
│   ├── process-monitor.js (~350 lines)
│   ├── interactive-session.js (~300 lines)
│   ├── permission-validator.js (~250 lines)
│   └── health-monitor.js (~200 lines)
```

**Extraction Plan:**
- Move process monitoring to `process-monitor.js`
- Extract interactive session management to `interactive-session.js`
- Move permission validation to `permission-validator.js`
- Extract health monitoring to `health-monitor.js`

#### 1.3 Refactor `services/aicli-session-manager.js` (1066 → ~350 lines each)
**Target Structure:**
```
services/
├── session/
│   ├── index.js (main manager ~350 lines)
│   ├── session-buffer.js (~300 lines)
│   ├── session-cleanup.js (~250 lines)
│   └── session-tracker.js (~200 lines)
```

**Extraction Plan:**
- Move buffer management to `session-buffer.js`
- Extract cleanup logic to `session-cleanup.js`
- Move tracking/routing to `session-tracker.js`

### Phase 2: Service Layer Cleanup (Week 2)

#### 2.1 Refactor `services/push-notification.js` (895 → ~300 lines each)
**Target Structure:**
```
services/
├── notifications/
│   ├── index.js (main service ~300 lines)
│   ├── apns-client.js (~200 lines)
│   ├── message-formatter.js (~250 lines)
│   └── notification-types.js (~200 lines)
```

#### 2.2 Refactor `services/aicli-utils.js` (759 → ~250 lines each)
**Target Structure:**
```
services/
├── utils/
│   ├── stream-utils.js (~250 lines)
│   ├── json-utils.js (~250 lines)
│   └── text-utils.js (~250 lines)
```

### Phase 3: Application Layer (Week 3)

#### 3.1 Refactor `index.js` (716 → ~350 lines each)
**Target Structure:**
```
src/
├── index.js (~350 lines - main server)
├── config/
│   └── server-setup.js (~200 lines)
└── middleware/
    └── middleware-setup.js (~200 lines)
```

#### 3.2 Refactor `routes/files.js` (628 → ~400 lines)
**Target Structure:**
```
routes/
├── files/
│   ├── index.js (~400 lines)
│   └── file-validators.js (~250 lines)
```

### Phase 4: Support Services (Week 4)

#### 4.1 Optimize remaining files
- `services/command-security.js` - Extract validation rules
- `services/aicli-message-handler.js` - Split response types
- `services/activity-monitor.js` - Keep as is (just over limit)
- `services/message-queue.js` - Keep as is (just over limit)

## Implementation Order

### Week 1: Core AICLI Services
1. **Day 1-2**: Refactor `aicli.js`
   - Create directory structure
   - Extract message classifier
   - Extract permission handler
   - Test thoroughly

2. **Day 3-4**: Refactor `aicli-process-runner.js`
   - Extract monitoring components
   - Separate session management
   - Validate all process operations

3. **Day 5**: Refactor `aicli-session-manager.js`
   - Extract buffer management
   - Separate cleanup logic

### Week 2: Supporting Services
1. **Day 1-2**: Refactor `push-notification.js`
   - Extract notification types
   - Separate APNS client logic

2. **Day 3**: Refactor `aicli-utils.js`
   - Categorize utilities
   - Create focused utility modules

3. **Day 4-5**: Testing and validation
   - Run full test suite
   - Performance testing

### Week 3: Application Layer
1. **Day 1-2**: Refactor `index.js`
   - Extract setup logic
   - Modularize middleware

2. **Day 3**: Refactor `routes/files.js`
   - Extract validators
   - Optimize route handlers

3. **Day 4-5**: Integration testing

### Week 4: Finalization
1. **Day 1-2**: Minor optimizations
2. **Day 3-4**: Documentation updates
3. **Day 5**: Final testing and deployment prep

## Success Criteria

### Code Quality Metrics
- [ ] No source file exceeds 500 lines (excluding tests)
- [ ] All tests passing (1251/1251)
- [ ] Test coverage maintained at >80%
- [ ] No circular dependencies introduced

### Functional Requirements
- [ ] All API endpoints functioning identically
- [ ] WebSocket connections stable
- [ ] Message queue processing unchanged
- [ ] Push notifications working
- [ ] Session management intact

### Performance Targets
- [ ] Server startup time < 3 seconds
- [ ] Memory usage not increased by >10%
- [ ] Response times unchanged or improved

## Risk Mitigation

### Potential Risks
1. **Breaking API contracts**: Mitigate with comprehensive testing
2. **Circular dependencies**: Use dependency injection patterns
3. **Performance degradation**: Profile before/after each phase
4. **Test failures**: Fix immediately, don't accumulate debt

### Rollback Strategy
- Each phase commits separately
- Tag releases before major refactors
- Keep original files during transition
- Gradual migration with feature flags if needed

## Testing Strategy

### Unit Tests
- Update imports in existing tests
- Add new tests for extracted modules
- Maintain >80% coverage

### Integration Tests
- Full API endpoint testing after each phase
- WebSocket connection tests
- Message queue processing tests
- Push notification delivery tests

### Performance Tests
- Memory usage profiling
- Response time benchmarks
- Concurrent connection stress tests

## Documentation Updates

### Required Updates
1. Update module documentation
2. Update API documentation if paths change
3. Update developer setup guide
4. Create module dependency diagram

## Next Steps

1. **Review and approve this plan**
2. **Create feature branch**: `refactor/modularize-large-files`
3. **Begin Phase 1**: Start with `aicli.js` decomposition
4. **Daily progress updates**: Track completion in GitHub issues

## Notes

- Prioritize maintaining functionality over arbitrary line limits
- Some files at 550-650 lines may be acceptable if cohesive
- Consider future growth when creating new structure
- Keep related functionality together for maintainability

---

**Estimated Total Time**: 4 weeks (part-time) or 2 weeks (full-time)
**Risk Level**: Medium (extensive changes but good test coverage)
**Impact**: High (significantly improved maintainability)