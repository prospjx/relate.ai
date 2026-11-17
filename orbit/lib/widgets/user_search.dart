import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../models/models.dart';
import '../state/session.dart';
import '../theme/orbit_theme.dart';
import '../util/formatting.dart';
import 'avatar.dart';

/// Search field plus results for finding Orbit users by email or name.
class UserSearch extends StatefulWidget {
  const UserSearch({
    super.key,
    required this.onSelect,
    this.selectedIds = const {},
    this.excludeIds = const {},
    this.header,
    this.autofocus = true,
  });

  final bool autofocus;
  final void Function(UserProfile profile) onSelect;
  final Set<String> selectedIds;
  final Set<String> excludeIds;
  final Widget? header;

  @override
  State<UserSearch> createState() => _UserSearchState();
}

class _UserSearchState extends State<UserSearch> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<UserProfile> _results = const [];
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value));
  }

  Future<void> _run(String value) async {
    final id = ++_requestId;
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final me = context.read<Session>().uid;
      final results = await context
          .read<OrbitServices>()
          .users
          .search(value, excludeUid: me);
      if (!mounted || id != _requestId) return;
      setState(() {
        _results =
            results.where((u) => !widget.excludeIds.contains(u.uid)).toList();
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = 'Search failed. Check your connection.');
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.text.trim().isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _query,
            autofocus: widget.autofocus,
            onChanged: _onChanged,
            onSubmitted: _run,
            decoration: InputDecoration(
              hintText: 'Search by email or name',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
        ),
        ?widget.header,
        Expanded(
          child: _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: OrbitColors.soft)))
              : _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          hasQuery && !_loading
                              ? 'No one found. Try their full email address.'
                              : 'Find people who use Orbit.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: OrbitColors.soft),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final user = _results[index];
                        final selected =
                            widget.selectedIds.contains(user.uid);
                        return ListTile(
                          minTileHeight: 56,
                          leading: AvatarBubble(
                            name: user.displayName,
                            photoUrl: user.photoUrl,
                            seed: user.uid,
                            online: user.isOnlineAt(DateTime.now()),
                          ),
                          title: Text(user.displayName),
                          subtitle: Text(
                            user.about.isNotEmpty
                                ? user.about
                                : presenceLabel(user, DateTime.now()),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: OrbitColors.soft),
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle_rounded,
                                  color: OrbitColors.accent)
                              : null,
                          selected: selected,
                          onTap: () => widget.onSelect(user),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
