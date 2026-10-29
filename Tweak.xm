// language: Objective-C, file: Tweak.xm
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/vm_map.h>
#include <cmath>

// ==========================================
// BỘ OFFSET FF NORMAL (Từ file của mày)
// ==========================================
namespace Offsets {
    constexpr uintptr_t GameFacade = 0xA72E4E0;
    constexpr uintptr_t GameFacade_P2 = 0xB8;
    constexpr uintptr_t BaseGame_Match = 0x90;
    constexpr uintptr_t Match_PlayerDict = 0xC0;
    constexpr uintptr_t Match_LocalPlayer = 0xD8;
    constexpr uintptr_t Dict_Entries = 0x18;
    constexpr uintptr_t Dict_Count = 0x20;
    constexpr uintptr_t Dict_ArrayHeader = 0x20;
    constexpr uintptr_t Dict_EntryStride = 0x18;
    constexpr uintptr_t Dict_EntryValue = 0x10;
    constexpr uintptr_t Player_IsDead = 0x7C;
    constexpr uintptr_t Player_HP = 0x70;
    constexpr uintptr_t Player_Rotation = 0x614;
    constexpr uintptr_t Bone_Head = 0x6A0;
}

static uintptr_t g_baseAddr = 0;
static bool aimbotEnabled = false;

uintptr_t get_base_address() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "UnityFramework") || strstr(name, "FreeFire"))) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

template <typename T>
T ReadMemory(uintptr_t address) {
    if (address < 0x100000000 || address > 0x7FFFFFFFFFFF) return T{};
    return *(T*)(address);
}

struct Vector3 {
    float x, y, z;
    Vector3() : x(0), y(0), z(0) {}
    Vector3(float _x, float _y, float _z) : x(_x), y(_y), z(_z) {}
    Vector3 operator-(const Vector3& v) const { return Vector3(x - v.x, y - v.y, z - v.z); }
    float distance(const Vector3& v) const {
        return sqrt(pow(x - v.x, 2) + pow(y - v.y, 2) + pow(z - v.z, 2));
    }
};

// Hàm lấy ma trận vị trí (Mày thử nghiệm, có thể cần sửa Offset)
Vector3 GetBonePosition(uintptr_t transformPtr) {
    if (!transformPtr) return Vector3();
    // Trong Unity, vị trí thường nằm ở 0x90 hoặc 0x38
    struct Matrix { float m[16]; };
    Matrix mat = ReadMemory<Matrix>(transformPtr + 0x90); 
    return Vector3(mat.m[12], mat.m[13], mat.m[14]); 
}

void UpdateAimbot() {
    if (!aimbotEnabled) return;
    if (!g_baseAddr) g_baseAddr = get_base_address();
    if (!g_baseAddr) return;

    uintptr_t gameFacade = ReadMemory<uintptr_t>(g_baseAddr + Offsets::GameFacade);
    if (!gameFacade) return;
    uintptr_t baseGame = ReadMemory<uintptr_t>(gameFacade + Offsets::GameFacade_P2);
    if (!baseGame) return;
    uintptr_t match = ReadMemory<uintptr_t>(baseGame + Offsets::BaseGame_Match);
    if (!match) return;
    uintptr_t localPlayer = ReadMemory<uintptr_t>(match + Offsets::Match_LocalPlayer);
    if (!localPlayer) return;
    uintptr_t playerDict = ReadMemory<uintptr_t>(match + Offsets::Match_PlayerDict);
    if (!playerDict) return;

    uintptr_t entries = ReadMemory<uintptr_t>(playerDict + Offsets::Dict_Entries);
    int count = ReadMemory<int>(playerDict + Offsets::Dict_Count);
    
    uintptr_t myHeadTransform = ReadMemory<uintptr_t>(localPlayer + Offsets::Bone_Head);
    if (!myHeadTransform) return;
    Vector3 myPos = GetBonePosition(myHeadTransform);

    uintptr_t bestTarget = 0;
    float bestDistance = 9999.0f;
    Vector3 bestEnemyPos;

    // Quét địch
    for (int i = 0; i < count; i++) {
        uintptr_t entryAddr = entries + Offsets::Dict_ArrayHeader + (i * Offsets::Dict_EntryStride);
        uintptr_t enemyPlayer = ReadMemory<uintptr_t>(entryAddr + Offsets::Dict_EntryValue);
        
        if (!enemyPlayer || enemyPlayer == localPlayer) continue;
        if (ReadMemory<bool>(enemyPlayer + Offsets::Player_IsDead)) continue;

        uintptr_t enemyHeadTransform = ReadMemory<uintptr_t>(enemyPlayer + Offsets::Bone_Head);
        if (!enemyHeadTransform) continue;
        
        Vector3 enemyPos = GetBonePosition(enemyHeadTransform);
        float dist = myPos.distance(enemyPos);
        
        if (dist < bestDistance) {
            bestDistance = dist;
            bestTarget = enemyPlayer;
            bestEnemyPos = enemyPos;
        }
    }

    // Ngắm
    if (bestTarget != 0) {
        Vector3 dir = bestEnemyPos - myPos;
        float pitch = -asin(dir.y / bestDistance) * (180.0f / M_PI);
        float yaw = atan2(dir.x, dir.z) * (180.0f / M_PI);
        
        uintptr_t rotationAddr = localPlayer + Offsets::Player_Rotation;
        vm_protect(mach_task_self(), rotationAddr, 8, false, VM_PROT_READ | VM_PROT_WRITE);
        float* angles = (float*)rotationAddr;
        angles[0] = pitch;
        angles[1] = yaw;
        vm_protect(mach_task_self(), rotationAddr, 8, false, VM_PROT_READ);
    }
}

// UI & Hook khởi tạo (Giữ nguyên như lúc nãy)
@interface TrungDungFFMenu : UIView
@end
@implementation TrungDungFFMenu
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.1 green:0.05 blue:0.05 alpha:0.9];
        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor redColor].CGColor;
        
        UILabel *lbl1 = [[UILabel alloc] initWithFrame:CGRectMake(15, 40, 150, 30)];
        lbl1.text = @"Aim Kill (FF)";
        lbl1.textColor = [UIColor whiteColor];
        [self addSubview:lbl1];
        
        UISwitch *sw1 = [[UISwitch alloc] initWithFrame:CGRectMake(frame.size.width - 60, 40, 50, 30)];
        [sw1 addTarget:self action:@selector(toggleAim:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:sw1];
    }
    return self;
}
- (void)toggleAim:(UISwitch *)s { aimbotEnabled = s.isOn; }
@end

@interface TrungDungTimer : NSObject
+ (void)startLoop;
@end
@implementation TrungDungTimer
+ (void)startLoop {
    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer * _Nonnull timer) {
        UpdateAimbot();
    }];
}
@end

%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
    id ret = %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TrungDungFFMenu *menu = [[TrungDungFFMenu alloc] initWithFrame:CGRectMake(20, 100, 250, 100)];
            UIWindow *window = [[UIApplication sharedApplication] keyWindow];
            [window addSubview:menu];
            [NSClassFromString(@"TrungDungTimer") startLoop];
        });
    });
    return ret;
}
%end