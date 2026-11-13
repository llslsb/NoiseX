// 雷达扫描动画组件（含信号点随机出现/消失）
// 与 Flutter 端 radar_animation.dart 对齐
//
// blipCount 由后端 nearby-activity 接口提供（已 clamp 至 0..8），
// 决定雷达上同时存在的信号点数量，反映附近真实活跃人数。
//
// 流畅性重构（2026-11-03 用户反馈"扫描动画不如 Flutter 端流畅"）：
// 旧版 setInterval 11ms 逐度推进 @State——JS 定时器漂移 + 每帧状态更新，
// 帧率上不去且肉眼可见抖动。现改为渲染引擎驱动的无限 animateTo
// （iterations: -1，3s/圈线性），与 Flutter AnimationController.repeat() 同级丝滑。
// 布局自适应（对齐 Flutter 同款修复）：旧版硬编码 320 盒子，宽屏折叠机上
// 雷达只占页面中心一小块、圆环比 Flutter 端小一圈。现 onAreaChange 取父
// 容器实际尺寸，圆环/扫描线/信号点全部按短边半径自适应；信号点存极坐标，
// 尺寸变化无需重生成。
// 扫描线锚点修复：ArkUI rotate 默认绕组件自身中心（线段中点）旋转，
// 视觉上是"短线原地打转"；现 centerX:0 锚定左端=雷达圆心，与 Flutter
// （Alignment.centerLeft 旋转）同为标准雷达扫掠。

interface Blip {
  angle: number; // 极角（弧度）
  radiusFactor: number; // 0.35~1.0 半径比例
  visible: boolean;
  isTail: boolean; // 是否为最远端小信号点（营造层次）
}

@Component
export struct RadarAnimation {
  @Prop isActive: boolean = true;
  @Prop @Watch('onBlipCountChanged') blipCount: number = 3;
  @State sweepAngle: number = 0;
  @State blips: Blip[] = [];
  @State boxW: number = 320;
  @State boxH: number = 320;
  private blipTimer: number = -1;
  private blipPhase: number = 0;
  private sweepStarted: boolean = false;

  // 每个相位（0..5）对应的可见信号点比例，营造"呼吸式"出现/消失
  private phaseRatios: number[] = [0.34, 0.5, 0.67, 0.84, 1.0, 0.5];

  aboutToAppear(): void {
    this.regenerateBlips();

    // 信号点随机出现/消失（每 2 秒切换一次）
    this.blipTimer = setInterval(() => {
      if (!this.isActive) return;
      this.regenerateBlips();
    }, 2000);
  }

  // blipCount 变化时立即刷新，不必等下个 tick
  private onBlipCountChanged(): void {
    this.regenerateBlips();
  }

  aboutToDisappear(): void {
    if (this.blipTimer !== -1) {
      clearInterval(this.blipTimer);
      this.blipTimer = -1;
    }
  }

  // 扫描线旋转：渲染引擎无限动画，首次拿到实际尺寸时启动一次（幂等）
  private startSweep(): void {
    if (this.sweepStarted) {
      return;
    }
    this.sweepStarted = true;
    this.getUIContext().animateTo({
      duration: 3000,
      curve: Curve.Linear,
      iterations: -1
    }, () => {
      this.sweepAngle = 360;
    });
  }

