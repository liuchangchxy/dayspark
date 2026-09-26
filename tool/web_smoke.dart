// Web 产物白屏冒烟：静态服务 build/web → headless Chrome(CDP) → 截图 → 数颜色。
// 纯 Dart 零依赖（dart:io 的 HttpServer / WebSocket / ZLibCodec），无需 npm。
//
// 判据分两层（v0.25.0 白屏事故的机械兜底，见 DECISIONS.md / CONSTRAINTS.md）：
//  1. 正身信号（先）——产物目录自检（不是 Flutter web 产物当场拒）；主文档**仅主框架**
//     状态 2xx/304；Flutter 主脚本（main.dart.* / flutter_bootstrap.js）加载成功；
//     宿主元素存在（Flutter 换渲染器/元素名时用 --allow-missing-host 放行）。
//  2. 白屏判据（后）——截图唯一颜色数 <= 1，或"与主色差异 > 8 的像素占比" < minInkRatio。
//     任一层不过即退出码 1。
//
// 用法：dart run tool/web_smoke.dart --dir build/web [--chrome <path>]
//      [--timeout 30] [--settle 3] [--min-colors 2] [--min-ink 0.005]
//      [--fail-on-errors] [--keep-temp] [--allow-missing-host] [--screenshot <png>]
// CI：`.github/workflows/{ci,release}.yml` 的 build-web job 在 flutter build web 后调用。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int kDefaultMinColors = 2;
const double kDefaultMinInkRatio = 0.005;
const int _channelTolerance = 8;

// ---------------------------------------------------------------- PNG 解码

class PngImage {
  PngImage(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;

  int get pixelCount => width * height;
}

int _u32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

const List<int> _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// 解码 8 位非隔行 PNG（灰/RGB/灰+A/RGBA）。其它形态明确报错，不静默降级。
PngImage decodePng(Uint8List bytes) {
  if (bytes.length < 8) {
    throw const FormatException('PNG 太短');
  }
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _pngSignature[i]) {
      throw const FormatException('不是 PNG（签名不匹配）');
    }
  }

  int? width;
  int? height;
  int? bitDepth;
  int? colorType;
  var interlace = 0;
  final idat = BytesBuilder();

  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = _u32(bytes, offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    final dataStart = offset + 8;
    if (dataStart + length + 4 > bytes.length) {
      throw FormatException('PNG chunk $type 被截断');
    }
    if (type == 'IHDR') {
      if (length < 13) {
        throw FormatException('IHDR 长度 $length < 13');
      }
      width = _u32(bytes, dataStart);
      height = _u32(bytes, dataStart + 4);
      bitDepth = bytes[dataStart + 8];
      colorType = bytes[dataStart + 9];
      interlace = bytes[dataStart + 12];
    } else if (type == 'IDAT') {
      idat.add(bytes.sublist(dataStart, dataStart + length));
    } else if (type == 'IEND') {
      break;
    }
    offset = dataStart + length + 4;
  }

  if (width == null ||
      height == null ||
      bitDepth == null ||
      colorType == null) {
    throw const FormatException('PNG 缺 IHDR');
  }
  if (bitDepth != 8) {
    throw FormatException('只支持 8 位深，收到 $bitDepth');
  }
  if (interlace != 0) {
    throw const FormatException('不支持隔行 PNG');
  }
  final channels = switch (colorType) {
    0 => 1,
    2 => 3,
    4 => 2,
    6 => 4,
    _ => throw FormatException('不支持的 colorType $colorType（调色板/16 位未实现）'),
  };

  final raw = Uint8List.fromList(ZLibCodec().decode(idat.takeBytes()));
  final stride = width * channels;
  if (raw.length < (stride + 1) * height) {
    throw FormatException(
      'PNG 像素数据不足：${raw.length} < ${(stride + 1) * height}',
    );
  }

  final rgba = Uint8List(width * height * 4);
  final previous = Uint8List(stride);
  final current = Uint8List(stride);
  var pos = 0;
  for (var y = 0; y < height; y++) {
    final filter = raw[pos++];
    current.setRange(0, stride, raw, pos);
    pos += stride;
    for (var i = 0; i < stride; i++) {
      final a = i >= channels ? current[i - channels] : 0;
      final b = previous[i];
      final c = i >= channels ? previous[i - channels] : 0;
      final x = current[i];
      final value = switch (filter) {
        0 => x,
        1 => x + a,
        2 => x + b,
        3 => x + ((a + b) >> 1),
        4 => x + _paeth(a, b, c),
        _ => throw FormatException('未知 PNG 过滤器 $filter'),
      };
      current[i] = value & 0xFF;
    }
    for (var x = 0; x < width; x++) {
      final src = x * channels;
      final dst = (y * width + x) * 4;
      switch (channels) {
        case 1:
          final g = current[src];
          rgba[dst] = g;
          rgba[dst + 1] = g;
          rgba[dst + 2] = g;
          rgba[dst + 3] = 255;
        case 2:
          final g = current[src];
          rgba[dst] = g;
          rgba[dst + 1] = g;
          rgba[dst + 2] = g;
          rgba[dst + 3] = current[src + 1];
        case 3:
          rgba[dst] = current[src];
          rgba[dst + 1] = current[src + 1];
          rgba[dst + 2] = current[src + 2];
          rgba[dst + 3] = 255;
        case 4:
          rgba[dst] = current[src];
          rgba[dst + 1] = current[src + 1];
          rgba[dst + 2] = current[src + 2];
          rgba[dst + 3] = current[src + 3];
      }
    }
    previous.setRange(0, stride, current);
  }
  return PngImage(width, height, rgba);
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

