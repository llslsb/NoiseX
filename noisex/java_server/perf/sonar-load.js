/**
 * NoiseX 性能测试 — k6 脚本
 *
 * 安装: https://k6.io/docs/get-started/installation/
 * 运行: k6 run perf/sonar-load.js
 *
 * 前置条件:
 *   - 服务运行在 http://localhost:8080
 *   - Redis + MySQL 已启动
 *   - JWT_SECRET 已设置
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// 自定义指标
const sonarSendFailRate = new Rate('sonar_send_fail_rate');
const sonarSendDuration = new Trend('sonar_send_duration');

// 测试配置
export const options = {
  stages: [
    { duration: '30s', target: 20 },   // 30秒内升到 20 VU
    { duration: '1m', target: 50 },    // 1分钟内升到 50 VU
    { duration: '30s', target: 50 },   // 保持 50 VU 30秒
    { duration: '30s', target: 0 },    // 30秒内降到 0
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% 请求 < 500ms
    sonar_send_fail_rate: ['rate<0.1'], // 发送失败率 < 10%
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// 注册并获取 JWT
function register(uuid) {
  const res = http.post(
    `${BASE_URL}/api/auth/register`,
    JSON.stringify({ anonymousUuid: uuid }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(res, { 'register ok': (r) => r.status === 200 });
  try {
    return JSON.parse(res.body).data.token;
  } catch {
    return null;
  }
}

// 发送声呐
function sendSonar(token, content, geohash) {
  const start = Date.now();
  const res = http.post(
    `${BASE_URL}/api/sonar`,
    JSON.stringify({ content, geohash }),
    { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` } }
  );
  const duration = Date.now() - start;
  sonarSendDuration.add(duration);

  const ok = res.status === 200 || res.status === 201;
  sonarSendFailRate.add(!ok);
  check(res, { 'sonar sent': (r) => ok });
  return ok;
}

// 获取收到的声呐
function getReceivedSonars(token) {
  const res = http.get(
    `${BASE_URL}/api/sonar/received`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  check(res, { 'get sonars ok': (r) => r.status === 200 });
  return res;
}

// 注册收听
function startListening(token, geohash) {
  const res = http.post(
    `${BASE_URL}/api/sonar/listen?geohash=${encodeURIComponent(geohash)}`,
    null,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  check(res, { 'listen ok': (r) => r.status === 200 });
}

export default function () {
  const uuid = `perf-user-${__VU}-${__ITER}`;
  const token = register(uuid);
  if (!token) return;

  // 先注册收听
  const geohash = 'wx4g0s';
  startListening(token, geohash);

  // 发送声呐
  const contents = [
    '有人看过昨晚的极光新闻吗？',
    '周末有人去爬山吗？',
    '附近有没有好的咖啡馆推荐？',
    '今天天气真不错！',
    '有没有人一起打羽毛球？',
  ];
  const content = contents[__VU % contents.length];
  sendSonar(token, content, geohash);

  // 查看收到的声呐
  getReceivedSonars(token);

  sleep(1);
}
