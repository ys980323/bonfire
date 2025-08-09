import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  MobileAds.instance.initialize();
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
  bool _uiFireOn = false; // UI表示用の点火状態（即時切替用）

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
    // タイマー監視ティッカー（1秒）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tickTimer();
    });

    _loadBanner();
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
    setState(() {
      _uiFireOn = true;
    });
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
    setState(() {
      _uiFireOn = true;
    });
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

  Future<void> _cancelTimerAndExtinguish() async {
    setState(() {
      _uiFireOn = false; // まずUIを消灯状態に
    });
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
    // kReleaseModeで本番/テストを切り替え
    if (kReleaseMode) {
      // TODO: 本番のバナー広告ユニットIDに置き換えてください
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          return 'ca-app-pub-xxxxxxxxxxxxxxxx/iiiiiiiiii';
        case TargetPlatform.android:
          return 'ca-app-pub-xxxxxxxxxxxxxxxx/aaaaaaaaaa';
        default:
          return 'ca-app-pub-xxxxxxxxxxxxxxxx/iiiiiiiiii';
      }
    } else {
      // AdMob公式のテストID（iOS/Android）
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
                bottom: (_isBannerReady ? 64 : 24),
                left: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // カウントダウンは稼働中のみ表示
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
                    // 時計ボタン + 火のトグル
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _IconCircleButton(
                          icon: Icons.timer_outlined,
                          onPressed: _openTimerSheet,
                        ),
                        const SizedBox(width: 14),
                        _FireToggleButton(
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
              if (_isBannerReady)
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
                    // シートを閉じてから任意入力を表示
                    await Future.delayed(const Duration(milliseconds: 50));
                    final d = await _pickCustomDuration(context);
                    if (d != null && d > Duration.zero) {
                      _startTimer(d);
                    }
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
    // 念のためUIを再描画（ボトムシート閉鎖後にコントロールが確実に再表示されるように）
    setState(() {});
  }
}

class _StarrySkyBackground extends StatelessWidget {
  const _StarrySkyBackground();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(child: ColoredBox(color: Colors.black));
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

    // 描画クリップ（境界ブリード抑制）
    final clipRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(0),
    );
    canvas.save();
    canvas.clipRRect(clipRRect);

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
      double? sx, sy; // 始点（左端）
      double? ex, ey; // 終点（右端）
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
      // 下辺を2段のベジェでスムーズに丸める
      final midBottom = center.translate(0, (baseRadius * 0.65) - yOffset);
      if (sx != null && sy != null && ex != null && ey != null) {
        // 右端→中央（コントロールは右端と中央の間を深めに）
        final c1x = ex + (midBottom.dx - ex) * 0.4;
        final c1y = ey + (midBottom.dy - ey) * 0.9;
        path.quadraticBezierTo(c1x, c1y, midBottom.dx, midBottom.dy);
        // 中央→左端（コントロールは左端へ向けて対称配置）
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
            ..blendMode = BlendMode.plus;
      canvas.drawPath(path, paint);
    }

    drawFlameLayer(
      baseRadius: 82,
      color: const Color(0xFFFF3B1D),
      yOffset: 0 + flicker(0.2, 6) * factor,
      noiseScale: 10,
      squeeze: 2.6,
    );
    drawFlameLayer(
      baseRadius: 65,
      color: const Color(0xFFFF7A1A),
      yOffset: 16 + flicker(0.8, 5) * factor,
      noiseScale: 8,
      squeeze: 2.2,
    );
    drawFlameLayer(
      baseRadius: 50,
      color: const Color(0xFFFFC23B),
      yOffset: 30 + flicker(1.6, 4) * factor,
      noiseScale: 6,
      squeeze: 1.8,
    );
    drawFlameLayer(
      baseRadius: 36,
      color: const Color.fromARGB(255, 255, 249, 236),
      yOffset: 42 + flicker(2.3, 3) * factor,
      noiseScale: 5,
      squeeze: 1.2,
    );

    // 中心のホットコア（白く強い発光）
    final coreCenter = center.translate(0, -38);
    final coreRadius = 28 * (0.8 + 0.2 * factor);
    final corePaint =
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withOpacity(0.95 * factor),
              Colors.white.withOpacity(0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(
            Rect.fromCircle(center: coreCenter, radius: coreRadius),
          )
          ..blendMode = BlendMode.plus;
    canvas.drawCircle(coreCenter, coreRadius, corePaint);

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

class _IconCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _IconCircleButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: const Color(0xFF1F2937),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

class _FireToggleButton extends StatelessWidget {
  final bool isOn;
  final VoidCallback onToggleOn;
  final VoidCallback onToggleOff;
  const _FireToggleButton({
    required this.isOn,
    required this.onToggleOn,
    required this.onToggleOff,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isOn ? onToggleOff : onToggleOn,
      icon: Icon(isOn ? Icons.stop : Icons.local_fire_department, size: 18),
      label: Text(isOn ? '火を消す' : '火をつける'),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isOn
                ? const Color(0xFF5A2A2A)
                : const Color.fromARGB(255, 58, 35, 26),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
