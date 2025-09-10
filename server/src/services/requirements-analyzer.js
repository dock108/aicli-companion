/**
 * Requirements Analyzer Service
 * Analyzes planning conversations to extract and validate requirements
 */

import { createLogger } from '../utils/logger.js';

const logger = createLogger('RequirementsAnalyzer');

export class RequirementsAnalyzer {
  constructor() {
    // Domain categories that should be covered
    this.domains = {
      database: {
        name: 'Database Design',
        icon: '🗄️',
        keywords: [
          'schema',
          'table',
          'database',
          'model',
          'relation',
          'constraint',
          'migration',
          'index',
        ],
        requirements: [
          'table_definitions',
          'relationships',
          'constraints',
          'indexes',
          'migration_strategy',
        ],
      },
      api: {
        name: 'API Design',
        icon: '🔌',
        keywords: [
          'endpoint',
          'api',
          'route',
          'rest',
          'graphql',
          'contract',
          'request',
          'response',
        ],
        requirements: [
          'endpoints',
          'authentication',
          'authorization',
          'rate_limiting',
          'response_formats',
          'error_handling',
        ],
      },
      ui_ux: {
        name: 'UI/UX Design',
        icon: '🎨',
        keywords: ['ui', 'ux', 'interface', 'screen', 'component', 'wireframe', 'flow', 'design'],
        requirements: [
          'user_flows',
          'wireframes',
          'component_specs',
          'responsive_design',
          'accessibility',
        ],
      },
      security: {
        name: 'Security',
        icon: '🔒',
        keywords: ['security', 'auth', 'encryption', 'ssl', 'https', 'oauth', 'jwt', 'permission'],
        requirements: [
          'authentication_method',
          'authorization_model',
          'data_encryption',
          'input_validation',
          'security_headers',
        ],
      },
      performance: {
        name: 'Performance',
        icon: '⚡',
        keywords: ['performance', 'cache', 'optimize', 'speed', 'load', 'scale', 'concurrent'],
        requirements: [
          'response_time_targets',
          'concurrent_users',
          'caching_strategy',
          'optimization_areas',
          'monitoring_metrics',
        ],
      },
      deployment: {
        name: 'Deployment',
        icon: '🚀',
        keywords: [
          'deploy',
          'docker',
          'kubernetes',
          'ci',
          'cd',
          'pipeline',
          'production',
          'staging',
        ],
        requirements: [
          'deployment_target',
          'ci_cd_pipeline',
          'monitoring',
          'logging',
          'rollback_strategy',
        ],
      },
      testing: {
        name: 'Testing',
        icon: '🧪',
        keywords: ['test', 'unit', 'integration', 'e2e', 'coverage', 'tdd', 'testing'],
        requirements: [
          'unit_test_coverage',
          'integration_tests',
          'e2e_scenarios',
          'performance_tests',
          'security_tests',
        ],
      },
      business: {
        name: 'Business Logic',
        icon: '💼',
        keywords: ['business', 'feature', 'requirement', 'user story', 'acceptance', 'criteria'],
        requirements: [
          'core_features',
          'user_stories',
          'acceptance_criteria',
          'business_rules',
          'validation_logic',
        ],
      },
    };

    // Patterns to detect specific requirement mentions
    this.patterns = {
      database_schema:
        /(?:table|schema|model|entity|database)\s{1,10}(?:definition|structure|design)/gi,
      api_endpoints: /(?:endpoint|api|route|rest|graphql)\s{1,10}(?:definition|design|contract)/gi,
      ui_components:
        /(?:ui|interface|screen|component|wireframe)\s{1,10}(?:design|specification|layout)/gi,
      authentication: /(?:auth|authentication|login|signup|oauth|jwt|session)/gi,
      performance_targets: /(?:\d+\s*ms|\d+\s*seconds?|response time|load time|concurrent users)/gi,
      deployment_info: /(?:deploy|docker|kubernetes|aws|azure|gcp|heroku|production)/gi,
      testing_strategy: /(?:test|testing|tdd|coverage|unit|integration|e2e)/gi,
    };
  }

