import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import { PermissionHandler } from '../../../services/aicli/permission-handler.js';

describe('PermissionHandler', () => {
  let permissionHandler;
  let mockProcessRunner;

  beforeEach(() => {
    mockProcessRunner = {
      permissionMode: 'default',
      allowedTools: [],
      disallowedTools: [],
      skipPermissions: false,
      setPermissionMode: mock.fn((mode) => {
        mockProcessRunner.permissionMode = mode;
      }),
      setAllowedTools: mock.fn((tools) => {
        mockProcessRunner.allowedTools = tools;
      }),
      setDisallowedTools: mock.fn((tools) => {
        mockProcessRunner.disallowedTools = tools;
      }),
      setSkipPermissions: mock.fn((skip) => {
        mockProcessRunner.skipPermissions = skip;
      }),
    };
    permissionHandler = new PermissionHandler(mockProcessRunner);
  });

  describe('constructor', () => {
    it('should initialize with process runner settings', () => {
      assert.equal(permissionHandler.permissionMode, 'default');
      assert.deepEqual(permissionHandler.allowedTools, []);
      assert.deepEqual(permissionHandler.disallowedTools, []);
      assert.equal(permissionHandler.skipPermissions, false);
    });

    it('should handle null process runner', () => {
      const handler = new PermissionHandler(null);
      assert.equal(handler.permissionMode, undefined);
      assert.deepEqual(handler.allowedTools, []);
      assert.deepEqual(handler.disallowedTools, []);
      assert.equal(handler.skipPermissions, false);
    });
  });

  describe('setPermissionMode', () => {
    it('should delegate to process runner', () => {
      permissionHandler.setPermissionMode('strict');
      assert.equal(mockProcessRunner.setPermissionMode.mock.calls.length, 1);
      assert.equal(mockProcessRunner.setPermissionMode.mock.calls[0].arguments[0], 'strict');
      assert.equal(permissionHandler.permissionMode, 'strict');
    });

    it('should handle null process runner', () => {
      const handler = new PermissionHandler(null);
      handler.setPermissionMode('strict');
      assert.equal(handler.permissionMode, undefined);
    });
  });

  describe('setAllowedTools', () => {
    it('should delegate to process runner', () => {
      const tools = ['tool1', 'tool2'];
      permissionHandler.setAllowedTools(tools);
      assert.equal(mockProcessRunner.setAllowedTools.mock.calls.length, 1);
      assert.deepEqual(mockProcessRunner.setAllowedTools.mock.calls[0].arguments[0], tools);
      assert.deepEqual(permissionHandler.allowedTools, tools);
    });
  });

  describe('setDisallowedTools', () => {
    it('should delegate to process runner', () => {
      const tools = ['danger1', 'danger2'];
      permissionHandler.setDisallowedTools(tools);
      assert.equal(mockProcessRunner.setDisallowedTools.mock.calls.length, 1);
      assert.deepEqual(mockProcessRunner.setDisallowedTools.mock.calls[0].arguments[0], tools);
      assert.deepEqual(permissionHandler.disallowedTools, tools);
    });
  });

  describe('setSkipPermissions', () => {
    it('should delegate to process runner', () => {
      permissionHandler.setSkipPermissions(true);
      assert.equal(mockProcessRunner.setSkipPermissions.mock.calls.length, 1);
      assert.equal(mockProcessRunner.setSkipPermissions.mock.calls[0].arguments[0], true);
      assert.equal(permissionHandler.skipPermissions, true);
    });
  });

  describe('buildPermissionArgs', () => {
    it('should add skip permissions flag when enabled', () => {
      permissionHandler.skipPermissions = true;
      const args = permissionHandler.buildPermissionArgs();
      assert.deepEqual(args, ['--dangerously-skip-permissions']);
    });

    it('should add skip permissions flag when passed as parameter', () => {
      const args = permissionHandler.buildPermissionArgs(true);
      assert.deepEqual(args, ['--dangerously-skip-permissions']);
    });

    it('should add permission mode when not skipping', () => {
      permissionHandler.permissionMode = 'strict';
      const args = permissionHandler.buildPermissionArgs(false);
      assert.deepEqual(args, ['--permission-mode', 'strict']);
    });

    it('should not add default permission mode', () => {
      permissionHandler.permissionMode = 'default';
      const args = permissionHandler.buildPermissionArgs(false);
      assert.deepEqual(args, []);
    });

    it('should add allowed tools when not skipping', () => {
      permissionHandler.allowedTools = ['tool1', 'tool2'];
      const args = permissionHandler.buildPermissionArgs(false);
      assert.deepEqual(args, ['--allow-tools', 'tool1,tool2']);
    });

    it('should add disallowed tools when not skipping', () => {
      permissionHandler.disallowedTools = ['danger1', 'danger2'];
      const args = permissionHandler.buildPermissionArgs(false);
      assert.deepEqual(args, ['--disallow-tools', 'danger1,danger2']);
    });

    it('should combine all permission settings', () => {
      permissionHandler.permissionMode = 'strict';
      permissionHandler.allowedTools = ['safe1'];
      permissionHandler.disallowedTools = ['danger1'];
      const args = permissionHandler.buildPermissionArgs(false);
      assert.deepEqual(args, [
        '--permission-mode',
        'strict',
        '--allow-tools',
        'safe1',
        '--disallow-tools',
        'danger1',
      ]);
    });
  });

  describe('containsApprovalResponse', () => {
    it('should detect approval responses', () => {
      assert.equal(permissionHandler.containsApprovalResponse('y'), true);
      assert.equal(permissionHandler.containsApprovalResponse('Y'), true);
      assert.equal(permissionHandler.containsApprovalResponse('yes'), true);
      assert.equal(permissionHandler.containsApprovalResponse('YES'), true);
      assert.equal(permissionHandler.containsApprovalResponse('approve'), true);
      assert.equal(permissionHandler.containsApprovalResponse(' Yes '), true);
    });

    it('should reject non-approval responses', () => {
      assert.equal(permissionHandler.containsApprovalResponse('n'), false);
      assert.equal(permissionHandler.containsApprovalResponse('no'), false);
      assert.equal(permissionHandler.containsApprovalResponse('deny'), false);
      assert.equal(permissionHandler.containsApprovalResponse(''), false);
    });
  });

  describe('handlePermissionPrompt', () => {
    let mockSessionManager;
    let mockEmitFunc;

    beforeEach(() => {
      mockSessionManager = {
        getSession: mock.fn(() => ({ sessionId: 'test-session' })),
        getSessionBuffer: mock.fn(() => ({
          pendingFinalResponse: true,
          finalResponseData: { result: 'test result' },
        })),
        clearSessionBuffer: mock.fn(),
      };
      mockEmitFunc = mock.fn();
    });

    it('should handle approval response', async () => {
      const result = await permissionHandler.handlePermissionPrompt(
        'test-session',
        'yes',
        mockSessionManager,
        mockEmitFunc
      );
      assert.equal(result, true);
      assert.equal(mockEmitFunc.mock.calls.length, 1);
      assert.equal(mockEmitFunc.mock.calls[0].arguments[0], 'conversationResult');
    });

    it('should handle denial response', async () => {
      const result = await permissionHandler.handlePermissionPrompt(
        'test-session',
        'no',
        mockSessionManager,
        mockEmitFunc
      );
      assert.equal(result, true);
      assert.equal(mockEmitFunc.mock.calls.length, 1);
      assert.equal(mockEmitFunc.mock.calls[0].arguments[0], 'permissionDenied');
    });

    it('should throw error for missing session', async () => {
      mockSessionManager.getSession = mock.fn(() => null);
      await assert.rejects(
        permissionHandler.handlePermissionPrompt(
          'missing-session',
          'yes',
          mockSessionManager,
          mockEmitFunc
        ),
        /No active session found/
      );
    });

    it('should return false when no pending permission', async () => {
      mockSessionManager.getSessionBuffer = mock.fn(() => ({
        pendingFinalResponse: false,
      }));
      const result = await permissionHandler.handlePermissionPrompt(
        'test-session',
        'yes',
        mockSessionManager,
        mockEmitFunc
      );
      assert.equal(result, false);
    });
  });
});
