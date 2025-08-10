import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import {
  EnvironmentUtils,
  isTestEnvironment,
  isNotTestEnvironment,
  isProductionEnvironment,
  isDevelopmentEnvironment,
  getCurrentEnvironment,
} from '../../utils/environment.js';

describe('EnvironmentUtils', () => {
  let originalNodeEnv;

  beforeEach(() => {
    // Store the original NODE_ENV value
    originalNodeEnv = process.env.NODE_ENV;
  });

  afterEach(() => {
    // Restore the original NODE_ENV value
    if (originalNodeEnv !== undefined) {
      process.env.NODE_ENV = originalNodeEnv;
    } else {
      delete process.env.NODE_ENV;
    }
  });

  describe('isTestEnvironment', () => {
    it('should return true when NODE_ENV is test', () => {
      process.env.NODE_ENV = 'test';
      assert.strictEqual(EnvironmentUtils.isTestEnvironment(), true);
      assert.strictEqual(isTestEnvironment(), true);
    });

    it('should return false when NODE_ENV is not test', () => {
      process.env.NODE_ENV = 'development';
      assert.strictEqual(EnvironmentUtils.isTestEnvironment(), false);
      assert.strictEqual(isTestEnvironment(), false);

      process.env.NODE_ENV = 'production';
      assert.strictEqual(EnvironmentUtils.isTestEnvironment(), false);
      assert.strictEqual(isTestEnvironment(), false);
    });

    it('should return false when NODE_ENV is undefined', () => {
      delete process.env.NODE_ENV;
      assert.strictEqual(EnvironmentUtils.isTestEnvironment(), false);
      assert.strictEqual(isTestEnvironment(), false);
    });

    it('should be case-sensitive', () => {
      process.env.NODE_ENV = 'TEST';
      assert.strictEqual(EnvironmentUtils.isTestEnvironment(), false);

      process.env.NODE_ENV = 'Test';
      assert.strictEqual(EnvironmentUtils.isTestEnvironment(), false);
    });
  });

  describe('isNotTestEnvironment', () => {
    it('should return false when NODE_ENV is test', () => {
      process.env.NODE_ENV = 'test';
      assert.strictEqual(EnvironmentUtils.isNotTestEnvironment(), false);
      assert.strictEqual(isNotTestEnvironment(), false);
    });

    it('should return true when NODE_ENV is not test', () => {
      process.env.NODE_ENV = 'development';
      assert.strictEqual(EnvironmentUtils.isNotTestEnvironment(), true);
      assert.strictEqual(isNotTestEnvironment(), true);

      process.env.NODE_ENV = 'production';
      assert.strictEqual(EnvironmentUtils.isNotTestEnvironment(), true);
      assert.strictEqual(isNotTestEnvironment(), true);
    });

    it('should return true when NODE_ENV is undefined', () => {
      delete process.env.NODE_ENV;
      assert.strictEqual(EnvironmentUtils.isNotTestEnvironment(), true);
      assert.strictEqual(isNotTestEnvironment(), true);
    });
  });

  describe('isProductionEnvironment', () => {
    it('should return true when NODE_ENV is production', () => {
      process.env.NODE_ENV = 'production';
      assert.strictEqual(EnvironmentUtils.isProductionEnvironment(), true);
      assert.strictEqual(isProductionEnvironment(), true);
    });

    it('should return false when NODE_ENV is not production', () => {
      process.env.NODE_ENV = 'development';
      assert.strictEqual(EnvironmentUtils.isProductionEnvironment(), false);
      assert.strictEqual(isProductionEnvironment(), false);

      process.env.NODE_ENV = 'test';
      assert.strictEqual(EnvironmentUtils.isProductionEnvironment(), false);
      assert.strictEqual(isProductionEnvironment(), false);
    });

    it('should return false when NODE_ENV is undefined', () => {
      delete process.env.NODE_ENV;
      assert.strictEqual(EnvironmentUtils.isProductionEnvironment(), false);
      assert.strictEqual(isProductionEnvironment(), false);
    });

    it('should be case-sensitive', () => {
      process.env.NODE_ENV = 'PRODUCTION';
      assert.strictEqual(EnvironmentUtils.isProductionEnvironment(), false);

      process.env.NODE_ENV = 'Production';
      assert.strictEqual(EnvironmentUtils.isProductionEnvironment(), false);
    });
  });

  describe('isDevelopmentEnvironment', () => {
    it('should return true when NODE_ENV is development', () => {
      process.env.NODE_ENV = 'development';
      assert.strictEqual(EnvironmentUtils.isDevelopmentEnvironment(), true);
      assert.strictEqual(isDevelopmentEnvironment(), true);
    });

    it('should return false when NODE_ENV is not development', () => {
      process.env.NODE_ENV = 'production';
      assert.strictEqual(EnvironmentUtils.isDevelopmentEnvironment(), false);
      assert.strictEqual(isDevelopmentEnvironment(), false);

      process.env.NODE_ENV = 'test';
      assert.strictEqual(EnvironmentUtils.isDevelopmentEnvironment(), false);
      assert.strictEqual(isDevelopmentEnvironment(), false);
    });

    it('should return false when NODE_ENV is undefined', () => {
      delete process.env.NODE_ENV;
      assert.strictEqual(EnvironmentUtils.isDevelopmentEnvironment(), false);
      assert.strictEqual(isDevelopmentEnvironment(), false);
    });

    it('should be case-sensitive', () => {
      process.env.NODE_ENV = 'DEVELOPMENT';
      assert.strictEqual(EnvironmentUtils.isDevelopmentEnvironment(), false);

      process.env.NODE_ENV = 'Development';
      assert.strictEqual(EnvironmentUtils.isDevelopmentEnvironment(), false);
    });
  });

  describe('getCurrentEnvironment', () => {
    it('should return current NODE_ENV value', () => {
      process.env.NODE_ENV = 'test';
      assert.strictEqual(EnvironmentUtils.getCurrentEnvironment(), 'test');
      assert.strictEqual(getCurrentEnvironment(), 'test');

      process.env.NODE_ENV = 'production';
      assert.strictEqual(EnvironmentUtils.getCurrentEnvironment(), 'production');
      assert.strictEqual(getCurrentEnvironment(), 'production');

      process.env.NODE_ENV = 'development';
      assert.strictEqual(EnvironmentUtils.getCurrentEnvironment(), 'development');
      assert.strictEqual(getCurrentEnvironment(), 'development');
    });

    it('should return development as default when NODE_ENV is undefined', () => {
      delete process.env.NODE_ENV;
      assert.strictEqual(EnvironmentUtils.getCurrentEnvironment(), 'development');
      assert.strictEqual(getCurrentEnvironment(), 'development');
    });

    it('should return custom environment values', () => {
      process.env.NODE_ENV = 'staging';
      assert.strictEqual(EnvironmentUtils.getCurrentEnvironment(), 'staging');

      process.env.NODE_ENV = 'custom-env';
      assert.strictEqual(EnvironmentUtils.getCurrentEnvironment(), 'custom-env');
    });

    it('should return empty string when NODE_ENV is empty string', () => {
      process.env.NODE_ENV = '';
      assert.strictEqual(EnvironmentUtils.getCurrentEnvironment(), 'development');
    });
  });

  describe('Mixed environment checks', () => {
    it('should correctly identify test environment', () => {
      process.env.NODE_ENV = 'test';
      assert.strictEqual(isTestEnvironment(), true);
      assert.strictEqual(isNotTestEnvironment(), false);
      assert.strictEqual(isProductionEnvironment(), false);
      assert.strictEqual(isDevelopmentEnvironment(), false);
      assert.strictEqual(getCurrentEnvironment(), 'test');
    });

    it('should correctly identify production environment', () => {
      process.env.NODE_ENV = 'production';
      assert.strictEqual(isTestEnvironment(), false);
      assert.strictEqual(isNotTestEnvironment(), true);
      assert.strictEqual(isProductionEnvironment(), true);
      assert.strictEqual(isDevelopmentEnvironment(), false);
      assert.strictEqual(getCurrentEnvironment(), 'production');
    });

    it('should correctly identify development environment', () => {
      process.env.NODE_ENV = 'development';
      assert.strictEqual(isTestEnvironment(), false);
      assert.strictEqual(isNotTestEnvironment(), true);
      assert.strictEqual(isProductionEnvironment(), false);
      assert.strictEqual(isDevelopmentEnvironment(), true);
      assert.strictEqual(getCurrentEnvironment(), 'development');
    });

    it('should handle undefined NODE_ENV correctly', () => {
      delete process.env.NODE_ENV;
      assert.strictEqual(isTestEnvironment(), false);
      assert.strictEqual(isNotTestEnvironment(), true);
      assert.strictEqual(isProductionEnvironment(), false);
      assert.strictEqual(isDevelopmentEnvironment(), false);
      assert.strictEqual(getCurrentEnvironment(), 'development');
    });
  });
});
