/**
 * AI Response Generator Service
 * Generates intelligent auto-responses using OpenAI API
 */

import { createLogger } from '../utils/logger.js';
import fetch from 'node-fetch';

const logger = createLogger('AIResponseGenerator');

export class AIResponseGenerator {
  constructor(options = {}) {
    this.apiKey = options.apiKey || process.env.OPENAI_API_KEY;
    this.model = options.model || process.env.AI_MODEL || 'gpt-3.5-turbo';
    this.temperature = parseFloat(options.temperature || process.env.AI_TEMPERATURE || '0.7');
    this.maxTokens = parseInt(options.maxTokens || process.env.AI_MAX_TOKENS || '150');
    this.apiUrl = options.apiUrl || 'https://api.openai.com/v1/chat/completions';

    // Allow fetch to be overridden for testing
    this.fetch = options.fetch || fetch;

    // Rate limiting
    this.requestCount = 0;
    this.requestResetTime = Date.now() + 60000; // Reset every minute
    this.maxRequestsPerMinute = parseInt(process.env.AI_RATE_LIMIT || '20');

    // Response cache
    this.responseCache = new Map();
    this.cacheTimeout = 300000; // 5 minutes

    this.enabled = !!(this.apiKey && process.env.USE_AI_RESPONSES !== 'false');

    if (!this.enabled) {
      logger.warn('AI Response Generator disabled', {
        hasApiKey: !!this.apiKey,
        useAiResponses: process.env.USE_AI_RESPONSES,
      });
    }
  }

  /**
   * Generate an AI response based on context
   * @param {Object} context - Full context for response generation
   * @returns {Object} AI-generated response with confidence
   */
  async generateResponse(context) {
    if (!this.enabled) {
      return null;
    }

    try {
      // Check rate limit
      if (!this.checkRateLimit()) {
        logger.warn('Rate limit exceeded, falling back to templates');
        return null;
      }

      // Check cache
      const cacheKey = this.generateCacheKey(context);
      const cached = this.getCachedResponse(cacheKey);
      if (cached) {
        logger.info('Using cached AI response', { cacheKey });
        return cached;
      }

      // Build the prompt
      const prompt = this.buildPrompt(context);

      // Call OpenAI API
      const response = await this.callOpenAI(prompt);

      if (!response) {
        return null;
      }

      // Parse and structure the response
      const structuredResponse = this.structureResponse(response, context);

      // Cache the response
      this.cacheResponse(cacheKey, structuredResponse);

      return structuredResponse;
    } catch (error) {
      logger.error('Failed to generate AI response', {
        error: error.message,
        model: this.model,
      });
      return null;
    }
  }

  /**
   * Build a comprehensive prompt for the AI
   * @private
   */
  buildPrompt(context) {
    const {
      claudeOutput,
      analysis,
      sessionHistory = [],
      projectContext = {},
      trainingExamples = [],
      claudeMdRules = null,
    } = context;

    const systemPrompt = this.buildSystemPrompt(projectContext, claudeMdRules);
    const userPrompt = this.buildUserPrompt(
      claudeOutput,
      analysis,
      sessionHistory,
      trainingExamples
    );

    return [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ];
  }

  /**
   * Build the system prompt
   * @private
   */
  buildSystemPrompt(projectContext, claudeMdRules) {
    let prompt = `You are an AI assistant helping to guide Claude Code through software development tasks. 
Your role is to generate appropriate follow-up responses to keep Claude productive and on track.

Key Guidelines:
1. Be concise and action-oriented
2. Focus on moving the task forward
3. Detect when Claude needs clarification and provide it
4. Identify when Claude is stuck and suggest alternatives
5. Recognize completion and guide to next steps
6. Never give up - persist until the task is complete or genuinely blocked`;

    if (projectContext.projectName) {
      prompt += `\n\nProject: ${projectContext.projectName}`;
    }

    if (projectContext.currentTask) {
      prompt += `\nCurrent Task: ${projectContext.currentTask}`;
    }

    if (claudeMdRules) {
      prompt += `\n\nProject-Specific Rules:\n${this.summarizeRules(claudeMdRules)}`;
    }

    prompt += `\n\nIMPORTANT: Your response should be a single, clear instruction or clarification that Claude can act on immediately.`;

    return prompt;
  }

