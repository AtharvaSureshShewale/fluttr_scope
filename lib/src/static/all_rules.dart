import 'rule.dart';
import 'rules/accessibility_rules.dart';
import 'rules/async_widget_rules.dart';
import 'rules/avoid_logging_sensitive_data.dart';
import 'rules/avoid_print.dart';
import 'rules/build_misuse_rules.dart';
import 'rules/container_color_and_decoration_conflict.dart';
import 'rules/deeply_nested_widget_tree.dart';
import 'rules/dispose_missing.dart';
import 'rules/hardcoded_secret.dart';
import 'rules/hierarchy_rules.dart';
import 'rules/image_network_without_error_builder.dart';
import 'rules/insecure_certificate_validation.dart';
import 'rules/insecure_storage_of_sensitive_data.dart';
import 'rules/missing_const_constructor.dart';
import 'rules/missing_list_key.dart';
import 'rules/missing_mounted_check.dart';
import 'rules/nested_scaffold.dart';
import 'rules/numeric_constraint_rules.dart';
import 'rules/scaffold_missing_body.dart';
import 'rules/security_context_rules.dart';
import 'rules/security_regex_rules.dart';
import 'rules/setstate_in_build.dart';
import 'rules/setstate_in_list_builder.dart';
import 'rules/shrinkwrap_listview.dart';
import 'rules/simplification_rules.dart';
import 'rules/sql_injection_risk.dart';
import 'rules/sql_table_missing_constraints.dart';
import 'rules/todo_comment.dart';
import 'rules/unbounded_scrollable_in_flex.dart';
import 'rules/weak_hash_algorithm.dart';

/// Every static rule the engine ships, in one place so the CLI and tests
/// don't each maintain their own copy of the list.
List<StaticRule> allRules() => [
      MissingConstConstructorRule(),
      AvoidPrintRule(),
      DisposeMissingRule(),
      SetStateInBuildRule(),
      MissingMountedCheckRule(),
      ShrinkwrapListviewRule(),
      UnboundedScrollableInFlexRule(),
      NestedScaffoldRule(),
      HardcodedSecretRule(),
      ExpandedOutsideFlexRule(),
      PositionedOutsideStackRule(),
      KeyCreatedInBuildRule(),
      InheritedWidgetOfInInitStateRule(),
      BuildContextStoredInFieldRule(),
      InsecureHttpUrlRule(),
      SensitiveQueryParamRule(),
      HardcodedIpAddressRule(),
      InsecureRandomForSecretRule(),
      UnrestrictedWebviewJavascriptRule(),
      TextfieldPasswordNotObscuredRule(),
      MissingTooltipForIconButtonRule(),
      ImageMissingSemanticLabelRule(),
      FutureBuilderMissingErrorCheckRule(),
      StreamBuilderMissingErrorCheckRule(),
      FutureCreatedInBuildRule(),
      MissingListKeyRule(),
      ImageNetworkWithoutErrorBuilderRule(),
      EmptyContainerInsteadOfSizedboxRule(),
      UnnecessaryColumnOrRowRule(),
      EmptyFlexChildrenRule(),
      WidgetReturningMethodRule(),
      SliderInvalidRangeRule(),
      OpacityOutOfRangeRule(),
      InvalidAspectRatioRule(),
      FlexValueNonPositiveRule(),
      BottomNavigationBarTooFewItemsRule(),
      ContainerColorAndDecorationConflictRule(),
      ScaffoldMissingBodyRule(),
      DeeplyNestedWidgetTreeRule(),
      TodoCommentRule(),
      AvoidLoggingSensitiveDataRule(),
      SqlInjectionRiskRule(),
      InsecureStorageOfSensitiveDataRule(),
      WeakHashAlgorithmRule(),
      SqlTableMissingConstraintsRule(),
      InsecureCertificateValidationRule(),
      SetstateInListBuilderRule(),
    ];
