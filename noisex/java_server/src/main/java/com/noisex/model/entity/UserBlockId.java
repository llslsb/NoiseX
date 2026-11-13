package com.noisex.model.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import java.io.Serializable;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Embeddable
public class UserBlockId implements Serializable {

    @Column(name = "blocker_id", nullable = false, length = 36)
    private String blockerId;

    @Column(name = "blocked_id", nullable = false, length = 36)
    private String blockedId;
}
