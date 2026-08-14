import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProjectLibraryScreen extends StatefulWidget {
  const ProjectLibraryScreen({super.key});

  @override
  State<ProjectLibraryScreen> createState() => _ProjectLibraryScreenState();
}

class _ProjectLibraryScreenState extends State<ProjectLibraryScreen> {
  List<String> _projectIds = [];

  @override
  void initState() {
    super.initState();
    _loadProjectIds();
  }

  Future<void> _loadProjectIds() async {
    final prefs = await SharedPreferences.getInstance();
    final projectIds = prefs.getStringList('project_ids') ?? [];

    if (!mounted) return;

    setState(() {
      _projectIds = projectIds;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Project Library')),
      body: Center(child: Text('Saved projects: ${_projectIds.length}')),
    );
  }
}
