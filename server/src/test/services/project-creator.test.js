import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { promises as fs } from 'fs';
import { ProjectCreator } from '../../services/project-creator.js';

describe('ProjectCreator', () => {
  let projectCreator;
  let _mockFs;
  let mockTemplateEngine;
  let _mockLogger;
  let consoleLogSpy;
  let _consoleErrorSpy;
  let consoleWarnSpy;
  let _consoleDebugSpy;
  let originalFsAccess;
  let originalFsMkdir;
  let originalFsWriteFile;
  let originalFsReaddir;
  let originalFsReadFile;
  let originalFsRm;
  let originalFsRename;
  let originalFsRmdir;

  beforeEach(() => {
    // Mock console methods
    consoleLogSpy = mock.method(console, 'log', () => {});
    _consoleErrorSpy = mock.method(console, 'error', () => {});
    consoleWarnSpy = mock.method(console, 'warn', () => {});
    _consoleDebugSpy = mock.method(console, 'debug', () => {});

    // Save original fs methods
    originalFsAccess = fs.access;
    originalFsMkdir = fs.mkdir;
    originalFsWriteFile = fs.writeFile;
    originalFsReaddir = fs.readdir;
    originalFsReadFile = fs.readFile;
    originalFsRm = fs.rm;
    originalFsRename = fs.rename;
    originalFsRmdir = fs.rmdir;

    // Create instance
    projectCreator = new ProjectCreator();

    // Mock template engine
    mockTemplateEngine = {
      generateProjectTemplates: mock.fn(async (data) => ({
        'README.md': `# ${data.project_name}`,
        'package.json': JSON.stringify({ name: data.project_name }),
        '.gitignore': 'node_modules\n',
      })),
      versionTemplates: mock.fn((version, templates) => {
        const versioned = {};
        for (const [key, value] of Object.entries(templates)) {
          versioned[key] = `/* Version: ${version} */\n${value}`;
        }
        return versioned;
      }),
    };
  });

  afterEach(() => {
    // Restore fs methods
    fs.access = originalFsAccess;
    fs.mkdir = originalFsMkdir;
    fs.writeFile = originalFsWriteFile;
    fs.readdir = originalFsReaddir;
    fs.readFile = originalFsReadFile;
    fs.rm = originalFsRm;
    fs.rename = originalFsRename;
    fs.rmdir = originalFsRmdir;
  });

  describe('constructor', () => {
    it('should initialize with config and projects directory', () => {
      const instance = new ProjectCreator();
      assert(instance.config);
      assert(instance.projectsDir);
    });
  });

  describe('isValidProjectName', () => {
    it('should accept valid project names', () => {
      assert(projectCreator.isValidProjectName('my-project'));
      assert(projectCreator.isValidProjectName('MyProject'));
      assert(projectCreator.isValidProjectName('project_123'));
      assert(projectCreator.isValidProjectName('test-app_v2'));
    });

    it('should reject invalid project names', () => {
      assert(!projectCreator.isValidProjectName(''));
      assert(!projectCreator.isValidProjectName(null));
      assert(!projectCreator.isValidProjectName(undefined));
      assert(!projectCreator.isValidProjectName(123));
      assert(!projectCreator.isValidProjectName('my project')); // spaces
      assert(!projectCreator.isValidProjectName('my@project')); // special chars
      assert(!projectCreator.isValidProjectName('my.project')); // dots
      assert(!projectCreator.isValidProjectName('a'.repeat(101))); // too long
    });
  });

  describe('projectExists', () => {
    it('should return true if project exists', async () => {
      fs.access = mock.fn(async () => {
        // No error means file exists
      });

      const exists = await projectCreator.projectExists('/path/to/project');
      assert.strictEqual(exists, true);
    });

    it('should return false if project does not exist', async () => {
      fs.access = mock.fn(async () => {
        throw new Error('ENOENT');
      });

      const exists = await projectCreator.projectExists('/path/to/project');
      assert.strictEqual(exists, false);
    });
  });

  describe('createFolderStructure', () => {
    it('should create base folders for all project types', async () => {
      const mkdirCalls = [];
      fs.mkdir = mock.fn(async (path, _options) => {
        mkdirCalls.push(path);
      });

      await projectCreator.createFolderStructure('/project', 'web-app');

      // Check base folders were created
      assert(mkdirCalls.some((p) => p.includes('src')));
      assert(mkdirCalls.some((p) => p.includes('tests')));
      assert(mkdirCalls.some((p) => p.includes('docs')));
      assert(mkdirCalls.some((p) => p.includes('issues')));
      assert(mkdirCalls.some((p) => p.includes('.github/workflows')));
    });

    it('should create web-app specific folders', async () => {
      const mkdirCalls = [];
      fs.mkdir = mock.fn(async (path, _options) => {
        mkdirCalls.push(path);
      });

      await projectCreator.createFolderStructure('/project', 'web-app');

      assert(mkdirCalls.some((p) => p.includes('src/components')));
      assert(mkdirCalls.some((p) => p.includes('src/pages')));
      assert(mkdirCalls.some((p) => p.includes('src/styles')));
      assert(mkdirCalls.some((p) => p.includes('public')));
    });

    it('should create mobile-app specific folders', async () => {
      const mkdirCalls = [];
      fs.mkdir = mock.fn(async (path, _options) => {
        mkdirCalls.push(path);
      });

      await projectCreator.createFolderStructure('/project', 'mobile-app');

      assert(mkdirCalls.some((p) => p.includes('src/screens')));
      assert(mkdirCalls.some((p) => p.includes('src/navigation')));
      assert(mkdirCalls.some((p) => p.includes('assets')));
    });

    it('should create api-service specific folders', async () => {
      const mkdirCalls = [];
      fs.mkdir = mock.fn(async (path, _options) => {
        mkdirCalls.push(path);
      });

      await projectCreator.createFolderStructure('/project', 'api-service');

      assert(mkdirCalls.some((p) => p.includes('src/routes')));
      assert(mkdirCalls.some((p) => p.includes('src/controllers')));
      assert(mkdirCalls.some((p) => p.includes('src/models')));
      assert(mkdirCalls.some((p) => p.includes('src/middleware')));
    });

    it('should create cli-tool specific folders', async () => {
      const mkdirCalls = [];
      fs.mkdir = mock.fn(async (path, _options) => {
        mkdirCalls.push(path);
      });

      await projectCreator.createFolderStructure('/project', 'cli-tool');

      assert(mkdirCalls.some((p) => p.includes('src/commands')));
      assert(mkdirCalls.some((p) => p.includes('src/utils')));
      assert(mkdirCalls.some((p) => p.includes('bin')));
    });

    it('should handle unknown project type', async () => {
      const mkdirCalls = [];
      fs.mkdir = mock.fn(async (path, _options) => {
        mkdirCalls.push(path);
      });

      await projectCreator.createFolderStructure('/project', 'unknown-type');

      // Should still create base folders
      assert(mkdirCalls.some((p) => p.includes('src')));
      assert(mkdirCalls.some((p) => p.includes('tests')));
    });
  });

  describe('writeTemplates', () => {
    it('should write all template files', async () => {
      const writtenFiles = [];
      fs.mkdir = mock.fn(async () => {});
      fs.writeFile = mock.fn(async (path, content) => {
        writtenFiles.push({ path, content });
      });

      const templates = {
        'README.md': '# Test Project',
        'src/index.js': 'console.log("Hello");',
        'package.json': '{"name": "test"}',
      };

      await projectCreator.writeTemplates('/project', templates);

      assert.strictEqual(writtenFiles.length, 3);
      assert(writtenFiles.some((f) => f.path.includes('README.md')));
      assert(writtenFiles.some((f) => f.path.includes('src/index.js')));
      assert(writtenFiles.some((f) => f.content === '# Test Project'));
    });

    it('should create directories for nested files', async () => {
      const mkdirCalls = [];
      fs.mkdir = mock.fn(async (path) => {
        mkdirCalls.push(path);
      });
      fs.writeFile = mock.fn(async () => {});

      const templates = {
        'src/components/App.js': 'export default App;',
        'docs/README.md': '# Docs',
      };

      await projectCreator.writeTemplates('/project', templates);

      // Should create parent directories
      assert(mkdirCalls.some((p) => p.includes('src/components')));
      assert(mkdirCalls.some((p) => p.includes('docs')));
    });
  });

  describe('createProjectMetadata', () => {
    it('should create metadata file with correct structure', async () => {
      let _writtenMetadata = null;
      fs.mkdir = mock.fn(async () => {});
      fs.writeFile = mock.fn(async (path, content) => {
        if (path.includes('project.json')) {
          _writtenMetadata = JSON.parse(content);
        }
      });

      const config = {
        projectName: 'test-project',
        projectType: 'web-app',
        techStack: 'React',
        teamSize: 'medium',
        author: 'John Doe',
      };

      const metadata = await projectCreator.createProjectMetadata('/project', config);

      assert.strictEqual(metadata.name, 'test-project');
      assert.strictEqual(metadata.type, 'web-app');
      assert.strictEqual(metadata.techStack, 'React');
      assert.strictEqual(metadata.teamSize, 'medium');
      assert.strictEqual(metadata.author, 'John Doe');
      assert.strictEqual(metadata.version, '0.1.0');
      assert.strictEqual(metadata.status, 'planning');
      assert(metadata.createdAt);
      assert(metadata.templates);
      assert.strictEqual(metadata.templates.version, '0.1.0');
    });

    it('should create .aicli-companion directory', async () => {
      const mkdirCalls = [];
      fs.mkdir = mock.fn(async (path) => {
        mkdirCalls.push(path);
      });
      fs.writeFile = mock.fn(async () => {});

      await projectCreator.createProjectMetadata('/project', {
        projectName: 'test',
      });

      assert(mkdirCalls.some((p) => p.includes('.aicli-companion')));
    });
  });

  describe('createProject', () => {
    it('should reject invalid project name', async () => {
      await assert.rejects(
        async () => {
          await projectCreator.createProject({ projectName: 'invalid name!' });
        },
        {
          message: /Invalid project name/,
        }
      );
    });

    it('should reject if project already exists', async () => {
      fs.access = mock.fn(async () => {}); // Project exists

      await assert.rejects(
        async () => {
          await projectCreator.createProject({ projectName: 'existing-project' });
        },
        {
          message: /already exists/,
        }
      );
    });

    it('should create project with default values', async () => {
      // Mock all fs operations
      fs.access = mock.fn(async () => {
        throw new Error('Not found');
      });
      fs.mkdir = mock.fn(async () => {});
      fs.writeFile = mock.fn(async () => {});

      // Mock template engine on the projectCreator instance
      const { templateEngine } = await import('../../services/template-engine.js');
      templateEngine.generateProjectTemplates = mockTemplateEngine.generateProjectTemplates;
      templateEngine.versionTemplates = mockTemplateEngine.versionTemplates;

      const result = await projectCreator.createProject({
        projectName: 'new-project',
      });

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.projectName, 'new-project');
      assert(result.projectPath);
      assert(result.templates);
      assert(result.metadata);
      assert(result.message.includes('successfully'));
    });

    it('should create project with custom configuration', async () => {
      fs.access = mock.fn(async () => {
        throw new Error('Not found');
      });
      fs.mkdir = mock.fn(async () => {});
      fs.writeFile = mock.fn(async () => {});

      const { templateEngine } = await import('../../services/template-engine.js');
      templateEngine.generateProjectTemplates = mockTemplateEngine.generateProjectTemplates;
      templateEngine.versionTemplates = mockTemplateEngine.versionTemplates;

      const result = await projectCreator.createProject({
        projectName: 'custom-project',
        projectType: 'api-service',
        techStack: 'Express.js',
        teamSize: 'large',
        description: 'Custom API service',
        author: 'Jane Smith',
      });

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.projectName, 'custom-project');
    });

    it('should cleanup on failure', async () => {
      fs.access = mock.fn(async () => {
        throw new Error('Not found');
      });
      fs.mkdir = mock.fn(async () => {});

      // Make writeFile fail
      fs.writeFile = mock.fn(async () => {
        throw new Error('Write failed');
      });

      let rmdirCalled = false;
      fs.rmdir = mock.fn(async () => {
        rmdirCalled = true;
      });

      const { templateEngine } = await import('../../services/template-engine.js');
      templateEngine.generateProjectTemplates = mockTemplateEngine.generateProjectTemplates;
      templateEngine.versionTemplates = mockTemplateEngine.versionTemplates;

      await assert.rejects(
        async () => {
          await projectCreator.createProject({ projectName: 'fail-project' });
        },
        {
          message: /Write failed/,
        }
      );

      assert(rmdirCalled);
    });

    it('should handle git initialization when requested', async () => {
      fs.access = mock.fn(async () => {
        throw new Error('Not found');
      });
      fs.mkdir = mock.fn(async () => {});
      fs.writeFile = mock.fn(async () => {});

      // Mock exec for git commands
      const _mockExec = mock.fn(async (_command, _options) => {
        return { stdout: '', stderr: '' };
      });

      // Mock the dynamic imports
      const originalImport = projectCreator.initializeGit;
      projectCreator.initializeGit = async (projectPath) => {
        // Simulate git initialization
        consoleLogSpy({ message: 'Initialized git repository', projectPath });
      };

      const { templateEngine } = await import('../../services/template-engine.js');
      templateEngine.generateProjectTemplates = mockTemplateEngine.generateProjectTemplates;
      templateEngine.versionTemplates = mockTemplateEngine.versionTemplates;

      const result = await projectCreator.createProject({
        projectName: 'git-project',
        initGit: true,
      });

      assert.strictEqual(result.success, true);

      // Restore
      projectCreator.initializeGit = originalImport;
    });
  });

  describe('listProjects', () => {
    it('should list all projects with metadata', async () => {
      fs.readdir = mock.fn(async () => [
        { name: 'project1', isDirectory: () => true },
        { name: 'project2', isDirectory: () => true },
        { name: '.hidden', isDirectory: () => true },
        { name: 'file.txt', isDirectory: () => false },
      ]);

      fs.readFile = mock.fn(async (path) => {
        if (path.includes('project1')) {
          return JSON.stringify({
            name: 'project1',
            type: 'web-app',
            createdAt: '2024-01-01',
          });
        }
        throw new Error('No metadata');
      });

      const projects = await projectCreator.listProjects();

      assert.strictEqual(projects.length, 2);
      assert.strictEqual(projects[0].name, 'project1');
      assert.strictEqual(projects[0].type, 'web-app');
      assert.strictEqual(projects[1].name, 'project2');
      assert.strictEqual(projects[1].type, 'unknown');
    });

    it('should handle empty projects directory', async () => {
      fs.readdir = mock.fn(async () => []);

      const projects = await projectCreator.listProjects();

      assert.strictEqual(projects.length, 0);
    });

    it('should handle readdir errors', async () => {
      fs.readdir = mock.fn(async () => {
        throw new Error('Permission denied');
      });

      await assert.rejects(
        async () => {
          await projectCreator.listProjects();
        },
        {
          message: /Permission denied/,
        }
      );
    });

    it('should sort projects alphabetically', async () => {
      fs.readdir = mock.fn(async () => [
        { name: 'zebra', isDirectory: () => true },
        { name: 'alpha', isDirectory: () => true },
        { name: 'beta', isDirectory: () => true },
      ]);

      fs.readFile = mock.fn(async () => {
        throw new Error('No metadata');
      });

      const projects = await projectCreator.listProjects();

      assert.strictEqual(projects[0].name, 'alpha');
      assert.strictEqual(projects[1].name, 'beta');
      assert.strictEqual(projects[2].name, 'zebra');
    });
  });

  describe('deleteProject', () => {
    it('should delete project permanently', async () => {
      fs.access = mock.fn(async () => {}); // Project exists

      let rmCalled = false;
      fs.rm = mock.fn(async (path, options) => {
        rmCalled = true;
        assert(options.recursive);
        assert(options.force);
      });

      const result = await projectCreator.deleteProject('test-project', false);

      assert.strictEqual(result.success, true);
      assert(result.message.includes('deleted'));
      assert(rmCalled);
    });

    it('should archive project when requested', async () => {
      fs.access = mock.fn(async () => {}); // Project exists
      fs.mkdir = mock.fn(async () => {});

      let renameCalled = false;
      fs.rename = mock.fn(async (from, to) => {
        renameCalled = true;
        assert(from.includes('test-project'));
        assert(to.includes('.archived'));
      });

      const result = await projectCreator.deleteProject('test-project', true);

      assert.strictEqual(result.success, true);
      assert(result.message.includes('archived'));
      assert(result.archivePath);
      assert(renameCalled);
    });

    it('should throw error if project not found', async () => {
      fs.access = mock.fn(async () => {
        throw new Error('Not found');
      });

      await assert.rejects(
        async () => {
          await projectCreator.deleteProject('nonexistent');
        },
        {
          message: /not found/,
        }
      );
    });

    it('should handle deletion errors', async () => {
      fs.access = mock.fn(async () => {}); // Project exists
      fs.rm = mock.fn(async () => {
        throw new Error('Permission denied');
      });

      await assert.rejects(
        async () => {
          await projectCreator.deleteProject('test-project');
        },
        {
          message: /Permission denied/,
        }
      );
    });
  });

  describe('updateProjectMetadata', () => {
    it('should update existing metadata', async () => {
      const existingMetadata = {
        name: 'test-project',
        type: 'web-app',
        status: 'planning',
      };

      fs.readFile = mock.fn(async () => JSON.stringify(existingMetadata));

      let _writtenContent = null;
      fs.writeFile = mock.fn(async (path, content) => {
        _writtenContent = JSON.parse(content);
      });

      const updates = {
        status: 'development',
        teamSize: 'large',
      };

      const result = await projectCreator.updateProjectMetadata('test-project', updates);

      assert.strictEqual(result.status, 'development');
      assert.strictEqual(result.teamSize, 'large');
      assert.strictEqual(result.name, 'test-project'); // Preserved
      assert(result.lastModified);
    });

    it('should handle read errors', async () => {
      fs.readFile = mock.fn(async () => {
        throw new Error('File not found');
      });

      await assert.rejects(
        async () => {
          await projectCreator.updateProjectMetadata('test-project', {});
        },
        {
          message: /File not found/,
        }
      );
    });

    it('should handle write errors', async () => {
      fs.readFile = mock.fn(async () => JSON.stringify({ name: 'test' }));
      fs.writeFile = mock.fn(async () => {
        throw new Error('Write failed');
      });

      await assert.rejects(
        async () => {
          await projectCreator.updateProjectMetadata('test-project', {});
        },
        {
          message: /Write failed/,
        }
      );
    });

    it('should handle invalid JSON', async () => {
      fs.readFile = mock.fn(async () => 'invalid json');

      await assert.rejects(
        async () => {
          await projectCreator.updateProjectMetadata('test-project', {});
        },
        {
          message: /JSON/,
        }
      );
    });
  });

  describe('initializeGit', () => {
    it('should handle git initialization failure gracefully', async () => {
      // Direct test of the actual method
      const projectPath = '/test/project';

      // This should not throw even if git commands would fail
      await assert.doesNotReject(async () => {
        await projectCreator.initializeGit(projectPath);
      });

      // Check that warning was logged
      assert(
        consoleWarnSpy.mock.calls.some((call) => {
          const arg = call.arguments[0];
          return typeof arg === 'string' && arg.includes('Failed to initialize git');
        })
      );
    });
  });
});
