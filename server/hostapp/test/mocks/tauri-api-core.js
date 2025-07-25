import { vi } from 'vitest';

export const invoke = vi.fn(async (command, args) => {
  switch (command) {
    case 'get_local_ip':
      return '192.168.1.100';
    
    case 'start_server':
      return {
        running: true,
        port: args.port || 3001,
        pid: 12345,
        health_url: `http://localhost:${args.port || 3001}/health`,
        external: false
      };
    
    case 'stop_server':
      return null;
    
    case 'check_server_health':
      return true;
    
    case 'get_server_status':
      return {
        running: false,
        port: 3001,
        pid: null,
        health_url: 'http://localhost:3001/health',
        external: false
      };
    
    case 'detect_running_server':
      return {
        running: false,
        port: args.port,
        pid: null,
        health_url: `http://localhost:${args.port}/health`,
        external: false
      };
    
    default:
      throw new Error(`Unknown command: ${command}`);
  }
});