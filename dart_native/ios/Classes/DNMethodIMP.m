//
//  DNMethodIMP.m
//  dart_native
//
//  Created by 杨萧玉 on 2019/10/30.
//

#import "DNMethodIMP.h"
#import "DNFFIHelper.h"
#import "DartNativePlugin.h"
#import "native_runtime.h"
#import "DNInvocation.h"
#import "NSThread+DartNative.h"
#import "DNPointerWrapper.h"

static void DNFFIIMPClosureFunc(ffi_cif *cif, void *ret, void **args, void *userdata);

@interface DNMethodIMP ()
{
    ffi_cif _cif;
    ffi_closure *_closure;
    void *_methodIMP;
}

@property (nonatomic) NSUInteger numberOfArguments;
@property (nonatomic) char *typeEncoding;
@property (nonatomic) NSThread *thread;
@property (nonatomic) void *callback;
@property (nonatomic) DNFFIHelper *helper;
@property (nonatomic) NSMethodSignature *signature;
@property (nonatomic, getter=hasStret) BOOL stret;

@end

@implementation DNMethodIMP

- (instancetype)initWithTypeEncoding:(const char *)typeEncoding callback:(void *)callback {
    self = [super init];
    if (self) {
        _helper = [DNFFIHelper new];
        _typeEncoding = malloc(sizeof(char) * strlen(typeEncoding));
        strcpy(_typeEncoding, typeEncoding);
        _callback = callback;
        _thread = NSThread.currentThread;
        _signature = [NSMethodSignature signatureWithObjCTypes:_typeEncoding];
    }
    return self;
}

- (void)dealloc {
    free(_typeEncoding);
    ffi_closure_free(_closure);
}

- (IMP)imp {
    if (!_methodIMP) {
        NSUInteger numberOfArguments = [self _prepCIF:&_cif withEncodeString:self.typeEncoding];
        if (numberOfArguments == -1) { // Unknown encode.
            return nil;
        }
        self.numberOfArguments = numberOfArguments;
        
        _closure = ffi_closure_alloc(sizeof(ffi_closure), (void **)&_methodIMP);
        ffi_status status = ffi_prep_closure_loc(_closure, &_cif, DNFFIIMPClosureFunc, (__bridge void *)(self), _methodIMP);
        if (status != FFI_OK) {
            NSLog(@"ffi_prep_closure returned %d", (int)status);
            abort();
        }
    }
    return _methodIMP;
}

- (int)_prepCIF:(ffi_cif *)cif withEncodeString:(const char *)str {
    int argCount;
    ffi_type **argTypes;
    ffi_type *returnType;
    
    // TODO: handle struct return on x86
    argTypes = [self.helper argsWithEncodeString:str getCount:&argCount];
    if (!argTypes) { // Error!
        return -1;
    }
    returnType = [self.helper ffiTypeForEncode:str];
    
    if (!returnType) { // Error!
        return -1;
    }
    ffi_status status = ffi_prep_cif(cif, FFI_DEFAULT_ABI, argCount, returnType, argTypes);
    if (status != FFI_OK) {
        NSLog(@"Got result %ld from ffi_prep_cif", (long)status);
        abort();
    }
    return argCount;
}

@end


static void DNHandleReturnValue(void *ret, void **args, DNMethodIMP *methodIMP, DNInvocation *invocation) {
    if (methodIMP.hasStret) {
        // synchronize stret value from first argument.
        [invocation setReturnValue:*(void **)args[0]];
    } else if (methodIMP.typeEncoding[0] == '{') {
        DNPointerWrapper *pointerWrapper = *(DNPointerWrapper *__strong *)ret;
        memcpy(ret, pointerWrapper.pointer, invocation.methodSignature.methodReturnLength);
    } else if (methodIMP.typeEncoding[0] == '*') {
        DNPointerWrapper *pointerWrapper = *(DNPointerWrapper *__strong *)ret;
        const char *origCString = (const char *)pointerWrapper.pointer;
        const char *temp = [NSString stringWithUTF8String:origCString].UTF8String;
        *(const char **)ret = temp;
    }
}

static void DNFFIIMPClosureFunc(ffi_cif *cif, void *ret, void **args, void *userdata) {
    DNMethodIMP *methodIMP = (__bridge DNMethodIMP *)userdata;
    FlutterMethodChannel *channel = DartNativePlugin.channel;
    
    void *userRet = ret;
    void **userArgs = args;
    // handle struct return: should pass pointer to struct
    if (methodIMP.hasStret) {
        // The first arg contains address of a pointer of returned struct.
        userRet = *((void **)args[0]);
        // Other args move backwards.
        userArgs = args + 1;
    }
    *(void **)userRet = NULL;
    __block int64_t retObjectAddr = 0;
    // Use (numberOfArguments - 2) exclude itself and _cmd.
    int numberOfArguments = (int)methodIMP.numberOfArguments - 2;
    
    NSUInteger indexOffset = methodIMP.hasStret ? 1 : 0;
    for (NSUInteger i = 0; i < methodIMP.signature.numberOfArguments; i++) {
        const char *type = [methodIMP.signature getArgumentTypeAtIndex:i];
        if (type[0] == '{') {
            NSUInteger size;
            DNSizeAndAlignment(type, &size, NULL, NULL);
            void *temp = malloc(size);
            memcpy(temp, args[i + indexOffset], size);
            args[i + indexOffset] = temp;
        }
    }
    
    const char **types = native_types_encoding(methodIMP.typeEncoding, NULL, 0);
    
    __block DNInvocation *invocation = [[DNInvocation alloc] initWithSignature:methodIMP.signature
                                                                      hasStret:methodIMP.hasStret];
    invocation.args = userArgs;
    invocation.retValue = userRet;
    invocation.realArgs = args;
    invocation.realRetValue = ret;
    
    int64_t retAddr = (int64_t)(invocation.realRetValue);
    
    if (methodIMP.thread == NSThread.currentThread && methodIMP.callback) {
        void(*callback)(void **args, void *ret, int numberOfArguments, const char **types, BOOL stret) = methodIMP.callback;
        // args: target, selector, realArgs...
        callback(args, ret, numberOfArguments, types, methodIMP.hasStret);
        free(types);
        retObjectAddr = (int64_t)*(void **)retAddr;
        DNHandleReturnValue(ret, args, methodIMP, invocation);
    } else {
        
        int64_t argsAddr = (int64_t)(invocation.realArgs);
        int64_t typesAddr = (int64_t)types;
        
        [invocation retainArguments];
        
        BOOL voidRet = strcmp(types[0], "void") == 0;
        
        dispatch_semaphore_t sema;
        if (!NSThread.isMainThread && !voidRet) {
            sema = dispatch_semaphore_create(0);
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [channel invokeMethod:@"method_callback"
                        arguments:@[@(argsAddr),
                                    @(retAddr),
                                    @(numberOfArguments),
                                    @(typesAddr),
                                    @(methodIMP.hasStret)]
                           result:^(id  _Nullable result) {
                retObjectAddr = (int64_t)*(void **)retAddr;
                DNHandleReturnValue(ret, args, methodIMP, invocation);
                invocation = nil;
                if (sema) {
                    dispatch_semaphore_signal(sema);
                }
                free(types);
            }];
        });
        if (sema) {
            dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        }
    }
    [methodIMP.thread dn_performBlock:^{
        NSThread.currentThread.threadDictionary[@(retObjectAddr)] = nil;
    }];
}

