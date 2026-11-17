import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/data/auth_repository.dart';
import 'package:orbit/data/user_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late UserRepository users;

  setUp(() {
    db = FakeFirebaseFirestore();
    users = UserRepository(db);
  });

  group('UserRepository', () {
    test('ensureProfile creates once and keeps existing data', () async {
      final first = await users.ensureProfile(
          uid: 'u1', email: 'maya@example.com', displayName: 'Maya');
      expect(first.displayName, 'Maya');
      await users.updateProfile('u1', about: 'Climbing');
      final second = await users.ensureProfile(
          uid: 'u1', email: 'maya@example.com', displayName: 'Other');
      expect(second.displayName, 'Maya');
      expect(second.about, 'Climbing');
    });

    test('falls back to the email name when no display name is given',
        () async {
      final p = await users.ensureProfile(uid: 'u2', email: 'sam@example.com');
      expect(p.displayName, 'sam');
    });

    test('updateProfile trims and validates', () async {
      await users.ensureProfile(uid: 'u1', email: 'a@b.c', displayName: 'A');
      await users.updateProfile('u1',
          displayName: '  Ann Lee ', phone: ' +1 555 ', photoUrl: 'https://p');
      var p = (await users.getUser('u1'))!;
      expect(p.displayName, 'Ann Lee');
      expect(p.phone, '+1 555');
      expect(p.photoUrl, 'https://p');
      await users.updateProfile('u1', clearPhoto: true);
      p = (await users.getUser('u1'))!;
      expect(p.photoUrl, isNull);
      expect(() => users.updateProfile('u1', displayName: ' '),
          throwsArgumentError);
    });

    test('search matches email exactly and names by prefix', () async {
      await users.ensureProfile(
          uid: 'm', email: 'Maya@Example.com', displayName: 'Maya Chen');
      await users.ensureProfile(
          uid: 'j', email: 'jordan@example.com', displayName: 'Jordan Hale');
      await users.ensureProfile(
          uid: 'me', email: 'me@example.com', displayName: 'Mark');

      final byEmail = await users.search('maya@example.com');
      expect(byEmail.map((u) => u.uid), ['m']);

      final byName = await users.search('Ma', excludeUid: 'me');
      expect(byName.map((u) => u.uid), ['m']);

      expect(await users.search('  '), isEmpty);
    });

    test('setPresence records online state and last seen', () async {
      await users.ensureProfile(uid: 'u1', email: 'a@b.c', displayName: 'A');
      await users.setPresence('u1', online: true);
      final p = (await users.getUser('u1'))!;
      expect(p.online, isTrue);
      expect(p.lastSeen, isNotNull);
    });
  });

  group('AuthRepository', () {
    test('signUp creates the profile with the chosen name', () async {
      final auth = MockFirebaseAuth();
      final repo = AuthRepository(auth, users);
      await repo.signUp(
          email: 'new@example.com', password: 'secret1', displayName: 'Nia');
      final uid = auth.currentUser!.uid;
      final profile = (await users.getUser(uid))!;
      expect(profile.displayName, 'Nia');
      expect(profile.email, 'new@example.com');
    });

    test('signUp requires a display name', () {
      final repo = AuthRepository(MockFirebaseAuth(), users);
      expect(
        () => repo.signUp(email: 'x@y.z', password: 'secret1', displayName: ''),
        throwsArgumentError,
      );
    });

    test('signOut marks the user offline', () async {
      final auth = MockFirebaseAuth(
          signedIn: true, mockUser: MockUser(uid: 'u1', email: 'a@b.c'));
      await users.ensureProfile(uid: 'u1', email: 'a@b.c', displayName: 'A');
      await users.setPresence('u1', online: true);
      await AuthRepository(auth, users).signOut();
      expect(auth.currentUser, isNull);
      expect((await users.getUser('u1'))!.online, isFalse);
    });

    test('describeError gives plain sentences', () {
      expect(
        AuthRepository.describeError(
            FirebaseAuthException(code: 'invalid-credential')),
        'Email or password is incorrect.',
      );
      expect(
        AuthRepository.describeError(
            FirebaseAuthException(code: 'email-already-in-use')),
        'An account already exists for that email.',
      );
      expect(AuthRepository.describeError(Exception('x')),
          'Something went wrong. Try again.');
    });
  });
}
