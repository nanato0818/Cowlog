import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../models.dart';
import '../app_theme.dart';
import '../state/app_store.dart';
import '../widgets/cow_avatar.dart';
import 'dashboard_screen.dart';

class HerdScreen extends StatefulWidget {
  const HerdScreen({super.key, required this.store, this.active = true});
  final AppStore store;

  /// タブが表示中か。表示に戻ったとき一覧を取り直す。
  final bool active;
  @override
  State<HerdScreen> createState() => _HerdScreenState();
}

class _HerdScreenState extends State<HerdScreen> {
  List<Collar>? _collars;
  String? _error;
  bool _loading = false, _saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HerdScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !_loading && !_saving) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final collars = await widget.store.loadCollars();
      if (mounted) setState(() => _collars = collars);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '通信できません。再読み込みしてください');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit(Collar? collar) async {
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _CollarEditor(collar: collar),
    );
    if (!mounted || result == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (collar == null) {
        await widget.store.addCollar(
          result.deviceId!,
          result.number,
          result.style,
        );
      } else {
        await widget.store.saveNumber(
          collar,
          result.number,
          style: result.style,
        );
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      final done = collar == null ? '登録しました' : '保存しました';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(28, 0, 28, 96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          duration: const Duration(seconds: 2),
          content: Text(widget.store.demoMode ? '$done（デモ）' : done),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // 応答だけ失われ、サーバーでは保存済みの可能性がある。
      if (mounted) {
        setState(() => _error = '通信できません。一覧を再読み込みして確認してください');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refreshed = CowlogUi.isRefreshed(context);
    final busy = _loading || _saving;
    final canEdit = widget.store.canManageNumbers && !busy;
    return Scaffold(
      appBar: AppBar(
        centerTitle: !refreshed,
        title: Text(
          refreshed ? '設定' : '首輪・番号',
          style: refreshed
              ? const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)
              : null,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: busy
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: busy ? null : _load,
            icon: const Icon(CupertinoIcons.arrow_clockwise),
          ),
          if (refreshed)
            IconButton.filled(
              tooltip: '首輪を追加',
              onPressed: canEdit ? () => _submit(null) : null,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onInk,
              ),
              icon: const Icon(CupertinoIcons.add, size: 23),
            )
          else
            IconButton(
              tooltip: '首輪を追加',
              onPressed: canEdit ? () => _submit(null) : null,
              icon: const Icon(CupertinoIcons.add, size: 28),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, refreshed ? 14 : 8, 20, 140),
        children: [
          if (refreshed) ...[
            const Text(
              '首輪・番号',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              if (_collars != null)
                Text(
                  '${_collars!.length}台の首輪',
                  style: TextStyle(
                    fontSize: refreshed ? 15 : 13,
                    fontWeight: refreshed ? FontWeight.w600 : null,
                    color: AppColors.muted,
                    fontFeatures: tabularFigures,
                  ),
                ),
              const Spacer(),
              if (!widget.store.canManageNumbers)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    '閲覧のみ',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ),
              if (widget.store.demoMode) const DemoBadge(),
            ],
          ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.onInk,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SizedBox(height: refreshed ? 12 : 6),
          for (final collar in _collars ?? <Collar>[])
            Pressable(
              onTap: canEdit ? () => _submit(collar) : null,
              scale: .97,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                  child: Row(
                    children: [
                      CowAvatar(style: collar.style, size: 50),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              collar.number ?? '番号未設定',
                              style: TextStyle(
                                fontSize: collar.number == null
                                    ? 17
                                    : (refreshed ? 25 : 22),
                                fontWeight: FontWeight.w700,
                                fontFeatures: tabularFigures,
                                color: collar.number == null
                                    ? AppColors.muted
                                    : AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '首輪ID：${collar.deviceId}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                            ),
                            Text(
                              collar.lastSeenAt == null
                                  ? '未受信'
                                  : dateTimeLabel(collar.lastSeenAt!),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '番号を設定',
                        icon: const Icon(CupertinoIcons.pencil, size: 22),
                        onPressed: canEdit ? () => _submit(collar) : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditResult {
  const _EditResult(this.number, this.style, [this.deviceId]);
  final String? deviceId;
  final String number;
  final CowStyle style;
}

class _CollarEditor extends StatefulWidget {
  const _CollarEditor({this.collar});
  final Collar? collar;
  @override
  State<_CollarEditor> createState() => _CollarEditorState();
}

class _CollarEditorState extends State<_CollarEditor> {
  String _device = '';
  late String _number;
  late CowStyle _style;
  String? _error;
  @override
  void initState() {
    super.initState();
    _number = widget.collar?.number ?? '';
    _style = widget.collar?.style ?? CowStyle.unknown;
  }

  void _save() {
    if (widget.collar == null &&
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$',
        ).hasMatch(_device.trim())) {
      setState(() => _error = '首輪IDを確認してください');
      return;
    }
    final value = _number.trim();
    if (!RegExp(r'^[0-9]{1,12}$').hasMatch(value)) {
      setState(() => _error = '半角数字1〜12桁');
      return;
    }
    Navigator.pop(context, _EditResult(value, _style, _device.trim()));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      10,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.faint,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.collar == null ? '首輪を追加' : widget.collar!.deviceId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: CowlogUi.isRefreshed(context) ? 21 : 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル', style: TextStyle(fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.collar == null) ...[
            TextFormField(
              key: const ValueKey('new-collar-id'),
              onChanged: (v) => _device = v,
              maxLength: 64,
              style: const TextStyle(fontSize: 17),
              decoration: const InputDecoration(
                labelText: '首輪ID',
                counterText: '',
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            initialValue: _number,
            autofocus: widget.collar != null,
            onChanged: (v) => _number = v,
            keyboardType: TextInputType.number,
            maxLength: 12,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
            decoration: InputDecoration(
              labelText: '番号',
              hintText: '0007',
              counterText: '',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in CowStyle.values)
                Pill(
                  key: ValueKey('cow-style-${style.name}'),
                  leading: CowAvatar(style: style, size: 28),
                  label: style.label,
                  selected: _style == style,
                  onTap: () => setState(() => _style = style),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    ),
  );
}
