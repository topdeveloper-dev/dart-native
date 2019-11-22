#import "native_runtime.h"
#include <stdlib.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import "DOBlockWrapper.h"
#import "DOFFIHelper.h"
#import "DOMethodIMP.h"
#import "DOObjectDealloc.h"

static NSTimeInterval duration1 = 0;
static NSTimeInterval duration2 = 0;

NSMethodSignature *
native_method_signature(Class cls, SEL selector) {
    NSDate *now = [NSDate date];
    if (!selector) {
        return nil;
    }
    NSMethodSignature *signature = [cls instanceMethodSignatureForSelector:selector];
    duration1 += -[now timeIntervalSinceNow];
    return signature;
}

void
native_signature_encoding_list(NSMethodSignature *signature, const char **typeEncodings) {
    if (!signature || !typeEncodings) {
        return;
    }
    
    NSDate *now = [NSDate date];
    for (NSUInteger i = 2; i < signature.numberOfArguments; i++) {
        *(typeEncodings + i - 1) = [signature getArgumentTypeAtIndex:i];
    }
    *typeEncodings = signature.methodReturnType;
    duration2 += -[now timeIntervalSinceNow];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"-----------d1:%f, d2:%f", duration1 * 1000, duration2 * 1000);
        });
    });
}

BOOL
native_add_method(id target, SEL selector, Protocol *proto, void *callback) {
    Class cls = object_getClass(target);
    NSString *selName = [NSString stringWithFormat:@"dart_objc_%@", NSStringFromSelector(selector)];
    SEL key = NSSelectorFromString(selName);
    DOMethodIMP *imp = objc_getAssociatedObject(cls, key);
    // Existing implemention can't be replaced. Flutter hot-reload must also be well handled.
    if (!imp && [target respondsToSelector:selector]) {
        return NO;
    }
    struct objc_method_description description = protocol_getMethodDescription(proto, selector, YES, YES);
    if (description.types == NULL) {
        description = protocol_getMethodDescription(proto, selector, NO, YES);
    }
    if (description.types != NULL) {
        DOMethodIMP *methodIMP = [[DOMethodIMP alloc] initWithTypeEncoding:description.types callback:callback]; // DOMethodIMP always exists.
        class_replaceMethod(cls, selector, [methodIMP imp], description.types);
        objc_setAssociatedObject(cls, key, methodIMP, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    return NO;
}

Class
native_get_class(const char *className, Class baseClass) {
    Class result = objc_getClass(className);
    if (result) {
        return result;
    }
    if (!baseClass) {
        baseClass = NSObject.class;
    }
    result = objc_allocateClassPair(baseClass, className, 0);
    objc_registerClassPair(result);
    return result;
}

void *
native_instance_invoke(id object, SEL selector, NSMethodSignature *signature, dispatch_queue_t queue, void **args) {
    if (!object || !selector || !signature) {
        return NULL;
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = object;
    invocation.selector = selector;
    for (NSUInteger i = 2; i < signature.numberOfArguments; i++) {
        const char *argType = [signature getArgumentTypeAtIndex:i];
        if (argType[0] == '*') {
            // Copy CString to NSTaggedPointerString and transfer it's lifecycle to ARC. Orginal pointer will be freed after function returning.
            const char *temp = [NSString stringWithUTF8String:(const char *)args[i - 2]].UTF8String;
            if (temp) {
                args[i - 2] = (void *)temp;
            }
        }
        if (argType[0] == '{') {
            [invocation setArgument:args[i - 2] atIndex:i];
        }
        else {
            [invocation setArgument:&args[i - 2] atIndex:i];
        }
    }
    if (queue != NULL) {
        if (strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), dispatch_queue_get_label(queue)) == 0) {
            [invocation invoke];
        } else {
            dispatch_sync(queue, ^{
                [invocation invoke];
            });
        }
    }
    else {
        [invocation invoke];
    }
    void *result = NULL;
    if (signature.methodReturnLength > 0) {
        [invocation getReturnValue:&result];
        const char returnType = signature.methodReturnType[0];
        if (result && returnType == '@') {
            NSString *selString = NSStringFromSelector(selector);
            if (!([selString hasPrefix:@"new"] ||
                [selString hasPrefix:@"alloc"] ||
                [selString hasPrefix:@"copy"] ||
                [selString hasPrefix:@"mutableCopy"])) {
                [DOObjectDealloc attachHost:(__bridge id)result];
            }
        }
        else if (returnType == '{') {
            const char *temp = signature.methodReturnType;
            int index = 0;
            while (temp && *temp && *temp != '=') {
                temp++;
                index++;
            }
            NSString *structTypeEncoding = [NSString stringWithUTF8String:signature.methodReturnType];
            NSString *structName = [structTypeEncoding substringWithRange:NSMakeRange(1, index - 1)];
            #define HandleStruct(struct) \
            if ([structName isEqualToString:@#struct]) { \
                void *structAddr = malloc(sizeof(struct)); \
                memcpy(structAddr, &result, sizeof(struct)); \
                return structAddr; \
            }
            HandleStruct(CGSize)
            HandleStruct(CGPoint)
            HandleStruct(CGVector)
            HandleStruct(CGRect)
            HandleStruct(_NSRange)
            HandleStruct(UIOffset);
            HandleStruct(UIEdgeInsets);
            if (@available(iOS 11.0, *)) {
                HandleStruct(NSDirectionalEdgeInsets);
            }
            HandleStruct(CGAffineTransform);
            NSCAssert(NO, @"Can't handle struct type:%@", structName);
        }
    }
    return result;
}

void *
native_instance_invoke_noArgs(id object, SEL selector, NSMethodSignature *signature, dispatch_queue_t queue) {
    return native_instance_invoke(object, selector, signature, queue, nil);
}

void *
native_instance_invoke_noQueue(id object, SEL selector, NSMethodSignature *signature, void **args) {
    return native_instance_invoke(object, selector, signature, nil, args);
}

void *
native_instance_invoke_noArgsNorQueue(id object, SEL selector, NSMethodSignature *signature) {
    return native_instance_invoke(object, selector, signature, nil, nil);
}

void *
native_block_create(char *types, void *callback) {
    DOBlockWrapper *wrapper = [[DOBlockWrapper alloc] initWithTypeString:types callback:callback];
    return (__bridge void *)wrapper;
}

void *
native_block_invoke(void *block, void **args) {
    const char *typeString = DOBlockTypeEncodeString((__bridge id)block);
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:typeString];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    for (NSUInteger idx = 1; idx < signature.numberOfArguments; idx++) {
        [invocation setArgument:&args[idx - 1] atIndex:idx];
    }
    [invocation invokeWithTarget:(__bridge id)block];
    void *result = NULL;
    if (signature.methodReturnLength > 0) {
        [invocation getReturnValue:&result];
        if (result && signature.methodReturnType[0] == '@') {
            [DOObjectDealloc attachHost:(__bridge id)result];
        }
    }
    return result;
}

const char *
native_type_encoding(const char *str) {
    if (!str) {
        return NULL;
    }
    // Use pointer as key of encoding string cache (on dart side).
    static const char *typeList[20] = {"sint8", "sint16", "sint32", "sint64", "uint8", "uint16", "uint32", "uint64", "float32", "float64", "object", "class", "selector", "block", "char *", "void", "ptr", "bool", "char", "uchar"};
    
    #define SINT(type) do { \
        if(str[0] == @encode(type)[0]) \
        { \
            size_t size = sizeof(type); \
            if(size == 1) \
                return typeList[0]; \
            else if(size == 2) \
                return typeList[1]; \
            else if(size == 4) \
                return typeList[2]; \
            else if(size == 8) \
                return typeList[3]; \
            else \
            { \
                NSLog(@"Unknown size for type %s", #type); \
                abort(); \
            } \
        } \
    } while(0)
    
    #define UINT(type) do { \
        if(str[0] == @encode(type)[0]) \
        { \
            size_t size = sizeof(type); \
            if(size == 1) \
                return typeList[4]; \
            else if(size == 2) \
                return typeList[5]; \
            else if(size == 4) \
                return typeList[6]; \
            else if(size == 8) \
                return typeList[7]; \
            else \
            { \
                NSLog(@"Unknown size for type %s", #type); \
                abort(); \
            } \
        } \
    } while(0)
    
    #define INT(type) do { \
        SINT(type); \
        UINT(unsigned type); \
    } while(0)
    
    #define COND(type, name) do { \
        if(str[0] == @encode(type)[0]) \
        return name; \
    } while(0)
    
    #define PTR(type) COND(type, typeList[16])
    
    COND(_Bool, typeList[17]);
    COND(char, typeList[18]);
    COND(unsigned char, typeList[19]);
    INT(short);
    INT(int);
    INT(long);
    INT(long long);
    COND(float, typeList[8]);
    COND(double, typeList[9]);
    
    if (strcmp(str, "@?") == 0) {
        return typeList[13];
    }
    
    COND(id, typeList[10]);
    COND(Class, typeList[11]);
    COND(SEL, typeList[12]);
    PTR(void *);
    COND(char *, typeList[14]);
    COND(void, typeList[15]);
    
    // Ignore Method Encodings
    switch (*str) {
        case 'r':
        case 'R':
        case 'n':
        case 'N':
        case 'o':
        case 'O':
        case 'V':
            return native_type_encoding(str + 1);
    }
    
    // Struct Type Encodings
    if (*str == '{') {
        return native_struct_encoding(str);
    }
    
    NSLog(@"Unknown encode string %s", str);
    return str;
}

