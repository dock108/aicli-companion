import { describe, it } from 'node:test';
import assert from 'node:assert';
import { AICLIValidationService } from '../../services/aicli-validation-service.js';

describe('AICLIValidationService', () => {
  describe('isValidCompleteJSON', () => {
    it('should return false for null or empty input', () => {
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(null), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(''), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(undefined), false);
    });

    it('should return true for valid complete JSON objects', () => {
      const validJson = '{"type": "result", "message": "Hello world"}';
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(validJson), true);
    });

    it('should return true for valid complete JSON arrays', () => {
      const validJson = '[{"type": "result"}, {"type": "status"}]';
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(validJson), true);
    });

    it('should return true for simple JSON values', () => {
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('"hello"'), true);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('42'), true);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('true'), true);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('null'), true);
    });

    it('should return false for incomplete JSON', () => {
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('{"type": "result"'), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('[{"type": "result"}'), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('"unterminated string'), false);
    });

    it('should return false for malformed JSON', () => {
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('{type: "result"}'), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('{"type": result}'), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('invalid json'), false);
    });

    it('should handle JSON with whitespace', () => {
      const jsonWithWhitespace = '  \n  {"type": "result"}  \n  ';
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(jsonWithWhitespace), true);
    });
  });

  describe('parseStreamJsonOutput', () => {
    it('should parse empty input', () => {
      const result = AICLIValidationService.parseStreamJsonOutput('');
      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 0);
    });

    it('should parse single JSON object', () => {
      const input = '{"type": "result", "message": "Hello"}';
      const result = AICLIValidationService.parseStreamJsonOutput(input);
      
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].type, 'result');
      assert.strictEqual(result[0].message, 'Hello');
    });

    it('should parse multiple JSON objects on separate lines', () => {
      const input = '{"type": "status", "stage": "init"}\n{"type": "result", "message": "Done"}';
      const result = AICLIValidationService.parseStreamJsonOutput(input);
      
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].type, 'status');
      assert.strictEqual(result[1].type, 'result');
    });

    it('should handle empty lines', () => {
      const input = '{"type": "status"}\n\n{"type": "result"}\n';
      const result = AICLIValidationService.parseStreamJsonOutput(input);
      
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].type, 'status');
      assert.strictEqual(result[1].type, 'result');
    });

    it('should handle lines with only whitespace', () => {
      const input = '{"type": "status"}\n   \n{"type": "result"}';
      const result = AICLIValidationService.parseStreamJsonOutput(input);
      
      assert.strictEqual(result.length, 2);
    });

    it('should fall back to object extraction for malformed lines', () => {
      const input = 'invalid json\n{"type": "result"}';
      const result = AICLIValidationService.parseStreamJsonOutput(input);
      
      // Should extract the valid JSON object, skip the invalid line
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].type, 'result');
    });
  });

  describe('extractCompleteObjectsFromLine', () => {
    it('should extract single complete object', () => {
      const line = '{"type": "result", "data": "test"}';
      const result = AICLIValidationService.extractCompleteObjectsFromLine(line);
      
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].type, 'result');
      assert.strictEqual(result[0].data, 'test');
    });

    it('should extract multiple complete objects from single line', () => {
      const line = '{"type": "status"}{"type": "result"}';
      const result = AICLIValidationService.extractCompleteObjectsFromLine(line);
      
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].type, 'status');
      assert.strictEqual(result[1].type, 'result');
    });

    it('should handle nested objects', () => {
      const line = '{"type": "result", "data": {"nested": "value"}}';
      const result = AICLIValidationService.extractCompleteObjectsFromLine(line);
      
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].type, 'result');
      assert.strictEqual(result[0].data.nested, 'value');
    });

    it('should handle strings with escaped quotes', () => {
      const line = '{"message": "He said \\"hello\\" to me"}';
      const result = AICLIValidationService.extractCompleteObjectsFromLine(line);
      
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].message, 'He said "hello" to me');
    });

    it('should ignore incomplete objects', () => {
      const line = '{"type": "incomplete"';
      const result = AICLIValidationService.extractCompleteObjectsFromLine(line);
      
      assert.strictEqual(result.length, 0);
    });

    it('should extract valid objects and ignore invalid ones', () => {
      const line = '{"valid": true}{"invalid": }{"another": "valid"}';
      const result = AICLIValidationService.extractCompleteObjectsFromLine(line);
      
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].valid, true);
      assert.strictEqual(result[1].another, 'valid');
    });

    it('should return empty array for non-object content', () => {
      const line = 'this is not json';
      const result = AICLIValidationService.extractCompleteObjectsFromLine(line);
      
      assert.strictEqual(result.length, 0);
    });
  });

  describe('extractLastCompleteJSON', () => {
    it('should extract complete JSON object', () => {
      const truncatedJson = '{"type": "result", "message": "complete"}';
      const result = AICLIValidationService.extractLastCompleteJSON(truncatedJson);
      
      assert.ok(result);
      assert.strictEqual(result.type, 'result');
      assert.strictEqual(result.message, 'complete');
    });

    it('should return null for incomplete JSON', () => {
      const truncatedJson = '{"type": "result", "message": "incom';
      const result = AICLIValidationService.extractLastCompleteJSON(truncatedJson);
      
      assert.strictEqual(result, null);
    });

    it('should extract from array format', () => {
      const truncatedJson = '[{"type": "status"}, {"type": "result"}]';
      const result = AICLIValidationService.extractLastCompleteJSON(truncatedJson);
      
      assert.ok(result);
      // Should return the complete array
      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 2);
    });

    it('should handle nested structures', () => {
      const truncatedJson = '{"data": {"nested": {"deep": "value"}}}';
      const result = AICLIValidationService.extractLastCompleteJSON(truncatedJson);
      
      assert.ok(result);
      assert.strictEqual(result.data.nested.deep, 'value');
    });

    it('should return null for empty input', () => {
      assert.strictEqual(AICLIValidationService.extractLastCompleteJSON(''), null);
      assert.strictEqual(AICLIValidationService.extractLastCompleteJSON(null), null);
      assert.strictEqual(AICLIValidationService.extractLastCompleteJSON(undefined), null);
    });
  });

  describe('findLastCompleteJSONStart', () => {
    it('should find start of complete object', () => {
      const text = 'prefix{"type": "result"}suffix';
      const start = AICLIValidationService.findLastCompleteJSONStart(text);
      
      assert.strictEqual(start, 6); // Position of '{'
    });

    it('should find start of complete array', () => {
      const text = 'prefix[{"type": "result"}]suffix';
      const start = AICLIValidationService.findLastCompleteJSONStart(text);
      
      assert.strictEqual(start, 6); // Position of '['
    });

    it('should return -1 for no complete structure', () => {
      const text = '{"incomplete": "object"';
      const start = AICLIValidationService.findLastCompleteJSONStart(text);
      
      assert.strictEqual(start, -1);
    });

    it('should handle nested structures', () => {
      const text = '{"outer": {"inner": "value"}}';
      const start = AICLIValidationService.findLastCompleteJSONStart(text);
      
      assert.strictEqual(start, 0); // Start of outermost object
    });

    it('should ignore strings with braces', () => {
      const text = '{"message": "contains { braces }", "type": "result"}';
      const start = AICLIValidationService.findLastCompleteJSONStart(text);
      
      assert.strictEqual(start, 0);
    });
  });

  describe('extractCompleteObjectsFromArray', () => {
    it('should extract objects from array format', () => {
      const arrayText = '[{"type": "status"}, {"type": "result"}]';
      const result = AICLIValidationService.extractCompleteObjectsFromArray(arrayText);
      
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].type, 'status');
      assert.strictEqual(result[1].type, 'result');
    });

    it('should handle nested objects in array', () => {
      const arrayText = '[{"data": {"nested": "value"}}]';
      const result = AICLIValidationService.extractCompleteObjectsFromArray(arrayText);
      
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].data.nested, 'value');
    });

    it('should ignore incomplete objects', () => {
      const arrayText = '[{"complete": true}, {"incomplete": ';
      const result = AICLIValidationService.extractCompleteObjectsFromArray(arrayText);
      
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].complete, true);
    });

    it('should handle strings with special characters', () => {
      const arrayText = '[{"message": "String with { } and [ ] chars"}]';
      const result = AICLIValidationService.extractCompleteObjectsFromArray(arrayText);
      
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].message, 'String with { } and [ ] chars');
    });

    it('should return empty array for invalid input', () => {
      assert.strictEqual(AICLIValidationService.extractCompleteObjectsFromArray('not an array').length, 0);
      assert.strictEqual(AICLIValidationService.extractCompleteObjectsFromArray('').length, 0);
    });

    it('should handle empty array', () => {
      const result = AICLIValidationService.extractCompleteObjectsFromArray('[]');
      assert.strictEqual(result.length, 0);
    });
  });
});