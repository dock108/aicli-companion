/**
 * Autonomous Agent Service
 * Orchestrates intelligent auto-response by analyzing messages and selecting responses
 */

import { createLogger } from '../utils/logger.js';
import { MessageAnalyzer } from './message-analyzer.js';
import { ResponseTemplates } from './response-templates.js';
import { AgentContext } from './agent-context.js';
import { AIResponseGenerator } from './ai-response-generator.js';
import { TrainingDataManager } from './training-data-manager.js';

const logger = createLogger('AutonomousAgent');

export class AutonomousAgent {
  constructor(options = {}) {
    this.messageAnalyzer = new MessageAnalyzer();
    this.responseTemplates = new ResponseTemplates();
    this.agentContext = new AgentContext();
    this.aiGenerator = new AIResponseGenerator(options);
    this.trainingManager = new TrainingDataManager(options);

    // Configuration
    this.config = {
      maxIterations: options.maxIterations || 10,
      minConfidence: options.minConfidence || 0.6,
      escalationThreshold: options.escalationThreshold || 0.8,
      stuckDetectionWindow: options.stuckDetectionWindow || 5,
      enableAutoResponse: options.enableAutoResponse !== false,
      enableShowstopperDetection: options.enableShowstopperDetection !== false,
      enableAIResponses: options.enableAIResponses !== false && this.aiGenerator.enabled,
      claudeMdPath: options.claudeMdPath || null,
    };

    // State tracking
    this.sessions = new Map(); // sessionId -> session state
  }

  /**
   * Initialize agent for a session
   * @param {string} sessionId - Session identifier
   * @param {Object} context - Initial context
   */
  initializeSession(sessionId, context = {}) {
    const session = {
      sessionId,
      startTime: Date.now(),
      iterations: 0,
      messageHistory: [],
      context: {
        projectPath: context.projectPath,
        projectName: context.projectName,
        currentTask: context.currentTask,
        claudeMdRules: null,
      },
      state: 'active',
      lastActivity: Date.now(),
    };

    this.sessions.set(sessionId, session);

    // Load CLAUDE.md rules if available
    if (this.config.claudeMdPath) {
      this.agentContext
        .loadClaudeMdRules(this.config.claudeMdPath)
        .then((rules) => {
          session.context.claudeMdRules = rules;
        })
        .catch((err) => {
          logger.warn('Failed to load CLAUDE.md rules', { error: err.message });
        });
    }

    logger.info('Initialized autonomous agent session', { sessionId, context });
    return session;
  }

  /**
   * Analyze Claude's output and determine response
   * @param {string} claudeOutput - Claude's message
   * @param {string} sessionId - Session identifier
   * @returns {Object} Analysis and response recommendation
   */
  async analyzeMessage(claudeOutput, sessionId) {
    let session = this.sessions.get(sessionId);

    if (!session) {
      session = this.initializeSession(sessionId);
    }

    // Update session
    session.lastActivity = Date.now();
    session.messageHistory.push({
      type: 'claude',
      message: claudeOutput,
      timestamp: Date.now(),
    });
    session.iterations++;

    // Perform analysis
    const recentHistory = session.messageHistory
      .slice(-this.config.stuckDetectionWindow)
      .filter((m) => m.type === 'claude')
      .map((m) => m.message);

    const analysis = this.messageAnalyzer.analyzeMessage(claudeOutput, recentHistory);

    // Store analysis in context
    this.agentContext.updateContext(sessionId, {
      lastAnalysis: analysis,
      iterationCount: session.iterations,
    });

    // Check for showstoppers
    if (this.config.enableShowstopperDetection && analysis.showstopper.isShowstopper) {
      return this.handleShowstopper(analysis, session);
    }

    // Check iteration limit
    if (session.iterations >= this.config.maxIterations) {
      return this.handleIterationLimit(session);
    }

    // Select response if auto-response enabled
    if (this.config.enableAutoResponse) {
      const response = await this.selectResponse(analysis, session);

      // Record the response
      session.messageHistory.push({
        type: 'agent',
        message: response.message,
        timestamp: Date.now(),
        confidence: response.confidence,
      });

      return {
        analysis,
        response,
        sessionState: this.getSessionState(session),
        shouldContinue: !response.isEscalation && response.confidence >= this.config.minConfidence,
      };
    }

    return {
      analysis,
      response: null,
      sessionState: this.getSessionState(session),
      shouldContinue: false,
    };
  }

