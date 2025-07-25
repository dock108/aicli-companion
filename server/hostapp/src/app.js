console.log('🚀 App.js starting to load...');

// Import the core module and initialize
import('./app-core.js')
  .then((appCore) => {
    console.log('📦 Importing Tauri APIs...');

    // Initialize when DOM is ready
    console.log('🎯 Setting up DOMContentLoaded listener...');
    document.addEventListener('DOMContentLoaded', () => {
      console.log('✅ DOM Content Loaded - starting init()');
      appCore.init();
    });
  })
  .catch((error) => {
    console.error('❌ Failed to import app-core:', error);
  });
