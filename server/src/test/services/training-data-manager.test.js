/**
 * Tests for Training Data Manager Service
 */

import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { TrainingDataManager } from '../../services/training-data-manager.js';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TEST_DATA_DIR = path.join(__dirname, 'test-training-data');

describe('TrainingDataManager', () => {
  let manager;

  beforeEach(async () => {
    // Create test data directory
    await fs.mkdir(TEST_DATA_DIR, { recursive: true });

    // Create manager with test directory
    manager = new TrainingDataManager({
      dataDir: TEST_DATA_DIR,
      maxExamples: 10,
      minConfidence: 0.6,
    });

    // Wait for initialization
    await manager.initialized;
  });

  afterEach(async () => {
    // Clean up test data directory
    try {
      await fs.rm(TEST_DATA_DIR, { recursive: true, force: true });
    } catch (error) {
      // Directory might not exist
    }
  });

  describe('recordInteraction', () => {
    test('should record accepted high-confidence interactions', async () => {
      const interaction = {
        projectId: 'test-project',
        sessionId: 'session-123',
        claudeOutput: 'Task completed successfully',
        analysis: {
          intent: { type: 'completion' },
          completion: { isComplete: true },
          recommendation: 'next_task',
        },
        response: {
          message: 'Move to the next task',
          confidence: 0.8,
        },
        accepted: true,
        confidence: 0.8,
        context: {
          projectName: 'TestApp',
          currentTask: 'Feature implementation',
        },
      };

      await manager.recordInteraction(interaction);

      const examples = manager.trainingData.get('test-project');
      assert.ok(examples);
      assert.strictEqual(examples.length, 1);
      assert.strictEqual(examples[0].response, 'Move to the next task');
    });

    test('should not record rejected interactions', async () => {
      const interaction = {
        projectId: 'test-project',
        sessionId: 'session-123',
        claudeOutput: 'Error occurred',
        analysis: {
          intent: { type: 'error' },
          completion: { isComplete: false },
          recommendation: 'troubleshoot',
        },
        response: {
          message: 'Try again',
          confidence: 0.7,
        },
        accepted: false,
        confidence: 0.7,
      };

      await manager.recordInteraction(interaction);

      const examples = manager.trainingData.get('test-project');
      assert.ok(!examples || examples.length === 0);
    });

    test('should not record low-confidence interactions', async () => {
      const interaction = {
        projectId: 'test-project',
        sessionId: 'session-123',
        claudeOutput: 'Unclear situation',
        analysis: {
          intent: { type: 'unknown' },
          completion: { isComplete: false },
          recommendation: 'continue',
        },
        response: {
          message: 'Continue',
          confidence: 0.4,
        },
        accepted: true,
        confidence: 0.4,
      };

      await manager.recordInteraction(interaction);

      const examples = manager.trainingData.get('test-project');
      assert.ok(!examples || examples.length === 0);
    });

    test('should limit number of examples', async () => {
      manager.maxExamples = 3;

      for (let i = 0; i < 5; i++) {
        await manager.recordInteraction({
          projectId: 'test-project',
          sessionId: `session-${i}`,
          claudeOutput: `Output ${i}`,
          analysis: {
            intent: { type: 'progress' },
            completion: { isComplete: false },
            recommendation: 'continue',
          },
          response: {
            message: `Response ${i}`,
            confidence: 0.8,
          },
          accepted: true,
          confidence: 0.8,
        });
      }

      const examples = manager.trainingData.get('test-project');
      assert.strictEqual(examples.length, 3);
      // Should keep the most recent ones
      assert.strictEqual(examples[2].response, 'Response 4');
    });
  });

  describe('getRelevantExamples', () => {
    beforeEach(async () => {
      // Add some test examples
      const examples = [
        {
          id: '1',
          timestamp: new Date().toISOString(),
          intent: 'completion',
          completion: true,
          recommendation: 'next_task',
          situation: 'Task completed',
          response: 'Move to next task',
          confidence: 0.9,
        },
        {
          id: '2',
          timestamp: new Date().toISOString(),
          intent: 'error',
          completion: false,
          recommendation: 'troubleshoot',
          situation: 'Error occurred',
          response: 'Debug the error',
          confidence: 0.8,
        },
        {
          id: '3',
          timestamp: new Date().toISOString(),
          intent: 'progress',
          completion: false,
          recommendation: 'continue',
          situation: 'In progress',
          response: 'Continue working',
          confidence: 0.7,
        },
      ];

      manager.trainingData.set('test-project', examples);
    });

    test('should return relevant examples based on intent', () => {
      const analysis = {
        intent: { type: 'completion' },
        completion: { isComplete: true },
        recommendation: 'next_task',
      };

      const relevant = manager.getRelevantExamples('test-project', analysis, 2);

      assert.ok(relevant.length > 0);
      assert.strictEqual(relevant[0].intent, 'completion');
    });

    test('should score examples by relevance', () => {
      const analysis = {
        intent: { type: 'error' },
        completion: { isComplete: false },
        recommendation: 'troubleshoot',
      };

      const relevant = manager.getRelevantExamples('test-project', analysis, 5);

      assert.ok(relevant.length > 0);
      // Error example should be first
      assert.strictEqual(relevant[0].intent, 'error');
    });

    test('should limit number of returned examples', () => {
      const analysis = {
        intent: { type: 'progress' },
        completion: { isComplete: false },
        recommendation: 'continue',
      };

      const relevant = manager.getRelevantExamples('test-project', analysis, 1);
      assert.strictEqual(relevant.length, 1);
    });

    test('should return empty array for unknown project', () => {
      const analysis = {
        intent: { type: 'completion' },
        completion: { isComplete: true },
        recommendation: 'next_task',
      };

      const relevant = manager.getRelevantExamples('unknown-project', analysis, 5);
      assert.strictEqual(relevant.length, 0);
    });
  });

  describe('getStatistics', () => {
    test('should calculate project statistics', async () => {
      // Add some examples
      for (let i = 0; i < 3; i++) {
        await manager.recordInteraction({
          projectId: 'test-project',
          sessionId: `session-${i}`,
          claudeOutput: `Output ${i}`,
          analysis: {
            intent: { type: i === 0 ? 'completion' : 'progress' },
            completion: { isComplete: i === 0 },
            recommendation: i === 0 ? 'next_task' : 'continue',
          },
          response: {
            message: `Response ${i}`,
            confidence: 0.7 + i * 0.1,
          },
          accepted: true,
          confidence: 0.7 + i * 0.1,
        });
      }

      const stats = manager.getStatistics('test-project');

      assert.strictEqual(stats.totalExamples, 3);
      assert.ok(stats.intentDistribution);
      assert.strictEqual(stats.intentDistribution.completion, 1);
      assert.strictEqual(stats.intentDistribution.progress, 2);
      assert.ok(stats.averageConfidence > 0);
    });

    test('should return overall statistics', () => {
      manager.statistics.set('project1', {
        totalExamples: 5,
        intentDistribution: { progress: 3, completion: 2 },
        averageConfidence: 0.75,
      });
      manager.statistics.set('project2', {
        totalExamples: 3,
        intentDistribution: { error: 2, progress: 1 },
        averageConfidence: 0.65,
      });

      const overall = manager.getStatistics();

      assert.strictEqual(overall.totalProjects, 2);
      assert.strictEqual(overall.totalExamples, 8);
      assert.ok(overall.projects.project1);
      assert.ok(overall.projects.project2);
    });
  });

  describe('importTrainingData', () => {
    test('should import valid training examples', async () => {
      const examples = [
        {
          situation: 'Task completed',
          response: 'Move to next',
          intent: 'completion',
        },
        {
          situation: 'Error found',
          response: 'Debug it',
          intent: 'error',
        },
        {
          // Invalid - missing required fields
          response: 'Invalid example',
        },
      ];

      const result = await manager.importTrainingData('test-project', examples);

      assert.strictEqual(result.imported, 2);
      assert.strictEqual(result.skipped, 1);

      const imported = manager.trainingData.get('test-project');
      assert.strictEqual(imported.length, 2);
    });

    test('should handle non-array input', async () => {
      await assert.rejects(
        async () => {
          await manager.importTrainingData('test-project', 'not an array');
        },
        {
          message: 'Examples must be an array',
        }
      );
    });
  });

  describe('exportTrainingData', () => {
    test('should export training data', async () => {
      const examples = [
        {
          id: '1',
          situation: 'Test situation',
          response: 'Test response',
          intent: 'progress',
        },
      ];
      manager.trainingData.set('test-project', examples);

      const exported = await manager.exportTrainingData('test-project');

      assert.deepStrictEqual(exported, examples);
    });

    test('should return empty array for unknown project', async () => {
      const exported = await manager.exportTrainingData('unknown-project');
      assert.deepStrictEqual(exported, []);
    });
  });

  describe('clearTrainingData', () => {
    test('should clear project training data', async () => {
      manager.trainingData.set('test-project', [{ id: '1' }]);
      manager.statistics.set('test-project', { totalExamples: 1 });

      await manager.clearTrainingData('test-project');

      assert.ok(!manager.trainingData.has('test-project'));
      assert.ok(!manager.statistics.has('test-project'));
    });
  });

  describe('analyzeDataQuality', () => {
    test('should analyze data quality', async () => {
      // Add varied examples
      for (let i = 0; i < 15; i++) {
        await manager.recordInteraction({
          projectId: 'test-project',
          sessionId: `session-${i}`,
          claudeOutput: `Output ${i}`,
          analysis: {
            intent: { type: ['completion', 'progress', 'error'][i % 3] },
            completion: { isComplete: i % 3 === 0 },
            recommendation: ['next_task', 'continue', 'troubleshoot'][i % 3],
          },
          response: {
            message: `Response ${i}`,
            confidence: 0.6 + (i % 4) * 0.1,
          },
          accepted: true,
          confidence: 0.6 + (i % 4) * 0.1,
        });
      }

      const quality = manager.analyzeDataQuality('test-project');

      assert.ok(['good', 'moderate', 'poor'].includes(quality.quality));
      assert.ok(quality.examples > 0);
      assert.ok(quality.intentCoverage >= 3);
      assert.ok(quality.averageConfidence > 0);
      assert.ok(Array.isArray(quality.recommendations));
    });

    test('should detect insufficient data', () => {
      const quality = manager.analyzeDataQuality('test-project');

      assert.strictEqual(quality.quality, 'insufficient');
      assert.strictEqual(quality.examples, 0);
      assert.ok(quality.recommendations.includes('Need more training examples'));
    });

    test('should detect limited intent coverage', async () => {
      // Add examples with only one intent type
      for (let i = 0; i < 5; i++) {
        await manager.recordInteraction({
          projectId: 'test-project',
          sessionId: `session-${i}`,
          claudeOutput: `Output ${i}`,
          analysis: {
            intent: { type: 'progress' },
            completion: { isComplete: false },
            recommendation: 'continue',
          },
          response: {
            message: `Response ${i}`,
            confidence: 0.8,
          },
          accepted: true,
          confidence: 0.8,
        });
      }

      const quality = manager.analyzeDataQuality('test-project');

      assert.ok(quality.recommendations.some((r) => r.includes('Limited intent coverage')));
    });
  });

  describe('persistence', () => {
    test('should save and load project data', async () => {
      // Add some data
      await manager.recordInteraction({
        projectId: 'persist-test',
        sessionId: 'session-1',
        claudeOutput: 'Test output',
        analysis: {
          intent: { type: 'completion' },
          completion: { isComplete: true },
          recommendation: 'next_task',
        },
        response: {
          message: 'Saved response',
          confidence: 0.9,
        },
        accepted: true,
        confidence: 0.9,
      });

      // Create new manager instance to test loading
      const newManager = new TrainingDataManager({
        dataDir: TEST_DATA_DIR,
      });

      // Wait for initialization
      await newManager.initialized;

      const loaded = newManager.trainingData.get('persist-test');
      assert.ok(loaded);
      assert.strictEqual(loaded.length, 1);
      assert.strictEqual(loaded[0].response, 'Saved response');
    });
  });
});
