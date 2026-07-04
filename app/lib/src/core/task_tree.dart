import 'package:todori/src/rust/api.dart';

class TaskTreeNode {
  const TaskTreeNode({
    required this.task,
    required this.depth,
    required this.children,
  });

  final TaskDto task;
  final int depth;
  final List<TaskTreeNode> children;
}

class SubtaskStats {
  const SubtaskStats({required this.doneCount, required this.totalCount});

  final int doneCount;
  final int totalCount;

  bool get hasDescendants => totalCount > 0;
}

List<TaskTreeNode> buildTaskTree(List<TaskDto> tasks) {
  final sorted = [...tasks]..sort(_compareTasks);
  final byId = {for (final task in sorted) task.id: task};
  final childrenByParent = _childrenByParent(sorted);
  final emitted = <String>{};

  TaskTreeNode? buildNode(TaskDto task, int depth, Set<String> path) {
    if (emitted.contains(task.id) || path.contains(task.id)) {
      return null;
    }

    emitted.add(task.id);
    final nextPath = {...path, task.id};
    final children = <TaskTreeNode>[];
    for (final child in childrenByParent[task.id] ?? const <TaskDto>[]) {
      final childNode = buildNode(child, depth + 1, nextPath);
      if (childNode != null) {
        children.add(childNode);
      }
    }

    return TaskTreeNode(task: task, depth: depth, children: children);
  }

  final roots = <TaskTreeNode>[];
  for (final task in sorted) {
    final parentId = task.parentTaskId;
    if (parentId == null || !byId.containsKey(parentId)) {
      final node = buildNode(task, 0, <String>{});
      if (node != null) {
        roots.add(node);
      }
    }
  }

  for (final task in sorted) {
    final node = buildNode(task, 0, <String>{});
    if (node != null) {
      roots.add(node);
    }
  }

  return roots;
}

List<TaskTreeNode> flattenTaskTree(List<TaskTreeNode> roots) {
  final flattened = <TaskTreeNode>[];

  void visit(TaskTreeNode node) {
    flattened.add(node);
    for (final child in node.children) {
      visit(child);
    }
  }

  for (final root in roots) {
    visit(root);
  }

  return flattened;
}

List<TaskDto> directSubtasksOf(String taskId, List<TaskDto> tasks) {
  final children = tasks.where((task) => task.parentTaskId == taskId).toList();
  children.sort(_compareTasks);
  return children;
}

SubtaskStats descendantStatsOf(String taskId, List<TaskDto> tasks) {
  final childrenByParent = _childrenByParent(tasks);
  final visited = <String>{taskId};
  var doneCount = 0;
  var totalCount = 0;

  void visitChildren(String parentId) {
    for (final child in childrenByParent[parentId] ?? const <TaskDto>[]) {
      if (!visited.add(child.id)) {
        continue;
      }
      totalCount += 1;
      if (child.status == 'done') {
        doneCount += 1;
      }
      visitChildren(child.id);
    }
  }

  visitChildren(taskId);
  return SubtaskStats(doneCount: doneCount, totalCount: totalCount);
}

bool hasIncompleteDescendants(String taskId, List<TaskDto> tasks) {
  final childrenByParent = _childrenByParent(tasks);
  final visited = <String>{taskId};

  bool visitChildren(String parentId) {
    for (final child in childrenByParent[parentId] ?? const <TaskDto>[]) {
      if (!visited.add(child.id)) {
        continue;
      }
      if (child.status != 'done' || visitChildren(child.id)) {
        return true;
      }
    }
    return false;
  }

  return visitChildren(taskId);
}

Map<String, List<TaskDto>> _childrenByParent(List<TaskDto> tasks) {
  final childrenByParent = <String, List<TaskDto>>{};
  for (final task in tasks) {
    final parentId = task.parentTaskId;
    if (parentId == null) {
      continue;
    }
    childrenByParent.putIfAbsent(parentId, () => <TaskDto>[]).add(task);
  }
  for (final children in childrenByParent.values) {
    children.sort(_compareTasks);
  }
  return childrenByParent;
}

int _compareTasks(TaskDto a, TaskDto b) {
  final sortOrder = a.sortOrder.compareTo(b.sortOrder);
  if (sortOrder != 0) {
    return sortOrder;
  }
  return a.id.compareTo(b.id);
}
