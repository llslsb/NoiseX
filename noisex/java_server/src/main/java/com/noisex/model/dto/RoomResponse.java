package com.noisex.model.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
public class RoomResponse {
    private String id;
    private String signalCode;
    private String sonarContent;
    private MessageResponse lastMessage;
    private long createdAt;
    private long expiresAt;
    private boolean unlocked;
    private boolean deepConnectionAchieved;
    private boolean deepConnectionConfirmed;
    private boolean bothDeepConfirmed;
    private boolean saveConnectionConfirmed;
    private boolean bothSaveConfirmed;
    private int messageCount;
    private String lastReadMessageId;
    private String peerReadMessageId;
}
