import '../mcp/endpoint.dart';
import '../mcp/schemas.dart';

// The real MCP scope gate (T2 seam implementation). Reads the token's
// `scope` claim off the McpScopeRequest:
//
// - session tokens (login/refresh, no claim) never reach here as null —
//   /auth tokens always mint mcp:read mcp:write, so claimless means a
//   hand-built JWT and fails closed;
// - read-only tools and resources/* require mcp:read;
// - write/trash/batch tools require mcp:write;
// - mcp:write does NOT imply mcp:read (and vice versa) — the consent page
//   grants each scope explicitly.
ScopeDecision? mcpScopeGate(McpScopeRequest request) {
  final scope = request.scope;
  if (scope == null) {
    return const ScopeDecision(
      mcpCodeForbiddenScope,
      'token carries no scope claim',
      hintForbiddenScope,
    );
  }
  final granted = scope
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toSet();
  final required = request.tool.startsWith('resources/')
      ? mcpScopeRead
      : (request.readOnly ? mcpScopeRead : mcpScopeWrite);
  if (granted.contains(required)) {
    return null;
  }
  return ScopeDecision(
    mcpCodeForbiddenScope,
    'token scope "$scope" lacks $required',
    hintForbiddenScope,
  );
}
