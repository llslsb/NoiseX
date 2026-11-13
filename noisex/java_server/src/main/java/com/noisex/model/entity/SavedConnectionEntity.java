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
@Table(name = "saved_connection")
public class SavedConnectionEntity {
    @Id
    @Column(length = 32)
    private String id;

    @Column(name = "user_id_a", nullable = false, length = 36)
    private String userIdA;

    @Column(name = "user_id_b", nullable = false, length = 36)
    private String userIdB;

    @Column(name = "room_id", nullable = false, length = 32)
    private String roomId;

    @Column(name = "created_at", nullable = false)
    private long createdAt;
}
