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
          final isPortrait = constraints.maxHeight > constraints.maxWidth;

          Widget buildExterior({
            required double width,
            required double height,
          }) {
            return SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/inkdframes_home_exterior_v1.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),

                  // Invisible interactive area over the cottage door.
                  Positioned(
                    left: width * 0.475,
                    top: height * 0.44,
                    width: width * 0.105,
                    height: height * 0.30,
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
              ),
            );
          }

          // Landscape retains the existing full-screen exterior.
          if (!isPortrait) {
            return buildExterior(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            );
          }

          // Portrait becomes a horizontal viewport into the exterior,
          // matching the exploration language of the internal Home.
          final worldHeight = constraints.maxHeight;
          final worldWidth = worldHeight * (3 / 2);

          return InteractiveViewer(
            constrained: false,
            panEnabled: true,
            scaleEnabled: false,
            boundaryMargin: EdgeInsets.zero,
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.center,
            child: buildExterior(width: worldWidth, height: worldHeight),
          );
        },
      ),
    );
  }
}
