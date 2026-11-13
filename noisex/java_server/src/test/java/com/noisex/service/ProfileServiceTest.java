package com.noisex.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

import com.noisex.model.dto.ProfileRequest;
import com.noisex.model.dto.ProfileResponse;
import com.noisex.model.entity.UserProfileEntity;
import com.noisex.model.repository.SavedConnectionRepository;
import com.noisex.model.repository.UserProfileRepository;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ProfileServiceTest {

    @Mock private UserProfileRepository userProfileRepository;

    @Mock private SavedConnectionRepository savedConnectionRepository;

    @InjectMocks private ProfileService profileService;

    @Test
    void getProfile_whenExists_shouldReturnProfile() {
        UserProfileEntity entity =
                UserProfileEntity.builder()
                        .userId("user-1")
                        .signature("sig")
                        .city("city")
                        .contact("contact")
                        .build();
        when(userProfileRepository.findById("user-1")).thenReturn(Optional.of(entity));

        ProfileResponse response = profileService.getProfile("user-1");

        assertEquals("sig", response.getSignature());
        assertEquals("city", response.getCity());
        assertEquals("contact", response.getContact());
    }

    @Test
    void getProfile_whenNotExists_shouldReturnEmpty() {
        when(userProfileRepository.findById("user-1")).thenReturn(Optional.empty());

        ProfileResponse response = profileService.getProfile("user-1");

        assertNull(response.getSignature());
        assertNull(response.getCity());
        assertNull(response.getContact());
    }

    @Test
    void updateProfile_whenExists_shouldUpdateFields() {
        UserProfileEntity entity =
                UserProfileEntity.builder().userId("user-1").signature("old").build();
        when(userProfileRepository.findById("user-1")).thenReturn(Optional.of(entity));
        when(userProfileRepository.save(any())).thenReturn(entity);

        ProfileRequest request = new ProfileRequest();
        request.setSignature("new-sig");
        request.setCity("new-city");
        request.setContact("new-contact");

        ProfileResponse response = profileService.updateProfile("user-1", request);

        assertEquals("new-sig", response.getSignature());
        assertEquals("new-city", response.getCity());
        assertEquals("new-contact", response.getContact());
        verify(userProfileRepository).save(entity);
    }

    @Test
    void updateProfile_whenNotExists_shouldCreateNew() {
        when(userProfileRepository.findById("user-1")).thenReturn(Optional.empty());
        when(userProfileRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        ProfileRequest request = new ProfileRequest();
        request.setSignature("sig");

        ProfileResponse response = profileService.updateProfile("user-1", request);

        assertEquals("sig", response.getSignature());
        verify(userProfileRepository).save(any());
    }

    @Test
    void saveConnection_shouldSaveWithOrderedIds() {
        when(savedConnectionRepository.existsByRoomId(anyString())).thenReturn(false);
        when(savedConnectionRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        // user-B < user-A alphabetically, should be swapped
        profileService.saveConnection("room-1", "user-B", "user-A");

        verify(savedConnectionRepository).existsByRoomId("room-1");
        verify(savedConnectionRepository)
                .save(
                        argThat(
                                connection ->
                                        "room-1".equals(connection.getRoomId())
                                                && "user-A".equals(connection.getUserIdA())
                                                && "user-B".equals(connection.getUserIdB())));
    }

    @Test
    void saveConnection_shouldAllowSameUsersInDifferentRooms() {
        when(savedConnectionRepository.existsByRoomId(anyString())).thenReturn(false);
        when(savedConnectionRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        profileService.saveConnection("room-1", "user-B", "user-A");
        profileService.saveConnection("room-2", "user-B", "user-A");

        verify(savedConnectionRepository).existsByRoomId("room-1");
        verify(savedConnectionRepository).existsByRoomId("room-2");
        verify(savedConnectionRepository, times(2)).save(any());
    }

    @Test
    void saveConnection_whenAlreadyExists_shouldNotSave() {
        when(savedConnectionRepository.existsByRoomId(anyString())).thenReturn(true);

        profileService.saveConnection("room-1", "user-A", "user-B");

        verify(savedConnectionRepository, never()).save(any());
    }
}
