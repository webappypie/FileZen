import 'package:flutter/material.dart';

/// Represents a distinct storage volume or root directory accessible to FileZen.
class StorageLocation {
  final String id;
  final String name;
  final String path;
  final int totalBytes;
  final int freeBytes;
  final bool isRemovable;
  final bool isReadOnly;
  final IconData icon;

  const StorageLocation({
    required this.id,
    required this.name,
    required this.path,
    required this.totalBytes,
    required this.freeBytes,
    this.isRemovable = false,
    this.isReadOnly = false,
    this.icon = Icons.phone_android_rounded,
  });

  int get usedBytes => totalBytes > freeBytes ? totalBytes - freeBytes : 0;
  double get usedRatio => totalBytes > 0 ? usedBytes / totalBytes : 0.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageLocation && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'StorageLocation($name, path: $path, free: $freeBytes/$totalBytes)';
}