const char **
native_types_encoding(const char *str, int *count, int startIndex) {
    int argCount = DOTypeCount(str) - startIndex;
    const char **argTypes = (const char **)malloc(sizeof(char *) * argCount);
    
    int i = -startIndex;
    while(str && *str)
    {
        const char *next = DOSizeAndAlignment(str, NULL, NULL, NULL);
        if (i >= 0 && i < argCount) {
            const char *argType = native_type_encoding(str);
            if (argType) {
                argTypes[i] = argType;
            }
            else {
                if (count) {
                    *count = -1;
                }
                return nil;
            }
        }
        i++;
        str = next;
    }
    
    if (count) {
        *count = argCount;
    }
    
    return argTypes;
}

const char *
native_struct_encoding(const char *encoding)
{
    NSUInteger size, align;
    long length;
    DOSizeAndAlignment(encoding, &size, &align, &length);
    NSString *str = [NSString stringWithUTF8String:encoding];
    const char *temp = [str substringWithRange:NSMakeRange(0, length)].UTF8String;
    int structNameLength = 0;
    // cut "struct="
    while (temp && *temp && *temp != '=') {
        temp++;
        structNameLength++;
    }
    int elementCount = 0;
    const char **elements = native_types_encoding(temp + 1, &elementCount, 0);
    if (!elements) {
        return nil;
    }
    NSMutableString *structType = [NSMutableString stringWithFormat:@"%@", [str substringToIndex:structNameLength + 1]];
    for (int i = 0; i < elementCount; i++) {
        if (i != 0) {
            [structType appendString:@","];
        }
        [structType appendFormat:@"%@", [NSString stringWithUTF8String:elements[i]]];
    }
    [structType appendString:@"}"];
    free(elements);
    return structType.UTF8String;
}

bool
LP64() {
#if defined(__LP64__) && __LP64__
    return true;
#else
    return false;
#endif
}

bool
NS_BUILD_32_LIKE_64() {
#if defined(NS_BUILD_32_LIKE_64) && NS_BUILD_32_LIKE_64
    return true;
#else
    return false;
#endif
}

dispatch_queue_main_t
_dispatch_get_main_queue(void) {
    return dispatch_get_main_queue();
}


void *
native_null() {
    return (__bridge void *)[NSNull null];
}
