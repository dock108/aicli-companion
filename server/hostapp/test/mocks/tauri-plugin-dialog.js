import { vi } from 'vitest';

export const open = vi.fn(async (options) => {
  // Simulate user selecting a directory
  return '/Users/test/claude-companion-data';
});