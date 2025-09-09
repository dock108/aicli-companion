/**
 * Readiness Scorer Service
 * Calculates project readiness scores and provides detailed feedback
 */

import { requirementsAnalyzer } from './requirements-analyzer.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('ReadinessScorer');

export class ReadinessScorer {
  constructor() {
    // Scoring weights for different aspects
    this.weights = {
      requirements: 0.35, // 35% - Requirements completeness
      technical_detail: 0.25, // 25% - Technical specification depth
      testing_strategy: 0.15, // 15% - Testing approach defined
      deployment_ready: 0.1, // 10% - Deployment considerations
      security: 0.1, // 10% - Security measures
      documentation: 0.05, // 5%  - Documentation quality
    };

    // Minimum scores for different readiness levels
    this.thresholds = {
      production_ready: 90,
      development_ready: 75,
      prototype_ready: 60,
      planning_needed: 40,
      not_ready: 0,
    };

    // Score modifiers based on project type
    this.projectTypeModifiers = {
      'web-app': {
        ui_ux: 1.2, // UI/UX more important
        api: 1.1,
        database: 1.0,
        deployment: 1.0,
      },
      'api-service': {
        api: 1.3, // API design critical
        database: 1.2,
        security: 1.2,
        ui_ux: 0.5, // UI less important
      },
      'mobile-app': {
        ui_ux: 1.3, // UI/UX critical
        api: 1.1,
        performance: 1.2,
        deployment: 0.8, // Different deployment model
      },
      'cli-tool': {
        api: 0.7, // API less important
        ui_ux: 0.3, // Minimal UI
        testing: 1.2, // Testing critical
        documentation: 1.3, // Docs very important
      },
    };
  }

  /**
   * Calculate comprehensive readiness score
   * @param {string} conversation - Planning conversation
   * @param {object} projectConfig - Project configuration
   * @returns {object} - Detailed scoring results
   */
  calculateReadiness(conversation, projectConfig = {}) {
    const startTime = Date.now();

    // Get requirements analysis
    const requirementsAnalysis = requirementsAnalyzer.analyzeConversation(conversation);

    // Calculate component scores
    const scores = {
      requirements: this.scoreRequirements(requirementsAnalysis),
      technical_detail: this.scoreTechnicalDetail(conversation),
      testing_strategy: this.scoreTestingStrategy(conversation),
      deployment_ready: this.scoreDeploymentReadiness(conversation),
      security: this.scoreSecurityReadiness(conversation),
      documentation: this.scoreDocumentation(conversation),
    };

    // Apply project type modifiers if specified
    if (projectConfig.projectType) {
      scores.adjusted = this.applyProjectTypeModifiers(scores, projectConfig.projectType);
    }

    // Calculate weighted overall score
    const overallScore = this.calculateWeightedScore(scores.adjusted || scores);

    // Determine readiness level
    const readinessLevel = this.determineReadinessLevel(overallScore);

    // Generate detailed feedback
    const feedback = this.generateDetailedFeedback(scores, requirementsAnalysis, overallScore);

    // Identify blockers
    const blockers = this.identifyBlockers(scores, requirementsAnalysis);

    // Generate action items
    const actionItems = this.generateActionItems(scores, requirementsAnalysis, projectConfig);

    const result = {
      overallScore: Math.round(overallScore),
      readinessLevel,
      scores,
      requirementsAnalysis,
      feedback,
      blockers,
      actionItems,
      metadata: {
        calculatedAt: new Date().toISOString(),
        calculationTime: Date.now() - startTime,
        conversationLength: conversation.length,
        projectType: projectConfig.projectType || 'general',
      },
    };

    logger.info('Readiness score calculated', {
      overallScore: result.overallScore,
      readinessLevel: readinessLevel.level,
      blockersCount: blockers.length,
      calculationTime: result.metadata.calculationTime,
    });

    return result;
  }

