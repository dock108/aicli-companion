import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  parseSessionId,
  extractProjectName,
  extractSessionId,
  isValidSessionId,
  createCompositeSessionId,
  SESSION_ID_FORMATS,
} from '../../utils/session-parser.js';

describe('SessionIdParser', () => {
  describe('parseSessionId', () => {
    it('should parse UUID format correctly', () => {
      const sessionId = '550e8400-e29b-41d4-a716-446655440000';
      const result = parseSessionId(sessionId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.UUID);
      assert.strictEqual(result.sessionId, sessionId);
      assert.strictEqual(result.projectName, null);
      assert.strictEqual(result.rawSessionId, sessionId);
    });

    it('should parse composite format with UUID correctly', () => {
      const sessionId = 'my_project_550e8400-e29b-41d4-a716-446655440000';
      const result = parseSessionId(sessionId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.sessionId, '550e8400-e29b-41d4-a716-446655440000');
      assert.strictEqual(result.projectName, 'my_project');
      assert.strictEqual(result.rawSessionId, sessionId);
    });

    it('should parse composite format with simple session ID', () => {
      const sessionId = 'test_session_uuid123';
      const result = parseSessionId(sessionId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.sessionId, 'uuid123');
      assert.strictEqual(result.projectName, 'test_session');
    });

    it('should handle complex project names with multiple underscores', () => {
      const sessionId = 'my_complex_project_name_abc123';
      const result = parseSessionId(sessionId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.COMPOSITE);
      assert.strictEqual(result.sessionId, 'abc123');
      assert.strictEqual(result.projectName, 'my_complex_project_name');
    });

    it('should handle simple format', () => {
      const sessionId = 'abc123';
      const result = parseSessionId(sessionId);

      assert.strictEqual(result.isValid, true);
      assert.strictEqual(result.format, SESSION_ID_FORMATS.SIMPLE);
      assert.strictEqual(result.sessionId, 'abc123');
      assert.strictEqual(result.projectName, null);
    });

    it('should handle invalid inputs', () => {
      const invalidInputs = [null, undefined, '', '   '];

      invalidInputs.forEach((input) => {
        const result = parseSessionId(input);
        if (input === '   ') {
          // Whitespace-only is treated as simple format after trimming
          assert.strictEqual(result.isValid, true);
        } else {
          assert.strictEqual(result.isValid, false);
          assert.strictEqual(result.format, null);
          assert.strictEqual(result.sessionId, null);
          assert.strictEqual(result.projectName, null);
        }
      });
    });
  });

  describe('extractProjectName', () => {
    it('should extract project name from composite session ID', () => {
      assert.strictEqual(extractProjectName('test_session_uuid123'), 'test_session');
      assert.strictEqual(extractProjectName('my_project_abc123'), 'my_project');
      assert.strictEqual(extractProjectName('complex_project_name_xyz789'), 'complex_project_name');
    });

    it('should return fallback for non-composite session IDs', () => {
      // UUIDs and simple IDs without underscores should return fallback
      assert.strictEqual(extractProjectName('550e8400-e29b-41d4-a716-446655440000'), 'Project');
      assert.strictEqual(extractProjectName('abc123'), 'Project');
    });

    it('should treat single underscore IDs as composite format', () => {
      // Single underscore is treated as composite (project_session format)
      assert.strictEqual(extractProjectName('simple_session'), 'simple');
      assert.strictEqual(extractProjectName('project_123'), 'project');
    });

    it('should use custom fallback', () => {
      assert.strictEqual(extractProjectName('abc123', 'CustomFallback'), 'CustomFallback');
      assert.strictEqual(extractProjectName(null, 'DefaultProject'), 'DefaultProject');
    });
  });

  describe('extractSessionId', () => {
    it('should extract session ID from composite format', () => {
      assert.strictEqual(extractSessionId('test_session_uuid123'), 'uuid123');
      assert.strictEqual(
        extractSessionId('my_project_550e8400-e29b-41d4-a716-446655440000'),
        '550e8400-e29b-41d4-a716-446655440000'
      );
    });

    it('should return original ID for simple formats', () => {
      assert.strictEqual(extractSessionId('abc123'), 'abc123');
      assert.strictEqual(
        extractSessionId('550e8400-e29b-41d4-a716-446655440000'),
        '550e8400-e29b-41d4-a716-446655440000'
      );
    });
  });

  describe('isValidSessionId', () => {
    it('should validate correct session IDs', () => {
      assert.strictEqual(isValidSessionId('abc123'), true);
      assert.strictEqual(isValidSessionId('test_session_uuid123'), true);
      assert.strictEqual(isValidSessionId('550e8400-e29b-41d4-a716-446655440000'), true);
    });

    it('should reject invalid session IDs', () => {
      assert.strictEqual(isValidSessionId(null), false);
      assert.strictEqual(isValidSessionId(undefined), false);
      assert.strictEqual(isValidSessionId(''), false);
    });
  });

  describe('createCompositeSessionId', () => {
    it('should create composite session ID correctly', () => {
      const result = createCompositeSessionId('My Project', 'abc123');
      assert.strictEqual(result, 'My_Project_abc123');
    });

    it('should sanitize project name', () => {
      const result = createCompositeSessionId('My Project Name!@#$%', 'session123');
      assert.strictEqual(result, 'My_Project_Name_session123');
    });

    it('should handle multiple underscores in project name', () => {
      const result = createCompositeSessionId('Project___With____Underscores', 'xyz');
      assert.strictEqual(result, 'Project_With_Underscores_xyz');
    });

    it('should throw error for missing parameters', () => {
      assert.throws(() => createCompositeSessionId('', 'session'), /required/);
      assert.throws(() => createCompositeSessionId('project', ''), /required/);
      assert.throws(() => createCompositeSessionId(null, 'session'), /required/);
    });
  });

  describe('backwards compatibility', () => {
    it('should maintain compatibility with existing test case', () => {
      // This test ensures the exact behavior expected by the existing long-running task manager test
      const sessionId = 'test_session_uuid123';
      const projectName = extractProjectName(sessionId, 'Project');

      assert.strictEqual(projectName, 'test_session');
    });
  });
});
