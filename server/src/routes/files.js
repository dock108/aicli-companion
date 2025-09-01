import express from 'express';
import { promises as fs } from 'fs';
import path from 'path';
import { PathValidator } from '../utils/path-security.js';
import { createLogger } from '../utils/logger.js';

const router = express.Router();
const logger = createLogger('FileRoutes');

// Define safe root for all file operations
const ROOT_DIRECTORY = process.cwd();

/**
 * Validates and resolves a working directory to ensure it's within the safe root
 * @param {string} workingDirectory - The directory to validate
 * @returns {Promise<string>} The validated and resolved directory path
 * @throws {Error} If the directory is invalid or outside the root
 */
async function validateWorkingDirectory(workingDirectory) {
  // If no working directory specified, use the root
  if (!workingDirectory || typeof workingDirectory !== 'string') {
    return ROOT_DIRECTORY;
  }

  // Sanitize the input to remove any null bytes or control characters
  // eslint-disable-next-line no-control-regex
  const sanitized = workingDirectory.replace(/[\x00-\x1f\x7f]/g, '');
  if (sanitized !== workingDirectory) {
    logger.warn(`Rejected working directory with control characters: ${workingDirectory}`);
    throw new Error('Invalid working directory');
  }

  // Normalize the path to remove .. and . segments
  const normalized = path.normalize(workingDirectory);

  // Check for obvious path traversal attempts
  if (normalized.includes('..') || path.isAbsolute(normalized)) {
    // If it's an absolute path, ensure it's under ROOT_DIRECTORY
    if (path.isAbsolute(normalized)) {
      if (!normalized.startsWith(ROOT_DIRECTORY)) {
        logger.warn(`Blocked absolute path outside root: ${workingDirectory}`);
        throw new Error('Working directory is outside the allowed root');
      }
      // Use the absolute path as-is if it's within root
      const resolvedDir = normalized;

      try {
        // Verify it exists and is a directory
        const stats = await fs.stat(resolvedDir);
        if (!stats.isDirectory()) {
          throw new Error('Working directory is not a directory');
        }

        // Get real path to resolve symlinks
        const realPath = await fs.realpath(resolvedDir);

        // Double-check the real path is still within root
        if (!realPath.startsWith(ROOT_DIRECTORY)) {
          logger.warn(`Blocked symlink escape attempt: ${workingDirectory} -> ${realPath}`);
          throw new Error('Working directory is outside the allowed root');
        }

        return realPath;
      } catch (error) {
        if (error.code === 'ENOENT') {
          logger.warn(`Working directory does not exist: ${workingDirectory}`);
          throw new Error('Working directory does not exist');
        } else if (error.code === 'EACCES') {
          logger.warn(`No access to working directory: ${workingDirectory}`);
          throw new Error('Permission denied for working directory');
        }
        throw error;
      }
    }

    // Reject relative paths with ..
    if (normalized.includes('..')) {
      logger.warn(`Blocked path traversal attempt: ${workingDirectory}`);
      throw new Error('Path traversal not allowed');
    }
  }

  // For relative paths, resolve against ROOT_DIRECTORY
  const resolvedDir = path.resolve(ROOT_DIRECTORY, normalized);

  // Ensure resolved path is within root (belt and suspenders)
  if (!resolvedDir.startsWith(ROOT_DIRECTORY)) {
    logger.warn(`Blocked attempt to escape root directory: ${workingDirectory} -> ${resolvedDir}`);
    throw new Error('Working directory is outside the allowed root');
  }

  try {
    // Verify the directory exists and is accessible
    const stats = await fs.stat(resolvedDir);
    if (!stats.isDirectory()) {
      throw new Error('Working directory is not a directory');
    }

    // Get the real path to handle symlinks
    const realPath = await fs.realpath(resolvedDir);

    // Final check: ensure the real path is still within the root directory
    if (!realPath.startsWith(ROOT_DIRECTORY)) {
      logger.warn(`Blocked symlink escape attempt: ${workingDirectory} -> ${realPath}`);
      throw new Error('Working directory is outside the allowed root');
    }

    return realPath;
  } catch (error) {
    if (error.code === 'ENOENT') {
      logger.warn(`Working directory does not exist: ${workingDirectory}`);
      throw new Error('Working directory does not exist');
    } else if (error.code === 'EACCES') {
      logger.warn(`No access to working directory: ${workingDirectory}`);
      throw new Error('Permission denied for working directory');
    }
    throw error;
  }
}

