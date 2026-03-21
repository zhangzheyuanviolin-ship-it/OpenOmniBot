import 'package:flutter/material.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/app_text_styles.dart';
import 'package:ui/services/device_service.dart';
import 'package:ui/widgets/common_app_bar.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final versionInfo = await DeviceService.getAppVersion();
      if (versionInfo != null && mounted) {
        final versionName = versionInfo['versionName'] as String?;
        setState(() {
          _version = 'Version ${versionName ?? '-'}';
        });
      } else {
        setState(() {
          _version = 'Version -';
        });
      }
    } catch (e) {
      print('加载版本号失败: $e');
      setState(() {
        _version = 'Version -';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const CommonAppBar(title: '关于小万', primary: true),
      body: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 80),
                    // Logo
                    SizedBox(
                      width: 167,
                      height: 120,
                      child: Center(
                        child: Image.asset(
                          'assets/my/about_icon.png',
                          width: 167,
                          height: 120,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.image,
                              size: 96,
                              color: AppColors.primaryBlue,
                            );
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // 描述文字
                    Text(
                      '小万，是一款以智能对话为核心的手机AI助\n手，通过语义理解与持续学习能力，协助用户\n完成信息处理、决策辅助和日常管理。',
                    textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text70,
                        letterSpacing: 0.39,
                        height: 1.5,
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // 版本号
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _version,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.text70,
                            letterSpacing: 0.33,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 10),
                    const SizedBox(height: 154),
                  ],
                  ),
        ),
      ),
    );
  }
}
