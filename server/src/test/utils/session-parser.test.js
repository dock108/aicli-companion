import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  SessionIdParser,
  SESSION_ID_FORMATS,
  parseSessionId,
  extractProjectName,
  extractSessionId,
  isValidSessionId,
  createCompositeSessionId,
} from '../../utils/session-parser.js';

describe('SessionIdParser', () => {
  describe('parseSessionId', () => {
    it('should parse standard UUID format', () => {
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      const result = SessionIdParser.parseSessionId(uuid);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.UUID);
      assert.strictEqual(result.sessionId, uuid);
      assert.strictEqual(result.projectName, null);
      assert.strictEqual(result.rawSessionId, uuid);
    });

    it('should parse UUID v4 format', () => {
      const uuid = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
      const result = SessionIdParser.parseSessionId(uuid);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.UUID);
      assert.strictEqual(result.sessionId, uuid);
    });

    it('should parse composite format with project name and UUID', () => {
      const compositeId = 'my-project_550e8400-e29b-41d4-a716-446655440000';
      const result = SessionIdParser.parseSessionId(compositeId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.sessionId, '550e8400-e29b-41d4-a716-446655440000');
      assert.strictEqual(result.projectName, 'my-project');
      assert.strictEqual(result.rawSessionId, compositeId);
    });

    it('should parse composite format with multi-part project name', () => {
      const compositeId = 'my_awesome_project_550e8400-e29b-41d4-a716-446655440000';
      const result = SessionIdParser.parseSessionId(compositeId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.sessionId, '550e8400-e29b-41d4-a716-446655440000');
      assert.strictEqual(result.projectName, 'my_awesome_project');
    });

    it('should parse composite format with simple session ID', () => {
      const compositeId = 'project_name_session123';
      const result = SessionIdParser.parseSessionId(compositeId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.sessionId, 'session123');
      assert.strictEqual(result.projectName, 'project_name');
    });

    it('should parse simple format without underscores', () => {
      const simpleId = 'session12345';
      const result = SessionIdParser.parseSessionId(simpleId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.SIMPLE);
      assert.strictEqual(result.sessionId, simpleId);
      assert.strictEqual(result.projectName, null);
    });

    it('should handle single underscore as composite', () => {
      const id = 'project_123';
      const result = SessionIdParser.parseSessionId(id);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.sessionId, '123');
      assert.strictEqual(result.projectName, 'project');
    });

    it('should handle trailing spaces', () => {
      const id = '  session123  ';
      const result = SessionIdParser.parseSessionId(id);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.sessionId, 'session123');
    });

    it('should handle null input', () => {
      const result = SessionIdParser.parseSessionId(null);

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.format, null);
      assert.strictEqual(result.sessionId, null);
      assert.strictEqual(result.projectName, null);
      assert.strictEqual(result.error, 'Invalid or missing session ID');
    });

    it('should handle undefined input', () => {
      const result = SessionIdParser.parseSessionId(undefined);

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.error, 'Invalid or missing session ID');
    });

    it('should handle empty string', () => {
      const result = SessionIdParser.parseSessionId('');

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.error, 'Invalid or missing session ID');
    });

    it('should handle non-string input', () => {
      const result = SessionIdParser.parseSessionId(12345);

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.error, 'Invalid or missing session ID');
    });

    it('should be case-insensitive for UUID detection', () => {
      const uuid = '550E8400-E29B-41D4-A716-446655440000';
      const result = SessionIdParser.parseSessionId(uuid);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.UUID);
    });

    it('should handle project names with numbers', () => {
      const id = 'project123_session456';
      const result = SessionIdParser.parseSessionId(id);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.sessionId, 'session456');
      assert.strictEqual(result.projectName, 'project123');
    });

    it('should handle project names with hyphens', () => {
      const id = 'my-cool-project_session789';
      const result = SessionIdParser.parseSessionId(id);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.sessionId, 'session789');
      assert.strictEqual(result.projectName, 'my-cool-project');
    });
  });

  describe('extractProjectName', () => {
    it('should extract project name from composite ID', () => {
      const result = SessionIdParser.extractProjectName('my-project_session123');
      assert.strictEqual(result, 'my-project');
    });

    it('should return fallback for simple ID', () => {
      const result = SessionIdParser.extractProjectName('session123');
      assert.strictEqual(result, 'Project');
    });

    it('should use custom fallback', () => {
      const result = SessionIdParser.extractProjectName('session123', 'Default');
      assert.strictEqual(result, 'Default');
    });

    it('should extract from multi-part project name', () => {
      const result = SessionIdParser.extractProjectName('my_awesome_project_123');
      assert.strictEqual(result, 'my_awesome_project');
    });

    it('should return fallback for UUID', () => {
      const result = SessionIdParser.extractProjectName('550e8400-e29b-41d4-a716-446655440000');
      assert.strictEqual(result, 'Project');
    });

    it('should handle null input', () => {
      const result = SessionIdParser.extractProjectName(null);
      assert.strictEqual(result, 'Project');
    });
  });

  describe('extractSessionId', () => {
    it('should extract session ID from composite format', () => {
      const result = SessionIdParser.extractSessionId('project_session123');
      assert.strictEqual(result, 'session123');
    });

    it('should return original for simple format', () => {
      const result = SessionIdParser.extractSessionId('session123');
      assert.strictEqual(result, 'session123');
    });

    it('should return UUID as-is', () => {
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      const result = SessionIdParser.extractSessionId(uuid);
      assert.strictEqual(result, uuid);
    });

    it('should extract from composite with UUID', () => {
      const result = SessionIdParser.extractSessionId(
        'project_550e8400-e29b-41d4-a716-446655440000'
      );
      assert.strictEqual(result, '550e8400-e29b-41d4-a716-446655440000');
    });

    it('should handle null input', () => {
      const result = SessionIdParser.extractSessionId(null);
      assert.strictEqual(result, null);
    });
  });

  describe('isValidSessionId', () => {
    it('should validate UUID format', () => {
      assert.strictEqual(
        SessionIdParser.isValidSessionId('550e8400-e29b-41d4-a716-446655440000'),
        true
      );
    });

    it('should validate composite format', () => {
      assert.strictEqual(SessionIdParser.isValidSessionId('project_session123'), true);
    });

    it('should validate simple format', () => {
      assert.strictEqual(SessionIdParser.isValidSessionId('session123'), true);
    });

    it('should reject null', () => {
      assert.strictEqual(SessionIdParser.isValidSessionId(null), false);
    });

    it('should reject empty string', () => {
      assert.strictEqual(SessionIdParser.isValidSessionId(''), false);
    });

    it('should reject non-string', () => {
      assert.strictEqual(SessionIdParser.isValidSessionId(12345), false);
    });
  });

  describe('getFormat', () => {
    it('should identify UUID format', () => {
      assert.strictEqual(
        SessionIdParser.getFormat('550e8400-e29b-41d4-a716-446655440000'),
        SESSION_ID_FORMATS.UUID
      );
    });

    it('should identify composite format', () => {
      assert.strictEqual(
        SessionIdParser.getFormat('project_session'),
        SESSION_ID_FORMATS.COMPOSITE
      );
    });

    it('should identify simple format', () => {
      assert.strictEqual(SessionIdParser.getFormat('session123'), SESSION_ID_FORMATS.SIMPLE);
    });

    it('should return null for invalid input', () => {
      assert.strictEqual(SessionIdParser.getFormat(null), null);
      assert.strictEqual(SessionIdParser.getFormat(''), null);
    });
  });

  describe('createCompositeId', () => {
    it('should create composite ID from project and session', () => {
      const result = SessionIdParser.createCompositeId('my-project', 'session123');
      assert.strictEqual(result, 'my-project_session123');
    });

    it('should sanitize project name with spaces', () => {
      const result = SessionIdParser.createCompositeId('my project', 'session123');
      assert.strictEqual(result, 'my_project_session123');
    });

    it('should sanitize special characters', () => {
      const result = SessionIdParser.createCompositeId('my@#$project!', 'session123');
      // The implementation collapses multiple underscores for cleaner IDs
      assert.strictEqual(result, 'my_project_session123');
    });

    it('should remove leading/trailing underscores', () => {
      const result = SessionIdParser.createCompositeId('_project_', 'session123');
      assert.strictEqual(result, 'project_session123');
    });

    it('should collapse multiple underscores', () => {
      const result = SessionIdParser.createCompositeId('my___project', 'session123');
      assert.strictEqual(result, 'my_project_session123');
    });

    it('should throw error for missing project name', () => {
      assert.throws(
        () => SessionIdParser.createCompositeId(null, 'session123'),
        /Both projectName and sessionId are required/
      );

      assert.throws(
        () => SessionIdParser.createCompositeId('', 'session123'),
        /Both projectName and sessionId are required/
      );
    });

    it('should throw error for missing session ID', () => {
      assert.throws(
        () => SessionIdParser.createCompositeId('project', null),
        /Both projectName and sessionId are required/
      );

      assert.throws(
        () => SessionIdParser.createCompositeId('project', ''),
        /Both projectName and sessionId are required/
      );
    });

    it('should preserve hyphens in project name', () => {
      const result = SessionIdParser.createCompositeId('my-cool-project', 'session123');
      assert.strictEqual(result, 'my-cool-project_session123');
    });

    it('should handle project name with numbers', () => {
      const result = SessionIdParser.createCompositeId('project123', 'session456');
      assert.strictEqual(result, 'project123_session456');
    });
  });

  describe('Convenience functions', () => {
    it('parseSessionId should work', () => {
      const result = parseSessionId('project_session123');
      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.projectName, 'project');
      assert.strictEqual(result.sessionId, 'session123');
    });

    it('extractProjectName should work', () => {
      const result = extractProjectName('project_session123');
      assert.strictEqual(result, 'project');
    });

    it('extractSessionId should work', () => {
      const result = extractSessionId('project_session123');
      assert.strictEqual(result, 'session123');
    });

    it('isValidSessionId should work', () => {
      assert.strictEqual(isValidSessionId('session123'), true);
      assert.strictEqual(isValidSessionId(null), false);
    });

    it('createCompositeSessionId should work', () => {
      const result = createCompositeSessionId('project', 'session123');
      assert.strictEqual(result, 'project_session123');
    });
  });

  describe('Edge cases', () => {
    it('should handle session ID that looks like UUID but isnt valid v4', () => {
      const fakeUuid = '550e8400-e29b-11d4-a716-446655440000'; // 11d4 instead of 41d4
      const result = SessionIdParser.parseSessionId(fakeUuid);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.SIMPLE); // Not recognized as UUID v4
      assert.strictEqual(result.sessionId, fakeUuid);
    });

    it('should handle very long session IDs', () => {
      const longId = 'a'.repeat(1000);
      const result = SessionIdParser.parseSessionId(longId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.SIMPLE);
      assert.strictEqual(result.sessionId, longId);
    });

    it('should handle session ID with only underscores', () => {
      const id = '___';
      const result = SessionIdParser.parseSessionId(id);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.projectName, '__');
      assert.strictEqual(result.sessionId, '');
    });

    it('should handle single underscore', () => {
      const id = '_';
      const result = SessionIdParser.parseSessionId(id);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.SIMPLE); // Single underscore treated as simple
      assert.strictEqual(result.sessionId, '_');
    });

    it('should handle whitespace-only input', () => {
      const result = SessionIdParser.parseSessionId('   ');

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.error, 'Invalid or missing session ID');
    });
  });
});
