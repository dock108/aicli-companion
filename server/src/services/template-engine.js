/**
 * Template Engine Service
 * Handles template processing, variable substitution, and versioning
 */

import { promises as fs } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { createLogger } from '../utils/logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const logger = createLogger('TemplateEngine');

export class TemplateEngine {
  constructor() {
    // Base template directory
    this.templateDir = path.join(__dirname, '../../templates');

    // Template variables with defaults
    this.defaultVariables = {
      project_name: 'My Project',
      project_description: 'A new project',
      project_type: 'web-app',
      tech_stack: 'Node.js',
      team_size: 'small',
      author: 'Development Team',
      year: new Date().getFullYear(),
      date: new Date().toISOString().split('T')[0],
      version: '0.1.0',
    };

    // Template extensions that should be processed
    this.processableExtensions = new Set([
      '.md',
      '.txt',
      '.json',
      '.yml',
      '.yaml',
      '.js',
      '.ts',
      '.html',
      '.css',
    ]);
  }

  /**
   * Load a template file
   * @param {string} templatePath - Path to the template file
   * @returns {Promise<string>} - Template content
   */
  async loadTemplate(templatePath) {
    try {
      const fullPath = path.join(this.templateDir, templatePath);
      const content = await fs.readFile(fullPath, 'utf-8');
      return content;
    } catch (error) {
      logger.error('Failed to load template', { templatePath, error: error.message });
      throw new Error(`Template not found: ${templatePath}`);
    }
  }

  /**
   * Process a template with variable substitution
   * @param {string} template - Template content
   * @param {object} variables - Variables to substitute
   * @returns {string} - Processed template
   */
  processTemplate(template, variables = {}) {
    // Merge with defaults
    const mergedVariables = { ...this.defaultVariables, ...variables };

    // Replace {{variable}} patterns
    let processed = template;
    for (const [key, value] of Object.entries(mergedVariables)) {
      const pattern = new RegExp(`{{\\s*${key}\\s*}}`, 'g');
      processed = processed.replace(pattern, value);
    }

    // Process conditional sections {{#if variable}}...{{/if}}
    processed = this.processConditionals(processed, mergedVariables);

    // Process loops {{#each items}}...{{/each}}
    processed = this.processLoops(processed, mergedVariables);

    return processed;
  }

