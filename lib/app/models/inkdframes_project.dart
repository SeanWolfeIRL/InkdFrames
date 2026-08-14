import 'vector_stroke.dart';

class InkdFramesProject {
  InkdFramesProject({
    required this.id,
    required this.name,
    required this.fps,
    required this.frames,
  });

  factory InkdFramesProject.fromJson(Map<String, dynamic> json) {
    return InkdFramesProject(
      id: json['id'] as String,
      name: json['name'] as String,
      fps: (json['fps'] as num).toDouble(),
      frames: (json['frames'] as List)
          .map(
            (frame) => (frame as List)
                .map(
                  (stroke) => VectorStroke.fromJson(
                    Map<String, dynamic>.from(stroke as Map),
                  ),
                )
                .toList(),
          )
          .toList(),
    );
  }

  final String id;
  final String name;
  final double fps;
  final List<List<VectorStroke>> frames;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'fps': fps,
      'frames': frames
          .map((frame) => frame.map((stroke) => stroke.toJson()).toList())
          .toList(),
    };
  }
}