// Enhanced function to search for files and detect duplicates
async function findAllMatchingFiles(baseDir, filename, maxDepth = 10, currentDepth = 0) {
  const matches = [];

  if (currentDepth > maxDepth) {
    logger.debug(`Max search depth reached (${maxDepth}) while looking for: ${filename}`);
    return matches;
  }

  try {
    const entries = await fs.readdir(baseDir, { withFileTypes: true });
    logger.debug(`Searching in directory: ${baseDir} (depth ${currentDepth})`);

    // Check for exact filename matches in current directory
    for (const entry of entries) {
      if (entry.isFile() && entry.name === filename) {
        const fullPath = path.join(baseDir, entry.name);
        logger.debug(`Found potential match: ${fullPath}`);
        // Verify the file actually exists and is accessible
        try {
          await fs.access(fullPath);
          const stats = await fs.stat(fullPath);
          matches.push({
            path: fullPath,
            relativePath: path.relative(baseDir, fullPath),
            size: stats.size,
            lastModified: stats.mtime,
          });
          logger.info(`Found file: ${filename} at ${fullPath}`);
        } catch (accessError) {
          logger.debug(`File exists but not accessible: ${fullPath}`);
          continue;
        }
      }
    }

    // Then recursively search subdirectories
    for (const entry of entries) {
      if (entry.isDirectory() && !entry.name.startsWith('.') && entry.name !== 'node_modules') {
        const subDir = path.join(baseDir, entry.name);
        const subMatches = await findAllMatchingFiles(subDir, filename, maxDepth, currentDepth + 1);
        matches.push(...subMatches);
      }
    }
  } catch (error) {
    logger.debug(`Error reading directory ${baseDir}: ${error.message}`);
  }

  return matches;
}

// File size limit (1MB)
const MAX_FILE_SIZE = 1024 * 1024;

// Supported file extensions for content viewing
const SUPPORTED_EXTENSIONS = new Set([
  '.js',
  '.ts',
  '.jsx',
  '.tsx',
  '.py',
  '.swift',
  '.java',
  '.cpp',
  '.c',
  '.h',
  '.hpp',
  '.go',
  '.rs',
  '.rb',
  '.php',
  '.html',
  '.css',
  '.scss',
  '.sass',
  '.json',
  '.xml',
  '.yml',
  '.yaml',
  '.toml',
  '.md',
  '.txt',
  '.sh',
  '.bat',
  '.sql',
  '.r',
  '.m',
  '.mm',
  '.vue',
  '.svelte',
  '.dart',
  '.kt',
  '.scala',
  '.clj',
  '.hs',
  '.elm',
  '.ex',
  '.exs',
  '.ini',
  '.conf',
  '.env',
  '.gitignore',
  '.dockerignore',
  '.editorconfig',
]);

/**
 * Get file content securely
 * POST /api/files/content
 */
