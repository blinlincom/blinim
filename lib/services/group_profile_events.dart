import 'dart:async';

import '../models/im_models.dart';

class GroupProfileEvents {
  static final StreamController<ImGroup> _controller =
      StreamController<ImGroup>.broadcast();

  static Stream<ImGroup> get stream => _controller.stream;

  static void notify(ImGroup group) {
    if (group.id > 0 && !_controller.isClosed) {
      _controller.add(group);
    }
  }
}
