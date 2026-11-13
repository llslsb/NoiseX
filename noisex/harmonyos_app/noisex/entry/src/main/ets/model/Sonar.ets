// 声呐数据模型
export interface Sonar {
  id: string;
  content: string;
  distance: string; // 模糊化距离，如 "~500m", "同城"
  timestamp: number;
  geohash: string;
}
