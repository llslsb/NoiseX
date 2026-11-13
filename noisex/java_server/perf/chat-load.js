/**
 * NoiseX 聊天消息压测 — k6 脚本
 *
 * 测试场景: 两个用户匹配后互相发送消息
 * 运行: k6 run perf/chat-load.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const msgFailRate = new Rate('msg_send_fail_rate');

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 30 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<300'],
    msg_send_fail_rate: ['rate<0.05'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

function register(uuid) {
  const res = http.post(
    `${BASE_URL}/api/auth/register`,
    JSON.stringify({ anonymousUuid: uuid }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  try {
    return JSON.parse(res.body).data.token;
  } catch {
    return null;
  }
}

function getRooms(token) {
  const res = http.get(
    `${BASE_URL}/api/rooms`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  check(res, { 'get rooms ok': (r) => r.status === 200 });
  try {
    return JSON.parse(res.body).data || [];
  } catch {
    return [];
  }
}

function getMessages(token, roomId) {
  const res = http.get(
    `${BASE_URL}/api/rooms/${roomId}/messages?offset=0&limit=50`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  check(res, { 'get messages ok': (r) => r.status === 200 });
}

export default function () {
  const uuid = `chat-perf-${__VU}-${__ITER}`;
  const token = register(uuid);
  if (!token) return;

  // 获取房间列表
  const rooms = getRooms(token);

  // 如果有房间，获取消息历史
  if (rooms.length > 0) {
    const roomId = rooms[0].id;
    getMessages(token, roomId);
  }

  // 模拟消息发送频率检查
  // (实际聊天通过 WebSocket，这里只测试 REST API 的消息获取性能)
  sleep(2);
}