// ---------------------------------------------------------------- 判据

class ImageStats {
  ImageStats({
    required this.uniqueColors,
    required this.inkRatio,
    required this.samples,
    required this.modalColor,
  });

  final int uniqueColors;
  final double inkRatio;
  final int samples;
  final int modalColor;
}

/// 采样统计：唯一颜色数 + 相对主色的"着墨比"（差异 > 8 的像素占比）。
ImageStats analyzeImage(PngImage image, {int maxSamples = 200000}) {
  final total = image.pixelCount;
  final step = total <= maxSamples ? 1 : (total / maxSamples).ceil();
  final counts = <int, int>{};
  var samples = 0;
  for (var i = 0; i < total; i += step) {
    final p = i * 4;
    final color =
        (image.rgba[p] << 16) | (image.rgba[p + 1] << 8) | image.rgba[p + 2];
    counts[color] = (counts[color] ?? 0) + 1;
    samples++;
  }
  var modalColor = 0;
  var modalCount = 0;
  counts.forEach((color, count) {
    if (count > modalCount) {
      modalCount = count;
      modalColor = color;
    }
  });
  final mr = (modalColor >> 16) & 0xFF;
  final mg = (modalColor >> 8) & 0xFF;
  final mb = modalColor & 0xFF;
  var ink = 0;
  for (var i = 0; i < total; i += step) {
    final p = i * 4;
    if ((image.rgba[p] - mr).abs() > _channelTolerance ||
        (image.rgba[p + 1] - mg).abs() > _channelTolerance ||
        (image.rgba[p + 2] - mb).abs() > _channelTolerance) {
      ink++;
    }
  }
  return ImageStats(
    uniqueColors: counts.length,
    inkRatio: samples == 0 ? 0 : ink / samples,
    samples: samples,
    modalColor: modalColor,
  );
}

