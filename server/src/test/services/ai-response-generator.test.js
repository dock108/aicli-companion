/**
 * Tests for AI Response Generator Service
 */

import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert';
import { AIResponseGenerator } from '../../services/ai-response-generator.js';

describe('AIResponseGenerator', () => {
  let generator;
  let mockFetch;

  beforeEach(() => {
    // Create a mock fetch function
    mockFetch = async () => ({
      ok: true,
      json: async () => ({
        choices: [{ message: { content: 'Default mocked response' } }],
      }),
    });

    // Create generator with test configuration and mock fetch
    generator = new AIResponseGenerator({
      apiKey: 'test-api-key',
      model: 'gpt-3.5-turbo',
      temperature: 0.7,
      maxTokens: 150,
      fetch: mockFetch, // Use mock fetch
    });
  });

  describe('constructor', () => {
    test('should initialize with provided options', () => {
      assert.ok(generator);
      assert.strictEqual(generator.model, 'gpt-3.5-turbo');
      assert.strictEqual(generator.temperature, 0.7);
      assert.strictEqual(generator.maxTokens, 150);
      assert.strictEqual(generator.enabled, true);
    });

    test('should be disabled without API key', () => {
      const disabledGenerator = new AIResponseGenerator({
        apiKey: null,
      });
      assert.strictEqual(disabledGenerator.enabled, false);
    });
  });

  describe('generateResponse', () => {
    test('should generate AI response successfully', async () => {
      // Override fetch for this specific test
      generator.fetch = async () => ({
        ok: true,
        json: async () => ({
          choices: [
            {
              message: {
                content: 'Continue implementing the feature with proper error handling',
              },
            },
          ],
        }),
      });

      const context = {
        claudeOutput: 'I have started implementing the authentication feature',
        analysis: {
          intent: { type: 'progress', confidence: 0.8 },
          completion: { isComplete: false },
          showstopper: { isShowstopper: false },
          progress: { isProgressing: true },
          recommendation: 'continue',
        },
        sessionHistory: [],
        projectContext: {
          projectName: 'TestApp',
          currentTask: 'Authentication',
        },
      };

      const response = await generator.generateResponse(context);

      assert.ok(response);
      assert.strictEqual(
        response.message,
        'Continue implementing the feature with proper error handling'
      );
      assert.ok(response.confidence >= 0.5);
      assert.strictEqual(response.category, 'ai_generated');
      assert.strictEqual(response.source, 'openai');
    });

    test('should return null when disabled', async () => {
      generator.enabled = false;

      const response = await generator.generateResponse({
        claudeOutput: 'Test output',
        analysis: {},
      });

      assert.strictEqual(response, null);
    });

    test('should handle API errors gracefully', async () => {
      generator.fetch = async () => {
        throw new Error('API connection failed');
      };

      const response = await generator.generateResponse({
        claudeOutput: 'Test output',
        analysis: {
          intent: { type: 'error', confidence: 0.9 },
          completion: { isComplete: false },
          showstopper: { isShowstopper: false },
          progress: { isProgressing: false },
          recommendation: 'troubleshoot',
        },
      });

      assert.strictEqual(response, null);
    });

    test('should use cache for identical requests', async () => {
      let callCount = 0;
      generator.fetch = async () => {
        callCount++;
        return {
          ok: true,
          json: async () => ({
            choices: [{ message: { content: 'Cached response' } }],
          }),
        };
      };

      const context = {
        claudeOutput: 'Test',
        analysis: {
          intent: { type: 'progress', confidence: 0.8 },
          completion: { isComplete: false },
          showstopper: { isShowstopper: false },
          progress: { isProgressing: true },
          recommendation: 'continue',
        },
      };

      // First call
      const response1 = await generator.generateResponse(context);
      assert.ok(response1);

      // Second call should use cache
      const response2 = await generator.generateResponse(context);
      assert.ok(response2);
      assert.strictEqual(response2.message, response1.message);

      // Fetch should only be called once due to caching
      assert.strictEqual(callCount, 1);
    });
  });

  describe('buildPrompt', () => {
    test('should build comprehensive prompt', () => {
      const context = {
        claudeOutput: 'Test output',
        analysis: {
          intent: { type: 'completion', confidence: 0.9 },
          completion: { isComplete: true, success: true },
          showstopper: { isShowstopper: false },
          progress: { isProgressing: true },
          recommendation: 'next_task',
        },
        sessionHistory: [
          { type: 'claude', message: 'Previous message' },
          { type: 'agent', message: 'Agent response' },
        ],
        projectContext: {
          projectName: 'TestProject',
          currentTask: 'Feature implementation',
        },
        trainingExamples: [
          {
            situation: 'Similar completion',
            response: 'Move to the next task',
          },
        ],
      };

      const prompt = generator.buildPrompt(context);

      assert.ok(Array.isArray(prompt));
      assert.strictEqual(prompt.length, 2);
      assert.strictEqual(prompt[0].role, 'system');
      assert.strictEqual(prompt[1].role, 'user');
      assert.ok(prompt[0].content.includes('TestProject'));
      assert.ok(prompt[1].content.includes('completion'));
    });
  });

  describe('structureResponse', () => {
    test('should structure AI response with confidence', () => {
      const aiResponse = 'Continue with the implementation';
      const context = {
        analysis: {
          intent: { type: 'progress', confidence: 0.8 },
          showstopper: { isShowstopper: false },
        },
        sessionHistory: Array(6).fill({ type: 'claude', message: 'msg' }),
      };

      const structured = generator.structureResponse(aiResponse, context);

      assert.strictEqual(structured.message, aiResponse);
      assert.ok(structured.confidence >= 0.7);
      assert.strictEqual(structured.category, 'ai_generated');
      assert.strictEqual(structured.source, 'openai');
      assert.strictEqual(structured.model, 'gpt-3.5-turbo');
    });

    test('should set high confidence for showstoppers', () => {
      const context = {
        analysis: {
          intent: { type: 'error', confidence: 0.9 },
          showstopper: {
            isShowstopper: true,
            reasons: [{ reason: 'Fatal error' }],
          },
        },
      };

      const structured = generator.structureResponse('Escalate to user', context);
      assert.strictEqual(structured.confidence, 0.95);
      assert.strictEqual(structured.isEscalation, true);
    });
  });

  describe('checkRateLimit', () => {
    test('should enforce rate limiting', () => {
      generator.maxRequestsPerMinute = 2;
      generator.requestCount = 0;

      assert.strictEqual(generator.checkRateLimit(), true);
      generator.requestCount = 1;
      assert.strictEqual(generator.checkRateLimit(), true);
      generator.requestCount = 2;
      assert.strictEqual(generator.checkRateLimit(), false);
    });

    test('should reset rate limit after time window', () => {
      generator.requestCount = 10;
      generator.requestResetTime = Date.now() - 1000; // Past time

      assert.strictEqual(generator.checkRateLimit(), true);
      assert.strictEqual(generator.requestCount, 0);
    });
  });

  describe('validateConfiguration', () => {
    test('should validate valid configuration', () => {
      const result = generator.validateConfiguration();
      assert.strictEqual(result.valid, true);
      assert.strictEqual(result.issues.length, 0);
      assert.strictEqual(result.enabled, true);
    });

    test('should detect invalid configuration', () => {
      const invalidGenerator = new AIResponseGenerator({
        apiKey: null,
        model: 'invalid-model',
        temperature: 3.0,
        maxTokens: 5000,
      });

      const result = invalidGenerator.validateConfiguration();
      assert.strictEqual(result.valid, false);
      assert.ok(result.issues.length > 0);
      assert.ok(result.issues.some((i) => i.includes('API key')));
      assert.ok(result.issues.some((i) => i.includes('model')));
      assert.ok(result.issues.some((i) => i.includes('temperature')));
      assert.ok(result.issues.some((i) => i.includes('tokens')));
    });
  });

  describe('truncateText', () => {
    test('should truncate long text', () => {
      const longText = 'a'.repeat(200);
      const truncated = generator.truncateText(longText, 100);
      assert.strictEqual(truncated.length, 103); // 100 + '...'
      assert.ok(truncated.endsWith('...'));
    });

    test('should not truncate short text', () => {
      const shortText = 'Short text';
      const result = generator.truncateText(shortText, 100);
      assert.strictEqual(result, shortText);
    });
  });

  describe('estimateTokens', () => {
    test('should estimate token count', () => {
      const context = {
        claudeOutput: 'a'.repeat(400), // 400 characters
        analysis: {},
      };

      const tokens = generator.estimateTokens(context);
      assert.ok(tokens > 100); // Rough estimate
    });
  });
});
