import 'package:flutter/services.dart';
import '../constants.dart';

class NativeBridge {
  static const _channel = MethodChannel(AppConstants.channelName);
  static const _eventChannel = EventChannel(AppConstants.eventChannelName);
  static const _setupLogEventChannel =
      EventChannel(AppConstants.setupLogEventChannelName);
  static int _terminalSoftInputModeOwners = 0;
  static int _browserSoftInputModeOwners = 0;
  static String _appliedSoftInputMode = 'adjustResize';
  static Future<void> _softInputModeSync = Future<void>.value();

  static Future<String> getProotPath() async {
    return await _channel.invokeMethod('getProotPath');
  }

  static Future<String> getArch() async {
    return await _channel.invokeMethod('getArch');
  }

  static Future<String> getFilesDir() async {
    return await _channel.invokeMethod('getFilesDir');
  }

  static Future<String> getNativeLibDir() async {
    return await _channel.invokeMethod('getNativeLibDir');
  }

  static Future<Map<String, dynamic>> getWebViewPackageInfo() async {
    final result = await _channel.invokeMethod('getWebViewPackageInfo');
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>> getAppPackageInfo() async {
    final result = await _channel.invokeMethod('getAppPackageInfo');
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> isBootstrapComplete() async {
    return await _channel.invokeMethod('isBootstrapComplete');
  }

  static Future<Map<String, dynamic>> getBootstrapStatus() async {
    final result = await _channel.invokeMethod('getBootstrapStatus');
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> extractRootfs(String tarPath) async {
    return await _channel.invokeMethod('extractRootfs', {'tarPath': tarPath});
  }

  static Future<String> runInProot(
    String command, {
    int timeout = 900,
    bool keepForeground = false,
    String? foregroundText,
  }) async {
    return await _channel.invokeMethod('runInProot', {
      'command': command,
      'timeout': timeout,
      'keepForeground': keepForeground,
      'foregroundText': foregroundText,
    });
  }

  static Future<bool> startGateway() async {
    return await _channel.invokeMethod('startGateway');
  }

  static Future<bool> stopGateway() async {
    return await _channel.invokeMethod('stopGateway');
  }

  static Future<bool> startLocalApiProxy() async {
    return await _channel.invokeMethod('startLocalApiProxy');
  }

  static Future<bool> stopLocalApiProxy() async {
    return await _channel.invokeMethod('stopLocalApiProxy');
  }

  static Future<bool> isLocalApiProxyRunning() async {
    return await _channel.invokeMethod('isLocalApiProxyRunning');
  }

  static Future<bool> isGatewayRunning() async {
    return await _channel.invokeMethod('isGatewayRunning');
  }

  static Future<bool> isGatewayLogPersistenceEnabled() async {
    return await _channel.invokeMethod('isGatewayLogPersistenceEnabled');
  }

  static Future<bool> setGatewayLogPersistenceEnabled(bool enabled) async {
    return await _channel.invokeMethod(
      'setGatewayLogPersistenceEnabled',
      {'enabled': enabled},
    );
  }

  static Future<bool> setupDirs() async {
    return await _channel.invokeMethod('setupDirs');
  }

  static Future<bool> installBionicBypass() async {
    return await _channel.invokeMethod('installBionicBypass');
  }

  static Future<bool> writeResolv() async {
    return await _channel.invokeMethod('writeResolv');
  }

  static Future<bool> copyBundledAssetToFile({
    required String assetPath,
    required String destinationPath,
  }) async {
    return await _channel.invokeMethod('copyBundledAssetToFile', {
      'assetPath': assetPath,
      'destinationPath': destinationPath,
    });
  }

  static Future<int> extractDebPackages() async {
    return await _channel.invokeMethod('extractDebPackages');
  }

  static Future<bool> extractNodeTarball(String tarPath) async {
    return await _channel
        .invokeMethod('extractNodeTarball', {'tarPath': tarPath});
  }

  static Future<bool> createBinWrappers(String packageName) async {
    return await _channel
        .invokeMethod('createBinWrappers', {'packageName': packageName});
  }

  static Future<bool> startTerminalService() async {
    return await _channel.invokeMethod('startTerminalService');
  }

  static Future<bool> openNativeTerminalActivity({
    required String sessionId,
    required String title,
    required String executable,
    String cwd = '/',
    required List<String> arguments,
    required Map<String, String> environment,
    bool restart = false,
    bool keepAlive = true,
    bool emitOutput = false,
    bool renderingPaused = false,
    bool useNativeToolbar = true,
    int transcriptRows = 3000,
    int fontSize = 18,
  }) async {
    return await _channel.invokeMethod('openNativeTerminalActivity', {
      'sessionId': sessionId,
      'title': title,
      'executable': executable,
      'cwd': cwd,
      'arguments': arguments,
      'environment': environment,
      'restart': restart,
      'keepAlive': keepAlive,
      'emitOutput': emitOutput,
      'renderingPaused': renderingPaused,
      'useNativeToolbar': useNativeToolbar,
      'transcriptRows': transcriptRows,
      'fontSize': fontSize,
    });
  }

  static Future<bool> openNativeTerminalPagerActivity({
    required String sessionId,
    required String title,
    required String executable,
    String cwd = '/',
    required List<String> arguments,
    required Map<String, String> environment,
    bool restart = false,
    bool keepAlive = true,
    bool emitOutput = false,
    bool renderingPaused = false,
    bool useNativeToolbar = true,
    int transcriptRows = 3000,
    int fontSize = 18,
  }) async {
    return await _channel.invokeMethod('openNativeTerminalPagerActivity', {
      'sessionId': sessionId,
      'title': title,
      'executable': executable,
      'cwd': cwd,
      'arguments': arguments,
      'environment': environment,
      'restart': restart,
      'keepAlive': keepAlive,
      'emitOutput': emitOutput,
      'renderingPaused': renderingPaused,
      'useNativeToolbar': useNativeToolbar,
      'transcriptRows': transcriptRows,
      'fontSize': fontSize,
    });
  }

  static Future<Map<String, dynamic>> invokeNativeBrowserAction(
    String action, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    final result = await _channel.invokeMethod('invokeNativeBrowserAction', {
      'action': action,
      'payload': payload,
    });
    if (result == null) {
      return {
        'ok': false,
        'message': 'Native browser returned no result.',
      };
    }
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> stopTerminalService() async {
    return await _channel.invokeMethod('stopTerminalService');
  }

  static Future<bool> isTerminalServiceRunning() async {
    return await _channel.invokeMethod('isTerminalServiceRunning');
  }

  static Future<bool> startNodeService() async {
    return await _channel.invokeMethod('startNodeService');
  }

  static Future<bool> stopNodeService() async {
    return await _channel.invokeMethod('stopNodeService');
  }

  static Future<bool> isNodeServiceRunning() async {
    return await _channel.invokeMethod('isNodeServiceRunning');
  }

  static Future<bool> updateNodeNotification(String text) async {
    return await _channel
        .invokeMethod('updateNodeNotification', {'text': text});
  }

  static Future<bool> requestBatteryOptimization() async {
    return await _channel.invokeMethod('requestBatteryOptimization');
  }

  static Future<bool> isBatteryOptimized() async {
    return await _channel.invokeMethod('isBatteryOptimized');
  }

  static Future<bool> startSetupService() async {
    return await _channel.invokeMethod('startSetupService');
  }

  static Future<bool> updateSetupNotification(String text,
      {int progress = -1}) async {
    return await _channel.invokeMethod(
        'updateSetupNotification', {'text': text, 'progress': progress});
  }

  static Future<bool> stopSetupService() async {
    return await _channel.invokeMethod('stopSetupService');
  }

  static Future<bool> showUrlNotification(String url,
      {String title = 'URL Detected'}) async {
    return await _channel
        .invokeMethod('showUrlNotification', {'url': url, 'title': title});
  }

  static Future<Map<String, dynamic>?> pickSnapshotFile() async {
    final result = await _channel.invokeMethod('pickSnapshotFile');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> saveSnapshotFile({
    required String suggestedName,
    required String content,
  }) async {
    final result = await _channel.invokeMethod('saveSnapshotFile', {
      'suggestedName': suggestedName,
      'content': content,
    });
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> pickBackupFile() async {
    final result = await _channel.invokeMethod('pickBackupFile');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> pickBootstrapArchiveFile() async {
    final result = await _channel.invokeMethod('pickBootstrapArchiveFile');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> exportWorkspaceBackup({
    required String suggestedName,
    required String appVersion,
    String? openClawVersion,
  }) async {
    final result = await _channel.invokeMethod('exportWorkspaceBackup', {
      'suggestedName': suggestedName,
      'appVersion': appVersion,
      'openClawVersion': openClawVersion,
    });
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> inspectWorkspaceBackup(
    String path,
  ) async {
    final result = await _channel.invokeMethod(
      'inspectWorkspaceBackup',
      {'path': path},
    );
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> restoreWorkspaceBackup(String path) async {
    return await _channel.invokeMethod(
      'restoreWorkspaceBackup',
      {'path': path},
    );
  }

  static Stream<String> get gatewayLogStream {
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) => event.toString());
  }

  static Stream<String> get setupLogStream {
    return _setupLogEventChannel
        .receiveBroadcastStream()
        .map((event) => event.toString());
  }

  static Future<String?> requestScreenCapture(int durationMs) async {
    return await _channel
        .invokeMethod('requestScreenCapture', {'durationMs': durationMs});
  }

  static Future<bool> stopScreenCapture() async {
    return await _channel.invokeMethod('stopScreenCapture');
  }

  static Future<bool> requestStoragePermission() async {
    return await _channel.invokeMethod('requestStoragePermission');
  }

  static Future<bool> hasStoragePermission() async {
    return await _channel.invokeMethod('hasStoragePermission');
  }

  static Future<bool> hasOverlayPermission() async {
    return await _channel.invokeMethod('hasOverlayPermission');
  }

  static Future<bool> requestOverlayPermission() async {
    return await _channel.invokeMethod('requestOverlayPermission');
  }

  static Future<bool> startFloatingFileManager() async {
    return await _channel.invokeMethod('startFloatingFileManager');
  }

  static Future<bool> stopFloatingFileManager() async {
    return await _channel.invokeMethod('stopFloatingFileManager');
  }

  static Future<bool> isFloatingFileManagerRunning() async {
    return await _channel.invokeMethod('isFloatingFileManagerRunning');
  }

  static Future<String> getExternalStoragePath() async {
    return await _channel.invokeMethod('getExternalStoragePath');
  }

  static Future<bool> installApk(String apkPath) async {
    return await _channel.invokeMethod('installApk', {'apkPath': apkPath});
  }

  static Future<String?> readRootfsFile(String path) async {
    return await _channel.invokeMethod('readRootfsFile', {'path': path});
  }

  static Future<bool> writeRootfsFile(String path, String content) async {
    return await _channel
        .invokeMethod('writeRootfsFile', {'path': path, 'content': content});
  }

  // SSH Service
  static Future<bool> startSshd({int port = 8022}) async {
    return await _channel.invokeMethod('startSshd', {'port': port});
  }

  static Future<bool> stopSshd() async {
    return await _channel.invokeMethod('stopSshd');
  }

  static Future<bool> isSshdRunning() async {
    return await _channel.invokeMethod('isSshdRunning');
  }

  static Future<int> getSshdPort() async {
    return await _channel.invokeMethod('getSshdPort');
  }

  static Future<bool> startCpolarService({
    required String binaryPath,
    required String configPath,
    required String logPath,
    int webPort = 9200,
  }) async {
    return await _channel.invokeMethod('startCpolarService', {
      'binaryPath': binaryPath,
      'configPath': configPath,
      'logPath': logPath,
      'webPort': webPort,
    });
  }

  static Future<bool> stopCpolarService() async {
    return await _channel.invokeMethod('stopCpolarService');
  }

  static Future<bool> isCpolarServiceRunning() async {
    return await _channel.invokeMethod('isCpolarServiceRunning');
  }

  static Future<bool> startLocalModelService({
    required String binaryPath,
    required String modelPath,
    required String logPath,
    required int port,
    required String alias,
    required int contextSize,
    required int threads,
    required int threadsBatch,
    required int batchSize,
    required int ubatchSize,
  }) async {
    return await _channel.invokeMethod('startLocalModelService', {
      'binaryPath': binaryPath,
      'modelPath': modelPath,
      'logPath': logPath,
      'port': port,
      'alias': alias,
      'contextSize': contextSize,
      'threads': threads,
      'threadsBatch': threadsBatch,
      'batchSize': batchSize,
      'ubatchSize': ubatchSize,
    });
  }

  static Future<bool> stopLocalModelService() async {
    return await _channel.invokeMethod('stopLocalModelService');
  }

  static Future<bool> isLocalModelServiceRunning() async {
    return await _channel.invokeMethod('isLocalModelServiceRunning');
  }

  static Future<Map<String, dynamic>?> getLocalModelRuntimeStats() async {
    final result = await _channel.invokeMethod('getLocalModelRuntimeStats');
    if (result == null) {
      return null;
    }
    return Map<String, dynamic>.from(result);
  }

  static Future<List<String>> getDeviceIps() async {
    final result = await _channel.invokeMethod('getDeviceIps');
    return List<String>.from(result);
  }

  static Future<bool> bringToForeground() async {
    return await _channel.invokeMethod('bringToForeground');
  }

  static Future<bool> setRootPassword(String password) async {
    return await _channel
        .invokeMethod('setRootPassword', {'password': password});
  }

  static Future<bool> _setWindowSoftInputMode(String mode) async {
    return await _channel.invokeMethod(
      'setWindowSoftInputMode',
      {'mode': mode},
    );
  }

  static String _desiredSoftInputMode() {
    if (_browserSoftInputModeOwners > 0) {
      return 'adjustNothing';
    }
    if (_terminalSoftInputModeOwners > 0) {
      return 'adjustResize';
    }
    return 'adjustResize';
  }

  static Future<void> _syncWindowSoftInputMode() {
    final nextSync = _softInputModeSync.catchError((Object _) {}).then((_) async {
      final desiredMode = _desiredSoftInputMode();
      if (desiredMode == _appliedSoftInputMode) {
        return;
      }
      await _setWindowSoftInputMode(desiredMode);
      _appliedSoftInputMode = desiredMode;
    });
    _softInputModeSync = nextSync.catchError((Object _) {});
    return nextSync;
  }

  static Future<void> acquireTerminalSoftInputMode() async {
    _terminalSoftInputModeOwners += 1;
    await _syncWindowSoftInputMode();
  }

  static Future<void> releaseTerminalSoftInputMode() async {
    if (_terminalSoftInputModeOwners <= 0) {
      _terminalSoftInputModeOwners = 0;
    } else {
      _terminalSoftInputModeOwners -= 1;
    }
    await _syncWindowSoftInputMode();
  }

  static Future<void> acquireBrowserSoftInputMode() async {
    _browserSoftInputModeOwners += 1;
    await _syncWindowSoftInputMode();
  }

  static Future<void> releaseBrowserSoftInputMode() async {
    if (_browserSoftInputModeOwners <= 0) {
      _browserSoftInputModeOwners = 0;
    } else {
      _browserSoftInputModeOwners -= 1;
    }
    await _syncWindowSoftInputMode();
  }
}
