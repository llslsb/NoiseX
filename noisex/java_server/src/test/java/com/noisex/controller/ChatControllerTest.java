package com.noisex.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.model.dto.*;
import com.noisex.service.BlockService;
import com.noisex.service.ChatService;
import com.noisex.websocket.NoiseXWebSocketHandler;
import java.util.Collections;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class ChatControllerTest {

    @Mock private ChatService chatService;

    @Mock private BlockService blockService;

    @Mock private NoiseXWebSocketHandler webSocketHandler;

    @InjectMocks private ChatController chatController;

    @BeforeEach
    void setUp() {
        org.springframework.security.authentication.UsernamePasswordAuthenticationToken auth =
                new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                        "user-1", null, java.util.List.of());
        org.springframework.security.core.context.SecurityContextHolder.getContext()
                .setAuthentication(auth);
    }

    @Test
    void getRooms_shouldReturnRoomList() {
        when(chatService.getRooms("user-1")).thenReturn(Collections.emptyList());

        ResponseEntity<?> response = chatController.getRooms();

        assertEquals(200, response.getStatusCode().value());
        verify(chatService).getRooms("user-1");
    }

    @Test
    void getRoom_shouldReturnRoomDetail() {
        RoomResponse roomResponse =
                new RoomResponse(
                        "room-1",
                        "RX-1234",
                        "hello",
                        null,
                        System.currentTimeMillis() - 3600000L,
                        System.currentTimeMillis() + 7200000L,
                        false,
                        false,
                        false,
                        false,
                        false,
                        false,
                        0,
                        null,
                        null);
        when(chatService.getRoom("room-1", "user-1")).thenReturn(roomResponse);

        ResponseEntity<?> response = chatController.getRoom("room-1");

        assertEquals(200, response.getStatusCode().value());
        verify(chatService).getRoom("room-1", "user-1");
    }

    @Test
    void getMessages_shouldReturnMessages() {
        MessagesResponse msgsResponse = new MessagesResponse(Collections.emptyList(), false);
        when(chatService.getMessages("room-1", "user-1", 0, 50)).thenReturn(msgsResponse);

        ResponseEntity<?> response = chatController.getMessages("room-1", 0, 50);

        assertEquals(200, response.getStatusCode().value());
        verify(chatService).getMessages("room-1", "user-1", 0, 50);
    }

    @Test
    void saveConnection_whenDeclined_shouldValidateRoomMembershipBeforeNotify() {
        when(chatService.getRoom("room-1", "user-1"))
                .thenReturn(
                        new RoomResponse(
                                "room-1", "RX-1234", "hello", null, 1000L, 2000L, true, true, false,
                                false, false, false, 0, null, null));
        when(chatService.getOtherUserId("room-1", "user-1")).thenReturn("user-2");

        SaveConnectionRequest request = new SaveConnectionRequest();
        request.setAgree(false);
        ResponseEntity<ApiResponse<SaveConnectionResponse>> response =
                chatController.saveConnection("room-1", request);

        assertEquals(200, response.getStatusCode().value());
        verify(chatService).getRoom("room-1", "user-1");
        verify(chatService).getOtherUserId("room-1", "user-1");
    }

    @Test
    void saveConnection_whenDeclinedAndRoomInvalid_shouldNotNotify() {
        when(chatService.getRoom("room-1", "user-1"))
                .thenThrow(new com.noisex.exception.NotFoundException("房间不存在"));

        SaveConnectionRequest request = new SaveConnectionRequest();
        request.setAgree(false);

        assertThrows(
                com.noisex.exception.NotFoundException.class,
                () -> chatController.saveConnection("room-1", request));
        verify(chatService, never()).getOtherUserId(anyString(), anyString());
    }

    @Test
    void markAsRead_shouldReturnMessageId() {
        when(chatService.markAsRead("room-1", "user-1", "msg-1")).thenReturn("msg-1");

        ResponseEntity<?> response = chatController.markAsRead("room-1", "msg-1");

        assertEquals(200, response.getStatusCode().value());
        verify(chatService).markAsRead("room-1", "user-1", "msg-1");
    }

    @Test
    void blockUser_shouldCallBlockService() {
        when(chatService.getOtherUserId("room-1", "user-1")).thenReturn("user-2");

        ResponseEntity<?> response = chatController.blockUser("room-1");

        assertEquals(200, response.getStatusCode().value());
        verify(blockService).blockUser("user-1", "user-2");
    }

    @Test
    void blockUser_whenOtherUserNull_shouldThrowNotFound() {
        when(chatService.getOtherUserId("room-1", "user-1")).thenReturn(null);

        assertThrows(
                com.noisex.exception.NotFoundException.class,
                () -> chatController.blockUser("room-1"));
        verify(blockService, never()).blockUser(anyString(), anyString());
    }

    @AfterEach
    void tearDown() {
        org.springframework.security.core.context.SecurityContextHolder.clearContext();
    }
}
