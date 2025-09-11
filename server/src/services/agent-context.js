/**
 * Agent Context Service
 * Manages conversation context, state, and project-specific rules
 */

import { promises as fs } from 'fs';
import path from 'path';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('AgentContext');

export class AgentContext {
  constructor() {
    // Context storage by session
    this.contexts = new Map(); // sessionId -> context

    // CLAUDE.md rules cache
    this.claudeMdCache = new Map(); // projectPath -> rules

    // Task tracking
    this.taskQueues = new Map(); // sessionId -> task queue
  }

  /**
   * Initialize context for a session
   * @param {string} sessionId - Session identifier
   * @param {Object} initialContext - Initial context data
   */
  initializeContext(sessionId, initialContext = {}) {
    const context = {
      sessionId,
      createdAt: Date.now(),
      lastUpdated: Date.now(),

      // Project information
      projectPath: initialContext.projectPath || null,
      projectName: initialContext.projectName || null,
      projectType: initialContext.projectType || null,

      // Current state
      currentTask: initialContext.currentTask || null,
      currentPhase: initialContext.currentPhase || 'implementation',

      // Task tracking
      completedTasks: [],
      pendingTasks: [],
      failedTasks: [],

      // Conversation tracking
      topics: [],
      decisions: [],
      blockers: [],

      // Performance metrics
      successRate: 1.0,
      errorCount: 0,
      iterationCount: 0,

      // Custom data
      customData: initialContext.customData || {},
    };

    this.contexts.set(sessionId, context);
    logger.info('Initialized agent context', { sessionId, projectPath: context.projectPath });

    return context;
  }

  /**
   * Update context for a session
   * @param {string} sessionId - Session identifier
   * @param {Object} updates - Context updates
   */
  updateContext(sessionId, updates) {
    let context = this.contexts.get(sessionId);

    if (!context) {
      context = this.initializeContext(sessionId);
    }

    // Update context
    Object.assign(context, updates);
    context.lastUpdated = Date.now();

    // Track specific updates
    if (updates.currentTask && updates.currentTask !== context.currentTask) {
      this.trackTaskChange(context, updates.currentTask);
    }

    if (updates.error) {
      context.errorCount++;
      this.updateSuccessRate(context);
    }

    if (updates.completion) {
      this.trackTaskCompletion(context, updates.completion);
    }

    return context;
  }

  /**
   * Track task change
   * @private
   */
  trackTaskChange(context, newTask) {
    if (context.currentTask) {
      // Move current task to appropriate list
      if (
        !context.completedTasks.includes(context.currentTask) &&
        !context.failedTasks.includes(context.currentTask)
      ) {
        context.pendingTasks.push(context.currentTask);
      }
    }

    logger.info('Task changed', {
      sessionId: context.sessionId,
      from: context.currentTask,
      to: newTask,
    });
  }

  /**
   * Track task completion
   * @private
   */
  trackTaskCompletion(context, completion) {
    const task = context.currentTask || 'Unknown task';

    if (completion.success) {
      context.completedTasks.push({
        task,
        completedAt: Date.now(),
        iterations: context.iterationCount,
      });

      // Remove from pending if exists
      context.pendingTasks = context.pendingTasks.filter((t) => t !== task);
    } else {
      context.failedTasks.push({
        task,
        failedAt: Date.now(),
        reason: completion.reason || 'Unknown reason',
      });
    }

    this.updateSuccessRate(context);
  }

  /**
   * Update success rate
   * @private
   */
  updateSuccessRate(context) {
    const total = context.completedTasks.length + context.failedTasks.length;
    if (total > 0) {
      context.successRate = context.completedTasks.length / total;
    }
  }

  /**
   * Load CLAUDE.md rules for a project
   * @param {string} projectPath - Project path
   * @returns {Object} Parsed rules
   */
  async loadClaudeMdRules(projectPath) {
    // Check cache first
    if (this.claudeMdCache.has(projectPath)) {
      return this.claudeMdCache.get(projectPath);
    }

    try {
      const claudeMdPath = path.join(projectPath, 'CLAUDE.md');
      const content = await fs.readFile(claudeMdPath, 'utf-8');

      const rules = this.parseClaudeMdRules(content);
      this.claudeMdCache.set(projectPath, rules);

      logger.info('Loaded CLAUDE.md rules', {
        projectPath,
        ruleCount: rules.autoResponseRules?.length || 0,
      });

      return rules;
    } catch (error) {
      logger.warn('Failed to load CLAUDE.md', { projectPath, error: error.message });
      return null;
    }
  }

  /**
   * Parse CLAUDE.md content into rules
   * @private
   */
  parseClaudeMdRules(content) {
    const rules = {
      autoResponseRules: [],
      taskRules: [],
      escalationRules: [],
      customPatterns: [],
    };

    // Parse auto-response rules (simplified parser)
    const autoResponseSection = this.extractSection(content, 'AUTO-RESPONSE RULES');
    if (autoResponseSection) {
      rules.autoResponseRules = this.parseAutoResponseRules(autoResponseSection);
    }

    // Parse task rules
    const taskSection = this.extractSection(content, 'TASK RULES');
    if (taskSection) {
      rules.taskRules = this.parseTaskRules(taskSection);
    }

    // Parse escalation rules
    const escalationSection = this.extractSection(content, 'ESCALATION RULES');
    if (escalationSection) {
      rules.escalationRules = this.parseEscalationRules(escalationSection);
    }

    return rules;
  }

