package com.noisex.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.noisex.exception.BusinessException;
import com.noisex.exception.NotFoundException;
import com.noisex.model.dto.RoomResponse;
import com.noisex.websocket.NoiseXWebSocketHandler;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.data.redis.connection.stream.RecordId;
import org.springframework.data.redis.core.HashOperations;
import org.springframework.data.redis.core.RedisCallback;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StreamOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.data.redis.core.ZSetOperations;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class ChatServiceTest {

    @Mock private RedisTemplate<String, Object> redisTemplate;

    @Mock private StringRedisTemplate stringRedisTemplate;

    @Mock private NoiseXWebSocketHandler webSocketHandler;

    @Mock private ProfileService profileService;

    @Mock private HashOperations<String, Object, Object> hashOperations;

    @Mock private SetOperations<String, Object> setOperations;

    @Mock private SetOperations<String, String> stringSetOperations;

    @Mock private com.noisex.service.PushService pushService;

    @Mock private ValueOperations<String, Object> valueOperations;

    @Mock private StreamOperations<String, Object, Object> streamOperations;

    @Mock private ZSetOperations<String, Object> zSetOperations;

    @Mock private CompensationService compensationService;

    @Mock private com.noisex.service.BlockService blockService;

    private ChatService chatService;

    @BeforeEach
    void setUp() {
        MeterRegistry registry = new SimpleMeterRegistry();
        Counter roomCreatedCounter =
                Counter.builder("noisex.room.created.total").register(registry);
        Counter messageSentCounter =
                Counter.builder("noisex.chat.message.sent.total").register(registry);

        chatService =
                new ChatService(
                        redisTemplate,
                        stringRedisTemplate,
                        webSocketHandler,
                        profileService,
                        pushService,
                        compensationService,
                        blockService,
                        roomCreatedCounter,
                        messageSentCounter);

        ReflectionTestUtils.setField(chatService, "roomLifetimeHours", 72);
        ReflectionTestUtils.setField(chatService, "unlockWindowHours", 24);
        ReflectionTestUtils.setField(chatService, "unlockThresholdMessages", 10);
        ReflectionTestUtils.setField(chatService, "unlockMinMessageLength", 5);
        ReflectionTestUtils.setField(chatService, "maxMessageLength", 500);
        ReflectionTestUtils.setField(chatService, "msgRateSeconds", 2);
        ReflectionTestUtils.setField(chatService, "duplicateWindowSeconds", 30);
        lenient().when(redisTemplate.opsForHash()).thenReturn(hashOperations);
        lenient().when(redisTemplate.opsForSet()).thenReturn(setOperations);
        lenient().when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        lenient().when(redisTemplate.opsForStream()).thenReturn(streamOperations);
        lenient().when(redisTemplate.opsForZSet()).thenReturn(zSetOperations);
    }

    @Test
    void getRoom_roomNotFound_shouldThrow() {
        when(hashOperations.entries(anyString())).thenReturn(Collections.emptyMap());

        assertThrows(NotFoundException.class, () -> chatService.getRoom("room-nonexist", "user-1"));
    }

    @Test
    void getRoom_userNotInRoom_shouldThrow() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        assertThrows(BusinessException.class, () -> chatService.getRoom("room-1", "user-stranger"));
    }

    @Test
    void getRoom_shouldReturnBothOwnAndPeerReadPointers() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(hashOperations.get(contains("room:read:"), eq("user-A"))).thenReturn("msg-own-read");
        when(hashOperations.get(contains("room:read:"), eq("user-B"))).thenReturn("msg-peer-read");
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);

        RoomResponse room = chatService.getRoom("room-1", "user-A");

        assertEquals("msg-own-read", room.getLastReadMessageId());
        assertEquals("msg-peer-read", room.getPeerReadMessageId());
    }

    @Test
    void getRoom_shouldAllowMissingPeerReadPointer() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(hashOperations.get(contains("room:read:"), eq("user-A"))).thenReturn("msg-own-read");
        when(hashOperations.get(contains("room:read:"), eq("user-B"))).thenReturn(null);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);

        RoomResponse room = chatService.getRoom("room-1", "user-A");

        assertEquals("msg-own-read", room.getLastReadMessageId());
        assertNull(room.getPeerReadMessageId());
    }

    @Test
    void unlockProfile_shouldStoreDeepConfirmWithStringRedisTemplate() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "true");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);
        when(stringSetOperations.members(contains("room:deep:"))).thenReturn(Set.of("user-A"));

        chatService.unlockProfile("room-1", "user-A");

        verify(stringSetOperations).add(contains("room:deep:"), eq("user-A"));
    }

    @Test
    void unlockProfile_shouldReturnOtherUserProfileWhenBothConfirmed() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "true");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);
        when(stringSetOperations.size(contains("room:deep:"))).thenReturn(2L);

        chatService.unlockProfile("room-1", "user-A");

        verify(profileService).getProfile("user-B");
    }

    @Test
    void getRoom_shouldReturnOwnAndBothDeepConfirmState() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "true");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);
        when(stringSetOperations.isMember(contains("room:deep:"), eq("user-A"))).thenReturn(true);
        when(stringSetOperations.size(contains("room:deep:"))).thenReturn(2L);

        RoomResponse room = chatService.getRoom("room-1", "user-A");

        assertTrue(room.isDeepConnectionConfirmed());
        assertTrue(room.isBothDeepConfirmed());
    }

    @Test
    void getRooms_noRooms_shouldReturnEmpty() {
        when(setOperations.members(anyString())).thenReturn(Collections.emptySet());

        List<RoomResponse> rooms = chatService.getRooms("user-1");

        assertTrue(rooms.isEmpty());
    }

    /** D-M9-1 根治（2026-11-05）：我拉黑了对方 → 相关房间从我的列表消失（服务端权威过滤， 不依赖客户端会话级兜底）。未拉黑对象的房间正常返回。 */
    @Test
    void getRooms_shouldFilterOutRoomsWhereUserBlockedPeer() {
        when(setOperations.members(anyString())).thenReturn(Set.of("room-1", "room-2"));
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);
        when(redisTemplate.executePipelined(any(RedisCallback.class)))
                .thenReturn(
                        List.of(
                                blockedPeerRoomMap("room-1", "user-B"),
                                blockedPeerRoomMap("room-2", "user-C")));
        when(blockService.getBlockedList("user-1")).thenReturn(Set.of("user-B"));

        List<RoomResponse> rooms = chatService.getRooms("user-1");

        assertEquals(1, rooms.size());
        assertEquals("room-2", rooms.get(0).getId());
    }

    /** D-M9-1 防过滤误伤：拉黑名单为空时全部房间可见，行为与过滤前一致。 */
    @Test
    void getRooms_shouldKeepAllRoomsWhenNothingBlocked() {
        when(setOperations.members(anyString())).thenReturn(Set.of("room-1", "room-2"));
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);
        when(redisTemplate.executePipelined(any(RedisCallback.class)))
                .thenReturn(
                        List.of(
                                blockedPeerRoomMap("room-1", "user-B"),
                                blockedPeerRoomMap("room-2", "user-C")));
        when(blockService.getBlockedList("user-1")).thenReturn(Collections.emptySet());

        List<RoomResponse> rooms = chatService.getRooms("user-1");

        assertEquals(2, rooms.size());
    }

    /** 构造 getRooms 单测用的房间哈希图（pipeline 返回形态）。 */
    private Map<Object, Object> blockedPeerRoomMap(String roomId, String peerUserId) {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", roomId);
        roomData.put("userIdA", "user-1");
        roomData.put("userIdB", peerUserId);
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", String.valueOf(System.currentTimeMillis() + 3600000));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        return roomData;
    }

    @Test
    void leaveRoom_roomNotFound_shouldThrow() {
        when(hashOperations.entries(anyString())).thenReturn(Collections.emptyMap());

        assertThrows(
                NotFoundException.class, () -> chatService.leaveRoom("room-nonexist", "user-1"));
    }

    /**
     * F2-2：用户主动 leaveRoom 时，必须向对方发送 peer_left（携带 signalCode），而不是 room_expired。room_expired 仅用于 TTL
     * 到期。
     *
     * <p>对应计划 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F2-2。
     */
    @Test
    void leaveRoom_shouldNotifyPeerLeftWithSignalCode() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", String.valueOf(System.currentTimeMillis() + 3600000));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        chatService.leaveRoom("room-1", "user-A");

        verify(webSocketHandler).notifyPeerLeft("user-B", "room-1", "RX-1234");
    }

    /** F2-2：leaveRoom 不应再调用 notifyRoomExpired（语义只属于 TTL 自然过期）。 */
    @Test
    void leaveRoom_shouldNotCallNotifyRoomExpired() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", String.valueOf(System.currentTimeMillis() + 3600000));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        chatService.leaveRoom("room-1", "user-A");

        verify(webSocketHandler, never()).notifyRoomExpired(anyString(), anyString());
    }

    /** F2-2：用户 B 主动离开时应通知 user-A。 */
    @Test
    void leaveRoom_byUserB_shouldNotifyUserA() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", String.valueOf(System.currentTimeMillis() + 3600000));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        chatService.leaveRoom("room-1", "user-B");

        verify(webSocketHandler).notifyPeerLeft("user-A", "room-1", "RX-1234");
    }

    @Test
    void getOtherUserId_roomNotFound_shouldReturnNull() {
        when(hashOperations.entries(anyString())).thenReturn(Collections.emptyMap());

        String result = chatService.getOtherUserId("room-nonexist", "user-1");

        assertNull(result);
    }

    @Test
    void getRoomSignalCode_roomNotFound_shouldReturnNull() {
        when(hashOperations.entries(anyString())).thenReturn(Collections.emptyMap());

        String result = chatService.getRoomSignalCode("room-nonexist");

        assertNull(result);
    }

    @Test
    void sendMessage_messageTooLong_shouldThrow() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", String.valueOf(System.currentTimeMillis() + 3600000));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        // 构建超长消息
        String longMsg = "a".repeat(501);

        assertThrows(
                BusinessException.class,
                () -> chatService.sendMessage("room-1", "user-A", longMsg));
    }

    @Test
    void sendMessage_rateLimited_shouldThrow() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", String.valueOf(System.currentTimeMillis() + 3600000));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        org.springframework.data.redis.core.script.DefaultRedisScript<Long> rateScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_RATE_LIMIT_SCRIPT");
        lenient()
                .when(stringRedisTemplate.execute(eq(rateScript), anyList(), any()))
                .thenReturn(2L);

        assertThrows(
                BusinessException.class,
                () -> chatService.sendMessage("room-1", "user-A", "Hello"));
    }

    @Test
    void sendMessage_duplicateContent_shouldThrow() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", String.valueOf(System.currentTimeMillis() + 3600000));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        org.springframework.data.redis.core.script.DefaultRedisScript<Long> rateScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_RATE_LIMIT_SCRIPT");
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> dupScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_DUPLICATE_SCRIPT");
        lenient()
                .when(stringRedisTemplate.execute(eq(rateScript), anyList(), any()))
                .thenReturn(1L);
        lenient()
                .when(stringRedisTemplate.execute(eq(dupScript), anyList(), any(), any()))
                .thenReturn(1L);

        assertThrows(
                BusinessException.class,
                () -> chatService.sendMessage("room-1", "user-A", "Hello"));
    }

    @Test
    void sendMessage_shouldReturnPersistedStreamMessageId() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", String.valueOf(System.currentTimeMillis() + 3600000));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> rateScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_RATE_LIMIT_SCRIPT");
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> dupScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_DUPLICATE_SCRIPT");
        lenient()
                .when(stringRedisTemplate.execute(eq(rateScript), anyList(), any()))
                .thenReturn(1L);
        lenient()
                .when(stringRedisTemplate.execute(eq(dupScript), anyList(), any(), any()))
                .thenReturn(0L);
        when(streamOperations.add(anyString(), anyMap())).thenReturn(RecordId.of("msg-redis-1"));

        String messageId = chatService.sendMessage("room-1", "user-A", "Hello there");

        assertEquals("msg-redis-1", messageId);
    }

    @Test
    void markAsRead_shouldUpdateRedis() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        String result = chatService.markAsRead("room-1", "user-A", "msg-1");

        assertEquals("msg-1", result);
        verify(hashOperations).put(contains("room:read:"), eq("user-A"), eq("msg-1"));
    }

    @Test
    void getReadPointer_noPointer_shouldReturnNull() {
        when(hashOperations.get(anyString(), eq("user-A"))).thenReturn(null);

        String result = chatService.getReadPointer("room-1", "user-A");

        assertNull(result);
    }

    @Test
    void getReadPointer_hasPointer_shouldReturnIt() {
        when(hashOperations.get(anyString(), eq("user-A"))).thenReturn("msg-5");

        String result = chatService.getReadPointer("room-1", "user-A");

        assertEquals("msg-5", result);
    }

    @Test
    void sendMessage_shouldCallPushServiceForOfflineUser() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", String.valueOf(System.currentTimeMillis() + 3600000));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> rateScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_RATE_LIMIT_SCRIPT");
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> dupScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_DUPLICATE_SCRIPT");
        lenient()
                .when(stringRedisTemplate.execute(eq(rateScript), anyList(), any()))
                .thenReturn(1L);
        lenient()
                .when(stringRedisTemplate.execute(eq(dupScript), anyList(), any(), any()))
                .thenReturn(0L);
        when(streamOperations.add(anyString(), anyMap()))
                .thenReturn(RecordId.of("1700000000000-0"));

        chatService.sendMessage("room-1", "user-A", "Hello there");

        // 验证对 user-B (接收方) 调用了推送
        // 2026-11-05 推送脱敏：body 为固定文案，绝不携带 E2EE 密文（用户抓到通知栏显示乱码）
        verify(pushService).sendPush(eq("user-B"), eq("新消息"), eq("收到一条新消息，点击查看"), anyMap());
    }

    @Test
    void getRoom_shouldReturnCreatedAtInResponse() {
        long createdAt = System.currentTimeMillis() - 1800000L;
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", String.valueOf(createdAt));
        roomData.put("expiresAt", String.valueOf(createdAt + 72 * 3600 * 1000L));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);

        RoomResponse room = chatService.getRoom("room-1", "user-A");

        assertEquals(createdAt, room.getCreatedAt());
    }

    @Test
    void checkDeepConnection_withinWindow_shouldAchieveDeepConnection() {
        // 房间创建于 1 小时前，在 24h 窗口内
        long createdAt = System.currentTimeMillis() - 3600000L;
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", String.valueOf(createdAt));
        roomData.put("expiresAt", String.valueOf(createdAt + 72 * 3600 * 1000L));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        // 模拟满足深度交流的消息计数
        when(hashOperations.get(contains("msgcount:"), eq("user-A"))).thenReturn(6);
        when(hashOperations.get(contains("msgcount:"), eq("user-B"))).thenReturn(6);

        org.springframework.data.redis.core.script.DefaultRedisScript<Long> rateScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_RATE_LIMIT_SCRIPT");
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> dupScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_DUPLICATE_SCRIPT");
        lenient()
                .when(stringRedisTemplate.execute(eq(rateScript), anyList(), any()))
                .thenReturn(1L);
        lenient()
                .when(stringRedisTemplate.execute(eq(dupScript), anyList(), any(), any()))
                .thenReturn(0L);
        when(streamOperations.add(anyString(), anyMap()))
                .thenReturn(RecordId.of("1700000000000-0"));

        chatService.sendMessage("room-1", "user-A", "Hello there");

        // 窗口内应标记深度交流达成
        verify(hashOperations).put(contains("room:"), eq("deepConnectionAchieved"), eq("true"));
    }

    @Test
    void saveConnection_otherAlreadySaved_shouldNotSendSaveRequest() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "true");
        roomData.put("deepConnectionAchieved", "true");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);
        // 对方 (user-B) 已经在确认集合中
        when(stringSetOperations.isMember(contains("room:save:"), eq("user-B"))).thenReturn(true);
        when(stringSetOperations.size(contains("room:save:"))).thenReturn(2L);
        when(setOperations.members(contains("room:save:"))).thenReturn(Set.of("user-A", "user-B"));

        chatService.saveConnection("room-1", "user-A");

        // 不应向对方发送 save_request（避免弹窗循环）
        verify(webSocketHandler, never()).notifySaveRequest(eq("user-B"), anyString(), anyString());
        // 双方都同意，应通知保存确认
        verify(webSocketHandler).notifySaveConfirmed(eq("user-A"), eq("room-1"));
        verify(webSocketHandler).notifySaveConfirmed(eq("user-B"), eq("room-1"));
    }

    @Test
    void saveConnection_alreadySavedBySelf_shouldReturnWaitingWithoutNotifying() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "true");
        roomData.put("deepConnectionAchieved", "true");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);
        when(stringSetOperations.isMember(contains("room:save:"), eq("user-A"))).thenReturn(true);
        when(setOperations.members(contains("room:save:"))).thenReturn(Set.of("user-A"));

        var response = chatService.saveConnection("room-1", "user-A");

        assertEquals("waiting", response.getStatus());
        verify(webSocketHandler, never()).notifySaveRequest(anyString(), anyString(), anyString());
        verify(webSocketHandler, never()).notifySaveConfirmed(anyString(), anyString());
    }

    @Test
    void saveConnection_alreadySavedBySelfAndBothConfirmed_shouldResendConfirmedToBoth() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "true");
        roomData.put("deepConnectionAchieved", "true");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);
        when(stringSetOperations.isMember(contains("room:save:"), eq("user-A"))).thenReturn(true);
        when(setOperations.members(contains("room:save:"))).thenReturn(Set.of("user-A", "user-B"));

        var response = chatService.saveConnection("room-1", "user-A");

        assertEquals("confirmed", response.getStatus());
        verify(webSocketHandler, never()).notifySaveRequest(anyString(), anyString(), anyString());
        // D4（a401001，2026-11-03）：重复同意且双方已齐时补发 save_confirmed 给双方，
        // 让错过的端（弹窗打断/重连丢帧）立即对齐"双方已保存"状态，不必等列表刷新
        verify(webSocketHandler).notifySaveConfirmed(eq("user-A"), eq("room-1"));
        verify(webSocketHandler).notifySaveConfirmed(eq("user-B"), eq("room-1"));
    }

    @Test
    void saveConnection_otherNotYetSaved_shouldSendSaveRequest() {
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", "1000");
        roomData.put("expiresAt", "2000");
        roomData.put("unlocked", "true");
        roomData.put("deepConnectionAchieved", "true");
        when(hashOperations.entries(anyString())).thenReturn(roomData);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOperations);
        // 对方 (user-B) 还未同意
        when(stringSetOperations.isMember(contains("room:save:"), eq("user-B"))).thenReturn(false);
        when(stringSetOperations.size(contains("room:save:"))).thenReturn(1L);

        chatService.saveConnection("room-1", "user-A");

        // 应向对方发送 save_request
        verify(webSocketHandler).notifySaveRequest(eq("user-B"), eq("room-1"), eq("RX-1234"));
    }

    @Test
    void checkDeepConnection_outsideWindow_shouldNotAchieveDeepConnection() {
        // 房间创建于 25 小时前，超过 24h 解锁窗口
        long createdAt = System.currentTimeMillis() - 25 * 3600 * 1000L;
        Map<Object, Object> roomData = new HashMap<>();
        roomData.put("id", "room-1");
        roomData.put("userIdA", "user-A");
        roomData.put("userIdB", "user-B");
        roomData.put("signalCode", "RX-1234");
        roomData.put("sonarContent", "Hello");
        roomData.put("createdAt", String.valueOf(createdAt));
        roomData.put("expiresAt", String.valueOf(createdAt + 72 * 3600 * 1000L));
        roomData.put("unlocked", "false");
        roomData.put("deepConnectionAchieved", "false");
        when(hashOperations.entries(anyString())).thenReturn(roomData);

        // 模拟满足深度交流的消息计数
        when(hashOperations.get(contains("msgcount:"), eq("user-A"))).thenReturn(6);
        when(hashOperations.get(contains("msgcount:"), eq("user-B"))).thenReturn(6);

        org.springframework.data.redis.core.script.DefaultRedisScript<Long> rateScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_RATE_LIMIT_SCRIPT");
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> dupScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(ChatService.class, "MSG_DUPLICATE_SCRIPT");
        lenient()
                .when(stringRedisTemplate.execute(eq(rateScript), anyList(), any()))
                .thenReturn(1L);
        lenient()
                .when(stringRedisTemplate.execute(eq(dupScript), anyList(), any(), any()))
                .thenReturn(0L);
        when(streamOperations.add(anyString(), anyMap()))
                .thenReturn(RecordId.of("1700000000000-0"));

        chatService.sendMessage("room-1", "user-A", "Hello there");

        // 窗口外不应标记深度交流达成
        verify(hashOperations, never()).put(anyString(), eq("deepConnectionAchieved"), eq("true"));
    }
}
