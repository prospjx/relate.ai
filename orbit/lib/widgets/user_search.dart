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
    final palette = MessengerPalette.of(context);
    final hasQuery = _query.text.trim().isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            controller: _query,
            autofocus: widget.autofocus,
            onChanged: _onChanged,
            onSubmitted: _run,
            decoration: InputDecoration(
              hintText: 'Search by email or name',
              isDense: true,
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: palette.mutedInk,
              ),
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
                  child: Text(
                    _error!,
                    style: TextStyle(color: palette.secondaryInk, fontSize: 14),
                  ),
                )
              : _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          hasQuery && !_loading
                              ? 'No one found. Try their full email address.'
                              : 'Search by name or email to start a chat.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.secondaryInk,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _results.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        thickness: 1,
                        indent: 72,
                        color: palette.hairline,
                      ),
                      itemBuilder: (context, index) {
                        final user = _results[index];
                        final selected = widget.selectedIds.contains(user.uid);
                        return ListTile(
                          minTileHeight: 56,
                          horizontalTitleGap: 16,
                          leading: AvatarBubble(
                            name: user.displayName,
                            photoUrl: user.photoUrl,
                            seed: user.uid,
                            size: 40,
                            online: user.isOnlineAt(DateTime.now()),
                          ),
                          title: Text(
                            user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: palette.ink,
                            ),
                          ),
                          subtitle: Text(
                            user.about.isNotEmpty
                                ? user.about
                                : presenceLabel(user, DateTime.now()),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.secondaryInk,
                              fontSize: 13.5,
                            ),
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: palette.accent,
                                  size: 22,
                                )
                              : null,
                          selected: selected,
                          selectedTileColor:
                              palette.accent.withValues(alpha: 0.06),
                          onTap: () => widget.onSelect(user),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
