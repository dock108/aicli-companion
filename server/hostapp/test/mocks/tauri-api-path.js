import { vi } from 'vitest';

export const appDataDir = vi.fn(async () => {
  return '/Users/test/Library/Application Support';
});