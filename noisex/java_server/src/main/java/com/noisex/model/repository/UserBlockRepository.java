package com.noisex.model.repository;

import com.noisex.model.entity.UserBlockEntity;
import com.noisex.model.entity.UserBlockId;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface UserBlockRepository extends JpaRepository<UserBlockEntity, UserBlockId> {

    List<UserBlockEntity> findById_BlockerId(String blockerId);

    boolean existsById_BlockerIdAndId_BlockedId(String blockerId, String blockedId);

    @Modifying
    @Query(
            "DELETE FROM UserBlockEntity u WHERE u.id.blockerId = :userId OR u.id.blockedId = :userId")
    void deleteByUserId(@Param("userId") String userId);
}