  /**
   * Score requirements completeness
   * @param {object} requirementsAnalysis - Requirements analysis results
   * @returns {number} - Requirements score (0-100)
   */
  scoreRequirements(requirementsAnalysis) {
    const domainScores = Object.values(requirementsAnalysis.domains).map((d) => d.score);
    const baseScore = requirementsAnalysis.overallScore;

    // Bonus for having all critical domains covered
    const criticalDomains = ['database', 'api', 'security'];
    const criticalCoverage = criticalDomains.every(
      (domain) => requirementsAnalysis.domains[domain]?.score > 50
    );
    const criticalBonus = criticalCoverage ? 10 : 0;

    // Penalty for completely missing domains
    const missingDomains = domainScores.filter((score) => score === 0).length;
    const missingPenalty = missingDomains * 5;

    return Math.min(100, Math.max(0, baseScore + criticalBonus - missingPenalty));
  }

  /**
   * Score technical detail depth
   * @param {string} conversation - Planning conversation
   * @returns {number} - Technical detail score (0-100)
   */
  scoreTechnicalDetail(conversation) {
    let score = 0;
    const checks = [
      // Data types and structures
      { pattern: /\b(varchar|int|boolean|timestamp|json|array|enum)\b/gi, weight: 10 },
      // Specific measurements
      {
        pattern: /\b\d+\s*(ms|seconds?|minutes?|hours?|gb|mb|kb|users?|requests?)\b/gi,
        weight: 15,
      },
      // HTTP methods and status codes
      { pattern: /\b(GET|POST|PUT|DELETE|PATCH|200|201|400|401|403|404|500)\b/g, weight: 10 },
      // Technical specifications
      { pattern: /\b(algorithm|encryption|hashing|compression|indexing|caching)\b/gi, weight: 15 },
      // Architecture patterns
      {
        pattern: /\b(mvc|mvvm|microservice|monolith|serverless|rest|graphql|websocket)\b/gi,
        weight: 10,
      },
      // Specific technologies mentioned
      {
        pattern: /\b(react|vue|angular|node|python|java|postgres|mysql|mongodb|redis|docker)\b/gi,
        weight: 10,
      },
      // Version numbers
      { pattern: /\bv?\d+\.\d+(\.\d+)?/g, weight: 5 },
      // Code snippets or examples
      { pattern: /```[\s\S]*?```/g, weight: 15 },
      // API paths
      { pattern: /\/api\/\w+/g, weight: 10 },
    ];

    for (const check of checks) {
      const matches = conversation.match(check.pattern);
      if (matches) {
        score += Math.min(check.weight, (matches.length / 3) * check.weight);
      }
    }

    return Math.min(100, score);
  }

  /**
   * Score testing strategy completeness
   * @param {string} conversation - Planning conversation
   * @returns {number} - Testing score (0-100)
   */
  scoreTestingStrategy(conversation) {
    let score = 0;
    const lowerConversation = conversation.toLowerCase();

    // Check for different test types mentioned
    const testTypes = [
      { keyword: 'unit test', weight: 25 },
      { keyword: 'integration test', weight: 20 },
      { keyword: 'end-to-end', weight: 15 },
      { keyword: 'e2e test', weight: 15 },
      { keyword: 'performance test', weight: 10 },
      { keyword: 'load test', weight: 10 },
      { keyword: 'security test', weight: 10 },
      { keyword: 'coverage', weight: 15 },
      { keyword: 'tdd', weight: 20 },
      { keyword: 'test-driven', weight: 20 },
    ];

    for (const testType of testTypes) {
      if (lowerConversation.includes(testType.keyword)) {
        score += testType.weight;
      }
    }

    // Check for specific coverage targets
    const coverageMatch = conversation.match(/\b\d+%?\s*coverage/gi);
    if (coverageMatch) {
      score += 10;
    }

    // Check for testing tools mentioned
    const testingTools = ['jest', 'mocha', 'chai', 'cypress', 'selenium', 'pytest', 'unittest'];
    const toolsFound = testingTools.filter((tool) => lowerConversation.includes(tool));
    score += toolsFound.length * 5;

    return Math.min(100, score);
  }

