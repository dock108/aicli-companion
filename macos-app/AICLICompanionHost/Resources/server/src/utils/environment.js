/**
 * Environment detection utilities
 * Centralizes NODE_ENV checks to improve maintainability
 */
export class EnvironmentUtils {
  /**
   * Check if running in test environment
   * @returns {boolean} True if NODE_ENV === 'test'
   */
  static isTestEnvironment() {
    return process.env.NODE_ENV === 'test';
  }

  /**
   * Check if NOT running in test environment
   * @returns {boolean} True if NODE_ENV !== 'test'
   */
  static isNotTestEnvironment() {
    return process.env.NODE_ENV !== 'test';
  }

  /**
   * Check if running in production environment
   * @returns {boolean} True if NODE_ENV === 'production'
   */
  static isProductionEnvironment() {
    return process.env.NODE_ENV === 'production';
  }

  /**
   * Check if running in development environment
   * @returns {boolean} True if NODE_ENV === 'development'
   */
  static isDevelopmentEnvironment() {
    return process.env.NODE_ENV === 'development';
  }

  /**
   * Get the current environment name
   * @returns {string} Current NODE_ENV value or 'development' as default
   */
  static getCurrentEnvironment() {
    return process.env.NODE_ENV || 'development';
  }
}

// Convenience functions for common usage patterns
export const isTestEnvironment = () => EnvironmentUtils.isTestEnvironment();
export const isNotTestEnvironment = () => EnvironmentUtils.isNotTestEnvironment();
export const isProductionEnvironment = () => EnvironmentUtils.isProductionEnvironment();
export const isDevelopmentEnvironment = () => EnvironmentUtils.isDevelopmentEnvironment();
export const getCurrentEnvironment = () => EnvironmentUtils.getCurrentEnvironment();