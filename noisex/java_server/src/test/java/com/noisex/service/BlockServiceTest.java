package com.noisex.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.noisex.model.entity.UserBlockEntity;
import com.noisex.model.entity.UserBlockId;
import com.noisex.model.repository.UserBlockRepository;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;

@ExtendWith(MockitoExtension.class)
class BlockServiceTest {

    @Mock private UserBlockRepository blockRepository;

    @Mock private RedisTemplate<String, Object> redisTemplate;

    @Mock private SetOperations<String, Object> setOperations;

    @Mock private CompensationService compensationService;

    private BlockService blockService;

    @BeforeEach
    void setUp() {
        blockService = new BlockService(blockRepository, redisTemplate, compensationService);
        lenient().when(redisTemplate.opsForSet()).thenReturn(setOperations);
    }

    @Test
    void blockUser_notExists_shouldSaveAndCache() {
        when(blockRepository.existsById(any(UserBlockId.class))).thenReturn(false);
        when(blockRepository.save(any(UserBlockEntity.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        blockService.blockUser("user-A", "user-B");

        verify(blockRepository).save(any(UserBlockEntity.class));
        verify(setOperations).add(contains("block:"), eq("user-B"));
    }

    @Test
    void blockUser_alreadyExists_shouldNotSave() {
        when(blockRepository.existsById(any(UserBlockId.class))).thenReturn(true);

        blockService.blockUser("user-A", "user-B");

        verify(blockRepository, never()).save(any());
    }

    @Test
    void isBlocked_cachedInRedis_shouldReturnTrue() {
        when(setOperations.isMember(anyString(), eq("user-B"))).thenReturn(true);

        boolean result = blockService.isBlocked("user-A", "user-B");

        assertTrue(result);
        verify(blockRepository, never())
                .existsById_BlockerIdAndId_BlockedId(anyString(), anyString());
    }

    @Test
    void isBlocked_notCachedNotInDb_shouldReturnFalse() {
        when(setOperations.isMember(anyString(), eq("user-B"))).thenReturn(false);
        when(blockRepository.existsById_BlockerIdAndId_BlockedId("user-A", "user-B"))
                .thenReturn(false);

        boolean result = blockService.isBlocked("user-A", "user-B");

        assertFalse(result);
    }

    @Test
    void isBlocked_notCachedButInDb_shouldReturnTrueAndRefill() {
        when(setOperations.isMember(anyString(), eq("user-B"))).thenReturn(false);
        when(blockRepository.existsById_BlockerIdAndId_BlockedId("user-A", "user-B"))
                .thenReturn(true);

        boolean result = blockService.isBlocked("user-A", "user-B");

        assertTrue(result);
        verify(setOperations).add(contains("block:"), eq("user-B"));
    }

    @Test
    void getBlockedList_cachedInRedis_shouldReturnFromCache() {
        when(setOperations.members(anyString())).thenReturn(Set.of("user-B", "user-C"));

        Set<String> result = blockService.getBlockedList("user-A");

        assertEquals(2, result.size());
        assertTrue(result.contains("user-B"));
        assertTrue(result.contains("user-C"));
        verify(blockRepository, never()).findById_BlockerId(anyString());
    }

    @Test
    void getBlockedList_notCached_shouldQueryDb() {
        when(setOperations.members(anyString())).thenReturn(Collections.emptySet());

        UserBlockEntity entity1 = new UserBlockEntity(new UserBlockId("user-A", "user-B"), 1000L);
        UserBlockEntity entity2 = new UserBlockEntity(new UserBlockId("user-A", "user-C"), 2000L);
        when(blockRepository.findById_BlockerId("user-A")).thenReturn(List.of(entity1, entity2));

        Set<String> result = blockService.getBlockedList("user-A");

        assertEquals(2, result.size());
        assertTrue(result.contains("user-B"));
        assertTrue(result.contains("user-C"));
    }

    @Test
    void unblockUser_existsInDb_shouldDeleteAndClearCache() {
        when(blockRepository.existsById(any(UserBlockId.class))).thenReturn(true);

        blockService.unblockUser("user-A", "user-B");

        verify(blockRepository).deleteById(any(UserBlockId.class));
        verify(setOperations).remove(contains("block:"), eq("user-B"));
    }

    @Test
    void unblockUser_notExists_shouldDoNothing() {
        when(blockRepository.existsById(any(UserBlockId.class))).thenReturn(false);

        blockService.unblockUser("user-A", "user-B");

        verify(blockRepository, never()).deleteById(any());
        verify(setOperations, never()).remove(anyString(), any());
    }
}
