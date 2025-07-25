import { vi } from 'vitest';

// Mock console methods to avoid noise in tests
global.console = {
  ...console,
  log: vi.fn(),
  error: vi.fn(),
  warn: vi.fn(),
  info: vi.fn(),
  debug: vi.fn()
};

// Mock localStorage
const localStorageMock = (() => {
  let store = {};
  return {
    getItem: (key) => store[key] || null,
    setItem: (key, value) => {
      store[key] = value.toString();
    },
    removeItem: (key) => {
      delete store[key];
    },
    clear: () => {
      store = {};
    }
  };
})();

global.localStorage = localStorageMock;

// Mock DOM elements
global.document = {
  getElementById: vi.fn((id) => {
    const elements = {
      'config-path': { value: '', addEventListener: vi.fn() },
      'browse-btn': { addEventListener: vi.fn(), disabled: false },
      'port': { value: '3001', addEventListener: vi.fn() },
      'status-dot': { classList: { add: vi.fn(), remove: vi.fn() } },
      'status-text': { textContent: '' },
      'server-info': { style: { display: 'none' } },
      'server-url': { textContent: '' },
      'server-pid': { textContent: '' },
      'start-btn': { 
        addEventListener: vi.fn(), 
        disabled: false,
        classList: { add: vi.fn(), remove: vi.fn() }
      },
      'stop-btn': { 
        addEventListener: vi.fn(), 
        disabled: true,
        title: ''
      },
      'qr-section': { style: { display: 'none' } },
      'qr-code': { innerHTML: '' },
      'connection-string': { textContent: '' },
      'external-notice': { style: { display: 'none' } }
    };
    return elements[id] || null;
  }),
  addEventListener: vi.fn()
};

// Mock window.alert and window.confirm
global.alert = vi.fn();
global.confirm = vi.fn(() => true);

// Mock setInterval
global.setInterval = vi.fn((callback, delay) => {
  return 123; // Return mock timer ID
});

// Reset mocks before each test
beforeEach(() => {
  vi.clearAllMocks();
  localStorageMock.clear();
});