  /**
   * Analyze a conversation for requirements completeness
   * @param {string} conversation - The planning conversation text
   * @returns {object} - Analysis results with completeness scores
   */
  analyzeConversation(conversation) {
    const analysis = {
      domains: {},
      overallScore: 0,
      missingRequirements: [],
      foundRequirements: [],
      suggestions: [],
      confidence: 0,
    };

    // Analyze each domain
    for (const [domainKey, domain] of Object.entries(this.domains)) {
      const domainAnalysis = this.analyzeDomain(conversation, domain, domainKey);
      analysis.domains[domainKey] = domainAnalysis;

      // Collect missing requirements
      if (domainAnalysis.missingRequirements.length > 0) {
        analysis.missingRequirements.push({
          domain: domain.name,
          icon: domain.icon,
          missing: domainAnalysis.missingRequirements,
        });
      }

      // Collect found requirements
      if (domainAnalysis.foundRequirements.length > 0) {
        analysis.foundRequirements.push({
          domain: domain.name,
          icon: domain.icon,
          found: domainAnalysis.foundRequirements,
        });
      }
    }

    // Calculate overall score
    const scores = Object.values(analysis.domains).map((d) => d.score);
    analysis.overallScore = Math.round(scores.reduce((a, b) => a + b, 0) / scores.length);

    // Calculate confidence based on conversation length and keyword density
    analysis.confidence = this.calculateConfidence(conversation, analysis);

    // Generate suggestions
    analysis.suggestions = this.generateSuggestions(analysis);

    // Determine readiness
    analysis.isReady = analysis.overallScore >= 80;
    analysis.readinessLevel = this.getReadinessLevel(analysis.overallScore);

    logger.info('Requirements analysis completed', {
      overallScore: analysis.overallScore,
      confidence: analysis.confidence,
      domainsAnalyzed: Object.keys(analysis.domains).length,
    });

    return analysis;
  }

  /**
   * Analyze a specific domain
   * @param {string} conversation - The conversation text
   * @param {object} domain - Domain configuration
   * @param {string} domainKey - Domain identifier
   * @returns {object} - Domain analysis results
   */
  analyzeDomain(conversation, domain, _domainKey) {
    const analysis = {
      name: domain.name,
      icon: domain.icon,
      score: 0,
      foundRequirements: [],
      missingRequirements: [],
      keywordMatches: 0,
      confidence: 0,
    };

    // Check for keyword matches
    for (const keyword of domain.keywords) {
      const regex = new RegExp(`\\b${keyword}\\b`, 'gi');
      const matches = conversation.match(regex);
      if (matches) {
        analysis.keywordMatches += matches.length;
      }
    }

    // Check specific requirements
    for (const requirement of domain.requirements) {
      const found = this.checkRequirement(conversation, requirement, null);
      if (found) {
        analysis.foundRequirements.push(this.formatRequirement(requirement));
      } else {
        analysis.missingRequirements.push(this.formatRequirement(requirement));
      }
    }

    // Calculate domain score
    const foundCount = analysis.foundRequirements.length;
    const totalCount = domain.requirements.length;
    analysis.score = totalCount > 0 ? Math.round((foundCount / totalCount) * 100) : 0;

    // Calculate domain confidence
    analysis.confidence = Math.min(100, Math.round((analysis.keywordMatches / 5) * 100));

    return analysis;
  }

