import 'package:cloud_firestore/cloud_firestore.dart';

class AdminProfileService {
	static final FirebaseFirestore _db = FirebaseFirestore.instance;

	static Stream<Map<String, dynamic>> streamProfile(String email) {
		final normalized = email.trim().toLowerCase();
		if (normalized.isEmpty) {
			return Stream.value(const <String, dynamic>{});
		}

		return _db
				.collection('admins')
				.where('email', isEqualTo: normalized)
				.limit(1)
				.snapshots()
				.asyncMap((snap) async {
			if (snap.docs.isNotEmpty) {
				return snap.docs.first.data();
			}

			final byGmail = await _db
					.collection('admins')
					.where('gmail', isEqualTo: normalized)
					.limit(1)
					.get();
			if (byGmail.docs.isNotEmpty) {
				return byGmail.docs.first.data();
			}

			return <String, dynamic>{};
		});
	}
}
