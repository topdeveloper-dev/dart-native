# dart_native_gen

Annotation for dart_native.

## Description

Automatic type conversion solution for dart_native based on source_gen through annotation.

## Getting Started

1. Add `build_runner` package to `dev_dependencies` in your `pubspec.yaml`.

```yaml
dev_dependencies:
  # Add this line
  build_runner:
```

2. Annotate a Dart wrapper class with `@native`. If this wrapper is generated by [@dartnative/codegen](https://www.npmjs.com/package/@dartnative/codegen), skip to next.

```dart
@native
class RuntimeSon extends RuntimeStub {
  RuntimeSon([Class isa]) : super(Class('RuntimeSon'));
  RuntimeSon.fromPointer(Pointer<Void> ptr) : super.fromPointer(ptr);
}
```

3. Annotate your own entry(such as`main()`) with `@nativeRoot`:

```dart
@nativeRoot
void main() {
  runApp(App());
}
```

4. Run this command to generate files into your source directory:

```bash
flutter packages pub run build_runner build --delete-conflicting-outputs
```

Suggest you running the clean command before build:

```bash
flutter packages pub run build_runner clean
```

5. Call function generated in `xxx.dn.dart`:

```dart
@nativeRoot
void main() {
  // Function name is generated by name in pubspec.yaml.
  runDartNativeExample(); 
  runApp(App());
}
```

## Installation

Add packages to `dependencies` in your `pubspec.yaml`
example:

```yaml
dependencies:
  dart_native_gen: any
```