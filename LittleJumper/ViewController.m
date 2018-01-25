//
//  ViewController.m
//  LittleJumper
//
//  Created by anjohnlv on 2018/1/22.
//  Copyright © 2018年 anjohnlv. All rights reserved.
//

#import "ViewController.h"
#import <SceneKit/SceneKit.h>

static const double kMaxPressDuration = 2.f;
static const int kMaxPlatformRadius = 6;
static const int kMinPlatformRadius = kMaxPlatformRadius-4;
static const double kGravityValue = 30;

typedef NS_OPTIONS(NSUInteger, CollisionDetectionMask) {
    CollisionDetectionMaskNone = 0,
    CollisionDetectionMaskFloor = 1 << 0,
    CollisionDetectionMaskPlatform = 1 << 1,
    CollisionDetectionMaskJumper = 1 << 2,
    CollisionDetectionMaskOldPlatform = 1 << 3,
};

@interface ViewController ()<SCNPhysicsContactDelegate>
@property (strong, nonatomic) IBOutlet UIControl *infoView;
@property (strong, nonatomic) IBOutlet UILabel *scoreLabel;
- (IBAction)restart;

@property(nonatomic, strong)SCNView *scnView;
@property(nonatomic, strong)SCNScene *scene;
@property(nonatomic, strong)SCNNode *floor;
@property(nonatomic, strong)SCNNode *lastPlatform, *platform, *nextPlatform;
@property(nonatomic, strong)SCNNode *jumper;
@property(nonatomic, strong)SCNNode *camera,*light;
@property(nonatomic, strong)NSDate *pressDate;
@property(nonatomic)NSInteger score;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if(self.scnView && self.floor && self.jumper) {
        [self createFirstPlatform];
    }
}

#pragma mark 添加第一个台子
/**
 初始化第一个台子
 
 @discussion 第一个台子造型固定，静态，会与小人碰撞，初始化完成后调整镜头位置
 */
-(void)createFirstPlatform {
    self.platform = ({
        SCNNode *node = [SCNNode node];
        node.geometry = ({
            SCNCylinder *cylinder = [SCNCylinder cylinderWithRadius:5 height:2];
            cylinder.firstMaterial.diffuse.contents = UIColor.redColor;
            cylinder;
        });
        node.physicsBody = ({
            SCNPhysicsBody *body = [SCNPhysicsBody staticBody];
            body.restitution = 0;
            body.friction = 1;
            body.damping = 0;
            body.categoryBitMask = CollisionDetectionMaskPlatform;
            body.collisionBitMask = CollisionDetectionMaskJumper|CollisionDetectionMaskPlatform|CollisionDetectionMaskOldPlatform;
            body;
        });
        node.position = SCNVector3Make(0, 1, 0);
        [self.scene.rootNode addChildNode:node];
        node;
    });
    [self moveCameraToCurrentPlatform];
}

#pragma mark 蓄力
/**
 长按手势事件
 
 @discussion 通过长按时间差模拟力量，如果有最大值
 */
-(void)accumulateStrength:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _pressDate = [NSDate date];
        [self updateStrengthStatus];
    }else if(recognizer.state == UIGestureRecognizerStateEnded) {
        if (_pressDate) {
            self.jumper.geometry.firstMaterial.diffuse.contents = UIColor.whiteColor;
            [self.jumper removeAllActions];
            NSDate *now = [NSDate date];
            double pressDate = [_pressDate timeIntervalSince1970];
            double nowDate = [now timeIntervalSince1970];
            double power = nowDate - pressDate;
            power = power>kMaxPressDuration?kMaxPressDuration:power;
            [self jumpWithPower:power];
            _pressDate = nil;
        }
    }
}

/**
 力量显示
 
 @discussion 这里简单地用颜色表示，力量越大，小人越红
 */
-(void)updateStrengthStatus {
    SCNAction *action = [SCNAction customActionWithDuration:kMaxPressDuration actionBlock:^(SCNNode * node, CGFloat elapsedTime) {
        CGFloat percentage = elapsedTime/kMaxPressDuration;
        self.jumper.geometry.firstMaterial.diffuse.contents = [UIColor colorWithRed:1 green:1-percentage blue:1-percentage alpha:1];
    }];
    [self.jumper runAction:action];
}

#pragma mark 发力
/**
 根据力量值给小人一个力

 @param power 按的时间0~kMaxPressDuration秒
 @discussion 根据按的时间长短，对小人施加一个力，力由一个向上的力，和平面方向上的力组成，平面方向的力由小人的位置和目标台子的位置计算得出
 */
