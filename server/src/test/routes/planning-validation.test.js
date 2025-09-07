/**
 * Unit tests for planning-validation.js route
 * Note: These are simplified tests that verify the route exports exist
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';

describe('Planning Validation Route', () => {
  it('should export a router', async () => {
    const planningRouter = await import('../../routes/planning-validation.js');
    assert(planningRouter.default, 'Should have a default export');
  });
});
