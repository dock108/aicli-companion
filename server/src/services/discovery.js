import { Bonjour } from 'bonjour-service';

export function setupBonjour(port, enableTLS = false) {
  try {
    const bonjour = new Bonjour();
    
    // Advertise the service
    const service = bonjour.publish({
      name: 'Claude Companion Server',
      type: 'claudecode',
      port: port,
      txt: {
        version: '1.0.0',
        features: 'chat,streaming,permissions',
        auth: process.env.AUTH_TOKEN ? 'required' : 'none',
        tls: enableTLS ? 'enabled' : 'disabled',
        protocol: enableTLS ? 'wss' : 'ws'
      }
    });
    
    service.on('up', () => {
      console.log(`🔍 Bonjour service published: ${service.fqdn}`);
    });
    
    service.on('error', (error) => {
      console.error('Bonjour service error:', error);
    });
    
    // Graceful cleanup
    process.on('SIGINT', () => {
      bonjour.unpublishAll(() => {
        bonjour.destroy();
      });
    });
    
    process.on('SIGTERM', () => {
      bonjour.unpublishAll(() => {
        bonjour.destroy();
      });
    });
    
    return service;
  } catch (error) {
    console.error('Failed to setup Bonjour:', error);
    throw error;
  }
}