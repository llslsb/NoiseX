package com.noisex.util;

import com.noisex.exception.BusinessException;
import com.noisex.exception.ErrorCode;
import java.util.concurrent.atomic.AtomicLong;

/** 雪花 ID 生成器 格式: 时间戳(42bit) + 机器ID(10bit) + 序列号(12bit) */
public class IdGenerator {

    private static final long EPOCH = 1700000000000L;
    private static final long MACHINE_ID;
    private static final long MAX_SEQUENCE = 0xFFF;
    private static final AtomicLong lastTimestamp = new AtomicLong(0);
    private static final AtomicLong sequence = new AtomicLong(0);

    static {
        long mid = 1L;
        String envMachineId = System.getenv("MACHINE_ID");
        if (envMachineId != null) {
            try {
                mid = Long.parseLong(envMachineId);
                if (mid < 0 || mid > 1023) {
                    mid = 1L;
                }
            } catch (NumberFormatException ignored) {
            }
        }
        MACHINE_ID = mid;
    }

    private IdGenerator() {}

    public static synchronized String nextId() {
        long timestamp = System.currentTimeMillis() - EPOCH;
        long lastTs = lastTimestamp.get();

        // 时钟回拨检测
        if (timestamp < lastTs) {
            throw new BusinessException(
                    ErrorCode.INTERNAL_ERROR,
                    "Clock moved backwards! Refusing to generate id for "
                            + (lastTs - timestamp)
                            + "ms");
        }

        long seq;
        if (timestamp == lastTs) {
            seq = sequence.incrementAndGet();
            if (seq > MAX_SEQUENCE) {
                // 序列溢出，等到下一毫秒
                timestamp = lastTs + 1;
                seq = 0;
                sequence.set(0);
            }
        } else {
            seq = 0;
            sequence.set(0);
        }

        lastTimestamp.set(timestamp);
        long id = (timestamp << 22) | (MACHINE_ID << 12) | seq;
        return String.valueOf(id);
    }

    public static String sonarId() {
        return "sonar-" + nextId();
    }

    public static String roomId() {
        return "room-" + nextId();
    }

    public static String msgId() {
        return "msg-" + nextId();
    }
}
