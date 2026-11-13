import { RoomCard } from '../components/RoomCard';
import { HourglassTimer } from '../components/HourglassTimer';
import { ChatRoom, getRoomCardRenderKey, getNow, isUnlockWindowAvailable } from '../model/ChatRoom';
import { Utils } from '../common/Utils';
import { StorageService } from '../service/StorageService';

// 沙漏列表页
//
// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P2-D 对齐：
// 智能分组（即将过期 / 可解锁 / 进行中）三栏渲染，节奏感优于平铺。
// UI 评审 P2（§4-4）：底部教育文案只在前 3 次进入本页时显示（本地计数）。
@Component
export struct HourglassPage {
  @Prop rooms: ChatRoom[] = [];
  @State now: number = getNow();
  @State showEduCopy: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  public onEnterRoom: ((roomId: string) => void) | null = null;
  private timer: number = -1;
  private static readonly EDU_SHOWN_KEY: string = 'edu_hourglass_shown_count';

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      this.now = getNow();
    }, 10000); // 每10秒更新倒计时
    this.maybeShowEduCopy();
  }

  private async maybeShowEduCopy(): Promise<void> {
    try {
      const shown: string = await StorageService.getInstance()
        .getPref(HourglassPage.EDU_SHOWN_KEY, '0');
      const count: number = parseInt(shown, 10) || 0;
      if (count >= 3) {
        return;
      }
      this.showEduCopy = true;
      await StorageService.getInstance()
        .setPref(HourglassPage.EDU_SHOWN_KEY, `${count + 1}`);
    } catch (_) {
      // 本地计数失败不阻塞页面
    }
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
    }
  }

  private getEarliestExpiry(): number {
    let earliest: number = 0;
    for (let i: number = 0; i < this.rooms.length; i++) {
      if (earliest === 0 || this.rooms[i].expiresAt < earliest) {
        earliest = this.rooms[i].expiresAt;
      }
    }
    return earliest;
  }

  // ========== P2-D 智能分组 ==========

  private static readonly EXPIRING_THRESHOLD_MS: number = 6 * 3600 * 1000;

  private classifyExpiring(): ChatRoom[] {
    const out: ChatRoom[] = [];
    for (let i: number = 0; i < this.rooms.length; i++) {
      const r: ChatRoom = this.rooms[i];
      const left: number = r.expiresAt - this.now;
      if (left > 0 && left < HourglassPage.EXPIRING_THRESHOLD_MS) {
        out.push(r);
      }
    }
    out.sort((a, b) => a.expiresAt - b.expiresAt);
    return out;
  }

  private classifyUnlockable(): ChatRoom[] {
    const out: ChatRoom[] = [];
    for (let i: number = 0; i < this.rooms.length; i++) {
      const r: ChatRoom = this.rooms[i];
      const left: number = r.expiresAt - this.now;
      // 即将过期优先级更高，已纳入 expiring 桶的不再重复
      if (left > 0 && left < HourglassPage.EXPIRING_THRESHOLD_MS) continue;
      const canUnlockNow: boolean = r.bothDeepConfirmed && !r.unlocked;
      const inWindow: boolean = !r.unlocked && r.deepConnectionAchieved && isUnlockWindowAvailable(r.createdAt);
      if (canUnlockNow || inWindow) {
        out.push(r);
      }
    }
    out.sort((a, b) => a.expiresAt - b.expiresAt);
    return out;
  }

  private classifyOngoing(): ChatRoom[] {
    const out: ChatRoom[] = [];
    for (let i: number = 0; i < this.rooms.length; i++) {
      const r: ChatRoom = this.rooms[i];
      const left: number = r.expiresAt - this.now;
      if (left > 0 && left < HourglassPage.EXPIRING_THRESHOLD_MS) continue;
      const canUnlockNow: boolean = r.bothDeepConfirmed && !r.unlocked;
      const inWindow: boolean = !r.unlocked && r.deepConnectionAchieved && isUnlockWindowAvailable(r.createdAt);
      if (canUnlockNow || inWindow) continue;
      out.push(r);
    }
    out.sort((a, b) => a.expiresAt - b.expiresAt);
    return out;
  }

  build() {
    Column() {
      // 顶部标题栏
      Column() {
        Row() {
          Text('⏳')
            .fontSize(18)

          Text(' 沙漏')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary'))

          // 最早到期房间倒计时
          if (this.rooms.length > 0) {
            HourglassTimer({ expiresAt: this.getEarliestExpiry() })
              .margin({ left: 12 })
          }
        }

        Text(`> ${this.rooms.length} 个活跃连接`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.statusBarHeight + 16, bottom: 16 })
      .backgroundColor($r('app.color.tab_bar_bg'))
      .border({ width: { bottom: 1 }, color: $r('app.color.divider') })

      // 内容列表
      if (this.rooms.length === 0) {
        Column() {
          Text('⏳')
            .fontSize(64)
            .opacity(0.2)

          Text('暂无活跃对话')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 16 })

          Text('响应一个声呐信号开始对话')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.6)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .height(256)
        .justifyContent(FlexAlign.Center)
      } else {
        this.GroupedListBuilder()
      }

      // 底部提示（UI 评审 P2：只在前 3 次进入显示）
      if (this.rooms.length > 0 && this.showEduCopy) {
        Text('所有对话将在72小时后自动风干，除非双方保存连接')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(12)
          .backgroundColor($r('app.color.tab_bar_bg'))
          .border({ width: { top: 1 }, color: $r('app.color.divider') })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.bg_base'))
  }

  @Builder
  GroupedListBuilder() {
    List({ space: 8 }) {
      // 即将过期
      if (this.classifyExpiring().length > 0) {
        ListItem() {
          this.SectionHeaderBuilder('⏰ 即将过期', '#E84855', this.classifyExpiring().length)
        }
        ForEach(this.classifyExpiring(), (room: ChatRoom) => {
          ListItem() {
            RoomCard({
              room: room,
              now: this.now,
              onEnter: (roomId: string) => {
                if (this.onEnterRoom) {
                  this.onEnterRoom(roomId);
                }
              }
            })
          }
        }, (room: ChatRoom) => getRoomCardRenderKey(room))
      }

      // 可解锁
      if (this.classifyUnlockable().length > 0) {
        ListItem() {
          this.SectionHeaderBuilder('🔓 可解锁', '#FF7800', this.classifyUnlockable().length)
        }
        ForEach(this.classifyUnlockable(), (room: ChatRoom) => {
          ListItem() {
            RoomCard({
              room: room,
              now: this.now,
              onEnter: (roomId: string) => {
                if (this.onEnterRoom) {
                  this.onEnterRoom(roomId);
                }
              }
            })
          }
        }, (room: ChatRoom) => getRoomCardRenderKey(room))
      }

      // 进行中
      if (this.classifyOngoing().length > 0) {
        ListItem() {
          this.SectionHeaderBuilder('💬 进行中', '#9CA3AF', this.classifyOngoing().length)
        }
        ForEach(this.classifyOngoing(), (room: ChatRoom) => {
          ListItem() {
            RoomCard({
              room: room,
              now: this.now,
              onEnter: (roomId: string) => {
                if (this.onEnterRoom) {
                  this.onEnterRoom(roomId);
                }
              }
            })
          }
        }, (room: ChatRoom) => getRoomCardRenderKey(room))
      }
    }
    .layoutWeight(1)
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  SectionHeaderBuilder(title: string, accent: string, count: number) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(accent)

      Row() {
        Text(`${count}`)
          .fontSize(11)
          .fontColor(accent)
          .fontWeight(FontWeight.Medium)
      }
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .margin({ left: 8 })
      .borderRadius(8)
      .backgroundColor(accent + '1F')

      Blank().layoutWeight(1)

      Row()
        .height(1)
        .width(40)
        .backgroundColor(accent + '33')
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }
}