/// 白屏判定：返回 null 表示通过，否则返回人话失败原因。
String? judge(
  ImageStats stats, {
  int minColors = kDefaultMinColors,
  double minInkRatio = kDefaultMinInkRatio,
}) {
  if (stats.samples == 0) return '截图为空（0 像素）';
  if (stats.uniqueColors < minColors) {
    return '白屏：唯一颜色数 ${stats.uniqueColors} < $minColors';
  }
  if (stats.inkRatio < minInkRatio) {
    return '白屏：着墨比 ${(stats.inkRatio * 100).toStringAsFixed(3)}% < '
        '${(minInkRatio * 100).toStringAsFixed(3)}%（页面几乎全是主色 '
        '#${stats.modalColor.toRadixString(16).padLeft(6, '0')}）';
  }
  return null;
}

// ---------------------------------------------------------------- 产物自检

const List<String> _flutterMainCandidates = <String>[
  'main.dart.js',
  'main.dart.mjs',
  'main.dart.wasm',
];

/// 目录必须是 Flutter web 产物 —— 否则"根本不是我们的 App"的页面会被判成
/// "不白 → PASS"（2026-09-26 审查发现：把宿主探测降级成诊断后，502 占位页会通过）。
/// 2xx 或 304 都算"拿到了"（304 = 协商缓存命中，内容仍是我们的）。
bool isOkStatus(int status) => (status >= 200 && status < 300) || status == 304;

String? verifyFlutterBuild(String dir) {
  final indexPath = '$dir/index.html';
  if (!File(indexPath).existsSync()) {
    return '$dir 里没有 index.html：不是 web 产物目录';
  }
  final html = File(indexPath).readAsStringSync();
  if (!html.contains('flutter_bootstrap.js') && !html.contains('flutter.js')) {
    return 'index.html 里没有 Flutter 引导脚本（flutter_bootstrap.js / flutter.js）：'
        '$dir 不是 Flutter web 产物';
  }
  final mains = _flutterMainCandidates
      .where((name) => File('$dir/$name').existsSync())
      .toList();
  if (mains.isEmpty) {
    return '$dir 里没有 ${_flutterMainCandidates.join(' / ')}：不是 Flutter web 产物';
  }
  return null;
}

// ---------------------------------------------------------------- 静态服务

const Map<String, String> _mimeTypes = <String, String>{
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  // Flutter web release 实际会请求但这里不给 MIME 会退化成 octet-stream 的形态
  '.bin': 'application/octet-stream',
  '.frag': 'application/octet-stream',
  '.vert': 'application/octet-stream',
  '.mp3': 'audio/mpeg',
  '.symbols': 'text/plain; charset=utf-8',
};

