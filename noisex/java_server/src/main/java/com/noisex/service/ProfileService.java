package com.noisex.service;

import com.noisex.model.dto.ProfileRequest;
import com.noisex.model.dto.ProfileResponse;
import com.noisex.model.entity.SavedConnectionEntity;
import com.noisex.model.entity.UserProfileEntity;
import com.noisex.model.repository.SavedConnectionRepository;
import com.noisex.model.repository.UserProfileRepository;
import com.noisex.util.IdGenerator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProfileService {

    private final UserProfileRepository userProfileRepository;
    private final SavedConnectionRepository savedConnectionRepository;

    @Transactional(readOnly = true)
    public ProfileResponse getProfile(String userId) {
        return userProfileRepository
                .findById(userId)
                .map(
                        profile ->
                                new ProfileResponse(
                                        profile.getSignature(),
                                        profile.getCity(),
                                        profile.getContact()))
                .orElse(new ProfileResponse(null, null, null));
    }

    @Transactional
    public ProfileResponse updateProfile(String userId, ProfileRequest request) {
        UserProfileEntity profile =
                userProfileRepository
                        .findById(userId)
                        .orElse(UserProfileEntity.builder().userId(userId).build());

        if (request.getSignature() != null) {
            profile.setSignature(request.getSignature());
        }
        if (request.getCity() != null) {
            profile.setCity(request.getCity());
        }
        if (request.getContact() != null) {
            profile.setContact(request.getContact());
        }
        profile.setUpdatedAt(System.currentTimeMillis());

        userProfileRepository.save(profile);

        log.info("Profile updated: userId={}", userId);
        return new ProfileResponse(profile.getSignature(), profile.getCity(), profile.getContact());
    }

    @Transactional
    public void saveConnection(String roomId, String userIdA, String userIdB) {
        // 确保 user_id_a < user_id_b
        String a = userIdA.compareTo(userIdB) < 0 ? userIdA : userIdB;
        String b = userIdA.compareTo(userIdB) < 0 ? userIdB : userIdA;

        // 保存连接按房间实例隔离，同一对用户在不同房间可以分别保存。
        if (savedConnectionRepository.existsByRoomId(roomId)) {
            log.info("Connection already saved for room: {}", roomId);
            return;
        }

        SavedConnectionEntity connection =
                SavedConnectionEntity.builder()
                        .id(IdGenerator.nextId())
                        .roomId(roomId)
                        .userIdA(a)
                        .userIdB(b)
                        .createdAt(System.currentTimeMillis())
                        .build();

        savedConnectionRepository.save(connection);
        log.info("Connection saved: roomId={}, {} <-> {}", roomId, a, b);
    }
}
