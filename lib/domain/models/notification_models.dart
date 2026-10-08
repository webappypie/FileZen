import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Categories of notifications supported in FileZen.
enum NotificationType {
  system,
  storage,
  security,
  ai,
  transfer;

  String get displayName {
    switch (this) {
      case NotificationType.system:
        return 'System';
      case NotificationType.storage:
        return 'Storage';
      case NotificationType.security:
        return 'Security';
      case NotificationType.ai:
        return 'AI';
      case NotificationType.transfer:
        return 'Transfer';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationType.system:
        return Icons.info_outline_rounded;
      case NotificationType.storage:
        return Icons.storage_rounded;
      case NotificationType.security:
        return Icons.security_rounded;
      case NotificationType.ai:
        return Icons.psychology_rounded;
      case NotificationType.transfer:
        return Icons.swap_horiz_rounded;
    }
  }

  Color get color {
    switch (this) {
      case NotificationType.system:
        return AppColors.info;
      case NotificationType.storage:
        return AppColors.warning;
      case NotificationType.security:
        return AppColors.typeVault;
      case NotificationType.ai:
        return AppColors.secondary;
      case NotificationType.transfer:
        return AppColors.primary;
    }
  }
}

/// Notification priority level.
enum NotificationPriority {
  low,
  normal,
  high,
  critical;
}

/// Filter selection for Notification Center.
enum NotificationFilter {
  all,
  unread,
  storage,
  security,
  ai,
  system;

  String get label {
    switch (this) {
      case NotificationFilter.all:
        return 'All';
      case NotificationFilter.unread:
        return 'Unread';
      case NotificationFilter.storage:
        return 'Storage';
      case NotificationFilter.security:
        return 'Security';
      case NotificationFilter.ai:
        return 'AI';
      case NotificationFilter.system:
        return 'System';
    }
  }
}

/// Complete representation of an in-app notification in FileZen.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final NotificationType type;
  final NotificationPriority priority;
  final String? actionRoute;
  final String? actionLabel;
  final Map<String, dynamic>? actionPayload;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.type = NotificationType.system,
    this.priority = NotificationPriority.normal,
    this.actionRoute,
    this.actionLabel,
    this.actionPayload,
  });

  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? timestamp,
    bool? isRead,
    NotificationType? type,
    NotificationPriority? priority,
    String? actionRoute,
    String? actionLabel,
    Map<String, dynamic>? actionPayload,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      actionRoute: actionRoute ?? this.actionRoute,
      actionLabel: actionLabel ?? this.actionLabel,
      actionPayload: actionPayload ?? this.actionPayload,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
        'type': type.name,
        'priority': priority.name,
        'actionRoute': actionRoute,
        'actionLabel': actionLabel,
        'actionPayload': actionPayload,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['isRead'] as bool? ?? false,
      type: NotificationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => NotificationType.system,
      ),
      priority: NotificationPriority.values.firstWhere(
        (p) => p.name == json['priority'],
        orElse: () => NotificationPriority.normal,
      ),
      actionRoute: json['actionRoute'] as String?,
      actionLabel: json['actionLabel'] as String?,
      actionPayload: json['actionPayload'] as Map<String, dynamic>?,
    );
  }
}
