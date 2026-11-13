package com.noisex.util;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.junit.jupiter.api.Test;

class IdGeneratorTest {

    @Test
    void nextId_shouldReturnNonEmptyString() {
        String id = IdGenerator.nextId();
        assertNotNull(id);
        assertFalse(id.isEmpty());
    }

    @Test
    void sonarId_shouldStartWithPrefix() {
        String id = IdGenerator.sonarId();
        assertTrue(id.startsWith("sonar-"));
    }

    @Test
    void roomId_shouldStartWithPrefix() {
        String id = IdGenerator.roomId();
        assertTrue(id.startsWith("room-"));
    }

    @Test
    void msgId_shouldStartWithPrefix() {
        String id = IdGenerator.msgId();
        assertTrue(id.startsWith("msg-"));
    }

    @Test
    void concurrentGeneration_shouldNotProduceDuplicates() throws InterruptedException {
        int count = 1000;
        Set<String> ids = ConcurrentHashMap.newKeySet();
        ExecutorService executor = Executors.newFixedThreadPool(10);
        CountDownLatch latch = new CountDownLatch(count);

        for (int i = 0; i < count; i++) {
            executor.submit(
                    () -> {
                        ids.add(IdGenerator.nextId());
                        latch.countDown();
                    });
        }

        latch.await();
        executor.shutdown();
        assertEquals(count, ids.size(), "All generated IDs should be unique");
    }
}
