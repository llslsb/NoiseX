package com.noisex.exception;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class ErrorCodeTest {

    @Test
    void allErrorCodes_shouldHaveCorrectValues() {
        assertEquals(0, ErrorCode.SUCCESS.getCode());
        assertEquals(40001, ErrorCode.BAD_REQUEST.getCode());
        assertEquals(40101, ErrorCode.UNAUTHORIZED.getCode());
        assertEquals(40102, ErrorCode.TOKEN_EXPIRED.getCode());
        assertEquals(40301, ErrorCode.RATE_LIMIT.getCode());
        assertEquals(40401, ErrorCode.NOT_FOUND.getCode());
        assertEquals(40901, ErrorCode.SONAR_EXPIRED.getCode());
        assertEquals(40902, ErrorCode.ROOM_CLOSED.getCode());
        assertEquals(50001, ErrorCode.INTERNAL_ERROR.getCode());
    }

    @Test
    void allErrorCodes_shouldHaveMessages() {
        for (ErrorCode code : ErrorCode.values()) {
            assertNotNull(code.getMessage());
            assertFalse(code.getMessage().isEmpty());
        }
    }
}