  // 根据 blipCount 重新生成信号点：数量反映附近活跃人数，
  // 可见数量按当前相位比例缩放，位置存极坐标（角度 + 0.35~1.0 半径比例）。
  private regenerateBlips(): void {
    const count: number = Math.min(8, Math.max(0, this.blipCount));
    if (count === 0) {
      this.blips = [];
      return;
    }
    this.blipPhase = (this.blipPhase + 1) % 6;
    const visibleN: number =
      Math.min(count, Math.max(0, Math.round(count * this.phaseRatios[this.blipPhase])));

    // Fisher-Yates 随机打乱 index，挑选哪些信号点可见
    const order: number[] = [];
    for (let i = 0; i < count; i++) {
      order.push(i);
    }
    for (let i = order.length - 1; i > 0; i--) {
      const j: number = Math.floor(Math.random() * (i + 1));
      const tmp: number = order[i];
      order[i] = order[j];
      order[j] = tmp;
    }
    const visibleSet: Set<number> = new Set<number>();
    for (let i = 0; i < visibleN; i++) {
      visibleSet.add(order[i]);
    }

    const next: Blip[] = [];
    for (let i = 0; i < count; i++) {
      const blip: Blip = {
        angle: Math.random() * Math.PI * 2,
        // 0.35~1.0：落在最内环之外、最外环之内（与 Flutter 同口径）
        radiusFactor: 0.35 + Math.random() * 0.65,
        visible: visibleSet.has(i),
        isTail: i === count - 1 && count > 1
      };
      next.push(blip);
    }
    this.blips = next;
  }

  // 雷达短边（圆环直径基准，与 Flutter min(w,h) 同口径）
  private boxMinSize(): number {
    return Math.min(this.boxW, this.boxH);
  }

  // 雷达半径
  private radiusSize(): number {
    return this.boxMinSize() / 2;
  }

  // 信号点 x/y：圆心 + 极坐标换算（×0.92 收一点，与 Flutter 同口径）
  private blipX(blip: Blip): number {
    return this.boxW / 2 + Math.cos(blip.angle) * blip.radiusFactor * this.radiusSize() * 0.92 - 4;
  }

  private blipY(blip: Blip): number {
    return this.boxH / 2 + Math.sin(blip.angle) * blip.radiusFactor * this.radiusSize() * 0.92 - 4;
  }

  build() {
    Stack() {
      // 雷达圆环（直径按短边 100%/75%/50%/25% 自适应，与 Flutter 同口径）
      Circle()
        .width(this.boxMinSize())
        .height(this.boxMinSize())
        .fill(Color.Transparent)
        .stroke($r('app.color.primary'))
        .strokeWidth(2)
        .opacity(0.3)

      Circle()
        .width(this.boxMinSize() * 0.75)
        .height(this.boxMinSize() * 0.75)
        .fill(Color.Transparent)
        .stroke($r('app.color.primary'))
        .strokeWidth(1)
        .opacity(0.2)

      Circle()
        .width(this.boxMinSize() * 0.5)
        .height(this.boxMinSize() * 0.5)
        .fill(Color.Transparent)
        .stroke($r('app.color.primary'))
        .strokeWidth(1)
        .opacity(0.2)

      Circle()
        .width(this.boxMinSize() * 0.25)
        .height(this.boxMinSize() * 0.25)
        .fill(Color.Transparent)
        .stroke($r('app.color.primary'))
        .strokeWidth(1)
        .opacity(0.2)

      // 扫描指针：左端锚定圆心（position 定位到圆心 + centerX:0 旋转轴），
      // 3s/圈无限旋转，渐隐向圆心（与 Flutter 同款）
      Row()
        .width(this.radiusSize())
        .height(2)
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [['#FF6B35', 0], ['transparent', 1]]
        })
        .position({ x: this.boxW / 2, y: this.boxH / 2 - 1 })
        .rotate({ angle: this.sweepAngle, centerX: 0, centerY: '50%' })

      // 信号点（数量由 blipCount 决定）
      ForEach(this.blips, (blip: Blip, index: number) => {
        if (blip.visible) {
          Circle()
            .width(blip.isTail ? 6 : 8)
            .height(blip.isTail ? 6 : 8)
            .fill($r('app.color.primary'))
            .opacity(blip.isTail ? 0.7 : 1.0)
            .position({ x: this.blipX(blip), y: this.blipY(blip) })
        }
      }, (blip: Blip, index: number) =>
        `${index}_${blip.visible}_${blip.angle.toFixed(3)}_${blip.radiusFactor.toFixed(3)}`)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.boxW = Number(newArea.width);
      this.boxH = Number(newArea.height);
      this.startSweep();
    })
    .opacity(this.isActive ? 1.0 : 0.3)
  }
}
