package com.noisex.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.model.dto.ProfileRequest;
import com.noisex.model.dto.ProfileResponse;
import com.noisex.service.AdminService;
import com.noisex.service.AuthService;
import com.noisex.service.ProfileService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class ProfileControllerTest {

    @Mock private ProfileService profileService;
    @Mock private AuthService authService;
    @Mock private AdminService adminService;

    @InjectMocks private ProfileController profileController;

    @BeforeEach
    void setUp() {
        org.springframework.security.authentication.UsernamePasswordAuthenticationToken auth =
                new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                        "user-1", null, java.util.List.of());
        org.springframework.security.core.context.SecurityContextHolder.getContext()
                .setAuthentication(auth);
    }

    @Test
    void getProfile_shouldReturnProfile() {
        ProfileResponse profile = new ProfileResponse("sig", "city", "contact");
        when(profileService.getProfile("user-1")).thenReturn(profile);

        ResponseEntity<?> response = profileController.getProfile();

        assertEquals(200, response.getStatusCode().value());
        verify(profileService).getProfile("user-1");
    }

    @Test
    void updateProfile_shouldReturnUpdatedProfile() {
        ProfileRequest request = new ProfileRequest();
        request.setSignature("new-sig");
        request.setCity("new-city");
        request.setContact("new-contact");

        ProfileResponse updated = new ProfileResponse("new-sig", "new-city", "new-contact");
        when(profileService.updateProfile("user-1", request)).thenReturn(updated);

        ResponseEntity<?> response = profileController.updateProfile(request);

        assertEquals(200, response.getStatusCode().value());
        verify(profileService).updateProfile("user-1", request);
    }

    @Test
    void resetIdentity_shouldCallServiceAndBlacklistToken() {
        jakarta.servlet.http.HttpServletRequest httpRequest =
                mock(jakarta.servlet.http.HttpServletRequest.class);
        when(httpRequest.getHeader("Authorization")).thenReturn("Bearer jwt-token-123");

        ResponseEntity<?> response = profileController.resetIdentity(httpRequest);

        assertEquals(200, response.getStatusCode().value());
        verify(authService).resetIdentity("user-1");
        verify(adminService).blacklistToken("jwt-token-123");
    }

    @AfterEach
    void tearDown() {
        org.springframework.security.core.context.SecurityContextHolder.clearContext();
    }
}
