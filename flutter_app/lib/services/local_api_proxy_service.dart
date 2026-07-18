import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'native_bridge.dart';

class LocalApiProxyService {
  LocalApiProxyService._();

  static const assetRoot = 'assets/api2py';
  static const guestDir = '/root/.openclaw/api2py';
  static const url = 'http://127.0.0.1:9999/';
  static const healthUrl = 'http://127.0.0.1:9999/api/health';

  static Future<bool> isRunning() async {
    try {
      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 2));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  static Future<String> start() async {
    await installBundledFiles();
    return _startInstalled();
  }

  static Future<String> restart() async {
    await installBundledFiles();
    await NativeBridge.runInProot(
      '''
cd $guestDir 2>/dev/null && bash stop.sh || true
''',
      timeout: 15,
    );
    return _startInstalled(restarted: true);
  }

  static Future<String> _startInstalled({bool restarted = false}) async {
    final command = '''
set -e
cd $guestDir
mkdir -p data/sessions
if [ ! -f data/config.json ] && [ -f data/config.example.json ]; then
  cp data/config.example.json data/config.json
fi
chmod +x start.sh stop.sh
python3 - <<'PY'
missing = []
for module in ('starlette', 'uvicorn', 'httpx', 'aiosqlite'):
    try:
        __import__(module)
    except Exception:
        missing.append(module)
if missing:
    raise SystemExit(1)
PY
bash start.sh
curl -s --max-time 3 http://127.0.0.1:9999/api/health >/dev/null
echo '${restarted ? '本地中转代理已重启' : '本地中转代理已启动'}：http://127.0.0.1:9999/'
''';
    try {
      return await NativeBridge.runInProot(command, timeout: 30);
    } catch (_) {
      final installCommand = '''
set -e
cd $guestDir
if ! python3 -m pip --version >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y python3-pip
  else
    echo 'Python 缺少 pip，且当前 RootFS 中找不到 apt-get，无法自动安装中转代理依赖。' >&2
    exit 1
  fi
fi
python3 -m pip install --break-system-packages -r requirements.txt || \
  python3 -m pip install --break-system-packages --index-url https://pypi.org/simple -r requirements.txt || \
  python3 -m pip install -r requirements.txt || \
  python3 -m pip install --index-url https://pypi.org/simple -r requirements.txt
python3 - <<'PY'
for module in ('starlette', 'uvicorn', 'httpx', 'aiosqlite'):
    __import__(module)
PY
bash start.sh
curl -s --max-time 3 http://127.0.0.1:9999/api/health >/dev/null
echo '本地中转代理依赖已安装并${restarted ? '重启' : '启动'}：http://127.0.0.1:9999/'
''';
      try {
        return await NativeBridge.runInProot(installCommand, timeout: 300);
      } catch (error, stackTrace) {
        final logTail = await _serverLogTail();
        if (logTail.trim().isEmpty) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        Error.throwWithStackTrace(
          StateError('${_errorText(error)}\n\n$logTail'),
          stackTrace,
        );
      }
    }
  }

  static String _errorText(Object error) {
    if (error is PlatformException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return error.code;
    }
    return error.toString();
  }

  static Future<String> _serverLogTail() async {
    try {
      return await NativeBridge.runInProot(
        '''
if [ -f $guestDir/server.log ]; then
  echo '--- server.log 最近输出 ---'
  tail -80 $guestDir/server.log
fi
''',
        timeout: 10,
      );
    } catch (_) {
      return '';
    }
  }

  static Future<void> installBundledFiles() async {
    final filesDir = await NativeBridge.getFilesDir();
    final rootfsDir = Directory('$filesDir/rootfs/ubuntu');
    if (!rootfsDir.existsSync()) {
      throw StateError('Ubuntu RootFS 还没有安装，无法启动本地中转代理。');
    }
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetPaths = manifest
        .listAssets()
        .where((path) => path.startsWith('$assetRoot/'))
        .where((path) => !path.endsWith('/'))
        .toList()
      ..sort();
    if (assetPaths.isEmpty) {
      throw StateError('APK 中没有找到内置 api2py 资源。');
    }
    final targetRoot = Directory('${rootfsDir.path}$guestDir');
    for (final assetPath in assetPaths) {
      final relativePath = assetPath.substring('$assetRoot/'.length);
      final target = File('${targetRoot.path}/$relativePath');
      await target.parent.create(recursive: true);
      final data = await rootBundle.load(assetPath);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    final requiredFiles = <String>[
      'server.py',
      'start.sh',
      'requirements.txt',
      'app/__init__.py',
      'app/config.py',
      'app/main.py',
      'public/static/index.html',
    ];
    final missing = requiredFiles
        .where((path) => !File('${targetRoot.path}/$path').existsSync())
        .toList();
    if (missing.isNotEmpty) {
      throw StateError(
        '内置 api2py 文件同步不完整，缺少：${missing.join(', ')}。请安装包含完整 api2py 资源目录的新版本。',
      );
    }
  }
}
