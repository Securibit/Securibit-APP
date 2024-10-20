import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String?> loadUserUid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('UserUid');
  }

  Future<String?> fetchUserDisplayName(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('user')
          .where('uid', isEqualTo: uid)
          .get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['name'] != null && data['name'].isNotEmpty) {
          return data['name'];
        }
      }
    } catch (error) {
      print('Error fetching user display name: $error');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchUserTotps(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('user')
          .where('uid', isEqualTo: uid)
          .get();

      final List<Map<String, dynamic>> totps = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['totp'] != null && data['totp'].isNotEmpty) {
          for (var totpEntry in data['totp']) {
            totps.add({
              'name': totpEntry['name'] ?? 'No Name',
              'secret': totpEntry['secret'] ?? '',
              'category': totpEntry['category'] ?? 'Default',
            });
          }
        }
      }
      return totps;
    } catch (error) {
      print('Error fetching TOTP data: $error');
      return [];
    }
  }
}