  /**
   * Check if a specific requirement is mentioned
   * @param {string} conversation - The conversation text
   * @param {string} requirement - The requirement to check
   * @param {string} domainKey - The domain key
   * @returns {boolean} - Whether requirement was found
   */
  checkRequirement(conversation, requirement, _domainKey) {
    const lowerConversation = conversation.toLowerCase();
    const requirementWords = requirement.split('_').join(' ');

    // Direct mention check
    if (lowerConversation.includes(requirementWords)) {
      return true;
    }

    // Pattern-based checks for specific requirements
    switch (requirement) {
      case 'table_definitions':
        return /(?:table|entity|model)\s{1,10}(?:definition|structure|schema)/gi.test(conversation);

      case 'relationships':
        return /(?:relationship|relation|foreign key|reference|association)/gi.test(conversation);

      case 'endpoints':
        return /(?:endpoint|api|route|path|rest|graphql)/gi.test(conversation);

      case 'authentication_method':
        return /(?:auth|authentication|oauth|jwt|login|signup)/gi.test(conversation);

      case 'user_flows':
        return /(?:user flow|user journey|workflow|process flow)/gi.test(conversation);

      case 'response_time_targets':
        // Fixed ReDoS: Limit digit repetition and use more specific patterns
        return /(?:\d{1,6}\s{0,3}ms|\d{1,3}\s{0,3}seconds?|response time|performance target)/gi.test(
          conversation
        );

      case 'deployment_target':
        return /(?:deploy|hosting|aws|azure|gcp|heroku|docker|kubernetes)/gi.test(conversation);

      case 'unit_test_coverage': {
        // Fixed ReDoS: Limit digit repetition for coverage percentage
        return /(?:test coverage|\d{1,3}%\s{0,3}coverage|unit test|testing strategy)/gi.test(
          conversation
        );
      }

      default: {
        // Check for any word from the requirement in conversation
        const words = requirement.split('_');
        return words.some((word) => lowerConversation.includes(word));
      }
    }
  }

  /**
   * Format requirement name for display
   * @param {string} requirement - Raw requirement name
   * @returns {string} - Formatted requirement name
   */
  formatRequirement(requirement) {
    return requirement
      .split('_')
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  }

  /**
   * Calculate confidence in the analysis
   * @param {string} conversation - The conversation text
   * @param {object} analysis - Current analysis results
   * @returns {number} - Confidence percentage
   */
  calculateConfidence(conversation, analysis) {
    const factors = {
      conversationLength: Math.min(100, (conversation.length / 5000) * 100),
      keywordDensity: 0,
      domainCoverage:
        (Object.values(analysis.domains).filter((d) => d.score > 0).length /
          Object.keys(this.domains).length) *
        100,
      specificityScore: 0,
    };

    // Calculate keyword density
    const totalKeywords = Object.values(analysis.domains).reduce(
      (sum, d) => sum + d.keywordMatches,
      0
    );
    factors.keywordDensity = Math.min(100, (totalKeywords / 50) * 100);

    // Check for specific technical details
    const technicalPatterns = [
      /\b\d{1,10}\s{0,3}(ms|seconds?|minutes?|gb|mb|users?)\b/gi,
      /\b(post|get|put|delete|patch)\s{1,10}\/\w{1,100}/gi,
      /\b(varchar|int|boolean|timestamp|foreign key)\b/gi,
    ];

    const specificMatches = technicalPatterns.reduce((count, pattern) => {
      const matches = conversation.match(pattern);
      return count + (matches ? matches.length : 0);
    }, 0);

    factors.specificityScore = Math.min(100, (specificMatches / 10) * 100);

    // Weighted average
    const confidence = Math.round(
      factors.conversationLength * 0.2 +
        factors.keywordDensity * 0.3 +
        factors.domainCoverage * 0.3 +
        factors.specificityScore * 0.2
    );

    return Math.min(100, confidence);
  }

