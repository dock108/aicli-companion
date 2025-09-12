/**
 * Message Analyzer Service
 * Analyzes Claude's output to extract intent, detect completion, and track progress
 */

import { createLogger } from '../utils/logger.js';

const _logger = createLogger('MessageAnalyzer');

export class MessageAnalyzer {
  constructor() {
    // Intent patterns with confidence scores
    this.intentPatterns = {
      completion: {
        patterns: [
          { regex: /task[s]?\s+(is\s+)?complet(ed?|e)/i, score: 0.9 },
          { regex: /finished\s+(implementing|working|creating)/i, score: 0.85 },
          { regex: /all\s+(tests?\s+)?pass(ing|ed)?/i, score: 0.8 },
          { regex: /successfully\s+(implemented|created|fixed)/i, score: 0.85 },
          { regex: /done\s+with\s+(the\s+)?/i, score: 0.7 },
          { regex: /implementation\s+is\s+complete/i, score: 0.9 },
        ],
        type: 'completion',
      },

      needsClarification: {
        patterns: [
          { regex: /need[s]?\s+(more\s+)?clarification/i, score: 0.9 },
          { regex: /not\s+sure\s+(what|how|which)/i, score: 0.8 },
          { regex: /could\s+you\s+(please\s+)?(clarify|explain|specify)/i, score: 0.85 },
          { regex: /what\s+(do\s+you\s+mean|should\s+i)/i, score: 0.75 },
          { regex: /ambiguous|unclear|confusing/i, score: 0.7 },
          { regex: /which\s+(approach|option|method)\s+would\s+you\s+prefer/i, score: 0.8 },
        ],
        type: 'clarification',
      },

      error: {
        patterns: [
          { regex: /test[s]?\s+(are\s+)?failing/i, score: 0.85 },
          { regex: /(fatal|critical)\s+error/i, score: 0.95 },
          { regex: /cannot\s+(find|locate|access|continue)/i, score: 0.8 },
          { regex: /permission\s+denied/i, score: 0.9 },
          { regex: /build\s+failed/i, score: 0.85 },
          { regex: /compilation\s+error/i, score: 0.85 },
          { regex: /undefined\s+(is\s+not|reference)/i, score: 0.75 },
          { regex: /module\s+not\s+found/i, score: 0.8 },
        ],
        type: 'error',
      },

      progress: {
        patterns: [
          { regex: /working\s+on/i, score: 0.7 },
          { regex: /implementing|creating|adding|updating/i, score: 0.65 },
          { regex: /let\s+me\s+(now\s+)?/i, score: 0.6 },
          { regex: /next[,\s]+i('ll|'m\s+going\s+to)/i, score: 0.7 },
          { regex: /continuing\s+with/i, score: 0.75 },
          { regex: /moving\s+(on\s+)?to/i, score: 0.7 },
        ],
        type: 'progress',
      },

      waiting: {
        patterns: [
          { regex: /waiting\s+for/i, score: 0.85 },
          { regex: /please\s+(provide|specify|tell)/i, score: 0.8 },
          { regex: /what\s+would\s+you\s+like/i, score: 0.75 },
          { regex: /should\s+i\s+(proceed|continue)/i, score: 0.8 },
          { regex: /ready\s+to\s+(proceed|continue)/i, score: 0.7 },
        ],
        type: 'waiting',
      },
    };

    // Showstopper patterns that require immediate escalation
    this.showstopperPatterns = [
      { regex: /fatal\s+error/i, reason: 'Fatal error detected' },
      { regex: /permission\s+denied/i, reason: 'Permission issue' },
      { regex: /cannot\s+continue/i, reason: 'Process blocked' },
      { regex: /need\s+human\s+intervention/i, reason: 'Explicit escalation request' },
      { regex: /security\s+violation/i, reason: 'Security issue' },
      { regex: /credentials?\s+(required|missing|invalid)/i, reason: 'Authentication issue' },
      { regex: /quota\s+exceeded/i, reason: 'Resource limit reached' },
      { regex: /rate\s+limit/i, reason: 'API rate limit' },
      { regex: /out\s+of\s+memory/i, reason: 'Memory exhaustion' },
    ];

    // Completion indicators
    this.completionIndicators = {
      strong: [
        /all\s+tests?\s+pass/i,
        /build\s+successful/i,
        /deployment\s+complete/i,
        /task\s+complete/i,
        /implementation\s+complete/i,
      ],
      moderate: [/finished/i, /done/i, /completed/i, /ready\s+for\s+review/i],
      weak: [/looks\s+good/i, /should\s+work/i, /that's\s+it/i],
    };
  }

  /**
   * Extract intent from a message
   * @param {string} message - Claude's message to analyze
   * @returns {Object} Intent analysis with type and confidence
   */
  extractIntent(message) {
    if (!message || typeof message !== 'string') {
      return { type: 'unknown', confidence: 0, details: [] };
    }

    const results = [];

    // Check each intent category
    for (const [category, config] of Object.entries(this.intentPatterns)) {
      for (const pattern of config.patterns) {
        if (pattern.regex.test(message)) {
          results.push({
            type: config.type,
            confidence: pattern.score,
            match: message.match(pattern.regex)[0],
            category,
          });
        }
      }
    }

    // Sort by confidence and return highest
    results.sort((a, b) => b.confidence - a.confidence);

    if (results.length === 0) {
      return { type: 'unknown', confidence: 0, details: [] };
    }

    // Check if multiple intents detected
    const topIntent = results[0];
    const similarIntents = results.filter((r) => r.confidence >= topIntent.confidence - 0.1);

    return {
      type: topIntent.type,
      confidence: topIntent.confidence,
      match: topIntent.match,
      category: topIntent.category,
      alternativeIntents: similarIntents.slice(1),
      details: results,
    };
  }

  /**
   * Detect if message indicates task completion
   * @param {string} message - Message to analyze
   * @returns {Object} Completion detection result
   */
  detectCompletion(message) {
    if (!message) {
      return { isComplete: false, confidence: 0, indicators: [] };
    }

    const indicators = [];
    let maxConfidence = 0;

    // Check strong indicators
    for (const pattern of this.completionIndicators.strong) {
      if (pattern.test(message)) {
        indicators.push({ level: 'strong', match: message.match(pattern)[0] });
        maxConfidence = Math.max(maxConfidence, 0.9);
      }
    }

    // Check moderate indicators
    for (const pattern of this.completionIndicators.moderate) {
      if (pattern.test(message)) {
        indicators.push({ level: 'moderate', match: message.match(pattern)[0] });
        maxConfidence = Math.max(maxConfidence, 0.7);
      }
    }

    // Check weak indicators
    for (const pattern of this.completionIndicators.weak) {
      if (pattern.test(message)) {
        indicators.push({ level: 'weak', match: message.match(pattern)[0] });
        maxConfidence = Math.max(maxConfidence, 0.5);
      }
    }

    // Also check for failure completion
    const failurePatterns = [
      /cannot\s+be\s+completed/i,
      /unable\s+to\s+complete/i,
      /failed\s+to\s+complete/i,
    ];

    for (const pattern of failurePatterns) {
      if (pattern.test(message)) {
        return {
          isComplete: true,
          success: false,
          confidence: 0.85,
          indicators: [{ level: 'failure', match: message.match(pattern)[0] }],
        };
      }
    }

    return {
      isComplete: indicators.length > 0,
      success: true,
      confidence: maxConfidence,
      indicators,
    };
  }

  /**
   * Detect showstoppers that require human intervention
   * @param {string} message - Message to analyze
   * @returns {Object} Showstopper detection result
   */
  detectShowstopper(message) {
    if (!message) {
      return { isShowstopper: false, reasons: [] };
    }

    const detectedReasons = [];

    for (const pattern of this.showstopperPatterns) {
      if (pattern.regex.test(message)) {
        detectedReasons.push({
          reason: pattern.reason,
          match: message.match(pattern.regex)[0],
          severity: 'critical',
        });
      }
    }

    // Check for repeated failures (requires context)
    const failureCount = (message.match(/fail(ed|ing|ure)?/gi) || []).length;
    if (failureCount >= 3) {
      detectedReasons.push({
        reason: 'Multiple failures detected',
        match: `${failureCount} failure mentions`,
        severity: 'high',
      });
    }

    return {
      isShowstopper: detectedReasons.length > 0,
      reasons: detectedReasons,
      requiresEscalation: detectedReasons.some((r) => r.severity === 'critical'),
    };
  }

  /**
   * Assess progress from a series of messages
   * @param {Array} messages - Array of recent messages
   * @returns {Object} Progress assessment
   */
  assessProgress(messages) {
    if (!messages || messages.length === 0) {
      return { isProgressing: false, stuckIndicators: [], progressRate: 0 };
    }

    // Look for stuck patterns
    const stuckIndicators = [];

    // Check for repeated similar messages
    const lastThree = messages.slice(-3);
    if (lastThree.length === 3) {
      const similarities = this.calculateSimilarity(lastThree);
      if (similarities > 0.8) {
        stuckIndicators.push({
          type: 'repeated_output',
          confidence: similarities,
        });
      }
    }

    // Check for error loops
    const recentErrors = messages.slice(-5).filter((m) => /error|fail|cannot|unable/i.test(m));
    if (recentErrors.length >= 3) {
      stuckIndicators.push({
        type: 'error_loop',
        errorCount: recentErrors.length,
      });
    }

    // Check for lack of progress keywords
    const progressKeywords = /complet|finish|implement|creat|add|fix|updat|build/i;
    const recentProgress = messages.slice(-5).filter((m) => progressKeywords.test(m));
    const progressRate = recentProgress.length / Math.min(5, messages.length);

    return {
      isProgressing: stuckIndicators.length === 0 && progressRate > 0.3,
      stuckIndicators,
      progressRate,
      recommendation: this.getProgressRecommendation(stuckIndicators, progressRate),
    };
  }

  /**
   * Calculate similarity between messages
   * @private
   */
  calculateSimilarity(messages) {
    if (messages.length < 2) return 0;

    // Simple similarity based on common words
    const tokenize = (str) => str.toLowerCase().split(/\s+/);
    const tokens = messages.map((m) => new Set(tokenize(m)));

    let totalSimilarity = 0;
    let comparisons = 0;

    for (let i = 0; i < tokens.length - 1; i++) {
      for (let j = i + 1; j < tokens.length; j++) {
        const intersection = new Set([...tokens[i]].filter((x) => tokens[j].has(x)));
        const union = new Set([...tokens[i], ...tokens[j]]);
        totalSimilarity += intersection.size / union.size;
        comparisons++;
      }
    }

    return comparisons > 0 ? totalSimilarity / comparisons : 0;
  }

  /**
   * Get recommendation based on progress assessment
   * @private
   */
  getProgressRecommendation(stuckIndicators, progressRate) {
    if (stuckIndicators.length === 0 && progressRate > 0.6) {
      return 'continue_current_approach';
    }

    if (stuckIndicators.some((i) => i.type === 'error_loop')) {
      return 'try_different_approach';
    }

    if (stuckIndicators.some((i) => i.type === 'repeated_output')) {
      return 'provide_clarification';
    }

    if (progressRate < 0.2) {
      return 'check_requirements';
    }

    return 'monitor_progress';
  }

  /**
   * Analyze a message comprehensively
   * @param {string} message - Message to analyze
   * @param {Array} context - Recent message history for context
   * @returns {Object} Complete analysis
   */
  analyzeMessage(message, context = []) {
    const intent = this.extractIntent(message);
    const completion = this.detectCompletion(message);
    const showstopper = this.detectShowstopper(message);
    const progress =
      context.length > 0
        ? this.assessProgress([...context, message])
        : { isProgressing: true, stuckIndicators: [], progressRate: 0.5 };

    // Determine overall recommendation
    let recommendation = 'continue';
    let priority = 'normal';

    if (showstopper.isShowstopper) {
      recommendation = 'escalate';
      priority = 'critical';
    } else if (completion.isComplete) {
      recommendation = completion.success ? 'next_task' : 'troubleshoot';
      priority = 'high';
    } else if (intent.type === 'clarification') {
      recommendation = 'provide_clarification';
      priority = 'high';
    } else if (intent.type === 'error') {
      recommendation = 'troubleshoot';
      priority = 'high';
    } else if (!progress.isProgressing) {
      recommendation = progress.recommendation;
      priority = 'medium';
    }

    return {
      intent,
      completion,
      showstopper,
      progress,
      recommendation,
      priority,
      timestamp: new Date().toISOString(),
    };
  }
}

export default MessageAnalyzer;
