package com.noisex.model.domain;

import java.io.Serializable;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ChatRoomData implements Serializable {
    private static final long serialVersionUID = 1L;

    private String id;
    private String sonarContent;
    private String signalCode;
    private String userIdA;
    private String userIdB;
    private long createdAt;
    private long expiresAt;
    private boolean unlocked;
    private boolean deepConnectionAchieved;
}
