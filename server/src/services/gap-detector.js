/**
 * Gap Detector Service
 * Identifies missing requirements and generates recommendations
 */

import { createLogger } from '../utils/logger.js';
import path from 'path';
import { promises as fs } from 'fs';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const logger = createLogger('GapDetector');

export class GapDetector {
  constructor() {
    this.configPath = path.join(__dirname, '../../config/validation-rules.json');
    this.rules = null;
    this.loadRules();
  }

  /**
   * Load validation rules from configuration
   */
  async loadRules() {
    try {
      const rulesContent = await fs.readFile(this.configPath, 'utf-8');
      this.rules = JSON.parse(rulesContent);
      logger.info('Loaded validation rules');
    } catch (error) {
      logger.warn('Failed to load validation rules, using defaults', { error: error.message });
      this.rules = this.getDefaultRules();
    }
  }

  /**
   * Get default validation rules
   * @returns {object} - Default rules
   */
  getDefaultRules() {
    return {
      project_types: {
        'web-app': {
          required: ['database.schema', 'api.endpoints', 'ui_ux.screens', 'auth.strategy'],
          recommended: ['performance.targets', 'deployment.environment', 'testing.strategy'],
          optional: ['monitoring', 'analytics']
        },
        'mobile-app': {
          required: ['ui_ux.screens', 'ui_ux.navigation', 'api.endpoints', 'auth.strategy'],
          recommended: ['offline.strategy', 'push.notifications', 'performance.targets'],
          optional: ['analytics', 'crash.reporting']
        },
        'api-service': {
          required: ['api.endpoints', 'database.schema', 'auth.strategy'],
          recommended: ['api.documentation', 'rate_limiting', 'monitoring'],
          optional: ['ui_ux']
        },
        'cli-tool': {
          required: ['commands', 'arguments', 'output.format'],
          recommended: ['help.documentation', 'config.management'],
          optional: ['update.mechanism']
        }
      },
      completeness_criteria: {
        'database.schema': {
          must_have: ['tables', 'primary_keys', 'relationships'],
          should_have: ['indexes', 'constraints', 'migrations'],
          nice_to_have: ['seed_data', 'backup_strategy']
        },
        'api.endpoints': {
          must_have: ['http_methods', 'paths', 'response_formats'],
          should_have: ['request_validation', 'error_handling', 'rate_limiting'],
          nice_to_have: ['api_documentation', 'versioning']
        },
        'ui_ux.screens': {
          must_have: ['screen_list', 'navigation_flow'],
          should_have: ['responsive_design', 'user_interactions'],
          nice_to_have: ['animations', 'accessibility']
        },
        'auth.strategy': {
          must_have: ['authentication_method', 'user_roles'],
          should_have: ['session_management', 'password_policy'],
          nice_to_have: ['mfa', 'sso']
        },
        'performance.targets': {
          must_have: ['response_time', 'concurrent_users'],
          should_have: ['caching_strategy', 'load_testing'],
          nice_to_have: ['cdn', 'optimization']
        },
        'deployment.environment': {
          must_have: ['hosting_platform', 'deployment_process'],
          should_have: ['environments', 'ci_cd'],
          nice_to_have: ['rollback_strategy', 'blue_green']
        },
        'testing.strategy': {
          must_have: ['unit_tests', 'test_coverage'],
          should_have: ['integration_tests', 'e2e_tests'],
          nice_to_have: ['performance_tests', 'security_tests']
        }
      }
    };
  }

  /**
   * Detect gaps in requirements
   * @param {Map} requirements - Current requirements by domain
   * @param {string} projectType - Type of project
   * @returns {object} - Gaps by domain
   */
  detectGaps(requirements, projectType = 'web-app') {
    const gaps = {};
    
    // Ensure rules are loaded
    if (!this.rules) {
      this.rules = this.getDefaultRules();
    }
    
    const projectRules = this.rules.project_types[projectType] || this.rules.project_types['web-app'];
    
    // Check required items
    for (const requirement of projectRules.required) {
      const [domain, aspect] = requirement.split('.');
      const domainReqs = requirements.get(domain) || [];
      
      if (!this.hasRequirement(domainReqs, aspect)) {
        if (!gaps[domain]) gaps[domain] = [];
        gaps[domain].push({
          item: aspect,
          priority: 'critical',
          description: this.getGapDescription(domain, aspect),
          type: 'required'
        });
      }
    }
    
    // Check recommended items
    for (const requirement of projectRules.recommended) {
      const [domain, aspect] = requirement.split('.');
      const domainReqs = requirements.get(domain) || [];
      
      if (!this.hasRequirement(domainReqs, aspect)) {
        if (!gaps[domain]) gaps[domain] = [];
        gaps[domain].push({
          item: aspect,
          priority: 'high',
          description: this.getGapDescription(domain, aspect),
          type: 'recommended'
        });
      }
    }
    
    // Check completeness criteria for each domain
    for (const [domain, domainReqs] of requirements.entries()) {
      const criteria = this.rules.completeness_criteria[`${domain}.${this.getDomainMainAspect(domain)}`];
      
      if (criteria) {
        const domainGaps = this.checkCompleteness(domainReqs, criteria);
        if (domainGaps.length > 0) {
          if (!gaps[domain]) gaps[domain] = [];
          gaps[domain].push(...domainGaps);
        }
      }
    }
    
    logger.debug('Detected gaps', { 
      projectType,
      gapCount: Object.values(gaps).flat().length 
    });
    
    return gaps;
  }

