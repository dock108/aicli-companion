/**
 * Planning Validator Service
 * Analyzes planning conversations to assess requirement completeness
 */

import { createLogger } from '../utils/logger.js';
import { RequirementsAnalyzer } from './requirements-analyzer.js';
import { ReadinessScorer } from './readiness-scorer.js';
import { GapDetector } from './gap-detector.js';

const logger = createLogger('PlanningValidator');

export class PlanningValidator {
  constructor() {
    this.domains = ['database', 'api', 'ui_ux', 'auth', 'performance', 'deployment', 'testing'];

    this.requirements = new Map();
    this.analyzer = new RequirementsAnalyzer();
    this.scorer = new ReadinessScorer();
    this.gapDetector = new GapDetector();

    // Track validation session state
    this.sessionId = null;
    this.projectType = null;
    this.conversationHistory = [];
  }

  /**
   * Initialize a new validation session
   * @param {string} sessionId - Session identifier
   * @param {string} projectType - Type of project being planned
   */
  initializeSession(sessionId, projectType = 'web-app') {
    this.sessionId = sessionId;
    this.projectType = projectType;
    this.conversationHistory = [];
    this.requirements.clear();

    logger.info('Initialized planning validation session', { sessionId, projectType });
  }

  /**
   * Analyze a single message for requirements
   * @param {object} message - Chat message to analyze
   * @returns {object} - Extracted requirements
   */
  async analyzeMessage(message) {
    if (!message || !message.content) {
      return { requirements: [] };
    }

    try {
      // Add to conversation history
      this.conversationHistory.push(message);

      // Use the analyzer's analyzeConversation method with full history
      const conversationText = this.conversationHistory
        .map((m) => m.content || m.text || '')
        .join('\n');

      const analysis = this.analyzer.analyzeConversation(conversationText);

      // Convert analysis to requirements format
      const requirements = [];
      for (const [domain, domainAnalysis] of Object.entries(analysis.domains)) {
        if (domainAnalysis.foundRequirements && domainAnalysis.foundRequirements.length > 0) {
          for (const req of domainAnalysis.foundRequirements) {
            requirements.push({
              domain,
              type: 'explicit',
              value: req,
              confidence: domainAnalysis.confidence,
            });
          }
        }
      }

      // Update requirements map
      for (const req of requirements) {
        const domain = req.domain || 'general';
        if (!this.requirements.has(domain)) {
          this.requirements.set(domain, []);
        }
        // Only add if not already present
        const existing = this.requirements.get(domain);
        if (!existing.some((e) => e.value === req.value)) {
          existing.push(req);
        }
      }

      logger.debug('Analyzed message', {
        messageId: message.id,
        requirementsFound: requirements.length,
      });

      return { requirements, confidence: analysis.overallScore / 100 };
    } catch (error) {
      logger.error('Failed to analyze message', { error: error.message });
      return { requirements: [] };
    }
  }

  /**
   * Validate entire conversation for requirement completeness
   * @param {array} messages - Array of conversation messages
   * @returns {object} - Validation result with score and gaps
   */
  async validateConversation(messages = []) {
    try {
      // Clear and rebuild requirements from all messages
      this.requirements.clear();
      this.conversationHistory = [];

      // Analyze all messages
      for (const message of messages) {
        await this.analyzeMessage(message);
      }

      // Calculate completeness per domain
      const domainScores = {};
      for (const domain of this.domains) {
        const domainReqs = this.requirements.get(domain) || [];
        domainScores[domain] = this.scorer.calculateDomainScore(
          domain,
          domainReqs,
          this.projectType
        );
      }

      // Calculate overall readiness score
      const readinessScore = this.scorer.calculateScore(this.requirements, this.projectType);

      // Detect gaps and missing requirements
      const gaps = this.gapDetector.detectGaps(this.requirements, this.projectType);

      // Generate checklist of missing items
      const checklist = this.generateChecklist(gaps);

      // Determine readiness level
      const readinessLevel = this.scorer.getReadinessLevel(readinessScore);

      const result = {
        sessionId: this.sessionId,
        projectType: this.projectType,
        readinessScore,
        readinessLevel,
        domainScores,
        gaps,
        checklist,
        totalRequirements: this.getTotalRequirements(),
        message: this.getReadinessMessage(readinessLevel, gaps),
      };

      logger.info('Validation complete', {
        sessionId: this.sessionId,
        readinessScore,
        readinessLevel,
      });

      return result;
    } catch (error) {
      logger.error('Failed to validate conversation', { error: error.message });
      throw error;
    }
  }

