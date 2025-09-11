/**
 * Unit tests for template-engine.js service
 * Note: These are simplified tests that verify the service exports exist
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';

describe('TemplateEngine', () => {
  it('should export TemplateEngine class', async () => {
    const templateModule = await import('../../services/template-engine.js');
    assert(templateModule.TemplateEngine, 'Should export TemplateEngine class');
    assert(
      typeof templateModule.TemplateEngine === 'function',
      'TemplateEngine should be a constructor'
    );
  });

  it('should create an instance', async () => {
    const { TemplateEngine } = await import('../../services/template-engine.js');
    const instance = new TemplateEngine();
    assert(instance, 'Should create an instance');
    assert(instance instanceof TemplateEngine, 'Should be an instance of TemplateEngine');
  });
});
