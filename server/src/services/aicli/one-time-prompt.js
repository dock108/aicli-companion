import { spawn } from 'child_process';
import { AICLIConfig } from '../aicli-utils.js';

export class OneTimePrompt {
  constructor(permissionHandler) {
    this.permissionHandler = permissionHandler;
    this.aicliCommand = null;
  }

  setAicliCommand(command) {
    this.aicliCommand = command;
  }

  async sendOneTimePrompt(
    prompt,
    { format = 'json', workingDirectory = process.cwd(), skipPermissions = false }
  ) {
    const aicliPath = this.aicliCommand || (await AICLIConfig.findAICLICommand());

    // Build command args
    const args = [prompt];

    // Add format flag
    if (format === 'json') {
      args.unshift('--format', 'json');
    }

    // Add permission flags before the prompt
    const permissionArgs = this.permissionHandler.buildPermissionArgs(skipPermissions);
    args.unshift(...permissionArgs);

    // Sanitize prompt for shell execution
    const sanitizedPrompt = prompt.replace(/"/g, '\\"').replace(/\$/g, '\\$');

    // Double-check sanitization
    if (!args.includes(sanitizedPrompt)) {
      args[args.indexOf(prompt)] = sanitizedPrompt;
    }

    // Build spawn options
    const spawnOptions = {
      cwd: workingDirectory,
      env: { ...process.env },
      shell: false,
      windowsHide: true,
    };

    return new Promise((resolve, reject) => {
      console.log(`🚀 Starting one-time AICLI Code process...`);
      const aicliProcess = spawn(aicliPath, args, spawnOptions);

      let stdout = '';
      let stderr = '';
      const resolvePromise = resolve;

      // Handle spawn errors
      aicliProcess.on('error', (error) => {
        const errorMsg = `Failed to start AICLI Code: ${error.message}`;
        console.error(`❌ ${errorMsg}`);
        reject(new Error(errorMsg));
      });

      // Check if process started successfully
      setTimeout(() => {
        if (!aicliProcess.pid) {
          const errorMsg = 'AICLI Code process failed to start (no PID assigned)';
          console.error(`❌ ${errorMsg}`);
          aicliProcess.kill();
          reject(new Error(errorMsg));
        }
      }, 100);

      // Collect stdout
      aicliProcess.stdout.on('data', (data) => {
        stdout += data.toString();
      });

      // Collect stderr
      aicliProcess.stderr.on('data', (data) => {
        stderr += data.toString();
        // Log errors but don't fail immediately
        if (data.toString().includes('error') || data.toString().includes('Error')) {
          console.warn('⚠️ AICLI stderr:', data.toString());
        }
      });

      // Handle process exit
      aicliProcess.on('exit', (code) => {
        console.log(`🏁 AICLI Code process exited with code ${code}`);

        if (code !== 0) {
          reject(new Error(`AICLI Code exited with code ${code}: ${stderr}`));
        } else {
          try {
            // Parse response based on format
            if (format === 'json') {
              const response = JSON.parse(stdout);
              console.log('✅ Successfully parsed AICLI Code JSON response');
              resolvePromise(response);
            } else {
              resolvePromise({ result: stdout });
            }
          } catch (error) {
            reject(new Error(`Failed to parse AICLI Code response: ${error.message}`));
          }
        }
      });

      aicliProcess.on('close', () => {
        reject(new Error(`AICLI Code process closed unexpectedly`));
      });
    });
  }
}