router.post('/content', async (req, res) => {
  try {
    const { path: requestedPath, workingDirectory } = req.body;

    // Input validation
    if (!requestedPath || typeof requestedPath !== 'string') {
      return res.status(400).json({
        success: false,
        message: 'File path is required',
        error: 'INVALID_PATH',
      });
    }

    // Validate and get the base directory
    let baseDirectory;
    try {
      baseDirectory = await validateWorkingDirectory(workingDirectory);
    } catch (error) {
      logger.warn(`Invalid working directory: ${error.message}`);
      return res.status(400).json({
        success: false,
        message: 'Invalid working directory',
        error: 'INVALID_WORKING_DIRECTORY',
        details: error.message,
      });
    }

    logger.info(`File content request for: ${requestedPath} in directory: ${baseDirectory}`);

    // Check if this is just a filename (no path separators) and needs searching
    let validatedPath;
    let duplicateWarning = null;

    if (!requestedPath.includes('/') && !requestedPath.includes('\\')) {
      // This is just a filename, search for it in the project directory
      logger.info(`Searching for file: ${requestedPath} in project directory: ${baseDirectory}`);

      const allMatches = await findAllMatchingFiles(baseDirectory, requestedPath);
      if (allMatches.length === 0) {
        logger.warn(`File not found in project directory: ${requestedPath}`);
        return res.status(404).json({
          success: false,
          message: `File '${requestedPath}' not found in project directory`,
          error: 'FILE_NOT_FOUND',
        });
      }

      // Use the first match (most recently modified if same name)
      allMatches.sort((a, b) => b.lastModified - a.lastModified);
      validatedPath = allMatches[0].path;

      // Check for duplicates
      if (allMatches.length > 1) {
        logger.warn(
          `Found ${allMatches.length} files with name '${requestedPath}' - this may cause confusion`
        );
        duplicateWarning = {
          type: 'DUPLICATE_FILENAMES',
          message: `Found ${allMatches.length} files named '${requestedPath}' in your project. Consider renaming them for better organization.`,
          duplicates: allMatches.map((match) => ({
            relativePath: match.relativePath,
            size: match.size,
            lastModified: match.lastModified.toISOString(),
          })),
          suggestion: `Ask Claude Code to rename these files with more descriptive names to avoid confusion. Example: "Please rename the duplicate '${requestedPath}' files to have more descriptive names based on their content and location."`,
        };
      }

      // Security: Always validate the found path is within the safe root
      try {
        validatedPath = await PathValidator.validatePath(baseDirectory, path.relative(baseDirectory, validatedPath), {
          allowSymlinks: false,
          mustExist: true,
          mustBeDirectory: false,
        });
      } catch (pathError) {
        logger.warn(`Path validation failed for found file ${validatedPath}: ${pathError.message}`);
        return res.status(403).json({
          success: false,
          message: 'Access denied to file path',
          error: 'PATH_VALIDATION_FAILED',
        });
      }
      logger.info(
        `Using file at: ${validatedPath}${allMatches.length > 1 ? ` (selected most recent of ${allMatches.length} matches)` : ''}`
      );
    } else {
      // Validate and resolve the path securely for paths with directories
      try {
        validatedPath = await PathValidator.validatePath(baseDirectory, requestedPath, {
          allowSymlinks: false,
          mustExist: true,
          mustBeDirectory: false,
        });
      } catch (pathError) {
        logger.warn(`Path validation failed for ${requestedPath}: ${pathError.message}`);
        return res.status(403).json({
          success: false,
          message: 'Access denied to file path',
          error: 'PATH_VALIDATION_FAILED',
        });
      }
    }

    // Check if file extension is supported
    const fileExtension = path.extname(validatedPath).toLowerCase();
    if (!SUPPORTED_EXTENSIONS.has(fileExtension) && fileExtension !== '') {
      logger.warn(`Unsupported file extension: ${fileExtension} for file: ${requestedPath}`);
      return res.status(415).json({
        success: false,
        message: `File type '${fileExtension}' is not supported for viewing`,
        error: 'UNSUPPORTED_FILE_TYPE',
      });
    }

    // Get file stats first
    let stats;
    try {
      stats = await fs.stat(validatedPath);
    } catch (statError) {
      logger.warn(`File stat failed for ${validatedPath}: ${statError.message}`);

      if (statError.code === 'ENOENT') {
        return res.status(404).json({
          success: false,
          message: 'File not found',
          error: 'FILE_NOT_FOUND',
        });
      } else if (statError.code === 'EACCES') {
        return res.status(403).json({
          success: false,
          message: 'Permission denied',
          error: 'PERMISSION_DENIED',
        });
      } else {
        throw statError;
      }
    }

    // Check if it's a directory
    if (stats.isDirectory()) {
      return res.status(400).json({
        success: false,
        message: 'Cannot view directory contents',
        error: 'IS_DIRECTORY',
      });
    }

    // Check file size
    if (stats.size > MAX_FILE_SIZE) {
      return res.status(413).json({
        success: false,
        message: `File is too large (${Math.round(stats.size / 1024)}KB). Maximum size is ${Math.round(MAX_FILE_SIZE / 1024)}KB`,
        error: 'FILE_TOO_LARGE',
      });
    }

    // Read file content
    let content;
    try {
      content = await fs.readFile(validatedPath, 'utf8');
    } catch (readError) {
      logger.error(`File read failed for ${validatedPath}: ${readError.message}`);

      if (readError.code === 'ENOENT') {
        return res.status(404).json({
          success: false,
          message: 'File not found',
          error: 'FILE_NOT_FOUND',
        });
      } else if (readError.code === 'EACCES') {
        return res.status(403).json({
          success: false,
          message: 'Permission denied',
          error: 'PERMISSION_DENIED',
        });
      } else if (readError.code === 'EISDIR') {
        return res.status(400).json({
          success: false,
          message: 'Cannot read directory as file',
          error: 'IS_DIRECTORY',
        });
      } else {
        // Check if it's a binary file (rough heuristic)
        if (readError.message.includes('invalid') || readError.message.includes('binary')) {
          return res.status(415).json({
            success: false,
            message: 'Binary files are not supported',
            error: 'BINARY_FILE',
          });
        }
        throw readError;
      }
    }

    // Create response
    const fileName = path.basename(validatedPath);
    const mimeType = getMimeType(fileExtension);

    const fileContentData = {
      filename: fileName,
      content,
      mimeType,
      size: stats.size,
      encoding: 'utf-8',
    };

    logger.info(`Successfully served file content for: ${requestedPath} (${stats.size} bytes)`);

    const response = {
      success: true,
      content: fileContentData,
    };

    // Include duplicate warning if found
    if (duplicateWarning) {
      response.warning = duplicateWarning;
      logger.warn(`Including duplicate filename warning for: ${requestedPath}`);
    }

    res.json(response);
  } catch (error) {
    logger.error(`Unexpected error in file content endpoint: ${error.message}`, { error });

    res.status(500).json({
      success: false,
      message: 'Internal server error',
      error: 'INTERNAL_ERROR',
    });
  }
});

