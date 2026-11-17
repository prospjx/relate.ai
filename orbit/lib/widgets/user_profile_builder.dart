import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../models/models.dart';

/// Listens to one user's profile and rebuilds when it changes. Keeps the same
/// stream across rebuilds so lists do not resubscribe on every frame.
class UserProfileBuilder extends StatefulWidget {
  const UserProfileBuilder({
    super.key,
    required this.uid,
    required this.builder,
  });

  final String uid;
  final Widget Function(BuildContext context, UserProfile? profile) builder;

  @override
  State<UserProfileBuilder> createState() => _UserProfileBuilderState();
}

class _UserProfileBuilderState extends State<UserProfileBuilder> {
  late Stream<UserProfile?> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _watch();
  }

  @override
  void didUpdateWidget(UserProfileBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) _stream = _watch();
  }

  Stream<UserProfile?> _watch() =>
      context.read<OrbitServices>().users.watchUser(widget.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile?>(
      stream: _stream,
      builder: (context, snap) => widget.builder(context, snap.data),
    );
  }
}
