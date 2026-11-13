package com.noisex.util;

import static org.junit.jupiter.api.Assertions.*;

import com.noisex.exception.BusinessException;
import org.junit.jupiter.api.Test;

class SecurityUtilsTest {

    @Test
    void getCurrentUserId_noAuth_shouldThrowUnauthorized() {
        assertThrows(BusinessException.class, SecurityUtils::getCurrentUserId);
    }
}
