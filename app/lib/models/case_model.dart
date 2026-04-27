import 'package:cloud_firestore/cloud_firestore.dart';

class CaseModel {
  final String id;
  final String name;
  final DateTime createdAt;

  CaseModel({required this.id, required this.name, required this.createdAt});

  factory CaseModel.fromMap(String id, Map<String, dynamic> data) {
    return CaseModel(
      id: id,
      name: data['name'] as String? ?? 'Caso sin nombre',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
