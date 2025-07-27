console.log('🚀 App.js starting to load...');

// Import the core module and initialize
import('./app-core.js')
  .then((appCore) => {
    console.log('📦 Importing Tauri APIs...');

    // Initialize when DOM is ready
    console.log('🎯 Current document readyState:', document.readyState);

    if (document.readyState === 'loading') {
      console.log('⏳ Document still loading, setting up DOMContentLoaded listener...');
      document.addEventListener('DOMContentLoaded', () => {
        console.log('✅ DOM Content Loaded - starting init()');
        appCore.init();
      });
    } else {
      console.log('✅ Document already loaded, starting init() immediately');
      appCore.init();
    }
  })
  .catch((error) => {
    console.error('❌ Failed to import app-core:', error);
  });
