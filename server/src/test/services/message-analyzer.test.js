/**
 * Tests for Message Analyzer Service
 */

import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert';
import { MessageAnalyzer } from '../../services/message-analyzer.js';

describe('MessageAnalyzer', () => {
  let analyzer;

  beforeEach(() => {
    analyzer = new MessageAnalyzer();
  });

  describe('extractIntent', () => {
    test('should detect completion intent', () => {
      const message = 'The task is complete and all tests are passing.';
      const result = analyzer.extractIntent(message);

      assert.strictEqual(result.type, 'completion');
      assert.ok(result.confidence >= 0.8);
      assert.ok(result.match);
    });

    test('should detect error intent', () => {
      const message = 'Tests are failing with a compilation error.';
      const result = analyzer.extractIntent(message);

      assert.strictEqual(result.type, 'error');
      assert.ok(result.confidence >= 0.75);
    });

    test('should detect clarification intent', () => {
      const message = 'I need more clarification on what you want me to implement.';
      const result = analyzer.extractIntent(message);

      assert.strictEqual(result.type, 'clarification');
      assert.ok(result.confidence >= 0.8);
    });

    test('should detect progress intent', () => {
      const message = "I'm working on implementing the new feature.";
      const result = analyzer.extractIntent(message);

      assert.strictEqual(result.type, 'progress');
      assert.ok(result.confidence >= 0.6);
    });

    test('should detect waiting intent', () => {
      const message = 'Please provide the configuration details.';
      const result = analyzer.extractIntent(message);

      assert.strictEqual(result.type, 'waiting');
      assert.ok(result.confidence >= 0.7);
    });

    test('should return unknown for unrecognized patterns', () => {
      const message = 'The weather is nice today.';
      const result = analyzer.extractIntent(message);

      assert.strictEqual(result.type, 'unknown');
      assert.strictEqual(result.confidence, 0);
    });

    test('should handle empty or invalid input', () => {
      assert.strictEqual(analyzer.extractIntent('').type, 'unknown');
      assert.strictEqual(analyzer.extractIntent(null).type, 'unknown');
      assert.strictEqual(analyzer.extractIntent(undefined).type, 'unknown');
    });
  });

  describe('detectCompletion', () => {
    test('should detect strong completion indicators', () => {
      const message = 'All tests pass and the build is successful.';
      const result = analyzer.detectCompletion(message);

      assert.strictEqual(result.isComplete, true);
      assert.strictEqual(result.success, true);
      assert.ok(result.confidence >= 0.9);
      assert.ok(result.indicators.length > 0);
    });

    test('should detect moderate completion indicators', () => {
      const message = 'I have finished implementing the feature.';
      const result = analyzer.detectCompletion(message);

      assert.strictEqual(result.isComplete, true);
      assert.strictEqual(result.success, true);
      assert.ok(result.confidence >= 0.7);
    });

    test('should detect failure completion', () => {
      const message = 'The task cannot be completed due to missing dependencies.';
      const result = analyzer.detectCompletion(message);

      assert.strictEqual(result.isComplete, true);
      assert.strictEqual(result.success, false);
      assert.ok(result.confidence >= 0.8);
    });

    test('should not detect completion for in-progress messages', () => {
      const message = "I'm currently working on the implementation.";
      const result = analyzer.detectCompletion(message);

      assert.strictEqual(result.isComplete, false);
      assert.strictEqual(result.confidence, 0);
    });
  });

  describe('detectShowstopper', () => {
    test('should detect fatal errors', () => {
      const message = 'Fatal error: Cannot access the database.';
      const result = analyzer.detectShowstopper(message);

      assert.strictEqual(result.isShowstopper, true);
      assert.strictEqual(result.requiresEscalation, true);
      assert.ok(result.reasons.length > 0);
      assert.strictEqual(result.reasons[0].severity, 'critical');
    });

    test('should detect permission issues', () => {
      const message = 'Permission denied when trying to write to the directory.';
      const result = analyzer.detectShowstopper(message);

      assert.strictEqual(result.isShowstopper, true);
      assert.strictEqual(result.requiresEscalation, true);
    });

    test('should detect multiple failures', () => {
      const message = 'Failed to connect, failed to authenticate, and failed to fetch data.';
      const result = analyzer.detectShowstopper(message);

      assert.strictEqual(result.isShowstopper, true);
      assert.ok(result.reasons.some((r) => r.reason === 'Multiple failures detected'));
    });

    test('should not detect showstoppers in normal messages', () => {
      const message = 'Successfully implemented the feature with all tests passing.';
      const result = analyzer.detectShowstopper(message);

      assert.strictEqual(result.isShowstopper, false);
      assert.strictEqual(result.reasons.length, 0);
    });
  });

  describe('assessProgress', () => {
    test('should detect progressing state', () => {
      const messages = [
        'Starting implementation',
        'Created the main component',
        'Added validation logic',
        'Implementing tests',
      ];

      const result = analyzer.assessProgress(messages);

      assert.strictEqual(result.isProgressing, true);
      assert.ok(result.progressRate > 0.3);
      assert.strictEqual(result.stuckIndicators.length, 0);
    });

    test('should detect stuck state with repeated messages', () => {
      const messages = [
        'Trying to fix the error',
        'Trying to fix the error',
        'Trying to fix the error',
      ];

      const result = analyzer.assessProgress(messages);

      assert.strictEqual(result.isProgressing, false);
      assert.ok(result.stuckIndicators.some((i) => i.type === 'repeated_output'));
    });

    test('should detect error loops', () => {
      const messages = [
        'Error: Cannot connect',
        'Failed to establish connection',
        'Connection error occurred',
        'Unable to connect to server',
        'Connection failed again',
      ];

      const result = analyzer.assessProgress(messages);

      assert.strictEqual(result.isProgressing, false);
      assert.ok(result.stuckIndicators.some((i) => i.type === 'error_loop'));
    });

    test('should handle empty message history', () => {
      const result = analyzer.assessProgress([]);

      assert.strictEqual(result.isProgressing, false);
      assert.strictEqual(result.progressRate, 0);
    });
  });

  describe('analyzeMessage', () => {
    test('should provide comprehensive analysis', () => {
      const message = 'Task complete! All tests are passing.';
      const context = ['Working on implementation', 'Adding tests'];

      const result = analyzer.analyzeMessage(message, context);

      assert.ok(result.intent);
      assert.ok(result.completion);
      assert.ok(result.showstopper);
      assert.ok(result.progress);
      assert.ok(result.recommendation);
      assert.ok(result.priority);
      assert.ok(result.timestamp);
    });

    test('should recommend escalation for showstoppers', () => {
      const message = 'Fatal error: System crash detected.';
      const result = analyzer.analyzeMessage(message);

      assert.strictEqual(result.recommendation, 'escalate');
      assert.strictEqual(result.priority, 'critical');
    });

    test('should recommend next task for completion', () => {
      const message = 'Implementation is complete and all tests pass.';
      const result = analyzer.analyzeMessage(message);

      assert.strictEqual(result.recommendation, 'next_task');
      assert.strictEqual(result.priority, 'high');
    });

    test('should recommend clarification when needed', () => {
      const message = 'Could you please clarify what you mean by this requirement?';
      const result = analyzer.analyzeMessage(message);

      assert.strictEqual(result.recommendation, 'provide_clarification');
      assert.strictEqual(result.priority, 'high');
    });
  });

  describe('calculateSimilarity', () => {
    test('should detect high similarity', () => {
      const messages = [
        'Working on the implementation',
        'Working on the implementation',
        'Working on the implementation',
      ];

      const similarity = analyzer.calculateSimilarity(messages);
      assert.ok(similarity > 0.8);
    });

    test('should detect low similarity', () => {
      const messages = ['Starting the implementation', 'Running tests now', 'Deployment complete'];

      const similarity = analyzer.calculateSimilarity(messages);
      assert.ok(similarity < 0.5);
    });
  });
});
