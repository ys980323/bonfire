import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.onRefreshEntitlements});

  final Future<void> Function() onRefreshEntitlements;

  static const String _privacyUrl = 'https://example.com/privacy';
  static const String _termsUrl = 'https://example.com/terms';
  static const String _supportEmail = 'support@example.com';
  static const String _appShareText = '焚き火アプリ「Bonfire」おすすめ！';
  static const String _storeUrl = 'https://example.com/app';

  // RevenueCatの設定に合わせて変更する（ダッシュボード側で用意したID）
  static const String _offeringId = 'premium'; // 例: default / current
  static const PackageType _targetPackageType = PackageType.lifetime; // 買い切り

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定'), backgroundColor: Colors.black),
      backgroundColor: Colors.black,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            title: Text('Bonfire 設定', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'アプリの各種設定や情報へアクセスできます。',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          const Divider(color: Colors.white24),
          _item(
            context,
            icon: Icons.privacy_tip_outlined,
            title: 'プライバシーポリシー',
            onTap: () => _launchUrl(_privacyUrl),
          ),
          _item(
            context,
            icon: Icons.description_outlined,
            title: '利用規約',
            onTap: () => _launchUrl(_termsUrl),
          ),
          _item(
            context,
            icon: Icons.share_outlined,
            title: 'このアプリを紹介する',
            onTap: () => Share.share('$_appShareText\n$_storeUrl'),
          ),
          _item(
            context,
            icon: Icons.star_rate_outlined,
            title: 'このアプリを評価する',
            onTap: () => _launchUrl(_storeUrl),
          ),
          _item(
            context,
            icon: Icons.feedback_outlined,
            title: 'ご意見ご要望',
            onTap: () => _sendFeedback(),
          ),
          const Divider(color: Colors.white24),
          _item(
            context,
            icon: Icons.block,
            title: '広告非表示を購入',
            onTap: () async {
              await _purchaseRemoveAds(context);
              await onRefreshEntitlements();
            },
          ),
          _item(
            context,
            icon: Icons.restore,
            title: '購入を復元',
            onTap: () async {
              await _restorePurchases(context);
              await onRefreshEntitlements();
            },
          ),
          const Divider(color: Colors.white24),
          const ListTile(
            title: Text('バージョン', style: TextStyle(color: Colors.white)),
            subtitle: Text('1.0.0', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }

  static Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // ignore
    }
  }

  Future<void> _sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'Bonfire ご意見・ご要望',
        'body': '以下にご記入ください\n\n・ご意見/ご要望:\n',
      },
    );
    await launchUrl(uri);
  }

  Future<void> _purchaseRemoveAds(BuildContext context) async {
    try {
      final offerings = await Purchases.getOfferings();
      final offering = offerings.all[_offeringId] ?? offerings.current;
      if (offering == null || offering.availablePackages.isEmpty) {
        _showError(
          context,
          '現在購入可能な商品がありません。\nRevenueCatのOfferingとProductの設定を確認してください。',
        );
        return;
      }
      final candidates = offering.availablePackages;
      Package? target = candidates.firstWhere(
        (p) => p.packageType == _targetPackageType,
        orElse: () => candidates.first,
      );
      await Purchases.purchasePackage(target);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('購入が完了しました。')));
    } on PlatformException catch (e) {
      _showError(context, '購入に失敗しました: ${e.message ?? e.toString()}');
    } catch (e) {
      _showError(context, '購入に失敗しました: $e');
    }
  }

  Future<void> _restorePurchases(BuildContext context) async {
    try {
      await Purchases.restorePurchases();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('購入情報を復元しました。')));
    } on PlatformException catch (e) {
      _showError(context, '復元に失敗しました: ${e.message ?? e.toString()}');
    } catch (e) {
      _showError(context, '復元に失敗しました: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
