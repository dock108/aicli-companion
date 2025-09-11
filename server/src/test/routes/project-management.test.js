/**
 * Unit tests for project-management.js route
 * Note: These are simplified tests that verify the route exports exist
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';

describe('Project Management Route', () => {
  it('should export a router', async () => {
    const projectRouter = await import('../../routes/project-management.js');
    assert(projectRouter.default, 'Should have a default export');
  });
});
