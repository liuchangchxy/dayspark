// web_smoke 的判据自证：白屏断言必须"纯白→红、有内容→绿"，否则等于没断言。
// 两条独立证据链，缺一不可：
//  (1) **外部金标**——由本仓库之外的实现（python3 + 标准库 zlib）生成的 PNG 字节 +
//      其源像素的期望 RGBA 字面量（见 `_goldenA`/`_goldenB`）。金标不依赖本文件的
//      编码器，故解码器与编码器"共同错成一套"时仍然会红（自证向量陷阱的解药）。
//  (2) 本文件手写编码器的 5 种过滤器往返（覆盖 filter 1–4 的每条路径）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/web_smoke.dart';

// 外部金标 A：5x5 RGB（colorType 2），每行依次用 filter 0/1/2/3/4。
// 源像素 (x,y) = ((x*40+7)%256, (y*50+3)%256, (x*10+y*20)%256)。
const String _goldenABase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAIAAAACDbGyAAAANUlEQVR42mNgZ2bQZ+YKZxapZ5Zb'
    'zqzByG4qosHABUdMDEYiyIiZJU1DRJIfjlhAwgxccAQANy0Gl32OIUAAAAAASUVORK5CYII=';
const List<int> _goldenARgba = <int>[
  7, 3, 0, 255, 47, 3, 10, 255, 87, 3, 20, 255, 127, 3, 30, 255, 167, 3, 40,
  255, //
  7, 53, 20, 255, 47, 53, 30, 255, 87, 53, 40, 255, 127, 53, 50, 255, 167, 53,
  60, 255, //
  7, 103, 40, 255, 47, 103, 50, 255, 87, 103, 60, 255, 127, 103, 70, 255, 167,
  103, 80, 255, //
  7, 153, 60, 255, 47, 153, 70, 255, 87, 153, 80, 255, 127, 153, 90, 255, 167,
  153, 100, 255, //
  7, 203, 80, 255, 47, 203, 90, 255, 87, 203, 100, 255, 127, 203, 110, 255,
  167, 203, 120, 255, //
];

// 外部金标 B：3x2 灰度+alpha（colorType 4，本文件编码器不支持的形态），行 filter 0/4。
const String _goldenBBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAQAAAA3fa6RAAAAFklEQVR42mPg+i/SIOfAso+R6z9X'
    'IwAdvQRTDCIARQAAAABJRU5ErkJggg==';
const List<int> _goldenBRgba = <int>[
  10, 10, 10, 255, 20, 20, 20, 128, 30, 30, 30, 64, //
  200, 200, 200, 0, 210, 210, 210, 255, 220, 220, 220, 1,
];

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

List<int> _u32be(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

void _chunk(BytesBuilder out, String type, List<int> data) {
  out.add(_u32be(data.length));
  final payload = <int>[...ascii.encode(type), ...data];
  out.add(payload);
  out.add(_u32be(_crc32(payload)));
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

/// 极简 PNG 编码器（8 位 RGBA，指定过滤器），只为自证解码器而存在。
Uint8List encodePng(
  Uint8List rgba,
  int width,
  int height, {
  int filter = 0,
  int colorType = 6,
}) {
  final channels = switch (colorType) {
    0 => 1,
    2 => 3,
    6 => 4,
    _ => throw ArgumentError('colorType $colorType'),
  };
  final stride = width * channels;
  final raw = Uint8List((stride + 1) * height);
  final previous = Uint8List(stride);
  for (var y = 0; y < height; y++) {
    final rowStart = y * (stride + 1);
    raw[rowStart] = filter;
    for (var i = 0; i < stride; i++) {
      final value = rgba[y * stride + i];
      final a = i >= channels ? rgba[y * stride + i - channels] : 0;
      final b = previous[i];
      final c = i >= channels ? previous[i - channels] : 0;
      final predicted = switch (filter) {
        0 => 0,
        1 => a,
        2 => b,
        3 => (a + b) >> 1,
        4 => _paeth(a, b, c),
        _ => throw ArgumentError('filter $filter'),
      };
      raw[rowStart + 1 + i] = (value - predicted) & 0xFF;
    }
    previous.setRange(0, stride, rgba, y * stride);
  }

  final out = BytesBuilder();
  out.add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', <int>[
    ..._u32be(width),
    ..._u32be(height),
    8,
    colorType,
    0,
    0,
    0,
  ]);
  _chunk(out, 'IDAT', ZLibCodec().encode(raw));
  _chunk(out, 'IEND', const <int>[]);
  return out.takeBytes();
}