-(void)jumpWithPower:(double)power {
    power *= 30;
    SCNVector3 platformPosition = self.nextPlatform.presentationNode.position;
    SCNVector3 jumperPosition = self.jumper.presentationNode.position;
    double subtractionX = platformPosition.x-jumperPosition.x;
    double subtractionZ = platformPosition.z-jumperPosition.z;
    double proportion = fabs(subtractionX/subtractionZ);
    double x = sqrt(1 / (pow(proportion, 2) + 1)) * proportion;
    double z = sqrt(1 / (pow(proportion, 2) + 1));
    x*=subtractionX<0?-1:1;
    z*=subtractionZ<0?-1:1;
    SCNVector3 force = SCNVector3Make(x*power, 20, z*power);
    [self.jumper.physicsBody applyForce:force impulse:YES];
}

#pragma mark 跳跃会触发的事件
-(void)jumpCompleted {
    self.score++;
    self.lastPlatform = self.platform;
    self.platform = self.nextPlatform;
    [self moveCameraToCurrentPlatform];
}

/**
 调整镜头以观察小人目前所在台子的位置
 */
-(void)moveCameraToCurrentPlatform {
    SCNVector3 position = self.platform.presentationNode.position;
    position.x += 20;
    position.y += 30;
    position.z += 20;
    SCNAction *move = [SCNAction moveTo:position duration:0.5];
    [self.camera runAction:move];
    [self createNextPlatform];
}

/**
 创建下一个台子
 */
-(void)createNextPlatform {
    self.nextPlatform = ({
        SCNNode *node = [SCNNode node];
        node.geometry = ({
            //随机大小
            int radius = (arc4random() % kMinPlatformRadius) + (kMaxPlatformRadius-kMinPlatformRadius);
            SCNCylinder *cylinder = [SCNCylinder cylinderWithRadius:radius height:2];
            //随机颜色
            cylinder.firstMaterial.diffuse.contents = ({
                CGFloat r = ((arc4random() % 255)+0.0)/255;
                CGFloat g = ((arc4random() % 255)+0.0)/255;
                CGFloat b = ((arc4random() % 255)+0.0)/255;
                UIColor *color = [UIColor colorWithRed:r green:g blue:b alpha:1];
                color;
            });
            cylinder;
        });
        node.physicsBody = ({
            SCNPhysicsBody *body = [SCNPhysicsBody dynamicBody];
//            body.mass = 100;
            body.restitution = 1;
            body.friction = 1;
            body.damping = 0;
            body.allowsResting = YES;
            body.categoryBitMask = CollisionDetectionMaskPlatform;
            body.collisionBitMask = CollisionDetectionMaskJumper|CollisionDetectionMaskFloor|CollisionDetectionMaskOldPlatform|CollisionDetectionMaskPlatform;
            body.contactTestBitMask = CollisionDetectionMaskJumper;
            body;
        });
        //随机位置
        node.position = ({
            SCNVector3 position = self.platform.presentationNode.position;
            int xDistance = (arc4random() % (kMaxPlatformRadius*3-1))+1;
            position.z -= ({
                double lastRadius = ((SCNCylinder *)self.platform.geometry).radius;
                double radius = ((SCNCylinder *)node.geometry).radius;
                double maxDistance = sqrt(pow(kMaxPlatformRadius*3, 2)-pow(xDistance, 2));
                double minDistance = (xDistance>lastRadius+radius)?xDistance:sqrt(pow(lastRadius+radius, 2)-pow(xDistance, 2));
                double zDistance = (((double) rand() / RAND_MAX) * (maxDistance-minDistance)) + minDistance;
                zDistance;
            });
            position.x -= xDistance;
            position.y += 5;
            position;
        });
        [self.scene.rootNode addChildNode:node];
        node;
    });
}

#pragma mark 游戏结束
-(void)gameDidOver {
    NSLog(@"Game Over");
    [self.view bringSubviewToFront:self.infoView];
    [self.scoreLabel setText:[NSString stringWithFormat:@"当前分数:%d",(int)self.score]];
}

#pragma mark SCNPhysicsContactDelegate
/**
 碰撞事件监听

 @discussion 如果是小人与地板碰撞，游戏结束。取消地板对小人的监听。
             如果是小人与台子碰撞，则跳跃完成，进行状态刷新
 */
- (void)physicsWorld:(SCNPhysicsWorld *)world didBeginContact:(SCNPhysicsContact *)contact{
    SCNPhysicsBody *bodyA = contact.nodeA.physicsBody;
    SCNPhysicsBody *bodyB = contact.nodeB.physicsBody;
    if (bodyA.categoryBitMask==CollisionDetectionMaskJumper) {
        if (bodyB.categoryBitMask==CollisionDetectionMaskFloor) {
            bodyB.contactTestBitMask = CollisionDetectionMaskNone;
            [self performSelectorOnMainThread:@selector(gameDidOver) withObject:nil waitUntilDone:NO];
        }else if (bodyB.categoryBitMask==CollisionDetectionMaskPlatform) {
            //这里有个小bug，我在第一次收到碰撞后进行如下配置，按理说不应该收到碰撞回调了。可实际上还是会来。于是我直接将跳过的台子的categoryBitMask改为CollisionDetectionMaskOldPlatform，保证每个台子只会收到一次。上面的掉落又没有这个bug。
            //bodyB.contactTestBitMask = CollisionDetectionMaskNone;
            bodyB.categoryBitMask = CollisionDetectionMaskOldPlatform;
            [self jumpCompleted];
        }
    }
}

