import 'dart:convert';

typedef Json = Map<String, Object?>;

/// Gap between neighbouring `position` values, so an item can be inserted
/// between two others without renumbering.
const positionStep = 1024;

Json decodeJson(Object? text) =>
    (jsonDecode(text as String) as Map).cast<String, Object?>();