  /**
   * Score deployment readiness
   * @param {string} conversation - Planning conversation
   * @returns {number} - Deployment score (0-100)
   */
  scoreDeploymentReadiness(conversation) {
    let score = 0;
    const lowerConversation = conversation.toLowerCase();

    // Deployment platforms
    const platforms = [
      { keyword: 'docker', weight: 15 },
      { keyword: 'kubernetes', weight: 15 },
      { keyword: 'aws', weight: 10 },
      { keyword: 'azure', weight: 10 },
      { keyword: 'gcp', weight: 10 },
      { keyword: 'google cloud', weight: 10 },
      { keyword: 'heroku', weight: 10 },
      { keyword: 'vercel', weight: 10 },
      { keyword: 'netlify', weight: 10 },
    ];

    // CI/CD mentions
    const cicd = [
      { keyword: 'ci/cd', weight: 20 },
      { keyword: 'continuous integration', weight: 15 },
      { keyword: 'continuous deployment', weight: 15 },
      { keyword: 'github actions', weight: 10 },
      { keyword: 'jenkins', weight: 10 },
      { keyword: 'gitlab ci', weight: 10 },
      { keyword: 'circle ci', weight: 10 },
    ];

    // Monitoring and logging
    const monitoring = [
      { keyword: 'monitoring', weight: 15 },
      { keyword: 'logging', weight: 10 },
      { keyword: 'metrics', weight: 10 },
      { keyword: 'alerting', weight: 10 },
      { keyword: 'observability', weight: 15 },
    ];

    // Environment management
    const environments = [
      { keyword: 'production', weight: 10 },
      { keyword: 'staging', weight: 10 },
      { keyword: 'development environment', weight: 5 },
      { keyword: 'environment variable', weight: 10 },
    ];

    const allChecks = [...platforms, ...cicd, ...monitoring, ...environments];

    for (const check of allChecks) {
      if (lowerConversation.includes(check.keyword)) {
        score += check.weight;
      }
    }

    return Math.min(100, score);
  }

  /**
   * Score security readiness
   * @param {string} conversation - Planning conversation
   * @returns {number} - Security score (0-100)
   */
  scoreSecurityReadiness(conversation) {
    let score = 0;
    const lowerConversation = conversation.toLowerCase();

    const securityChecks = [
      { keyword: 'authentication', weight: 20 },
      { keyword: 'authorization', weight: 15 },
      { keyword: 'oauth', weight: 10 },
      { keyword: 'jwt', weight: 10 },
      { keyword: 'encryption', weight: 15 },
      { keyword: 'https', weight: 10 },
      { keyword: 'ssl', weight: 10 },
      { keyword: 'tls', weight: 10 },
      { keyword: 'hash', weight: 10 },
      { keyword: 'bcrypt', weight: 10 },
      { keyword: 'salt', weight: 10 },
      { keyword: 'input validation', weight: 15 },
      { keyword: 'sql injection', weight: 10 },
      { keyword: 'xss', weight: 10 },
      { keyword: 'csrf', weight: 10 },
      { keyword: 'rate limit', weight: 10 },
      { keyword: 'security header', weight: 10 },
      { keyword: 'cors', weight: 10 },
      { keyword: 'penetration test', weight: 15 },
      { keyword: 'security audit', weight: 15 },
      { keyword: 'vulnerability', weight: 10 },
      { keyword: 'owasp', weight: 15 },
    ];

    for (const check of securityChecks) {
      if (lowerConversation.includes(check.keyword)) {
        score += check.weight;
      }
    }

    return Math.min(100, score);
  }

