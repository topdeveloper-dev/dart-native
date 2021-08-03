# Dart_Native

Dart_Native operates as both a code generator tool and a bridge to communicate between Dart and native APIs.

Replaces the low-performing Flutter channel with faster and more concise code.

* Under development

[![pub package](https://img.shields.io/pub/v/dart_native.svg)](https://pub.dev/packages/dart_native)
[![Build Status](https://travis-ci.org/dart-native/dart_native.svg?branch=master)](https://travis-ci.org/dart-native/dart_native)

This package is the blue part(DartNative Bridge):

![](images/dartnative.png)

## Requirements

| Dart_Native Version | Requirements |
| --- | --- |
| 0.3.0 | Flutter 1.20.0 (Dart 2.9.1) |
| 0.2.0 | Flutter 1.12.13 (Dart 2.7) |

## Supported Platforms

iOS & Android

## Usage

1. Add ```dart_native``` to dependencies and ```source_gen``` to dev_dependencies.

2. Generate Dart wrapper code with [@dartnative/codegen](https://www.npmjs.com/package/@dartnative/codegen) or write Dart code manually.

3. Generate code for automatic type conversion using [dart_native_gen](https://pub.dev/packages/dart_native_gen) with the following steps (3.1-3.3):

   3.1 Annotate a Dart wrapper class with `@native`.
    ```dart
    @native
    class RuntimeSon extends RuntimeStub {
      RuntimeSon([Class isa]) : super(Class('RuntimeSon'));
      RuntimeSon.fromPointer(Pointer<Void> ptr) : super.fromPointer(ptr);
    }
    ```
  
   3.2 Annotate your own entry (such as`main()`) with `@nativeRoot`.

    ```dart
    @nativeRoot
    void main() {
      runApp(App());
    }
    ```

    3.3 Run  
    ```bash 
    flutter packages pub run build_runner build --delete-conflicting-outputs 
    ```
    to generate files into your source directory.

    Note: we recommend running `clean` first:

    ```bash
    flutter packages pub run build_runner clean
    ```

4. Call autogenerated function in `<generated-name>.dn.dart` in 3.3. The function name is determined by `name` in `pubspec.yaml`.

    ```dart
    @nativeRoot
    void main() {
      // Function name is generated by name in pubspec.yaml.
      runDartNativeExample(); 
      runApp(App());
    }
    ```

## Features

### High-performance synchronous & asynchronous channeling

Dart_Native costs significantly less time than the Flutter channel and supports both synchronous and asynchronous channeling. A comparison of two native channeling tasks using Flutter channel and Dart_Native is shown below. 

Both tasks were executed 10,000 times in the same environment using either Flutter channel or Dart_Native:

| Task | Total time cost (ms) (Channel/Dart_Native) | Channeling time cost (ms) (Channel/Dart_Native) |
| --- | --- | --- |
| Checking if an app needs to be installed | 5202/4166 | 919/99  |
| Logging | 2480/2024 | 1075/432 |


### Autogenerate succinct bridging code

Dart_Native supports automatic type conversion so its bridging code is shorter & simpler than the Flutter channel.

A comparison of the task of "checking if an app needs to be installed" is shown below:

| | # of lines of bridging code | Coding complexity |
| --- | --- | --- |
| Dart_Native | Dart 1 + Native 1 | Autogenerated code returns BOOL directly |
| Channel | Dart 15 + Native 30 | Needs to manually define return format, convert INT to BOOL, determine channel & methodName |

### Automatic object marshalling between Dart and native

## Examples
##### iOS:

Dart code (generated):

```dart
// new Objective-C object.
RuntimeStub stub = RuntimeStub();

// Dart function will be converted to Objective-C block.
stub.fooBlock((NSObject a) {
    print('hello block! ${a.toString()}');
    return 101;
});

// support built-in structs.
CGRect rect = stub.fooCGRect(CGRect(4, 3, 2, 1));
print(rect);

```
Corresponding Objective-C code:

```objc
typedef int(^BarBlock)(NSObject *a);

@interface RuntimeStub

- (CGRect)fooCGRect:(CGRect)rect;
- (void)fooBlock:(BarBlock)block;

@end
```

More iOS examples see: [ios_unit_test.dart](/dart_native/example/lib/ios/unit_test.dart)

##### Android:

Dart code (generated):
```dart
// new Java object.
RuntimeStub stub = RuntimeStub();

// get java list.
List list = stub.getList([1, 2, 3, 4]);

// support interface.
stub.setDelegateListener(DelegateStub());

```
Corresponding Java code:

```java
public class RuntimeStub {

    public List<Integer> getList(List<Integer> list) {
        List<Integer> returnList = new ArrayList<>();
        returnList.add(1);
        returnList.add(2);
        return returnList;
     }

    public void setDelegateListener(SampleDelegate delegate) {
         delegate.callbackInt(1);
    }
}
```
More android examples see: [android_unit_test.dart](/dart_native/example/lib/android/unit_test.dart)
## Documentation

### Readme

1. [dart_native README.md](/dart_native/README.md)
2. [dart_native_gen README.md](/dart_native_gen/README.md)

### Further reading

- [告别 Flutter Channel，调用 Native API 仅需一行代码！](http://yulingtianxia.com/blog/2020/06/25/Codegen-for-DartNative/)
- [如何实现一行命令自动生成 Flutter 插件](http://yulingtianxia.com/blog/2020/07/25/How-to-Implement-Codegen/)
- [用 Dart 来写 Objective-C 代码](http://yulingtianxia.com/blog/2019/10/27/Write-Objective-C-Code-using-Dart/)
- [谈谈 dart_native 混合编程引擎的设计](http://yulingtianxia.com/blog/2019/11/28/DartObjC-Design/)
- [DartNative Memory Management: Object](http://yulingtianxia.com/blog/2019/12/26/DartObjC-Memory-Management-Object/)
- [DartNative Memory Management: C++ Non-Object](http://yulingtianxia.com/blog/2020/01/31/DartNative-Memory-Management-Cpp-Non-Object/)
- [DartNative Struct](http://yulingtianxia.com/blog/2020/02/24/DartNative-Struct/)
- [在 Flutter 中玩转 Objective-C Block](http://yulingtianxia.com/blog/2020/03/28/Using-Objective-C-Block-in-Flutter/)
- [Passing Out Parameter in DartNative](http://yulingtianxia.com/blog/2020/04/25/Passing-Out-Parameter-in-DartNative/)

## FAQs

Q: Failed to lookup symbol (dlsym(RTLD_DEFAULT, InitDartApiDL): symbol not found) on iOS archive.

A: Select one solution:
   1. Use dynamic library: Add `use_frameworks!` in Podfile.
   2. Select Target Runner -> Build Settings -> Strip Style -> change from "All Symbols" to "Non-Global Symbols"

## Contribution

- If you **need help** or you'd like to **ask a general question**, open an issue.
- If you **found a bug**, open an issue.
- If you **have a feature request**, open an issue.
- If you **want to contribute**, submit a pull request.

## License

DartNative is available under the BSD 3-Clause License. See the LICENSE file for more info.
