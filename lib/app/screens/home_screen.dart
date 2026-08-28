import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'project_library_screen.dart';
import 'workspace_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _showComingSoon(BuildContext context, String area) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(area),
          content: const Text(
            'This part of your InkdFrames home is still being built.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createBlankAnimation(BuildContext context) async {
    final screenSize = MediaQuery.sizeOf(context);
    final initialPortrait = screenSize.height > screenSize.width;

    final result = await showDialog<({String name, bool portrait, double fps})>(
      context: context,
      builder: (dialogContext) {
        return _CreateAnimationDialog(
          title: 'Create animation',
          initialName: '',
          initialPortrait: initialPortrait,
        );
      },
    );

    if (result == null || !context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceScreen(
          projectName: result.name,
          initialCanvasWidth: result.portrait ? 1080 : 1920,
          initialCanvasHeight: result.portrait ? 1920 : 1080,
          initialFps: result.fps,
        ),
      ),
    );
  }

  Future<void> _importMemory(BuildContext context) async {
    final mediaType = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Import a Memory'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext, 'image');
              },
              child: const ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text('Import Image'),
                subtitle: Text('JPG, JPEG or PNG'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext, 'video');
              },
              child: const ListTile(
                leading: Icon(Icons.videocam_outlined),
                title: Text('Import Video'),
                subtitle: Text('Video reference'),
              ),
            ),
          ],
        );
      },
    );

    if (mediaType == null || !context.mounted) return;

    String? sourcePath;
    String? sourceName;

    if (Platform.isLinux) {
      final testDirectory = Directory(
        mediaType == 'image'
            ? '/sdcard/InkdFramesTestMedia/images'
            : '/sdcard/InkdFramesTestMedia/videos',
      );

      final files = testDirectory.existsSync()
          ? testDirectory.listSync().whereType<File>().toList()
          : <File>[];

      if (files.isEmpty) {
        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mediaType == 'image'
                  ? 'No test images found in InkdFramesTestMedia/images.'
                  : 'No test videos found in InkdFramesTestMedia/videos.',
            ),
          ),
        );

        return;
      }

      final selectedFile = await showDialog<File>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              mediaType == 'image' ? 'Choose Test Image' : 'Choose Test Video',
            ),
            content: SizedBox(
              width: 420,
              height: 320,
              child: ListView.separated(
                itemCount: files.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final file = files[index];
                  final name = file.uri.pathSegments.last;

                  return ListTile(
                    leading: Icon(
                      mediaType == 'image'
                          ? Icons.image_outlined
                          : Icons.movie_outlined,
                    ),
                    title: Text(name),
                    onTap: () {
                      Navigator.pop(dialogContext, file);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );

      if (selectedFile == null || !context.mounted) {
        return;
      }

      sourcePath = selectedFile.path;
      sourceName = selectedFile.uri.pathSegments.last;
    } else {
      final pickedFile = await FilePicker.pickFile(
        type: mediaType == 'image' ? FileType.image : FileType.video,
      );

      if (pickedFile == null || !context.mounted) {
        return;
      }

      if (pickedFile.path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access that file.')),
        );
        return;
      }

      sourcePath = pickedFile.path!;
      sourceName = pickedFile.name;
    }

    final screenSize = MediaQuery.sizeOf(context);
    final initialPortrait = screenSize.height > screenSize.width;

    final result = await showDialog<({String name, bool portrait, double fps})>(
      context: context,
      builder: (dialogContext) {
        return _CreateAnimationDialog(
          title: mediaType == 'image'
              ? 'Create from image'
              : 'Create from video',
          initialName: sourceName!.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          initialPortrait: initialPortrait,
          showFps: mediaType == 'video',
          initialFps: mediaType == 'video' ? 12 : 8,
        );
      },
    );

    if (result == null || !context.mounted) return;

    final referenceDirectory = Platform.isLinux
        ? Directory('/tmp/inkdframes_reference_media')
        : Directory('/data/user/0/com.inkdframes.app/files/reference_media');

    if (!await referenceDirectory.exists()) {
      await referenceDirectory.create(recursive: true);
    }

    final extension = sourceName.contains('.')
        ? '.${sourceName.split('.').last}'
        : '';

    final storedPath =
        '${referenceDirectory.path}/'
        '${DateTime.now().microsecondsSinceEpoch}$extension';

    await File(sourcePath).copy(storedPath);

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceScreen(
          projectName: result.name,
          initialCanvasWidth: result.portrait ? 1080 : 1920,
          initialCanvasHeight: result.portrait ? 1920 : 1080,
          initialReferenceMediaPath: storedPath,
          initialReferenceMediaType: mediaType,
          initialFps: result.fps,
        ),
      ),
    );
  }

  Widget _roomHotspot({required String tooltip, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.white12,
            highlightColor: Colors.white10,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isPortrait = constraints.maxHeight > constraints.maxWidth;

          final roomHeight = constraints.maxHeight;

          // Portrait keeps the room at a readable landscape scale.
          // The phone becomes a horizontal viewport into the room.
          final roomWidth = isPortrait
              ? roomHeight * (16 / 9)
              : constraints.maxWidth;

          Widget buildRoom() {
            return SizedBox(
              width: roomWidth,
              height: roomHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/inkdframes_home_room_v1.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),

                  // PROJECT WALL
                  Positioned(
                    left: roomWidth * 0.39,
                    top: roomHeight * 0.18,
                    width: roomWidth * 0.31,
                    height: roomHeight * 0.39,
                    child: _roomHotspot(
                      tooltip: 'Project Wall',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ProjectLibraryScreen(),
                          ),
                        );
                      },
                    ),
                  ),

                  // CREATION DESK
                  Positioned(
                    left: roomWidth * 0.31,
                    top: roomHeight * 0.63,
                    width: roomWidth * 0.37,
                    height: roomHeight * 0.28,
                    child: _roomHotspot(
                      tooltip: 'Creation Desk',
                      onTap: () async {
                        final action = await showModalBottomSheet<String>(
                          context: context,
                          showDragHandle: true,
                          builder: (sheetContext) {
                            return SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  24,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const ListTile(
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('Creation Desk'),
                                      subtitle: Text('Start something new.'),
                                    ),
                                    const SizedBox(height: 4),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.add_box_outlined,
                                      ),
                                      title: const Text('Blank Animation'),
                                      onTap: () {
                                        Navigator.pop(sheetContext, 'blank');
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.photo_library_outlined,
                                      ),
                                      title: const Text('Import a Memory'),
                                      onTap: () {
                                        Navigator.pop(sheetContext, 'import');
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );

                        if (!context.mounted) return;

                        if (action == 'blank') {
                          await _createBlankAnimation(context);
                        } else if (action == 'import') {
                          await _importMemory(context);
                        }
                      },
                    ),
                  ),

                  // BAG
                  Positioned(
                    left: roomWidth * 0.775,
                    top: roomHeight * 0.63,
                    width: roomWidth * 0.18,
                    height: roomHeight * 0.25,
                    child: _roomHotspot(
                      tooltip: 'The Bag',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'The Bag room entrance is ready for wiring next 🎒',
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // KITCHEN
                  Positioned(
                    left: roomWidth * 0.23,
                    top: roomHeight * 0.12,
                    width: roomWidth * 0.16,
                    height: roomHeight * 0.48,
                    child: _roomHotspot(
                      tooltip: 'Kitchen · Coming Soon',
                      onTap: () {
                        _showComingSoon(context, 'Kitchen');
                      },
                    ),
                  ),

                  // GARDEN
                  Positioned(
                    left: roomWidth * 0.70,
                    top: roomHeight * 0.16,
                    width: roomWidth * 0.17,
                    height: roomHeight * 0.47,
                    child: _roomHotspot(
                      tooltip: 'Garden · Coming Soon',
                      onTap: () {
                        _showComingSoon(context, 'Garden');
                      },
                    ),
                  ),

                  // SETTINGS
                  Positioned(
                    left: roomWidth * 0.795,
                    top: roomHeight * 0.855,
                    width: roomWidth * 0.19,
                    height: roomHeight * 0.12,
                    child: _roomHotspot(
                      tooltip: 'Options',
                      onTap: () {
                        _showComingSoon(context, 'Options');
                      },
                    ),
                  ),

                  // WINDOW
                  Positioned(
                    left: roomWidth * 0.015,
                    top: roomHeight * 0.18,
                    width: roomWidth * 0.20,
                    height: roomHeight * 0.42,
                    child: _roomHotspot(
                      tooltip: 'Window',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('A quiet view outside. 🌿'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }

          if (!isPortrait) {
            return buildRoom();
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: buildRoom(),
          );
        },
      ),
    );
  }
}

