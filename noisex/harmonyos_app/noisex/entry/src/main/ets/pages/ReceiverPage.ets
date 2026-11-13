import { SonarCard } from '../components/SonarCard';
import { Sonar } from '../model/Sonar';
import { promptAction } from '@kit.ArkUI';

// 接收器列表页
//
// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P2-E 对齐：
// - ListItem.swipeAction：右滑响应 / 左滑忽略
// - 顶栏【全部响应/全部忽略】按钮（≥2 条声呐时显示），AlertDialog 二次确认
@Component
export struct ReceiverPage {
  @Prop sonars: Sonar[] = [];
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  public onAccept: ((sonar: Sonar) => void) | null = null;
  public onIgnore: ((sonarId: string) => void) | null = null;
  // UI 评审 P1（§3-4）：空态行动出口——跳回声呐页（Index.ets 接线）
  public onGoToSonar: (() => void) | null = null;

  // ========== P2-E 批量决策对话框 ==========

  private confirmBatch(
    title: string,
    message: string,
    confirmLabel: string,
    confirmColor: ResourceColor,
    onConfirm: () => void
  ): void {
    AlertDialog.show({
      title: title,
      message: message,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: confirmLabel,
        fontColor: confirmColor,
        action: onConfirm
      }
    });
  }

  private handleAcceptAll(): void {
    if (this.sonars.length === 0) return;
    const count: number = this.sonars.length;
    this.confirmBatch(
      '全部响应',
      `将依次响应当前 ${count} 个声呐信号，并创建临时对话房间。`,
      '全部响应',
      $r('app.color.primary'),
      () => {
        // 一次性快照避免在迭代中被父端修改
        const snapshot: Sonar[] = this.sonars.slice();
        for (let i: number = 0; i < snapshot.length; i++) {
          if (this.onAccept) {
            this.onAccept(snapshot[i]);
          }
        }
      }
    );
  }

  private handleIgnoreAll(): void {
    if (this.sonars.length === 0) return;
    const count: number = this.sonars.length;
    this.confirmBatch(
      '全部忽略',
      `将忽略当前 ${count} 个声呐信号。`,
      '全部忽略',
      Color.Red,
      () => {
        const snapshot: Sonar[] = this.sonars.slice();
        for (let i: number = 0; i < snapshot.length; i++) {
          if (this.onIgnore) {
            this.onIgnore(snapshot[i].id);
          }
        }
        promptAction.showToast({ message: `已忽略 ${snapshot.length} 条声呐`, duration: 2000 });
      }
    );
  }

  // ========== P2-E 滑动操作背景 Builder ==========

  @Builder
  AcceptSwipeBuilder(sonar: Sonar) {
    Row() {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(20)
        .fontColor([$r('app.color.primary')])
      Text('响应')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary'))
        .margin({ left: 8 })
    }
    .padding({ left: 20, right: 20 })
    .height('100%')
    .backgroundColor('#FF6B351F')
    .borderRadius(12)
    .onClick(() => {
      if (this.onAccept) {
        this.onAccept(sonar);
      }
    })
  }

  @Builder
  IgnoreSwipeBuilder(sonar: Sonar) {
    Row() {
      Text('忽略')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ left: 8 })
    }
    .padding({ left: 20, right: 20 })
    .height('100%')
    .backgroundColor('#9CA3AF1F')
    .borderRadius(12)
    .onClick(() => {
      if (this.onIgnore) {
        this.onIgnore(sonar.id);
      }
    })
  }

  build() {
    Column() {
      // 顶部标题栏
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.ohos_mic'))
            .fontSize(18)
            .fontColor([$r('app.color.primary')])

          Text(' 接收器')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary'))

          Blank().layoutWeight(1)

          // P2-E 批量动作按钮：仅当 ≥2 条时显示
          if (this.sonars.length >= 2) {
            Row() {
              Text('全部响应')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary'))
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(6)
            .border({ width: 1, color: '#FF6B3566' })
            .onClick(() => this.handleAcceptAll())

            Row() {
              Text('全部忽略')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .margin({ left: 8 })
            .borderRadius(6)
            .border({ width: 1, color: '#9CA3AF66' })
            .onClick(() => this.handleIgnoreAll())
          }
        }
        .width('100%')

        Text(`> ${this.sonars.length} 个信号等待响应  ·  右滑响应 / 左滑忽略`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.statusBarHeight + 16, bottom: 16 })
      .backgroundColor($r('app.color.tab_bar_bg'))
      .border({ width: { bottom: 1 }, color: $r('app.color.divider') })

      // 内容列表
      if (this.sonars.length === 0) {
        // 空状态（UI 评审 P1 §3-4：标题+副标题去重，给行动出口）
        Column() {
          Text('📡')
            .fontSize(64)
            .opacity(0.2)

          Text('暂无收到的声呐信号')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 16 })

          Text('去声呐页发一个脉冲')
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(16)
            .border({ width: 1, color: $r('app.color.primary_border') })
            .margin({ top: 12 })
            .onClick(() => {
              if (this.onGoToSonar) {
                this.onGoToSonar();
              }
            })
        }
        .layoutWeight(1)
        .height(256)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.sonars, (sonar: Sonar) => {
            ListItem() {
              SonarCard({
                sonar: sonar,
                onAccept: (sonarId: string) => {
                  if (this.onAccept) {
                    this.onAccept(sonar);
                  }
                }
              })
            }
            // P2-E 滑动操作：start = 右滑揭示（响应）；end = 左滑揭示（忽略）
            .swipeAction({
              start: {
                builder: () => { this.AcceptSwipeBuilder(sonar) },
                actionAreaDistance: 80
              },
              end: {
                builder: () => { this.IgnoreSwipeBuilder(sonar) },
                actionAreaDistance: 80
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }, (sonar: Sonar) => sonar.id)
        }
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }

      // 底部提示
      if (this.sonars.length > 0) {
        Text('响应后将创建临时对话房间（72小时有效期）')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(12)
          .backgroundColor('rgba(19, 19, 26, 0.5)')
          .border({ width: { top: 1 }, color: $r('app.color.divider') })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.bg_base'))
  }
}
