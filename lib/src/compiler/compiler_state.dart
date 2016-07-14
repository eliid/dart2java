import '../java/ast.dart' as java;
import 'package:kernel/ast.dart' as dart;
import 'package:path/path.dart' as path;

import 'compiler.dart' show CompilerOptions;
import 'runner.dart' show CompileErrorException;

class CompilerState {
  /// Maps Dart classes to Java classes which will be reused in generated code.
  ///
  /// E.g., dart.core.int uses java.lang.Integer. This is required to get
  /// the types right in generated Java code.
  /// TODO(springerm): Try to use mapping from dart.DartType here later.
  final javaClasses = new Map<String, String>();

  /// Maps Dart SDK classes and interfaces to their runtime implementations,
  /// i.e., "interceptor classes".
  ///
  /// E.g., dart.core.int is implemented by dart class JavaInteger. This
  /// required to find method implementations.
  /// TODO(springerm): Try to use mapping from dart.DartType here later.
  final interceptorClasses = new Map<String, String>();

  final CompilerOptions options;

  CompilerState(this.options) {
    // Set up primitive types
    registerPrimitiveCoreClass(
        "dart.core::bool", "java.lang.Boolean", "dart.core::bool");
    registerPrimitiveCoreClass(
        "dart.core::int", "java.lang.Integer", "dart._runtime::JavaInteger");
    registerPrimitiveCoreClass(
        "dart.core::double", "java.lang.Double", "dart._runtime::JavaDouble");
    registerPrimitiveCoreClass(
        "dart.core::String", "java.lang.String", "dart._runtime::JavaString");
  }

  void registerPrimitiveCoreClass(
      String dartName, String javaName, String interceptorClass) {
    javaClasses[dartName] = javaName;
    javaClasses[interceptorClass] = javaName;
    interceptorClasses[dartName] = interceptorClass;
    interceptorClasses[interceptorClass] = interceptorClass;
  } 

  /// Check if a certain class is an interceptor class.
  /// 
  /// TODO(springerm): Remove once we got annotations working.
  /// TODO(springerm): This should be the fully qualified class name, but
  /// package naming is not fully implemented yet.
  bool isInterceptorClass(String dartClassName) {
    return interceptorClasses.values.map((interceptor) =>
      interceptor.split("::").last).contains(dartClassName);
  }

  /// Get a Java package name for a Dart Library.
  ///
  /// The package name always has at least one identifier in it (it will never
  /// be the empty string). The package name is essentially just
  /// [options.packagePrefix] plus the relative path from [options.buildRoot]
  /// to the [library] source file (with '/' replaced by '.', of course).
  String getJavaPackageName(dart.Library library) {
    // Omit empty parts, to handle cases like `packagePrefix == "org.example."`
    // or `packagePrefix == ""`.
    List<String> packageParts = options.packagePrefix
        .split('.')
        .where((String part) => part.isNotEmpty)
        .toList();
    Uri uri = library.importUri;

    // Add parts to the package name, depending on the URI scheme.
    switch (library.importUri.scheme) {
      case 'file':
        String libraryPath = uri.toFilePath();

        if (!path.isWithin(options.buildRoot, libraryPath)) {
          throw new CompileErrorException(
              'All sources must be inside build-root.');
        }

        String relativePath =
            path.relative(libraryPath, from: options.buildRoot);
        packageParts.addAll(path.split(path.withoutExtension(relativePath)));
        break;
      case 'dart':
        packageParts.add(uri.path);
        break;
      default:
        throw new CompileErrorException('Unrecognized library URI scheme: '
            '${library.importUri}');
    }

    // TODO(andrewkrieger): Maybe validate the package name?
    return packageParts.join('.');
  }

  static String getClassNameForPackageTopLevel(String package) {
    return package.split('.').last;
  }
}
