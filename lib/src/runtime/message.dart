import 'dart:ffi';

import 'package:dart_objc/src/common/library.dart';
import 'package:dart_objc/src/common/native_type_encoding.dart';
import 'package:dart_objc/src/runtime/id.dart';
import 'package:dart_objc/src/runtime/selector.dart';
import 'package:ffi/ffi.dart';

// C header typedef:
typedef MethodSignatureC = Pointer<Void> Function(Pointer<Void> instance,
    Pointer<Void> selector, Pointer<Pointer<Utf8>> typeEncodings);
typedef InvokeMethodC = Pointer<Void> Function(
    Pointer<Void> instance,
    Pointer<Void> selector,
    Pointer<Void> signature,
    Pointer<Pointer<Void>> args);
typedef InvokeMethodNoArgsC = Pointer<Void> Function(
    Pointer<Void> instance, Pointer<Void> selector, Pointer<Void> signature);
typedef TypeEncodingC = Pointer<Utf8> Function(Pointer<Utf8>);

// Dart header typedef
typedef MethodSignatureDart = Pointer<Void> Function(Pointer<Void> instance,
    Pointer<Void> selector, Pointer<Pointer<Utf8>> typeEncodings);
typedef InvokeMethodDart = Pointer<Void> Function(
    Pointer<Void> instance,
    Pointer<Void> selector,
    Pointer<Void> signature,
    Pointer<Pointer<Void>> args);
typedef InvokeMethodNoArgsDart = Pointer<Void> Function(
    Pointer<Void> instance, Pointer<Void> selector, Pointer<Void> signature);
typedef TypeEncodingDart = Pointer<Utf8> Function(Pointer<Utf8>);

Pointer<Void> _msgSend(
    Pointer<Void> target, Pointer<Void> selector, Pointer<Void> signature,
    [Pointer<Pointer<Void>> args]) {
  Pointer<Void> result;
  if (args != null) {
    final InvokeMethodDart nativeInvokeMethod =
        nativeRuntimeLib.lookupFunction<InvokeMethodC, InvokeMethodDart>(
            'native_instance_invoke');
    result = nativeInvokeMethod(target, selector, signature, args);
  } else {
    final InvokeMethodNoArgsDart nativeInvokeMethodNoArgs = nativeRuntimeLib
        .lookupFunction<InvokeMethodNoArgsC, InvokeMethodNoArgsDart>(
            'native_instance_invoke');
    result = nativeInvokeMethodNoArgs(target, selector, signature);
  }
  return result;
}

dynamic msgSend(id target, Selector selector, [List args]) {

  Pointer<Pointer<Utf8>> typeEncodingsPtrPtr =
      Pointer<Pointer<Utf8>>.allocate(count: args?.length ?? 0 + 1);
  Pointer<Void> selectorPtr = selector.toPointer();

  final MethodSignatureDart nativeMethodSignature =
      nativeRuntimeLib.lookupFunction<MethodSignatureC, MethodSignatureDart>(
          'native_method_signature');
  Pointer<Void> signature =
      nativeMethodSignature(target.pointer, selectorPtr, typeEncodingsPtrPtr);
  if (signature.address == 0) {
    throw 'signature for [$target $selector] is NULL.';
  }
  final TypeEncodingDart nativeTypeEncoding = nativeRuntimeLib
      .lookupFunction<TypeEncodingC, TypeEncodingDart>('native_type_encoding');

  Pointer<Pointer<Void>> pointers;
  if (args != null) {
    pointers = Pointer<Pointer<Void>>.allocate(count: args.length);
    for (var i = 0; i < args.length; i++) {
      var arg = args[i];
      if (arg == null) {
        // TODO: throw error.
        continue;
      }
      String typeEncodings =
          nativeTypeEncoding(typeEncodingsPtrPtr.elementAt(i + 1).load()).load().toString();
      storeValueToPointer(arg, pointers.elementAt(i), typeEncodings);
    }
  }
  Pointer<Void> resultPtr =
      _msgSend(target.pointer, selectorPtr, signature, pointers);

  String typeEncodings =
      nativeTypeEncoding(typeEncodingsPtrPtr.load()).load().toString();
  typeEncodingsPtrPtr.free();
  dynamic result = loadValueFromPointer(resultPtr, typeEncodings);
  if (pointers != null) {
    pointers.free();
  }
  return result;
}
