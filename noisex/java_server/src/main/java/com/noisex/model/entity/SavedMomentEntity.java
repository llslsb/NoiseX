package com.noisex.model.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(name = "saved_moment")
public class SavedMomentEntity {
    @Id
    @Column(length = 32)
    private String id;

    @Column(name = "room_id", nullable = false, length = 32)
    private String roomId;

    @Column(name = "user_id", nullable = false, length = 36)
    private String userId;

    @Column(name = "content", nullable = false, length = 500)
    private String content;

    @Column(name = "created_at", nullable = false)
    private long createdAt;
}
