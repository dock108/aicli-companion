/**
 * Response Templates Service
 * Provides categorized response templates for auto-response system
 */

import { createLogger } from '../utils/logger.js';

const logger = createLogger('ResponseTemplates');

export class ResponseTemplates {
  constructor() {
    // Response templates organized by category and intent
    this.templates = {
      continuation: {
        default: {
          template: 'Continue working on the current task',
          confidence: 0.5,
          context: ['progress'],
        },
        testing: {
          template: 'Run the tests and fix any failures',
          confidence: 0.8,
          context: ['error', 'testing'],
        },
        implementation: {
          template: 'Continue implementing the feature',
          confidence: 0.7,
          context: ['progress', 'implementation'],
        },
        debugging: {
          template: 'Continue debugging and add more logging if needed',
          confidence: 0.7,
          context: ['error', 'debugging'],
        },
        completion: {
          template: 'Complete the remaining implementation',
          confidence: 0.6,
          context: ['progress', 'partial'],
        },
      },

      clarification: {
        rules: {
          template: 'Check the CLAUDE.md file for project-specific guidelines on this',
          confidence: 0.9,
          context: ['clarification', 'rules'],
        },
        requirements: {
          template: 'Review the issue description for detailed requirements',
          confidence: 0.85,
          context: ['clarification', 'requirements'],
        },
        approach: {
          template: 'Use the approach that best follows the existing codebase patterns',
          confidence: 0.7,
          context: ['clarification', 'approach'],
        },
        specification: {
          template: 'Please follow the specification as outlined in the requirements',
          confidence: 0.75,
          context: ['clarification', 'specification'],
        },
      },

      progression: {
        nextTask: {
          template: 'Great! Move to the next task in the sprint',
          confidence: 0.9,
          context: ['completion', 'success'],
        },
        nextPhase: {
          template: "Let's move to the testing phase",
          confidence: 0.85,
          context: ['completion', 'implementation'],
        },
        review: {
          template: 'Excellent! Now review the changes and ensure everything is working',
          confidence: 0.8,
          context: ['completion', 'review'],
        },
        documentation: {
          template: 'Good work! Update the documentation if needed and move to the next task',
          confidence: 0.75,
          context: ['completion', 'documentation'],
        },
      },

      troubleshooting: {
        retry: {
          template: 'Try again with a different approach',
          confidence: 0.7,
          context: ['error', 'stuck'],
        },
        reread: {
          template: 'Re-read the error message carefully and address the specific issue',
          confidence: 0.75,
          context: ['error', 'confusion'],
        },
        debug: {
          template: 'Add debug logging to understand what is happening',
          confidence: 0.8,
          context: ['error', 'unknown'],
        },
        dependencies: {
          template: 'Check if all dependencies are installed and up to date',
          confidence: 0.75,
          context: ['error', 'module'],
        },
        permissions: {
          template: 'Check file permissions and ensure you have access to required resources',
          confidence: 0.85,
          context: ['error', 'permission'],
        },
      },

      error_recovery: {
        testFailure: {
          template: 'Review the test output and fix the failing tests',
          confidence: 0.9,
          context: ['error', 'test'],
        },
        buildFailure: {
          template: 'Check the build output for specific errors and fix them',
          confidence: 0.85,
          context: ['error', 'build'],
        },
        syntaxError: {
          template: 'Fix the syntax error shown in the output',
          confidence: 0.95,
          context: ['error', 'syntax'],
        },
        typeError: {
          template: 'Fix the type errors and ensure types are consistent',
          confidence: 0.9,
          context: ['error', 'type'],
        },
      },

      validation: {
        tests: {
          template: 'Run npm test to ensure all tests pass',
          confidence: 0.85,
          context: ['validation', 'testing'],
        },
        lint: {
          template: 'Run npm run lint and fix any issues',
          confidence: 0.8,
          context: ['validation', 'lint'],
        },
        coverage: {
          template: 'Check test coverage with npm run test:coverage',
          confidence: 0.75,
          context: ['validation', 'coverage'],
        },
      },

      escalation: {
        showstopper: {
          template:
            '[ESCALATION REQUIRED] Critical issue detected that requires human intervention',
          confidence: 1.0,
          context: ['showstopper'],
          isEscalation: true,
        },
        ambiguous: {
          template:
            '[CLARIFICATION NEEDED] The requirements are ambiguous and need human clarification',
          confidence: 0.9,
          context: ['ambiguous'],
          isEscalation: true,
        },
        blocked: {
          template: '[BLOCKED] Cannot proceed without additional information or access',
          confidence: 0.95,
          context: ['blocked'],
          isEscalation: true,
        },
      },
    };

    // Context matching rules
    this.contextRules = {
      error: ['error', 'fail', 'cannot', 'unable', 'exception'],
      progress: ['working', 'implementing', 'creating', 'updating'],
      completion: ['complete', 'done', 'finished', 'ready'],
      clarification: ['unclear', 'which', 'what', 'should'],
      testing: ['test', 'spec', 'coverage', 'jest', 'mocha'],
      implementation: ['implement', 'create', 'build', 'develop'],
    };
  }