  /**
   * Build the user prompt
   * @private
   */
  buildUserPrompt(claudeOutput, analysis, sessionHistory, trainingExamples) {
    let prompt = `Claude's Latest Output:\n${this.truncateText(claudeOutput, 500)}\n\n`;

    prompt += `Analysis:\n`;
    prompt += `- Intent: ${analysis.intent.type} (confidence: ${analysis.intent.confidence})\n`;
    prompt += `- Completion: ${analysis.completion.isComplete ? 'Yes' : 'No'}`;
    if (analysis.completion.isComplete) {
      prompt += ` (${analysis.completion.success ? 'Successful' : 'Failed'})`;
    }
    prompt += `\n`;
    prompt += `- Progress: ${analysis.progress.isProgressing ? 'Progressing' : 'Stuck'}\n`;
    prompt += `- Recommendation: ${analysis.recommendation}\n`;

    if (analysis.showstopper.isShowstopper) {
      prompt += `- CRITICAL: ${analysis.showstopper.reasons.map((r) => r.reason).join(', ')}\n`;
    }

    // Add recent history context
    if (sessionHistory.length > 0) {
      const recentHistory = sessionHistory.slice(-3);
      prompt += `\nRecent Conversation:\n`;
      recentHistory.forEach((msg, idx) => {
        const preview = this.truncateText(msg.message, 100);
        prompt += `${idx + 1}. [${msg.type}]: ${preview}\n`;
      });
    }

    // Add training examples if available
    if (trainingExamples.length > 0) {
      prompt += `\nRelevant Examples:\n`;
      trainingExamples.slice(0, 2).forEach((example, idx) => {
        prompt += `Example ${idx + 1}:\n`;
        prompt += `Situation: ${example.situation}\n`;
        prompt += `Good Response: ${example.response}\n`;
      });
    }

    prompt += `\nBased on this context, generate an appropriate follow-up response for Claude.`;
    prompt += `\nConsider the analysis and provide a response that will help Claude continue productively.`;
    prompt += `\nResponse:`;

    return prompt;
  }

