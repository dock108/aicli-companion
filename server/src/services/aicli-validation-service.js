import { MessageProcessor } from './aicli-utils.js';

/**
 * Handles JSON validation and parsing utilities for AICLI CLI responses
 */
export class AICLIValidationService {
  /**
   * Validate that JSON is complete and not truncated
   */
  static isValidCompleteJSON(jsonString) {
    if (!jsonString || jsonString.length === 0) {
      console.log(`JSON validation: Empty or null input`);
      return false;
    }

    try {
      // First, try basic JSON parsing
      const parsed = JSON.parse(jsonString);

      // Additional checks for completeness
      const trimmed = jsonString.trim();

      // For primitive JSON values, they are valid if they parse successfully
      // No additional validation needed for strings, numbers, booleans, null

      // Successful parsing and validation
      console.log(`JSON validation: Valid complete JSON (${parsed ? 'object' : 'value'})`);
      return true;
    } catch (error) {
      console.log(`JSON validation: Parse error - ${error.message}`);
      return false;
    }
  }

  /**
   * Parse stream-json format output into structured responses
   */
  static parseStreamJsonOutput(output) {
    const responses = [];
    const lines = output.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;

      try {
        // Try parsing each line as JSON
        let parsed = JSON.parse(line);
        responses.push(parsed);
      } catch (parseError) {
        // For incomplete lines, try to extract complete objects
        const extracted = MessageProcessor.extractCompleteObjectsFromLine(line);
        responses.push(...extracted);
      }
    }

    return responses;
  }

  /**
   * Extract complete JSON objects from a potentially incomplete line
   */
  static extractCompleteObjectsFromLine(line) {
    const objects = [];
    let depth = 0;
    let currentObject = '';
    let inString = false;
    let escaped = false;

    for (let i = 0; i < line.length; i++) {
      const char = line[i];
      currentObject += char;

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char === '\\' && inString) {
        escaped = true;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char === '{') {
        depth++;
      } else if (char === '}') {
        depth--;
        if (depth === 0) {
          // Complete object found
          try {
            const parsed = JSON.parse(currentObject);
            objects.push(parsed);
            currentObject = '';
          } catch (error) {
            // Invalid JSON, skip
            currentObject = '';
          }
        }
      }
    }

    return objects;
  }

  /**
   * Extract the last complete JSON object from truncated JSON
   */
  static extractLastCompleteJSON(truncatedJSON) {
    try {
      // Look for complete JSON objects/arrays by finding balanced braces/brackets
      const lastCompleteStart = this.findLastCompleteJSONStart(truncatedJSON);
      if (lastCompleteStart >= 0) {
        const candidate = truncatedJSON.substring(lastCompleteStart);
        return JSON.parse(candidate);
      }
    } catch (error) {
      // If that fails, try extracting from array format
      try {
        const objects = this.extractCompleteObjectsFromArray(truncatedJSON);
        if (objects.length > 0) {
          return objects[objects.length - 1];
        }
      } catch (arrayError) {
        console.error('Failed to extract from array format:', arrayError);
      }
    }

    return null;
  }

  /**
   * Find the start position of the last complete JSON object
   */
  static findLastCompleteJSONStart(text) {
    let braceCount = 0;
    let bracketCount = 0;
    let inString = false;
    let escaped = false;
    let lastObjectStart = -1;

    for (let i = text.length - 1; i >= 0; i--) {
      const char = text[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char === '\\' && inString) {
        escaped = true;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char === '}') braceCount++;
      else if (char === '{') braceCount--;
      else if (char === ']') bracketCount++;
      else if (char === '[') bracketCount--;

      if (braceCount === 0 && bracketCount === 0 && (char === '{' || char === '[')) {
        lastObjectStart = i;
        break;
      }
    }

    return lastObjectStart;
  }

  /**
   * Extract complete objects from array-formatted text
   */
  static extractCompleteObjectsFromArray(arrayText) {
    if (!arrayText || typeof arrayText !== 'string') {
      return [];
    }
    
    const objects = [];
    let depth = 0;
    let currentObject = '';
    let inString = false;
    let escaped = false;
    let objectDepth = 0;

    for (let i = 0; i < arrayText.length; i++) {
      const char = arrayText[i];

      if (escaped) {
        escaped = false;
        currentObject += char;
        continue;
      }

      if (char === '\\' && inString) {
        escaped = true;
        currentObject += char;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        currentObject += char;
        continue;
      }

      if (inString) {
        currentObject += char;
        continue;
      }

      if (char === '[' && currentObject === '') {
        // Start of array, skip
        continue;
      }

      if (char === '{') {
        if (objectDepth === 0) {
          currentObject = char;
        } else {
          currentObject += char;
        }
        objectDepth++;
      } else if (char === '}') {
        currentObject += char;
        objectDepth--;
        if (objectDepth === 0) {
          // Complete object
          try {
            const parsed = JSON.parse(currentObject);
            objects.push(parsed);
          } catch (error) {
            // Invalid JSON, skip
          }
          currentObject = '';
        }
      } else if (objectDepth > 0) {
        currentObject += char;
      }
    }

    return objects;
  }
}