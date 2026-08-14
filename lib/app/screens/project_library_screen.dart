import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inkdframes_project.dart';
import 'dart:convert';
import 'workspace_screen.dart';

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
              leading: const Icon(Icons.movie_outlined),
              title: Text(project.name),
              subtitle: Text('${project.frames.length} frames'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WorkspaceScreen(projectId: project.id),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
