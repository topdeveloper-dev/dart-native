# dart_objc

Write Objective-C Code using Dart.

Still under development!!! 

## Getting Started

Dart code:

```
// new Objective-C object.
RuntimeStub stub = RuntimeStub();

// Define Dart function according to Objective-C BarBlock signature.
Function testFunc = (NSObject a) {
    print('hello block! ${a.toString()}');
    return 101;
};

// Dart function will be converted to Objective-C block.
Block block = stub.fooBlock(testFunc);
// invoke Objective-C block.
int result = block.invoke([stub]);
print(result); 

// support built-in structs.
CGRect rect = stub.fooCGRect(CGRect.allocate(4, 3, 2, 1));
print(rect);

```

Objective-C code:

```
@interface RuntimeStub ()
@end
@implementation RuntimeStub
- (CGRect)fooCGRect:(CGRect)rect
{
    NSLog(@"%s %f, %f, %f, %f", __func__, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    return (CGRect){1, 2, 3, 4};
}

typedef int(^BarBlock)(NSObject *a);

- (BarBlock)fooBlock:(BarBlock)block
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        int result = block([NSObject new]);
        NSLog(@"---result: %d", result);
    });
    BarBlock bar = ^(NSObject *a) {
        NSLog(@"bar block arg: %@", a);
        return 404;
    };
    return bar;
}
@end
```

## TODO List

- [x] Type support:Block
- [x] Type support:Struct
- [ ] delegate Callback
- [ ] Memory Management
- [ ] Generate Dart code from ObjectiveC/C++ Headers.

