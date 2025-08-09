import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BonfireApp());
}

class BonfireApp extends StatelessWidget {
  const BonfireApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bonfire',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const CampfireScreen(),
    );
  }
}

class CampfireScreen extends StatefulWidget {
  const CampfireScreen({super.key});

  @override
  State<CampfireScreen> createState() => _CampfireScreenState();
}

class _CampfireScreenState extends State<CampfireScreen>
    with TickerProviderStateMixin {
  late final AnimationController _flickerController; // ゆらぎ
  late final AnimationController _flameController; // 炎強度 0..1
  late final AudioPlayer _player;
  double _currentVolume = 0.0;
  double _userVolume = 0.6; // ユーザー設定音量(0.0-1.0)
  bool _isUnlimited = false; // 無制限モード

  Duration _remaining = Duration.zero;
  DateTime? _endAt;
  bool get _isTimerRunning =>
      _isUnlimited || (_endAt != null && _remaining > Duration.zero);

  @override
  void initState() {
    super.initState();
    _flickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _flameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 0.0,
    );

    _player = AudioPlayer();
    // タイマー監視ティッカー（1秒）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tickTimer();
    });
  }

  Future<void> _playAudioFadeIn() async {
    try {
      if (_player.state != PlayerState.playing) {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.setVolume(0.0);
        _currentVolume = 0.0;
        await _player.play(AssetSource('audio/campfire.mp3'));
      }
      const steps = 20;
      for (int i = 0; i <= steps; i++) {
        await Future.delayed(const Duration(milliseconds: 40));
        _currentVolume = (_userVolume * i / steps);
        await _player.setVolume(_currentVolume);
      }
    } catch (_) {}
  }

  Future<void> _fadeOutAndPauseAudio() async {
    try {
      const steps = 15;
      for (int i = steps; i >= 0; i--) {
        await Future.delayed(const Duration(milliseconds: 50));
        final v = _currentVolume * (i / steps);
        _currentVolume = v;
        await _player.setVolume(v);
      }
      await _player.pause();
    } catch (_) {}
  }

  void _startTimer(Duration duration) async {
    _isUnlimited = false;
    _endAt = DateTime.now().add(duration);
    setState(() {
      _remaining = duration;
    });
    // 炎オン（フェードイン開始）
    _flameController.value = 0.001; // 最低限の描画を即時開始
    setState(() {});
    await _flameController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
    );
    // サウンド
    await _playAudioFadeIn();
    // 画面スリープ防止（失敗しても続行）
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    _tickTimer();
  }

  Future<void> _startUnlimited() async {
    _isUnlimited = true;
    _endAt = null;
    setState(() {
      _remaining = Duration.zero;
    });
    // 炎オン（フェードイン）
    _flameController.value = 0.001;
    setState(() {});
    await _flameController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
    );
    // サウンド
    await _playAudioFadeIn();
    // 画面スリープ防止
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  void _cancelTimerAndExtinguish() async {
    _endAt = null;
    _isUnlimited = false;
    setState(() {
      _remaining = Duration.zero;
    });
    // 炎オフ（フェードアウト）
    await _flameController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 1200),
    );
    // サウンド停止
    await _fadeOutAndPauseAudio();
    // スリープ許可（失敗しても続行）
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  Future<void> _tickTimer() async {
    if (!mounted) return;
    if (_endAt == null) return;
    while (mounted && _endAt != null) {
      final now = DateTime.now();
      final diff = _endAt!.difference(now);
      if (diff <= Duration.zero) {
        // タイムアップ
        _cancelTimerAndExtinguish();
        break;
      } else {
        setState(() {
          _remaining = diff;
        });
      }
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  String _formatDuration(Duration d) {
    final total = d.inSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _flickerController.dispose();
    _flameController.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (_flameController.value > 0.0) {
          if (_player.state == PlayerState.playing) {
            await _player.pause();
          } else {
            await _player.resume();
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              const _StarrySkyBackground(),
              Center(
                child: Transform.scale(
                  scale: 2,
                  child: SizedBox(
                    width: 360,
                    height: 500,
                    child: AnimatedBuilder(
                      animation: _flameController,
                      builder: (context, _) {
                        return AnimatedBuilder(
                          animation: _flickerController,
                          builder: (context, __) {
                            return CustomPaint(
                              painter: _CampfirePainter(
                                t: _flickerController.value,
                                factor: _flameController.value,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                left: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // タイマー表示
                    AnimatedBuilder(
                      animation: _flameController,
                      builder: (context, _) {
                        final on = _flameController.value > 0.0;
                        return Text(
                          on
                              ? (_isUnlimited
                                  ? '∞'
                                  : _formatDuration(_remaining))
                              : '00:00',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 22,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        );
                      },
                    ),
                    // プリセット + 任意 + 無制限
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _TimeButton(
                          label: '5分',
                          onPressed:
                              () => _startTimer(const Duration(minutes: 5)),
                          enabled: !_isTimerRunning,
                        ),
                        _TimeButton(
                          label: '10分',
                          onPressed:
                              () => _startTimer(const Duration(minutes: 10)),
                          enabled: !_isTimerRunning,
                        ),
                        _TimeButton(
                          label: '15分',
                          onPressed:
                              () => _startTimer(const Duration(minutes: 15)),
                          enabled: !_isTimerRunning,
                        ),
                        _TimeButton(
                          label: '任意',
                          onPressed: () async {
                            final d = await _pickCustomDuration(context);
                            if (d != null && d > Duration.zero) {
                              _startTimer(d);
                            }
                          },
                          enabled: !_isTimerRunning,
                        ),
                        _TimeButton(
                          label: '無制限',
                          onPressed: _startUnlimited,
                          enabled: !_isTimerRunning,
                        ),
                        _StopButton(
                          onPressed:
                              _isTimerRunning
                                  ? _cancelTimerAndExtinguish
                                  : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  const _TimeButton({
    required this.label,
    required this.onPressed,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(label),
    );
  }
}

class _StopButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _StopButton({this.onPressed});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.stop, size: 18),
      label: const Text('停止'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF5A2A2A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }
}

class _StarrySkyBackground extends StatelessWidget {
  const _StarrySkyBackground();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback:
          (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.black],
          ).createShader(rect),
      blendMode: BlendMode.srcATop,
      child: CustomPaint(
        painter: _StarsPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  final math.Random _rand = math.Random(42);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.black;
    canvas.drawRect(Offset.zero & size, bg);

    final starPaint = Paint()..color = Colors.white.withOpacity(0.9);
    for (int i = 0; i < 160; i++) {
      final x = _rand.nextDouble() * size.width;
      final y = _rand.nextDouble() * size.height;
      final r = 0.6 + _rand.nextDouble() * 1.2;
      starPaint.color = Colors.white.withOpacity(
        0.4 + _rand.nextDouble() * 0.6,
      );
      canvas.drawCircle(Offset(x, y), r, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CampfirePainter extends CustomPainter {
  final double t; // 0..1 繰り返し
  final double factor; // 炎強度 0..1
  _CampfirePainter({required this.t, required this.factor});

  @override
  void paint(Canvas canvas, Size size) {
    if (factor <= 0.0) {
      return; // 消灯
    }

    final center = Offset(size.width / 2, size.height * 0.62);

    // 炎のノイズ的ゆらぎ
    double flicker(double seed, double scale) {
      return (math.sin((t * 2 * math.pi) + seed) +
              math.sin((t * 4 * math.pi) + seed * 1.7) * 0.5 +
              math.cos((t * 6 * math.pi) + seed * 2.3) * 0.3) *
          scale;
    }

    // 炎のレイヤー（下から上に、赤->オレンジ->黄->白）
    void drawFlameLayer({
      required double baseRadius,
      required Color color,
      required double yOffset,
      required double noiseScale,
      required double squeeze,
    }) {
      final path = Path();
      final segments = 24;
      for (int i = 0; i <= segments; i++) {
        final angle = (i / segments) * math.pi; // 半円
        final n = flicker(i * 0.37, noiseScale) * factor;
        final radius =
            (baseRadius * factor) +
            n -
            (i - segments / 2).abs() * (squeeze * factor);
        final x = center.dx + math.cos(angle) * radius;
        final y = center.dy - yOffset - math.sin(angle) * (radius * 1.6);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      final innerBase = Color.lerp(Colors.white, color, 0.35)!;
      final innerOpacity = (0.85 * factor + 0.25).clamp(0.0, 1.0);
      final outerOpacity = (0.35 * factor + 0.15).clamp(0.0, 1.0);
      final inner = innerBase.withOpacity(innerOpacity);
      final outer = color.withOpacity(outerOpacity);
      final shader = RadialGradient(
        colors: [inner, outer],
        stops: const [0.0, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: center.translate(0, -yOffset),
          radius: baseRadius * 1.6,
        ),
      );
      final paint =
          Paint()
            ..shader = shader
            ..blendMode = BlendMode.plus;
      canvas.drawPath(path, paint);
    }

    drawFlameLayer(
      baseRadius: 70,
      color: const Color(0xFFFF3B1D),
      yOffset: 0 + flicker(0.2, 6) * factor,
      noiseScale: 10,
      squeeze: 2.6,
    );
    drawFlameLayer(
      baseRadius: 54,
      color: const Color(0xFFFF7A1A),
      yOffset: 16 + flicker(0.8, 5) * factor,
      noiseScale: 8,
      squeeze: 2.2,
    );
    drawFlameLayer(
      baseRadius: 42,
      color: const Color(0xFFFFC23B),
      yOffset: 30 + flicker(1.6, 4) * factor,
      noiseScale: 6,
      squeeze: 1.8,
    );
    drawFlameLayer(
      baseRadius: 30,
      color: const Color.fromARGB(255, 255, 249, 236),
      yOffset: 42 + flicker(2.3, 3) * factor,
      noiseScale: 5,
      squeeze: 1.2,
    );

    // 火の粉
    final spark =
        Paint()
          ..color = const Color(
            0xFFFFE7A8,
          ).withOpacity(math.min(1.0, 0.95 * factor));
    final sparkCount = (18 * factor).clamp(0, 18).toInt();
    for (int i = 0; i < sparkCount; i++) {
      final a = (i * 0.7 + t * 6) % 6;
      final ox = math.sin(a * 2.0) * (14 + i * factor);
      final oy = -a * (26 + i * 2 * factor);
      final r = (1.0 + (i % 3) * 0.4) * (0.6 + 0.4 * factor);
      canvas.drawCircle(center.translate(ox, oy - 40), r, spark);
    }

    // グロー
    final glowCenter = center.translate(0, -40); // 少し上に
    final glowPaint =
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFF7A1A).withOpacity(0.6 * factor),
              Colors.transparent,
            ],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: glowCenter, radius: 200));
    canvas.drawCircle(glowCenter, 200, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _CampfirePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.factor != factor;
}

Future<Duration?> _pickCustomDuration(BuildContext context) async {
  final minutesController = TextEditingController();
  final secondsController = TextEditingController(text: '00');
  Duration? result;
  await showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('任意の時間', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '分',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: secondsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '秒',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              final m = int.tryParse(minutesController.text.trim());
              final s = int.tryParse(secondsController.text.trim());
              if (m == null && s == null) {
                Navigator.of(ctx).pop();
                return;
              }
              final mm = (m ?? 0).clamp(0, 9999);
              final ss = (s ?? 0).clamp(0, 59);
              result = Duration(minutes: mm, seconds: ss);
              Navigator.of(ctx).pop();
            },
            child: const Text('開始'),
          ),
        ],
      );
    },
  );
  return result;
}
