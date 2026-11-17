import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../services/gif_service.dart';
import 'auth_repository.dart';
import 'chat_repository.dart';
import 'media_repository.dart';
import 'user_repository.dart';

/// Everything the UI needs to talk to the backend, provided once at the root.
class OrbitServices {
  OrbitServices({
    required this.auth,
    required this.users,
    required this.chats,
    required this.media,
    required this.gifs,
  });

  factory OrbitServices.firebase() {
    final firestore = FirebaseFirestore.instance;
    final users = UserRepository(firestore);
    return OrbitServices(
      auth: AuthRepository(FirebaseAuth.instance, users),
      users: users,
      chats: ChatRepository(firestore),
      media: MediaRepository(FirebaseStorage.instance),
      gifs: GifService.fromEnvironment(),
    );
  }

  final AuthRepository auth;
  final UserRepository users;
  final ChatRepository chats;
  final MediaRepository media;
  final GifService gifs;
}
