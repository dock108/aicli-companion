import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { PlanningModeService } from '../../services/planning-mode.js';

describe('PlanningModeService', () => {
  let planningModeService;

  beforeEach(() => {
    planningModeService = new PlanningModeService();
  });

  describe('getAllowedExtensions', () => {
    it('should return default allowed extensions', () => {
      const extensions = planningModeService.getAllowedExtensions();
      assert(Array.isArray(extensions));
      assert(extensions.includes('.md'));
      assert(extensions.includes('.txt'));
      assert(extensions.includes('.plan'));
      assert(extensions.includes('.todo'));
    });

    it('should return custom extensions when set', () => {
      planningModeService.customAllowedExtensions = ['.custom', '.test'];
      const extensions = planningModeService.getAllowedExtensions();
      assert.deepEqual(extensions, ['.custom', '.test']);
    });
  });

  describe('isFileAllowedForWriting', () => {
    it('should allow markdown files', () => {
      assert(planningModeService.isFileAllowedForWriting('test.md'));
      assert(planningModeService.isFileAllowedForWriting('/path/to/file.md'));
      assert(planningModeService.isFileAllowedForWriting('README.md'));
    });

    it('should allow text files', () => {
      assert(planningModeService.isFileAllowedForWriting('notes.txt'));
      assert(planningModeService.isFileAllowedForWriting('/docs/plan.txt'));
    });

    it('should allow special file names regardless of extension', () => {
      assert(planningModeService.isFileAllowedForWriting('README'));
      assert(planningModeService.isFileAllowedForWriting('TODO'));
      assert(planningModeService.isFileAllowedForWriting('PLAN'));
      assert(planningModeService.isFileAllowedForWriting('CHANGELOG'));
      assert(planningModeService.isFileAllowedForWriting('README.rst'));
      assert(planningModeService.isFileAllowedForWriting('TODO.html'));
    });

    it('should reject code files', () => {
      assert(!planningModeService.isFileAllowedForWriting('index.js'));
      assert(!planningModeService.isFileAllowedForWriting('main.py'));
      assert(!planningModeService.isFileAllowedForWriting('app.tsx'));
      assert(!planningModeService.isFileAllowedForWriting('server.go'));
    });

    it('should reject null or empty paths', () => {
      assert(!planningModeService.isFileAllowedForWriting(null));
      assert(!planningModeService.isFileAllowedForWriting(''));
      assert(!planningModeService.isFileAllowedForWriting(undefined));
    });

    it('should handle case insensitivity for special files', () => {
      assert(planningModeService.isFileAllowedForWriting('readme'));
      assert(planningModeService.isFileAllowedForWriting('Readme'));
      assert(planningModeService.isFileAllowedForWriting('README'));
    });
  });

  describe('wrapPromptForPlanning', () => {
    it('should wrap user prompt with planning mode instructions', () => {
      const userPrompt = 'Create a new feature';
      const wrapped = planningModeService.wrapPromptForPlanning(userPrompt);
      const parsed = JSON.parse(wrapped);

      assert.equal(parsed.mode, 'planning');
      assert.equal(parsed.userPrompt, userPrompt);
      assert(parsed.instructions);
      assert(parsed.instructions.primary);
      assert(Array.isArray(parsed.instructions.restrictions));
      assert(parsed.timestamp);
    });

    it('should include allowed extensions in instructions', () => {
      const userPrompt = 'Test prompt';
      const wrapped = planningModeService.wrapPromptForPlanning(userPrompt);
      const parsed = JSON.parse(wrapped);

      const restrictionText = parsed.instructions.restrictions.join(' ');
      assert(restrictionText.includes('.md'));
      assert(restrictionText.includes('.txt'));
    });
  });

  describe('buildToolRestrictions', () => {
    it('should return allowed tools for planning mode', () => {
      const restrictions = planningModeService.buildToolRestrictions();

      assert(Array.isArray(restrictions.allowedTools));
      assert(restrictions.allowedTools.includes('Read'));
      assert(restrictions.allowedTools.includes('Grep'));
      assert(restrictions.allowedTools.includes('Bash:ls'));
      assert(restrictions.allowedTools.includes('Bash:find'));
    });

    it('should specify tools requiring validation', () => {
      const restrictions = planningModeService.buildToolRestrictions();

      assert(Array.isArray(restrictions.requiresValidation));
      assert(restrictions.requiresValidation.includes('Write'));
      assert(restrictions.requiresValidation.includes('Edit'));
      assert(restrictions.requiresValidation.includes('MultiEdit'));
    });

    it('should disallow destructive tools', () => {
      const restrictions = planningModeService.buildToolRestrictions();

      assert(Array.isArray(restrictions.disallowedTools));
      assert(restrictions.disallowedTools.includes('Delete'));
      assert(restrictions.disallowedTools.includes('Bash:rm'));
      assert(restrictions.disallowedTools.includes('Bash:mv'));
    });
  });

  describe('validateFileOperation', () => {
    it('should allow all operations in normal mode', () => {
      let result = planningModeService.validateFileOperation('Write', 'test.js', 'normal');
      assert(result.allowed);

      result = planningModeService.validateFileOperation('Delete', 'file.py', 'normal');
      assert(result.allowed);

      result = planningModeService.validateFileOperation('Edit', 'app.tsx', 'normal');
      assert(result.allowed);
    });

    it('should always allow read operations in planning mode', () => {
      let result = planningModeService.validateFileOperation('Read', 'test.js', 'planning');
      assert(result.allowed);

      result = planningModeService.validateFileOperation('Grep', 'file.py', 'planning');
      assert(result.allowed);
    });

    it('should validate write operations in planning mode', () => {
      let result = planningModeService.validateFileOperation('Write', 'README.md', 'planning');
      assert(result.allowed);

      result = planningModeService.validateFileOperation('Write', 'index.js', 'planning');
      assert(!result.allowed);
      assert(result.reason);
      assert(result.suggestion);
    });

    it('should validate edit operations in planning mode', () => {
      let result = planningModeService.validateFileOperation('Edit', 'TODO.txt', 'planning');
      assert(result.allowed);

      result = planningModeService.validateFileOperation('Edit', 'server.py', 'planning');
      assert(!result.allowed);
      assert(result.reason.includes('Planning Mode'));
    });

    it('should block delete operations in planning mode', () => {
      const result = planningModeService.validateFileOperation('Delete', 'README.md', 'planning');
      assert(!result.allowed);
      assert(result.reason.includes('deletion is not allowed'));
      assert(result.suggestion);
    });

    it('should handle MultiEdit operations', () => {
      let result = planningModeService.validateFileOperation(
        'MultiEdit',
        'CHANGELOG.md',
        'planning'
      );
      assert(result.allowed);

      result = planningModeService.validateFileOperation('MultiEdit', 'app.js', 'planning');
      assert(!result.allowed);
    });
  });

  describe('getStatusMessage', () => {
    it('should return null for non-planning mode', () => {
      const status = planningModeService.getStatusMessage('normal');
      assert.equal(status, null);
    });

    it('should return status message for planning mode', () => {
      const status = planningModeService.getStatusMessage('planning');

      assert(status);
      assert.equal(status.mode, 'planning');
      assert.equal(status.emoji, '📝');
      assert(status.title);
      assert(status.description);
      assert(Array.isArray(status.allowedExtensions));
      assert(Array.isArray(status.allowedFileNames));
      assert(Array.isArray(status.restrictions));
    });
  });

  describe('generateViolationResponse', () => {
    it('should generate proper violation response', () => {
      const response = planningModeService.generateViolationResponse('Write', 'index.js');

      assert.equal(response.error, 'Planning Mode Violation');
      assert(response.message.includes('Cannot Write'));
      assert(response.message.includes('index.js'));
      assert(response.details);
      assert(Array.isArray(response.allowedExtensions));
      assert(response.suggestion);
      assert.equal(response.mode, 'planning');
    });
  });

  describe('shouldEnforceServerSide', () => {
    it('should return false by default', () => {
      assert.equal(planningModeService.shouldEnforceServerSide(), false);
    });

    it('should respect environment variable', () => {
      const originalValue = process.env.PLANNING_MODE_STRICT;

      process.env.PLANNING_MODE_STRICT = 'true';
      assert.equal(planningModeService.shouldEnforceServerSide(), true);

      process.env.PLANNING_MODE_STRICT = 'false';
      assert.equal(planningModeService.shouldEnforceServerSide(), false);

      // Restore original value
      if (originalValue !== undefined) {
        process.env.PLANNING_MODE_STRICT = originalValue;
      } else {
        delete process.env.PLANNING_MODE_STRICT;
      }
    });
  });
});
