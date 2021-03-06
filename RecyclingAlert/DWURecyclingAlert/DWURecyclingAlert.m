//
//  DWURecyclingAlert.m
//  RecyclingAlert
//
//  Created by Di Wu on 6/7/15.
//  Copyright (c) 2015 Di Wu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UITableViewCell.h>
#import <UIKit/UIImage.h>
#import <QuartzCore/CALayer.h>

#define DWURecyclingAlertEnabled

#if defined (DEBUG) && defined (DWURecyclingAlertEnabled)
@interface UIView (DWURecyclingAlert)

@property (nonatomic, strong) NSNumber *dwuRecyclingCount;

@end

@implementation UIView (DWURecyclingAlert)

@dynamic dwuRecyclingCount;

- (void)setDwuRecyclingCount:(NSNumber *)number {
    objc_setAssociatedObject(self, @selector(dwuRecyclingCount), number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)dwuRecyclingCount {
    return objc_getAssociatedObject(self, @selector(dwuRecyclingCount));
}

@end

// http://www.mikeash.com/pyblog/friday-qa-2010-01-29-method-replacement-for-fun-and-profit.html
static BOOL dwu_replaceMethodWithBlock(Class c, SEL origSEL, SEL newSEL, id block) {
    if ([c instancesRespondToSelector:newSEL]) return YES; // Selector already implemented, skip silently.
    
    Method origMethod = class_getInstanceMethod(c, origSEL);
    
    // Add the new method.
    IMP impl = imp_implementationWithBlock(block);
    if (!class_addMethod(c, newSEL, impl, method_getTypeEncoding(origMethod))) {
        return NO;
    }else {
        Method newMethod = class_getInstanceMethod(c, newSEL);
        
        // If original doesn't implement the method we want to swizzle, create it.
        if (class_addMethod(c, origSEL, method_getImplementation(newMethod), method_getTypeEncoding(origMethod))) {
            class_replaceMethod(c, newSEL, method_getImplementation(origMethod), method_getTypeEncoding(newMethod));
        }else {
            method_exchangeImplementations(origMethod, newMethod);
        }
    }
    return YES;
}

static void dwu_recursionHelper1(UIView *view) {
    view.dwuRecyclingCount = @(1);
    for (UIView *subview in view.subviews) {
        dwu_recursionHelper1(subview);
    }
}

static void dwu_markAllSubviewsAsRecycled(UITableViewCell *_self) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dwu_recursionHelper1(_self.contentView);
    });
}

static void dwu_recursionHelper2(UIView *view) {
    static NSMutableSet *cgImageRefSet;
    if (!cgImageRefSet) {
        cgImageRefSet = [NSMutableSet set];
    }
    NSNumber *recyclingCount = view.dwuRecyclingCount;
    SEL imageSelector = NSSelectorFromString(@"image");
    BOOL viewTargetFound = NO;
    BOOL imageTargetFound = NO;
    if ([view respondsToSelector:imageSelector]) {
        UIImage *image = ((UIImage * ( *)(id, SEL))objc_msgSend)(view, imageSelector);
        if (image) {
            if (![cgImageRefSet containsObject:[NSString stringWithFormat:@"%@", image.CGImage]]) {
                [cgImageRefSet addObject:[NSString stringWithFormat:@"%@", image.CGImage]];
                imageTargetFound = YES;
            }
        }
    } else if (!recyclingCount) {
        viewTargetFound = YES;
        view.dwuRecyclingCount = @(1);
    }
    
    if (viewTargetFound || imageTargetFound) {
        view.layer.borderColor = [[UIColor redColor] CGColor];
        view.layer.borderWidth = 5.0;
    } else {
        view.layer.borderColor = [[UIColor clearColor] CGColor];
        view.layer.borderWidth = 0.0;
    }
    for (UIView *subview in view.subviews) {
        dwu_recursionHelper2(subview);
    }
}

static void dwu_checkNonRecycledSubviews(UITableViewCell *_self) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dwu_recursionHelper2(_self.contentView);
    });
}

__attribute__((constructor)) static void DWURecyclingAlert(void) {
    @autoreleasepool {
        NSString *selStr = NSStringFromSelector(@selector(prepareForReuse));
        SEL selector = NSSelectorFromString(selStr);
        SEL newSelector = NSSelectorFromString([NSString stringWithFormat:@"dwu_%@", selStr]);
        dwu_replaceMethodWithBlock(UITableViewCell.class, selector, newSelector, ^(__unsafe_unretained UITableViewCell *_self) {
            ((void ( *)(id, SEL))objc_msgSend)(_self, newSelector);
            dwu_checkNonRecycledSubviews(_self);
        });
        selStr = NSStringFromSelector(@selector(initWithStyle:reuseIdentifier:));
        selector = NSSelectorFromString(selStr);
        newSelector = NSSelectorFromString([NSString stringWithFormat:@"dwu_%@", selStr]);
        dwu_replaceMethodWithBlock(UITableViewCell.class, selector, newSelector, (id)^(__unsafe_unretained UITableViewCell *_self, NSInteger arg1, __unsafe_unretained id arg2) {
            dwu_markAllSubviewsAsRecycled(_self);
            return ((id ( *)(id, SEL, NSInteger, id))objc_msgSend)(_self, newSelector, arg1, arg2);
        });
    }
}
#endif