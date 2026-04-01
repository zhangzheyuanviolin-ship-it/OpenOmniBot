import 'package:flutter/material.dart';
import 'package:ui/features/home/pages/authorize/authorize_page_args.dart';
import 'package:ui/features/home/pages/authorize/widgets/permission_section.dart';
import 'package:ui/services/permission_service.dart';
import 'package:ui/theme/app_colors.dart';

class PermissionSectionCard extends StatefulWidget {
  final Map<String, dynamic> cardData;
  final void Function(List<String> requiredPermissionIds)? onRequestAuthorize;

  const PermissionSectionCard({
    super.key,
    required this.cardData,
    this.onRequestAuthorize,
  });

  @override
  State<PermissionSectionCard> createState() => _PermissionSectionCardState();
}

class _PermissionSectionCardState extends State<PermissionSectionCard> {
  late final List<PermissionData> _backgroundPermissions;

  @override
  void initState() {
    super.initState();
    final requiredPermissionIds = normalizeRequiredPermissionIds(
      widget.cardData['requiredPermissionIds'] as List?,
    );
    _backgroundPermissions = [
      ...PermissionService.buildDisplayPermissionsForIds(
        requiredPermissionIds.isEmpty
            ? kTaskExecutionRequiredPermissionIds
            : requiredPermissionIds,
      ),
    ];
  }

  void _goAuthorizePage() {
    final requiredPermissionIds = normalizeRequiredPermissionIds(
      widget.cardData['requiredPermissionIds'] as List?,
    );
    widget.onRequestAuthorize?.call(
      requiredPermissionIds.isEmpty
          ? kTaskExecutionRequiredPermissionIds
          : requiredPermissionIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 30,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 1,
                      child: PermissionSection(
                        permissions: _backgroundPermissions,
                        spacing: 14,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: const Alignment(0.50, 0),
                        end: const Alignment(0.50, 0.50),
                        colors: [
                          Colors.white.withValues(alpha: 0.3),
                          const Color(0xFFF9FDFF),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Image.asset(
                    'assets/chatbot/permission_section_bg1.png',
                    fit: BoxFit.fill,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Image.asset(
                    'assets/chatbot/permission_section_bg2.png',
                    fit: BoxFit.fill,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Center(
                    child: GestureDetector(
                      onTap: _goAuthorizePage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment(-0.17, -0.47),
                            end: Alignment(1.48, 1.69),
                            colors: [Color(0xFF0056FA), Color(0xB2609CF7)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '前往开启',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontFamily: 'PingFang SC',
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
