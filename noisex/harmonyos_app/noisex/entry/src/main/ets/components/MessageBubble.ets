import { Message } from '../model/Message';
import { Utils } from '../common/Utils';

// 消息气泡组件
//
// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P2-C 对齐：
// 长按触发上下文菜单（复制 / 引用 / 举报）。回调由 ChatPage 在 onLongPress 中处理。
// UI 评审 P1（§5-2/§5-3，与 Flutter MessageBubble 同步）：
// - 相邻 1 分钟内的消息隐藏时间戳行（由 ChatPage 判定传入 showTime）
// - 已读 ✓✓ 用气泡同款墨色 bg_base 加粗（2026-11-03：纯白与橙底深字
//   配色不协调，改回墨色靠 形态+字重+透明度 区分）
@Component
export struct MessageBubble {
  @Prop message: Message = { id: '', roomId: '', sender: 'me', content: '', timestamp: 0, read: false, encrypted: true };
  @Prop showTime: boolean = true;

  // P2-C：长按消息回调。由 ChatPage 注入处理菜单弹出与复制/引用/举报。
  onLongPress?: (message: Message) => void;

  // 三态送达指示（delivered 协议已下线，保留为死路径）：
  // - read: ✓✓ bg_base 全透明度 + 加粗（与 sent 的区分靠 形态+字重+透明度，
  //   不再换色——2026-11-03 用户反馈纯白对号与"橙底深字"配色不协调）
  // - delivered: ✓✓（半透明）
  // - 仅 sent: ✓（半透明）
  @Builder
  StatusGlyph() {
    if (this.message.sender === 'me') {
      if (this.message.read) {
        Text('✓✓')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.bg_base'))
          .margin({ left: 4 })
      } else if (this.message.delivered === true) {
        Text('✓✓')
          .fontSize(10)
          .fontColor($r('app.color.bg_base'))
          .opacity(0.6)
          .margin({ left: 4 })
      } else {
        Text('✓')
          .fontSize(10)
          .fontColor($r('app.color.bg_base'))
          .opacity(0.6)
          .margin({ left: 4 })
      }
    }
  }

  build() {
    Row() {
      Column() {
        Text(this.message.content)
          .fontSize(14)
          .fontColor(this.message.sender === 'me' ?
            $r('app.color.bg_base') : $r('app.color.text_primary'))
          .lineHeight(22.4)

        // 2026-11-03 用户反馈"对号不显示"修复：状态符号（✓/✓✓）是发送
        // 状态不是时间戳，不再跟随 showTime 隐藏——时间隐藏时本端消息
        // 仍渲染只含对号的行
        if (this.showTime) {
          Row() {
            Text(Utils.formatMessageTime(this.message.timestamp))
              .fontSize(10)
              .fontColor(this.message.sender === 'me' ?
                $r('app.color.bg_base') : $r('app.color.text_primary'))
              .opacity(0.6)

            this.StatusGlyph()
          }
          .margin({ top: 4 })
        } else if (this.message.sender === 'me') {
          Row() {
            this.StatusGlyph()
          }
          .margin({ top: 4 })
        }
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .borderRadius(8)
      .constraintSize({ maxWidth: '70%' })
      .backgroundColor(this.message.sender === 'me' ?
        $r('app.color.primary') : $r('app.color.bg_card'))
      .border({
        width: 1,
        color: this.message.sender === 'other' ?
          $r('app.color.card_border') : Color.Transparent
      })
      // P2-C：长按手势 → 上下文菜单（500ms 长按阈值）
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => {
            if (this.onLongPress !== undefined) {
              this.onLongPress(this.message);
            }
          })
      )
    }
    .width('100%')
    .justifyContent(this.message.sender === 'me' ? FlexAlign.End : FlexAlign.Start)
  }
}
