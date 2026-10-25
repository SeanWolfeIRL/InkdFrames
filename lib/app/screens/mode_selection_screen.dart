import 'package:flutter/material.dart';

import 'project_library_screen.dart';
import 'welcome_home_screen.dart';

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  void _enter(BuildContext context, Widget destination) {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF17121F), Color(0xFF211A30), Color(0xFF111018)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_motion_rounded,
                      color: Color(0xFFD1B4FF),
                      size: 46,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'InkdFrames',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 35,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your imagination, frame by frame.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFB8ACC8), fontSize: 13),
                    ),
                    const SizedBox(height: 36),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF292237),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFF463A57)),
                      ),
                      child: Column(
                        children: [
                          _modeTile(
                            context,
                            icon: Icons.draw_rounded,
                            title: 'Enter Studio',
                            subtitle: 'Draw, animate and create',
                            destination: const ProjectLibraryScreen(),
                          ),
                          const Divider(color: Color(0xFF51445F), height: 18),
                          _modeTile(
                            context,
                            icon: Icons.home_rounded,
                            title: 'Enter Home',
                            subtitle: 'Explore your creative world',
                            destination: const WelcomeHomeScreen(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'BETA',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 3,
                        color: Color(0xFF897B9C),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget destination,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _enter(context, destination),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF40344F),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: const Color(0xFFD1B4FF), size: 25),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB8ACC8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFD1B4FF)),
            ],
          ),
        ),
      ),
    );
  }
}
