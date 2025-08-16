/**
 * Parser for Claude's structured output
 * Detects and extracts user-facing content from Claude's JSON responses
 */

/**
 * Attempts to parse Claude's JSON output and extract the user-facing content
 * @param {string} text - Raw text that might contain JSON
 * @returns {Object|null} Parsed result with { isJson: boolean, content: string, metadata: Object }
 */
export function parseClaudeOutput(text) {
  if (!text || typeof text !== 'string') {
    return null;
  }

  // Try to detect JSON blocks in the text
  const jsonMatches = text.match(/\{[\s\S]*\}/g);
  if (!jsonMatches) {
    return null;
  }

  for (const jsonMatch of jsonMatches) {
    try {
      const parsed = JSON.parse(jsonMatch);

      // Check if this looks like Claude's structured output
      if (isClaudeStructuredOutput(parsed)) {
        // Extract the user-facing content
        const content = extractUserContent(parsed);
        return {
          isJson: true,
          content,
          metadata: {
            type: parsed.type || 'unknown',
            hasThinking: !!parsed.thinking,
            hasToolUse: !!(parsed.tool_calls || parsed.tools_used),
          },
        };
      }
    } catch (e) {
      // Not valid JSON, continue
    }
  }

  return null;
}

/**
 * Check if the parsed object looks like Claude's structured output
 */
function isClaudeStructuredOutput(obj) {
  // Common patterns in Claude's JSON output
  return (
    obj &&
    typeof obj === 'object' &&
    // Has content field (main response)
    (obj.content ||
      // Has result field
      obj.result ||
      // Has answer field
      obj.answer ||
      // Has thinking/reasoning fields
      obj.thinking ||
      obj.reasoning ||
      // Has tool-related fields
      obj.tool_calls ||
      obj.tools_used ||
      // Has type field indicating structured response
      obj.type)
  );
}

/**
 * Extract user-facing content from Claude's structured output
 */
function extractUserContent(parsed) {
  // Priority order for content extraction
  if (parsed.content) {
    return parsed.content;
  }

  if (parsed.result) {
    return parsed.result;
  }

  if (parsed.answer) {
    return parsed.answer;
  }

  // If there's a message field
  if (parsed.message) {
    return parsed.message;
  }

  // If there's text field
  if (parsed.text) {
    return parsed.text;
  }

  // If there's a response field
  if (parsed.response) {
    return parsed.response;
  }

  // For tool use, create a summary
  if (parsed.tool_calls || parsed.tools_used) {
    const tools = parsed.tool_calls || parsed.tools_used;
    if (Array.isArray(tools) && tools.length > 0) {
      return `Using tools: ${tools.map((t) => t.name || t.tool).join(', ')}`;
    }
  }

  // Fallback: try to find any string content
  for (const key of Object.keys(parsed)) {
    if (
      typeof parsed[key] === 'string' &&
      key !== 'thinking' &&
      key !== 'reasoning' &&
      key !== 'type' &&
      parsed[key].length > 0
    ) {
      return parsed[key];
    }
  }

  return null;
}

/**
 * Clean up text by removing JSON blocks that have been parsed
 */
export function removeJsonFromText(text, jsonContent) {
  if (!text || !jsonContent) {
    return text;
  }

  // Escape special regex characters in the JSON content
  const escaped = jsonContent.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return text.replace(new RegExp(escaped, 'g'), '').trim();
}