class _CreateAnimationDialog extends StatefulWidget {
  const _CreateAnimationDialog({
    required this.title,
    required this.initialName,
    required this.initialPortrait,
    this.showFps = false,
    this.initialFps = 8,
  });

  final String title;
  final String initialName;
  final bool initialPortrait;
  final bool showFps;
  final double initialFps;

  @override
  State<_CreateAnimationDialog> createState() => _CreateAnimationDialogState();
}

class _CreateAnimationDialogState extends State<_CreateAnimationDialog> {
  late final TextEditingController _controller;
  late bool _isPortrait;
  late double _fps;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _isPortrait = widget.initialPortrait;
    _fps = widget.initialFps;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Animation name',
                    hintText: 'e.g. Bouncing Ball',
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Canvas orientation',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.crop_landscape),
                      label: Text('Landscape'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.crop_portrait),
                      label: Text('Portrait'),
                    ),
                  ],
                  selected: {_isPortrait},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _isPortrait = selection.first;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _isPortrait ? '1080 × 1920' : '1920 × 1080',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.showFps) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Rotoscope FPS',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text('${_fps.round()} FPS'),
                    ],
                  ),
                  Slider(
                    value: _fps,
                    min: 6,
                    max: 24,
                    divisions: 18,
                    label: '${_fps.round()} FPS',
                    onChanged: (value) {
                      setState(() {
                        _fps = value;
                      });
                    },
                  ),
                  Text(
                    _fps == 12
                        ? '12 FPS · Classic smooth rotoscoping'
                        : '${_fps.round()} drawing frames per second',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _controller.text.trim();

            if (name.isEmpty) return;

            Navigator.pop(context, (
              name: name,
              portrait: _isPortrait,
              fps: _fps,
            ));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