  /**
   * Process conditional sections in template
   * @param {string} template - Template content
   * @param {object} variables - Variables for evaluation
   * @returns {string} - Processed template
   */
  processConditionals(template, variables) {
    const ifPattern = /{{#if\s+(\w+)}}([\s\S]*?){{\/if}}/g;

    return template.replace(ifPattern, (match, varName, content) => {
      const value = variables[varName];
      if (value && value !== 'false' && value !== '0') {
        return content;
      }
      return '';
    });
  }

  /**
   * Process loop sections in template
   * @param {string} template - Template content
   * @param {object} variables - Variables containing arrays
   * @returns {string} - Processed template
   */
  processLoops(template, variables) {
    const eachPattern = /{{#each\s+(\w+)}}([\s\S]*?){{\/each}}/g;

    return template.replace(eachPattern, (match, varName, content) => {
      const items = variables[varName];
      if (Array.isArray(items)) {
        return items
          .map((item) => {
            let processedContent = content;
            if (typeof item === 'object') {
              // Replace {{this.property}} with item properties
              for (const [key, value] of Object.entries(item)) {
                const pattern = new RegExp(`{{\\s*this\\.${key}\\s*}}`, 'g');
                processedContent = processedContent.replace(pattern, value);
              }
            } else {
              // Replace {{this}} with item value
              processedContent = processedContent.replace(/{{\\s*this\\s*}}/g, item);
            }
            return processedContent;
          })
          .join('');
      }
      return '';
    });
  }

  /**
   * Generate project templates
   * @param {object} config - Project configuration
   * @returns {Promise<object>} - Generated templates
   */
  async generateProjectTemplates(config) {
    const templates = {};

    // Base templates that every project gets
    const baseTemplates = ['base/CLAUDE.md', 'base/plan.md', 'base/README.md'];

    // Project-type specific templates
    const typeTemplates = this.getProjectTypeTemplates(config.project_type);

    // Generate all templates
    for (const templatePath of [...baseTemplates, ...typeTemplates]) {
      try {
        const template = await this.loadTemplate(templatePath);
        const processed = this.processTemplate(template, config);

        // Extract filename from path
        const filename =
          path.basename(templatePath, path.extname(templatePath)) +
          (path.extname(templatePath) === '.md' ? '.md' : '');

        templates[filename] = processed;
      } catch (error) {
        logger.warn('Failed to generate template', { templatePath, error: error.message });
      }
    }

    // Add issue template directory
    templates['issues/template.md'] = await this.generateIssueTemplate(config);

    return templates;
  }

  /**
   * Get project-type specific templates
   * @param {string} projectType - Type of project
   * @returns {array} - Template paths
   */
  getProjectTypeTemplates(projectType) {
    const templates = {
      'web-app': [
        'project-types/web-app/package.json',
        'project-types/web-app/.gitignore',
        'project-types/web-app/.env.example',
      ],
      'mobile-app': ['project-types/mobile-app/README.md', 'project-types/mobile-app/.gitignore'],
      'api-service': [
        'project-types/api-service/package.json',
        'project-types/api-service/.gitignore',
        'project-types/api-service/Dockerfile',
      ],
      'cli-tool': ['project-types/cli-tool/package.json', 'project-types/cli-tool/bin/cli.js'],
    };

    return templates[projectType] || [];
  }

  /**
   * Generate issue template
   * @param {object} config - Project configuration
   * @returns {Promise<string>} - Issue template content
   */
  async generateIssueTemplate(config) {
    const template = `# Issue #[NUMBER]: [TITLE]

**Priority**: [High/Medium/Low]
**Component**: [Component Name]
**Discovered**: {{date}}
**Status**: New

## Problem Description
[Describe the issue or feature request]

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Steps to Reproduce
1. [First step]
2. [Second step]
3. [Third step]

## Technical Details
- **Project**: {{project_name}}
- **Version**: {{version}}
- **Environment**: {{tech_stack}}

## Proposed Solution
[If applicable, describe potential solution]

## Testing Requirements
- [ ] Unit tests
- [ ] Integration tests
- [ ] Manual testing

---
**Last Updated**: {{date}}
**Assigned To**: [Unassigned]
`;

    return this.processTemplate(template, config);
  }

  /**
   * Version a template
   * @param {string} version - Version string (e.g., "1.0.0")
   * @param {object} templates - Template content
   * @returns {object} - Versioned templates
   */
  versionTemplates(version, templates) {
    const versioned = {};

    for (const [filename, content] of Object.entries(templates)) {
      // Add version header to markdown files
      if (filename.endsWith('.md')) {
        versioned[filename] = `<!-- Template Version: ${version} -->\n${content}`;
      } else {
        versioned[filename] = content;
      }
    }

    return versioned;
  }

  /**
   * List available templates
   * @returns {Promise<object>} - Available templates by category
   */
  async listAvailableTemplates() {
    const templates = {
      base: [],
      projectTypes: [],
      issues: [],
      workflows: [],
    };

    try {
      // List base templates
      const baseDir = path.join(this.templateDir, 'base');
      try {
        const baseFiles = await fs.readdir(baseDir);
        templates.base = baseFiles.filter((f) => !f.startsWith('.'));
      } catch (err) {
        logger.debug('Base templates directory not found');
      }

      // List project type templates
      const typesDir = path.join(this.templateDir, 'project-types');
      try {
        const types = await fs.readdir(typesDir, { withFileTypes: true });
        templates.projectTypes = types.filter((d) => d.isDirectory()).map((d) => d.name);
      } catch (err) {
        logger.debug('Project types directory not found');
      }

      // List issue templates
      const issuesDir = path.join(this.templateDir, 'issues');
      try {
        const issueFiles = await fs.readdir(issuesDir);
        templates.issues = issueFiles.filter((f) => !f.startsWith('.'));
      } catch (err) {
        logger.debug('Issues templates directory not found');
      }

      // List workflow templates
      const workflowsDir = path.join(this.templateDir, 'workflows');
      try {
        const workflowFiles = await fs.readdir(workflowsDir);
        templates.workflows = workflowFiles.filter((f) => !f.startsWith('.'));
      } catch (err) {
        logger.debug('Workflows directory not found');
      }
    } catch (error) {
      logger.error('Failed to list templates', { error: error.message });
    }

    return templates;
  }

  /**
   * Create custom template from existing project
   * @param {string} projectPath - Path to existing project
   * @param {string} templateName - Name for the new template
   * @returns {Promise<void>}
   */
  async createCustomTemplate(projectPath, templateName) {
    // Sanitize template name to prevent path traversal
    const safeTemplateName = path.basename(templateName);
    const customDir = path.resolve(this.templateDir, 'custom', safeTemplateName);

    // Ensure custom directory is within template directory
    if (!customDir.startsWith(path.resolve(this.templateDir))) {
      throw new Error('Invalid template path');
    }

    try {
      // Create custom template directory
      await fs.mkdir(customDir, { recursive: true });

      // Copy key files from project
      const filesToCopy = ['CLAUDE.md', 'plan.md', 'README.md', 'package.json', '.gitignore'];

      for (const file of filesToCopy) {
        // Sanitize file paths
        const safeFile = path.basename(file);
        const sourcePath = path.resolve(projectPath, safeFile);
        const destPath = path.resolve(customDir, safeFile);

        try {
          const content = await fs.readFile(sourcePath, 'utf-8');
          // Replace project-specific values with variables
          const templated = content
            .replace(new RegExp(path.basename(projectPath), 'g'), '{{project_name}}')
            .replace(/\d{4}-\d{2}-\d{2}/g, '{{date}}')
            .replace(/\d+\.\d+\.\d+/g, '{{version}}');

          await fs.writeFile(destPath, templated);
        } catch (err) {
          logger.debug(`File ${file} not found in project, skipping`);
        }
      }

      logger.info('Created custom template', { templateName, projectPath });
    } catch (error) {
      logger.error('Failed to create custom template', { error: error.message });
      throw error;
    }
  }
}

// Export singleton instance
export const templateEngine = new TemplateEngine();
