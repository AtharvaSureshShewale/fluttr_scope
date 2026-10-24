import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// `MediaQueryData` properties that have their own `MediaQuery.<x>Of`
/// lookup (all present since Flutter 3.35). `textScaleFactor` is left out:
/// its `Of` is deprecated in favour of `textScalerOf`.
const _propertyLookups = {
  'size': 'sizeOf',
  'orientation': 'orientationOf',
  'devicePixelRatio': 'devicePixelRatioOf',
  'textScaler': 'textScalerOf',
  'platformBrightness': 'platformBrightnessOf',
  'padding': 'paddingOf',
  'viewInsets': 'viewInsetsOf',
  'systemGestureInsets': 'systemGestureInsetsOf',
  'viewPadding': 'viewPaddingOf',
  'alwaysUse24HourFormat': 'alwaysUse24HourFormatOf',
  'accessibleNavigation': 'accessibleNavigationOf',
  'invertColors': 'invertColorsOf',
  'highContrast': 'highContrastOf',
  'onOffSwitchLabels': 'onOffSwitchLabelsOf',
  'disableAnimations': 'disableAnimationsOf',
  'boldText': 'boldTextOf',
  'supportsAnnounce': 'supportsAnnounceOf',
  'navigationMode': 'navigationModeOf',
  'gestureSettings': 'gestureSettingsOf',
};

/// Flags `MediaQuery.of(context).size` (and `.padding`, `.viewInsets`, ...)
/// where `MediaQuery.sizeOf(context)` reads the same value.
///
/// `MediaQuery.of` makes the widget depend on *every* field of
/// `MediaQueryData`, so it rebuilds whenever any of them changes -- on each
/// frame of the keyboard sliding in (`viewInsets`), for example, even if it
/// only reads the screen size. The `<x>Of` lookups depend on that one field
/// only. `MediaQuery.of(context)` kept in a variable and read for several
/// fields isn't flagged: replacing it means one lookup per field.
class MediaQueryOfSinglePropertyRule extends StaticRule {
  @override
  String get id => 'media_query_of_single_property';

  @override
  Category get category => Category.performance;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    if (isTestFile(unit, context)) return const [];
    final findings = <Finding>[];
    unit.unit.accept(_MediaQueryVisitor((node, property, replacement) {
      // The keyboard is the usual culprit, unless the keyboard's insets are
      // the very value being read.
      final example = property == 'viewInsets'
          ? 'when the screen rotates or its safe-area padding changes'
          : 'on every frame of the keyboard sliding in';
      findings.add(Finding(
        ruleId: id,
        category: Category.performance,
        severity: Severity.info,
        message: '`MediaQuery.${node.methodName.name}(context).$property` rebuilds this widget '
            'when anything in MediaQuery changes, e.g. $example. '
            '`MediaQuery.$replacement(context)` reads the same value and rebuilds only '
            'when it changes.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _MediaQueryVisitor extends RecursiveAstVisitor<void> {
  final void Function(MethodInvocation node, String property, String replacement) onMatch;

  _MediaQueryVisitor(this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node);
    super.visitMethodInvocation(node);
  }

  void _check(MethodInvocation node) {
    final method = node.methodName.name;
    if (method != 'of' && method != 'maybeOf') return;
    final target = node.target;
    if (target is! SimpleIdentifier || target.name != 'MediaQuery') return;
    final element = target.element;
    if (element is! ClassElement ||
        !element.library.uri.toString().startsWith('package:flutter/')) {
      return;
    }

    final access = node.parent;
    if (access is! PropertyAccess || access.target != node) return;
    final property = access.propertyName.name;
    var lookup = _propertyLookups[property];
    if (lookup == null) return;

    // `.size.width` / `.size.height` have lookups of their own.
    var shown = property;
    final outer = access.parent;
    if (property == 'size' && outer is PropertyAccess && outer.target == access) {
      final dimension = outer.propertyName.name;
      if (dimension == 'width' || dimension == 'height') {
        lookup = '${dimension}Of';
        shown = 'size.$dimension';
      }
    }

    if (method == 'maybeOf') {
      lookup = 'maybe${lookup[0].toUpperCase()}${lookup.substring(1)}';
    }
    onMatch(node, shown, lookup);
  }
}

/// Flags `setState` called from a listener on an `Animation`
/// (`controller.addListener(() => setState(() {}))`).
///
/// An animation notifies its listeners on every frame while it runs, so
/// this rebuilds the whole widget -- everything its `build` returns -- 60+
/// times a second, when usually only a small part of it moves.
/// `AnimatedBuilder` (or a `*Transition` widget, or a `CustomPainter`
/// with `repaint: controller`) rebuilds or repaints just that part.
///
/// Only flagged when the `setState` isn't behind a condition: a listener
/// that calls it only when some threshold is crossed rebuilds rarely. A
/// bare `if (mounted)` doesn't count as a condition. The listener may be a
/// closure or a method of the same class passed by name.
class SetStateInAnimationListenerRule extends StaticRule {
  @override
  String get id => 'setstate_in_animation_listener';

  @override
  Category get category => Category.performance;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_AnimationListenerVisitor((addListener) {
      findings.add(Finding(
        ruleId: id,
        category: Category.performance,
        severity: Severity.warning,
        message: 'This listener calls `setState` on every frame of the animation, '
            'rebuilding the whole widget 60+ times a second. Wrap only the part that '
            'moves in `AnimatedBuilder` (or a `*Transition` widget), or give a '
            '`CustomPainter` the animation as `repaint:`.',
        location: locationOfToken(unit, addListener.methodName.token, context,
            end: addListener.end),
      ));
    }));
    return findings;
  }
}

class _AnimationListenerVisitor extends RecursiveAstVisitor<void> {
  final void Function(MethodInvocation addListener) onMatch;

  _AnimationListenerVisitor(this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'addListener' &&
        node.argumentList.arguments.length == 1 &&
        isFlutterAnimation(node.realTarget?.staticType)) {
      final body = _listenerBody(node.argumentList.arguments.single);
      if (body != null && _callsSetStateUnconditionally(body)) onMatch(node);
    }
    super.visitMethodInvocation(node);
  }

  /// The body of the listener: a closure's, or that of a method of the
  /// enclosing class passed by name (`addListener(_onTick)`).
  FunctionBody? _listenerBody(Expression listener) {
    if (listener is FunctionExpression) return listener.body;
    if (listener is! SimpleIdentifier) return null;
    final classNode = listener.thisOrAncestorOfType<ClassDeclaration>();
    if (classNode == null) return null;
    for (final member in classMembers(classNode)) {
      if (member is MethodDeclaration && member.name.lexeme == listener.name) {
        return member.body;
      }
    }
    return null;
  }
}

bool _callsSetStateUnconditionally(FunctionBody body) {
  var found = false;
  body.accept(_SetStateFinder((call) {
    if (!_isConditional(call, body)) found = true;
  }));
  return found;
}

class _SetStateFinder extends RecursiveAstVisitor<void> {
  final void Function(MethodInvocation call) onSetState;

