import 'package:flutter/material.dart';

class FireToggleButton extends StatelessWidget {
  final bool isOn;
  final VoidCallback onToggleOn;
  final VoidCallback onToggleOff;
  const FireToggleButton({
    super.key,
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    );
  }
}