  /**
   * Select appropriate response based on analysis
   * @param {Object} analysis - Message analysis
   * @param {Object} session - Session state
   * @returns {Object} Selected response
   */
  async selectResponse(analysis, session) {
    // Prepare context for response generation
    const responseContext = {
      projectName: session.context.projectName,
      currentTask: session.context.currentTask,
      iteration: session.iterations,
      variables: {
        task_name: session.context.currentTask || 'current task',
        project_name: session.context.projectName || 'project',
        iteration_count: session.iterations,
      },
    };

    // Check if we should apply CLAUDE.md rules first
    if (session.context.claudeMdRules) {
      const ruleBasedResponse = this.applyClaudeMdRules(analysis, session.context.claudeMdRules);
      if (ruleBasedResponse) {
        // Record successful rule application for training
        await this.recordResponseSelection(session, analysis, ruleBasedResponse, true);
        return ruleBasedResponse;
      }
    }

    // Try AI-generated response if enabled
    if (this.config.enableAIResponses) {
      const aiResponse = await this.generateAIResponse(analysis, session);
      if (aiResponse && aiResponse.confidence >= this.config.minConfidence) {
        logger.info('Using AI-generated response', {
          sessionId: session.sessionId,
          confidence: aiResponse.confidence,
          model: aiResponse.model,
        });

        // Record AI response for training
        await this.recordResponseSelection(session, analysis, aiResponse, true);
        return aiResponse;
      }
    }

    // Fall back to template-based response
    const templateResponse = this.responseTemplates.getResponse(analysis, responseContext);

    // Check confidence threshold
    if (templateResponse.confidence < this.config.minConfidence) {
      logger.warn('Low confidence response selected', {
        sessionId: session.sessionId,
        confidence: templateResponse.confidence,
        response: templateResponse.message,
      });
    }

    // Log selection
    logger.info('Response selected', {
      sessionId: session.sessionId,
      category: templateResponse.category,
      confidence: templateResponse.confidence,
      isEscalation: templateResponse.isEscalation,
      source: 'template',
    });

    return templateResponse;
  }

  /**
   * Generate AI response
   * @private
   */
  async generateAIResponse(analysis, session) {
    try {
      // Get the last Claude output
      const claudeMessages = session.messageHistory.filter((m) => m.type === 'claude').slice(-1);

      if (claudeMessages.length === 0) {
        return null;
      }

      const claudeOutput = claudeMessages[0].message;

      // Get relevant training examples
      const projectId = session.context.projectPath || 'default';
      const trainingExamples = this.trainingManager.getRelevantExamples(projectId, analysis, 3);

      // Build context for AI
      const aiContext = {
        claudeOutput,
        analysis,
        sessionHistory: session.messageHistory.slice(-5),
        projectContext: {
          projectName: session.context.projectName,
          currentTask: session.context.currentTask,
        },
        trainingExamples,
        claudeMdRules: session.context.claudeMdRules,
      };

      // Generate AI response
      const aiResponse = await this.aiGenerator.generateResponse(aiContext);

      return aiResponse;
    } catch (error) {
      logger.error('Failed to generate AI response', {
        sessionId: session.sessionId,
        error: error.message,
      });
      return null;
    }
  }

  /**
   * Record response selection for training
   * @private
   */
  async recordResponseSelection(session, analysis, response, accepted) {
    try {
      const projectId = session.context.projectPath || 'default';

      // Get Claude's output
      const claudeMessages = session.messageHistory.filter((m) => m.type === 'claude').slice(-1);

      if (claudeMessages.length === 0) {
        return;
      }

      await this.trainingManager.recordInteraction({
        projectId,
        sessionId: session.sessionId,
        claudeOutput: claudeMessages[0].message,
        analysis,
        response,
        accepted,
        confidence: response.confidence,
        context: {
          projectName: session.context.projectName,
          currentTask: session.context.currentTask,
          iterationCount: session.iterations,
        },
      });
    } catch (error) {
      logger.error('Failed to record training data', {
        sessionId: session.sessionId,
        error: error.message,
      });
    }
  }

  /**
   * Apply CLAUDE.md rules to response selection
   * @private
   */
  applyClaudeMdRules(analysis, rules) {
    if (!rules || !rules.autoResponseRules) {
      return null;
    }

    // Check for specific rule matches
    for (const rule of rules.autoResponseRules) {
      if (this.matchesRule(analysis, rule)) {
        return {
          message: rule.response,
          confidence: rule.confidence || 0.9,
          category: 'claude_md_rule',
          key: rule.name,
          isEscalation: rule.escalate || false,
          source: 'CLAUDE.md',
        };
      }
    }

    return null;
  }

