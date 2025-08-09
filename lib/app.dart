import 'package:flutter/material.dart';
import 'screens/campfire_screen.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class AdsState extends ChangeNotifier {
  bool _adsEnabled = true;
  bool get adsEnabled => _adsEnabled;
  void setAdsEnabled(bool enabled) {
    if (_adsEnabled != enabled) {
      _adsEnabled = enabled;
      notifyListeners();
    }
  }
}

final AdsState adsState = AdsState();

class BonfireApp extends StatefulWidget {
  const BonfireApp({super.key});

  @override
  State<BonfireApp> createState() => _BonfireAppState();
}

class _BonfireAppState extends State<BonfireApp> {
  @override
  void initState() {
    super.initState();
    _initRevenueCat();
  }

  Future<void> _initRevenueCat() async {
    // TODO: ここにあなたのRevenueCat公開APIキーを設定
    // iOS例: 'appl_XXXXXXXXXXXXXXXXXXXXXXXX'
    const apiKey = 'appl_jJJemQZZkdjXqlETqkoohDijJGo';
    await Purchases.setLogLevel(LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(apiKey));
    await _refreshEntitlements();
  }

  Future<void> _refreshEntitlements() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      // Entitlement ID はRCダッシュボードで設定したIDに合わせて変更
      final active = customerInfo.entitlements.active.containsKey(
        'com.premium',
      );
      adsState.setAdsEnabled(!active);
    } catch (_) {
      // 失敗時は広告有効のまま
      adsState.setAdsEnabled(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: adsState,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Bonfire',
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: Colors.black,
          ),
          home: CampfireScreen(
            adsEnabled: adsState.adsEnabled,
            onRefreshEntitlements: _refreshEntitlements,
          ),
        );
      },
    );
  }
}
