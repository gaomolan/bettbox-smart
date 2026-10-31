import 'dart:convert';

import 'package:bett_box/clash/clash.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// Bettbox-SmartCore: in-app viewer for the Smart groups' learning data.
///
/// Reads the same document as the Smart learning-data export (the
/// persisted smart_stats bucket of the kernel cache database, served
/// by the core's exportSmartData action) and renders it grouped by
/// proxy group: learned node ranking, per-node success statistics,
/// node states, per-target prefetch results and host failure records.
/// The data is a snapshot of the last flushed state; use the refresh
/// action to re-read it.
class SmartLearningView extends StatefulWidget {
  const SmartLearningView({super.key});

  @override
  State<SmartLearningView> createState() => _SmartLearningViewState();
}

class _SmartLearningViewState extends State<SmartLearningView> {
  bool _loading = true;
  String? _error;
  _SmartLearningDoc? _doc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await clashCore.exportSmartData();
      if (raw.isEmpty) {
        throw '核心未返回数据';
      }
      final doc = _SmartLearningDoc.parse(
        json.decode(raw) as Map<String, dynamic>,
      );
      if (mounted) {
        setState(() {
          _doc = doc;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Smart 学习情况',
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('读取失败：$_error', style: context.textTheme.bodyMedium),
            const SizedBox(height: 12),
            CommonChip(
              avatar: const Icon(Icons.refresh),
              label: '重试',
              onPressed: _load,
            ),
          ],
        ),
      );
    }
    final doc = _doc!;
    if (!doc.available || doc.totalKeys == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '暂无学习数据。Smart 组运行一段时间、产生连接记录后，这里会显示它学到的节点排名与表现。',
            style: context.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SummaryTile(doc: doc),
          for (final group in doc.groups) _GroupSection(group: group),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final _SmartLearningDoc doc;

  const _SummaryTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final counts = doc.counts;
    String part(String label, String key) {
      final value = counts[key] ?? 0;
      return value > 0 ? '$label $value' : '';
    }

    final detail = [
      part('节点状态', 'node'),
      part('目标统计', 'stats'),
      part('排名', 'ranking'),
      part('预取', 'prefetch'),
      part('失败记录', 'failures'),
    ].where((e) => e.isNotEmpty).join(' · ');
    return ListTile(
      leading: const Icon(Icons.psychology_outlined),
      title: Text('共 ${doc.totalKeys} 条学习记录'),
      subtitle: Text(
        [
          if (doc.exportedAt.isNotEmpty) '数据截至 ${doc.exportedAt}',
          if (detail.isNotEmpty) detail,
        ].join('\n'),
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  final _SmartGroupData group;

  const _GroupSection({required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            group.group,
            style: context.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (group.ranking.isNotEmpty) ...[
          const _SectionLabel('学到的排名'),
          for (var i = 0; i < group.ranking.length; i++)
            ListTile(
              dense: true,
              leading: Text('${i + 1}'),
              title: Text(
                group.ranking[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '${group.ranking[i].rankLabel} · 权重 ${group.ranking[i].weight.toStringAsFixed(2)}',
                style: context.textTheme.bodyMedium,
              ),
            ),
        ],
        if (group.nodeRows.isNotEmpty) ...[
          const _SectionLabel('节点表现'),
          for (final row in group.nodeRows)
            ListTile(
              dense: true,
              title: Text(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(row.describe()),
            ),
        ],
        if (group.prefetches.isNotEmpty) ...[
          const _SectionLabel('目标预取（首选节点）'),
          for (final prefetch in group.prefetches.take(20))
            ListTile(
              dense: true,
              title: Text(
                prefetch.target,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(prefetch.describe()),
            ),
          if (group.prefetches.length > 20)
            _MoreLine(count: group.prefetches.length - 20),
        ],
        if (group.failures.isNotEmpty) ...[
          const _SectionLabel('目标失败记录'),
          for (final failure in group.failures.take(20))
            ListTile(
              dense: true,
              title: Text(
                failure.target,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(failure.describe()),
            ),
          if (group.failures.length > 20)
            _MoreLine(count: group.failures.length - 20),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Text(
        text,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.primary,
        ),
      ),
    );
  }
}

class _MoreLine extends StatelessWidget {
  final int count;

  const _MoreLine({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Text('还有 $count 个目标…', style: context.textTheme.bodySmall),
    );
  }
}

// ---------------------------------------------------------------------------
// Parsed model of the export document (see core/smart_export.go).
// ---------------------------------------------------------------------------

class _SmartLearningDoc {
  final bool available;
  final String exportedAt;
  final int totalKeys;
  final Map<String, int> counts;
  final List<_SmartGroupData> groups;

  const _SmartLearningDoc({
    required this.available,
    required this.exportedAt,
    required this.totalKeys,
    required this.counts,
    required this.groups,
  });

  factory _SmartLearningDoc.parse(Map<String, dynamic> json) {
    final counts = <String, int>{};
    final rawCounts = json['counts'];
    if (rawCounts is Map) {
      rawCounts.forEach((key, value) {
        if (value is num) counts[key.toString()] = value.toInt();
      });
    }

    final byGroup = <String, _SmartGroupData>{};
    final rawEntries = json['entries'];
    if (rawEntries is List) {
      for (final raw in rawEntries) {
        if (raw is! Map) continue;
        final entry = _Entry.fromJson(raw.cast<String, dynamic>());
        final data = byGroup.putIfAbsent(
          '${entry.config}\n${entry.group}',
          () => _SmartGroupData(config: entry.config, group: entry.group),
        );
        data.add(entry);
      }
    }
    final groups = byGroup.values.toList()
      ..sort((a, b) => a.group.compareTo(b.group));
    for (final group in groups) {
      group.finish();
    }

    var exportedAt = '';
    final rawTime = json['exportedAt'];
    if (rawTime is String) {
      final parsed = DateTime.tryParse(rawTime);
      exportedAt = parsed == null ? rawTime : _formatTime(parsed);
    }
    return _SmartLearningDoc(
      available: json['available'] == true,
      exportedAt: exportedAt,
      totalKeys: (json['totalKeys'] as num?)?.toInt() ?? 0,
      counts: counts,
      groups: groups,
    );
  }
}

class _Entry {
  final String type;
  final String config;
  final String group;
  final String target;
  final String node;
  final dynamic value;

  const _Entry({
    required this.type,
    required this.config,
    required this.group,
    required this.target,
    required this.node,
    required this.value,
  });

  factory _Entry.fromJson(Map<String, dynamic> json) {
    return _Entry(
      type: json['type'] as String? ?? '',
      config: json['config'] as String? ?? '',
      group: json['group'] as String? ?? '',
      target: json['target'] as String? ?? '',
      node: json['node'] as String? ?? '',
      value: json['value'],
    );
  }
}

class _SmartGroupData {
  final String config;
  final String group;
  final List<_RankRow> ranking = [];
  final Map<String, _NodeRow> _nodes = {};
  final List<_PrefetchRow> prefetches = [];
  final List<_FailureRow> failures = [];

  _SmartGroupData({required this.config, required this.group});

  List<_NodeRow> get nodeRows => _nodes.values.toList();

  _NodeRow _node(String name) => _nodes.putIfAbsent(name, () => _NodeRow(name));

  void add(_Entry entry) {
    final value = entry.value;
    switch (entry.type) {
      case 'ranking':
        if (value is Map && value['result'] is List) {
          for (final item in value['result'] as List) {
            if (item is Map) {
              ranking.add(
                _RankRow(
                  name: item['Name'] as String? ?? '',
                  rank: item['Rank'] as String? ?? '',
                  weight: (item['Weight'] as num?)?.toDouble() ?? 0,
                ),
              );
            }
          }
        }
      case 'node':
        if (value is Map) {
          final row = _node(entry.node);
          row.blockedUntil = (value['blocked_until'] as num?)?.toInt() ?? 0;
          row.lastChecked = (value['last_checked'] as num?)?.toInt() ?? 0;
          row.exitRegion = value['exit_region'] as String? ?? '';
          row.exitASN = value['exit_asn'] as String? ?? '';
        }
      case 'stats':
        if (value is Map) {
          final row = _node(entry.node);
          row.success += (value['success'] as num?)?.toInt() ?? 0;
          row.failure += (value['failure'] as num?)?.toInt() ?? 0;
          row.targets++;
          final lastUsed = (value['last_used'] as num?)?.toInt() ?? 0;
          if (lastUsed > row.lastUsed) row.lastUsed = lastUsed;
        }
      case 'prefetch':
        if (value is Map) {
          prefetches.add(_PrefetchRow.fromValue(entry.target, value));
        }
      case 'failures':
        if (value is Map) {
          failures.add(
            _FailureRow(
              target: entry.target,
              blocked: value['blocked'] == true,
              lastFailure: (value['last_failure'] as num?)?.toInt() ?? 0,
            ),
          );
        }
    }
  }

  void finish() {
    _nodes.removeWhere((_, row) => row.name.isEmpty);
    final rows = _nodes.values.toList()
      ..sort((a, b) {
        final byAttempts = (b.success + b.failure).compareTo(
          a.success + a.failure,
        );
        return byAttempts != 0 ? byAttempts : a.name.compareTo(b.name);
      });
    _nodes
      ..clear()
      ..addEntries(rows.map((row) => MapEntry(row.name, row)));
    prefetches.sort((a, b) => a.target.compareTo(b.target));
    failures.sort((a, b) => a.target.compareTo(b.target));
  }
}

class _RankRow {
  final String name;
  final String rank;
  final double weight;

  const _RankRow({
    required this.name,
    required this.rank,
    required this.weight,
  });

  String get rankLabel {
    switch (rank) {
      case 'MostUsed':
        return '最常用';
      case 'OccasionalUsed':
        return '偶尔用';
      case 'RarelyUsed':
        return '很少用';
      default:
        return rank;
    }
  }
}

class _NodeRow {
  final String name;
  int success = 0;
  int failure = 0;
  int targets = 0;
  int lastUsed = 0;
  int lastChecked = 0;
  int blockedUntil = 0;
  String exitRegion = '';
  String exitASN = '';

  _NodeRow(this.name);

  String describe() {
    final parts = <String>[];
    final attempts = success + failure;
    if (attempts > 0) {
      final rate = (success * 100 / attempts).toStringAsFixed(0);
      parts.add('成功率 $rate%（成功 $success · 失败 $failure · $targets 个目标）');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (blockedUntil > now) {
      parts.add('拉黑至 ${_formatUnix(blockedUntil)}');
    }
    if (exitRegion.isNotEmpty || exitASN.isNotEmpty) {
      parts.add(
        '出口 ${[exitRegion, exitASN].where((e) => e.isNotEmpty).join(' · ')}',
      );
    }
    final last = lastUsed > lastChecked ? lastUsed : lastChecked;
    if (last > 0) {
      parts.add('最近活动 ${_formatUnix(last)}');
    }
    return parts.isEmpty ? '暂无活动记录' : parts.join(' · ');
  }
}

class _PrefetchRow {
  final String target;
  final String tcpFirst;
  final String udpFirst;

  const _PrefetchRow({
    required this.target,
    required this.tcpFirst,
    required this.udpFirst,
  });

  factory _PrefetchRow.fromValue(String target, Map value) {
    String firstOf(dynamic section) {
      if (section is Map && section['nodes'] is List) {
        final nodes = section['nodes'] as List;
        if (nodes.isNotEmpty) return nodes.first.toString();
      }
      return '';
    }

    return _PrefetchRow(
      target: target,
      tcpFirst: firstOf(value['tcp']),
      udpFirst: firstOf(value['udp']),
    );
  }

  String describe() {
    final parts = <String>[];
    if (tcpFirst.isNotEmpty) parts.add('TCP 首选 $tcpFirst');
    if (udpFirst.isNotEmpty) parts.add('UDP 首选 $udpFirst');
    return parts.isEmpty ? '暂无首选' : parts.join(' · ');
  }
}

class _FailureRow {
  final String target;
  final bool blocked;
  final int lastFailure;

  const _FailureRow({
    required this.target,
    required this.blocked,
    required this.lastFailure,
  });

  String describe() {
    final parts = <String>[];
    if (blocked) parts.add('该目标已被标记不可用');
    if (lastFailure > 0) parts.add('最近失败 ${_formatUnix(lastFailure)}');
    return parts.isEmpty ? '有失败记录' : parts.join(' · ');
  }
}

String _formatUnix(int seconds) {
  var ms = seconds * 1000;
  if (seconds > 100000000000) {
    // Already milliseconds.
    ms = seconds;
  }
  final time = DateTime.fromMillisecondsSinceEpoch(ms);
  return _formatTime(time);
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