  /**
   * Check if requirements contain a specific aspect
   * @param {array} requirements - Domain requirements
   * @param {string} aspect - Aspect to check
   * @returns {boolean} - Whether aspect is covered
   */
  hasRequirement(requirements, aspect) {
    if (!requirements || requirements.length === 0) return false;
    
    const aspectLower = aspect.toLowerCase().replace(/_/g, ' ');
    
    return requirements.some(req => {
      const reqText = (req.value || req.text || '').toLowerCase();
      return reqText.includes(aspectLower) || req.type === aspect;
    });
  }

  /**
   * Get main aspect for a domain
   * @param {string} domain - Domain name
   * @returns {string} - Main aspect
   */
  getDomainMainAspect(domain) {
    const mainAspects = {
      database: 'schema',
      api: 'endpoints',
      ui_ux: 'screens',
      auth: 'strategy',
      performance: 'targets',
      deployment: 'environment',
      testing: 'strategy'
    };
    
    return mainAspects[domain] || 'general';
  }

  /**
   * Check completeness against criteria
   * @param {array} requirements - Domain requirements
   * @param {object} criteria - Completeness criteria
   * @returns {array} - Gaps found
   */
  checkCompleteness(requirements, criteria) {
    const gaps = [];
    
    if (!criteria) return gaps;
    
    // Check must-have items
    if (criteria.must_have) {
      for (const item of criteria.must_have) {
        if (!this.hasRequirement(requirements, item)) {
          gaps.push({
            item,
            priority: 'high',
            description: `Missing critical requirement: ${item}`,
            type: 'must_have'
          });
        }
      }
    }
    
    // Check should-have items
    if (criteria.should_have) {
      for (const item of criteria.should_have) {
        if (!this.hasRequirement(requirements, item)) {
          gaps.push({
            item,
            priority: 'medium',
            description: `Recommended requirement missing: ${item}`,
            type: 'should_have'
          });
        }
      }
    }
    
    return gaps;
  }

  /**
   * Get human-readable description for a gap
   * @param {string} domain - Domain name
   * @param {string} aspect - Aspect name
   * @returns {string} - Description
   */
  getGapDescription(domain, aspect) {
    const descriptions = {
      database: {
        schema: 'Define database tables, fields, and relationships',
        indexes: 'Specify database indexes for performance',
        migrations: 'Plan database migration strategy',
        constraints: 'Define data constraints and validation rules'
      },
      api: {
        endpoints: 'Specify REST API endpoints and methods',
        authentication: 'Define API authentication mechanism',
        documentation: 'Plan API documentation approach',
        validation: 'Specify request/response validation rules'
      },
      ui_ux: {
        screens: 'List all application screens and views',
        navigation: 'Define navigation flow between screens',
        responsive: 'Specify responsive design requirements',
        interactions: 'Define user interaction patterns'
      },
      auth: {
        strategy: 'Choose authentication strategy (JWT, OAuth, etc.)',
        roles: 'Define user roles and permissions',
        sessions: 'Specify session management approach',
        security: 'Define security measures and policies'
      },
      performance: {
        targets: 'Set performance targets (response time, throughput)',
        caching: 'Define caching strategy',
        optimization: 'Plan optimization approaches',
        scalability: 'Define scalability requirements'
      },
      deployment: {
        environment: 'Specify deployment environment (AWS, Azure, etc.)',
        ci_cd: 'Define CI/CD pipeline',
        monitoring: 'Plan monitoring and alerting',
        infrastructure: 'Define infrastructure requirements'
      },
      testing: {
        strategy: 'Define overall testing strategy',
        coverage: 'Set test coverage targets',
        automation: 'Plan test automation approach',
        types: 'Specify types of testing needed'
      }
    };
    
    const domainDesc = descriptions[domain] || {};
    return domainDesc[aspect] || `Define ${aspect} for ${domain}`;
  }

