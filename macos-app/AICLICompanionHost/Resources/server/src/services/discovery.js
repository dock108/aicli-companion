import { Bonjour } from 'bonjour-service';

export function setupBonjour(port, enableTLS = false) {
  // Skip Bonjour setup in test environment to prevent network conflicts
  if (process.env.NODE_ENV === 'test') {
    console.log('   📡 Bonjour service skipped in test environment');
    return {
      on: () => {},
      unpublishAll: () => {},
    };
  }

  try {
    const bonjour = new Bonjour();

    // Advertise the service
    const service = bonjour.publish({
      name: 'AICLI Companion Server',
      type: 'aiclicode',
      port,
      txt: {
        version: '1.0.0',
        features: 'chat,streaming,permissions',
        auth: process.env.AUTH_TOKEN ? 'required' : 'none',
        tls: enableTLS ? 'enabled' : 'disabled',
        protocol: enableTLS ? 'wss' : 'ws',
      },
    });

    service.on('up', () => {
      console.log(`🔍 Bonjour service published: ${service.fqdn}`);
    });

    service.on('error', (error) => {
      console.error('Bonjour service error:', error);
    });

    // Graceful cleanup (skip in test environment)
    if (process.env.NODE_ENV !== 'test') {
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
    }

    return service;
  } catch (error) {
    console.error('Failed to setup Bonjour:', error);
    throw error;
  }
}
