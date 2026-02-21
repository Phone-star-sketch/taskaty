import 'package:flutter/material.dart';

class ModernTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final bool isSelected;
  final Function(bool?) onSelectionChanged;
  final VoidCallback onTap;
  final Function(Map<String, dynamic>)? onDelete;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const ModernTaskCard({
    Key? key,
    required this.task,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.onTap,
    this.onDelete,
    required this.colorScheme,
    required this.theme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final assignments = task['task_assignments'] as List<dynamic>?;
    final assignment =
        assignments?.isNotEmpty == true ? assignments?.elementAt(0) : null;
    final assigneeProfile = assignment?['assignee_profile'];
    final creatorProfile = task['creator_profile'];

    // Use status from tasks table instead of assignment
    final status = task['status'] ?? 'new'; // Get status directly from task
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);

    // Get unique assignees to prevent duplicates
    final Map<String, Map<String, dynamic>> uniqueAssignees = {};
    if (assignments != null) {
      for (final assignment in assignments) {
        final userId = assignment['user_id']?.toString();
        final assigneeProfile = assignment['assignee_profile'];
        if (userId != null && assigneeProfile != null) {
          uniqueAssignees[userId] = assigneeProfile;
        }
      }
    }
    final uniqueAssigneesList = uniqueAssignees.values.toList();

    return Container(
      margin: const EdgeInsets.all(6), // Increased from 4
      child: Material(
        elevation: 0,
        borderRadius: BorderRadius.circular(24), // Increased from 20
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24), // Increased from 20
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surface,
                colorScheme.surface.withOpacity(0.8),
              ],
            ),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withOpacity(0.5)
                  : colorScheme.outline.withOpacity(0.2),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
              if (isSelected)
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24), // Increased from 20
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(24), // Increased from 20
                splashColor: colorScheme.primary.withOpacity(0.1),
                highlightColor: colorScheme.primary.withOpacity(0.05),
                child: Container(
                  padding: const EdgeInsets.all(20), // Reduced from 24
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with checkbox and status
                      Row(
                        children: [
                          _buildModernCheckbox(),
                          const SizedBox(width: 12), // Reduced from 16
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task['title'] ?? 'بدون عنوان',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    // Changed back from titleLarge
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 3, // Increased from 2 to allow more lines
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4), // Reduced from 6
                                Text(
                                  _formatDate(task['created_at']),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    // Changed back from bodyMedium
                                    color:
                                        colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildModernStatusChip(
                              status, statusColor, statusText),
                          if (onDelete != null) ...[
                            const SizedBox(width: 8), // Reduced from 12
                            _buildDeleteButton(context),
                          ],
                        ],
                      ),

                      const SizedBox(height: 16), // Reduced from 20

                      // Description
                      if (task['description'] != null) ...[
                        Container(
                          padding:
                              const EdgeInsets.all(12), // Reduced from 16
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant.withOpacity(0.3),
                            borderRadius:
                                BorderRadius.circular(12), // Reduced from 16
                          ),
                          child: Text(
                            task['description'],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              // Changed back from bodyLarge
                              color: colorScheme.onSurface.withOpacity(0.8),
                              height: 1.3, // Reduced line height from 1.4
                            ),
                            maxLines: 2, // Reduced from 3 to save space
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16), // Reduced from 20
                      ],

                      // Users section
                      Flexible( // Wrapped in Flexible to prevent overflow
                        child: Container(
                          padding: const EdgeInsets.all(12), // Reduced from 16
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withOpacity(0.1),
                            borderRadius:
                                BorderRadius.circular(12), // Reduced from 16
                            border: Border.all(
                              color:
                                  colorScheme.primaryContainer.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildModernUserInfo(
                                  'منشئ',
                                  creatorProfile,
                                  Icons.person_add,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40, // Reduced from 50
                                color: colorScheme.outline.withOpacity(0.3),
                              ),
                              const SizedBox(width: 12), // Reduced from 16
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.assignment_ind,
                                            size: 18,
                                            color: colorScheme
                                                .primary), // Increased from 14
                                        const SizedBox(
                                            width: 6), // Increased from 4
                                        Text(
                                          'معين إلى',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            // Changed from bodySmall
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8), // Increased from 6
                                    if (uniqueAssigneesList.isNotEmpty)
                                      uniqueAssigneesList.length > 1
                                          ? SizedBox(
                                              height: 56,
                                              child: ListView.builder(
                                                itemCount:
                                                    uniqueAssigneesList.length,
                                                itemBuilder: (context, idx) {
                                                  final assignee =
                                                      uniqueAssigneesList[idx];
                                                  final name = assignee['name']
                                                          ?.toString() ??
                                                      'غير محدد';
                                                  final avatarUrl =
                                                      assignee['avatar_url']
                                                          ?.toString();

                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 8.0),
                                                    child: Row(
                                                      children: [
                                                        CircleAvatar(
                                                          radius:
                                                              20, // Increased from 16
                                                          backgroundColor:
                                                              colorScheme
                                                                  .primaryContainer
                                                                  .withOpacity(
                                                                      0.7),
                                                          backgroundImage:
                                                              avatarUrl != null &&
                                                                      avatarUrl
                                                                          .isNotEmpty
                                                                  ? NetworkImage(
                                                                      avatarUrl)
                                                                  : null,
                                                          child:
                                                              avatarUrl == null ||
                                                                      avatarUrl
                                                                          .isEmpty
                                                                  ? Text(
                                                                      name.isNotEmpty
                                                                          ? name[0]
                                                                              .toUpperCase()
                                                                          : '?',
                                                                      style:
                                                                          TextStyle(
                                                                        color: colorScheme
                                                                            .onPrimaryContainer,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontSize:
                                                                            16, // Increased from 12
                                                                      ),
                                                                    )
                                                                  : null,
                                                        ),
                                                        const SizedBox(
                                                            width:
                                                                12), // Increased from 8
                                                        Expanded(
                                                          child: Text(
                                                            name,
                                                            style: theme.textTheme
                                                                .bodyMedium // Changed from bodySmall
                                                                ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight.w500,
                                                              color: colorScheme
                                                                  .onSurface,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow
                                                                .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            )
                                          : Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 20, // Increased from 16
                                                  backgroundColor: colorScheme
                                                      .primaryContainer
                                                      .withOpacity(0.7),
                                                  backgroundImage: uniqueAssigneesList[
                                                                      0][
                                                                  'avatar_url'] !=
                                                              null &&
                                                          uniqueAssigneesList[0]
                                                                  ['avatar_url']
                                                              .toString()
                                                              .isNotEmpty
                                                      ? NetworkImage(
                                                          uniqueAssigneesList[0]
                                                              ['avatar_url'])
                                                      : null,
                                                  child: uniqueAssigneesList[0][
                                                                  'avatar_url'] ==
                                                              null ||
                                                          uniqueAssigneesList[0]
                                                                  ['avatar_url']
                                                              .toString()
                                                              .isEmpty
                                                      ? Text(
                                                          (uniqueAssigneesList[0]
                                                                          ['name']
                                                                      ?.toString()
                                                                      .isNotEmpty ??
                                                                  false)
                                                              ? uniqueAssigneesList[
                                                                      0]['name']
                                                                  .toString()[0]
                                                                  .toUpperCase()
                                                              : '?',
                                                          style: TextStyle(
                                                            color: colorScheme
                                                                .onPrimaryContainer,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize:
                                                                16, // Increased from 12
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                                const SizedBox(
                                                    width:
                                                        12), // Increased from 8
                                                Expanded(
                                                  child: Text(
                                                    uniqueAssigneesList[0]['name']
                                                            ?.toString() ??
                                                        'غير محدد',
                                                    style: theme.textTheme
                                                        .bodyMedium // Changed from bodySmall
                                                        ?.copyWith(
                                                      fontWeight: FontWeight.w500,
                                                      color:
                                                          colorScheme.onSurface,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            )
                                  else
                                    Text(
                                      'غير محدد',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        // Changed from bodySmall
                                        color: colorScheme.onSurface
                                            .withOpacity(0.7),
                                      ),
                                    ),
                            ]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernCheckbox() {
    return GestureDetector(
      onTap: () => onSelectionChanged(!isSelected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 28, // Increased from 24
        height: 28, // Increased from 24
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8), // Increased from 6
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: colorScheme.onPrimary,
                size: 20, // Increased from 16
              )
            : null,
      ),
    );
  }

  Widget _buildModernStatusChip(String status, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 8), // Increased padding
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24), // Increased from 20
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10, // Increased from 8
            height: 10, // Increased from 8
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8), // Increased from 6
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14, // Increased from 12
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernUserInfo(
      String label, Map<String, dynamic>? user, IconData icon) {
    final name = user?['name']?.toString() ?? 'غير محدد';
    final avatarUrl = user?['avatar_url']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18, // Increased from 14
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6), // Increased from 4
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                // Changed from bodySmall
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8), // Increased from 6
        Row(
          children: [
            Container(
              width: 40, // Increased from 32
              height: 40, // Increased from 32
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.primaryContainer.withOpacity(0.7),
                  ],
                ),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildAvatarFallback(name);
                        },
                      ),
                    )
                  : _buildAvatarFallback(name),
            ),
            const SizedBox(width: 12), // Increased from 8
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  // Changed from bodySmall
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatarFallback(String name) {
    return Container(
      width: 40, // Increased from 32
      height: 40, // Increased from 32
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.primaryContainer.withOpacity(0.7),
          ],
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: 18, // Increased from 14
          ),
        ),
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'تم التنفيذ';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'pending':
        return 'قيد الانتظار';
      default:
        return 'جديدة';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF4CAF50);
      case 'in_progress':
        return const Color(0xFF2196F3);
      case 'pending':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'غير محدد';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'تاريخ غير صالح';
    }
  }

  Widget _buildDeleteButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDeleteConfirmation(context),
      child: Container(
        padding: const EdgeInsets.all(8), // Increased from 6
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10), // Increased from 8
          border: Border.all(
            color: Colors.red.withOpacity(0.3),
          ),
        ),
        child: Icon(
          Icons.delete_outline,
          size: 22, // Increased from 18
          color: Colors.red,
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                color: Colors.red,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'حذف المهمة',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل أنت متأكد من حذف هذه المهمة؟',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  task['title'] ?? 'بدون عنوان',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'هذا الإجراء لا يمكن التراجع عنه.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red.withOpacity(0.8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: colorScheme.primary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDelete?.call(task);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('حذف'),
            ),
          ],
        );
      },
    );
  }
}

