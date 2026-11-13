import { ApiService } from '../service/ApiService';
import { AuthService } from '../service/AuthService';
import { PushService } from '../service/PushService';
import { ProfileData } from '../model/ApiTypes';
import { normalizeProfileField } from '../model/ChatRoom';
import { Logger } from '../common/Logger';
import { promptAction } from '@kit.ArkUI';
import { RitualAnimationService } from '../service/RitualAnimationService';

// 重置身份按住确认弹窗（UI 评审 P0 §7-2：全应用最不可逆操作，确认方式
// 从"点一下"升级为"按住 3 秒"——误触不可能完成，松手即取消。
// 与 Flutter showHarmonyHoldConfirmDialog / _HoldToConfirmButton 同款交互）
@CustomDialog
struct ResetHoldDialog {
  controller?: CustomDialogController;
  onConfirmed: () => void = () => {};
  @State holdProgress: number = 0;
  @State holding: boolean = false;
  private holdTimer: number = -1;
  private static readonly HOLD_TOTAL_MS: number = 3000;

  // 按住开始：进度填充交给渲染引擎线性动画（精确 3000ms），完成回调按
  // wall-clock setTimeout 触发。旧版 setInterval 50ms 每帧 elapsed += 50——
  // UI 线程被进度条重排拖慢时定时器晚点、累加变慢，"3 秒"实际按 5-6 秒
  // 才满（2026-11-03 用户实测）；引擎动画 + 真实时钟回调不受卡顿影响。
  // 填充条用 scaleX 左锚变换（纯渲染属性，动画插值可靠且丝滑）。
  private startHold(): void {
    this.stopHoldTimer();
    this.holding = true;
    this.holdProgress = 0;
    this.getUIContext().animateTo({
      duration: ResetHoldDialog.HOLD_TOTAL_MS,
      curve: Curve.Linear
    }, () => {
      this.holdProgress = 1;
    });
    this.holdTimer = setTimeout(() => {
      this.holdTimer = -1;
      this.holding = false;
      if (this.controller) {
        this.controller.close();
      }
      this.onConfirmed();
    }, ResetHoldDialog.HOLD_TOTAL_MS);
  }

  private cancelHold(): void {
    this.stopHoldTimer();
    this.holding = false;
    this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.holdProgress = 0;
    });
  }

  private stopHoldTimer(): void {
    if (this.holdTimer !== -1) {
      clearTimeout(this.holdTimer);
      this.holdTimer = -1;
    }
  }

  aboutToDisappear(): void {
    this.stopHoldTimer();
  }

  build() {
    // 用户反馈：弹窗贴左右两边——customStyle 弹窗内容 width('100%') 会铺满
    // 窗口。外层透明容器负责左右留白 48（对齐 Flutter
    // showHarmonyHoldConfirmDialog 的 insetPadding horizontal 48），
    // 内层面板 width('100%') 拿到留白后的宽度。
    Column() {
      Column() {
        Text('重置身份')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 12 })

        Text('此操作不可撤销！重置后：\n\n1. 当前身份的所有数据将被永久删除\n2. 所有进行中的对话将被关闭\n3. 对方将收到对话关闭通知\n4. 你将以全新身份重新开始')
          .fontSize(14)
          .lineHeight(21)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ bottom: 24 })

        // 按住 3 秒确认按钮：按住期间红色进度填充，松手重置
        // （填充条 scaleX 左锚变换，由渲染引擎 3s 线性插值）
        Stack({ alignContent: Alignment.Start }) {
          Text(this.holding ? '继续按住…' : '按住 3 秒确认重置')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.error'))
            .textAlign(TextAlign.Center)
            .backgroundColor('rgba(232, 72, 85, 0.12)')
            .border({ width: 1, color: $r('app.color.error'), radius: 12 })

          Row()
            .width('100%')
            .height(44)
            .backgroundColor('rgba(232, 72, 85, 0.35)')
            .scale({ x: this.holdProgress, y: 1, centerX: 0, centerY: '50%' })
        }
        .borderRadius(12)
        .clip(true)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.startHold();
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.cancelHold();
          }
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 28, bottom: 24 })
      .backgroundColor('#F013131A')
      .borderRadius(24)
    }
    .width('100%')
    .padding({ left: 48, right: 48 })
  }
}

