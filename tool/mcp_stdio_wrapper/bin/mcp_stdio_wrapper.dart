import 'dart:convert';
import 'dart:io';

import 'package:mcp_stdio_wrapper/mcp_stdio_wrapper.dart';

Future<void> main() async {
  final error = envError(Platform.environment);
  if (error != null) {
    stderr.writeln('mcp_stdio_wrapper: $error');
    exit(exitConfig);
  }
  final endpoint = Uri.parse(Platform.environment['DAYSPARK_MCP_URL']!);
  final token = Platform.environment['DAYSPARK_MCP_TOKEN']!;
  final client = HttpClient();

  Future<HttpPostResult> post(String body) async {
    final request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.add(utf8.encode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return HttpPostResult(response.statusCode, text);
  }

  final lines = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await runBridge(
    lines: lines,
    writeLine: (String line) => stdout.writeln(line),
    post: post,
  );
  await stdout.flush();
  // HttpClient.close is synchronous (returns void), not a Future.
  client.close(force: true);
}
