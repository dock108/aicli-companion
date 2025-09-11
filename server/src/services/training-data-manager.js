/**
 * Training Data Manager Service
 * Manages training data for AI response generation
 */

import { createLogger } from '../utils/logger.js';
import fs from 'fs/promises';
import path from 'path';

const logger = createLogger('TrainingDataManager');

export class TrainingDataManager {
  constructor(options = {}) {
    this.dataDir = options.dataDir || process.env.TRAINING_DATA_DIR || './training-data';
    this.maxExamples = options.maxExamples || 1000;
    this.minConfidence = options.minConfidence || 0.7;

    // In-memory cache
    this.trainingData = new Map(); // projectId -> examples[]
    this.statistics = new Map(); // projectId -> stats

    // Initialize data directory (don't await in constructor)
    this.initialized = this.initializeDataDirectory();
  }

  /**
   * Initialize the training data directory
   * @private
   */
  async initializeDataDirectory() {
    try {
      await fs.mkdir(this.dataDir, { recursive: true });
      await this.loadAllData();
    } catch (error) {
      logger.error('Failed to initialize training data directory', { error: error.message });
    }
  }

  /**
   * Record a successful interaction for training
   * @param {Object} interaction - The interaction to record
   */
  async recordInteraction(interaction) {
    const {
      projectId,
      sessionId,
      claudeOutput,
      analysis,
      response,
      accepted,
      confidence,
      context = {},
    } = interaction;

    // Only record high-confidence accepted responses
    if (!accepted || confidence < this.minConfidence) {
      return;
    }

    const example = {
      id: this.generateId(),
      timestamp: new Date().toISOString(),
      projectId,
      sessionId,
      situation: this.extractSituation(claudeOutput, analysis),
      response: response.message,
      confidence,
      intent: analysis.intent.type,
      completion: analysis.completion.isComplete,
      recommendation: analysis.recommendation,
      context: {
        projectName: context.projectName,
        taskType: context.currentTask,
        iterationCount: context.iterationCount,
      },
      metadata: {
        model: response.model || 'template',
        source: response.source || 'manual',
      },
    };

    await this.addExample(projectId, example);

    logger.info('Recorded training interaction', {
      projectId,
      intent: example.intent,
      confidence: example.confidence,
    });
  }

  /**
   * Add a training example
   * @private
   */
  async addExample(projectId, example) {
    if (!this.trainingData.has(projectId)) {
      this.trainingData.set(projectId, []);
    }

    const examples = this.trainingData.get(projectId);
    examples.push(example);

    // Limit the number of examples
    if (examples.length > this.maxExamples) {
      examples.shift(); // Remove oldest
    }

    // Update statistics
    this.updateStatistics(projectId);

    // Persist to disk
    await this.saveProjectData(projectId);
  }

  /**
   * Get relevant training examples for a context
   * @param {string} projectId - Project identifier
   * @param {Object} analysis - Current analysis
   * @param {number} limit - Maximum examples to return
   * @returns {Array} Relevant training examples
   */
  getRelevantExamples(projectId, analysis, limit = 5) {
    const examples = this.trainingData.get(projectId) || [];

    if (examples.length === 0) {
      return [];
    }

    // Score and sort examples by relevance
    const scoredExamples = examples.map((example) => ({
      example,
      score: this.calculateRelevance(example, analysis),
    }));

    scoredExamples.sort((a, b) => b.score - a.score);

    // Return top examples
    return scoredExamples
      .slice(0, limit)
      .filter((item) => item.score > 0.5)
      .map((item) => item.example);
  }

  /**
   * Calculate relevance score
   * @private
   */
  calculateRelevance(example, analysis) {
    let score = 0;

    // Intent match
    if (example.intent === analysis.intent.type) {
      score += 0.4;
    }

    // Completion status match
    if (example.completion === analysis.completion.isComplete) {
      score += 0.2;
    }

    // Recommendation match
    if (example.recommendation === analysis.recommendation) {
      score += 0.3;
    }

    // Recency bonus (examples from last 24 hours)
    const age = Date.now() - new Date(example.timestamp).getTime();
    if (age < 86400000) {
      // 24 hours
      score += 0.1;
    }

    return score;
  }