@Component
export struct ProfilePage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  // 底部导航条避让高度（Index.refreshAvoidAreas 维护）：滚动到最底时末项不被导航条遮挡
  @StorageProp('bottomAvoidHeight') bottomAvoidHeight: number = 32;
  @State signature: string = '';
  @State city: string = '';
  @State contact: string = '';
  @State isEditing: boolean = false;
  @State isSaving: boolean = false;
  @State inputSignature: string = '';
  @State inputCity: string = '';
  @State inputContact: string = '';
  @State animEnabled: boolean = true;

  // UI 评审 P0 §7-2：重置身份按住 3 秒确认弹窗（替代一层普通 AlertDialog）
  resetDialog: CustomDialogController = new CustomDialogController({
    builder: ResetHoldDialog({
      onConfirmed: () => {
        void this.handleResetIdentity();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  });

  async aboutToAppear(): Promise<void> {
    this.loadProfile();
    this.animEnabled = await RitualAnimationService.getInstance().isRitualAnimationEnabled();
  }

  private async loadProfile(): Promise<void> {
    try {
      const profile: ProfileData = await ApiService.getInstance().getProfile();
      this.signature = profile.signature ?? '';
      this.city = profile.city ?? '';
      this.contact = profile.contact ?? '';
      this.inputSignature = profile.signature ?? '';
      this.inputCity = profile.city ?? '';
      this.inputContact = profile.contact ?? '';
    } catch (e) {
      Logger.error(`[ProfilePage] Load failed: ${e}`);
    }
  }

  private async saveProfile(): Promise<void> {
    this.isSaving = true;
    try {
      const profile: ProfileData = await ApiService.getInstance().updateProfile(
        this.inputSignature, this.inputCity, this.inputContact);
      this.signature = normalizeProfileField(profile.signature);
      this.city = normalizeProfileField(profile.city);
      this.contact = normalizeProfileField(profile.contact);
      this.isEditing = false;
    } catch (e) {
      Logger.error(`[ProfilePage] Save failed: ${e}`);
    }
    this.isSaving = false;
  }

  @Builder
  HeaderBuilder() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Text('←')
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.navPathStack.pop();
      })

      Text('设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 8 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }

  build() {
    NavDestination() {
      Column() {
        // 状态栏占位
        Blank()
          .height(this.statusBarHeight)

        // 顶部导航栏
        this.HeaderBuilder()

        Scroll() {
          Column() {
            Column() {
              Text('一句签名')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })

              if (this.isEditing) {
                TextInput({ text: this.inputSignature, placeholder: '比如：夜跑爱好者 / 只聊天文' })
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .placeholderColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.bg_base'))
                  .border({ width: 1, color: $r('app.color.primary_border'), radius: 4 })
                  .onChange((value: string) => {
                    this.inputSignature = value;
                  })
              } else {
                Column() {
                  Text(this.signature.length > 0 ? this.signature : '未设置')
                    .fontSize(16)
                    .fontColor(this.signature.length > 0 ? '#ffffff' : $r('app.color.text_secondary'))
                  // UI 评审 P1（§7-1）："未设置"下加动机行——填了对方解锁后能看到
                  if (this.signature.length === 0) {
                    Text('填一句签名，对方解锁资料后第一眼看到')
                      .fontSize(12)
                      .fontColor($r('app.color.text_muted'))
                      .margin({ top: 2 })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .onClick(() => {
                  this.isEditing = true;
                })
              }
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)

            Column() {
              Text('城市')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })

              if (this.isEditing) {
                TextInput({ text: this.inputCity, placeholder: '比如：芜湖' })
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .placeholderColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.bg_base'))
                  .border({ width: 1, color: $r('app.color.primary_border'), radius: 4 })
                  .onChange((value: string) => {
                    this.inputCity = value;
                  })
              } else {
                Column() {
                  Text(this.city.length > 0 ? this.city : '未设置')
                    .fontSize(16)
                    .fontColor(this.city.length > 0 ? '#ffffff' : $r('app.color.text_secondary'))
                  if (this.city.length === 0) {
                    Text('填了城市，匹配的陌生人更有共同话题')
                      .fontSize(12)
                      .fontColor($r('app.color.text_muted'))
                      .margin({ top: 2 })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .onClick(() => {
                  this.isEditing = true;
                })
              }
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)

            Column() {
              Text('一个公开联系方式')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })

              if (this.isEditing) {
                TextInput({ text: this.inputContact, placeholder: '比如：一个邮箱或公开账号' })
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .placeholderColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.bg_base'))
                  .border({ width: 1, color: $r('app.color.primary_border'), radius: 4 })
                  .onChange((value: string) => {
                    this.inputContact = value;
                  })
              } else {
                Column() {
                  Text(this.contact.length > 0 ? this.contact : '未设置')
                    .fontSize(16)
                    .fontColor(this.contact.length > 0 ? '#ffffff' : $r('app.color.text_secondary'))
                  if (this.contact.length === 0) {
                    Text('保存连接后对方靠它联系你')
                      .fontSize(12)
                      .fontColor($r('app.color.text_muted'))
                      .margin({ top: 2 })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .onClick(() => {
                  this.isEditing = true;
                })
              }
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)

            Text('资料卡仅在双方确认深度交流并解锁后对对方可见')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .opacity(0.6)
              .padding(16)

            if (this.isEditing) {
              Button(this.isSaving ? '保存中...' : '保存')
                .width('80%')
                .height(44)
                .fontSize(16)
                .fontColor('#ffffff')
                .backgroundColor($r('app.color.primary'))
                .margin({ top: 24 })
                .enabled(!this.isSaving)
                .onClick(() => {
                  this.saveProfile();
                })
            }

            // 分隔区域
            Column() {
              Text('其他')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .opacity(0.6)
            }
            .width('100%')
            .padding({ top: 32, bottom: 8, left: 16, right: 16 })
            .alignItems(HorizontalAlign.Start)

            // 仪式动效开关
            Row() {
              Text('仪式动效')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.animEnabled })
                .selectedColor($r('app.color.primary'))
                .onChange((isOn: boolean) => {
                  this.animEnabled = isOn;
                  RitualAnimationService.getInstance().setRitualAnimationEnabled(isOn);
                })
            }
            .width('80%')
            .height(40)
            .margin({ top: 8 })

            // 拉黑列表
            Button('拉黑列表')
              .width('80%')
              .height(40)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: $r('app.color.divider'), radius: 4 })
              .onClick(() => {
                this.navPathStack.pushPathByName('BlockedList', null);
              })

            // 重置身份
            Button('重置身份')
              .width('80%')
              .height(40)
              .fontSize(14)
              .fontColor('#E84855')
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: '#E84855', radius: 4 })
              .margin({ top: 8 })
              .onClick(() => {
                this.resetDialog.open();
              })
          }
          // 滚动内容底部留出导航条避让，"重置身份"滚到最底仍完整可见
          .padding({ bottom: this.bottomAvoidHeight + 16 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_base'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_base'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      this.navPathStack.pop();
      return true;
    })
  }

  private async handleResetIdentity(): Promise<void> {
    try {
      await AuthService.getInstance().resetIdentity();
      promptAction.showToast({ message: '身份已重置，请重新打开应用' });
      this.navPathStack.clear();
    } catch (e) {
      Logger.error(`[ProfilePage] Reset identity failed: ${e}`);
      promptAction.showToast({ message: '重置失败，请重试' });
    }
  }
}
