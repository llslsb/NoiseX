import { RadarAnimation } from '../components/RadarAnimation';
import { Constants } from '../model/Constants';

// 启动页
@Component
export struct SplashPage {
  @State progress: number = 0;
  private timer: number = -1;
  public onComplete: () => void = () => {};

  build() {
    Stack() {
      // 雷达动画背景
      Stack() {
        RadarAnimation()
      }
      .width('100%')
      .height('100%')
      .opacity(0.1)

      // 内容区域
      Column() {
        // Logo
        Text('📡')
          .fontSize(96)
          .margin({ bottom: 16 })

        // 品牌名
        Text('NOISEX')
          .fontSize(64)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))
          .letterSpacing(0.3)
          .margin({ bottom: 12 })

        // Slogan
        Text('遇见未知，不必算法')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .letterSpacing(0.1)
          .margin({ bottom: 48 })

        // 进度条
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width(256)
          .color($r('app.color.primary'))
          .backgroundColor($r('app.color.bg_muted'))
          .margin({ bottom: 8 })

        Text(`初始化声呐系统... ${this.progress}%`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        // 底部标语
        Column() {
          Text('无算法 · 无推荐 · 无排序')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.6)

          Text('纯粹的随机与地理邻近')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.6)
            .margin({ top: 4 })
        }
        .margin({ top: 32 })
      }
      .zIndex(10)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_base'))
    .alignContent(Alignment.Center)
  }

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      this.progress += 2;
      if (this.progress >= 100) {
        this.progress = 100;
        clearInterval(this.timer);
        // 通知父组件加载完成
        setTimeout(() => {
          this.onComplete();
        }, 500);
      }
    }, 30);
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
    }
  }
}