  /**
   * Extract situation description from output and analysis
   * @private
   */
  extractSituation(claudeOutput, analysis) {
    const lines = claudeOutput.split('\n').filter((line) => line.trim());
    const firstLine = lines[0] || '';
    // const lastLine = lines[lines.length - 1] || ''; // Removed unused variable

    let situation = `Intent: ${analysis.intent?.type || 'unknown'}. `;

    if (analysis.completion?.isComplete) {
      situation += `Task completed ${analysis.completion.success ? 'successfully' : 'with errors'}. `;
    } else if (analysis.progress?.isProgressing) {
      situation += 'Task in progress. ';
    } else {
      situation += 'Task stuck or blocked. ';
    }

    if (analysis.showstopper?.isShowstopper) {
      situation += `Critical issue: ${analysis.showstopper.reasons?.[0]?.reason}. `;
    }

    // Add context from output
    if (firstLine.length > 0) {
      situation += `Output: "${this.truncate(firstLine, 100)}"`;
    }

    return situation;
  }

  /**
   * Update statistics for a project
   * @private
   */
  updateStatistics(projectId) {
    const examples = this.trainingData.get(projectId) || [];

    const stats = {
      totalExamples: examples.length,
      intentDistribution: {},
      averageConfidence: 0,
      acceptanceRate: 0,
      lastUpdated: new Date().toISOString(),
    };

    // Calculate intent distribution
    examples.forEach((example) => {
      stats.intentDistribution[example.intent] =
        (stats.intentDistribution[example.intent] || 0) + 1;
    });

    // Calculate average confidence
    if (examples.length > 0) {
      const totalConfidence = examples.reduce((sum, ex) => sum + ex.confidence, 0);
      stats.averageConfidence = totalConfidence / examples.length;
    }

    this.statistics.set(projectId, stats);
  }

  /**
   * Get training statistics
   * @param {string} projectId - Project identifier
   * @returns {Object} Training statistics
   */
  getStatistics(projectId) {
    if (projectId) {
      return this.statistics.get(projectId) || this.getDefaultStats();
    }

    // Return overall statistics
    const overall = {
      totalProjects: this.statistics.size,
      totalExamples: 0,
      projects: {},
    };

    for (const [pid, stats] of this.statistics) {
      overall.totalExamples += stats.totalExamples;
      overall.projects[pid] = stats;
    }

    return overall;
  }

  /**
   * Get default statistics
   * @private
   */
  getDefaultStats() {
    return {
      totalExamples: 0,
      intentDistribution: {},
      averageConfidence: 0,
      acceptanceRate: 0,
      lastUpdated: null,
    };
  }

  /**
   * Import training data from JSON
   * @param {string} projectId - Project identifier
   * @param {Array} examples - Training examples to import
   */
  async importTrainingData(projectId, examples) {
    if (!Array.isArray(examples)) {
      throw new Error('Examples must be an array');
    }

    const validExamples = examples.filter((ex) => ex.situation && ex.response && ex.intent);

    for (const example of validExamples) {
      await this.addExample(projectId, {
        ...example,
        id: example.id || this.generateId(),
        timestamp: example.timestamp || new Date().toISOString(),
        projectId,
      });
    }

    logger.info('Imported training data', {
      projectId,
      imported: validExamples.length,
      total: examples.length,
    });

    return {
      imported: validExamples.length,
      skipped: examples.length - validExamples.length,
    };
  }

  /**
   * Export training data as JSON
   * @param {string} projectId - Project identifier
   * @returns {Array} Training examples
   */
  async exportTrainingData(projectId) {
    const examples = this.trainingData.get(projectId) || [];
    return examples;
  }