  /**
   * Score documentation quality
   * @param {string} conversation - Planning conversation
   * @returns {number} - Documentation score (0-100)
   */
  scoreDocumentation(conversation) {
    let score = 0;

    // Check for structured sections (markdown headers)
    const headers = conversation.match(/^#+\s+/gm);
    if (headers && headers.length > 5) {
      score += 20;
    }

    // Check for lists (ordered or unordered)
    const lists = conversation.match(/^\s*[-*+]\s+/gm);
    if (lists && lists.length > 10) {
      score += 15;
    }

    // Check for code blocks
    const codeBlocks = conversation.match(/```[\s\S]*?```/g);
    if (codeBlocks && codeBlocks.length > 0) {
      score += 20;
    }

    // Check for diagrams or visual representations
    const diagrams = conversation.match(/\b(diagram|chart|graph|flow|wireframe|mockup)\b/gi);
    if (diagrams && diagrams.length > 0) {
      score += 15;
    }

    // Check for API documentation patterns
    const apiDocs = conversation.match(/\b(request|response|payload|header|parameter|body)\b/gi);
    if (apiDocs && apiDocs.length > 5) {
      score += 15;
    }

    // Check for examples
    const examples = conversation.match(/\b(example|sample|e\.g\.|for instance)\b/gi);
    if (examples && examples.length > 3) {
      score += 15;
    }

    return Math.min(100, score);
  }

  /**
   * Apply project type modifiers to scores
   * @param {object} scores - Base scores
   * @param {string} projectType - Type of project
   * @returns {object} - Adjusted scores
   */
  applyProjectTypeModifiers(scores, projectType) {
    const modifiers = this.projectTypeModifiers[projectType];
    if (!modifiers) {
      return scores;
    }

    const adjusted = { ...scores };

    // Apply modifiers based on project type priorities
    if (modifiers.ui_ux !== undefined && scores.requirements) {
      adjusted.requirements = Math.min(100, scores.requirements * modifiers.ui_ux);
    }

    if (modifiers.api !== undefined && scores.technical_detail) {
      adjusted.technical_detail = Math.min(100, scores.technical_detail * modifiers.api);
    }

    if (modifiers.testing !== undefined && scores.testing_strategy) {
      adjusted.testing_strategy = Math.min(100, scores.testing_strategy * modifiers.testing);
    }

    if (modifiers.documentation !== undefined && scores.documentation) {
      adjusted.documentation = Math.min(100, scores.documentation * modifiers.documentation);
    }

    return adjusted;
  }

  /**
   * Calculate weighted overall score
   * @param {object} scores - Component scores
   * @returns {number} - Weighted score
   */
  calculateWeightedScore(scores) {
    let weightedSum = 0;
    let totalWeight = 0;

    for (const [component, weight] of Object.entries(this.weights)) {
      if (scores[component] !== undefined) {
        weightedSum += scores[component] * weight;
        totalWeight += weight;
      }
    }

    return totalWeight > 0 ? weightedSum / totalWeight : 0;
  }

  /**
   * Determine readiness level based on score
   * @param {number} score - Overall score
   * @returns {object} - Readiness level details
   */
  determineReadinessLevel(score) {
    if (score >= this.thresholds.production_ready) {
      return {
        level: 'production-ready',
        label: 'Production Ready',
        color: '#4CAF50',
        icon: '🚀',
        description: 'Project is fully specified and ready for production development',
        canProceed: true,
      };
    } else if (score >= this.thresholds.development_ready) {
      return {
        level: 'development-ready',
        label: 'Development Ready',
        color: '#8BC34A',
        icon: '✅',
        description:
          'Ready to start development with minor gaps that can be addressed during implementation',
        canProceed: true,
      };
    } else if (score >= this.thresholds.prototype_ready) {
      return {
        level: 'prototype-ready',
        label: 'Prototype Ready',
        color: '#FFC107',
        icon: '🔨',
        description:
          'Sufficient detail for prototyping, but production features need more planning',
        canProceed: true,
        withWarning: true,
      };
    } else if (score >= this.thresholds.planning_needed) {
      return {
        level: 'planning-needed',
        label: 'More Planning Needed',
        color: '#FF9800',
        icon: '📝',
        description: 'Significant gaps in requirements, continued planning recommended',
        canProceed: false,
        requiresOverride: true,
      };
    } else {
      return {
        level: 'not-ready',
        label: 'Not Ready',
        color: '#F44336',
        icon: '🛑',
        description: 'Insufficient planning, comprehensive requirements gathering needed',
        canProceed: false,
      };
    }
  }

  /**
   * Generate detailed feedback
   * @param {object} scores - Component scores
   * @param {object} requirementsAnalysis - Requirements analysis
   * @param {number} overallScore - Overall score
   * @returns {array} - Feedback messages
   */
  generateDetailedFeedback(scores, requirementsAnalysis, overallScore) {
    const feedback = [];

    // Overall assessment
    if (overallScore >= 90) {
      feedback.push({
        type: 'success',
        message: 'Excellent! Your project is comprehensively planned and ready for development.',
        priority: 'info',
      });
    } else if (overallScore >= 75) {
      feedback.push({
        type: 'success',
        message:
          'Good planning! You can start development, but consider addressing the gaps during implementation.',
        priority: 'info',
      });
    } else if (overallScore >= 60) {
      feedback.push({
        type: 'warning',
        message:
          'Decent foundation, but important details are missing. Review the suggestions before starting.',
        priority: 'medium',
      });
    } else {
      feedback.push({
        type: 'error',
        message:
          'Significant planning required. Work through each domain systematically before development.',
        priority: 'high',
      });
    }

    // Component-specific feedback
    for (const [component, score] of Object.entries(scores)) {
      if (score < 50) {
        const componentName = component.replace('_', ' ').replace(/\b\w/g, (l) => l.toUpperCase());
        feedback.push({
          type: 'warning',
          message: `${componentName} needs attention (${Math.round(score)}% complete)`,
          priority: score < 30 ? 'high' : 'medium',
        });
      }
    }

    // Missing domain feedback
    for (const missing of requirementsAnalysis.missingRequirements) {
      if (missing.missing.length > 2) {
        feedback.push({
          type: 'info',
          message: `${missing.icon} ${missing.domain}: Missing ${missing.missing.slice(0, 3).join(', ')}`,
          priority: 'medium',
        });
      }
    }

    return feedback;
  }

  /**
   * Identify blockers that prevent development
   * @param {object} scores - Component scores
   * @param {object} requirementsAnalysis - Requirements analysis
   * @returns {array} - List of blockers
   */
  identifyBlockers(scores, requirementsAnalysis) {
    const blockers = [];

    // Critical missing requirements
    const criticalDomains = ['database', 'api', 'security'];
    for (const domain of criticalDomains) {
      if (requirementsAnalysis.domains[domain]?.score < 30) {
        blockers.push({
          severity: 'critical',
          domain,
          message: `${domain.charAt(0).toUpperCase() + domain.slice(1)} design is severely lacking`,
          resolution: `Define ${requirementsAnalysis.domains[domain].missingRequirements.slice(0, 2).join(', ')}`,
        });
      }
    }

    // No technical details
    if (scores.technical_detail < 20) {
      blockers.push({
        severity: 'high',
        domain: 'technical',
        message: 'Insufficient technical specifications',
        resolution: 'Add specific data types, API endpoints, and technical constraints',
      });
    }

    // No testing strategy
    if (scores.testing_strategy < 20) {
      blockers.push({
        severity: 'medium',
        domain: 'testing',
        message: 'No testing strategy defined',
        resolution: 'Define test types, coverage targets, and testing approach',
      });
    }

    // No deployment plan
    if (scores.deployment_ready < 20) {
      blockers.push({
        severity: 'medium',
        domain: 'deployment',
        message: 'Deployment strategy not defined',
        resolution: 'Specify target platform, CI/CD approach, and monitoring',
      });
    }

    return blockers;
  }

  /**
   * Calculate score for a specific domain
   * @param {string} domain - Domain name
   * @param {array} domainReqs - Requirements for the domain
   * @param {string} projectType - Type of project
   * @returns {number} - Domain score (0-100)
   */
  calculateDomainScore(domain, domainReqs, projectType) {
    if (!domainReqs || domainReqs.length === 0) {
      return 0;
    }

    // Simple scoring based on requirement count
    // More requirements = higher score, up to a reasonable maximum
    const baseScore = Math.min(100, domainReqs.length * 20);

    // Apply project type modifier if available
    if (
      projectType &&
      this.projectTypeModifiers[projectType] &&
      this.projectTypeModifiers[projectType][domain]
    ) {
      return Math.min(100, baseScore * this.projectTypeModifiers[projectType][domain]);
    }

    return baseScore;
  }

  /**
   * Calculate overall score from requirements
   * @param {Map} requirements - Map of domain requirements
   * @param {string} projectType - Type of project
   * @returns {number} - Overall score (0-100)
   */
  calculateScore(requirements, projectType) {
    if (!requirements || requirements.size === 0) {
      return 0;
    }

    let totalScore = 0;
    let domainCount = 0;

    for (const [domain, domainReqs] of requirements.entries()) {
      const domainScore = this.calculateDomainScore(domain, domainReqs, projectType);
      totalScore += domainScore;
      domainCount++;
    }

    return domainCount > 0 ? Math.round(totalScore / domainCount) : 0;
  }

  /**
   * Get readiness level based on score
   * @param {number} score - Overall score
   * @returns {string} - Readiness level
   */
  getReadinessLevel(score) {
    if (score >= this.thresholds.production_ready) {
      return 'ready';
    } else if (score >= this.thresholds.development_ready) {
      return 'partial';
    } else if (score >= this.thresholds.prototype_ready) {
      return 'incomplete';
    } else {
      return 'insufficient';
    }
  }

  /**
   * Generate actionable items to improve readiness
   * @param {object} scores - Component scores
   * @param {object} requirementsAnalysis - Requirements analysis
   * @param {object} projectConfig - Project configuration
   * @returns {array} - Action items
   */
  generateActionItems(scores, requirementsAnalysis, _projectConfig) {
    const actionItems = [];

    // Priority 1: Critical missing requirements
    for (const missing of requirementsAnalysis.missingRequirements) {
      if (missing.missing.length > 0) {
        actionItems.push({
          priority: 1,
          category: missing.domain,
          action: `Define ${missing.missing[0]}`,
          impact: 'high',
          effort: 'medium',
          icon: missing.icon,
        });
      }
    }

    // Priority 2: Low scoring components
    const componentPriority = {
      security: 1,
      requirements: 2,
      technical_detail: 3,
      testing_strategy: 4,
      deployment_ready: 5,
      documentation: 6,
    };

    for (const [component, score] of Object.entries(scores)) {
      if (score < 60) {
        const priority = componentPriority[component] || 5;
        actionItems.push({
          priority,
          category: component,
          action: this.getComponentAction(component, score),
          impact: score < 30 ? 'high' : 'medium',
          effort: 'medium',
          icon: this.getComponentIcon(component),
        });
      }
    }

    // Sort by priority
    actionItems.sort((a, b) => a.priority - b.priority);

    // Limit to top 10 items
    return actionItems.slice(0, 10);
  }

  /**
   * Get action for improving a component
   * @param {string} component - Component name
   * @param {number} score - Current score
   * @returns {string} - Action description
   */
  getComponentAction(component, _score) {
    const actions = {
      requirements: 'Add detailed specifications for core features',
      technical_detail: 'Include specific data types, API contracts, and technical constraints',
      testing_strategy: 'Define test types, coverage goals, and testing tools',
      deployment_ready: 'Specify deployment platform and CI/CD pipeline',
      security: 'Add authentication method and security measures',
      documentation: 'Structure planning with clear sections and examples',
    };

    return actions[component] || 'Improve specifications';
  }

  /**
   * Get icon for a component
   * @param {string} component - Component name
   * @returns {string} - Emoji icon
   */
  getComponentIcon(component) {
    const icons = {
      requirements: '📋',
      technical_detail: '⚙️',
      testing_strategy: '🧪',
      deployment_ready: '🚀',
      security: '🔒',
      documentation: '📄',
    };

    return icons[component] || '📌';
  }
}

// Export singleton instance
export const readinessScorer = new ReadinessScorer();