  /**
   * Call the OpenAI API
   * @private
   */
  async callOpenAI(messages) {
    try {
      const requestBody = {
        model: this.model,
        messages,
        temperature: this.temperature,
        max_tokens: this.maxTokens,
        n: 1,
        stop: null,
      };

      logger.info('Calling OpenAI API', {
        model: this.model,
        temperature: this.temperature,
        maxTokens: this.maxTokens,
      });

      const response = await this.fetch(this.apiUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify(requestBody),
      });

      if (!response.ok) {
        const error = await response.text();
        throw new Error(`OpenAI API error: ${response.status} - ${error}`);
      }

      const data = await response.json();

      this.requestCount++;

      if (!data.choices || data.choices.length === 0) {
        throw new Error('No response from OpenAI');
      }

      return data.choices[0].message.content;
    } catch (error) {
      logger.error('OpenAI API call failed', { error: error.message });
      throw error;
    }
  }

  /**
   * Structure the AI response
   * @private
   */
  structureResponse(aiResponse, context) {
    // Calculate confidence based on various factors
    let confidence = 0.7; // Base confidence for AI responses

    // Adjust confidence based on analysis
    if (context.analysis.intent.confidence > 0.8) {
      confidence += 0.1;
    }

    if (context.analysis.showstopper.isShowstopper) {
      confidence = 0.95; // High confidence for critical issues
    }

    if (context.sessionHistory && context.sessionHistory.length > 5) {
      confidence += 0.05; // More context = higher confidence
    }

    // Ensure confidence is within bounds
    confidence = Math.min(0.95, Math.max(0.5, confidence));

    return {
      message: aiResponse,
      confidence,
      category: 'ai_generated',
      key: 'dynamic',
      isEscalation: context.analysis.showstopper.isShowstopper,
      source: 'openai',
      model: this.model,
      metadata: {
        temperature: this.temperature,
        promptTokens: this.estimateTokens(context),
        generatedAt: new Date().toISOString(),
      },
    };
  }

  /**
   * Check rate limiting
   * @private
   */
  checkRateLimit() {
    const now = Date.now();

    // Reset counter if time window passed
    if (now > this.requestResetTime) {
      this.requestCount = 0;
      this.requestResetTime = now + 60000;
    }

    return this.requestCount < this.maxRequestsPerMinute;
  }

  /**
   * Generate cache key
   * @private
   */
  generateCacheKey(context) {
    const key = `${context.analysis.intent.type}_${context.analysis.recommendation}_${context.analysis.completion.isComplete}`;
    return key;
  }

  /**
   * Get cached response
   * @private
   */
  getCachedResponse(key) {
    const cached = this.responseCache.get(key);
    if (cached && Date.now() - cached.timestamp < this.cacheTimeout) {
      return cached.response;
    }
    return null;
  }

  /**
   * Cache a response
   * @private
   */
  cacheResponse(key, response) {
    this.responseCache.set(key, {
      response,
      timestamp: Date.now(),
    });

    // Clean old entries
    if (this.responseCache.size > 100) {
      const oldestKey = this.responseCache.keys().next().value;
      this.responseCache.delete(oldestKey);
    }
  }

  /**
   * Truncate text to specified length
   * @private
   */
  truncateText(text, maxLength) {
    if (!text || text.length <= maxLength) {
      return text;
    }
    return `${text.substring(0, maxLength)}...`;
  }

  /**
   * Summarize CLAUDE.md rules
   * @private
   */
  summarizeRules(rules) {
    if (!rules) return '';

    let summary = '';

    if (rules.corePrinciples) {
      summary += `Core Principles: ${rules.corePrinciples.slice(0, 3).join(', ')}\n`;
    }

    if (rules.autoResponseRules) {
      summary += `Auto-Response Rules: ${rules.autoResponseRules.length} rules defined\n`;
    }

    return summary || 'No specific rules defined';
  }

  /**
   * Estimate token count for prompt
   * @private
   */
  estimateTokens(context) {
    // Rough estimation: 1 token ≈ 4 characters
    const promptLength = JSON.stringify(context).length;
    return Math.ceil(promptLength / 4);
  }

  /**
   * Validate configuration
   * @returns {Object} Validation result
   */
  validateConfiguration() {
    const issues = [];

    if (!this.apiKey) {
      issues.push('OpenAI API key not configured');
    }

    if (!['gpt-4', 'gpt-3.5-turbo', 'gpt-4-turbo-preview'].includes(this.model)) {
      issues.push(`Unknown model: ${this.model}`);
    }

    if (this.temperature < 0 || this.temperature > 2) {
      issues.push(`Invalid temperature: ${this.temperature} (should be 0-2)`);
    }

    if (this.maxTokens < 1 || this.maxTokens > 4000) {
      issues.push(`Invalid max tokens: ${this.maxTokens} (should be 1-4000)`);
    }

    return {
      valid: issues.length === 0,
      issues,
      enabled: this.enabled,
    };
  }

  /**
   * Test API connectivity
   * @returns {boolean} True if API is accessible
   */
  async testConnection() {
    if (!this.enabled) {
      return false;
    }

    try {
      const testPrompt = [
        { role: 'system', content: 'You are a helpful assistant.' },
        { role: 'user', content: 'Reply with "OK" if you receive this.' },
      ];

      const response = await this.callOpenAI(testPrompt);
      return response && response.includes('OK');
    } catch (error) {
      logger.error('API connection test failed', { error: error.message });
      return false;
    }
  }
}

export default AIResponseGenerator;
