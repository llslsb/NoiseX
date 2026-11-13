package com.noisex.service;

import com.noisex.model.dto.SaveMomentRequest;
import com.noisex.model.dto.SavedMomentResponse;
import com.noisex.model.entity.SavedMomentEntity;
import com.noisex.model.repository.SavedMomentRepository;
import com.noisex.util.IdGenerator;
import java.util.List;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class SavedMomentService {

    private final SavedMomentRepository savedMomentRepository;

    /** 保存临终片段 每个用户在每个房间只能保存一次 */
    public SavedMomentResponse saveMoment(String userId, SaveMomentRequest request) {
        if (savedMomentRepository.existsByUserIdAndRoomId(userId, request.getRoomId())) {
            throw new IllegalArgumentException("该房间已保存过片段");
        }

        SavedMomentEntity moment =
                SavedMomentEntity.builder()
                        .id(IdGenerator.nextId())
                        .roomId(request.getRoomId())
                        .userId(userId)
                        .content(request.getContent())
                        .createdAt(System.currentTimeMillis())
                        .build();

        savedMomentRepository.save(moment);
        log.info(
                "Saved moment: id={}, user={}, room={}",
                moment.getId(),
                userId,
                request.getRoomId());

        return toResponse(moment);
    }

    /** 获取用户保存的所有片段 */
    public List<SavedMomentResponse> getUserMoments(String userId) {
        return savedMomentRepository.findByUserIdOrderByCreatedAtDesc(userId).stream()
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    private SavedMomentResponse toResponse(SavedMomentEntity entity) {
        return SavedMomentResponse.builder()
                .id(entity.getId())
                .roomId(entity.getRoomId())
                .content(entity.getContent())
                .createdAt(entity.getCreatedAt())
                .build();
    }
}
