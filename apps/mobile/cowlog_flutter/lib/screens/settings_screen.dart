import 'package:flutter/material.dart';

import '../state/app_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  final _token = TextEditingController();
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.store.baseUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.store.saveConnection(url: _url.text, token: _token.text);
    _token.clear();
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('接続情報を保存しました')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('接続設定')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('サンプルデータを使う'),
          subtitle: const Text('実際の牛や牧場の位置は表示しません。'),
          value: widget.store.demoMode,
          onChanged: widget.store.setDemoMode,
        ),
        const Divider(height: 32),
        Text('クラウド接続', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'HTTPSのAPI URL',
            hintText: 'https://example.com/',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '閲覧用トークン',
            helperText: '空欄のまま保存すると、すでに保存したトークンを維持します。',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save),
          label: Text(_saving ? '保存中' : '接続情報を保存'),
        ),
        const SizedBox(height: 12),
        Text(
          '実データを見るにはサンプルデータをオフにし、HTTPSで公開したCowlog APIを指定します。閲覧用トークンは端末の安全な保存領域に記録します。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
