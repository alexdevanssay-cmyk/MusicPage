// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member
// ignore_for_file: invalid_use_of_visible_for_testing_member
// ignore_for_file: deprecated_member_use_from_same_package

part of 'router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// Hash of the source of `router`.
// If the source changes, re-run `dart run build_runner build` to regenerate.
String _$routerHash() => r'e4f7c3a2b1d09e8f5a6c7b3d2e1f0a9b8c7d6e5f';

/// GoRouter instance for the whole application.
/// keepAlive: true — lives for the entire app lifetime.
///
/// See also [router].
@ProviderFor(router)
final routerProvider = Provider<GoRouter>.internal(
  router,
  name: r'routerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$routerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

/// Ref type passed to the [router] function.
typedef RouterRef = ProviderRef<GoRouter>;
