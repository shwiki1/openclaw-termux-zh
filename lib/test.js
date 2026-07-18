/**
 * Basic tests for CiYuanXia compatibility CLI
 * Tests module loading, exports, and basic functionality
 */

import { strict as assert } from 'node:assert';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { existsSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import os from 'node:os';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (error) {
    console.log(`  ✗ ${name}`);
    console.log(`    ${error.message}`);
    failed++;
  }
}

async function testAsync(name, fn) {
  try {
    await fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (error) {
    console.log(`  ✗ ${name}`);
    console.log(`    ${error.message}`);
    failed++;
  }
}

async function runTests() {
  console.log('\n🧪 CiYuanXia compatibility CLI tests\n');

  // File existence tests
  console.log('📁 File Structure:');

  test('bin/openclawx exists', () => {
    assert.ok(existsSync(join(projectRoot, 'bin/openclawx')));
  });

  test('lib/index.js exists', () => {
    assert.ok(existsSync(join(projectRoot, 'lib/index.js')));
  });

  test('lib/installer.js exists', () => {
    assert.ok(existsSync(join(projectRoot, 'lib/installer.js')));
  });

  test('lib/bionic-bypass.js exists', () => {
    assert.ok(existsSync(join(projectRoot, 'lib/bionic-bypass.js')));
  });

  test('package.json exists', () => {
    assert.ok(existsSync(join(projectRoot, 'package.json')));
  });

  // Module import tests
  console.log('\n📦 Module Imports:');

  await testAsync('index.js exports main function', async () => {
    const indexModule = await import('./index.js');
    assert.ok(typeof indexModule.main === 'function');
  });

  await testAsync('installer.js exports setup functions', async () => {
    const installerModule = await import('./installer.js');
    assert.ok(typeof installerModule.setupProotUbuntu === 'function');
    assert.ok(typeof installerModule.installProot === 'function');
    assert.ok(typeof installerModule.getInstallStatus === 'function');
  });

  await testAsync('bionic-bypass.js loads without error', async () => {
    await import('./bionic-bypass.js');
  });

  // Package.json validation
  console.log('\n📋 Package Configuration:');

  test('package.json has required fields', () => {
    const pkg = JSON.parse(readFileSync(join(projectRoot, 'package.json'), 'utf8'));
    assert.ok(pkg.name === 'ciyuanxia');
    assert.ok(pkg.version);
    assert.ok(pkg.main);
    assert.ok(pkg.bin);
    assert.ok(pkg.bin.openclawx);
  });

  test('package.json specifies node engine >= 18', () => {
    const pkg = JSON.parse(readFileSync(join(projectRoot, 'package.json'), 'utf8'));
    assert.ok(pkg.engines?.node);
    const minVersion = parseInt(pkg.engines.node.match(/\d+/)[0]);
    assert.ok(minVersion >= 18, 'Node.js version should be >= 18');
  });

  test('CLI banner version matches package.json version', () => {
    const pkg = JSON.parse(readFileSync(join(projectRoot, 'package.json'), 'utf8'));
    const indexSource = readFileSync(join(projectRoot, 'lib/index.js'), 'utf8');
    assert.ok(indexSource.includes(`const VERSION = '${pkg.version}';`));
  });

  console.log('\n📱 Android Versioning:');

  test('Gradle keeps install-visible versionName separate from build number', () => {
    const gradle = readFileSync(
      join(projectRoot, 'flutter_app/android/app/build.gradle'),
      'utf8',
    );
    assert.ok(gradle.includes('flutter.androidVersionName'));
    assert.match(gradle, /versionName\s*=\s*androidVersionName/);
    assert.ok(gradle.includes('displayVersionName(flutterVersionName)'));
  });

  test('settings screen does not append split APK versionCode', () => {
    const settingsScreen = readFileSync(
      join(projectRoot, 'flutter_app/lib/screens/settings_screen.dart'),
      'utf8',
    );
    assert.ok(!settingsScreen.includes('versionCode'));
    assert.ok(settingsScreen.includes('? versionName'));
  });

  test('Flutter app exposes a dedicated display version instead of fullVersion', () => {
    const constantsSource = readFileSync(
      join(projectRoot, 'flutter_app/lib/constants.dart'),
      'utf8',
    );
    assert.ok(constantsSource.includes('APP_VERSION_DISPLAY'));
    assert.ok(constantsSource.includes('static final String displayVersion'));
    assert.ok(!constantsSource.includes('static const String displayVersion = fullVersion'));
  });

  test('shared versioning helper keeps the current build at 2.5 and advances later builds by 0.1', () => {
    const versioningScript = join(projectRoot, 'scripts/versioning.py');
    const derive = (buildNumber) => JSON.parse(
      execFileSync(
        'python3',
        [
          versioningScript,
          'derive',
          '--base-version',
          '2.5.0',
          '--base-build',
          '143',
          '--target-build',
          String(buildNumber),
          '--format',
          'json',
        ],
        { encoding: 'utf8' },
      ),
    );

    assert.deepStrictEqual(derive(144), {
      semanticVersion: '2.5.0',
      displayVersion: '2.5',
      fullVersion: '2.5.0+144',
      buildNumber: '144',
      baseVersion: '2.5.0',
      baseBuildNumber: '143',
    });
    assert.equal(derive(145).displayVersion, '2.6');
    assert.equal(derive(149).semanticVersion, '3.0.0');
    assert.equal(derive(156).displayVersion, '3.7');
  });

  test('build automation uses the shared versioning helper', () => {
    const buildApk = readFileSync(join(projectRoot, 'scripts/build-apk.sh'), 'utf8');
    const workflow = readFileSync(
      join(projectRoot, '.github/workflows/flutter-build.yml'),
      'utf8',
    );
    assert.ok(buildApk.includes('scripts/versioning.py'));
    assert.ok(workflow.includes('scripts/versioning.py derive'));
  });

  test('browser header keeps the address bar on its own row', () => {
    const browserPanel = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/terminal_browser_panel.dart'),
      'utf8',
    );
    assert.ok(browserPanel.includes('const Spacer(),'));
    assert.ok(browserPanel.includes('_buildAddressBar(theme, compact: compact),'));
    assert.ok(!browserPanel.includes('Expanded(\n                          child: _buildAddressBar'));
  });

  test('browser popup menus use explicit high-contrast menu entries', () => {
    const browserPanel = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/terminal_browser_panel.dart'),
      'utf8',
    );
    assert.ok(browserPanel.includes('Widget _buildMenuEntry('));
    assert.ok(browserPanel.includes('label: \'脚本助手\''));
    assert.ok(!browserPanel.includes('child: ListTile('));
  });

  test('browser automation defaults to mobile UA and exposes recovery controls', () => {
    const browserPanel = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/terminal_browser_panel.dart'),
      'utf8',
    );
    const browserService = readFileSync(
      join(projectRoot, 'flutter_app/lib/services/browser_automation_service.dart'),
      'utf8',
    );
    const cliApiConfig = readFileSync(
      join(projectRoot, 'flutter_app/lib/services/cli_api_config_service.dart'),
      'utf8',
    );
    assert.ok(browserPanel.includes('userAgentMode = _BrowserUserAgentMode.mobile'));
    assert.ok(browserPanel.includes('Future<Map<String, dynamic>> healthCheck'));
    assert.ok(browserPanel.includes('Future<Map<String, dynamic>> resetTab'));
    assert.ok(browserPanel.includes('Future<Map<String, dynamic>> paste'));
    assert.ok(browserPanel.includes('Future<Map<String, dynamic>> waitForResource'));
    assert.ok(browserPanel.includes('Future<Map<String, dynamic>> listOverlays'));
    assert.ok(browserPanel.includes('Future<Map<String, dynamic>> clickAt'));
    assert.ok(browserPanel.includes('ThemeData _browserButtonTheme(ThemeData baseTheme)'));
    assert.ok(browserPanel.includes('disabledForegroundColor: Colors.white38'));
    assert.ok(browserService.includes("'browser_health_check': 'health_check'"));
    assert.ok(browserService.includes("'browser_reset_tab': 'reset_tab'"));
    assert.ok(browserService.includes('bool _autoScriptDraftEnabled = false'));
    assert.ok(cliApiConfig.includes('name: "browser_paste"'));
    assert.ok(cliApiConfig.includes('name: "browser_wait_for_resource"'));
    assert.ok(cliApiConfig.includes('name: "browser_list_overlays"'));
    assert.ok(cliApiConfig.includes('name: "browser_click_at"'));
  });

  test('script assistant separates traditional user scripts from Codex workflows', () => {
    const userScriptLibrary = readFileSync(
      join(projectRoot, 'flutter_app/lib/services/browser_user_script_library_service.dart'),
      'utf8',
    );
    const browserPanel = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/terminal_browser_panel.dart'),
      'utf8',
    );
    const browserService = readFileSync(
      join(projectRoot, 'flutter_app/lib/services/browser_automation_service.dart'),
      'utf8',
    );
    assert.ok(userScriptLibrary.includes("_storageKey = 'browser_user_scripts_v1'"));
    assert.ok(browserPanel.includes("'传统网站脚本'"));
    assert.ok(browserPanel.includes("'新增传统脚本'"));
    assert.ok(browserPanel.includes('_importUserScript'));
    assert.ok(browserPanel.includes('PageView('));
    assert.ok(browserPanel.includes('_workspacePageController'));
    assert.ok(browserPanel.includes('左右滑动切换 Codex 自动化流程与传统网站脚本'));
    assert.ok(browserService.includes("'browser_user_script_save': 'user_script_save'"));
    assert.ok(browserService.includes('Traditional website script saved.'));
  });

  test('browser panel switches to browser soft-input mode for address-bar and page inputs', () => {
    const browserPanel = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/terminal_browser_panel.dart'),
      'utf8',
    );
    const terminalScreen = readFileSync(
      join(projectRoot, 'flutter_app/lib/screens/terminal_screen.dart'),
      'utf8',
    );
    assert.ok(browserPanel.includes('final bool visible;'));
    assert.ok(browserPanel.includes('final _urlFocusNode = FocusNode();'));
    assert.ok(browserPanel.includes("_keyboardFocusChannelName = 'OpenClawImeFocus'"));
    assert.ok(browserPanel.includes('addJavaScriptChannel('));
    assert.ok(browserPanel.includes("document.addEventListener('focusin', postState, true);"));
    assert.ok(browserPanel.includes("document.addEventListener('focusout', () => {"));
    assert.ok(browserPanel.includes('NativeBridge.acquireBrowserSoftInputMode()'));
    assert.ok(browserPanel.includes('NativeBridge.releaseBrowserSoftInputMode()'));
    assert.ok(terminalScreen.includes('visible: _browserPanelOpen'));
    assert.ok(terminalScreen.includes('const shouldKeepBrowserMounted = true;'));
  });

  test('CLI tools launch native terminal surfaces, and Codex binds the native browser delegate', () => {
    const cliToolsScreen = readFileSync(
      join(projectRoot, 'flutter_app/lib/screens/cli_tools_screen.dart'),
      'utf8',
    );
    const nativeBrowserDelegate = readFileSync(
      join(projectRoot, 'flutter_app/lib/services/native_browser_automation_delegate.dart'),
      'utf8',
    );
    assert.ok(cliToolsScreen.includes('final browserService = BrowserAutomationService.instance;'));
    assert.ok(cliToolsScreen.includes('final browserDelegate = NativeBrowserAutomationDelegate.instance;'));
    assert.ok(cliToolsScreen.includes('final isCodexTool = _isCodexTool(tool, initialCommand);'));
    assert.ok(cliToolsScreen.includes('await NativeBridge.openNativeTerminalPagerActivity('));
    assert.ok(cliToolsScreen.includes('await NativeBridge.openNativeTerminalActivity('));
    assert.ok(!cliToolsScreen.includes('builder: (_) => TerminalScreen('));
    assert.ok(nativeBrowserDelegate.includes('class NativeBrowserAutomationDelegate implements BrowserAutomationDelegate'));
    assert.ok(nativeBrowserDelegate.includes("String get sessionLabel => 'native-browser-page';"));
    assert.ok(nativeBrowserDelegate.includes("Future<Map<String, dynamic>> getState() => _invoke('get_state');"));
    assert.ok(nativeBrowserDelegate.includes("Future<Map<String, dynamic>> selfTest() => _invoke('self_test');"));
  });

  test('terminal toolbar keeps bottom safe-area padding and provides press feedback', () => {
    const terminalToolbar = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/terminal_toolbar.dart'),
      'utf8',
    );
    assert.ok(terminalToolbar.includes('static const double toolbarHeight = 42;'));
    assert.ok(terminalToolbar.includes('maintainBottomViewPadding: true'));
    assert.ok(terminalToolbar.includes('HapticFeedback.selectionClick();'));
    assert.ok(terminalToolbar.includes('overlayColor: MaterialStateProperty.resolveWith'));
  });

  test('Android native terminal can host the shortcut bar inside the platform view', () => {
    const terminalScreen = readFileSync(
      join(projectRoot, 'flutter_app/lib/screens/terminal_screen.dart'),
      'utf8',
    );
    const nativeTerminalWidget = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/native_terminal_view.dart'),
      'utf8',
    );
    const nativeTerminalHost = readFileSync(
      join(
        projectRoot,
        'flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalSessionView.kt',
      ),
      'utf8',
    );
    assert.ok(nativeTerminalWidget.includes('final bool useNativeToolbar;'));
    assert.ok(nativeTerminalWidget.includes("'useNativeToolbar': widget.useNativeToolbar"));
    assert.ok(!terminalScreen.includes('TerminalToolbar('));
    assert.ok(terminalScreen.includes('useNativeToolbar: true'));
    assert.ok(nativeTerminalHost.includes('val useNativeToolbar: Boolean = false'));
    assert.ok(nativeTerminalHost.includes('createToolbarStrip(context)'));
    assert.ok(nativeTerminalHost.includes('sendToolbarInput("\\u001b[A")'));
    assert.ok(nativeTerminalHost.includes('performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)'));
    assert.ok(nativeTerminalHost.includes('private fun toolbarButtonBackground(): StateListDrawable'));
    assert.ok(!nativeTerminalHost.includes('scrollView.setOnApplyWindowInsetsListener'));
    assert.ok(!nativeTerminalHost.includes('insets.systemWindowInsetBottom'));
    assert.ok(!nativeTerminalHost.includes('private val bottomSpaceView = View(context)'));
    assert.ok(!nativeTerminalHost.includes('private val globalLayoutListener = ViewTreeObserver.OnGlobalLayoutListener'));
    assert.ok(!nativeTerminalHost.includes('container.viewTreeObserver.addOnGlobalLayoutListener(globalLayoutListener)'));
  });

  test('native terminal keeps IME show requests lightweight while preserving retry-on-startup handling', () => {
    const nativeTerminalWidget = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/native_terminal_view.dart'),
      'utf8',
    );
    const nativeTerminalHost = readFileSync(
      join(
        projectRoot,
        'flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalSessionView.kt',
      ),
      'utf8',
    );
    assert.ok(!nativeTerminalWidget.includes('unawaited(showKeyboard())'));
    assert.ok(nativeTerminalHost.includes('private var lastKeyboardShowRequestElapsedMs = 0L'));
    assert.ok(nativeTerminalHost.includes('private val keyboardRetryRunnable = Runnable'));
    assert.ok(nativeTerminalHost.includes('terminalView.removeCallbacks(keyboardRetryRunnable)'));
    assert.ok(!nativeTerminalHost.includes('pendingImeCompensationBottomPx'));
    assert.ok(!nativeTerminalHost.includes('imeTransitionSettleRunnable'));
    assert.ok(!nativeTerminalHost.includes('imeTransitionFinishRunnable'));
    assert.ok(!nativeTerminalHost.includes('setImeTransitionActive('));
    assert.ok(!nativeTerminalHost.includes('applyPendingImeCompensation()'));
    assert.ok(!nativeTerminalHost.includes('updateImeCompensation()'));
    assert.ok(!nativeTerminalHost.includes('private val imePostLayoutRefreshRunnable = Runnable'));
    assert.ok(!nativeTerminalHost.includes('private fun handleGlobalLayoutChange()'));
    assert.ok(!nativeTerminalHost.includes('container.removeCallbacks(imePostLayoutRefreshRunnable)'));
    assert.ok(!nativeTerminalHost.includes('container.viewTreeObserver.removeOnGlobalLayoutListener(globalLayoutListener)'));
    assert.ok(nativeTerminalHost.includes('if (renderingPaused) {'));
    assert.ok(nativeTerminalHost.includes('requestScreenUpdate()'));
    assert.ok(nativeTerminalHost.includes('private fun requestKeyboardShow(force: Boolean = false)'));
    assert.ok(nativeTerminalHost.includes('requestKeyboardShow(force = true)'));
    assert.ok(nativeTerminalHost.includes('val recentlyRequested = now - lastKeyboardShowRequestElapsedMs < 120L'));
    assert.ok(!nativeTerminalHost.includes('imm.restartInput(terminalView)'));
  });

  test('Codex proxy preserves responses tool-call structures through the OpenAI bridge', () => {
    const cliApiConfig = readFileSync(
      join(projectRoot, 'flutter_app/lib/services/cli_api_config_service.dart'),
      'utf8',
    );
    assert.ok(cliApiConfig.includes('def responses_to_chat_messages(input_value):'));
    assert.ok(cliApiConfig.includes('if item_type == "function_call_output":'));
    assert.ok(cliApiConfig.includes('"tool_call_id": item.get("call_id")'));
    assert.ok(cliApiConfig.includes('"type": "function_call"'));
    assert.ok(cliApiConfig.includes('"call_id": call.get("id") or f"tool_call_{index}"'));
    assert.ok(cliApiConfig.includes('function responsesToChatMessages(input) {'));
    assert.ok(cliApiConfig.includes('if (item.type === "function_call_output") {'));
    assert.ok(cliApiConfig.includes('function chatToResponses(payload, originalModel) {'));
    assert.ok(cliApiConfig.includes('type: "function_call",'));
    assert.ok(cliApiConfig.includes('targetPath = "/v1/chat/completions";'));
  });

  test('Android host exposes the native terminal pager and native browser action bridge', () => {
    const nativeBridge = readFileSync(
      join(projectRoot, 'flutter_app/lib/services/native_bridge.dart'),
      'utf8',
    );
    const manifest = readFileSync(
      join(projectRoot, 'flutter_app/android/app/src/main/AndroidManifest.xml'),
      'utf8',
    );
    const mainActivity = readFileSync(
      join(
        projectRoot,
        'flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/MainActivity.kt',
      ),
      'utf8',
    );
    const nativeTerminalActivity = readFileSync(
      join(
        projectRoot,
        'flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalActivity.kt',
      ),
      'utf8',
    );
    const nativeTerminalPagerActivity = readFileSync(
      join(
        projectRoot,
        'flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalPagerActivity.kt',
      ),
      'utf8',
    );
    const nativeBrowserView = readFileSync(
      join(
        projectRoot,
        'flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeCodexBrowserView.kt',
      ),
      'utf8',
    );
    assert.ok(nativeBridge.includes("setWindowSoftInputMode"));
    assert.ok(nativeBridge.includes("adjustResize"));
    assert.ok(nativeBridge.includes("adjustNothing"));
    assert.ok(nativeBridge.includes("acquireBrowserSoftInputMode"));
    assert.ok(nativeBridge.includes("releaseBrowserSoftInputMode"));
    assert.ok(nativeBridge.includes('openNativeTerminalActivity({'));
    assert.ok(nativeBridge.includes('openNativeTerminalPagerActivity({'));
    assert.ok(nativeBridge.includes("invokeNativeBrowserAction("));
    assert.ok(nativeBridge.includes("_desiredSoftInputMode()"));
    assert.ok(mainActivity.includes('"openNativeTerminalActivity" -> {'));
    assert.ok(mainActivity.includes('"openNativeTerminalPagerActivity" -> {'));
    assert.ok(mainActivity.includes('"invokeNativeBrowserAction" -> {'));
    assert.ok(mainActivity.includes('NativeTerminalActivity.createIntent(this, config)'));
    assert.ok(mainActivity.includes('NativeTerminalPagerActivity.createIntent(this, config)'));
    assert.ok(mainActivity.includes('NATIVE_TERMINAL_ACTIVITY_REQUEST'));
    assert.ok(mainActivity.includes('NATIVE_TERMINAL_PAGER_ACTIVITY_REQUEST'));
    assert.ok(nativeTerminalActivity.includes('class NativeTerminalActivity : Activity()'));
    assert.ok(nativeTerminalActivity.includes('NativeTerminalSessionView('));
    assert.ok(nativeTerminalActivity.includes('TerminalSessionService.start(applicationContext)'));
    assert.ok(nativeTerminalActivity.includes('ViewCompat.setOnApplyWindowInsetsListener(rootLayout)'));
    assert.ok(nativeTerminalActivity.includes('terminalContainer.updatePadding('));
    assert.ok(nativeTerminalActivity.includes('background = nativeCardDrawable('));
    assert.ok(nativeTerminalPagerActivity.includes('class NativeTerminalPagerActivity : Activity()'));
    assert.ok(nativeTerminalPagerActivity.includes('NativeBrowserAutomationRegistry.controller = browserView'));
    assert.ok(nativeTerminalPagerActivity.includes('showPage(PAGE_BROWSER)'));
    assert.ok(nativeTerminalPagerActivity.includes('ViewCompat.setOnApplyWindowInsetsListener(rootLayout)'));
    assert.ok(nativeTerminalPagerActivity.includes('activeTerminalView?.requestToolbarVisible()'));
    assert.ok(nativeTerminalPagerActivity.includes('useCodexChrome = true'));
    assert.ok(nativeTerminalPagerActivity.includes('createIconActionButton(R.drawable.lucide_plus, "新建会话") { openNewSession() }'));
    assert.ok(nativeTerminalPagerActivity.includes('performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)'));
    assert.ok(nativeTerminalPagerActivity.includes('private fun openNewSession()'));
    assert.ok(nativeTerminalPagerActivity.includes('private fun closeCurrentSession()'));
    assert.ok(nativeTerminalPagerActivity.includes('private fun showSessionMenu(anchor: View)'));
    assert.ok(nativeTerminalPagerActivity.includes('popup.menu.add(1, MENU_NEW_SESSION, sessions.size, "新建会话")'));
    assert.ok(nativeTerminalPagerActivity.includes('setBackgroundColor(NativeUiPalette.background)'));
    assert.ok(nativeTerminalPagerActivity.includes('nativeRoundedStateDrawable('));
    assert.ok(nativeTerminalPagerActivity.includes('radiusDp = 8'));
    assert.ok(nativeBrowserView.includes('class NativeCodexBrowserView('));
    assert.ok(nativeBrowserView.includes('interface NativeBrowserAutomationController'));
    assert.ok(nativeBrowserView.includes('object NativeBrowserAutomationRegistry'));
    assert.ok(nativeBrowserView.includes('override fun executeAction('));
    assert.ok(nativeBrowserView.includes('private val recentActionsColumn = LinearLayout(context)'));
    assert.ok(nativeBrowserView.includes('private val inspectorColumn = LinearLayout(context)'));
    assert.ok(nativeBrowserView.includes('private fun showMoreMenu(anchor: View)'));
    assert.ok(nativeBrowserView.includes('private fun loadInspector(mode: NativeBrowserInspectorMode)'));
    assert.ok(nativeBrowserView.includes('浏览器脚本助手'));
    assert.ok(nativeBrowserView.includes('待保存草稿、已保存流程和传统网站脚本分区管理'));
    assert.ok(nativeBrowserView.includes('Codex 自动化'));
    assert.ok(nativeBrowserView.includes('private data class NativeBrowserPendingScriptDraft'));
    assert.ok(nativeBrowserView.includes('private var pendingScriptDraft: NativeBrowserPendingScriptDraft? = null'));
    assert.ok(nativeBrowserView.includes('createPendingDraftCard(draft, refreshLibrary)'));
    assert.ok(nativeBrowserView.includes('savePendingDraftAsScript(draft, refreshLibrary)'));
    assert.ok(nativeBrowserView.includes('discardPendingDraft(refreshLibrary)'));
    assert.ok(nativeBrowserView.includes('"browser_script_stage" to "script_stage"'));
    assert.ok(nativeBrowserView.includes('"browser_script_save" to "script_save"'));
    assert.ok(nativeBrowserView.includes('"browser_script_run" to "script_run"'));
    assert.ok(nativeBrowserView.includes('"browser_user_script_save" to "user_script_save"'));
    assert.ok(nativeBrowserView.includes('"pendingScriptDraft" to pendingScriptDraft?.toJsonMap()'));
    assert.ok(nativeBrowserView.includes('private fun runSavedScriptFromPayload('));
    assert.ok(nativeBrowserView.includes('private fun stageScriptDraft(payload: Map<String, Any?>): Map<String, Any?>'));
    assert.ok(nativeBrowserView.includes('background = flatControlDrawable(NativeUiPalette.surfaceAlt)'));
    assert.ok(nativeBrowserView.includes('webViewContainer.setPadding(0, 0, 0, 0)'));
    assert.ok(nativeBrowserView.includes('private fun createMoreMenuItem('));
    assert.ok(nativeBrowserView.includes('text = "浏览器工具"'));
    assert.ok(nativeBrowserView.includes('private fun createActionButton(iconRes: Int, description: String, onClick: () -> Unit): FrameLayout'));
    assert.ok(nativeBrowserView.includes('performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)'));
    assert.ok(nativeBrowserView.includes('private fun smallActionIcon(label: String): Int?'));
    assert.ok(nativeBrowserView.includes('tintedIcon(if (showInspector) R.drawable.lucide_eye_off else R.drawable.lucide_eye)'));
    assert.ok(nativeBrowserView.includes('R.drawable.lucide_share_2'));
    assert.ok(nativeBrowserView.includes('normalized.contains("看源码") -> R.drawable.lucide_eye'));
    assert.ok(nativeBrowserView.includes('normalized.contains("让") || normalized.contains("Codex") -> R.drawable.lucide_audio_waveform'));
    assert.ok(nativeBrowserView.includes('automationTab.isSelected = workspaceIndex == 0'));
    assert.ok(nativeBrowserView.includes('userTab.isSelected = workspaceIndex == 1'));
    assert.ok(!nativeBrowserView.includes('PopupMenu(context, anchor)'));
    assert.ok(!nativeBrowserView.includes('rootLayout.addView(addressRow)'));
    assert.ok(nativeBrowserView.includes('createSmallActionButton("保存最近流程"'));
    assert.ok(nativeBrowserView.includes('createSmallActionButton("新增传统脚本")'));
    assert.ok(nativeBrowserView.includes('createSmallActionButton("运行当前页")'));
    assert.ok(nativeBrowserView.includes('createSmallActionButton("导入")'));
    assert.ok(manifest.includes('android:name=".NativeTerminalActivity"'));
    assert.ok(manifest.includes('android:name=".NativeTerminalPagerActivity"'));
    assert.ok(manifest.includes('android:windowSoftInputMode="adjustResize"'));
    assert.ok(mainActivity.includes('"setWindowSoftInputMode" -> {'));
    assert.ok(mainActivity.includes('SOFT_INPUT_ADJUST_NOTHING'));
    assert.ok(mainActivity.includes('SOFT_INPUT_ADJUST_RESIZE'));
  });

  test('saving CLI API settings synchronizes the local Codex proxy process', () => {
    const cliApiConfig = readFileSync(
      join(projectRoot, 'flutter_app/lib/services/cli_api_config_service.dart'),
      'utf8',
    );
    assert.ok(cliApiConfig.includes('await _syncCodexProxyProcess();'));
    assert.ok(cliApiConfig.includes('pkill -f "[c]odex-proxy.py"'));
    assert.ok(cliApiConfig.includes('pkill -f "[c]odex-proxy.js"'));
    assert.ok(cliApiConfig.includes('openclaw_kill_codex_proxy_port()'));
    assert.ok(cliApiConfig.includes('/proc/net/tcp'));
    assert.ok(cliApiConfig.includes('allow_reuse_address = True'));
    assert.ok(cliApiConfig.includes('grep -q "^OPENCLAW_CODEX_PROXY_UPSTREAM="'));
    assert.ok(cliApiConfig.includes('set -a'));
    assert.ok(cliApiConfig.includes('.replaceAll(\'__ENV_PATH__\', _codexProxyEnvPath)'));
    assert.ok(cliApiConfig.includes('nohup python3 __PY_PATH__'));
    assert.ok(cliApiConfig.includes('nohup node __JS_PATH__'));
    assert.ok(cliApiConfig.includes('http://127.0.0.1:8787/health'));
    assert.ok(cliApiConfig.includes('grep -F -- "$OPENCLAW_CODEX_PROXY_UPSTREAM"'));
    assert.ok(cliApiConfig.includes('Codex proxy did not become ready on 127.0.0.1:8787'));
    assert.ok(cliApiConfig.includes('configure_codex_termux_runtime || true'));
    assert.ok(cliApiConfig.includes('refusing to fall back to a stale provider'));
    assert.ok(!cliApiConfig.includes('localhost:'));
    assert.ok(cliApiConfig.includes('sharedProfiles.length == 1'));
    assert.ok(cliApiConfig.includes('? sharedProfiles.single'));
    assert.ok(cliApiConfig.includes('codexSharedProfileId'));
    assert.ok(cliApiConfig.includes('RootFS 配置写入失败'));
    assert.ok(cliApiConfig.includes('同步 Ubuntu RootFS 失败'));
    const cliApiDialog = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/cli_api_config_dialog.dart'),
      'utf8',
    );
    assert.ok(cliApiDialog.includes('final savedProfileId = await CliApiProfilesDialog.show(context);'));
    assert.ok(cliApiDialog.includes('requested: savedProfileId'));
    assert.ok(cliApiDialog.includes('_toolSettings(sharedProfileId: selectedProfileId)'));
    const cliApiProfilesDialog = readFileSync(
      join(projectRoot, 'flutter_app/lib/widgets/cli_api_profiles_dialog.dart'),
      'utf8',
    );
    assert.ok(cliApiProfilesDialog.includes('Navigator.of(context).pop(selectedProfileId)'));
    assert.ok(cliApiProfilesDialog.includes('codexSharedProfileId: selectedProfileId'));
    const setupWizard = readFileSync(
      join(projectRoot, 'flutter_app/lib/screens/setup_wizard_screen.dart'),
      'utf8',
    );
    assert.ok(setupWizard.includes('final savedProfileId = await CliApiProfilesDialog.show(context);'));
    assert.ok(setupWizard.includes('if (savedProfileId != null)'));
  });

  test('native terminal exposes a bottom input strip for IME panning', () => {
    const nativeTerminalView = readFileSync(
      join(
        projectRoot,
        'flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalSessionView.kt',
      ),
      'utf8',
    );
    const pagerActivity = readFileSync(
      join(
        projectRoot,
        'flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalPagerActivity.kt',
      ),
      'utf8',
    );
    assert.ok(nativeTerminalView.includes('private val inputStripRect = Rect()'));
    assert.ok(nativeTerminalView.includes('private val contentContainer = LinearLayout(context)'));
    assert.ok(nativeTerminalView.includes('val useCodexChrome: Boolean = false'));
    assert.ok(nativeTerminalView.includes('private fun requestInputStripVisible()'));
    assert.ok(nativeTerminalView.includes('if (config.useNativeToolbar && toolbar != null) {'));
    assert.ok(nativeTerminalView.includes('terminalView.requestRectangleOnScreen(inputStripRect, true)'));
    assert.ok(nativeTerminalView.includes('requestRectangleOnScreen(parentInputStripRect, true)'));
    assert.ok(!nativeTerminalView.includes('toolbar.requestRectangleOnScreen(inputStripRect, true)'));
    assert.ok(pagerActivity.includes('pagesContainer.updatePadding(bottom = if (imeVisible) imeBottom else systemBars.bottom)'));
    assert.ok(pagerActivity.includes('val imeBottom = (imeInsets.bottom - navigationBars.bottom).coerceAtLeast(0)'));
    assert.ok(!nativeTerminalView.includes('private fun updateImeCompensation()'));
    assert.ok(!nativeTerminalView.includes('contentContainer.setPadding('));
    assert.ok(!nativeTerminalView.includes('KEYBOARD_VISIBLE_THRESHOLD_DP'));
    assert.ok(!nativeTerminalView.includes('OnGlobalLayoutListener'));
    assert.ok(!nativeTerminalView.includes('imePostLayoutRefreshRunnable'));
    assert.ok(!nativeTerminalView.includes('private class ImeAwareTerminalView('));
  });

  test('cloud build derives the next Android build number from the latest release artifact', () => {
    const workflow = readFileSync(
      join(projectRoot, '.github/workflows/flutter-build.yml'),
      'utf8',
    );
    assert.ok(workflow.includes('repos/${GITHUB_REPOSITORY}/releases?per_page=20'));
    assert.ok(workflow.includes('LATEST_RELEASE_BUILD'));
    assert.ok(workflow.includes('MINIMUM_RELEASE_BUILD=166'));
    assert.ok(
      workflow.includes(
        'Unable to determine the latest published Android build number from GitHub Releases.',
      ),
    );
    assert.ok(
      workflow.includes(
        'This workflow refuses to silently fall back to ${MINIMUM_RELEASE_BUILD}',
      ),
    );
    assert.ok(!workflow.includes('GENERATED_VERSION_CODE="${GITHUB_RUN_NUMBER:-0}"'));
  });

  console.log('\n🧩 Runtime Versioning:');

  test('Node runtime defaults match current OpenClaw engine floor', () => {
    const expectedNodeVersion = '24.15.0';
    const expectedArmv7NodeVersion = '22.22.3';
    const staleNodeVersion = '24.14.1';
    const staleArmv7NodeVersion = '22.22.2';
    const checkedFiles = [
      'flutter_app/lib/constants.dart',
      'scripts/build-prebuilt-rootfs.sh',
      'scripts/prebuilt-rootfs-metadata.sh',
      'flutter_app/lib/l10n/app_strings_en.dart',
      'flutter_app/lib/l10n/app_strings_ja.dart',
      'flutter_app/lib/l10n/app_strings_zh_hans.dart',
      'flutter_app/lib/l10n/app_strings_zh_hant.dart',
      'flutter_app/assets/bootstrap/README.md',
      'flutter_app/assets/bootstrap/basic-resource-release.zh.md',
      'README.md',
      'docs/README_en.md',
      'STRUCTURE.md',
      'CHANGELOG.md',
      'lib/installer.js',
      'THIRD_PARTY_NOTICES.md',
      'OPEN_SOURCE_SOURCES.md',
    ];
    const armv7CheckedFiles = [
      'flutter_app/lib/constants.dart',
      'flutter_app/lib/l10n/app_strings_en.dart',
      'flutter_app/lib/l10n/app_strings_ja.dart',
      'flutter_app/lib/l10n/app_strings_zh_hans.dart',
      'flutter_app/lib/l10n/app_strings_zh_hant.dart',
      'README.md',
      'docs/README_en.md',
      'STRUCTURE.md',
      'CHANGELOG.md',
      'THIRD_PARTY_NOTICES.md',
    ];
    const currentRuntimeContents = (relativePath) => {
      const contents = readFileSync(join(projectRoot, relativePath), 'utf8');
      if (relativePath === 'CHANGELOG.md') {
        return contents.split('\n## v2.0.2 ')[0];
      }
      if (relativePath === 'STRUCTURE.md') {
        return contents.split('\n## 9. 构建与发布流程')[0];
      }
      return contents;
    };

    for (const relativePath of checkedFiles) {
      const contents = currentRuntimeContents(relativePath);
      assert.ok(
        contents.includes(expectedNodeVersion),
        `${relativePath} should reference Node.js ${expectedNodeVersion}`,
      );
      assert.ok(
        !contents.includes(staleNodeVersion),
        `${relativePath} should not reference stale Node.js ${staleNodeVersion}`,
      );
    }

    for (const relativePath of armv7CheckedFiles) {
      const contents = currentRuntimeContents(relativePath);
      assert.ok(
        contents.includes(expectedArmv7NodeVersion),
        `${relativePath} should reference armv7 Node.js ${expectedArmv7NodeVersion}`,
      );
      assert.ok(
        !contents.includes(staleArmv7NodeVersion),
        `${relativePath} should not reference stale armv7 Node.js ${staleArmv7NodeVersion}`,
      );
    }

    const pubspec = readFileSync(join(projectRoot, 'flutter_app/pubspec.yaml'), 'utf8');
    assert.ok(
      !pubspec.includes('assets/bootstrap/node-v'),
      'Node.js tarball caches should not be packaged directly into the APK',
    );
    assert.ok(
      readFileSync(join(projectRoot, 'flutter_app/assets/bootstrap/README.md'), 'utf8')
        .includes(`node-v${expectedNodeVersion}-linux-arm64.tar.xz`),
      'bootstrap README should document the current Node.js fallback archive name',
    );
  });

  // Bionic bypass functionality
  console.log('\n🔧 Bionic Bypass:');

  test('os.networkInterfaces returns object after bypass', () => {
    const interfaces = os.networkInterfaces();
    assert.ok(typeof interfaces === 'object');
  });

  // Summary
  console.log('\n' + '─'.repeat(40));
  console.log(`\n📊 Results: ${passed} passed, ${failed} failed\n`);

  if (failed > 0) {
    process.exit(1);
  }
}

runTests();