  /**
   * Generate recommendations based on gaps
   * @param {object} gaps - Detected gaps
   * @param {string} projectType - Project type
   * @returns {array} - Recommendations
   */
  generateRecommendations(gaps, projectType) {
    const recommendations = [];
    
    // Priority 1: Critical gaps
    const criticalGaps = [];
    for (const [domain, domainGaps] of Object.entries(gaps)) {
      const critical = domainGaps.filter(g => g.priority === 'critical');
      if (critical.length > 0) {
        criticalGaps.push({ domain, gaps: critical });
      }
    }
    
    if (criticalGaps.length > 0) {
      recommendations.push({
        priority: 'critical',
        title: 'Address Critical Requirements',
        items: criticalGaps.map(dg => ({
          domain: dg.domain,
          action: `Define ${dg.gaps.map(g => g.item).join(', ')} for ${dg.domain}`,
          impact: 'Blocking - Required for project success'
        }))
      });
    }
    
    // Priority 2: High priority gaps
    const highGaps = [];
    for (const [domain, domainGaps] of Object.entries(gaps)) {
      const high = domainGaps.filter(g => g.priority === 'high');
      if (high.length > 0) {
        highGaps.push({ domain, gaps: high });
      }
    }
    
    if (highGaps.length > 0) {
      recommendations.push({
        priority: 'high',
        title: 'Recommended Requirements',
        items: highGaps.map(dg => ({
          domain: dg.domain,
          action: `Consider adding ${dg.gaps.map(g => g.item).join(', ')}`,
          impact: 'Important for production readiness'
        }))
      });
    }
    
    // Priority 3: Project-specific recommendations
    const projectRecommendations = this.getProjectSpecificRecommendations(projectType, gaps);
    if (projectRecommendations.length > 0) {
      recommendations.push({
        priority: 'medium',
        title: 'Project-Specific Suggestions',
        items: projectRecommendations
      });
    }
    
    return recommendations;
  }

  /**
   * Get project-specific recommendations
   * @param {string} projectType - Project type
   * @param {object} gaps - Current gaps
   * @returns {array} - Recommendations
   */
  getProjectSpecificRecommendations(projectType, gaps) {
    const recommendations = [];
    
    switch (projectType) {
      case 'web-app':
        if (!gaps.performance) {
          recommendations.push({
            action: 'Consider defining performance budgets',
            impact: 'Ensures good user experience'
          });
        }
        if (!gaps.ui_ux || !gaps.ui_ux.find(g => g.item === 'responsive')) {
          recommendations.push({
            action: 'Plan responsive design for mobile devices',
            impact: 'Reaches wider audience'
          });
        }
        break;
        
      case 'mobile-app':
        recommendations.push({
          action: 'Define offline functionality requirements',
          impact: 'Critical for mobile user experience'
        });
        recommendations.push({
          action: 'Plan push notification strategy',
          impact: 'Improves user engagement'
        });
        break;
        
      case 'api-service':
        recommendations.push({
          action: 'Define rate limiting strategy',
          impact: 'Prevents API abuse'
        });
        recommendations.push({
          action: 'Plan API versioning approach',
          impact: 'Enables backward compatibility'
        });
        break;
        
      case 'cli-tool':
        recommendations.push({
          action: 'Define command structure and arguments',
          impact: 'Ensures intuitive CLI interface'
        });
        recommendations.push({
          action: 'Plan help documentation system',
          impact: 'Improves user adoption'
        });
        break;
    }
    
    return recommendations;
  }

  /**
   * Generate actionable checklist from gaps
   * @param {object} gaps - Detected gaps
   * @returns {array} - Checklist items
   */
  generateChecklist(gaps) {
    const checklist = [];
    let id = 1;
    
    // Sort by priority
    const priorityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
    
    for (const [domain, domainGaps] of Object.entries(gaps)) {
      const sortedGaps = domainGaps.sort((a, b) => 
        priorityOrder[a.priority] - priorityOrder[b.priority]
      );
      
      for (const gap of sortedGaps) {
        checklist.push({
          id: id++,
          domain,
          task: gap.description,
          priority: gap.priority,
          completed: false,
          notes: '',
          estimatedTime: this.estimateTime(gap)
        });
      }
    }
    
    return checklist;
  }

  /**
   * Estimate time for addressing a gap
   * @param {object} gap - Gap object
   * @returns {string} - Time estimate
   */
  estimateTime(gap) {
    const estimates = {
      critical: '1-2 hours',
      high: '30-60 minutes',
      medium: '15-30 minutes',
      low: '5-15 minutes'
    };
    
    return estimates[gap.priority] || '30 minutes';
  }
}

// Export singleton instance
export const gapDetector = new GapDetector();