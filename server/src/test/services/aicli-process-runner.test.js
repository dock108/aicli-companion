import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { AICLIProcessRunner } from '../../services/aicli-process-runner.js';

describe('AICLI Process Runner - Basic Tests', () => {
  let processRunner;

  beforeEach(() => {
    // Always use test mode to avoid spawning real processes
    process.env.NODE_ENV = 'test';
    processRunner = new AICLIProcessRunner();
  });

  describe('Configuration', () => {
    it('should create instance with default options', () => {
      assert.ok(processRunner);
      // _aicliCommand is lazily initialized as null, use the getter instead
      assert.ok(processRunner.aicliCommand);
    });

    it('should set permission mode', () => {
      processRunner.setPermissionMode('strict');
      assert.ok(processRunner);
    });

    it('should set allowed tools', () => {
      processRunner.setAllowedTools(['Read', 'Write']);
      assert.ok(processRunner.allowedTools);
      assert.strictEqual(processRunner.allowedTools.length, 2);
    });

    it('should set disallowed tools', () => {
      processRunner.setDisallowedTools(['Bash']);
      assert.ok(processRunner.disallowedTools);
      assert.strictEqual(processRunner.disallowedTools.length, 1);
    });

    it('should set skip permissions', () => {
      processRunner.setSkipPermissions(true);
      assert.strictEqual(processRunner.skipPermissions, true);
    });
  });

  describe('Health Monitor', () => {
    it('should create health monitor', () => {
      const monitor = processRunner.createHealthMonitor({ pid: 12345 }, 'test-session');
      assert.ok(monitor);
      assert.ok(monitor.recordActivity);
      assert.ok(monitor.cleanup);

      // Cleanup to avoid interval leak
      monitor.cleanup();
    });

    it('should handle null process in health monitor', () => {
      const monitor = processRunner.createHealthMonitor(null, 'test-session');
      assert.ok(monitor);
      monitor.cleanup();
    });
  });

  describe('Command Finding', () => {
    it('should find AICLI command in test mode', () => {
      const command = processRunner.findAICLICommand();
      assert.strictEqual(command, 'claude');
    });
  });

  describe('Permission Arguments', () => {
    it('should add permission args when configured', () => {
      processRunner.setSkipPermissions(true);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);
      // The actual implementation uses --dangerously-skip-permissions
      assert.ok(args.includes('--dangerously-skip-permissions'));
    });

    it('should add allowed tools to args', () => {
      processRunner.setAllowedTools(['Read', 'Write']);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);
      // The actual implementation uses --allowedTools (camelCase)
      assert.ok(args.includes('--allowedTools'));
    });

    it('should add disallowed tools to args', () => {
      processRunner.setDisallowedTools(['Bash']);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);
      // The actual implementation uses --disallowedTools (camelCase)
      assert.ok(args.includes('--disallowedTools'));
    });
  });
});