  _SetStateFinder(this.onSetState);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'setState' &&
        (node.target == null || node.target is ThisExpression)) {
      onSetState(node);
    }
    super.visitMethodInvocation(node);
  }
}

/// Whether anything between [call] and [root] decides if [call] runs: an
/// `if` (other than a bare `if (mounted)`), `?:`, `&&`/`||`/`??`, a
/// `switch`, a loop, or a nested closure that may never be called.
bool _isConditional(AstNode call, AstNode root) {
  for (var node = call.parent; node != null && node != root; node = node.parent) {
    switch (node) {
      case IfStatement(:final expression) when !_isMountedCheck(expression):
      case ConditionalExpression():
      case SwitchStatement():
      case SwitchExpression():
      case ForStatement():
      case WhileStatement():
      case DoStatement():
      case FunctionExpression():
        return true;
      case BinaryExpression(:final operator)
          when operator.type == TokenType.AMPERSAND_AMPERSAND ||
              operator.type == TokenType.BAR_BAR ||
              operator.type == TokenType.QUESTION_QUESTION:
        return true;
    }
  }
  return false;
}

bool _isMountedCheck(Expression condition) {
  final source = condition.toSource();
  return source == 'mounted' || source == 'this.mounted';
}

/// Flags an `Opacity` whose `opacity:` reads an animation's `.value`
/// (`Opacity(opacity: controller.value, child: ...)`, usually inside an
/// `AnimatedBuilder`).
///
/// That rebuilds the `Opacity` and its child on every frame of the
/// animation. `FadeTransition(opacity: animation, ...)` takes the
/// animation itself and only repaints, with no rebuilds.
class OpacityInAnimationRule extends StaticRule {
  @override
  String get id => 'opacity_in_animation';

  @override
  Category get category => Category.performance;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_OpacityVisitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.performance,
        severity: Severity.info,
        message: '`Opacity` driven by an animation\'s `.value` rebuilds its child on every '
            'frame. `FadeTransition(opacity: animation, ...)` fades it without rebuilding '
            '(use a `Tween` or `ReverseAnimation` for anything other than the raw value).',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _OpacityVisitor extends RecursiveAstVisitor<void> {
  final void Function(InstanceCreationExpression node) onMatch;

  _OpacityVisitor(this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (creationTypeName(node) == 'Opacity' && isFrameworkWidget(node)) {
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression &&
            arg.name.label.name == 'opacity' &&
            _readsAnimationValue(arg.expression)) {
          onMatch(node);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}

bool _readsAnimationValue(Expression expression) {
  var found = false;
  void check(Expression? target, SimpleIdentifier property) {
    if (property.name == 'value' && isFlutterAnimation(target?.staticType)) found = true;
  }

  expression.accept(_ValueAccessVisitor(check));
  return found;
}

class _ValueAccessVisitor extends RecursiveAstVisitor<void> {
  final void Function(Expression? target, SimpleIdentifier property) onAccess;

  _ValueAccessVisitor(this.onAccess);

  @override
  void visitPropertyAccess(PropertyAccess node) {
    onAccess(node.realTarget, node.propertyName);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    onAccess(node.prefix, node.identifier);
    super.visitPrefixedIdentifier(node);
  }
}