  /**
   * Clear training data for a project
   * @param {string} projectId - Project identifier
   */
  async clearTrainingData(projectId) {
    this.trainingData.delete(projectId);
    this.statistics.delete(projectId);

    try {
      const filePath = path.join(this.dataDir, `${projectId}.json`);
      await fs.unlink(filePath);
      logger.info('Cleared training data', { projectId });
    } catch (error) {
      // File might not exist
      logger.debug('No training data file to delete', { projectId });
    }
  }

  /**
   * Save project data to disk
   * @private
   */
  async saveProjectData(projectId) {
    try {
      const examples = this.trainingData.get(projectId) || [];
      const stats = this.statistics.get(projectId) || this.getDefaultStats();

      const data = {
        projectId,
        examples,
        statistics: stats,
        version: '1.0',
      };

      const filePath = path.join(this.dataDir, `${projectId}.json`);
      await fs.writeFile(filePath, JSON.stringify(data, null, 2));
    } catch (error) {
      logger.error('Failed to save training data', {
        projectId,
        error: error.message,
      });
    }
  }

  /**
   * Load all training data from disk
   * @private
   */
  async loadAllData() {
    try {
      const files = await fs.readdir(this.dataDir);
      const jsonFiles = files.filter((f) => f.endsWith('.json'));

      for (const file of jsonFiles) {
        const projectId = path.basename(file, '.json');
        await this.loadProjectData(projectId);
      }

      logger.info('Loaded training data', {
        projects: this.trainingData.size,
        totalExamples: Array.from(this.trainingData.values()).reduce(
          (sum, examples) => sum + examples.length,
          0
        ),
      });
    } catch (error) {
      logger.error('Failed to load training data', { error: error.message });
    }
  }

  /**
   * Load project data from disk
   * @private
   */
  async loadProjectData(projectId) {
    try {
      const filePath = path.join(this.dataDir, `${projectId}.json`);
      const content = await fs.readFile(filePath, 'utf-8');
      const data = JSON.parse(content);

      if (data.examples) {
        this.trainingData.set(projectId, data.examples);
      }

      if (data.statistics) {
        this.statistics.set(projectId, data.statistics);
      } else {
        this.updateStatistics(projectId);
      }
    } catch (error) {
      // File might not exist yet
      logger.debug('No existing training data for project', { projectId });
    }
  }

  /**
   * Generate unique ID
   * @private
   */
  generateId() {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Truncate text
   * @private
   */
  truncate(text, maxLength) {
    if (text.length <= maxLength) {
      return text;
    }
    return `${text.substring(0, maxLength)}...`;
  }

  /**
   * Analyze training data quality
   * @param {string} projectId - Project identifier
   * @returns {Object} Quality analysis
   */
  analyzeDataQuality(projectId) {
    const examples = this.trainingData.get(projectId) || [];

    if (examples.length === 0) {
      return {
        quality: 'insufficient',
        examples: 0,
        recommendations: ['Need more training examples'],
      };
    }

    const stats = this.statistics.get(projectId) || this.getDefaultStats();
    const recommendations = [];

    // Check example count
    if (examples.length < 10) {
      recommendations.push('Need at least 10 examples for effective training');
    }

    // Check intent coverage
    const intentTypes = Object.keys(stats.intentDistribution);
    if (intentTypes.length < 3) {
      recommendations.push('Limited intent coverage - need more diverse examples');
    }

    // Check confidence levels
    if (stats.averageConfidence < 0.7) {
      recommendations.push('Low average confidence - review example quality');
    }

    // Check recency
    const recentExamples = examples.filter((ex) => {
      const age = Date.now() - new Date(ex.timestamp).getTime();
      return age < 604800000; // 7 days
    });

    if (recentExamples.length < examples.length * 0.3) {
      recommendations.push('Most examples are old - consider refreshing training data');
    }

    return {
      quality:
        recommendations.length === 0 ? 'good' : recommendations.length <= 2 ? 'moderate' : 'poor',
      examples: examples.length,
      intentCoverage: intentTypes.length,
      averageConfidence: stats.averageConfidence,
      recentExamples: recentExamples.length,
      recommendations,
    };
  }
}

export default TrainingDataManager;
