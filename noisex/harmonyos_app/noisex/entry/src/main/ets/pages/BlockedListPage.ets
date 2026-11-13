import { ApiService } from '../service/ApiService';
import { Logger } from '../common/Logger';
import { Constants } from '../model/Constants';

/**
 * 拉黑列表页面
 *
 * 功能：
 * - 显示已拉黑的用户 ID 列表
 * - 提供解除拉黑按钮
 * - 解除时弹出确认对话框
 */
@Component
export struct BlockedListPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  // 底部导航条避让高度（Index.refreshAvoidAreas 维护）：底部提示条抬到导航条之上
  @StorageProp('bottomAvoidHeight') bottomAvoidHeight: number = 32;
  @State blockedList: string[] = [];
  @State isLoading: boolean = true;
  @State showConfirmDialog: boolean = false;
  @State pendingUnblockUserId: string = '';

  aboutToAppear(): void {
    this.loadBlockedList();
  }

  private async loadBlockedList(): Promise<void> {
    this.isLoading = true;
    try {
      const api: ApiService = ApiService.getInstance();
      this.blockedList = await api.getBlockedList();
    } catch (err) {
      Logger.error(`[BlockedListPage] 加载拉黑列表失败: ${err}`);
    } finally {
      this.isLoading = false;
    }
  }

  private showUnblockConfirm(userId: string): void {
    this.pendingUnblockUserId = userId;
    this.showConfirmDialog = true;
  }

  private async confirmUnblock(): Promise<void> {
    this.showConfirmDialog = false;
    if (this.pendingUnblockUserId.length === 0) {
      return;
    }

    const userId: string = this.pendingUnblockUserId;
    this.pendingUnblockUserId = '';

    try {
      const api: ApiService = ApiService.getInstance();
      await api.unblockUser(userId);
      Logger.info(`[BlockedListPage] 解除拉黑成功: ${userId}`);
      await this.loadBlockedList();
    } catch (err) {
      Logger.error(`[BlockedListPage] 解除拉黑失败: ${err}`);
    }
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

      Text('拉黑列表')
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

        // 内容区域
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color($r('app.color.primary'))
            Text('加载中...')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 12 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.blockedList.length === 0) {
          // 空状态
          Column() {
            Text('🛡️')
              .fontSize(64)
              .opacity(0.2)
            Text('暂无拉黑用户')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 16 })
            Text('在聊天页面点击"拉黑"后，对方会出现在这里')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .opacity(0.6)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 拉黑列表
          List({ space: 12 }) {
            ForEach(this.blockedList, (userId: string) => {
              ListItem() {
                Row() {
                  // 左侧：图标 + 用户信息
                  Row() {
                    Text('🚫')
                      .fontSize(20)
                    Column() {
                      Text('已拉黑用户')
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                      Text(this.maskUserId(userId))
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                        .opacity(0.7)
                        .margin({ top: 4 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .margin({ left: 12 })
                  }
                  .layoutWeight(1)

                  // 右侧：解除按钮
                  Button('解除')
                    .fontSize(13)
                    .fontColor($r('app.color.primary'))
                    .backgroundColor(Color.Transparent)
                    .borderWidth(1)
                    .borderColor($r('app.color.primary_border'))
                    .borderRadius(8)
                    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                    .height(32)
                    .onClick(() => {
                      this.showUnblockConfirm(userId);
                    })
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(16)
                .border({ width: 1, color: $r('app.color.card_border') })
              }
            }, (userId: string) => userId)
          }
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })

          // 底部提示
          Text('解除拉黑后，对方仍可能通过声呐匹配到你')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ left: 12, right: 12, top: 12, bottom: 12 + this.bottomAvoidHeight })
            .backgroundColor($r('app.color.tab_bar_bg'))
            .border({ width: { top: 1 }, color: $r('app.color.divider') })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_base'))
      .bindContentCover(this.showConfirmDialog, this.buildConfirmDialog(), {
        modalTransition: ModalTransition.NONE
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_base'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      this.navPathStack.pop();
      return true;
    })
  }

  @Builder
  buildConfirmDialog() {
    Column() {
      Column() {
        Text('🚫')
          .fontSize(48)
          .margin({ bottom: 16 })

        Text('解除拉黑')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 8 })

        Text('确定要解除拉黑吗？')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 8 })

        Text('解除后对方仍可能通过声呐匹配到你')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .opacity(0.8)
          .textAlign(TextAlign.Center)
          .margin({ bottom: 24 })

        Row() {
          Button('取消')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.bg_card'))
            .borderRadius(8)
            .layoutWeight(1)
            .height(44)
            .onClick(() => {
              this.showConfirmDialog = false;
              this.pendingUnblockUserId = '';
            })

          Button('确定解除')
            .fontSize(15)
            .fontColor($r('app.color.bg_base'))
            .backgroundColor($r('app.color.primary'))
            .borderRadius(8)
            .layoutWeight(1)
            .height(44)
            .margin({ left: 12 })
            .onClick(() => {
              this.confirmUnblock();
            })
        }
        .width('100%')
      }
      .width(300)
      .padding(24)
      .borderRadius(16)
      .backgroundColor($r('app.color.bg_card'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.6)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {})
  }

  /**
   * 脱敏显示用户 ID
   */
  private maskUserId(userId: string): string {
    if (userId.length <= 8) {
      return userId;
    }
    const prefix: string = userId.substring(0, 4);
    const suffix: string = userId.substring(userId.length - 4);
    const maskLength: number = userId.length - 8;
    return `${prefix}${'*'.repeat(maskLength)}${suffix}`;
  }
}