  /**
   * Check if analysis matches a rule
   * @private
   */
  matchesRule(analysis, rule) {
    if (rule.intent && rule.intent !== analysis.intent.type) {
      return false;
    }

    if (rule.pattern) {
      const regex = new RegExp(rule.pattern, 'i');
      return regex.test(analysis.intent.match || '');
    }

    if (rule.condition) {
      // Evaluate custom condition (simplified)
      try {
        return eval(rule.condition);
      } catch (err) {
        logger.warn('Failed to evaluate rule condition', { rule: rule.name, error: err.message });
        return false;
      }
    }

    return false;
  }

  /**
   * Handle showstopper detection
   * @private
   */
  handleShowstopper(analysis, session) {
    logger.warn('Showstopper detected', {
      sessionId: session.sessionId,
      reasons: analysis.showstopper.reasons,
    });

    session.state = 'escalated';

    return {
      analysis,
      response: {
        message: '[ESCALATION] Critical issue requiring human intervention detected',
        confidence: 1.0,
        category: 'escalation',
        isEscalation: true,
        showstopperReasons: analysis.showstopper.reasons,
      },
      sessionState: this.getSessionState(session),
      shouldContinue: false,
      requiresUserIntervention: true,
    };
  }

  /**
   * Handle iteration limit reached
   * @private
   */
  handleIterationLimit(session) {
    logger.info('Iteration limit reached', {
      sessionId: session.sessionId,
      iterations: session.iterations,
    });

    session.state = 'paused';

    return {
      analysis: null,
      response: {
        message: `Reached maximum iterations (${this.config.maxIterations}). Pausing for review.`,
        confidence: 1.0,
        category: 'system',
        isEscalation: false,
      },
      sessionState: this.getSessionState(session),
      shouldContinue: false,
      reason: 'iteration_limit',
    };
  }

  /**
   * Get session state summary
   * @private
   */
  getSessionState(session) {
    return {
      sessionId: session.sessionId,
      state: session.state,
      iterations: session.iterations,
      duration: Date.now() - session.startTime,
      lastActivity: session.lastActivity,
      messageCount: session.messageHistory.length,
      context: {
        projectName: session.context.projectName,
        currentTask: session.context.currentTask,
      },
    };
  }

  /**
   * Detect if agent is stuck in a loop
   * @param {string} sessionId - Session identifier
   * @returns {boolean} True if stuck detected
   */
  detectStuckState(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) return false;

    const recentMessages = session.messageHistory
      .slice(-this.config.stuckDetectionWindow)
      .filter((m) => m.type === 'claude')
      .map((m) => m.message);

    if (recentMessages.length < 3) return false;

    const progress = this.messageAnalyzer.assessProgress(recentMessages);
    return !progress.isProgressing && progress.stuckIndicators.length > 0;
  }

  /**
   * Update session context
   * @param {string} sessionId - Session identifier
   * @param {Object} updates - Context updates
   */
  updateSessionContext(sessionId, updates) {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    Object.assign(session.context, updates);
    this.agentContext.updateContext(sessionId, updates);
  }

  /**
   * Get session summary
   * @param {string} sessionId - Session identifier
   * @returns {Object} Session summary
   */
  getSessionSummary(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) return null;

    const claudeMessages = session.messageHistory.filter((m) => m.type === 'claude');
    const agentMessages = session.messageHistory.filter((m) => m.type === 'agent');

    // Calculate average confidence
    const confidences = agentMessages.map((m) => m.confidence).filter((c) => c !== undefined);
    const avgConfidence =
      confidences.length > 0 ? confidences.reduce((a, b) => a + b, 0) / confidences.length : 0;

    return {
      sessionId,
      state: session.state,
      startTime: session.startTime,
      duration: Date.now() - session.startTime,
      iterations: session.iterations,
      messageStats: {
        total: session.messageHistory.length,
        claude: claudeMessages.length,
        agent: agentMessages.length,
      },
      averageConfidence: avgConfidence,
      context: session.context,
      isStuck: this.detectStuckState(sessionId),
    };
  }

  /**
   * Clear session
   * @param {string} sessionId - Session identifier
   */
  clearSession(sessionId) {
    this.sessions.delete(sessionId);
    this.agentContext.clearContext(sessionId);
    logger.info('Cleared autonomous agent session', { sessionId });
  }

  /**
   * Clean up old sessions
   * @param {number} maxAge - Maximum age in milliseconds
   */
  cleanupOldSessions(maxAge = 3600000) {
    // 1 hour default
    const now = Date.now();
    const toDelete = [];

    for (const [sessionId, session] of this.sessions) {
      if (now - session.lastActivity > maxAge) {
        toDelete.push(sessionId);
      }
    }

    for (const sessionId of toDelete) {
      this.clearSession(sessionId);
    }

    if (toDelete.length > 0) {
      logger.info('Cleaned up old sessions', { count: toDelete.length });
    }
  }
}

export default AutonomousAgent;