Uint8List solid(int width, int height, List<int> rgba) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    bytes.setRange(i * 4, i * 4 + 4, rgba);
  }
  return bytes;
}

Future<String> _rawGet(int port, String path) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  socket.write(
    'GET $path HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n',
  );
  await socket.flush();
  final response = await socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .join();
  await socket.close();
  return response;
}

void main() {
  group('decodePng', () {
    test('5 种过滤器往返一致', () {
      const width = 5;
      const height = 4;
      final source = Uint8List(width * height * 4);
      for (var i = 0; i < source.length; i++) {
        source[i] = (i * 37 + (i ~/ 4) * 11) & 0xFF;
      }
      for (var filter = 0; filter <= 4; filter++) {
        final image = decodePng(
          encodePng(source, width, height, filter: filter),
        );
        expect(image.width, width);
        expect(image.height, height);
        expect(image.rgba, source, reason: '过滤器 $filter 往返不一致');
      }
    });

    test('RGB（colorType 2）与灰度（colorType 0）解码', () {
      final rgb = decodePng(
        encodePng(
          Uint8List.fromList(<int>[
            10, 20, 30, //
            40, 50, 60,
          ]),
          2,
          1,
          colorType: 2,
        ),
      );
      expect(rgb.rgba.sublist(0, 8), <int>[10, 20, 30, 255, 40, 50, 60, 255]);

      final gray = decodePng(
        encodePng(Uint8List.fromList(<int>[7, 9]), 2, 1, colorType: 0),
      );
      expect(gray.rgba.sublist(0, 8), <int>[7, 7, 7, 255, 9, 9, 9, 255]);
    });

    test('外部金标：python3 生成的 PNG（filter 0–4 全覆盖）必须解出源像素', () {
      final image = decodePng(base64Decode(_goldenABase64));
      expect(image.width, 5);
      expect(image.height, 5);
      expect(image.rgba, _goldenARgba);
    });

    test('外部金标：灰度+alpha（colorType 4）', () {
      final image = decodePng(base64Decode(_goldenBBase64));
      expect(image.width, 3);
      expect(image.height, 2);
      expect(image.rgba, _goldenBRgba);
    });

    test('非 PNG / 16 位深 / 隔行 / 短 IHDR 明确报错，不静默降级', () {
      expect(
        () => decodePng(Uint8List.fromList(<int>[1, 2, 3])),
        throwsFormatException,
      );

      final sixteenBit = encodePng(solid(1, 1, <int>[0, 0, 0, 255]), 1, 1);
      sixteenBit[24] = 16; // IHDR.bitDepth
      expect(() => decodePng(sixteenBit), throwsFormatException);

      final interlaced = encodePng(solid(1, 1, <int>[0, 0, 0, 255]), 1, 1);
      interlaced[28] = 1; // IHDR.interlace
      expect(() => decodePng(interlaced), throwsFormatException);

      // 声明长度 < 13 的 IHDR：必须 FormatException，而不是越界 RangeError
      final stubIhdr = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        ..._u32be(0),
        ...ascii.encode('IHDR'),
        0, 0, 0, 0,
      ]);
      expect(() => decodePng(stubIhdr), throwsFormatException);
    });
  });

  group('HTTP 状态判据', () {
    test('2xx 与 304 算通过，4xx/5xx/3xx-非 304 不通过', () {
      expect(isOkStatus(200), isTrue);
      expect(isOkStatus(204), isTrue);
      expect(isOkStatus(299), isTrue);
      expect(isOkStatus(304), isTrue);
      expect(isOkStatus(301), isFalse);
      expect(isOkStatus(302), isFalse);
      expect(isOkStatus(404), isFalse);
      expect(isOkStatus(500), isFalse);
    });
  });

  group('产物自检与静态服务', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('web_smoke_test');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('verifyFlutterBuild：缺 index.html / 缺引导脚本 / 缺主脚本都报错，齐件放行', () {
      final dir = Directory('${tmp.path}/web')..createSync(recursive: true);
      expect(verifyFlutterBuild(dir.path), contains('没有 index.html'));

      File('${dir.path}/index.html').writeAsStringSync('<html>hi</html>');
      expect(verifyFlutterBuild(dir.path), contains('没有 Flutter 引导脚本'));

      File(
        '${dir.path}/index.html',
      ).writeAsStringSync('<script src="flutter_bootstrap.js"></script>');
      expect(verifyFlutterBuild(dir.path), contains('main.dart.js'));

      File('${dir.path}/main.dart.js').writeAsStringSync('// compiled');
      expect(verifyFlutterBuild(dir.path), isNull);
    });

    test('serveDir 拒绝点段（含 %2f 编码穿越），正常文件 200', () async {
      final root = Directory('${tmp.path}/web')..createSync(recursive: true);
      File('${root.path}/index.html').writeAsStringSync('<html>ok</html>');
      final sibling = Directory('${tmp.path}/webX')
        ..createSync(recursive: true);
      File('${sibling.path}/secret.txt').writeAsStringSync('leaked');

      final server = await serveDir(root.path);
      try {
        expect(
          await _rawGet(server.port, '/index.html'),
          startsWith('HTTP/1.1 200'),
        );
        expect(
          await _rawGet(server.port, '/../webX/secret.txt'),
          startsWith('HTTP/1.1 404'),
        );
        expect(
          await _rawGet(server.port, '/..%2fwebX/secret.txt'),
          startsWith('HTTP/1.1 404'),
          reason: 'pathSegments 会把 %2f 解码成 `..`，只靠前缀比较挡不住',
        );
        // 非法 UTF-8 转义：必须答 400，而不是让服务端 handler 抛异常带走整进程
        expect(
          await _rawGet(server.port, '/%c0%ae%c0%ae/webX/secret.txt'),
          startsWith('HTTP/1.1 400'),
          reason: 'pathSegments 解码非法 UTF-8 会抛，不接住就是整进程带栈退出',
        );
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('白屏判据', () {
    test('纯白截图必须红（唯一颜色 1 / 着墨比 0）', () {
      final image = decodePng(
        encodePng(solid(8, 8, <int>[255, 255, 255, 255]), 8, 8),
      );
      final stats = analyzeImage(image);
      expect(stats.uniqueColors, 1);
      expect(stats.inkRatio, 0);
      expect(judge(stats), isNotNull);
    });

    test('有内容的截图必须绿', () {
      final rgba = solid(8, 8, <int>[255, 255, 255, 255]);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 8; x++) {
          rgba.setRange((y * 8 + x) * 4, (y * 8 + x) * 4 + 4, <int>[
            0,
            0,
            0,
            255,
          ]);
        }
      }
      final stats = analyzeImage(decodePng(encodePng(rgba, 8, 8, filter: 4)));
      expect(stats.uniqueColors, 2);
      expect(stats.inkRatio, closeTo(0.5, 0.01));
      expect(judge(stats), isNull);
    });

    test('几乎全白（着墨比极低）也算白屏', () {
      final rgba = solid(100, 100, <int>[255, 255, 255, 255]);
      rgba.setRange(0, 4, <int>[0, 0, 0, 255]);
      final stats = analyzeImage(decodePng(encodePng(rgba, 100, 100)));
      expect(stats.uniqueColors, 2);
      expect(stats.inkRatio, lessThan(0.005));
      expect(judge(stats), isNotNull);
    });

    test('阈值可调：放宽 minColors / minInkRatio 后同一张图转绿', () {
      final stats = analyzeImage(
        decodePng(encodePng(solid(8, 8, <int>[255, 255, 255, 255]), 8, 8)),
      );
      expect(judge(stats), isNotNull);
      expect(judge(stats, minColors: 1, minInkRatio: 0), isNull);
    });

    test('判据不看 alpha：透明底但有色块仍算有内容', () {
      final rgba = solid(4, 4, <int>[255, 255, 255, 0]);
      rgba.setRange(0, 4, <int>[12, 34, 56, 0]);
      final stats = analyzeImage(decodePng(encodePng(rgba, 4, 4)));
      expect(judge(stats), isNull);
    });
  });
}
