import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'player.dart';
import 'services/cover_feedback.dart';
import 'services/media_cache.dart';
import 'src/rust/api.dart' as api;
import 'src/rust/models.dart' as rust;

String decodeQrSvg(String dataUrl) {
  const prefix = 'data:image/svg+xml;base64,';
  if (!dataUrl.startsWith(prefix)) {
    throw const FormatException('不支持的二维码图像格式');
  }
  return utf8.decode(base64Decode(dataUrl.substring(prefix.length)));
}

String qrStatusText(String status) => switch (status) {
  'waiting' => '等待扫码',
  'scanned' => '已扫码，请在手机上确认',
  'expired' => '二维码已过期',
  'confirmed' => '登录成功',
  _ => '正在检查登录状态',
};

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.dark,
    required this.onThemeChanged,
    required this.coverFeedback,
    required this.onCoverFeedbackChanged,
  });

  final PlayerRepository repository;
  final bool dark;
  final ValueChanged<bool> onThemeChanged;
  final CoverFeedbackSettings coverFeedback;
  final ValueChanged<CoverFeedbackSettings> onCoverFeedbackChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool dark = widget.dark;
  late CoverFeedbackSettings _coverFeedback = widget.coverFeedback;
  String _cacheSize = '正在计算…';
  bool _clearingCache = false;
  rust.Profile? _profile;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await api.restoreSession();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {}
  }

  Future<void> _loadCacheSize() async {
    try {
      var rustBytes = BigInt.zero;
      try {
        rustBytes = await api.audioCacheSize();
      } catch (_) {}
      final coverBytes = await flutterCacheSize();
      if (!mounted) return;
      setState(
        () => _cacheSize =
            '音频 ${formatBytes(rustBytes.toInt())} · 封面 ${formatBytes(coverBytes)}',
      );
    } catch (_) {
      if (mounted) setState(() => _cacheSize = '无法读取缓存大小');
    }
  }

  Future<void> _clearCache() async {
    if (_clearingCache) return;
    setState(() => _clearingCache = true);
    try {
      await Future.wait([api.clearMediaCache(), clearFlutterMediaCache()]);
      await _loadCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('缓存已清理')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清理失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('深色模式'),
            secondary: const Icon(Icons.dark_mode_outlined),
            value: dark,
            onChanged: (value) {
              setState(() => dark = value);
              widget.onThemeChanged(value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.vibration_rounded),
            title: const Text('转盘震动强度'),
            subtitle: Slider(
              key: const Key('cover-haptic-strength'),
              value: _coverFeedback.hapticStrength,
              onChanged: (value) {
                setState(() {
                  _coverFeedback = _coverFeedback.copyWith(
                    hapticStrength: value,
                  );
                });
                widget.onCoverFeedbackChanged(_coverFeedback);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_rounded),
            title: const Text('转盘咔哒声强度'),
            subtitle: Slider(
              key: const Key('cover-sound-strength'),
              value: _coverFeedback.soundStrength,
              onChanged: (value) {
                setState(() {
                  _coverFeedback = _coverFeedback.copyWith(
                    soundStrength: value,
                  );
                });
                widget.onCoverFeedbackChanged(_coverFeedback);
              },
            ),
          ),
          ListTile(
            leading: _clearingCache
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
            title: const Text('清理缓存'),
            subtitle: Text(_cacheSize),
            onTap: _clearingCache ? null : _clearCache,
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_rounded),
            title: Text(_profile == null ? '登录网易云音乐' : '已登录'),
            subtitle: Text(
              _profile == null
                  ? '同步你的收藏'
                  : '${_profile!.nickname}  ·  ID ${_profile!.id}',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => QrLoginPage(repository: widget.repository),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class QrLoginPage extends StatefulWidget {
  const QrLoginPage({super.key, required this.repository});

  final PlayerRepository repository;

  @override
  State<QrLoginPage> createState() => _QrLoginPageState();
}

class _QrLoginPageState extends State<QrLoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _phone = TextEditingController();
  final _countryCode = TextEditingController(text: '86');
  final _code = TextEditingController();
  Timer? _pollTimer;
  String? _qrSvg;
  String? _qrKey;
  String _qrStatus = '正在生成二维码…';
  bool _checkingQr = false;
  bool _phoneBusy = false;
  bool _codeSent = false;
  int _qrGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_handleTabChanged);
    _createQr();
  }

  void _handleTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 1) {
      _pollTimer?.cancel();
    } else if (_qrKey != null && _qrStatus != qrStatusText('expired')) {
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _checkQr(),
      );
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabs.removeListener(_handleTabChanged);
    _tabs.dispose();
    _phone.dispose();
    _countryCode.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _createQr() async {
    final generation = ++_qrGeneration;
    _pollTimer?.cancel();
    setState(() {
      _qrSvg = null;
      _qrKey = null;
      _qrStatus = '正在生成二维码…';
    });
    try {
      final challenge = await api.createQrLogin();
      final svg = decodeQrSvg(challenge.imageDataUrl);
      if (!mounted || generation != _qrGeneration) return;
      setState(() {
        _qrKey = challenge.key;
        _qrSvg = svg;
        _qrStatus = qrStatusText('waiting');
      });
      if (_tabs.index == 0) {
        _pollTimer = Timer.periodic(
          const Duration(seconds: 2),
          (_) => _checkQr(),
        );
      }
    } catch (error) {
      if (mounted && generation == _qrGeneration) {
        setState(() => _qrStatus = '生成失败：$error');
      }
    }
  }

  Future<void> _checkQr() async {
    final key = _qrKey;
    final generation = _qrGeneration;
    if (key == null || _checkingQr) return;
    _checkingQr = true;
    try {
      final result = await api.checkQrLogin(key: key);
      if (!mounted ||
          generation != _qrGeneration ||
          key != _qrKey ||
          _tabs.index != 0) {
        return;
      }
      setState(() => _qrStatus = qrStatusText(result.status));
      if (result.status == 'expired' || result.status == 'confirmed') {
        _pollTimer?.cancel();
      }
      if (result.status == 'confirmed') {
        try {
          await widget.repository.reload();
        } catch (_) {}
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted && generation == _qrGeneration && key == _qrKey) {
        setState(() => _qrStatus = '检查失败：$error');
      }
    } finally {
      _checkingQr = false;
    }
  }

  Future<void> _sendCode() async {
    if (_phone.text.trim().isEmpty) return;
    setState(() => _phoneBusy = true);
    try {
      await api.sendLoginCode(
        phone: _phone.text.trim(),
        countryCode: _countryCode.text.trim(),
      );
      if (mounted) setState(() => _codeSent = true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _phoneBusy = false);
    }
  }

  Future<void> _loginWithCode() async {
    if (_phone.text.trim().isEmpty || _code.text.trim().isEmpty) return;
    setState(() => _phoneBusy = true);
    try {
      final profile = await api.loginWithCode(
        phone: _phone.text.trim(),
        countryCode: _countryCode.text.trim(),
        code: _code.text.trim(),
      );
      try {
        await widget.repository.reload();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已登录：${profile.nickname}')));
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _phoneBusy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录网易云音乐'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '扫码登录'),
            Tab(text: '手机号登录'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 256,
                    child: _qrSvg == null
                        ? const Center(child: CircularProgressIndicator())
                        : SvgPicture.string(_qrSvg!),
                  ),
                  const SizedBox(height: 20),
                  Text(_qrStatus, textAlign: TextAlign.center),
                  if (_qrStatus == qrStatusText('expired')) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _createQr,
                      icon: const Icon(Icons.refresh),
                      label: const Text('刷新二维码'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: TextField(
                      controller: _countryCode,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: '区号'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: '手机号'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_codeSent)
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '验证码'),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _phoneBusy
                    ? null
                    : (_codeSent ? _loginWithCode : _sendCode),
                child: Text(_codeSent ? '登录' : '获取验证码'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