  /**
   * Generate checklist from gaps
   * @param {object} gaps - Detected gaps by domain
   * @returns {array} - Checklist items
   */
  generateChecklist(gaps) {
    const checklist = [];

    for (const [domain, domainGaps] of Object.entries(gaps)) {
      for (const gap of domainGaps) {
        checklist.push({
          domain,
          item: gap.item,
          priority: gap.priority,
          description: gap.description,
          completed: false,
        });
      }
    }

    // Sort by priority
    checklist.sort((a, b) => {
      const priorityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
      return priorityOrder[a.priority] - priorityOrder[b.priority];
    });

    return checklist;
  }

  /**
   * Get total number of requirements collected
   * @returns {number} - Total requirements count
   */
  getTotalRequirements() {
    let total = 0;
    for (const reqs of this.requirements.values()) {
      total += reqs.length;
    }
    return total;
  }

  /**
   * Generate readiness message based on level and gaps
   * @param {string} level - Readiness level
   * @param {object} gaps - Detected gaps
   * @returns {string} - Human-readable message
   */
  getReadinessMessage(level, gaps) {
    const gapCount = Object.values(gaps).flat().length;

    switch (level) {
      case 'ready':
        return '✅ All critical requirements identified! Ready to start development.';

      case 'partial':
        return `⚠️ Missing ${gapCount} requirements: ${this.summarizeGaps(gaps)}`;

      case 'incomplete':
        return `🚨 Database schema needs: ${this.getDomainGapSummary(gaps.database)}`;

      case 'insufficient':
        return `📋 Generated ${gapCount}-item checklist for remaining specifications`;

      default:
        return "🎮 You're flying without instruments here! Missing critical requirements, but let's go if you're feeling adventurous...";
    }
  }

  /**
   * Summarize gaps for message
   * @param {object} gaps - Gaps by domain
   * @returns {string} - Summary text
   */
  summarizeGaps(gaps) {
    const summaries = [];

    for (const [domain, domainGaps] of Object.entries(gaps)) {
      if (domainGaps.length > 0) {
        const critical = domainGaps.filter((g) => g.priority === 'critical');
        if (critical.length > 0) {
          summaries.push(`${domain}: ${critical[0].item}`);
        }
      }
    }

    return summaries.slice(0, 3).join(', ');
  }

  /**
   * Get summary of gaps for a specific domain
   * @param {array} domainGaps - Gaps for a domain
   * @returns {string} - Summary
   */
  getDomainGapSummary(domainGaps = []) {
    if (domainGaps.length === 0) return 'complete';

    const items = domainGaps
      .slice(0, 3)
      .map((g) => g.item)
      .join(', ');

    return items;
  }

  /**
   * Check if validation passes minimum requirements
   * @returns {boolean} - Whether minimum requirements are met
   */
  meetsMinimumRequirements() {
    const score = this.scorer.calculateScore(this.requirements, this.projectType);
    return score >= 60; // 60% minimum threshold
  }

  /**
   * Get suggestions for improving completeness
   * @returns {array} - Suggestion strings
   */
  getSuggestions() {
    const suggestions = [];

    // Check each domain for missing critical items
    for (const domain of this.domains) {
      const domainReqs = this.requirements.get(domain) || [];

      if (domainReqs.length === 0) {
        switch (domain) {
          case 'database':
            suggestions.push('Define your database schema and relationships');
            break;
          case 'api':
            suggestions.push('Specify API endpoints and request/response formats');
            break;
          case 'ui_ux':
            suggestions.push('Describe user interface screens and flows');
            break;
          case 'auth':
            suggestions.push('Define authentication and authorization strategy');
            break;
        }
      }
    }

    return suggestions;
  }

  /**
   * Export validation report
   * @returns {object} - Full validation report
   */
  async exportReport() {
    const validation = await this.validateConversation(this.conversationHistory);

    return {
      ...validation,
      suggestions: this.getSuggestions(),
      timestamp: new Date().toISOString(),
      conversationLength: this.conversationHistory.length,
      meetsMinimum: this.meetsMinimumRequirements(),
    };
  }

  /**
   * Clear validation session
   */
  clearSession() {
    this.sessionId = null;
    this.projectType = null;
    this.conversationHistory = [];
    this.requirements.clear();

    logger.info('Cleared validation session');
  }
}

// Export singleton instance
export const planningValidator = new PlanningValidator();
