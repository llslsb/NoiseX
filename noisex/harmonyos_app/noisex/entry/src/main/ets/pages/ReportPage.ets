import { promptAction } from '@kit.ArkUI';
import { ApiService } from '../service/ApiService';
import { Logger } from '../common/Logger';

// 举报页
//
// UI 评审 P0（§8，与 Flutter report_page.dart 同步）：
// - 不再渲染内部 roomId（工程泄漏），只显示匿名信号码；上报 API 仍用 roomId
// - 举报原因加 preset chips（点按填入，仍可自由编辑——后端接口不变）
// - 手机号文案去恐惧化：保留"法律追溯"语义（与隐私协议承诺一致），
//   补充"不会透露给对方，不影响匿名身份"
@Component
export struct ReportPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @Prop roomId: string = '';
  @Prop signalCode: string = '';
  @State reason: string = '';
  @State phoneNumber: string = '';
  @State reportId: string = '';
  @State isSubmitting: boolean = false;
  @State isDone: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  // 底部导航条避让高度（Index.refreshAvoidAreas 维护）：提交按钮滚到最底不被导航条遮挡
  @StorageProp('bottomAvoidHeight') bottomAvoidHeight: number = 32;

  // 举报原因快捷项（Flutter 端 _reasonPresets 逐字对齐）
  private static readonly REASON_PRESETS: string[] =
    ['骚扰辱骂', '色情低俗', '诈骗钓鱼', '违法违规', '其他'];

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

      Text('举报')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 8 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }

  private async submitReport(): Promise<void> {
    if (this.reason.length === 0) return;
    this.isSubmitting = true;
    try {
      this.reportId = await ApiService.getInstance().reportRoom(this.roomId, this.reason, this.phoneNumber);
      this.isDone = true;
    } catch (e) {
      Logger.error(`[ReportPage] Report failed: ${e}`);
      promptAction.showToast({ message: '举报提交失败，请稍后重试' });
    }
    this.isSubmitting = false;
  }

  build() {
    NavDestination() {
      Column() {
        // 状态栏占位
        Blank()
          .height(this.statusBarHeight)

        // 顶部导航栏
        this.HeaderBuilder()

        if (this.isDone) {
          Column() {
            Text('举报已提交')
              .fontSize(18)
              .fontColor($r('app.color.primary'))
              .margin({ bottom: 8 })

            Text('已进入官方审核队列')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .margin({ bottom: 8 })

            Text(`举报编号：${this.reportId}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: 12 })

            // UI 评审 P1（§8-4）：完成态给"之后会发生什么"
            Text('接下来：官方将审核该对话；情况属实时对方账号会被限制使用，你的身份信息不会透露给对方。如需追踪请保留编号。')
              .fontSize(12)
              .lineHeight(19)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // UI 评审 P0：只显示匿名信号码，不暴露内部 roomId
              Text(`举报对话 ${this.signalCode !== '' ? this.signalCode : '与该陌生人'}`)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 16 })

              Column() {
                Text('举报原因 *')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ bottom: 8 })

                // 快捷原因 chips：点按填入文本框，可继续编辑补充
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(ReportPage.REASON_PRESETS, (preset: string) => {
                    Text(preset)
                      .fontSize(12)
                      .fontColor(this.reason === preset ?
                        $r('app.color.bg_base') : $r('app.color.text_secondary'))
                      .backgroundColor(this.reason === preset ?
                        $r('app.color.primary') : $r('app.color.bg_card'))
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .borderRadius(16)
                      .border({
                        width: 1,
                        color: this.reason === preset ?
                          $r('app.color.primary') : $r('app.color.primary_border')
                      })
                      .margin({ right: 8, bottom: 8 })
                      .onClick(() => {
                        this.reason = preset;
                      })
                  }, (preset: string) => preset)
                }
                .width('100%')

                TextArea({ text: this.reason, placeholder: '请描述违规行为（可补充细节）...' })
                  .width('100%')
                  .height(120)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_card'))
                  .placeholderColor($r('app.color.text_secondary'))
                  .onChange((value: string) => {
                    this.reason = value;
                  })
              }
              .width('100%')
              .padding(16)
              .alignItems(HorizontalAlign.Start)

              Column() {
                Text('手机号（选填，用于法律追溯）')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ bottom: 8 })

                TextInput({ text: this.phoneNumber, placeholder: '选填，如 13800138000' })
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_card'))
                  .placeholderColor($r('app.color.text_secondary'))
                  .type(InputType.Number)
                  .maxLength(11)
                  .onChange((value: string) => {
                    this.phoneNumber = value;
                  })

                // UI 评审 P0 §8-2：去恐惧化说明（语义与隐私协议一致）
                Text('仅官方处理纠纷或法律追溯时依法使用，AES-256-GCM 加密存储；不会透露给对方，不影响匿名身份。')
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_muted'))
                  .margin({ top: 8 })
              }
              .width('100%')
              .padding(16)
              .alignItems(HorizontalAlign.Start)

              Button(this.isSubmitting ? '提交中...' : '提交举报')
                .width('80%')
                .height(44)
                .fontSize(16)
                .fontColor('#ffffff')
                .backgroundColor('#e74c3c')
                .margin({ top: 24 })
                .enabled(!this.isSubmitting && this.reason.length > 0)
                .onClick(() => {
                  this.submitReport();
                })
            }
            // 滚动内容底部留出导航条避让，"提交举报"滚到最底仍完整可见
            .padding({ bottom: this.bottomAvoidHeight + 16 })
          }
          .layoutWeight(1)
        }
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
}
