import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inkdframes_project.dart';
import 'dart:convert';
import 'workspace_screen.dart';
import '../painters/frame_thumbnail_painter.dart';

class ProjectLibraryScreen extends StatefulWidget {
  const ProjectLibraryScreen({super.key});

  @override
  State<ProjectLibraryScreen> createState() => _ProjectLibraryScreenState();
}

class _ProjectLibraryScreenState extends State<ProjectLibraryScreen> {
  final List<InkdFramesProject> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadProjectIds();
  }

  Future<void> _loadProjectIds() async {
    final prefs = await SharedPreferences.getInstance();
    final projectIds = prefs.getStringList('project_ids') ?? [];
    final projects = <InkdFramesProject>[];

    for (final id in projectIds) {
      final jsonString = prefs.getString('project_$id');

      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        projects.add(InkdFramesProject.fromJson(json));
      }
    }

    if (!mounted) return;

    setState(() {
      _projects
        ..clear()
        ..addAll(projects);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Project Library')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _projects.length,
        itemBuilder: (context, index) {
          final project = _projects[index];

          return Card(
            child: ListTile(
              leading: SizedBox(
                width: 72,
                height: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    painter: project.frames.isNotEmpty
                        ? FrameThumbnailPainter(strokes: project.frames.first)
                        : null,
                    child: project.frames.isEmpty
                        ? const Center(child: Icon(Icons.movie_outlined))
                        : const SizedBox.expand(),
                  ),
                ),
              ),
              title: Text(project.name),
              subtitle: Text(
                '${project.frames.length} frames • ${project.fps} FPS',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final controller = TextEditingController(
                        text: project.name,
                      );

                      final newName = await showDialog<String>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Rename project'),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  final name = controller.text.trim();

                                  if (name.isNotEmpty) {
                                    Navigator.pop(context, name);
                                  }
                                },
                                child: const Text('Rename'),
                              ),
                            ],
                          );
                        },
                      );

                      controller.dispose();
                      if (newName == null) return;

                      final prefs = await SharedPreferences.getInstance();

                      final renamedProject = InkdFramesProject(
                        id: project.id,
                        name: newName,
                        fps: project.fps,
                        frames: project.frames,
                      );

                      await prefs.setString(
                        'project_${project.id}',
                        jsonEncode(renamedProject.toJson()),
                      );

                      setState(() {
                        _projects[index] = renamedProject;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final shouldDelete = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Delete project?'),
                            content: Text(
                              'Are you sure you want to delete "${project.name}"?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          );
                        },
                      );

                      if (shouldDelete != true) return;
                      final prefs = await SharedPreferences.getInstance();

                      await prefs.remove('project_${project.id}');
                      final projectIds =
                          prefs.getStringList('project_ids') ?? [];
                      projectIds.remove(project.id);
                      await prefs.setStringList('project_ids', projectIds);

                      setState(() {
                        _projects.removeAt(index);
                      });
                    },
                  ),
                ],
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WorkspaceScreen(projectId: project.id),
                  ),
                );

                _loadProjectIds();
              },
            ),
          );
        },
      ),
    );
  }
}