  /**
   * Generate suggestions based on analysis
   * @param {object} analysis - Analysis results
   * @returns {array} - List of suggestions
   */
  generateSuggestions(analysis) {
    const suggestions = [];

    // Check critical missing domains
    const criticalDomains = ['database', 'api', 'security'];
    for (const domain of criticalDomains) {
      if (analysis.domains[domain].score < 50) {
        suggestions.push({
          priority: 'high',
          icon: analysis.domains[domain].icon,
          message: `${analysis.domains[domain].name} needs more detail - only ${analysis.domains[domain].score}% complete`,
          action: `Discuss ${analysis.domains[domain].missingRequirements.slice(0, 2).join(', ')}`,
        });
      }
    }

    // Check for completely missing domains
    for (const [_key, domain] of Object.entries(analysis.domains)) {
      if (domain.score === 0) {
        suggestions.push({
          priority: 'medium',
          icon: domain.icon,
          message: `${domain.name} hasn't been discussed yet`,
          action: `Add ${domain.name.toLowerCase()} specifications`,
        });
      }
    }

    // Suggest next steps based on readiness
    if (analysis.overallScore >= 80) {
      suggestions.push({
        priority: 'low',
        icon: '✅',
        message: 'Project is ready for development!',
        action: 'Consider reviewing edge cases and non-functional requirements',
      });
    } else if (analysis.overallScore >= 60) {
      suggestions.push({
        priority: 'medium',
        icon: '📝',
        message: 'Good progress, but more planning needed',
        action: 'Focus on the high-priority missing requirements',
      });
    } else {
      suggestions.push({
        priority: 'high',
        icon: '⚠️',
        message: 'Significant planning still required',
        action: 'Work through each domain systematically',
      });
    }

    return suggestions;
  }

  /**
   * Get readiness level based on score
   * @param {number} score - Overall score
   * @returns {object} - Readiness level details
   */
  getReadinessLevel(score) {
    if (score >= 90) {
      return {
        level: 'production-ready',
        color: 'green',
        icon: '🚀',
        message: 'Fully specified and ready for production development',
      };
    } else if (score >= 80) {
      return {
        level: 'development-ready',
        color: 'lightgreen',
        icon: '✅',
        message: 'Ready to start development with minor gaps',
      };
    } else if (score >= 60) {
      return {
        level: 'partially-ready',
        color: 'yellow',
        icon: '⚠️',
        message: 'Some critical requirements still missing',
      };
    } else if (score >= 40) {
      return {
        level: 'planning-phase',
        color: 'orange',
        icon: '📝',
        message: 'In early planning phase, significant work needed',
      };
    } else {
      return {
        level: 'initial-phase',
        color: 'red',
        icon: '🔴',
        message: 'Just getting started, comprehensive planning required',
      };
    }
  }

  /**
   * Extract requirements from structured text (like plan.md)
   * @param {string} planText - Structured planning document
   * @returns {object} - Extracted requirements
   */
  extractFromPlan(planText) {
    const extracted = {
      features: [],
      database: [],
      api: [],
      ui: [],
      testing: [],
      deployment: [],
    };

    // Extract sections using markdown headers
    const sections = planText.split(/^##\s{1,10}/gm);

    for (const section of sections) {
      const lines = section.split('\n');
      const header = lines[0]?.toLowerCase() || '';

      // Extract checklist items
      const checklistItems = lines
        .filter((line) => line.match(/^\s{0,10}-\s{0,5}\[[ x]\]/i))
        .map((line) => line.replace(/^\s{0,10}-\s{0,5}\[[ x]\]\s{0,10}/i, '').trim());

      // Categorize by header
      if (header.includes('feature') || header.includes('requirement')) {
        extracted.features.push(...checklistItems);
      } else if (header.includes('database') || header.includes('schema')) {
        extracted.database.push(...checklistItems);
      } else if (header.includes('api') || header.includes('endpoint')) {
        extracted.api.push(...checklistItems);
      } else if (header.includes('ui') || header.includes('interface')) {
        extracted.ui.push(...checklistItems);
      } else if (header.includes('test')) {
        extracted.testing.push(...checklistItems);
      } else if (header.includes('deploy') || header.includes('infrastructure')) {
        extracted.deployment.push(...checklistItems);
      }
    }

    return extracted;
  }
}

// Export singleton instance
export const requirementsAnalyzer = new RequirementsAnalyzer();