  /**
   * Select appropriate response template based on analysis
   * @param {Object} analysis - Message analysis from MessageAnalyzer
   * @param {Object} context - Additional context
   * @returns {Object} Selected template with confidence
   */
  selectTemplate(analysis, context = {}) {
    const { showstopper, recommendation } = analysis;

    // Handle escalations first
    if (showstopper.isShowstopper) {
      return this.getEscalationTemplate(showstopper);
    }

    // Map recommendation to template category
    const categoryMap = {
      continue: 'continuation',
      next_task: 'progression',
      troubleshoot: 'troubleshooting',
      provide_clarification: 'clarification',
      try_different_approach: 'troubleshooting',
      escalate: 'escalation',
    };

    const category = categoryMap[recommendation] || 'continuation';
    const templates = this.templates[category];

    if (!templates) {
      logger.warn('No templates found for category', { category });
      return this.getDefaultTemplate();
    }

    // Score each template in the category
    const scoredTemplates = Object.entries(templates).map(([key, template]) => {
      const score = this.scoreTemplate(template, analysis, context);
      return { key, template, score };
    });

    // Sort by score and return best match
    scoredTemplates.sort((a, b) => b.score - a.score);
    const best = scoredTemplates[0];

    return {
      template: best.template.template,
      confidence: best.score,
      category,
      key: best.key,
      isEscalation: best.template.isEscalation || false,
    };
  }

  /**
   * Score a template based on context matching
   * @private
   */
  scoreTemplate(template, analysis, _context) {
    let score = template.confidence;

    // Check context matches
    const messageContext = this.extractContext(analysis);
    const matchingContexts = template.context.filter((ctx) => messageContext.includes(ctx));

    // Boost score for context matches
    score += matchingContexts.length * 0.1;

    // Boost for intent match
    if (template.context.includes(analysis.intent.type)) {
      score += 0.2;
    }

    // Penalty for no context matches
    if (matchingContexts.length === 0) {
      score *= 0.5;
    }

    return Math.min(1.0, score);
  }

  /**
   * Extract context from analysis
   * @private
   */
  extractContext(analysis) {
    const contexts = [];

    // Add intent type
    contexts.push(analysis.intent.type);

    // Add completion context
    if (analysis.completion.isComplete) {
      contexts.push('completion');
      contexts.push(analysis.completion.success ? 'success' : 'failure');
    }

    // Add progress context
    if (!analysis.progress.isProgressing) {
      contexts.push('stuck');
    }

    // Add recommendation as context
    contexts.push(analysis.recommendation);

    return contexts;
  }

  /**
   * Get escalation template
   * @private
   */
  getEscalationTemplate(showstopper) {
    const reason = showstopper.reasons[0]?.reason || 'Unknown issue';

    // Find matching escalation template
    for (const [key, template] of Object.entries(this.templates.escalation)) {
      if (reason.toLowerCase().includes(key.toLowerCase())) {
        return {
          template: template.template,
          confidence: template.confidence,
          category: 'escalation',
          key,
          isEscalation: true,
        };
      }
    }

    // Default escalation
    return {
      template: this.templates.escalation.showstopper.template,
      confidence: 1.0,
      category: 'escalation',
      key: 'showstopper',
      isEscalation: true,
    };
  }

  /**
   * Get default template
   * @private
   */
  getDefaultTemplate() {
    return {
      template: this.templates.continuation.default.template,
      confidence: 0.3,
      category: 'continuation',
      key: 'default',
      isEscalation: false,
    };
  }

  /**
   * Apply variable substitution to template
   * @param {string} template - Template string
   * @param {Object} variables - Variables to substitute
   * @returns {string} Processed template
   */
  applyVariables(template, variables = {}) {
    let processed = template;

    // Replace {variable} patterns
    for (const [key, value] of Object.entries(variables)) {
      const pattern = new RegExp(`\\{${key}\\}`, 'g');
      processed = processed.replace(pattern, value);
    }

    return processed;
  }

  /**
   * Get all templates for a category
   * @param {string} category - Template category
   * @returns {Object} Templates in category
   */
  getTemplatesByCategory(category) {
    return this.templates[category] || {};
  }

  /**
   * Add custom template
   * @param {string} category - Template category
   * @param {string} key - Template key
   * @param {Object} template - Template configuration
   */
  addTemplate(category, key, template) {
    if (!this.templates[category]) {
      this.templates[category] = {};
    }

    this.templates[category][key] = {
      template: template.template,
      confidence: template.confidence || 0.5,
      context: template.context || [],
      isEscalation: template.isEscalation || false,
    };

    logger.info('Added custom template', { category, key });
  }

  /**
   * Get response with context variables
   * @param {Object} analysis - Message analysis
   * @param {Object} context - Context with variables
   * @returns {Object} Complete response with processed template
   */
  getResponse(analysis, context = {}) {
    const selected = this.selectTemplate(analysis, context);

    // Apply variables if provided
    const processedTemplate = this.applyVariables(selected.template, context.variables || {});

    return {
      message: processedTemplate,
      confidence: selected.confidence,
      category: selected.category,
      key: selected.key,
      isEscalation: selected.isEscalation,
      requiresUserIntervention: selected.isEscalation || selected.confidence < 0.5,
      metadata: {
        analysis: analysis.intent.type,
        recommendation: analysis.recommendation,
        timestamp: new Date().toISOString(),
      },
    };
  }
}

export default ResponseTemplates;