#pragma mark 懒加载
-(SCNScene *)scene {
    if (!_scene) {
        _scene = ({
            SCNScene *scene = [SCNScene new];
            scene.physicsWorld.contactDelegate = self;
            scene.physicsWorld.gravity = SCNVector3Make(0, -kGravityValue, 0);
            scene;
        });
    }
    return _scene;
}

-(SCNView *)scnView {
    if (!_scnView) {
        _scnView = ({
            SCNView *view = [SCNView new];
            view.scene = self.scene;
            view.allowsCameraControl = NO;
            view.autoenablesDefaultLighting = NO;
            [self.view addSubview:view];
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[view]-0-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(view)]];
            [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[view]-0-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(view)]];
            UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(accumulateStrength:)];
            longPressGesture.minimumPressDuration = 0;
            view.gestureRecognizers = @[longPressGesture];
            view;
        });
    }
    return _scnView;
}

/**
 创建地板
 
 @discussion 用于光影效果，与落地判断
 */
-(SCNNode *)floor {
    if (!_floor) {
        _floor = ({
            SCNNode *node = [SCNNode node];
            node.geometry = ({
                SCNFloor *floor = [SCNFloor floor];
                floor.firstMaterial.diffuse.contents = UIColor.whiteColor;
                floor;
            });
            node.physicsBody = ({
                SCNPhysicsBody *body = [SCNPhysicsBody staticBody];
                body.restitution = 0;
                body.friction = 1;
                body.damping = 0.3;
                body.categoryBitMask = CollisionDetectionMaskFloor;
                body.collisionBitMask = CollisionDetectionMaskJumper|CollisionDetectionMaskPlatform|CollisionDetectionMaskOldPlatform;
                body.contactTestBitMask = CollisionDetectionMaskJumper;
                body;
            });
            [self.scene.rootNode addChildNode:node];
            node;
        });
    }
    return _floor;
}

/**
 初始化小人
 
 @discussion 小人是动态物体，自由落体到第一个台子中心，会受重力影响，会与台子和地板碰撞
 */
-(SCNNode *)jumper {
    if (!_jumper) {
        _jumper = ({
            SCNNode *node = [SCNNode node];
            node.geometry = ({
                SCNBox *box = [SCNBox boxWithWidth:1 height:1 length:1 chamferRadius:0];
                box.firstMaterial.diffuse.contents = UIColor.whiteColor;
                box;
            });
            node.physicsBody = ({
                SCNPhysicsBody *body = [SCNPhysicsBody dynamicBody];
                body.restitution = 0;
                body.friction = 1;
                body.rollingFriction = 1;
                body.damping = 0.3;
                body.allowsResting = YES;
                body.categoryBitMask = CollisionDetectionMaskJumper;
                body.collisionBitMask = CollisionDetectionMaskPlatform|CollisionDetectionMaskFloor|CollisionDetectionMaskOldPlatform;
                body;
            });
            node.position = SCNVector3Make(0, 12.5, 0);
            [self.scene.rootNode addChildNode:node];
            node;
        });
    }
    return _jumper;
}

/**
 初始化相机
 
 @discussion 光源随相机移动，所以将光源设置成相机的子节点
 */
-(SCNNode *)camera {
    if (!_camera) {
        _camera = ({
            SCNNode *node = [SCNNode node];
            node.camera = [SCNCamera camera];
            node.camera.zFar = 200.f;
            node.camera.zNear = .1f;
            [self.scene.rootNode addChildNode:node];
            node.eulerAngles = SCNVector3Make(-0.7, 0.6, 0);
            node;
        });
        [_camera addChildNode:self.light];
    }
    return _camera;
}

-(SCNNode *)light {
    if (!_light) {
        _light = ({
            SCNNode *node = [SCNNode node];
            node.light = ({
                SCNLight *light = [SCNLight light];
                light.color = UIColor.whiteColor;
                light.type = SCNLightTypeOmni;
                light;
            });
            node;
        });
    }
    return _light;
}

#pragma mark UI事件
- (IBAction)restart {
    [self.view sendSubviewToBack:self.infoView];
    self.score = 0;
    [self.scnView removeFromSuperview];
    self.scnView = nil;
    self.scene = nil;
    self.floor = nil;
    self.lastPlatform = nil;
    self.platform = nil;
    self.nextPlatform = nil;
    self.jumper = nil;
    self.camera = nil;
    self.light = nil;
    if(self.scnView && self.floor && self.jumper) {
        [self createFirstPlatform];
    }
}

#pragma mark 隐藏状态栏
-(BOOL)prefersStatusBarHidden {
    return YES;
}

@end
