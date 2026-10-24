import 'package:flutter/material.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/brand_widgets.dart';
import '../../providers/auth_provider.dart';
import '../shared/editor.dart';
import '../../core/network/workspace_api.dart';
import 'access.dart';
import 'record_screen.dart';

Future<void> showWorkflowProfile(
  BuildContext context,
  AuthProvider auth, {
  required VoidCallback onNotifications,
}) async {
  final action = await showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      backgroundColor: Colors.transparent,
      child: ProfileCard(user: auth.user!),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'notifications') {
    onNotifications();
    return;
  }
  if (action == 'logout') {
    if (await confirmAction(
      context,
      'Sign out?',
      'You can sign back in with your work email.',
    )) {
      await auth.logout();
    }
    return;
  }
  final access = Access(auth.user!);
  if (action == 'edit' && access.admin) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecordScreen(
          kind: 'People',
          id: auth.user!['id'] as int,
          api: WorkspaceApi(auth.api),
          access: access,
        ),
      ),
    );
    await auth.refreshProfile();
  } else if (action == 'password' && access.admin) {
    final result = await showEditor(
      context,
      title: 'Change password',
      fields: const [
        EditField(
          'password',
          'New temporary password',
          required: true,
          secret: true,
        ),
      ],
      save: (body) async {
        try {
          await auth.api.dio.patch(
            '/api/users/${auth.user!['id']}/password',
            data: body,
          );
        } catch (e) {
          throw Exception(auth.api.errorMessage(e));
        }
      },
    );
    if (result != null) await auth.logout();
  } else {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == 'password' ? 'Password help' : 'Your profile'),
        content: Text(
          action == 'password'
              ? 'Ask your company administrator to reset your password. You will choose a new personal password when you sign in again.'
              : 'Your profile is managed by your company administrator. Contact them to update your name, email, or department.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class ProfileCard extends StatelessWidget {
  final Record user;
  const ProfileCard({super.key, required this.user});
  @override
  Widget build(BuildContext context) {
    final role = user['role'] as String? ?? 'EMPLOYEE';
    final active = user['status'] == null || user['status'] == 'ACTIVE';
    final color = role == 'ADMIN'
        ? const Color(0xFFA36C16)
        : role == 'MANAGER'
        ? AppTheme.teal
        : const Color(0xFF2868BD);
    final icon = role == 'ADMIN'
        ? Icons.workspace_premium_rounded
        : role == 'MANAGER'
        ? Icons.groups_rounded
        : Icons.work_rounded;
    final name = person(user);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 460,
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: WaveBackdrop(
        borderRadius: BorderRadius.circular(30),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.muted.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Close profile',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Profile',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 14),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 98,
                    height: 98,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE8DEFF),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Text(
                      name.isEmpty ? 'U' : name.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 38,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.teal,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 1,
                    bottom: 5,
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? const Color(0xFF62C630)
                            : AppTheme.muted,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 3),
              Text(
                '${user['email'] ?? ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 17),
                    const SizedBox(width: 7),
                    Text(
                      human(role),
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Surface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF62C630)
                            : AppTheme.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Account status',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    StatusPill('${user['status'] ?? 'ACTIVE'}'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Surface(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    _item(
                      context,
                      Icons.person_outline_rounded,
                      role == 'ADMIN' ? 'Edit profile' : 'Profile details',
                      'edit',
                    ),
                    const Divider(indent: 48, height: 1),
                    _item(
                      context,
                      Icons.lock_outline_rounded,
                      role == 'ADMIN' ? 'Change password' : 'Password help',
                      'password',
                    ),
                    const Divider(indent: 48, height: 1),
                    _item(
                      context,
                      Icons.notifications_none_rounded,
                      'Notifications',
                      'notifications',
                    ),
                    const Divider(indent: 48, height: 1),
                    _info(Icons.translate_rounded, 'Language', 'English'),
                    const Divider(indent: 48, height: 1),
                    _info(Icons.palette_outlined, 'Theme', 'Lavender'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFEBF1),
                    foregroundColor: const Color(0xFFD93646),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, 'logout'),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text(
                    'Sign out',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'THH Workflow v1.0.0',
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => ListTile(
    dense: true,
    minTileHeight: 48,
    leading: Icon(icon, size: 22, color: AppTheme.ink),
    title: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      size: 22,
      color: AppTheme.muted,
    ),
    onTap: () => Navigator.pop(context, value),
  );
  Widget _info(IconData icon, String label, String value) => ListTile(
    dense: true,
    minTileHeight: 46,
    leading: Icon(icon, size: 21, color: AppTheme.ink),
    title: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
    trailing: Text(
      value,
      style: const TextStyle(color: AppTheme.muted, fontSize: 11),
    ),
  );
}
