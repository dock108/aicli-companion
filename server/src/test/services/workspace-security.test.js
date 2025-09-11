/**
 * Unit tests for workspace-security.js service
 * Note: These are simplified tests that verify the service exports exist
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';

describe('WorkspaceSecurity', () => {
  it('should export WorkspaceSecurity class', async () => {
    const securityModule = await import('../../services/workspace-security.js');
    assert(securityModule.WorkspaceSecurity, 'Should export WorkspaceSecurity class');
    assert(
      typeof securityModule.WorkspaceSecurity === 'function',
      'WorkspaceSecurity should be a constructor'
    );
  });

  it('should create an instance', async () => {
    const { WorkspaceSecurity } = await import('../../services/workspace-security.js');
    const instance = new WorkspaceSecurity();
    assert(instance, 'Should create an instance');
    assert(instance instanceof WorkspaceSecurity, 'Should be an instance of WorkspaceSecurity');
  });

  it('should have basic methods', async () => {
    const { WorkspaceSecurity } = await import('../../services/workspace-security.js');
    const instance = new WorkspaceSecurity();
    assert(
      typeof instance.isOperationAllowed === 'function',
      'Should have isOperationAllowed method'
    );
    assert(
      typeof instance.isPathWithinWorkspace === 'function',
      'Should have isPathWithinWorkspace method'
    );
    assert(
      typeof instance.validateWorkspaceCommand === 'function',
      'Should have validateWorkspaceCommand method'
    );
  });
});