  /**
   * Extract a section from markdown content
   * @private
   */
  extractSection(content, sectionName) {
    const regex = new RegExp(`#+ ${sectionName}([^#]*)`, 'i');
    const match = content.match(regex);
    return match ? match[1].trim() : null;
  }

  /**
   * Parse auto-response rules
   * @private
   */
  parseAutoResponseRules(section) {
    const rules = [];
    const lines = section.split('\n');

    // const currentRule = null; // Removed unused variable
    for (const line of lines) {
      // Simple rule format: - PATTERN: RESPONSE
      const ruleMatch = line.match(/^[-*]\s*(.+?):\s*(.+)$/);
      if (ruleMatch) {
        rules.push({
          name: `rule_${rules.length + 1}`,
          pattern: ruleMatch[1].trim(),
          response: ruleMatch[2].trim(),
          confidence: 0.9,
        });
      }
    }

    return rules;
  }

  /**
   * Parse task rules
   * @private
   */
  parseTaskRules(section) {
    const rules = [];
    const taskBlocks = section.split(/(?=^### )/m);

    for (const block of taskBlocks) {
      const nameMatch = block.match(/^### (.+)$/m);
      if (nameMatch) {
        rules.push({
          name: nameMatch[1].trim(),
          content: block,
        });
      }
    }

    return rules;
  }

  /**
   * Parse escalation rules
   * @private
   */
  parseEscalationRules(section) {
    const rules = [];
    const lines = section.split('\n');

    for (const line of lines) {
      if (line.trim().startsWith('-') || line.trim().startsWith('*')) {
        rules.push({
          condition: line.replace(/^[-*]\s*/, '').trim(),
          escalate: true,
        });
      }
    }

    return rules;
  }

  /**
   * Get context for a session
   * @param {string} sessionId - Session identifier
   * @returns {Object} Session context
   */
  getContext(sessionId) {
    return this.contexts.get(sessionId) || null;
  }

  /**
   * Get task queue for a session
   * @param {string} sessionId - Session identifier
   * @returns {Array} Task queue
   */
  getTaskQueue(sessionId) {
    const context = this.contexts.get(sessionId);
    return context ? context.pendingTasks : [];
  }

  /**
   * Add task to queue
   * @param {string} sessionId - Session identifier
   * @param {string} task - Task description
   */
  addTask(sessionId, task) {
    const context = this.contexts.get(sessionId);
    if (context) {
      context.pendingTasks.push(task);
      logger.info('Added task to queue', {
        sessionId,
        task,
        queueLength: context.pendingTasks.length,
      });
    }
  }

  /**
   * Get next task from queue
   * @param {string} sessionId - Session identifier
   * @returns {string} Next task or null
   */
  getNextTask(sessionId) {
    const context = this.contexts.get(sessionId);
    if (context && context.pendingTasks.length > 0) {
      const nextTask = context.pendingTasks.shift();
      context.currentTask = nextTask;
      return nextTask;
    }
    return null;
  }

  /**
   * Record a decision made during conversation
   * @param {string} sessionId - Session identifier
   * @param {Object} decision - Decision details
   */
  recordDecision(sessionId, decision) {
    const context = this.contexts.get(sessionId);
    if (context) {
      context.decisions.push({
        ...decision,
        timestamp: Date.now(),
      });
    }
  }

  /**
   * Record a blocker encountered
   * @param {string} sessionId - Session identifier
   * @param {Object} blocker - Blocker details
   */
  recordBlocker(sessionId, blocker) {
    const context = this.contexts.get(sessionId);
    if (context) {
      context.blockers.push({
        ...blocker,
        timestamp: Date.now(),
        resolved: false,
      });
    }
  }

  /**
   * Get session summary
   * @param {string} sessionId - Session identifier
   * @returns {Object} Summary of session context
   */
  getSessionSummary(sessionId) {
    const context = this.contexts.get(sessionId);
    if (!context) return null;

    return {
      sessionId,
      projectName: context.projectName,
      currentTask: context.currentTask,
      currentPhase: context.currentPhase,
      progress: {
        completed: context.completedTasks.length,
        pending: context.pendingTasks.length,
        failed: context.failedTasks.length,
        successRate: context.successRate,
      },
      metrics: {
        errorCount: context.errorCount,
        iterationCount: context.iterationCount,
        duration: Date.now() - context.createdAt,
      },
      blockers: context.blockers.filter((b) => !b.resolved),
      recentDecisions: context.decisions.slice(-5),
    };
  }

  /**
   * Clear context for a session
   * @param {string} sessionId - Session identifier
   */
  clearContext(sessionId) {
    this.contexts.delete(sessionId);
    this.taskQueues.delete(sessionId);
    logger.info('Cleared agent context', { sessionId });
  }

  /**
   * Export context for persistence
   * @param {string} sessionId - Session identifier
   * @returns {Object} Exportable context
   */
  exportContext(sessionId) {
    const context = this.contexts.get(sessionId);
    if (!context) return null;

    return {
      ...context,
      exported: true,
      exportedAt: Date.now(),
    };
  }

  /**
   * Import context from persistence
   * @param {Object} contextData - Context data to import
   */
  importContext(contextData) {
    if (contextData && contextData.sessionId) {
      this.contexts.set(contextData.sessionId, {
        ...contextData,
        imported: true,
        importedAt: Date.now(),
      });

      logger.info('Imported agent context', { sessionId: contextData.sessionId });
    }
  }
}

export default AgentContext;