/**
 * Get basic file info without content
 * GET /api/files/info
 */
router.get('/info', async (req, res) => {
  try {
    const { path: requestedPath, workingDirectory } = req.query;

    if (!requestedPath) {
      return res.status(400).json({
        success: false,
        message: 'File path is required',
        error: 'INVALID_PATH',
      });
    }

    // Validate and get the base directory
    let baseDirectory;
    try {
      baseDirectory = await validateWorkingDirectory(workingDirectory);
    } catch (error) {
      logger.warn(`Invalid working directory: ${error.message}`);
      return res.status(400).json({
        success: false,
        message: 'Invalid working directory',
        error: 'INVALID_WORKING_DIRECTORY',
        details: error.message,
      });
    }

    // Validate path
    let validatedPath;
    try {
      validatedPath = await PathValidator.validatePath(baseDirectory, requestedPath, {
        allowSymlinks: false,
        mustExist: true,
        mustBeDirectory: false,
      });
    } catch (pathError) {
      return res.status(403).json({
        success: false,
        message: 'Access denied to file path',
        error: 'PATH_VALIDATION_FAILED',
      });
    }

    // Get file stats
    const stats = await fs.stat(validatedPath);
    const fileName = path.basename(validatedPath);
    const fileExtension = path.extname(validatedPath).toLowerCase();
    const mimeType = getMimeType(fileExtension);

    res.json({
      success: true,
      info: {
        filename: fileName,
        size: stats.size,
        mimeType,
        isDirectory: stats.isDirectory(),
        lastModified: stats.mtime.toISOString(),
        isSupported: SUPPORTED_EXTENSIONS.has(fileExtension),
        canView:
          !stats.isDirectory() &&
          SUPPORTED_EXTENSIONS.has(fileExtension) &&
          stats.size <= MAX_FILE_SIZE,
      },
    });
  } catch (error) {
    logger.error(`Error getting file info: ${error.message}`, { error });

    if (error.code === 'ENOENT') {
      return res.status(404).json({
        success: false,
        message: 'File not found',
        error: 'FILE_NOT_FOUND',
      });
    }

    res.status(500).json({
      success: false,
      message: 'Internal server error',
      error: 'INTERNAL_ERROR',
    });
  }
});

// Helper function to get MIME type from file extension
function getMimeType(extension) {
  const mimeTypes = {
    '.js': 'text/javascript',
    '.ts': 'text/typescript',
    '.jsx': 'text/javascript',
    '.tsx': 'text/typescript',
    '.py': 'text/x-python',
    '.swift': 'text/x-swift',
    '.java': 'text/x-java-source',
    '.cpp': 'text/x-c++src',
    '.c': 'text/x-csrc',
    '.h': 'text/x-chdr',
    '.hpp': 'text/x-c++hdr',
    '.go': 'text/x-go',
    '.rs': 'text/x-rustsrc',
    '.rb': 'text/x-ruby',
    '.php': 'text/x-php',
    '.html': 'text/html',
    '.css': 'text/css',
    '.scss': 'text/x-scss',
    '.sass': 'text/x-sass',
    '.json': 'application/json',
    '.xml': 'application/xml',
    '.yml': 'text/x-yaml',
    '.yaml': 'text/x-yaml',
    '.toml': 'text/x-toml',
    '.md': 'text/markdown',
    '.txt': 'text/plain',
    '.sh': 'text/x-shellscript',
    '.bat': 'text/x-msdos-batch',
    '.sql': 'text/x-sql',
    '.r': 'text/x-rsrc',
    '.m': 'text/x-objcsrc',
    '.mm': 'text/x-objc++src',
  };

  return mimeTypes[extension] || 'text/plain';
}

export default router;
