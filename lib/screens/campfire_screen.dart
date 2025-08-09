import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

import '../widgets/icon_circle_button.dart';
import '../widgets/fire_toggle_button.dart';
import '../widgets/starry_background.dart';
import '../screens/settings_screen.dart';

class CampfireScreen extends StatefulWidget {
  final bool adsEnabled;
  final Future<void> Function() onRefreshEntitlements;
  const CampfireScreen({
    super.key,
    required this.adsEnabled,
    required this.onRefreshEntitlements,
  });

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
  bool _uiFireOn = false; // UI表示用の点火状態（即時切替用）
  bool _muted = false; // 消音状態

  Duration _remaining = Duration.zero;
  DateTime? _endAt;
  bool get _isTimerRunning =>
      _isUnlimited || (_endAt != null && _remaining > Duration.zero);

  BannerAd? _bannerAd;
  bool get _isBannerReady => _bannerAd != null;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tickTimer();
    });
    if (widget.adsEnabled) {
      _loadBanner();
    }
  }

  void _loadBanner() {
    final adUnitId = _getBannerId();
    final banner = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() => _bannerAd = ad as BannerAd?),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          setState(() => _bannerAd = null);
        },
      ),
    );
    banner.load();
  }

  String _getBannerId() {
    if (kReleaseMode) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          return 'ca-app-pub-8980159252766093~3569161950';
        case TargetPlatform.android:
          return 'ca-app-pub-xxxxxxxxxxxxxxxx/aaaaaaaaaa';
        default:
          return 'ca-app-pub-8980159252766093~3569161950';
      }
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          return 'ca-app-pub-3940256099942544/2934735716';
        case TargetPlatform.android:
          return 'ca-app-pub-3940256099942544/6300978111';
        default:
          return 'ca-app-pub-3940256099942544/2934735716';
      }
    }
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
      final target = _muted ? 0.0 : _userVolume;
      for (int i = 0; i <= steps; i++) {
        await Future.delayed(const Duration(milliseconds: 40));
        _currentVolume = (target * i / steps);
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
    setState(() {
      _uiFireOn = true;
    });
    _endAt = DateTime.now().add(duration);
    setState(() {
      _remaining = duration;
    });
    _flameController.value = 0.001;
    setState(() {});
    await _flameController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
    );
    await _playAudioFadeIn();
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    _tickTimer();
  }

  Future<void> _startUnlimited() async {
    _isUnlimited = true;
    setState(() {
      _uiFireOn = true;
    });
    _endAt = null;
    setState(() {
      _remaining = Duration.zero;
    });
    _flameController.value = 0.001;
    setState(() {});
    await _flameController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
    );
    await _playAudioFadeIn();
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  Future<void> _cancelTimerAndExtinguish() async {
    setState(() {
      _uiFireOn = false;
    });
    _endAt = null;
    _isUnlimited = false;
    setState(() {
      _remaining = Duration.zero;
    });
    await _flameController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 1200),
    );
    await _fadeOutAndPauseAudio();
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
    _bannerAd?.dispose();
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
              const StarryBackground(),
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
                bottom: (_isBannerReady ? 64 : 24),
                left: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isTimerRunning && !_isUnlimited)
                      Text(
                        _formatDuration(_remaining),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 22,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconCircleButton(
                          icon: Icons.settings_outlined,
                          onPressed: _openSettings,
                        ),
                        const SizedBox(width: 14),
                        IconCircleButton(
                          icon: _muted ? Icons.volume_off : Icons.volume_up,
                          onPressed: () async {
                            setState(() {
                              _muted = !_muted;
                            });
                            if (_player.state == PlayerState.playing) {
                              final v = _muted ? 0.0 : _userVolume;
                              _currentVolume = v;
                              await _player.setVolume(v);
                            }
                          },
                        ),
                        const SizedBox(width: 14),
                        IconCircleButton(
                          icon: Icons.timer_outlined,
                          onPressed: _openTimerSheet,
                        ),
                        const SizedBox(width: 14),
                        FireToggleButton(
                          isOn: _uiFireOn,
                          onToggleOn: () async {
                            setState(() {
                              _uiFireOn = true;
                            });
                            await _startUnlimited();
                          },
                          onToggleOff: () async {
                            setState(() {
                              _uiFireOn = false;
                            });
                            await _cancelTimerAndExtinguish();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_isBannerReady && widget.adsEnabled)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTimerSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0B0B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              runSpacing: 10,
              spacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _SheetButton(
                  label: '5分',
                  onTap: () {
                    Navigator.of(bctx).pop();
                    _startTimer(const Duration(minutes: 5));
                  },
                ),
                _SheetButton(
                  label: '10分',
                  onTap: () {
                    Navigator.of(bctx).pop();
                    _startTimer(const Duration(minutes: 10));
                  },
                ),
                _SheetButton(
                  label: '15分',
                  onTap: () {
                    Navigator.of(bctx).pop();
                    _startTimer(const Duration(minutes: 15));
                  },
                ),
                _SheetButton(
                  label: '任意',
                  onTap: () async {
                    Navigator.of(bctx).pop();
                    await Future.delayed(const Duration(milliseconds: 50));
                    final d = await _pickCustomDuration(context);
                    if (d != null && d > Duration.zero) {
                      _startTimer(d);
                    }
                  },
                ),
                _SheetButton(
                  label: '無制限',
                  onTap: () {
                    Navigator.of(bctx).pop();
                    _startUnlimited();
                  },
                ),
                _SheetButton(
                  label: '閉じる',
                  onTap: () => Navigator.of(bctx).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => SettingsScreen(
              onRefreshEntitlements: widget.onRefreshEntitlements,
            ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SheetButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label),
    );
  }
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

    final clipRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(0),
    );
    canvas.save();
    canvas.clipRRect(clipRRect);

    double flicker(double seed, double scale) {
      return (math.sin((t * 2 * math.pi) + seed) +
              math.sin((t * 4 * math.pi) + seed * 1.7) * 0.5 +
              math.cos((t * 6 * math.pi) + seed * 2.3) * 0.3) *
          scale;
    }

    void drawFlameLayer({
      required double baseRadius,
      required Color color,
      required double yOffset,
      required double noiseScale,
      required double squeeze,
      required BlendMode blendMode,
    }) {
      final path = Path();
      final segments = 24;
      double? sx, sy;
      double? ex, ey;
      for (int i = 0; i <= segments; i++) {
        final angle = (i / segments) * math.pi;
        final n = flicker(i * 0.37, noiseScale) * factor;
        final radius =
            (baseRadius * factor) +
            n -
            (i - segments / 2).abs() * (squeeze * factor);
        final x = center.dx + math.cos(angle) * radius;
        final y = center.dy - yOffset - math.sin(angle) * (radius * 1.6);
        if (i == 0) {
          path.moveTo(x, y);
          sx = x;
          sy = y;
        } else {
          path.lineTo(x, y);
        }
        if (i == segments) {
          ex = x;
          ey = y;
        }
      }
      final midBottom = center.translate(0, (baseRadius * 0.65) - yOffset);
      if (sx != null && sy != null && ex != null && ey != null) {
        final c1x = ex + (midBottom.dx - ex) * 0.4;
        final c1y = ey + (midBottom.dy - ey) * 0.9;
        path.quadraticBezierTo(c1x, c1y, midBottom.dx, midBottom.dy);
        final c2x = sx + (midBottom.dx - sx) * 0.4;
        final c2y = sy + (midBottom.dy - sy) * 0.9;
        path.quadraticBezierTo(c2x, c2y, sx, sy);
      } else {
        path.close();
      }
      final innerBase = Color.lerp(Colors.white, color, 0.2)!;
      final innerOpacity = (0.9 * factor + 0.35).clamp(0.0, 1.0);
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
            ..blendMode = blendMode;
      canvas.drawPath(path, paint);
    }

    drawFlameLayer(
      baseRadius: 82,
      color: const Color.fromARGB(255, 195, 26, 0),
      yOffset: 0 + flicker(0.2, 6) * factor,
      noiseScale: 10,
      squeeze: 2.6,
      blendMode: BlendMode.screen,
    );
    drawFlameLayer(
      baseRadius: 65,
      color: const Color.fromARGB(255, 127, 53, 0),
      yOffset: 16 + flicker(0.8, 5) * factor,
      noiseScale: 8,
      squeeze: 2.2,
      blendMode: BlendMode.screen,
    );
    drawFlameLayer(
      baseRadius: 50,
      color: const Color.fromARGB(255, 115, 33, 0),
      yOffset: 30 + flicker(1.6, 4) * factor,
      noiseScale: 6,
      squeeze: 1.8,
      blendMode: BlendMode.screen,
    );
    drawFlameLayer(
      baseRadius: 36,
      color: const Color.fromARGB(255, 73, 27, 0),
      yOffset: 42 + flicker(2.3, 3) * factor,
      noiseScale: 5,
      squeeze: 1.2,
      blendMode: BlendMode.screen,
    );

    final glowCenter = center.translate(0, -40);
    final glowPaint =
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFF7A1A).withOpacity(0.6 * factor),
              Colors.transparent,
            ],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: glowCenter, radius: 200))
          ..blendMode = BlendMode.plus;
    canvas.drawCircle(glowCenter, 200, glowPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CampfirePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.factor != factor;
}

Future<Duration?> _pickCustomDuration(BuildContext context) async {
  final minutesController = TextEditingController();
  final secondsController = TextEditingController();
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
