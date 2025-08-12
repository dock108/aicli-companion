import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { CommandSecurityService, SecurityConfig } from '../../services/command-security.js';

describe('CommandSecurityService', () => {
  let securityService;

  beforeEach(() => {
    // Reset environment variables
    delete process.env.AICLI_SAFE_DIRECTORIES;
    delete process.env.AICLI_BLOCKED_COMMANDS;
    delete process.env.AICLI_READONLY_MODE;
    delete process.env.AICLI_SECURITY_PRESET;

    securityService = new CommandSecurityService();
  });

  afterEach(() => {
    // Clean up
    securityService = null;
  });

  describe('Command Validation', () => {
    it('should allow safe commands by default', async () => {
      const result = await securityService.validateCommand('ls -la', '/tmp');
      assert.strictEqual(result.allowed, true);
      assert.strictEqual(result.reason, null);
    });

    it('should block dangerous commands in standard preset', async () => {
      // Recreate service with standard preset
      const standardService = new CommandSecurityService({ preset: 'standard' });

      const result = await standardService.validateCommand('rm -rf /', '/tmp');
      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.code, 'BLOCKED_COMMAND');
    });

    it('should block all commands with wildcard pattern', async () => {
      securityService.config.blockedCommands = ['*'];

      const result = await securityService.validateCommand('echo hello', '/tmp');
      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.reason, 'Command matches blocked pattern');
    });

    it('should detect destructive commands', async () => {
      securityService.config.requireConfirmation = true;

      const result = await securityService.validateCommand('rm -rf somedir', '/tmp');
      assert.strictEqual(result.requiresConfirmation, true);
    });

    it('should block write commands in read-only mode', async () => {
      securityService.config.readOnlyMode = true;

      const result = await securityService.validateCommand('echo test > file.txt', '/tmp');
      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.code, 'READONLY_MODE');
    });
  });

  describe('Directory Validation', () => {
    it('should allow all directories when none configured', async () => {
      const result = await securityService.validateDirectory('/etc');
      assert.strictEqual(result.allowed, true);
    });

    it('should validate against safe directories', async () => {
      securityService.config.safeDirectories = ['/tmp', '/home/user/projects'];

      const allowed = await securityService.validateDirectory('/tmp/test');
      assert.strictEqual(allowed.allowed, true);

      const blocked = await securityService.validateDirectory('/etc');
      assert.strictEqual(blocked.allowed, false);
      assert.ok(blocked.reason.includes('outside configured safe directories'));
    });

    it('should handle nested directories correctly', async () => {
      securityService.config.safeDirectories = ['/home/user/projects'];

      const result = await securityService.validateDirectory('/home/user/projects/subdir/deep');
      assert.strictEqual(result.allowed, true);
    });
  });

  describe('Path Extraction', () => {
    it('should extract absolute paths from commands', () => {
      const paths = securityService.extractPaths('cat /etc/passwd > /tmp/out.txt');
      assert.ok(paths.includes('/etc/passwd'));
      assert.ok(paths.includes('/tmp/out.txt'));
    });

    it('should extract relative paths', () => {
      const paths = securityService.extractPaths('rm ../parent/file.txt');
      assert.ok(paths.some((p) => p.includes('../parent/file.txt')));
    });

    it('should extract paths with --file arguments', () => {
      const paths = securityService.extractPaths('command --file=/var/log/app.log');
      assert.ok(paths.includes('/var/log/app.log'));
    });
  });

  describe('Security Presets', () => {
    it('should apply unrestricted preset', () => {
      const config = new SecurityConfig({ preset: 'unrestricted' });
      assert.strictEqual(config.blockedCommands.length, 0);
      assert.strictEqual(config.requireConfirmation, false);
      assert.strictEqual(config.readOnlyMode, false);
    });

    it('should apply standard preset', () => {
      const config = new SecurityConfig({ preset: 'standard' });
      assert.ok(config.blockedCommands.length > 0);
      assert.ok(config.blockedCommands.includes('rm -rf /'));
      assert.strictEqual(config.requireConfirmation, true);
      assert.strictEqual(config.readOnlyMode, false);
    });

    it('should apply restricted preset', () => {
      const config = new SecurityConfig({ preset: 'restricted' });
      assert.ok(config.blockedCommands.includes('*'));
      assert.strictEqual(config.requireConfirmation, true);
      assert.strictEqual(config.readOnlyMode, true);
    });
  });

  describe('Blocked Command Detection', () => {
    it('should handle literal patterns safely', () => {
      securityService.config.blockedCommands = ['test.file*'];

      // Should not match due to literal interpretation
      assert.strictEqual(securityService.isBlockedCommand('test.fileX'), false);
      assert.strictEqual(securityService.isBlockedCommand('testXfile'), false);

      // Should match exact command
      assert.strictEqual(securityService.isBlockedCommand('test.file*'), true);
    });

    it('should handle regex patterns when prefixed', () => {
      securityService.config.blockedCommands = ['re:test\\.file.*'];

      // Should match due to regex interpretation
      assert.strictEqual(securityService.isBlockedCommand('test.file.txt'), true);
      assert.strictEqual(securityService.isBlockedCommand('test.file123'), true);

      // Should not match
      assert.strictEqual(securityService.isBlockedCommand('testXfile.txt'), false);
    });

    it('should match command with arguments', () => {
      securityService.config.blockedCommands = ['rm'];

      assert.strictEqual(securityService.isBlockedCommand('rm file.txt'), true);
      assert.strictEqual(securityService.isBlockedCommand('rm'), true);
      assert.strictEqual(securityService.isBlockedCommand('rmdir'), false);
    });

    it('should handle path-specific blocks correctly', () => {
      securityService.config.blockedCommands = ['rm -rf /'];

      assert.strictEqual(securityService.isBlockedCommand('rm -rf /'), true);
      assert.strictEqual(securityService.isBlockedCommand('rm -rf / --force'), true);
      assert.strictEqual(securityService.isBlockedCommand('rm -rf /home/user'), false);
    });
  });

  describe('Audit Logging', () => {
    beforeEach(() => {
      securityService.config.enableAudit = true;
    });

    it('should log allowed commands', async () => {
      await securityService.validateCommand('ls', '/tmp');

      const log = securityService.getAuditLog();
      assert.strictEqual(log.length, 1);
      assert.strictEqual(log[0].allowed, true);
      assert.strictEqual(log[0].command, 'ls');
    });

    it('should log blocked commands', async () => {
      securityService.config.blockedCommands = ['rm'];

      await securityService.validateCommand('rm file.txt', '/tmp');

      const log = securityService.getAuditLog();
      assert.strictEqual(log.length, 1);
      assert.strictEqual(log[0].allowed, false);
      assert.ok(log[0].reason);
    });

    it('should filter audit log by criteria', async () => {
      await securityService.validateCommand('ls', '/tmp');
      securityService.config.blockedCommands = ['rm'];
      await securityService.validateCommand('rm file', '/tmp');

      const blockedOnly = securityService.getAuditLog({ allowed: false });
      assert.strictEqual(blockedOnly.length, 1);
      assert.strictEqual(blockedOnly[0].allowed, false);
    });

    it('should clear audit log', async () => {
      await securityService.validateCommand('ls', '/tmp');
      await securityService.validateCommand('pwd', '/tmp');

      const count = securityService.clearAuditLog();
      assert.strictEqual(count, 2);
      assert.strictEqual(securityService.getAuditLog().length, 0);
    });
  });

  describe('Permission Requests', () => {
    it('should create permission request', async () => {
      const requestId = await securityService.requestPermission('rm -rf dir', '/tmp');
      assert.ok(requestId);

      const pending = securityService.getPendingPermissions();
      assert.strictEqual(pending.length, 1);
      assert.strictEqual(pending[0].command, 'rm -rf dir');
    });

    it('should approve permission request', async () => {
      const requestId = await securityService.requestPermission('rm file', '/tmp');

      const result = securityService.approvePermission(requestId);
      assert.strictEqual(result.status, 'approved');

      const pending = securityService.getPendingPermissions();
      assert.strictEqual(pending.length, 0);
    });

    it('should deny permission request', async () => {
      const requestId = await securityService.requestPermission('rm file', '/tmp');

      const result = securityService.denyPermission(requestId, 'Too dangerous');
      assert.strictEqual(result.status, 'denied');
      assert.strictEqual(result.reason, 'Too dangerous');
    });
  });

  describe('Write Command Detection', () => {
    it('should detect output redirection', () => {
      assert.strictEqual(securityService.isWriteCommand('echo test > file'), true);
      assert.strictEqual(securityService.isWriteCommand('cat file'), false);
    });

    it('should detect file operations', () => {
      assert.strictEqual(securityService.isWriteCommand('rm file'), true);
      assert.strictEqual(securityService.isWriteCommand('mkdir dir'), true);
      assert.strictEqual(securityService.isWriteCommand('touch file'), true);
      assert.strictEqual(securityService.isWriteCommand('ls'), false);
    });

    it('should detect git write operations', () => {
      assert.strictEqual(securityService.isWriteCommand('git add .'), true);
      assert.strictEqual(securityService.isWriteCommand('git commit'), true);
      assert.strictEqual(securityService.isWriteCommand('git status'), false);
    });
  });

  describe('Destructive Command Detection', () => {
    it('should detect rm -rf patterns', () => {
      assert.strictEqual(securityService.isDestructiveCommand('rm -rf /'), true);
      assert.strictEqual(securityService.isDestructiveCommand('rm -rf dir'), true);
      assert.strictEqual(securityService.isDestructiveCommand('rm file'), false);
    });

    it('should detect format commands', () => {
      assert.strictEqual(securityService.isDestructiveCommand('format C:'), true);
      assert.strictEqual(securityService.isDestructiveCommand('diskutil eraseDisk'), true);
    });

    it('should detect fork bombs', () => {
      assert.strictEqual(securityService.isDestructiveCommand(':(){ :|:& };:'), true);
    });
  });

  describe('Configuration Update', () => {
    it('should update configuration', () => {
      securityService.updateConfig({
        readOnlyMode: true,
        maxFileSize: 1024,
      });

      assert.strictEqual(securityService.config.readOnlyMode, true);
      assert.strictEqual(securityService.config.maxFileSize, 1024);
    });

    it('should emit config update event', (t, done) => {
      securityService.once('configUpdated', (config) => {
        assert.strictEqual(config.readOnlyMode, true);
        done();
      });

      securityService.updateConfig({ readOnlyMode: true });
    });
  });

  describe('Test Command', () => {
    it('should test command without logging', async () => {
      securityService.config.enableAudit = true;

      const result = await securityService.testCommand('rm file', '/tmp');
      assert.ok('allowed' in result);

      // Should not be in audit log
      const log = securityService.getAuditLog();
      assert.strictEqual(log.length, 0);
    });
  });
});
