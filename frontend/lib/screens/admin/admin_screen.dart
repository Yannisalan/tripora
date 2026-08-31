import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/admin_service.dart';
import '../../widgets/shimmer_loader.dart';

/// Token-gated admin dashboard: aggregate stats, users, trips, and a live
/// activity log. Redirects to the login screen when no valid token is present.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final AdminService _service = AdminService();

  bool _checkingToken = true;

  // Overview
  Map<String, dynamic>? _stats;
  String? _statsError;

  // Users / Trips
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _trips = const [];

  // Activity log
  List<Map<String, dynamic>> _logs = const [];
  String _logFilter = 'all'; // all | page_view | api_request

  bool _loadingUsers = false;
  bool _loadingTrips = false;
  bool _loadingLogs = false;

  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _guard();
  }

  Future<void> _guard() async {
    final token = await _service.getToken();
    if (token == null || token.trim().isEmpty) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.adminLogin);
      return;
    }

    final valid = await _service.checkToken(token: token);
    if (!mounted) return;

    if (!valid) {
      await _service.clearToken();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.adminLogin);
      return;
    }

    setState(() => _checkingToken = false);
    await _loadOverview();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _stats = null;
      _statsError = null;
    });
    try {
      final data = await _service.fetchStats();
      if (!mounted) return;
      setState(() => _stats = (data['stats'] as Map? ?? {}) as Map<String, dynamic>);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _statsError = error.toString().replaceFirst('Exception: ', '').trim(),
      );
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final data = await _service.fetchUsers(limit: 200);
      if (!mounted) return;
      final list = (data['users'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _users = list;
        _loadingUsers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingUsers = false);
    }
  }

  Future<void> _loadTrips() async {
    setState(() => _loadingTrips = true);
    try {
      final data = await _service.fetchTrips(limit: 200);
      if (!mounted) return;
      final list = (data['trips'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _trips = list;
        _loadingTrips = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingTrips = false);
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _loadingLogs = true);
    try {
      final type = _logFilter == 'all' ? null : _logFilter;
      final data = await _service.fetchLogs(type: type, limit: 300);
      if (!mounted) return;
      final list = (data['logs'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _logs = list;
        _loadingLogs = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingLogs = false);
    }
  }

  Future<void> _onTabChanged(int index) async {
    setState(() => _tabIndex = index);
    switch (index) {
      case 1:
        if (_users.isEmpty) _loadUsers();
        break;
      case 2:
        if (_trips.isEmpty) _loadTrips();
        break;
      case 3:
        if (_logs.isEmpty) _loadLogs();
        break;
    }
  }

  Future<void> _refresh() async {
    await _loadOverview();
    if (_tabIndex == 3) await _loadLogs();
    if (_tabIndex == 1) await _loadUsers();
    if (_tabIndex == 2) await _loadTrips();
  }

  Future<void> _logout() async {
    await _service.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.adminLogin);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingToken) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tripora Admin')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tripora Admin'),
          actions: [
            IconButton(
              onPressed: _refresh,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              onPressed: _logout,
              tooltip: 'Log out',
              icon: const Icon(Icons.logout_outlined),
            ),
          ],
          bottom: TabBar(
            onTap: _onTabChanged,
            tabs: [
              const Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
              const Tab(icon: Icon(Icons.people_outline), text: 'Users'),
              const Tab(icon: Icon(Icons.travel_explore), text: 'Trips'),
              const Tab(icon: Icon(Icons.bolt_outlined), text: 'Activity'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOverview(),
            _buildUsers(),
            _buildTrips(),
            _buildActivity(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // OVERVIEW
  // ============================================================

  Widget _buildOverview() {
    if (_statsError != null) {
      return _errorState(_statsError!);
    }
    if (_stats == null) {
      return const _ListShimmer(rows: 6);
    }

    final s = _stats!;
    final users = (s['users'] as Map? ?? {}) as Map<String, dynamic>;
    final trips = (s['trips'] as Map? ?? {}) as Map<String, dynamic>;
    final subs = (s['subscriptions'] as Map? ?? {}) as Map<String, dynamic>;
    final activity = (s['activity'] as Map? ?? {}) as Map<String, dynamic>;
    final topDestinations = (s['topDestinations'] as List? ?? [])
        .whereType<Map>()
        .toList();

    final cards = <Widget>[
      _statCard(context, Icons.people_outline, 'Users',
          users['total']?.toString() ?? '0'),
      _statCard(context, Icons.verified_user_outlined, 'Verified',
          users['verified']?.toString() ?? '0'),
      _statCard(context, Icons.person_add_alt, 'New (7d)',
          users['recent7d']?.toString() ?? '0'),
      _statCard(context, Icons.travel_explore, 'Trips',
          trips['total']?.toString() ?? '0'),
      _statCard(context, Icons.workspace_premium, 'Subscriptions',
          subs['total']?.toString() ?? '0'),
      _statCard(context, Icons.route_outlined, 'API requests',
          activity['apiRequests']?.toString() ?? '0'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount:
              MediaQuery.sizeOf(context).width >= 640 ? 3 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          children: cards,
        ),
        const SizedBox(height: 20),
        _sectionTitle(context, 'Top destinations'),
        const SizedBox(height: 8),
        if (topDestinations.isEmpty)
          Text(
            'No trips yet.',
            style: TextStyle(color: context.triporaColors.textMuted),
          )
        else
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: context.triporaColors.border),
            ),
            child: Column(
              children: [
                for (final d in topDestinations)
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text((d['destination'] ?? '').toString()),
                    trailing: Text(
                      '${d['count']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ============================================================
  // USERS
  // ============================================================

  Widget _buildUsers() {
    if (_loadingUsers) return const _ListShimmer(rows: 8);
    if (_users.isEmpty) {
      return Center(
        child: Text(
          'No registered users yet.',
          style: TextStyle(color: context.triporaColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final u = _users[index];
        final verified = u['emailVerified'] == true;
        return Card(
          elevation: 0,
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(
                verified ? Icons.verified_user : Icons.person_outline,
              ),
            ),
            title: Text((u['name'] ?? '').toString()),
            subtitle: Text(
              (u['email'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _dateShort(u['createdAt']),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.triporaColors.textMuted,
                  ),
                ),
                Text(
                  verified ? 'verified' : 'unverified',
                  style: TextStyle(
                    fontSize: 12,
                    color: verified
                        ? context.triporaColors.appStatus.success
                        : context.triporaColors.appStatus.warning,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // TRIPS
  // ============================================================

  Widget _buildTrips() {
    if (_loadingTrips) return const _ListShimmer(rows: 8);
    if (_trips.isEmpty) {
      return Center(
        child: Text(
          'No trips generated yet.',
          style: TextStyle(color: context.triporaColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _trips.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final t = _trips[index];
        return Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text((t['destination'] ?? '').toString()),
            subtitle: Text(
              'user #${t['userId']}  •  ${t['travelers']} travelers  •  '
              '${t['createdAt']}'.replaceAll('T', ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(_dateShort(t['createdAt'])),
          ),
        );
      },
    );
  }

  // ============================================================
  // ACTIVITY LOG
  // ============================================================

  Widget _buildActivity() {
    final colors = context.triporaColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'page_view', label: Text('Page views')),
                    ButtonSegment(value: 'api_request', label: Text('API')),
                  ],
                  selected: {_logFilter},
                  onSelectionChanged: (selection) {
                    setState(() => _logFilter = selection.first);
                    _loadLogs();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingLogs
              ? const _ListShimmer(rows: 8)
              : _logs.isEmpty
                  ? Center(
                      child: Text(
                        'No activity recorded yet.',
                        style: TextStyle(color: colors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _logs.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final l = _logs[index];
                        return _logTile(context, l);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _logTile(BuildContext context, Map<String, dynamic> l) {
    final colors = context.triporaColors;
    final type = (l['eventType'] ?? '').toString();
    final path = (l['path'] ?? '').toString();
    final method = (l['method'] ?? '').toString();
    final status = l['statusCode'];
    final isPageView = type == 'page_view';

    IconData icon = Icons.bolt_outlined;
    Color? iconColor;
    if (isPageView) {
      icon = Icons.touch_app_outlined;
      iconColor = colors.appStatus.info;
    } else if (status != null && status >= 500) {
      iconColor = colors.appStatus.error;
    } else if (status != null && status >= 400) {
      iconColor = colors.appStatus.warning;
    } else {
      iconColor = colors.appStatus.success;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPageView ? path : '$method $path',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${isPageView ? 'page_view' : type}  •  user#${l['userId'] ?? '-'}'
                  '${status != null ? '  •  HTTP $status' : ''}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
          Text(
            _dateShort(l['createdAt']),
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SHARED HELPERS
  // ============================================================

  Widget _statCard(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final colors = context.triporaColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: colors.textMuted, size: 20),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: context.triporaColors.appStatus.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.triporaColors.textMuted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  String _dateShort(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final local = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';
    if (diff == 0) return time;
    if (diff == 1) return 'yest $time';
    return '${local.month}/${local.day} $time';
  }
}

// ================================================================
// SHIMMER LIST
// ================================================================

class _ListShimmer extends StatelessWidget {
  final int rows;
  const _ListShimmer({this.rows = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => const ShimmerLoader(height: 72),
    );
  }
}
