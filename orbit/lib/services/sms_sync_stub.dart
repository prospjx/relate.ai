import '../data/services.dart';
import 'sms_sync.dart';

SmsSync createSmsSync({
  required OrbitServices services,
  required String uid,
  required String Function() displayName,
}) =>
    SmsSync();
