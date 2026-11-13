/// 声呐输入过渡动效参数。
///
/// 纯函数集中保存动效数值，便于单元测试约束体验节奏，避免页面里散落魔法数字。
export interface SonarInputTransitionState {
  introVisible: boolean;
  burstVisible: boolean;
  inputScale: number;
  inputTranslateY: number;
  ringScale: number;
  ringOpacity: number;
}

export function createSonarInputTransitionState(visible: boolean): SonarInputTransitionState {
  if (visible) {
    return {
      introVisible: true,
      burstVisible: true,
      inputScale: 1,
      inputTranslateY: 0,
      ringScale: 2.4,
      ringOpacity: 0.04
    };
  }
  return {
    introVisible: false,
    burstVisible: true,
    inputScale: 0.9,
    inputTranslateY: 18,
    ringScale: 0.56,
    ringOpacity: 0.7
  };
}
