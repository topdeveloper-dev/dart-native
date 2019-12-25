import 'package:dart_objc/dart_objc.dart';

abstract class SampleDelegate {
  callback();
}

class DelegateStub extends NSObject implements SampleDelegate {
  DelegateStub() : super(Class('DelegateStub', type(of: NSObject))) {
    registerProtocolCallback(callback, 'callback', 'StubDelegate');
  }

  callback() {
    print('callback succeed!');
    return NSObject();
  }

  handleNotification(NSObject notification) {
    print('receive notification!');
  }
}
