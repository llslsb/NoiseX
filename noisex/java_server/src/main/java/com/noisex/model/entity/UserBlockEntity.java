package com.noisex.model.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(name = "user_block")
public class UserBlockEntity {

    @EmbeddedId private UserBlockId id;

    @Column(name = "created_at", nullable = false)
    private long createdAt;
}
