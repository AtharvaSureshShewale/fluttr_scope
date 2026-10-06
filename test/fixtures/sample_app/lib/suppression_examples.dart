// ignore_for_file: fluttr_scope/todo_comment

void suppressionExamples() {
  // ignore: fluttr_scope/avoid_print
  print('suppressed by a standalone ignore on the line above');
  print('suppressed by a trailing ignore'); // ignore: fluttr_scope/avoid_print
  // TODO: suppressed file-wide by ignore_for_file
  // ignore: avoid_print
  print('NOT suppressed: a bare Dart lint name is not a fluttr_scope id');
}
