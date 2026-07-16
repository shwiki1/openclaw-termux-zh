import 'browser_automation_service.dart';
import 'native_bridge.dart';

class NativeBrowserAutomationDelegate implements BrowserAutomationDelegate {
  NativeBrowserAutomationDelegate._();

  static final NativeBrowserAutomationDelegate instance =
      NativeBrowserAutomationDelegate._();

  @override
  String get sessionLabel => 'native-browser-page';

  Future<Map<String, dynamic>> _invoke(
    String action, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    return NativeBridge.invokeNativeBrowserAction(action, payload);
  }

  @override
  Future<Map<String, dynamic>> back() => _invoke('back');

  @override
  Future<Map<String, dynamic>> captureSnapshot({
    String? selector,
    int maxLength = 8000,
  }) {
    return _invoke('capture_snapshot', {
      'selector': selector,
      'maxLength': maxLength,
    });
  }

  @override
  Future<Map<String, dynamic>> click({
    required String selector,
  }) => _invoke('click', {'selector': selector});

  @override
  Future<Map<String, dynamic>> clickAt({
    required double x,
    required double y,
  }) => _invoke('click_at', {'x': x, 'y': y});

  @override
  Future<Map<String, dynamic>> closeTab({
    int? id,
  }) => _invoke('tab_close', {'id': id});

  @override
  Future<Map<String, dynamic>> eval({
    required String script,
  }) => _invoke('eval', {'script': script});

  @override
  Future<Map<String, dynamic>> extract({
    String? selector,
    String? prompt,
    int maxLength = 4000,
  }) {
    return _invoke('extract', {
      'selector': selector,
      'prompt': prompt,
      'maxLength': maxLength,
    });
  }

  @override
  Future<Map<String, dynamic>> forward() => _invoke('forward');

  @override
  Future<Map<String, dynamic>> getState() => _invoke('get_state');

  @override
  Future<Map<String, dynamic>> healthCheck({
    int quietWindowMs = 500,
    int timeoutMs = 10000,
  }) {
    return _invoke('health_check', {
      'quietWindowMs': quietWindowMs,
      'timeoutMs': timeoutMs,
    });
  }

  @override
  Future<Map<String, dynamic>> highlight({
    required String selector,
  }) => _invoke('highlight', {'selector': selector});

  @override
  Future<Map<String, dynamic>> listInteractables({
    String? filter,
    int maxItems = 16,
  }) {
    return _invoke('list_interactables', {
      'filter': filter,
      'maxItems': maxItems,
    });
  }

  @override
  Future<Map<String, dynamic>> listLinks({
    String? filter,
    int maxItems = 12,
  }) => _invoke('list_links', {'filter': filter, 'maxItems': maxItems});

  @override
  Future<Map<String, dynamic>> listOverlays({
    int maxItems = 24,
  }) => _invoke('list_overlays', {'maxItems': maxItems});

  @override
  Future<Map<String, dynamic>> listTabs() => _invoke('tab_list');

  @override
  Future<Map<String, dynamic>> newTab({
    String? url,
  }) => _invoke('tab_new', {'url': url});

  @override
  Future<Map<String, dynamic>> open(String url) => _invoke('open', {'url': url});

  @override
  Future<Map<String, dynamic>> paste({
    required String selector,
    required String text,
    bool submit = false,
  }) {
    return _invoke('paste', {
      'selector': selector,
      'text': text,
      'submit': submit,
    });
  }

  @override
  Future<Map<String, dynamic>> pressKey({
    String? selector,
    required String key,
  }) => _invoke('press_key', {'selector': selector, 'key': key});

  @override
  Future<Map<String, dynamic>> reload() => _invoke('reload');

  @override
  Future<Map<String, dynamic>> resetTab({
    String? url,
  }) => _invoke('reset_tab', {'url': url});

  @override
  Future<Map<String, dynamic>> scroll({
    String? selector,
    String direction = 'down',
    int pixels = 700,
  }) {
    return _invoke('scroll', {
      'selector': selector,
      'direction': direction,
      'pixels': pixels,
    });
  }

  @override
  Future<Map<String, dynamic>> selectOption({
    required String selector,
    String? value,
    String? label,
    int? index,
  }) {
    return _invoke('select_option', {
      'selector': selector,
      'value': value,
      'label': label,
      'index': index,
    });
  }

  @override
  Future<Map<String, dynamic>> selfTest() => _invoke('self_test');

  @override
  Future<Map<String, dynamic>> setUserAgent({
    required String mode,
  }) => _invoke('set_ua', {'mode': mode});

  @override
  Future<Map<String, dynamic>> switchTab({
    required int id,
  }) => _invoke('tab_switch', {'id': id});

  @override
  Future<Map<String, dynamic>> type({
    required String selector,
    required String text,
    bool submit = false,
  }) {
    return _invoke('type', {
      'selector': selector,
      'text': text,
      'submit': submit,
    });
  }

  @override
  Future<Map<String, dynamic>> waitForResource({
    required String pattern,
    int timeoutMs = 10000,
  }) {
    return _invoke('wait_for_resource', {
      'pattern': pattern,
      'timeoutMs': timeoutMs,
    });
  }

  @override
  Future<Map<String, dynamic>> waitForSelector({
    required String selector,
    int timeoutMs = 10000,
    bool visible = true,
  }) {
    return _invoke('wait_for_selector', {
      'selector': selector,
      'timeoutMs': timeoutMs,
      'visible': visible,
    });
  }

  @override
  Future<Map<String, dynamic>> waitForText({
    required String text,
    int timeoutMs = 10000,
  }) {
    return _invoke('wait_for_text', {
      'text': text,
      'timeoutMs': timeoutMs,
    });
  }
}
