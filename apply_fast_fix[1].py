#!/usr/bin/env python3
"""Apply Jarvis fast HUD controls + performance fixes to StudentBroken/solos-hud.

Compatible with current main and the earlier apply_jarvis_upgrade.py patch.
Runs --check without writing, or --apply atomically after verifying all source markers.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re

class PatchError(RuntimeError):
    pass

def exact(text: str, before: str, after: str, label: str) -> str:
    occurrences = text.count(before)
    if occurrences != 1:
        raise PatchError(f'{label}: expected one source match, got {occurrences}')
    return text.replace(before, after, 1)

def regex_one(text: str, pattern: str, replace: str, label: str) -> str:
    result, n = re.subn(pattern, lambda _: replace, text, count=0, flags=re.S)
    if n != 1:
        raise PatchError(f'{label}: expected one region, got {n}')
    return result

def patch_menu(c: str) -> str:
    # Use short releases only: buttonMake + buttonShort can otherwise scroll twice.
    c = exact(c, '  static const _doubleTapWindow = Duration(milliseconds: 600);',
              '  static const _doubleTapWindow = Duration(milliseconds: 320);', 'double-tap window') if 'milliseconds: 600' in c else c
    c = exact(c, '  static const _doubleTapWindow = Duration(milliseconds: 360);',
              '  static const _doubleTapWindow = Duration(milliseconds: 320);', 'old delayed fix window') if 'milliseconds: 360' in c else c
    if '  void Function(int direction)? onPageSwitch;' not in c:
        c = exact(c, '  void Function(GlassesEvent)? onActiveAppButton;',
                  '  bool Function(GlassesEvent)? onActiveAppButton;\n  void Function(int direction)? onPageSwitch;',
                  'menu callbacks')
        c = exact(c, '    this.onActiveAppButton,\n  });',
                  '    this.onActiveAppButton,\n    this.onPageSwitch,\n  });', 'menu constructor')
    else:
        c = exact(c, '  void Function(GlassesEvent)? onActiveAppButton;',
                  '  bool Function(GlassesEvent)? onActiveAppButton;', 'upgrade menu callback type')
    c = exact(c, '      if (action == GlassesActionType.buttonBreak) return;',
              '      if (action == GlassesActionType.buttonBreak ||\n          action == GlassesActionType.buttonMake) return;',
              'menu raw-event deduplication')
    for button, fn in [('front','_scrollUp()'),('back','_scrollDown()')]:
        before = ('if ((action == GlassesActionType.buttonMake ||\n'
                  '                  action == GlassesActionType.buttonShort) &&\n'
                  '              _debounced(btn)) {\n            '+fn+';\n          }')
        after = ('if (action == GlassesActionType.buttonShort &&\n'
                 '              _debounced(btn)) {\n            '+fn+';\n          }')
        if before in c:
            c=exact(c,before,after,'menu '+button+' dedup')
    # Remove delayed tap handling from previous patch: a short press must switch NOW.
    replacement = '''    // Instant page switching on each clean release: no 360ms wait.
    // Double-taps still provide the optional voice/music shortcuts.
    if (btn == GlassesButton.front && action == GlassesActionType.buttonShort) {
      final now = DateTime.now();
      final doubleTap = _lastFrontShort != null &&
          now.difference(_lastFrontShort!) <= _doubleTapWindow;
      _lastFrontShort = doubleTap ? null : now;
      if (doubleTap) {
        _triggerAssistant();
      } else if (onPageSwitch != null) {
        onPageSwitch!(1);
      } else {
        onActiveAppButton?.call(event);
      }
      return;
    }

    if (btn == GlassesButton.back && action == GlassesActionType.buttonShort) {
      final now = DateTime.now();
      final doubleTap = _lastBackShort != null &&
          now.difference(_lastBackShort!) <= _doubleTapWindow;
      _lastBackShort = doubleTap ? null : now;
      if (doubleTap) {
        _openMusicOverlay();
      } else if (onPageSwitch != null) {
        onPageSwitch!(-1);
      } else {
        onActiveAppButton?.call(event);
      }
      return;
    }

    // MAIN short: keep mini-app controls (e.g. play/pause). If the active
    // page did not handle the press, open Jarvis immediately.
    if (btn == GlassesButton.main && action == GlassesActionType.buttonShort) {
      final handled = onActiveAppButton?.call(event) ?? false;
      if (!handled) _triggerAssistant();
      return;
    }

'''
    c=regex_one(c,
        r'    // FRONT short → double-tap = assistant, single = forward to app.*?(?=    // All other events go to the active app)',
        replacement,'replace delayed front/back tap logic')
    # The first short changes the page immediately. A second short within the
    # double-tap window triggers the shortcut instead of delaying a single tap.
    c=c.replace('///   FRONT single-tap  → forwarded to the active app (e.g. prev track)',
                '///   FRONT single-tap  → next HUD page, immediately')
    c=c.replace('///   BACK  single-tap  → forwarded to the active app (e.g. next track)',
                '///   BACK  single-tap  → previous HUD page, immediately')
    c=c.replace('///   FRONT single-tap  → next HUD page (wraps around)',
                '///   FRONT single-tap  → next HUD page, immediately')
    c=c.replace('///   BACK  single-tap  → previous HUD page (wraps around)',
                '///   BACK  single-tap  → previous HUD page, immediately')
    # Cancel any v1 delayed timers in case its callbacks were set before refresh.
    if '_frontTapTimer' in c:
        # Previous upgrade introduced helper; keep cleanup for safe lifecycle.
        pass
    # Cache menu bitmap between actual selection/battery changes.
    if 'Uint8List? _cachedMenuFrame;' not in c:
        c=exact(c, '  Timer? _autoCloseTimer;',
                '  Timer? _autoCloseTimer;\n  Uint8List? _cachedMenuFrame;\n  String? _cachedMenuKey;',
                'menu cached frame fields')
    old='''  Future<Uint8List> renderFrame() {
    final items = apps'''
    new='''  Future<Uint8List> renderFrame() async {
    final key = '${_selectedIndex}:${apps.length}:${apps.indexOf(activeApp)}:'
        '${events.batteryLabel}:${events.batteryLevel}';
    if (key == _cachedMenuKey && _cachedMenuFrame != null) {
      return _cachedMenuFrame!;
    }
    final items = apps'''
    c=exact(c,old,new,'menu render cache fast path')
    c=exact(c,'''    return GlassesMenuRenderer.render(
      items: items,
      selectedIndex: _selectedIndex,
      batteryLabel: events.batteryLabel,
      batteryLevel: events.batteryLevel,
    );''', '''    final frame = await GlassesMenuRenderer.render(
      items: items,
      selectedIndex: _selectedIndex,
      batteryLabel: events.batteryLabel,
      batteryLevel: events.batteryLevel,
    );
    if (!_disposed) {
      _cachedMenuKey = key;
      _cachedMenuFrame = frame;
    }
    return frame;''', 'menu render cache store')
    return c

def patch_app(c: str) -> str:
    old='onActiveAppButton: (event) => _hud.activeApp?.onButtonEvent(event),'
    new='onActiveAppButton: (event) => _hud.activeApp?.onButtonEvent(event) ?? false,'
    c=exact(c,old,new,'active mini-app button boolean')
    if 'onPageSwitch: _switchHudPage,' not in c:
        c=exact(c,new,new+'\n      onPageSwitch: _switchHudPage,','app navigation wire')
    if '  void _switchHudPage(int direction) {' not in c:
        c=exact(c,'  void _onMenuLaunch(GlassesApp app) {', '''  void _switchHudPage(int direction) {
    if (!_loaded || _apps.isEmpty) return;
    final current = _apps.indexWhere((a) => identical(a, _hud.activeApp));
    final start = current >= 0 ? current : 0;
    final next = (start + direction + _apps.length) % _apps.length;
    if (next == start) return;
    final target = _apps[next];
    _hud.setActiveApp(target);
    _glassesMenu.activeApp = target;
    if (!_hud.running) _hud.startLoop();
    _hud.requestRefresh();
  }

  void _onMenuLaunch(GlassesApp app) {''', 'app page switch handler')
    else:
        c=exact(c, '''    if (!_hud.running) _hud.startLoop();
  }

  void _onMenuLaunch(GlassesApp app) {''', '''    if (!_hud.running) _hud.startLoop();
    _hud.requestRefresh();
  }

  void _onMenuLaunch(GlassesApp app) {''','v1 page switch immediate')
    return c

def patch_hud(c: str) -> str:
    if 'if (identical(_activeApp, app)) return;' not in c:
        c=exact(c, '''  void setActiveApp(GlassesApp? app) {
    _activeApp?.onDeactivate();''', '''  void setActiveApp(GlassesApp? app) {
    if (identical(_activeApp, app)) return;
    _activeApp?.onDeactivate();''','avoid duplicate page setup')
    c=exact(c, '''    _tickCount = 0;
    notifyListeners();
  }

  void startLoop() {''','''    _tickCount = 0;
    notifyListeners();
    requestRefresh();
  }

  // A button press preempts the normal refresh timer, without overlapping sends.
  bool _refreshPending = false;
  void requestRefresh() {
    if (!_running || !rfcomm.isConnected) return;
    if (_rendering) {
      _refreshPending = true;
      return;
    }
    _timer?.cancel();
    _timer = Timer(Duration.zero, _tick);
  }

  void startLoop() {''','urgent frame refresh')
    c=exact(c,'''    _running = true;
    _scheduleNext();''','''    _running = true;
    _timer?.cancel();
    _timer = Timer(Duration.zero, _tick);''','fast first frame')
    c=exact(c,'''    _timer?.cancel();
    _running = false;
    notifyListeners();''','''    _timer?.cancel();
    _refreshPending = false;
    _lastSentFrame = null; // reconnect always gets a full fresh frame
    _running = false;
    notifyListeners();''','clear queued refresh on stop')
    # Replaces both the original fixed frame rate and the previous patch pace.
    c=regex_one(c,
        r'    final delay = \(targetMs - elapsedMs\)\.clamp\(0, targetMs\);\n    _timer = Timer\(Duration\(milliseconds: delay\), _tick\);|    // Leave breathing room after a slow frame: never spin at 0ms\.\n    final pacedMs = targetMs\.clamp\(150, 9999\);\n    final delay = \(pacedMs - elapsedMs\)\.clamp\(40, pacedMs\);\n    _timer = Timer\(Duration\(milliseconds: delay\), _tick\);',
        '''    // Heavy image encoding at very high FPS stalls iOS touch handling.
    final pacedMs = targetMs.clamp(500, 9999);
    final delay = (pacedMs - elapsedMs).clamp(70, pacedMs);
    if (_refreshPending) {
      _refreshPending = false;
      _timer = Timer(Duration.zero, _tick);
    } else {
      _timer = Timer(Duration(milliseconds: delay), _tick);
    }''', 'throttled non-busy display refresh')
    if 'static const _previewThrottle = Duration(milliseconds: 900);' in c:
        c=exact(c,'static const _previewThrottle = Duration(milliseconds: 900);',
                'static const _previewThrottle = Duration(milliseconds: 1400);', 'preview decode throttle')
    if '''      packet = SolosProtocol.buildImagePacket(imageData: customRle);''' in c:
        c=exact(c,'''      packet = SolosProtocol.buildImagePacket(imageData: customRle);''',
                '''      packet = SolosProtocol.buildImagePacket(
        imageData: customRle,
        codec: _activeApp!.preferredCodec,
      );''', 'sendNow correct JPEG codec')
    if '      } catch (e) {\n        // A transient radio/render failure must not permanently kill the HUD.' not in c:
        c=exact(c,'''      } finally {
        _rendering = false;
      }
    }

    if (_running) _scheduleNext(elapsedMs: _tickSw.elapsedMilliseconds);''', '''      } catch (e) {
        debugPrint('[HUD] tick: $e');
      } finally {
        _rendering = false;
      }
    }

    if (_running) _scheduleNext(elapsedMs: _tickSw.elapsedMilliseconds);''', 'protect HUD timer after errors')
    # The image protocol is deterministic: skip retransmitting identical frames
    # until periodic refresh for resilience. Wake-up frames are sent separately.
    c=exact(c,'''  int _tickCount = 0;
  String? _lastPayload;''','''  int _tickCount = 0;
  String? _lastPayload;
  Uint8List? _lastSentFrame;
  DateTime _lastFrameSentAt = DateTime(1970);
  static const _maxDuplicateAge = Duration(seconds: 5);

  Future<bool> _sendFrame(Uint8List packet) async {
    final now = DateTime.now();
    if (_lastSentFrame != null &&
        listEquals(_lastSentFrame, packet) &&
        now.difference(_lastFrameSentAt) < _maxDuplicateAge) {
      return false;
    }
    final didSend = await rfcomm.sendBytes(packet);
    if (didSend) {
      _lastSentFrame = packet;
      _lastFrameSentAt = DateTime.now();
    }
    return didSend;
  }''','deduplicate redundant frames')
    c=exact(c, '''    _lastPayload = null;
    _tickCount = 0;''','''    _lastPayload = null;
    _lastSentFrame = null;
    _tickCount = 0;''','invalidate frame on page switch')
    # All HUD draw branches call this; keep other radio control sends direct.
    # Take the substring of _tick only so sendNow is independent.
    begin=c.index('  Future<void> _tick() async {')
    end=c.index('  /// Force a single frame send',begin)
    block=c[begin:end]
    if block.count('await rfcomm.sendBytes(packet);') < 2:
        raise PatchError('expected overlay + active frame sends')
    block=block.replace('''await rfcomm.sendBytes(packet);
          _tickCount++;
          notifyListeners();''', '''if (await _sendFrame(packet)) {
            _tickCount++;
            notifyListeners();
          }''')
    # All other send calls still operate, but redundant packets are skipped.
    block=block.replace('await rfcomm.sendBytes(packet);','await _sendFrame(packet);')
    block=block.replace('''await rfcomm.sendBytes(
                SolosProtocol.buildImagePacket(imageData: rle),
              );''','''await _sendFrame(
                SolosProtocol.buildImagePacket(imageData: rle),
              );''')
    # A button can switch apps while a frame is encoding. Do not send a
    # frame from the old app with the new app's codec.
    block=exact(block, '''        Uint8List? packet;
        try {
          final customData = await _activeApp!.buildCustomFrame();''', '''        final currentApp = _activeApp!;
        Uint8List? packet;
        try {
          final customData = await currentApp.buildCustomFrame();''', 'capture active app for frame')
    block=block.replace('_activeApp!.preferredCodec', 'currentApp.preferredCodec')
    block=block.replace('_activeApp!.buildGlassesPayload()', 'currentApp.buildGlassesPayload()')
    block=exact(block, '''        if (packet != null) {
          if (await _sendFrame(packet)) {''', '''        if (packet != null && identical(_activeApp, currentApp)) {
          if (await _sendFrame(packet)) {''', 'skip stale frame after navigation')
    c=c[:begin]+block+c[end:]
    return c

def patch_dashboard(c: str) -> str:
    # Rendering and JPEG encoding the same 428x240 frame several times per
    # second is expensive. Reuse it until a displayed value or setting changes.
    c=exact(c,
        '''  @override void onActivate() { gps.init(); }
  @override void onDeactivate() {}''',
        '''  Uint8List? _cachedFrame;
  String? _cachedFrameKey;

  @override void onActivate() { gps.init(); }
  @override void onDeactivate() {
    _cachedFrame = null;
    _cachedFrameKey = null;
  }''', 'dashboard frame cache fields')
    c=exact(c,
        '    return DashboardRenderer.render(data, cfg);',
        '''    final key = '${data.time.year}-${data.time.month}-${data.time.day}-'
        '${data.time.hour}:${data.time.minute}:${data.time.second}|'
        '${data.speedKmh?.toStringAsFixed(1)}|${data.speedUnit}|'
        '${data.heartRate}|${data.batteryPct}|${data.batteryCharging}|'
        '${data.headingDeg?.toStringAsFixed(0)}|'
        '${cfg.showTime}:${cfg.showBattery}:${cfg.showSpeed}:'
        '${cfg.showHr}:${cfg.showCompass}:${cfg.primaryMetric}';
    if (_cachedFrame != null && key == _cachedFrameKey) {
      return _cachedFrame;
    }
    final frame = await DashboardRenderer.render(data, cfg);
    _cachedFrameKey = key;
    _cachedFrame = frame;
    return frame;''', 'dashboard skip duplicate JPEG encoding')
    return c

def patch_home(c: str) -> str:
    c=exact(c,'''    final rfcomm = context.watch<RfcommService>();
    final hud    = context.watch<HudController>();

    final isConnected  = rfcomm.isConnected;
    final isConnecting = rfcomm.state == RfcommState.connecting;''','''    // Only connection/page changes should rebuild the full home screen.
    final rfcomm = context.read<RfcommService>();
    final connectionState = context.select<RfcommService, RfcommState>(
      (r) => r.state,
    );
    final activeApp = context.select<HudController, GlassesApp?>(
      (h) => h.activeApp,
    );

    final isConnected = connectionState == RfcommState.connected;
    final isConnecting = connectionState == RfcommState.connecting;''','home selector')
    c=exact(c,'\n    final activeApp = hud.activeApp;\n\n    return Scaffold(', '\n    return Scaffold(', 'remove old activeApp read')
    c=exact(c,'''    final rfcomm = context.watch<RfcommService>();
    final events = context.watch<GlassesEventService>();
    final menu   = context.watch<GlassesMenuController>();
    final hud    = context.watch<HudController>();
    final cs     = Theme.of(context).colorScheme;

    final isConnected = rfcomm.isConnected;''','''    final rfcomm = context.read<RfcommService>();
    final isConnected = context.select<RfcommService, bool>((r) => r.isConnected);
    final deviceName = context.select<RfcommService, String?>((r) => r.device?.name);
    final batteryLevel = context.select<GlassesEventService, int?>((e) => e.batteryLevel);
    final charging = context.select<GlassesEventService, bool?>((e) => e.isCharging);
    final menuOpen = context.select<GlassesMenuController, bool>((m) => m.isOpen);
    final activeApp = context.select<HudController, GlassesApp?>((h) => h.activeApp);
    final cs = Theme.of(context).colorScheme;
''','status-bar targeted selectors')
    # Scoped to _TopStatusBar, not the rest of the long file.
    a=c.index('class _TopStatusBar extends StatelessWidget')
    b=c.index('// Glasses preview strip',a)
    front=c[:a]; bar=c[a:b]; tail=c[b:]
    bar=bar.replace('rfcomm.device?.name ??', 'deviceName ??')
    bar=bar.replace('hud.activeApp', 'activeApp')
    bar=bar.replace('menu.isOpen', 'menuOpen')
    bar=bar.replace('events.batteryLevel', 'batteryLevel')
    bar=bar.replace('events.isCharging', 'charging')
    return front+bar+tail

PATCHERS = {
    'solos_hud/lib/core/hud_ui/glasses_menu_controller.dart': patch_menu,
    'solos_hud/lib/app.dart': patch_app,
    'solos_hud/lib/core/hud_controller.dart': patch_hud,
    'solos_hud/lib/screens/home_screen.dart': patch_home,
    'solos_hud/lib/apps/dashboard/dashboard_app.dart': patch_dashboard,
}

def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check',action='store_true')
    mode.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    root=Path.cwd()
    staged={}
    for name,fn in PATCHERS.items():
        path=root/name
        if not path.is_file():
            raise PatchError(f'File missing: {path}. Run from repo root, NOT solos_hud/')
        original=path.read_text(encoding='utf-8')
        updated=fn(original)
        if updated==original:
            raise PatchError(f'No patch applied to {name}')
        staged[path]=updated
        print('READY',name)
    if args.apply:
        for path,data in staged.items():
            path.write_text(data,encoding='utf-8')
            print('UPDATED',path)
        print('Patch applied. Now commit changes to GitHub and run your IPA workflow.')
    else:
        print('Dry-run passed: all expected source markers found; no files changed.')

if __name__=='__main__':
    try:
        main()
    except PatchError as exc:
        raise SystemExit('STOP: '+str(exc))
