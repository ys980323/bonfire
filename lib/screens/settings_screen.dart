import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定'), backgroundColor: Colors.black),
      backgroundColor: Colors.black,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            title: Text('Bonfire 設定', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'ここに各種設定項目を追加できます。',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          Divider(color: Colors.white24),
          ListTile(
            title: Text('バージョン', style: TextStyle(color: Colors.white)),
            subtitle: Text('1.0.0', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}