Future<HttpServer> serveDir(String root) async {
  final rootDir = Directory(root).absolute;
  final rootPrefix = '${rootDir.path}${Platform.pathSeparator}';
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    // 非法 UTF-8 转义（如 `/%c0%ae`）在 `pathSegments` 解码时抛，而这抛在 HttpServer
    // 自己的 zone 里 —— 不接住就是整进程带栈退出，连判据都不会印出来。
    final List<String> segments;
    try {
      segments = request.uri.pathSegments;
    } on Object {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    var path = '/${segments.join('/')}';
    if (path.endsWith('/')) path = '${path}index.html';
    final file = File('${rootDir.path}$path');
    // `%2e%2e` 解码成 `..`；`..%2f` 更阴：pathSegments 把 `%2f` 解成一个**段内**斜杠，
    // 于是段是 `../webX/secret.txt`（既非 `.` 也非 `..`），join 回路径后又变回穿越。
    // 而 `File.absolute` 不做 `..` 归一化，前缀比较因此挡不住 —— 故三段全拒。
    final hasDotSegment = segments.any(
      (segment) =>
          segment == '.' ||
          segment == '..' ||
          segment.contains('/') ||
          segment.contains(r'\'),
    );
    if (hasDotSegment ||
        !file.absolute.path.startsWith(rootPrefix) ||
        !file.existsSync() ||
        FileSystemEntity.isDirectorySync(file.path)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final dot = file.path.lastIndexOf('.');
    final ext = dot == -1 ? '' : file.path.substring(dot).toLowerCase();
    request.response.headers.contentType = ContentType.parse(
      _mimeTypes[ext] ?? 'application/octet-stream',
    );
    request.response.headers.set('cache-control', 'no-store');
    await request.response.addStream(file.openRead());
    await request.response.close();
  });
  return server;
}

// ---------------------------------------------------------------- CDP

class CdpClient {
  CdpClient._(this._socket) {
    _socket.listen(
      _onMessage,
      onDone: _onDone,
      onError: (Object e) => _onDone(),
    );
  }

  final WebSocket _socket;
  final Map<int, Completer<Map<String, dynamic>>> _pending =
      <int, Completer<Map<String, dynamic>>>{};
  final List<void Function(String, Map<String, dynamic>)> _listeners =
      <void Function(String, Map<String, dynamic>)>[];
  int _nextId = 1;

  static Future<CdpClient> connect(String url) async {
    final socket = await WebSocket.connect(url);
    return CdpClient._(socket);
  }

  void on(String method, void Function(Map<String, dynamic>) handler) {
    _listeners.add((m, params) {
      if (m == method) handler(params);
    });
  }

  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode(<String, dynamic>{
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      }),
    );
    return completer.future;
  }

  void _onMessage(dynamic data) {
    final decoded = jsonDecode(data as String);
    if (decoded is! Map<String, dynamic>) return;
    final id = decoded['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null || completer.isCompleted) return;
      final error = decoded['error'];
      if (error != null) {
        completer.completeError(StateError('CDP $error'));
      } else {
        completer.complete(
          (decoded['result'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
      }
      return;
    }
    final method = decoded['method'];
    if (method is String) {
      final params =
          (decoded['params'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      for (final listener in _listeners) {
        listener(method, params);
      }
    }
  }

  void _onDone() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Chrome 连接已断'));
      }
    }
    _pending.clear();
  }

  Future<void> close() => _socket.close();
}

// ---------------------------------------------------------------- Chrome

const List<String> _chromeCandidates = <String>[
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
  '/opt/google/chrome/chrome',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
];

String? findChrome({String? explicit}) {
  if (explicit != null && explicit.isNotEmpty) {
    return File(explicit).existsSync() ? explicit : null;
  }
  final env = Platform.environment['CHROME_EXECUTABLE'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  for (final name in <String>[
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
  ]) {
    final found = _which(name);
    if (found != null) return found;
  }
  for (final path in _chromeCandidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

String? _which(String name) {
  final result = Process.runSync('which', <String>[name]);
  if (result.exitCode != 0) return null;
  final path = (result.stdout as String).trim();
  return path.isEmpty ? null : path;
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

// ---------------------------------------------------------------- 主流程

class SmokeOutcome {
  SmokeOutcome({
    required this.stats,
    required this.failure,
    required this.errors,
    required this.screenshotPath,
  });

  final ImageStats? stats;
  final String? failure;
  final List<String> errors;
  final String? screenshotPath;
}

class SmokeOptions {
  SmokeOptions({
    required this.dir,
    this.chrome,
    this.timeout = const Duration(seconds: 30),
    this.settle = const Duration(seconds: 3),
    this.minColors = kDefaultMinColors,
    this.minInkRatio = kDefaultMinInkRatio,
    this.failOnErrors = false,
    this.keepTemp = false,
    this.allowMissingHost = false,
    this.screenshotPath,
  });

  final String dir;
  final String? chrome;
  final Duration timeout;
  final Duration settle;
  final int minColors;
  final double minInkRatio;
  final bool failOnErrors;
  final bool keepTemp;

  /// Flutter 改渲染器/宿主元素名时用它放行（默认要求宿主元素存在）。
  final bool allowMissingHost;
  final String? screenshotPath;
}

Future<SmokeOutcome> runSmoke(
  SmokeOptions options, {
  void Function(String) log = print,
}) async {
  final errors = <String>[];
  final buildError = verifyFlutterBuild(options.dir);
  if (buildError != null) {
    return SmokeOutcome(
      stats: null,
      failure: buildError,
      errors: errors,
      screenshotPath: null,
    );
  }
  final chrome = findChrome(explicit: options.chrome);
  if (chrome == null) {
    return SmokeOutcome(
      stats: null,
      failure: '找不到 Chrome：请设 CHROME_EXECUTABLE 或用 --chrome 指定',
      errors: errors,
      screenshotPath: null,
    );
  }

  final server = await serveDir(options.dir);
  final appPort = server.port;
  final debugPort = await _freePort();
  final tempDir = Directory.systemTemp.createTempSync('dayspark_web_smoke');
  final chromeLog = StringBuffer();
  Process? process;
  CdpClient? client;
  String? screenshotPath;
  try {
    process = await Process.start(chrome, <String>[
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--hide-scrollbars',
      '--no-first-run',
      '--no-default-browser-check',
      '--user-data-dir=${tempDir.path}',
      '--remote-debugging-port=$debugPort',
      'about:blank',
    ]);
    process.stdout.transform(utf8.decoder).listen(chromeLog.write);
    process.stderr.transform(utf8.decoder).listen(chromeLog.write);

    final wsUrl = await _waitForPageTarget(debugPort, options.timeout);
    if (wsUrl == null) {
      return SmokeOutcome(
        stats: null,
        failure:
            'Chrome 未在 ${options.timeout.inSeconds}s 内就绪'
            '（--headless=new 不被该版本支持？）\nChrome 输出：\n$chromeLog',
        errors: errors,
        screenshotPath: null,
      );
    }
    client = await CdpClient.connect(wsUrl);
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('Log.enable');
    await client.send('Network.enable');
    final documentStatuses = <int>[];
    var flutterPayloadOk = false;
    // 只有**主框架**的 Document 才算数：`type == 'Document'` 也覆盖 iframe 文档，
    // 否则一个 200 的子框架能替 500 的主文档"通过"。
    String? mainFrameId;
    client.on('Network.responseReceived', (params) {
      final response =
          params['response'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final url = response['url'] as String? ?? '';
      final status = response['status'] as int? ?? 0;
      final frameId = params['frameId'] as String?;
      if (params['type'] == 'Document' &&
          (mainFrameId == null || frameId == mainFrameId)) {
        documentStatuses.add(status);
      }
      final isFlutterPayload =
          _flutterMainCandidates.any(url.contains) ||
          url.contains('flutter_bootstrap.js');
      if (isFlutterPayload && isOkStatus(status)) {
        flutterPayloadOk = true;
      }
    });
    await client.send('Emulation.setDeviceMetricsOverride', <String, dynamic>{
      'width': 1280,
      'height': 900,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    client.on('Runtime.consoleAPICalled', (params) {
      if (params['type'] != 'error') return;
      final args = (params['args'] as List<dynamic>? ?? <dynamic>[])
          .map((arg) {
            final map = arg as Map<String, dynamic>;
            return map['value'] ?? map['description'];
          })
          .join(' ');
      errors.add('console.error: $args');
    });
    client.on('Runtime.exceptionThrown', (params) {
      final details =
          params['exceptionDetails'] as Map<String, dynamic>? ??
          <String, dynamic>{};
      final description =
          ((details['exception'] as Map<String, dynamic>?)?['description']
              as String?) ??
          details['text'] ??
          'unknown';
      errors.add('uncaught: $description');
    });
    client.on('Log.entryAdded', (params) {
      final entry =
          params['entry'] as Map<String, dynamic>? ?? <String, dynamic>{};
      if (entry['level'] != 'error') return;
      errors.add('log: ${entry['text']}');
    });

    final loaded = Completer<void>();
    client.on('Page.loadEventFired', (_) {
      if (!loaded.isCompleted) loaded.complete();
    });
    final navigation = await client.send('Page.navigate', <String, dynamic>{
      'url': 'http://127.0.0.1:$appPort/index.html',
    });
    mainFrameId = navigation['frameId'] as String?;
    final navigationError = navigation['errorText'];
    if (navigationError != null) {
      return SmokeOutcome(
        stats: null,
        failure: '页面导航失败：$navigationError',
        errors: errors,
        screenshotPath: null,
      );
    }
    await loaded.future.timeout(
      options.timeout,
      onTimeout: () => log('警告：等 Page.loadEventFired 超时，继续尝试截图'),
    );

    // 正向身份信号：页面必须是"我们的 App"，而不只是"不白"。颜色判据单独用会放过
    // 任何有内容的非 Flutter 页面（审查实测：502 占位页 PASS）。
    if (documentStatuses.isEmpty) {
      // 实测在无头管线里恒定可观测（about:blank 不发 Document 响应；SW/磁盘缓存不抑制），
      // 观测不到只可能是 CDP 行为变了 —— 那种情况下判据已悄悄降级，拒绝给绿。
      return SmokeOutcome(
        stats: null,
        failure: '没观察到主文档响应 —— CDP 的 Network 事件行为可能变了，判据已降级',
        errors: errors,
        screenshotPath: null,
      );
    }
    if (!documentStatuses.any(isOkStatus)) {
      return SmokeOutcome(
        stats: null,
        failure: '主文档 HTTP 状态 ${documentStatuses.join('/')}（非 2xx/304）',
        errors: errors,
        screenshotPath: null,
      );
    }
    if (!flutterPayloadOk) {
      return SmokeOutcome(
        stats: null,
        failure:
            '没有成功加载 Flutter 主脚本（${_flutterMainCandidates.join(' / ')} / '
            'flutter_bootstrap.js）—— 这个页面不是我们的 App。'
            '若确认是 Flutter 换了产物形态，请同步 _flutterMainCandidates',
        errors: errors,
        screenshotPath: null,
      );
    }
    final hostReady = await _waitForFlutterHost(client, options.timeout, log);
    if (!hostReady && !options.allowMissingHost) {
      return SmokeOutcome(
        stats: null,
        failure:
            '未探测到 Flutter 宿主元素（flt-glass-pane / flutter-view / flt-scene-host）。'
            '若确认是 Flutter 换了渲染器/元素名，用 --allow-missing-host 放行',
        errors: errors,
        screenshotPath: null,
      );
    }
    await Future<void>.delayed(options.settle);

    final shot = await client.send('Page.captureScreenshot', <String, dynamic>{
      'format': 'png',
    });
    final bytes = base64Decode(shot['data'] as String);
    if (options.screenshotPath != null) {
      File(options.screenshotPath!).writeAsBytesSync(bytes);
      screenshotPath = options.screenshotPath;
    }
    final image = decodePng(bytes);
    final stats = analyzeImage(image);
    return SmokeOutcome(
      stats: stats,
      failure: judge(
        stats,
        minColors: options.minColors,
        minInkRatio: options.minInkRatio,
      ),
      errors: errors,
      screenshotPath: screenshotPath,
    );
  } on Object catch (e, stack) {
    return SmokeOutcome(
      stats: null,
      failure: '冒烟执行异常：$e\n$stack',
      errors: errors,
      screenshotPath: screenshotPath,
    );
  } finally {
    await client?.close();
    process?.kill(ProcessSignal.sigkill);
    await server.close(force: true);
    if (!options.keepTemp) {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // 临时目录清理失败不影响结论
      }
    }
  }
}

Future<String?> _waitForPageTarget(int debugPort, Duration timeout) async {
  final client = HttpClient();
  final deadline = DateTime.now().add(timeout);
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$debugPort/json/list'),
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final targets = jsonDecode(body) as List<dynamic>;
        for (final target in targets) {
          final map = target as Map<String, dynamic>;
          if (map['type'] == 'page' && map['webSocketDebuggerUrl'] != null) {
            return map['webSocketDebuggerUrl'] as String;
          }
        }
      } on Object {
        // Chrome 还没起来，继续等
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  } finally {
    client.close(force: true);
  }
  return null;
}

Future<bool> _waitForFlutterHost(
  CdpClient client,
  Duration timeout,
  void Function(String) log,
) async {
  const expression =
      "document.querySelector('flt-glass-pane, flutter-view, flt-scene-host') !== null";
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final result = await client.send('Runtime.evaluate', <String, dynamic>{
        'expression': expression,
        'returnByValue': true,
      });
      final value = (result['result'] as Map<String, dynamic>?)?['value'];
      if (value == true) return true;
    } on Object catch (e) {
      log('探测 Flutter 宿主失败：$e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) {
    stderr.writeln('用法见文件头注释；至少需要 --dir <web 产物目录>');
    exit(2);
  }
  final outcome = await runSmoke(options);
  if (outcome.stats != null) {
    final stats = outcome.stats!;
    stdout.writeln(
      'web smoke: ${stats.samples} 采样 / 唯一颜色 ${stats.uniqueColors} / '
      '着墨比 ${(stats.inkRatio * 100).toStringAsFixed(2)}% / '
      '主色 #${stats.modalColor.toRadixString(16).padLeft(6, '0')}',
    );
  }
  if (outcome.screenshotPath != null) {
    stdout.writeln('截图：${outcome.screenshotPath}');
  }
  if (outcome.errors.isNotEmpty) {
    stdout.writeln('页面错误 ${outcome.errors.length} 条：');
    for (final error in outcome.errors.take(20)) {
      stdout.writeln('  - $error');
    }
  }
  if (outcome.failure != null) {
    stderr.writeln('FAIL: ${outcome.failure}');
    exit(1);
  }
  if (options.failOnErrors && outcome.errors.isNotEmpty) {
    stderr.writeln('FAIL: 页面报错 ${outcome.errors.length} 条（--fail-on-errors）');
    exit(1);
  }
  stdout.writeln('PASS: 页面有渲染内容');
}

SmokeOptions? _parseArgs(List<String> args) {
  String? dir;
  String? chrome;
  String? screenshot;
  var timeout = 30;
  var settle = 3;
  var minColors = kDefaultMinColors;
  var minInk = kDefaultMinInkRatio;
  var failOnErrors = false;
  var keepTemp = false;
  var allowMissingHost = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String? next() => i + 1 < args.length ? args[++i] : null;
    switch (arg) {
      case '--dir':
        dir = next();
      case '--chrome':
        chrome = next();
      case '--screenshot':
        screenshot = next();
      case '--timeout':
        timeout = int.tryParse(next() ?? '') ?? timeout;
      case '--settle':
        settle = int.tryParse(next() ?? '') ?? settle;
      case '--min-colors':
        minColors = int.tryParse(next() ?? '') ?? minColors;
      case '--min-ink':
        minInk = double.tryParse(next() ?? '') ?? minInk;
      case '--fail-on-errors':
        failOnErrors = true;
      case '--allow-missing-host':
        allowMissingHost = true;
      case '--keep-temp':
        keepTemp = true;
      default:
        stderr.writeln('未知参数：$arg');
        return null;
    }
  }
  if (dir == null || !Directory(dir).existsSync()) {
    stderr.writeln('--dir 必须是存在的目录（Web 产物）');
    return null;
  }
  return SmokeOptions(
    dir: dir,
    chrome: chrome,
    timeout: Duration(seconds: timeout),
    settle: Duration(seconds: settle),
    minColors: minColors,
    minInkRatio: minInk,
    failOnErrors: failOnErrors,
    keepTemp: keepTemp,
    allowMissingHost: allowMissingHost,
    screenshotPath: screenshot,
  );
}
