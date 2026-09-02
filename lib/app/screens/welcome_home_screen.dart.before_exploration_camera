import 'package:flutter/material.dart';

import 'home_screen.dart';

class WelcomeHomeScreen extends StatelessWidget {
  const WelcomeHomeScreen({super.key});

  void _goHome(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/inkdframes_home_exterior_v1.png',
                fit: BoxFit.cover,
              ),

              // Invisible interactive area over the cottage door.
              Positioned(
                left: constraints.maxWidth * 0.475,
                top: constraints.maxHeight * 0.44,
                width: constraints.maxWidth * 0.105,
                height: constraints.maxHeight * 0.30,
                child: Semantics(
                  button: true,
                  label: 'Go home',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _goHome(context),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
